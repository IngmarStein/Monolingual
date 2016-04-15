//
//  Helper.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation
import Lipo
import MachO.fat
import MachO.loader

extension NSURL {
	func hasExtendedAttribute(_ attribute: String) -> Bool {
		return getxattr(self.path!, attribute, nil, 0, 0, XATTR_NOFOLLOW) != -1
	}

	var isProtected : Bool {
		return hasExtendedAttribute("com.apple.rootless")
	}
}

final class Helper : NSObject, NSXPCListenerDelegate {

	private var listener: NSXPCListener
	private var timer: NSTimer?
	private let timeoutInterval = NSTimeInterval(30.0)
	private let workerQueue = NSOperationQueue()
	private var isRootless = true

	var version: String {
		return NSBundle.main().objectForInfoDictionaryKey("CFBundleVersion") as! String
	}

	override init() {
		listener = NSXPCListener(machServiceName: "com.github.IngmarStein.Monolingual.Helper")

		super.init()

		listener.delegate = self
		workerQueue.maxConcurrentOperationCount = 1
		isRootless = checkRootless()
		//NSLog("isRootless=\(isRootless)")
	}

	func run() {
		NSLog("MonolingualHelper started")

		listener.resume()
		timer = NSTimer.scheduledTimer(timeInterval: timeoutInterval, target: self, selector: #selector(Helper.timeout(_:)), userInfo: nil, repeats: false)
		NSRunLoop.current().run()
	}

	@objc func timeout(_: NSTimer) {
		NSLog("timeout while waiting for request")
		exitWithCode(Int(EXIT_SUCCESS))
	}

	func connectWithEndpointReply(reply:(NSXPCListenerEndpoint) -> Void) {
		reply(listener.endpoint)
	}

	func getVersionWithReply(reply:(String) -> Void) {
		reply(version)
	}

	// see https://devforums.apple.com/message/1004420#1004420
	func uninstall() {
		//NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["remove", "com.github.IngmarStein.Monolingual.Helper"])
		//NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["unload", "-wF", "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist"])
		do {
			try NSFileManager.defaultManager().removeItem(atPath: "/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try NSFileManager.defaultManager().removeItem(atPath: "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
		} catch _ {
		}
	}

	func exitWithCode(_ exitCode: Int) {
		NSLog("exiting with exit status \(exitCode)")
		workerQueue.waitUntilAllOperationsAreFinished()
		exit(Int32(exitCode))
	}

	func processRequest(_ request: HelperRequest, progress remoteProgress: ProgressProtocol?, reply:(Int) -> Void) {
		timer?.invalidate()

		let context = HelperContext(request, rootless: isRootless)

		//NSLog("Received request: %@", request)

		// https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/#10_10NSXPC
		let progress = NSProgress(totalUnitCount: -1)
		progress.completedUnitCount = 0
		progress.cancellationHandler = {
			NSLog("Stopping MonolingualHelper")
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
					context.remove(NSURL(fileURLWithPath:file))
				}
			}

			let roots = request.includes?.map { NSURL(fileURLWithPath: $0, isDirectory: true) }

			if let roots = roots {
				// recursively delete directories
				if let directories = request.directories where !directories.isEmpty {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.processDirectory(root, context:context)
					}
				}
			}

			// thin fat binaries
			if let archs = request.thin, roots = roots where !archs.isEmpty {
				if let lipo = Lipo(archs: archs) {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.thinDirectory(root, context:context, lipo: lipo)
					}
				}
			}

