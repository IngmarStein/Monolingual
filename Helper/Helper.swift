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

extension NSURL {
	func hasExtendedAttribute(attribute: String) -> Bool {
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
		#if swift(>=3.0)
		return NSBundle.main().object(forInfoDictionaryKey:"CFBundleVersion") as! String
		#else
		return NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleVersion") as! String
		#endif
	}

	override init() {
		listener = NSXPCListener(machServiceName: "com.github.IngmarStein.Monolingual.Helper")

		super.init()

		listener.delegate = self
		workerQueue.maxConcurrentOperationCount = 1
		isRootless = checkRootless()
		NSLog("isRootless=\(isRootless)")
	}

	func run() {
		NSLog("MonolingualHelper started")

		listener.resume()
		#if swift(>=3.0)
		timer = NSTimer.scheduledTimer(withTimeInterval: timeoutInterval, target: self, selector: #selector(Helper.timeout(_:)), userInfo: nil, repeats: false)
		NSRunLoop.current().run()
		#else
		timer = NSTimer.scheduledTimerWithTimeInterval(timeoutInterval, target: self, selector: #selector(Helper.timeout(_:)), userInfo: nil, repeats: false)
		NSRunLoop.currentRunLoop().run()
		#endif
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
			#if swift(>=3.0)
			try NSFileManager.defaultManager().removeItem(atPath: "/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try NSFileManager.defaultManager().removeItem(atPath: "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
			#else
			try NSFileManager.defaultManager().removeItemAtPath("/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try NSFileManager.defaultManager().removeItemAtPath("/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
			#endif
		} catch _ {
		}
	}

	func exitWithCode(exitCode: Int) {
		NSLog("exiting with exit status \(exitCode)")
		workerQueue.waitUntilAllOperationsAreFinished()
		exit(Int32(exitCode))
	}

	func processRequest(request: HelperRequest, progress remoteProgress: ProgressProtocol?, reply:(Int) -> Void) {
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
		#if swift(>=3.0)
		request.doStrip = request.doStrip && context.fileManager.fileExists(atPath: "/usr/bin/strip")
		#else
		request.doStrip = request.doStrip && context.fileManager.fileExistsAtPath("/usr/bin/strip")
		#endif

		#if swift(>=3.0)
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
		#else
		workerQueue.addOperationWithBlock {
			// delete regular files
			if let files = request.files {
				for file in files {
					if progress.cancelled {
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
						if progress.cancelled {
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
						if progress.cancelled {
							break
						}
						self.thinDirectory(root, context:context, lipo: lipo)
					}
				}
			}

			reply(progress.cancelled ? Int(EXIT_FAILURE) : Int(EXIT_SUCCESS))
		}
		#endif
	}

	//MARK: - NSXPCListenerDelegate

	func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		let helperRequestClass = HelperRequest.self as AnyObject as! NSObject
		let classes = Set([helperRequestClass])
		#if swift(>=3.0)
		let interface = NSXPCInterface(with: HelperProtocol.self)
		interface.setClasses(classes, for: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 0, ofReply: false)
		interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 1, ofReply: false)
		#else
		let interface = NSXPCInterface(withProtocol: HelperProtocol.self)
		interface.setClasses(classes, forSelector: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 0, ofReply: false)
		interface.setInterface(NSXPCInterface(withProtocol: ProgressProtocol.self), forSelector: #selector(Helper.processRequest(_:progress:reply:)), argumentIndex: 1, ofReply: false)
		#endif
		newConnection.exportedInterface = interface
		newConnection.exportedObject = self
		newConnection.resume()

		return true
	}

	//MARK: -

	private func iterateDirectory(url: NSURL, context:HelperContext, prefetchedProperties:[String], block:(NSURL, NSDirectoryEnumerator) -> Void) {
		#if swift(>=3.0)
		if let progress = context.progress where progress.isCancelled {
			return
		}
		#else
		if let progress = context.progress where progress.cancelled {
			return
		}
		#endif

		if context.isExcluded(url) || context.isDirectoryBlacklisted(url) || (isRootless && url.isProtected) {
			return
		}

		context.addCodeResourcesToBlacklist(url)

		#if swift(>=3.0)
		let dirEnumerator = context.fileManager.enumerator(at: url, includingPropertiesForKeys:prefetchedProperties, options:[], errorHandler:nil)
		#else
		let dirEnumerator = context.fileManager.enumeratorAtURL(url, includingPropertiesForKeys:prefetchedProperties, options:[], errorHandler:nil)
		#endif
		if let dirEnumerator = dirEnumerator {
			for entry in dirEnumerator {
				#if swift(>=3.0)
				if let progress = context.progress where progress.isCancelled {
					return
				}
				#else
				if let progress = context.progress where progress.cancelled {
					return
				}
				#endif
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

	func processDirectory(url: NSURL, context:HelperContext) {
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
		if lipo.run(url.path!, sizeDiff: &sizeDiff) {
			if sizeDiff > 0 {
				context.reportProgress(url, size:sizeDiff)
			}
		}
	}

	func thinDirectory(url: NSURL, context:HelperContext, lipo: Lipo) {
		iterateDirectory(url, context:context, prefetchedProperties:[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsExecutableKey,NSURLIsApplicationKey]) { theURL, dirEnumerator in
			do {
				#if swift(>=3.0)
				let resourceValues = try theURL.resourceValues(forKeys: [NSURLIsRegularFileKey, NSURLIsExecutableKey, NSURLIsApplicationKey])
				#else
				let resourceValues = try theURL.resourceValuesForKeys([NSURLIsRegularFileKey, NSURLIsExecutableKey, NSURLIsApplicationKey])
				#endif
				if let isExecutable = resourceValues[NSURLIsExecutableKey] as? Bool, isRegularFile = resourceValues[NSURLIsRegularFileKey] as? Bool where isExecutable && isRegularFile && !context.isFileBlacklisted(theURL) {
					if let pathExtension = theURL.pathExtension where pathExtension == "class" {
						return
					}

					#if swift(>=3.0)
					let data = try NSData(contentsOf:theURL, options:([.dataReadingMappedAlways, .dataReadingUncached]))
					#else
					let data = try NSData(contentsOfURL:theURL, options:([.DataReadingMappedAlways, .DataReadingUncached]))
					#endif
					var magic: UInt32 = 0
					if data.length >= sizeof(UInt32) {
						data.getBytes(&magic, length: sizeof(UInt32))

						if magic == FAT_MAGIC || magic == FAT_CIGAM {
							self.thinFile(theURL, context:context, lipo: lipo)
						}
						if context.request.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
							self.stripFile(theURL, context:context)
						}
					}
				} else if let isApplication = resourceValues[NSURLIsApplicationKey] as? Bool where isApplication {
					// don't thin universal frameworks contained in a single-architecture application
					// see https://github.com/IngmarStein/Monolingual/issues/67
					#if swift(>=3.0)
					let bundle = NSBundle(url: theURL)
					#else
					let bundle = NSBundle(URL: theURL)
					#endif
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
		#if swift(>=3.0)
		let flags = SecCSFlags.defaultFlags
		#else
		let flags = SecCSFlags.DefaultFlags
		#endif
		let result = SecStaticCodeCreateWithPath(url, flags, &codeRef)
		if result == errSecSuccess, let codeRef = codeRef {
			var requirement: SecRequirement?
			let result2 = SecCodeCopyDesignatedRequirement(codeRef, flags, &requirement)
			return result2 == errSecSuccess
		}
		return false
	}

	func stripFile(url: NSURL, context:HelperContext) {
		// do not modify executables with code signatures
		if !hasCodeSignature(url) {
			do {
				#if swift(>=3.0)
				let attributes = try context.fileManager.attributesOfItem(atPath: url.path!)
				#else
				let attributes = try context.fileManager.attributesOfItemAtPath(url.path!)
				#endif
				let path = url.path!
				var size: AnyObject?
				do {
					try url.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey)
				} catch _ {
					try! url.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey)
				}

				let oldSize = size as! Int

				#if swift(>=3.0)
				let task = NSTask.launchedTask(withLaunchPath: "/usr/bin/strip", arguments: ["-u", "-x", "-S", "-", path])
				#else
				let task = NSTask.launchedTaskWithLaunchPath("/usr/bin/strip", arguments:["-u", "-x", "-S", "-", path])
				#endif
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
					context.reportProgress(url, size:sizeDiff)
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
			#if swift(>=3.0)
			try fileManager.createDirectory(at: protectedDirectory, withIntermediateDirectories: false, attributes: nil)
			#else
			try fileManager.createDirectoryAtURL(protectedDirectory, withIntermediateDirectories: false, attributes: nil)
			#endif
		} catch {
			return true
		}

		do {
			#if swift(>=3.0)
			try fileManager.removeItem(at: protectedDirectory)
			#else
			try fileManager.removeItemAtURL(protectedDirectory)
			#endif
		} catch let error as NSError {
			NSLog("Failed to remove temporary file '%@': %@", protectedDirectory, error)
		}

		return false
	}
}
