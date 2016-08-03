//
//  Helper.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation
import MachO.fat
import MachO.loader

// TODO: remove the following as soon as the new logging API is available for Swift
// swiftlint:disable:next variable_name
var OS_LOG_DEFAULT = 0
func os_log_debug(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_error(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_info(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}

extension URL {
	func hasExtendedAttribute(_ attribute: String) -> Bool {
		return getxattr(self.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) != -1
	}

	var isProtected: Bool {
		return hasExtendedAttribute("com.apple.rootless")
	}
}

final class Helper: NSObject, NSXPCListenerDelegate {

	private var listener: NSXPCListener
	private var timer: Timer?
	private let timeoutInterval = TimeInterval(30.0)
	private let workerQueue = OperationQueue()
	private var isRootless = true

	var version: String {
		return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
	}

	override init() {
		listener = NSXPCListener(machServiceName: "com.github.IngmarStein.Monolingual.Helper")

		super.init()

		listener.delegate = self
		workerQueue.maxConcurrentOperationCount = 1
		isRootless = checkRootless()
		os_log_debug(OS_LOG_DEFAULT, "isRootless=\(isRootless)")
	}

	func run() {
		os_log_info(OS_LOG_DEFAULT, "MonolingualHelper started")

		listener.resume()
		timer = Timer.scheduledTimer(timeInterval: timeoutInterval, target: self, selector: #selector(Helper.timeout(_:)), userInfo: nil, repeats: false)
		RunLoop.current.run()
	}

	@objc func timeout(_: Timer) {
		os_log_info(OS_LOG_DEFAULT, "timeout while waiting for request")
		exitWithCode(Int(EXIT_SUCCESS))
	}

	func connectWithEndpointReply(reply: (NSXPCListenerEndpoint) -> Void) {
		reply(listener.endpoint)
	}

	func getVersionWithReply(reply: (String) -> Void) {
		reply(version)
	}

	// see https://devforums.apple.com/message/1004420#1004420
	func uninstall() {
		//NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["remove", "com.github.IngmarStein.Monolingual.Helper"])
		//NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["unload", "-wF", "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist"])
		do {
			try FileManager.default.removeItem(atPath: "/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
		} catch _ {
		}
	}

	func exitWithCode(_ exitCode: Int) {
		os_log_info(OS_LOG_DEFAULT, "exiting with exit status \(exitCode)")
		workerQueue.waitUntilAllOperationsAreFinished()
		exit(Int32(exitCode))
	}

	func processRequest(_ request: HelperRequest, progress remoteProgress: ProgressProtocol?, reply: (Int) -> Void) {
		timer?.invalidate()

		let context = HelperContext(request, rootless: isRootless)

		os_log_debug(OS_LOG_DEFAULT, "Received request: %@", request)

		// https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/#10_10NSXPC
		let progress = Progress(totalUnitCount: -1)
		progress.completedUnitCount = 0
		progress.cancellationHandler = {
			os_log_info(OS_LOG_DEFAULT, "Stopping MonolingualHelper")
		}
		context.progress = progress
		context.remoteProgress = remoteProgress

		// check if /usr/bin/strip is present
		request.doStrip = request.doStrip && context.fileManager.fileExists(atPath: "/usr/bin/strip")

		workerQueue.addOperation {
			// delete regular files
			if let files = request.files {
				for file in files {
					if progress.isCancelled {
						break
					}
					context.remove(URL(fileURLWithPath: file))
				}
			}

			let roots = request.includes?.map { URL(fileURLWithPath: $0, isDirectory: true) }

			if let roots = roots {
				// recursively delete directories
				if let directories = request.directories, !directories.isEmpty {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.processDirectory(root, context: context)
					}
				}
			}

			// thin fat binaries
			if let archs = request.thin, let roots = roots, !archs.isEmpty {
				if let lipo = Lipo(archs: archs) {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.thinDirectory(root, context: context, lipo: lipo)
					}
				}
			}

			reply(progress.isCancelled ? Int(EXIT_FAILURE) : Int(EXIT_SUCCESS))
		}
	}

	//MARK: - NSXPCListenerDelegate

	func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		let helperRequestClass = HelperRequest.self as AnyObject as! NSObject
		let classes = Set([helperRequestClass])
		let interface = NSXPCInterface(with: HelperProtocol.self)
		interface.setClasses(classes, for: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 0, ofReply: false)
		interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 1, ofReply: false)
		newConnection.exportedInterface = interface
		newConnection.exportedObject = self
		newConnection.resume()

		return true
	}

	//MARK: -

	private func iterateDirectory(_ url: URL, context: HelperContext, prefetchedProperties: [String], block: (URL, FileManager.DirectoryEnumerator) -> Void) {
		if let progress = context.progress, progress.isCancelled {
			return
		}

		if context.isExcluded(url) || context.isDirectoryBlacklisted(url) || (isRootless && url.isProtected) {
			return
		}

		context.addCodeResourcesToBlacklist(url)

		let dirEnumerator = context.fileManager.enumerator(at: url, includingPropertiesForKeys: prefetchedProperties, options: [], errorHandler: nil)
		if let dirEnumerator = dirEnumerator {
			for entry in dirEnumerator {
				if let progress = context.progress, progress.isCancelled {
					return
				}
				let theURL = entry as! URL

				do {
					let resourceValues = try theURL.resourceValues(forKeys: [URLResourceKey.isDirectoryKey])

					if let isDirectory = resourceValues.isDirectory, isDirectory {
						if context.isExcluded(theURL) || context.isDirectoryBlacklisted(theURL) || (isRootless && theURL.isProtected) {
							dirEnumerator.skipDescendents()
							continue
						}
						context.addCodeResourcesToBlacklist(theURL)
					}
				} catch _ {
					// ignore
				}

				block(theURL, dirEnumerator)
			}
		}
	}

	func processDirectory(_ url: URL, context: HelperContext) {
		iterateDirectory(url, context: context, prefetchedProperties: [URLResourceKey.isDirectoryKey.rawValue]) { theURL, dirEnumerator in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [URLResourceKey.isDirectoryKey])

				if let isDirectory = resourceValues.isDirectory, isDirectory {
					let lastComponent = theURL.lastPathComponent
					if let directories = context.request.directories {
						if directories.contains(lastComponent) {
							context.remove(theURL)
							dirEnumerator.skipDescendents()
						}
					}
				}
			} catch _ {
			}
		}
	}

	func thinFile(url: URL, context: HelperContext, lipo: Lipo) {
		var sizeDiff: Int = 0
		if lipo.run(path: url.path, sizeDiff: &sizeDiff) {
			if sizeDiff > 0 {
				context.reportProgress(url: url, size: sizeDiff)
			}
		}
	}

	func thinDirectory(_ url: URL, context: HelperContext, lipo: Lipo) {
		iterateDirectory(url, context: context, prefetchedProperties: [URLResourceKey.isDirectoryKey.rawValue, URLResourceKey.isRegularFileKey.rawValue, URLResourceKey.isExecutableKey.rawValue, URLResourceKey.isApplicationKey.rawValue]) { theURL, dirEnumerator in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [URLResourceKey.isRegularFileKey, URLResourceKey.isExecutableKey, URLResourceKey.isApplicationKey])
				if let isExecutable = resourceValues.isExecutable, let isRegularFile = resourceValues.isRegularFile, isExecutable && isRegularFile && !context.isFileBlacklisted(theURL) {
					if theURL.pathExtension == "class" {
						return
					}

					let data = try Data(contentsOf: theURL, options: [.alwaysMapped, .uncached])
					if data.count >= sizeof(UInt32.self) {
						data.withUnsafeBytes { (pointer: UnsafePointer<UInt32>) -> Void in
							let magic = pointer.pointee
							if magic == FAT_MAGIC || magic == FAT_CIGAM {
								self.thinFile(url: theURL, context: context, lipo: lipo)
							}
							if context.request.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
								self.stripFile(theURL, context: context)
							}
						}
					}
				} else if let isApplication = resourceValues.isApplication, isApplication {
					// don't thin universal frameworks contained in a single-architecture application
					// see https://github.com/IngmarStein/Monolingual/issues/67
					let bundle = Bundle(url: theURL)
					if let bundle = bundle, let executableArchitectures = bundle.executableArchitectures, executableArchitectures.count == 1 {
						if let sharedFrameworksURL = bundle.sharedFrameworksURL {
							context.excludeDirectory(sharedFrameworksURL)
						}
						if let privateFrameworksURL = bundle.privateFrameworksURL {
							context.excludeDirectory(privateFrameworksURL)
						}
					}
				}
			} catch _ {
			}
		}
	}

	func hasCodeSignature(url: URL) -> Bool {
		var codeRef: SecStaticCode?
		let result = SecStaticCodeCreateWithPath(url, [], &codeRef)
		if result == errSecSuccess, let codeRef = codeRef {
			var requirement: SecRequirement?
			let result2 = SecCodeCopyDesignatedRequirement(codeRef, [], &requirement)
			return result2 == errSecSuccess
		}
		return false
	}

	func stripFile(_ url: URL, context: HelperContext) {
		// do not modify executables with code signatures
		if !hasCodeSignature(url: url) {
			do {
				let attributes = try context.fileManager.attributesOfItem(atPath: url.path)
				let path = url.path
				let oldSize: Int
				do {
					let resourceValues = try url.resourceValues(forKeys: [URLResourceKey.totalFileAllocatedSizeKey, URLResourceKey.fileAllocatedSizeKey])
					oldSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
				} catch _ {
					return
				}

				let task = Task.launchedTask(withLaunchPath: "/usr/bin/strip", arguments: ["-u", "-x", "-S", "-", path])
				task.waitUntilExit()

				if task.terminationStatus != EXIT_SUCCESS {
					os_log_error(OS_LOG_DEFAULT, "/usr/bin/strip failed with exit status %d", task.terminationStatus)
				}

				let newAttributes = [
					FileAttributeKey.ownerAccountID: attributes[FileAttributeKey.ownerAccountID]!,
					FileAttributeKey.groupOwnerAccountID: attributes[FileAttributeKey.groupOwnerAccountID]!,
					FileAttributeKey.posixPermissions: attributes[FileAttributeKey.posixPermissions]!
				]

				do {
					try context.fileManager.setAttributes(newAttributes, ofItemAtPath: path)
				} catch let error as NSError {
					os_log_error(OS_LOG_DEFAULT, "Failed to set file attributes for '%@': %@", path, error)
				}

				do {
					let resourceValues = try url.resourceValues(forKeys: [URLResourceKey.totalFileAllocatedSizeKey, URLResourceKey.fileAllocatedSizeKey])
					let newSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0

					if oldSize > newSize {
						let sizeDiff = oldSize - newSize
						context.reportProgress(url: url, size: sizeDiff)
					}
				} catch _ {
				}
			} catch let error as NSError {
				os_log_error(OS_LOG_DEFAULT, "Failed to get file attributes for '%@': %@", url, error)
			}
		}
	}

	// check if SIP is enabled, see https://github.com/IngmarStein/Monolingual/issues/74
	func checkRootless() -> Bool {
		let protectedDirectory = URL(fileURLWithPath: "/System/Monolingual.sip", isDirectory: true)
		let fileManager = FileManager.default

		do {
			try fileManager.createDirectory(at: protectedDirectory, withIntermediateDirectories: false, attributes: nil)
		} catch {
			return true
		}

		do {
			try fileManager.removeItem(at: protectedDirectory)
		} catch let error as NSError {
			os_log_error(OS_LOG_DEFAULT, "Failed to remove temporary file '%@': %@", protectedDirectory, error)
		}

		return false
	}
}
