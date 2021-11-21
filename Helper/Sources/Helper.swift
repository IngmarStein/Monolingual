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
import OSLog

extension URL {
	func hasExtendedAttribute(_ attribute: String) -> Bool {
		getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) != -1
	}

	var isProtected: Bool {
		hasExtendedAttribute("com.apple.rootless")
	}
}

final class Helper: NSObject, NSXPCListenerDelegate, HelperProtocol {
	private var listener: NSXPCListener
	private var timer: Timer?
	private let timeoutInterval = TimeInterval(30.0)
	private let workerQueue = OperationQueue()
	private var isRootless = true
	private let logger = Logger()

	var version: String {
		Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	}

	override init() {
		listener = NSXPCListener(machServiceName: "com.github.IngmarStein.Monolingual.Helper")

		super.init()

		listener.delegate = self
		workerQueue.maxConcurrentOperationCount = 1
		isRootless = checkRootless()
		logger.debug("isRootless=\(isRootless ? "true" : "false", privacy: .public)")
	}

	func run() {
		logger.info("MonolingualHelper \(version, privacy: .public) started")

		listener.resume()
		timer = Timer.scheduledTimer(timeInterval: timeoutInterval, target: self, selector: #selector(Helper.timeout(_:)), userInfo: nil, repeats: false)
		RunLoop.current.run()
	}

	@objc func timeout(_: Timer) {
		logger.info("timeout while waiting for request")
		exit(code: Int(EXIT_SUCCESS))
	}

	@objc func connect(_ reply: @escaping (NSXPCListenerEndpoint) -> Void) {
		reply(listener.endpoint)
	}

	@objc func getVersion(_ reply: @escaping (String) -> Void) {
		reply(version)
	}

	// see https://devforums.apple.com/message/1004420#1004420
	@objc func uninstall() {
		// NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["remove", "com.github.IngmarStein.Monolingual.Helper"])
		// NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["unload", "-wF", "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist"])
		do {
			try FileManager.default.removeItem(atPath: "/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
		} catch {}
	}

	@objc func exit(code: Int) {
		logger.info("exiting with exit status \(code, privacy: .public)")
		workerQueue.waitUntilAllOperationsAreFinished()
		Darwin.exit(Int32(code))
	}

	@discardableResult @objc func process(request: HelperRequest, progress remoteProgress: ProgressProtocol?, reply: @escaping (Int) -> Void) -> Progress {
		timer?.invalidate()

		let context = HelperContext(request, rootless: isRootless)

		logger.debug("Received request: \(request, privacy: .public)")

		// https://developer.apple.com/library/content/releasenotes/Foundation/RN-Foundation-v10.10/index.html#10_10NSXPC
		// Progress must not be indeterminate - otherwise no KVO notifications are fired
		// see rdar://33140109
		let progress = Progress(totalUnitCount: 1)
		progress.completedUnitCount = 0
		progress.cancellationHandler = {
			self.logger.info("Stopping MonolingualHelper")
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
					context.remove(URL(fileURLWithPath: file, isDirectory: false))
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

		return progress
	}

	// MARK: - NSXPCListenerDelegate

	func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		let helperRequestClass = HelperRequest.self as AnyObject as! NSObject
		let classes = Set([helperRequestClass])
		let interface = NSXPCInterface(with: HelperProtocol.self)
		interface.setClasses(classes, for: #selector(Helper.process(request:progress:reply:)), argumentIndex: 0, ofReply: false)
		interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(Helper.process(request:progress:reply:)), argumentIndex: 1, ofReply: false)
		newConnection.exportedInterface = interface
		newConnection.exportedObject = self
		newConnection.resume()

		return true
	}

	// MARK: -

	private func iterateDirectory(_ url: URL, context: HelperContext, prefetchedProperties: [URLResourceKey], block: (URL, FileManager.DirectoryEnumerator) -> Void) {
		if let progress = context.progress, progress.isCancelled {
			return
		}

		if context.isExcluded(url) || context.isDirectoryBlocklisted(url) || (isRootless && url.isProtected) {
			return
		}

		context.addCodeResourcesToBlocklist(url)

		let dirEnumerator = context.fileManager.enumerator(at: url, includingPropertiesForKeys: prefetchedProperties, options: [], errorHandler: nil)
		if let dirEnumerator = dirEnumerator {
			for entry in dirEnumerator {
				if let progress = context.progress, progress.isCancelled {
					return
				}
				guard let theURL = entry as? URL else { continue }

				do {
					let resourceValues = try theURL.resourceValues(forKeys: [.isDirectoryKey])

					if let isDirectory = resourceValues.isDirectory, isDirectory {
						if context.isExcluded(theURL) || context.isDirectoryBlocklisted(theURL) || (isRootless && theURL.isProtected) {
							dirEnumerator.skipDescendents()
							continue
						}
						context.addCodeResourcesToBlocklist(theURL)
					}
				} catch {
					// ignore
				}

				block(theURL, dirEnumerator)
			}
		}
	}

	func processDirectory(_ url: URL, context: HelperContext) {
		iterateDirectory(url, context: context, prefetchedProperties: [.isDirectoryKey]) { theURL, dirEnumerator in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [.isDirectoryKey])

				if let isDirectory = resourceValues.isDirectory, isDirectory {
					let lastComponent = theURL.lastPathComponent
					if let directories = context.request.directories {
						if directories.contains(lastComponent) {
							context.remove(theURL)
							dirEnumerator.skipDescendents()
						}
					}
				}
			} catch {}
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
		iterateDirectory(url, context: context, prefetchedProperties: [.isDirectoryKey, .isRegularFileKey, .isExecutableKey, .isApplicationKey]) { theURL, _ in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey, .isApplicationKey])
				if let isExecutable = resourceValues.isExecutable, let isRegularFile = resourceValues.isRegularFile, isExecutable, isRegularFile, !context.isFileBlocklisted(theURL) {
					if theURL.pathExtension == "class" {
						return
					}

					let data = try Data(contentsOf: theURL, options: [.alwaysMapped, .uncached])
					if data.count >= MemoryLayout<UInt32>.size {
						data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Void in
							let magic = pointer.load(as: UInt32.self)
							let isFatMagic = magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
							if isFatMagic {
								self.thinFile(url: theURL, context: context, lipo: lipo)
							}
							if context.request.doStrip, isFatMagic || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64 {
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
			} catch {}
		}
	}

	func hasCodeSignature(url: URL) -> Bool {
		var codeRef: SecStaticCode?
		let result = SecStaticCodeCreateWithPath(url as CFURL, [], &codeRef)
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
					let resourceValues = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
					oldSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
				} catch {
					return
				}

				let process = try Process.run(URL(fileURLWithPath: "/usr/bin/strip", isDirectory: false), arguments: ["-u", "-x", "-S", "-", path])
				process.waitUntilExit()

				if process.terminationStatus != EXIT_SUCCESS {
					logger.error("/usr/bin/strip failed with exit status \(process.terminationStatus, privacy: .public)")
				}

				let newAttributes = [
					FileAttributeKey.ownerAccountID: attributes[FileAttributeKey.ownerAccountID]!,
					FileAttributeKey.groupOwnerAccountID: attributes[FileAttributeKey.groupOwnerAccountID]!,
					FileAttributeKey.posixPermissions: attributes[FileAttributeKey.posixPermissions]!,
				]

				do {
					try context.fileManager.setAttributes(newAttributes, ofItemAtPath: path)
				} catch {
					logger.error("Failed to set file attributes for '\(path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
				}

				do {
					let resourceValues = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
					let newSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0

					if oldSize > newSize {
						let sizeDiff = oldSize - newSize
						context.reportProgress(url: url, size: sizeDiff)
					}
				} catch {}
			} catch {
				logger.error("Failed to get file attributes for '\(url.absoluteString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
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
		} catch {
			logger.error("Failed to remove temporary file '\(protectedDirectory.absoluteString, privacy: .public)': \(error.localizedDescription, privacy: .public)")
		}

		return false
	}
}
