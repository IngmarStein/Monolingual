//
//  HelperContext.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

final class HelperContext : NSObject, NSFileManagerDelegate {

	var request: HelperRequest
	var remoteProgress: ProgressProtocol?
	var progress: NSProgress?
	private var fileBlacklist = Set<NSURL>()
	var fileManager = NSFileManager()

	init(_ request: HelperRequest) {
		self.request = request

		super.init()

		fileManager.delegate = self
	}

	func isExcluded(url: NSURL) -> Bool {
		if let path = url.path, excludes = request.excludes {
			for exclude in excludes {
				if path.hasPrefix(exclude) {
					return true
				}
			}
		}
		return false
	}

	func isDirectoryBlacklisted(path: NSURL) -> Bool {
		if let bundle = NSBundle(URL: path), bundleIdentifier = bundle.bundleIdentifier, bundleBlacklist = request.bundleBlacklist {
			return bundleBlacklist.contains(bundleIdentifier)
		}
		return false
	}

	func isFileBlacklisted(url: NSURL) -> Bool {
		return fileBlacklist.contains(url)
	}

	private func addFileDictionaryToBlacklist(files: [String:AnyObject], baseURL:NSURL) {
		for (key, value) in files {
			if let valueDict = value as? [String:AnyObject], optional = valueDict["optional"] as? Bool where optional {
				continue
			}
			fileBlacklist.insert(baseURL.URLByAppendingPathComponent(key))
		}
	}

	func addCodeResourcesToBlacklist(url: NSURL) {
		var codeRef: Unmanaged<SecStaticCode>? = nil
		let result = SecStaticCodeCreateWithPath(url, SecCSFlags(kSecCSDefaultFlags), &codeRef)
		if result == errSecSuccess, let code = codeRef?.takeRetainedValue() {
			var codeInfoRef: Unmanaged<CFDictionary>? = nil
			// warning: this relies on kSecCSInternalInformation
			let result2 = SecCodeCopySigningInformation(code, SecCSFlags(kSecCSInternalInformation), &codeInfoRef)
			if result2 == errSecSuccess, let codeInfo = codeInfoRef?.takeRetainedValue() as? [NSObject:AnyObject] {
				if let resDir = codeInfo["ResourceDirectory"] as? [NSObject:AnyObject] {
					let contentsDirectory = url.URLByAppendingPathComponent("Contents", isDirectory: true)
					let baseURL: NSURL
					if let path = contentsDirectory.path where fileManager.fileExistsAtPath(path) {
						baseURL = contentsDirectory
					} else {
						baseURL = url
					}
					if let files = resDir["files"] as? [String:AnyObject] {
						addFileDictionaryToBlacklist(files, baseURL: baseURL)
					}
					// Version 2 Code Signature (introduced in Mavericks)
					// https://developer.apple.com/library/mac/technotes/tn2206
					if let files = resDir["files2"] as? [String:AnyObject] {
						addFileDictionaryToBlacklist(files, baseURL: baseURL)
					}
				}
			}
		}
	}

	private func appNameForURL(url: NSURL) -> String? {
		let pathComponents = url.pathComponents as! [String]
		for (i, pathComponent) in enumerate(pathComponents) {
			if pathComponent.pathExtension == "app" {
				if let bundleURL = NSURL.fileURLWithPathComponents(Array(pathComponents[0...i])), bundle = NSBundle(URL: bundleURL) {
					var displayName: String?
					if let bundleLocalizations = bundle.localizations,
						localization = NSBundle.preferredLocalizationsFromArray(bundleLocalizations, forPreferences: NSLocale.preferredLanguages()).first as? String,
						infoPlistStringsURL = bundle.URLForResource("InfoPlist", withExtension: "strings", subdirectory: nil, localization: localization),
						strings = NSDictionary(contentsOfURL: infoPlistStringsURL) as? [String:String] {
						displayName = strings["CFBundleDisplayName"]
					}
					if displayName == nil {
						// seems not to be localized?!?
						displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
					}
					if let displayName = displayName {
						return displayName
					}
				}
				return pathComponent.substringToIndex(advance(pathComponent.endIndex, -4))
			}
		}
		return nil
	}

	func reportProgress(url: NSURL, size:Int) {
		let appName = appNameForURL(url)
		if let progress = progress {
			let count = progress.userInfo?[NSProgressFileCompletedCountKey] as? Int ?? 0
			progress.setUserInfoObject(count + 1, forKey:NSProgressFileCompletedCountKey)
			progress.setUserInfoObject(url, forKey:NSProgressFileURLKey)
			if let appName = appName {
				progress.setUserInfoObject(appName, forKey: "appName")
			}
			progress.completedUnitCount += size
		}
		if let progress = remoteProgress {
			progress.processed(url.path!, size: size, appName: appName)
		}
	}

	func remove(url: NSURL) {
		var error: NSError? = nil
		if request.trash {
			if request.dryRun {
				return
			}

			var dstURL: NSURL? = nil

			// trashItemAtURL does not call any delegate methods (radar 20481813)

			// check if any file in below url has been blacklisted
			if let dirEnumerator = fileManager.enumeratorAtURL(url, includingPropertiesForKeys:nil, options:.allZeros, errorHandler:nil) {
				for entry in dirEnumerator {
					let theURL = entry as! NSURL
					if isFileBlacklisted(theURL) {
						return
					}
				}
			}

			// try to move the file to the user's trash
			var success = false
			seteuid(request.uid)
			success = fileManager.trashItemAtURL(url, resultingItemURL:&dstURL, error:&error)
			seteuid(0)
			if !success {
				// move the file to root's trash
				success = self.fileManager.trashItemAtURL(url, resultingItemURL:&dstURL, error:&error)
			}

			if success {
				if let dirEnumerator = fileManager.enumeratorAtURL(url, includingPropertiesForKeys:[NSURLTotalFileAllocatedSizeKey, NSURLFileAllocatedSizeKey], options:.allZeros, errorHandler:nil) {
					for entry in dirEnumerator {
						let theURL = entry as! NSURL
						var size: AnyObject?
						if !theURL.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey, error:nil) {
							theURL.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey, error:nil)
						}
						if let size = size as? Int {
							reportProgress(theURL, size:size)
						}
					}
				}
			} else if let error = error {
				NSLog("Error trashing '%s': %@", url.fileSystemRepresentation, error)
			}
		} else {
			if !self.fileManager.removeItemAtURL(url, error:&error) {
				if let error = error {
					NSLog("Error removing '%s': %@", url.fileSystemRepresentation, error)
				}
			}
		}
	}

	private func fileManager(fileManager: NSFileManager, shouldProcessItemAtURL URL:NSURL) -> Bool {
		if request.dryRun || isFileBlacklisted(URL) {
			return false
		}

		var size: AnyObject?
		if !URL.getResourceValue(&size, forKey:NSURLTotalFileAllocatedSizeKey, error:nil) {
			URL.getResourceValue(&size, forKey:NSURLFileAllocatedSizeKey, error:nil)
		}

		if let size = size as? Int {
			reportProgress(URL, size:size)
		}

		return true
	}

	//MARK: - NSFileManagerDelegate

	func fileManager(fileManager: NSFileManager, shouldRemoveItemAtURL URL: NSURL) -> Bool {
		return self.fileManager(fileManager, shouldProcessItemAtURL:URL)
	}

}
