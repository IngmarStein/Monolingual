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

final class Helper : NSObject, NSXPCListenerDelegate {

	private var listener: NSXPCListener

	var version: String {
		return NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleVersion") as! String
	}

	override init() {
		listener = NSXPCListener(machServiceName: "net.sourceforge.MonolingualHelper")

		super.init()

		listener.delegate = self
	}

	func run() {
		NSLog("MonolingualHelper started")

		listener.resume()
		NSRunLoop.currentRunLoop().run()
	}

	func connectWithEndpointReply(reply:(NSXPCListenerEndpoint) -> Void) {
		reply(listener.endpoint)
	}

	func getVersionWithReply(reply:(String) -> Void) {
		reply(version)
	}

	// see https://devforums.apple.com/message/1004420#1004420
	func uninstall() {
		//let removeTask = NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["remove", "net.sourceforge.MonolingualHelper"])
		let unloadTask = NSTask.launchedTaskWithLaunchPath("/bin/launchctl", arguments: ["unload", "-wF", "/Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist"])
		NSFileManager.defaultManager().removeItemAtPath("/Library/PrivilegedHelperTools/net.sourceforge.MonolingualHelper", error: nil)
		NSFileManager.defaultManager().removeItemAtPath("/Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist", error: nil)
	}

	func exitWithCode(exitCode: Int) {
		NSLog("exiting with exit status \(exitCode)")
		exit(Int32(exitCode))
	}

	func processRequest(request: HelperRequest, progress remoteProgress: ProgressProtocol, reply:(Int) -> Void) {
		let context = HelperContext(request)

		NSLog("Received request: %@", request)

		// https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/#10_10NSXPC
		let progress = NSProgress(totalUnitCount: -1)
		progress.completedUnitCount = 0
		progress.cancellationHandler = {
			NSLog("Stopping MonolingualHelper")
		}
		context.progress = progress
		context.remoteProgress = remoteProgress

		// check if /usr/bin/strip is present
		request.doStrip = request.doStrip && context.fileManager.fileExistsAtPath("/usr/bin/strip")

		// delete regular files
		if let files = request.files {
			for file in files {
				if progress.cancelled {
					break
				}
				if let url = NSURL(fileURLWithPath:file) {
					context.remove(url)
				}
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
					if let root = root {
						processDirectory(root, context:context)
					}
				}
			}
		}

		// thin fat binaries
		if let thin = request.thin, roots = roots where !thin.isEmpty {
			var archs = thin.map { ($0 as NSString).UTF8String }
			if setup_lipo(&archs, UInt32(archs.count)) != 0 {
				for root in roots {
					if progress.cancelled {
						break
					}
					if let root = root {
						thinDirectory(root, context:context)
					}
				}
				finish_lipo()
			}
		}

