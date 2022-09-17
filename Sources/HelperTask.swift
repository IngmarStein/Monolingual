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

class HelperTask: ProgressProtocol, ObservableObject {
	private var helperConnection: NSXPCConnection?
	private var progress: Progress?
	private var progressResetTimer: Timer?
	private var progressObserverToken: NSKeyValueObservation?
	private let logger = Logger()
	@Published var text = ""
	@Published var file = ""
	@Published var byteCount: Int64 = 0

	private lazy var xpcServiceConnection: NSXPCConnection = {
		let connection = NSXPCConnection(serviceName: "com.github.IngmarStein.Monolingual.XPCService")
		connection.remoteObjectInterface = NSXPCInterface(with: XPCServiceProtocol.self)
		connection.resume()
		return connection
	}()

	func checkAndRunHelper(arguments: HelperRequest) {
		let xpcService = xpcServiceConnection.remoteObjectProxyWithErrorHandler { error -> Void in
			self.logger.error("XPCService error: \(error.localizedDescription, privacy: .public)")
		} as? XPCServiceProtocol

		if let xpcService = xpcService {
			xpcService.connect { endpoint -> Void in
				if let endpoint = endpoint {
					var performInstallation = false
					let connection = NSXPCConnection(listenerEndpoint: endpoint)
					let interface = NSXPCInterface(with: HelperProtocol.self)
					interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(HelperProtocol.process(request:progress:reply:)), argumentIndex: 1, ofReply: false)
					connection.remoteObjectInterface = interface
					connection.invalidationHandler = {
						self.logger.error("XPC connection to helper invalidated.")
						self.helperConnection = nil
						if performInstallation {
							self.installHelper { success in
								if success {
									self.checkAndRunHelper(arguments: arguments)
								}
							}
						}
					}
					connection.resume()
					self.helperConnection = connection

					if let connection = self.helperConnection {
						guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
							self.logger.error("Error connecting to helper: \(error.localizedDescription, privacy: .public)")
						}) as? HelperProtocol else {
							self.logger.error("Helper does not conform to HelperProtocol")
							return
						}

						helper.getVersion { installedVersion in
							xpcService.bundledHelperVersion { bundledVersion in
								if installedVersion == bundledVersion {
									// helper is current
									DispatchQueue.main.async {
										self.runHelper(helper, arguments: arguments)
									}
								} else {
									// helper is different version
									performInstallation = true
									// this triggers rdar://23143866 (duplicate of rdar://19601397)
									// helper.uninstall()
									helper.exit(code: Int(EXIT_SUCCESS))
									connection.invalidate()
									xpcService.disconnect()
								}
							}
						}
					}
				} else {
					self.logger.error("Failed to get XPC endpoint.")
					self.installHelper { success in
						if success {
							self.checkAndRunHelper(arguments: arguments)
						}
					}
				}
			}
		}
	}

	private func runHelper(_ helper: HelperProtocol, arguments: HelperRequest) {
		ProcessInfo.processInfo.disableSuddenTermination()

		text = "Removing..."
		file = ""

		let helperProgress = Progress(totalUnitCount: -1)
		helperProgress.becomeCurrent(withPendingUnitCount: -1)
		progressObserverToken = helperProgress.observe(\.completedUnitCount) { progress, _ in
			if let url = progress.fileURL, let size = progress.userInfo[ProgressUserInfoKey.sizeDifference] as? Int {
				self.processProgress(file: url, size: size, appName: progress.userInfo[ProgressUserInfoKey.appName] as? String)
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
				self.processProgress(file: url, size: size, appName: progress.userInfo[ProgressUserInfoKey.appName] as? String)
			}
		}

		showingProgressView = true

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

	func installHelper(reply: @escaping (Bool) -> Void) {
		let xpcService = xpcServiceConnection.remoteObjectProxyWithErrorHandler { error -> Void in
			self.logger.error("XPCService error: \(error.localizedDescription, privacy: .public)")
		} as? XPCServiceProtocol

		if let xpcService = xpcService {
			xpcService.installHelperTool { error in
				if let error = error {
					DispatchQueue.main.async {
						let alert = NSAlert()
						alert.alertStyle = .critical
						alert.messageText = error.localizedDescription
						alert.informativeText = error.localizedRecoverySuggestion ?? error.localizedFailureReason ?? " "
						alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
						log.close()
					}
					reply(false)
				} else {
					reply(true)
				}
			}
		}
	}

	func processed(file: String, size: Int, appName: String?) {
		if let progress = progress {
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
				progress.willChangeValue(forKey: #keyPath(Progress.completedUnitCount))
				progress.didChangeValue(forKey: #keyPath(Progress.completedUnitCount))
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

		processApplication = nil
		showingProgressView = false
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

			let alert = NSAlert()
			alert.alertStyle = .informational
			alert.messageText = NSLocalizedString("You cancelled the removal. Some files were erased, some were not.", comment: "")
			alert.informativeText = String(format: NSLocalizedString("Space saved: %@.", comment: ""), byteCount)
			alert.beginSheetModal(for: view.window!, completionHandler: nil)
		} else {
			let alert = NSAlert()
			alert.alertStyle = .informational
			alert.messageText = NSLocalizedString("Files removed.", comment: "")
			alert.informativeText = String(format: NSLocalizedString("Space saved: %@.", comment: ""), byteCount)
			alert.beginSheetModal(for: view.window!, completionHandler: nil)

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
			self.text = NSLocalizedString("Removing...", comment: "")
			self.file = ""
		}
	}
}
