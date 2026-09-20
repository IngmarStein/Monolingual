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
#if canImport(HelperShared)
import HelperShared
#endif

import Observation

@MainActor @Observable class HelperTask: ProgressProtocol {
	private var helperConnection: NSXPCConnection?
	private var progress: Progress?
	private var progressResetTimer: Timer?
	private var progressObserverToken: NSKeyValueObservation?
	private let logger = Logger()
	private let installer = HelperInstaller()
	var text = ""
	var file = ""
	var byteCount: Int64 = 0
	var isRunning = false

	/// Set when the privileged helper is unavailable, for instance because it still has to be
	/// allowed in System Settings.
	var installationFailure: HelperInstallationFailure?

	var languages: [LanguageSetting] = []
	var mode: MainView.MonolingualMode = .languages

	func checkAndRunHelper(arguments: HelperRequest) {
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

			runHelper(arguments: arguments)
		}
	}

	/// Returns a proxy for the privileged helper, connecting to it if necessary.
	private func connectToHelper() -> HelperProtocol? {
		if helperConnection == nil {
			let connection = NSXPCConnection(machServiceName: HelperInstaller.machServiceName, options: .privileged)
			let interface = NSXPCInterface(with: HelperProtocol.self)
			interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(HelperProtocol.process(request:progress:reply:)), argumentIndex: 1, ofReply: false)
			connection.remoteObjectInterface = interface
			connection.invalidationHandler = {
				self.logger.error("XPC connection to helper invalidated.")
				self.helperConnection = nil
			}
			connection.resume()
			helperConnection = connection
		}

		guard let helper = helperConnection?.remoteObjectProxyWithErrorHandler({ error in
			self.logger.error("Error connecting to helper: \(error.localizedDescription, privacy: .public)")
		}) as? HelperProtocol else {
			logger.error("Helper does not conform to HelperProtocol")
			return nil
		}

		return helper
	}

	private func runHelper(arguments: HelperRequest) {
		guard let helper = connectToHelper() else {
			return
		}

		helper.getVersion { version in
			// The helper lives inside the app bundle and therefore reports the version of the
			// app. Anything else means a helper installed by an older version of Monolingual
			// is still answering on the Mach service.
			guard version == HelperInstaller.appVersion else {
				self.logger.error("Unexpected helper version: \(version, privacy: .public)")
				DispatchQueue.main.async {
					self.installationFailure = .outdatedHelper(version)
				}
				return
			}

			DispatchQueue.main.async {
				self.performRemoval(with: helper, arguments: arguments)
			}
		}
	}

	private func performRemoval(with helper: HelperProtocol, arguments: HelperRequest) {
		ProcessInfo.processInfo.disableSuddenTermination()

		text = "Removing..."
		file = ""

		let helperProgress = Progress(totalUnitCount: -1)
		helperProgress.becomeCurrent(withPendingUnitCount: -1)
		progressObserverToken = helperProgress.observe(\.completedUnitCount) { progress, _ in
			if let url = progress.fileURL, let size = progress.userInfo[ProgressUserInfoKey.sizeDifference] as? Int {
				Task { @MainActor in
					self.processProgress(file: url, size: size, appName: progress.userInfo[ProgressUserInfoKey.appName] as? String)
				}
			}
		}

		// DEBUG
		// arguments.dryRun = true

		helper.process(request: arguments, progress: self) { exitCode in
			self.logger.info("helper finished with exit code: \(exitCode, privacy: .public)")
			helper.exit(code: exitCode)
			if exitCode == Int(EXIT_SUCCESS) {
				DispatchQueue.main.async {
					self.progressDidEnd(completed: true)
				}
			}
		}

		helperProgress.resignCurrent()
		progress = helperProgress

		progressObserverToken = helperProgress.observe(\.completedUnitCount) { progress, _ in
			if let url = progress.fileURL, let size = progress.userInfo[ProgressUserInfoKey.sizeDifference] as? Int {
				Task { @MainActor in
					self.processProgress(file: url, size: size, appName: progress.userInfo[ProgressUserInfoKey.appName] as? String)
				}
			}
		}

		isRunning = true

		let content = UNMutableNotificationContent()
		content.title = NSLocalizedString("Monolingual started", comment: "")
		content.body = NSLocalizedString("Started removing files", comment: "")

		let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: Date())
		let trigger = UNCalendarNotificationTrigger(dateMatching: now, repeats: false)
		let request = UNNotificationRequest(identifier: UUID().uuidString,
																				content: content,
																				trigger: trigger)

		UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
	}

	nonisolated func processed(file: String, size: Int, appName: String?) {
		Task { @MainActor in
			if let progress = self.progress {
				let count = progress.userInfo[.fileCompletedCountKey] as? Int ?? 0
				progress.setUserInfoObject(count + 1, forKey: .fileCompletedCountKey)
				progress.setUserInfoObject(URL(fileURLWithPath: file, isDirectory: false), forKey: .fileURLKey)
				progress.setUserInfoObject(size, forKey: ProgressUserInfoKey.sizeDifference)
				if let appName = appName {
					progress.setUserInfoObject(appName, forKey: ProgressUserInfoKey.appName)
				}
				progress.completedUnitCount += Int64(size)

				// show the file progress even if it has zero bytes
				if size == 0 {
					// progress.willChangeValue(forKey: #keyPath(Progress.completedUnitCount))
					// progress.didChangeValue(forKey: #keyPath(Progress.completedUnitCount))
				}
			}
		}
	}

	public func cancel() {
		text = "Canceling operation..."
		file = ""

		progressDidEnd(completed: false)
	}

	private func progressDidEnd(completed: Bool) {
		guard let progress = progress else { return }

		isRunning = false
		progressResetTimer?.invalidate()
		progressResetTimer = nil

		byteCount = max(progress.completedUnitCount, 0)
		progressObserverToken?.invalidate()
		self.progress = nil

		if !completed {
			// cancel the current progress which tells the helper to stop
			progress.cancel()
			logger.debug("Closing progress connection")

			if let helper = helperConnection?.remoteObjectProxy as? HelperProtocol {
				helper.exit(code: Int(EXIT_FAILURE))
			}

			// TODO: Show cancellation alert
			logger.info("Cancelled. Space saved: \(self.byteCount)")
		} else {
			// TODO: Show completion alert
			logger.info("Files removed. Space saved: \(self.byteCount)")

			let content = UNMutableNotificationContent()
			content.title = NSLocalizedString("Monolingual finished", comment: "")
			content.body = NSLocalizedString("Finished removing files", comment: "")

			let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: Date())
			let trigger = UNCalendarNotificationTrigger(dateMatching: now, repeats: false)
			let request = UNNotificationRequest(identifier: UUID().uuidString,
																					content: content,
																					trigger: trigger)

			UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
		}

		if let connection = helperConnection {
			logger.info("Closing connection to helper")
			connection.invalidate()
			helperConnection = nil
		}

		log.close()

		ProcessInfo.processInfo.enableSuddenTermination()
	}

	private func processProgress(file: URL, size: Int, appName: String?) {
		log.message("\(file.path): \(size)\n")

		let message: String
		if mode == .architectures {
			message = NSLocalizedString("Removing architecture from universal binary", comment: "")
		} else {
			// parse file name
			var lang: String?

			if mode == .languages {
				for pathComponent in file.pathComponents where (pathComponent as NSString).pathExtension == "lproj" {
					for language in self.languages {
						if language.folders.contains(pathComponent) {
							lang = language.displayName
							break
						}
					}
				}
			}
			if let app = appName, let lang = lang {
				message = String(format: NSLocalizedString("Removing language %@ from %@…", comment: ""), lang, app)
			} else if let lang = lang {
				message = String(format: NSLocalizedString("Removing language %@…", comment: ""), lang)
			} else {
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