		reply(progress.cancelled ? Int(EXIT_FAILURE) : Int(EXIT_SUCCESS))
	}

	//MARK: - NSXPCListenerDelegate

	func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		let interface = NSXPCInterface(withProtocol: HelperProtocol.self)
		let helperRequestClass = HelperRequest.self as AnyObject as! NSObject
		let classes = Set([helperRequestClass])
		interface.setClasses(classes, forSelector: "processRequest:progress:reply:", argumentIndex: 0, ofReply: false)
		interface.setInterface(NSXPCInterface(withProtocol: ProgressProtocol.self), forSelector: "processRequest:progress:reply:", argumentIndex: 1, ofReply: false)
		newConnection.exportedInterface = interface
		newConnection.exportedObject = self
		newConnection.resume()

		return true
	}

	//MARK: -

	func processDirectory(url: NSURL, context:HelperContext) {
		if let progress = context.progress where progress.cancelled {
			return
		}

		let path = url.path

		if path == nil || context.isExcluded(url) || context.isDirectoryBlacklisted(url) {
			return
		}

		if path == "/dev" {
			return
		}

		if let dirEnumerator = context.fileManager.enumeratorAtURL(url, includingPropertiesForKeys:[NSURLIsDirectoryKey], options:.allZeros, errorHandler:nil) {
			for entry in dirEnumerator {
				if let progress = context.progress where progress.cancelled {
					return
				}
				let theURL = entry as! NSURL

				var isDirectory: AnyObject?
				theURL.getResourceValue(&isDirectory, forKey:NSURLIsDirectoryKey, error:nil)

				if let isDirectory = isDirectory as? Bool where isDirectory {
					if context.isExcluded(theURL) || context.isDirectoryBlacklisted(theURL) {
						dirEnumerator.skipDescendents()
						continue
					}

					context.addCodeResourcesToBlacklist(theURL)

					if let lastComponent = theURL.lastPathComponent {
						if context.request.directories.contains(lastComponent) {
							context.remove(theURL)
							dirEnumerator.skipDescendents()
						}
					}
				}
			}
		}
	}

	func thinFile(url: NSURL, context: HelperContext) {
		var sizeDiff: Int = 0
		if run_lipo(url.fileSystemRepresentation, &sizeDiff) == 0 {
			if sizeDiff > 0 {
				context.reportProgress(url, size:sizeDiff)
			}
		}
	}

	func thinDirectory(url: NSURL, context:HelperContext) {
		if let progress = context.progress where progress.cancelled {
			return
		}

		let path = url.path

		if path == nil || context.isExcluded(url) || context.isDirectoryBlacklisted(url) {
			return
		}

		if path == "/dev" {
			return
		}

		if let dirEnumerator = context.fileManager.enumeratorAtURL(url, includingPropertiesForKeys:[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsExecutableKey], options:.allZeros, errorHandler:nil) {
			for entry in dirEnumerator {
				let theURL = entry as! NSURL
				if let progress = context.progress where progress.cancelled {
					return
				}

				var isDirectory: AnyObject?
				var isRegularFile: AnyObject?
				var isExecutable: AnyObject?

				theURL.getResourceValue(&isDirectory, forKey:NSURLIsDirectoryKey, error:nil)
				theURL.getResourceValue(&isRegularFile, forKey:NSURLIsRegularFileKey, error:nil)
				theURL.getResourceValue(&isExecutable, forKey:NSURLIsExecutableKey, error:nil)

				if let isDirectory = isDirectory as? Bool where isDirectory {
					if context.isDirectoryBlacklisted(theURL) {
						dirEnumerator.skipDescendents()
						continue
					}
					context.addCodeResourcesToBlacklist(theURL)
				} else if let isExecutable = isExecutable as? Bool, isRegularFile = isRegularFile as? Bool where isExecutable && isRegularFile {
					if !context.isFileBlacklisted(theURL) {
						var error: NSError?
						if let data = NSData(contentsOfURL:theURL, options:(.DataReadingMappedAlways | .DataReadingUncached), error:&error) {
							var magic: UInt32 = 0
							if data.length >= sizeof(UInt32) {
								data.getBytes(&magic, length: sizeof(UInt32))

								if magic == FAT_MAGIC || magic == FAT_CIGAM {
									thinFile(theURL, context:context)
								}
								if context.request.doStrip && (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
									stripFile(theURL, context:context)
								}
							}
						}
					}
				}
			}
		}
	}

	func hasCodeSignature(url: NSURL) -> Bool {
		var codeRef: Unmanaged<SecStaticCode>?

		let result = SecStaticCodeCreateWithPath(url, SecCSFlags(kSecCSDefaultFlags), &codeRef)
		if result == noErr, let codeRef = codeRef?.takeRetainedValue() {
			var requirement: Unmanaged<SecRequirement>?
			let result2 = SecCodeCopyDesignatedRequirement(codeRef, SecCSFlags(kSecCSDefaultFlags), &requirement)
			return result2 == noErr
		}
		return false
	}

	func stripFile(url: NSURL, context:HelperContext) {
		var error: NSError?
		// do not modify executables with code signatures
		if !hasCodeSignature(url), let attributes = context.fileManager.attributesOfItemAtPath(url.path!, error:&error) {
			let path = url.path!
			var size: AnyObject?
			if !url.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey, error:nil) {
				url.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey, error:nil)
			}
			let oldSize = size as! Int

			let task = NSTask.launchedTaskWithLaunchPath("/usr/bin/strip", arguments:["-u", "-x", "-S", "-", path])
			task.waitUntilExit()

			if task.terminationStatus != EXIT_SUCCESS {
				NSLog("/usr/bin/strip failed with exit status %d", task.terminationStatus)
			}

			let newAttributes = [ NSFileOwnerAccountID : attributes[NSFileOwnerAccountID]!,
								  NSFileGroupOwnerAccountID : attributes[NSFileGroupOwnerAccountID]!,
								  NSFilePosixPermissions : attributes[NSFilePosixPermissions]!
								]

			if !context.fileManager.setAttributes(newAttributes, ofItemAtPath:path, error:&error) {
				NSLog("Failed to set file attributes for '%@': %@", path, error!)
			}
			if !url.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey, error:nil) {
				url.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey, error:nil)
			}
			let newSize = size as! Int
			if oldSize > newSize {
				let sizeDiff = oldSize - newSize
				context.reportProgress(url, size:sizeDiff)
			}
		}
	}
}
