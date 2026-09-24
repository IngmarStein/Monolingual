//
//  HelperTask.swift
//  Monolingual
//
//  Created by Ingmar Stein on 30.12.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import Foundation
import AppKit
import UserNotifications
import OSLog
import XPC
#if canImport(HelperShared)
import HelperShared
#endif

import Observation

@MainActor @Observable class HelperTask {
	/// How a removal ended, for the alert that reports it.
	enum Outcome {
		case completed
		case cancelled
	}

	/// What a run removes. The progress messages are worded for it: a removal of languages
	/// names the language a file belongs to, stripping architectures does not.
	enum Removal {
		case languages([LanguageSetting])
		case architectures
	}

	/// The session to the privileged helper.
	private var session: XPCSession?
	/// The listener the helper reports progress and the result on.
	private var progressListener: XPCListener?
	private var progressResetTimer: Timer?
	private let logger = Logger()
	private let installer = HelperInstaller()
	/// Asking for permission to notify is a prompt, so it is left for the first notification.
	private var askedForNotificationPermission = false
	var text = ""
	var file = ""
	var byteCount: Int64 = 0
	var isRunning = false
	/// Set once a removal is over, and cleared when the user acknowledges the alert it brings up.
	var outcome: Outcome?

	/// Set when the privileged helper is unavailable, for instance because it still has to be
	/// allowed in System Settings.
	var installationFailure: HelperInstallationFailure?

	/// What the running removal is removing.
	private var removal: Removal = .languages([])

	/// Starts a removal. `removal` says what it covers, which is what its progress messages are
	/// worded for.
	func checkAndRunHelper(arguments: HelperRequest, removal: Removal) {
		self.removal = removal

		// Anything the previous removal reported is acknowledged by now, and a leftover
		// outcome would present its alert again over this run.
		outcome = nil

		Task {
			do {
				try await installer.installIfNeeded()
			} catch let failure as HelperInstallationFailure {
				logger.error("Helper is unavailable: \(failure.message, privacy: .public)")
				installationFailure = failure
				return
			} catch {
				logger.error("Helper is unavailable: \(error.localizedDescription, privacy: .public)")
				installationFailure = .registrationFailed(error)
				return
			}

			await runHelper(arguments: arguments)
		}
	}

	// MARK: - Talking to the helper