			reply(progress.isCancelled ? Int(EXIT_FAILURE) : Int(EXIT_SUCCESS))
		}
	}

	//MARK: - NSXPCListenerDelegate

	func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
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

	private func iterateDirectory(_ url: NSURL, context:HelperContext, prefetchedProperties:[String], block:(NSURL, NSDirectoryEnumerator) -> Void) {
		if let progress = context.progress where progress.isCancelled {
			return
		}

		if context.isExcluded(url) || context.isDirectoryBlacklisted(url) || (isRootless && url.isProtected) {
			return
		}

		context.addCodeResourcesToBlacklist(url)

		let dirEnumerator = context.fileManager.enumerator(at: url, includingPropertiesForKeys:prefetchedProperties, options:[], errorHandler:nil)
		if let dirEnumerator = dirEnumerator {
			for entry in dirEnumerator {
				if let progress = context.progress where progress.isCancelled {
					return
				}
				let theURL = entry as! NSURL

				var isDirectory: AnyObject?
				do {
					try theURL.getResourceValue(&isDirectory, forKey:NSURLIsDirectoryKey)
				} catch _ {
				}

				if let isDirectory = isDirectory as? Bool where isDirectory {
					if context.isExcluded(theURL) || context.isDirectoryBlacklisted(theURL) || (isRootless && theURL.isProtected) {
						dirEnumerator.skipDescendents()
						continue
					}
					context.addCodeResourcesToBlacklist(theURL)
				}

				block(theURL, dirEnumerator)
			}
		}
	}

	func processDirectory(_ url: NSURL, context:HelperContext) {
		iterateDirectory(url, context:context, prefetchedProperties:[NSURLIsDirectoryKey]) { theURL, dirEnumerator in
			var isDirectory: AnyObject?
			do {
				try theURL.getResourceValue(&isDirectory, forKey:NSURLIsDirectoryKey)
			} catch _ {
			}

			if let isDirectory = isDirectory as? Bool where isDirectory {
				if let lastComponent = theURL.lastPathComponent, directories = context.request.directories {
					if directories.contains(lastComponent) {
						context.remove(theURL)
						dirEnumerator.skipDescendents()
					}
				}
			}
		}
	}

	func thinFile(url: NSURL, context: HelperContext, lipo: Lipo) {
		var sizeDiff: Int = 0
		if lipo.run(path: url.path!, sizeDiff: &sizeDiff) {
			if sizeDiff > 0 {
				context.reportProgress(url: url, size:sizeDiff)
			}
		}
	}

	func thinDirectory(_ url: NSURL, context:HelperContext, lipo: Lipo) {
		iterateDirectory(url, context:context, prefetchedProperties:[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsExecutableKey,NSURLIsApplicationKey]) { theURL, dirEnumerator in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [NSURLIsRegularFileKey, NSURLIsExecutableKey, NSURLIsApplicationKey])
				if let isExecutable = resourceValues[NSURLIsExecutableKey] as? Bool, isRegularFile = resourceValues[NSURLIsRegularFileKey] as? Bool where isExecutable && isRegularFile && !context.isFileBlacklisted(theURL) {
					if let pathExtension = theURL.pathExtension where pathExtension == "class" {
						return
					}

					let data = try NSData(contentsOf:theURL, options:([.dataReadingMappedAlways, .dataReadingUncached]))
					var magic: UInt32 = 0
					if data.length >= sizeof(UInt32) {
						data.getBytes(&magic, length: sizeof(UInt32))

						if magic == FAT_MAGIC || magic == FAT_CIGAM {
							self.thinFile(url: theURL, context:context, lipo: lipo)
						}
						if context.request.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
							self.stripFile(theURL, context:context)
						}
					}
				} else if let isApplication = resourceValues[NSURLIsApplicationKey] as? Bool where isApplication {
					// don't thin universal frameworks contained in a single-architecture application
					// see https://github.com/IngmarStein/Monolingual/issues/67
					let bundle = NSBundle(url: theURL)
					if let bundle = bundle, executableArchitectures = bundle.executableArchitectures where executableArchitectures.count == 1 {
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

	func hasCodeSignature(url: NSURL) -> Bool {
		var codeRef: SecStaticCode?
		let result = SecStaticCodeCreateWithPath(url, [], &codeRef)
		if result == errSecSuccess, let codeRef = codeRef {
			var requirement: SecRequirement?
			let result2 = SecCodeCopyDesignatedRequirement(codeRef, [], &requirement)
			return result2 == errSecSuccess
		}
		return false
	}

	func stripFile(_ url: NSURL, context:HelperContext) {
		// do not modify executables with code signatures
		if !hasCodeSignature(url: url) {
			do {
				let attributes = try context.fileManager.attributesOfItem(atPath: url.path!)
				let path = url.path!
				var size: AnyObject?
				do {
					try url.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey)
				} catch _ {
					try! url.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey)
				}

				let oldSize = size as! Int

				let task = NSTask.launchedTask(withLaunchPath: "/usr/bin/strip", arguments: ["-u", "-x", "-S", "-", path])
				task.waitUntilExit()

				if task.terminationStatus != EXIT_SUCCESS {
					NSLog("/usr/bin/strip failed with exit status %d", task.terminationStatus)
				}

				let newAttributes = [
					NSFileOwnerAccountID : attributes[NSFileOwnerAccountID]!,
					NSFileGroupOwnerAccountID : attributes[NSFileGroupOwnerAccountID]!,
					NSFilePosixPermissions : attributes[NSFilePosixPermissions]!
				]

				do {
					try context.fileManager.setAttributes(newAttributes, ofItemAtPath:path)
				} catch let error as NSError {
					NSLog("Failed to set file attributes for '%@': %@", path, error)
				}
				do {
					try url.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey)
				} catch _ {
					try! url.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey)
				}
				let newSize = size as! Int
				if oldSize > newSize {
					let sizeDiff = oldSize - newSize
					context.reportProgress(url: url, size:sizeDiff)
				}
			} catch let error as NSError {
				NSLog("Failed to get file attributes for '%@': %@", url, error)
			}
		}
	}

	// check if SIP is enabled, see https://github.com/IngmarStein/Monolingual/issues/74
	func checkRootless() -> Bool {
		let protectedDirectory = NSURL(fileURLWithPath: "/System/Monolingual.sip", isDirectory: true)
		let fileManager = NSFileManager.defaultManager()

		do {
			try fileManager.createDirectory(at: protectedDirectory, withIntermediateDirectories: false, attributes: nil)
		} catch {
			return true
		}

		do {
			try fileManager.removeItem(at: protectedDirectory)
		} catch let error as NSError {
			NSLog("Failed to remove temporary file '%@': %@", protectedDirectory, error)
		}

		return false
	}
}