	/// Sends a message and waits for the helper's reply, or returns nil if it does not answer.
	private func request(_ message: HelperMessage) async -> HelperReply? {
		guard let session else {
			return nil
		}

		do {
			let reply: HelperReply = try await withCheckedThrowingContinuation { continuation in
				do {
					try session.send(message: HelperWire.dictionary(for: message)) { result in
						switch result {
						case let .success(dictionary):
							continuation.resume(with: Result { try HelperWire.message(HelperReply.self, in: dictionary) })
						case let .failure(error):
							continuation.resume(throwing: error)
						}
					}
				} catch {
					continuation.resume(throwing: error)
				}
			}
			return reply
		} catch {
			logger.error("The helper did not answer: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// Sends a message the helper does not answer.
	private func send(_ message: HelperMessage) {
		guard let session else {
			return
		}

		do {
			try session.send(message: HelperWire.dictionary(for: message))
		} catch {
			logger.error("Could not send a message to the helper: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Opens the connection to the helper, which XPC only accepts from the helper this app
	/// ships with.
	private func connectToHelper() -> Bool {
		// Anything left over from an earlier attempt is closed first: XPC crashes when an
		// active session is released without being cancelled.
		closeConnection()

		do {
			// The requirement is settled before the session is activated — XPC only accepts it
			// on a session that is not active yet — so there is no `activate()` to call here.
			session = try XPCSession(machService: HelperService.machServiceName,
			                         options: .privileged,
			                         requirement: HelperService.helperPeerRequirement,
			                         cancellationHandler: { [weak self] error in
				Task { @MainActor in
					self?.connectionDidEnd(error)
				}
			})

			return true
		} catch {
			logger.error("Could not connect to the helper: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}

	/// Opens the listener the helper reports progress and the result on.
	private func openProgressListener() -> XPCListener {
		// An anonymous listener listens as soon as it is created, and releasing one is safe;
		// there is no `activate()` to call, and calling one would be a misuse crash.
		XPCListener { [weak self] request in
			request.accept { (dictionary: XPCDictionary) -> XPCDictionary? in
				guard let reply = try? HelperWire.message(HelperReply.self, in: dictionary) else {
					return nil
				}
				Task { @MainActor in
					self?.receive(reply)
				}
				return nil
			}
		}
	}

	/// Closes both connections. Clearing the session first keeps the cancellation handler from
	/// reporting a connection we closed ourselves.
	private func closeConnection() {
		let session = self.session
		self.session = nil
		progressListener?.cancel()
		progressListener = nil
		session?.cancel(reason: "finished")
	}

	/// The session to the helper ended. A helper that has finished a removal exits, and that is
	/// what ends the session, so this is how every run ends; only a connection that goes away
	/// while a removal is running is a failure.
	private func connectionDidEnd(_ error: XPCRichError) {
		guard session != nil else {
			return
		}
		session = nil

		guard isRunning else {
			logger.debug("The helper exited: \(String(describing: error), privacy: .public)")
			return
		}

		logger.error("Lost the connection to the helper: \(String(describing: error), privacy: .public)")
		// It went away mid-removal, so there is no result left to wait for.
		installationFailure = .helperUnreachable
		progressDidEnd(outcome: nil)
	}

	// MARK: - Running a request

	private func runHelper(arguments: HelperRequest) async {
		guard connectToHelper() else {
			installationFailure = .helperUnreachable
			return
		}

		// A helper that never answers would otherwise leave the app doing nothing at all.
		let timeout = Task { @MainActor in
			try? await Task.sleep(for: .seconds(10))
			guard !Task.isCancelled, !self.isRunning else { return }
			self.logger.error("Helper did not answer within 10 seconds")
			self.installationFailure = .helperUnreachable
			// Cancelling lets the request that is still waiting give up, rather than hanging
			// on a helper that never answers.
			self.closeConnection()
		}
		defer { timeout.cancel() }

		let reply = await request(.version)

		// The helper lives inside the app bundle and therefore reports the version of the
		// app. Anything else means a helper installed by an older version of Monolingual
		// is still answering on the Mach service.
		guard case let .version(helperVersion)? = reply else {
			installationFailure = .helperUnreachable
			return
		}
		guard helperVersion == HelperInstaller.appVersion else {
			logger.error("Unexpected helper version: \(helperVersion, privacy: .public)")
			installationFailure = .outdatedHelper(helperVersion)
			return
		}

		await performRemoval(arguments: arguments)
	}

	private func performRemoval(arguments: HelperRequest) async {
		guard let session else {
			installationFailure = .helperUnreachable
			return
		}
		let listener = openProgressListener()
		progressListener = listener

		byteCount = 0
		text = NSLocalizedString("Removing...", comment: "")
		file = ""
		isRunning = true
		ProcessInfo.processInfo.disableSuddenTermination()

		do {
			// The endpoint and the request travel as two messages: `XPCSession.send` requires
			// all values of a dictionary to have the same type.
			try session.send(message: HelperWire.dictionary(carrying: listener.endpoint))
		} catch {
			logger.error("Could not send the progress endpoint: \(error.localizedDescription, privacy: .public)")
			installationFailure = .helperUnreachable
			progressDidEnd(outcome: nil)
			return
		}

		let reply = await request(.process(arguments))
		guard case .accepted? = reply else {
			logger.error("The helper did not accept the request")
			installationFailure = .helperUnreachable
			progressDidEnd(outcome: nil)
			return
		}

		notify(title: NSLocalizedString("Monolingual started", comment: ""),
		       body: NSLocalizedString("Started removing files", comment: ""))
	}

	/// Handles a reply that arrives over the progress connection.
	private func receive(_ reply: HelperReply) {
		switch reply {
		case let .progress(file, size, appName):
			byteCount += Int64(size)
			processProgress(file: URL(fileURLWithPath: file, isDirectory: false), size: size, appName: appName)
		case let .finished(exitCode):
			logger.info("Helper finished with exit code: \(exitCode, privacy: .public)")
			logger.info("Files removed. Space saved: \(self.byteCount)")
			progressDidEnd(outcome: exitCode == Int(EXIT_SUCCESS) ? .completed : .cancelled)
		case .version, .accepted:
			// Those answer a request directly, and are handled where it is sent.
			logger.error("Unexpected reply on the progress connection")
		}
	}

	/// Ends the run and shuts the helper down. `outcome` is nil for a run that failed for a
	/// reason already reported through `installationFailure`, which brings up its own alert.
	private func progressDidEnd(outcome: Outcome?) {
		guard isRunning else {
			return
		}

		isRunning = false
		progressResetTimer?.invalidate()
		progressResetTimer = nil

		// The listener has done its job, but the session is deliberately left open: exiting is
		// also what stops a removal that is still running, so the message has to reach the
		// helper before the connection goes away. The helper exits on it, and that is what ends
		// the session.
		progressListener?.cancel()
		progressListener = nil
		send(.exit(outcome == .completed ? Int(EXIT_SUCCESS) : Int(EXIT_FAILURE)))

		// A helper that does not get around to exiting must not keep the session alive, so it
		// is closed anyway after a while — unless a newer run has replaced it by then.
		let endingSession = session
		Task {
			try? await Task.sleep(for: .seconds(10))
			guard session === endingSession else { return }
			closeConnection()
		}

		self.outcome = outcome

		if outcome == .completed {
			notify(title: NSLocalizedString("Monolingual finished", comment: ""),
			       body: NSLocalizedString("Finished removing files", comment: ""))
		}

		log.close()

		ProcessInfo.processInfo.enableSuddenTermination()
	}

	public func cancel() {
		text = NSLocalizedString("Canceling operation...", comment: "")
		file = ""

		logger.info("Cancelled. Space saved: \(self.byteCount)")

		progressDidEnd(outcome: .cancelled)
	}

	private func notify(title: String, body: String) {
		let center = UNUserNotificationCenter.current()
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body

		let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: Date())
		let trigger = UNCalendarNotificationTrigger(dateMatching: now, repeats: false)
		let request = UNNotificationRequest(identifier: UUID().uuidString,
		                                    content: content,
		                                    trigger: trigger)

		// The system drops a notification the user has not allowed, and asking for that
		// permission is a prompt — so it is asked for on the first notification, which is
		// the one a removal starting posts.
		Task {
			if !askedForNotificationPermission {
				askedForNotificationPermission = true
				do {
					guard try await center.requestAuthorization(options: [.alert, .sound]) else {
						logger.info("Not showing a notification: Monolingual is not allowed to notify")
						return
					}
				} catch {
					logger.error("Could not ask for permission to notify: \(error.localizedDescription, privacy: .public)")
					return
				}
			}

			do {
				try await center.add(request)
			} catch {
				logger.error("Could not show a notification: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func processProgress(file: URL, size: Int, appName: String?) {
		log.message("\(file.path): \(size)\n")

		let message: String
		switch removal {
		case .architectures:
			message = NSLocalizedString("Removing architecture from universal binary", comment: "")
		case let .languages(languages):
			// A file belongs to a language when one of its path components is a folder that
			// language owns.
			let displayName = languages.first { language in
				file.pathComponents.contains { language.folders.contains($0) }
			}?.displayName

			switch (displayName, appName) {
			case let (displayName?, app?):
				message = String(format: NSLocalizedString("Removing language %@ from %@…", comment: ""), displayName, app)
			case let (displayName?, nil):
				message = String(format: NSLocalizedString("Removing language %@…", comment: ""), displayName)
			default:
				message = String(format: NSLocalizedString("Removing %@…", comment: ""), file.absoluteString)
			}
		}

		self.text = message
		self.file = file.path

		self.progressResetTimer?.invalidate()
		self.progressResetTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
			Task { @MainActor in
				self.text = NSLocalizedString("Removing...", comment: "")
				self.file = ""
			}
		}
	}
}
