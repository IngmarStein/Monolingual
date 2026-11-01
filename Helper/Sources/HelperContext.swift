//
//  HelperContext.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation
import OSLog

final class HelperContext: NSObject, FileManagerDelegate, @unchecked Sendable {
	var request: HelperRequest
	/// Reports progress to the app, which is on the other side of the XPC connection.
	var reportToClient: ((HelperReply) -> Void)?
	var progress: Progress?
	private var fileBlocklist = Set<URL>()
	let fileManager = FileManager()
	let isRootless: Bool
	let logger = Logger()

	init(_ request: HelperRequest, rootless: Bool) {
		self.request = request
		isRootless = rootless

		super.init()

		// exclude the user's trash directory
		setEffectiveUser(request.uid)
		for trashURL in fileManager.urls(for: .trashDirectory, in: [.userDomainMask]) {
			excludeDirectory(trashURL)
		}

		// exclude root's trash directory
		setEffectiveUser(0)
		for trashURL in fileManager.urls(for: .trashDirectory, in: [.userDomainMask]) {
			excludeDirectory(trashURL)
		}

		fileManager.delegate = self
	}

	/// Switches the process to `uid`, which is what a file has to be owned by to be moved to that
	/// user's trash.
	///
	/// `seteuid` is process-wide — every thread changes with it — so a failure here is not local to
	/// the caller: the daemon would go on running as the wrong user, and moving files to the trash
	/// would fail at the end of a removal that reported nothing wrong.
	private func setEffectiveUser(_ uid: uid_t) {
		if seteuid(uid) != 0 {
			logger.error("Failed to change to uid \(uid, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
		}
	}

	func isExcluded(_ url: URL) -> Bool {
		guard let excludes = request.excludes else {
			return false
		}

		let path = url.path
		return excludes.contains { exclude in
			// Excluding a directory excludes what is below it, and nothing else: comparing
			// plain prefixes would let "/bin" exclude "/binary" as well.
			path == exclude || path.hasPrefix(exclude.hasSuffix("/") ? exclude : exclude + "/")
		}
	}

	func excludeDirectory(_ url: URL) {
		if request.excludes != nil {
			request.excludes?.append(url.path)
		} else {
			request.excludes = [url.path]
		}
	}

	func isDirectoryBlocklisted(_ path: URL) -> Bool {
		if let bundle = Bundle(url: path), let bundleIdentifier = bundle.bundleIdentifier, let bundleBlocklist = request.bundleBlocklist {
			return bundleBlocklist.contains(bundleIdentifier)
		}
		return false
	}

	func isFileBlocklisted(_ url: URL) -> Bool {
		fileBlocklist.contains(url)
	}

	private func addFileDictionaryToBlocklist(_ files: [String: AnyObject], baseURL: URL) {
		for (key, value) in files {
			if let valueDict = value as? [String: AnyObject], let optional = valueDict["optional"] as? Bool, optional {
				continue
			}
			fileBlocklist.insert(baseURL.appendingPathComponent(key))
		}
	}

	func addCodeResourcesToBlocklist(_ url: URL) {
		var codeRef: SecStaticCode?
		// This call might print "MacOS error: -67028" to the console (harmless, but annoying)
		// See rdar://33203786
		let result = SecStaticCodeCreateWithPath(url as CFURL, [], &codeRef)
		if result == errSecSuccess, let code = codeRef {
			var codeInfoRef: CFDictionary?
			// warning: this relies on kSecCSInternalInformation
			let secCSInternalInformation = SecCSFlags(rawValue: 1)
			let result2 = SecCodeCopySigningInformation(code, secCSInternalInformation, &codeInfoRef)
			if result2 == errSecSuccess, let codeInfo = codeInfoRef as? [String: AnyObject] {
				if let resDir = codeInfo["ResourceDirectory"] as? [String: AnyObject] {
					let baseURL: URL

					let contentsDirectory = url.appendingPathComponent("Contents", isDirectory: true)
					if fileManager.fileExists(atPath: contentsDirectory.path) {
						baseURL = contentsDirectory
					} else {
						baseURL = url
					}
					if let files = resDir["files"] as? [String: AnyObject] {
						addFileDictionaryToBlocklist(files, baseURL: baseURL)
					}

					// Version 2 Code Signature (introduced in Mavericks)
					// https://developer.apple.com/library/mac/technotes/tn2206
					if let files = resDir["files2"] as? [String: AnyObject] {
						addFileDictionaryToBlocklist(files, baseURL: baseURL)
					}
				}
			}
		}
	}

	private func appNameForURL(_ url: URL) -> String? {
		let pathComponents = url.pathComponents
		for (i, pathComponent) in pathComponents.enumerated() where (pathComponent as NSString).pathExtension == "app" {
			if let bundleURL = NSURL.fileURL(withPathComponents: Array(pathComponents[0 ... i])) {
				if let bundle = Bundle(url: bundleURL) {
					var displayName: String?
					if let localization = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages).first,
					   let infoPlistStringsURL = bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: localization),
					   let strings = NSDictionary(contentsOf: infoPlistStringsURL) as? [String: String] {
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
			}
			return String(pathComponent[..<pathComponent.index(pathComponent.endIndex, offsetBy: -4)])
		}
		return nil
	}

	func reportProgress(url: URL, size: Int) {
		let appName = appNameForURL(url)

		if let progress = progress {
			progress.fileCompletedCount = (progress.fileCompletedCount ?? 0) + 1
			progress.fileURL = url
			progress.setUserInfoObject(size, forKey: ProgressUserInfoKey.sizeDifference)
			if let appName = appName {
				progress.setUserInfoObject(appName, forKey: ProgressUserInfoKey.appName)
			}
			progress.totalUnitCount += Int64(size)
			progress.completedUnitCount += Int64(size)

			// show the file progress even if it has zero bytes
			if size == 0 {
				progress.willChangeValue(for: \.completedUnitCount)
				progress.didChangeValue(for: \.completedUnitCount)
			}
		}

		reportToClient?(.progress(file: url.path, size: size, appName: appName))
	}

	func remove(_ url: URL) {
		var error: Error?
		if request.trash {
			if request.dryRun {
				return
			}

			var dstURL: NSURL?

			// trashItemAtURL does not call any delegate methods (radar 20481813)

			var fileSize: [URL: Int] = [:]

			// Nothing is changed while the tree is being walked: the walk can end in the early
			// return below, and attributes already set would stay set on a directory that is never
			// trashed — leaving a system directory owned by the user.

			// check if any file below `url` has been blocked and record sizes
			if let dirEnumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: nil) {
				for entry in dirEnumerator {
					guard let theURL = entry as? URL else { continue }
					if isFileBlocklisted(theURL) {
						return
					}

					do {
						let resourceValues = try theURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
						if let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize {
							fileSize[theURL] = size
						}
					} catch {}
				}
			}

			// change owner so that it can be moved to the user's trash
			// see https://github.com/IngmarStein/Monolingual/issues/110
			reown(url, uid: request.uid)

			// The parent has to be writable for the entry to be moved out of it, which means
			// changing the ownership of a directory the user did not ask to change. That is only
			// done when the parent is a real directory, and the descriptor is opened without
			// following a link, so a root that is itself a link does not hand the link's target — a
			// system directory, say — to the user. The attributes are read from, and put back
			// through, that same descriptor, so the restore reaches the directory that was changed
			// even if the path is replaced meanwhile. The restore is skipped when there is no
			// directory to restore, since there is then nothing that was changed.
			let parent = url.deletingLastPathComponent()
			let parentDescriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
			defer { if parentDescriptor >= 0 { close(parentDescriptor) } }
			var parentStatus = stat()
			let parentIsRealDirectory = parentDescriptor >= 0 && fstat(parentDescriptor, &parentStatus) == 0
			if parentIsRealDirectory {
				setOwner(parentDescriptor, uid: request.uid, path: parent.path)
			}

			// try to move the file to the user's trash
			var success = false
			setEffectiveUser(request.uid)
			do {
				try fileManager.trashItem(at: url, resultingItemURL: &dstURL)
				success = true
			} catch let error1 {
				error = error1
				logger.error("Could not move \(url.absoluteString, privacy: .public) to trash: \(error1.localizedDescription, privacy: .public)")
				success = false
			}
			setEffectiveUser(0)
			if !success {
				do {
					// move the file to root's trash
					try fileManager.trashItem(at: url, resultingItemURL: &dstURL)
					success = true
				} catch let error1 {
					error = error1
					success = false
				}
			}

			if parentIsRealDirectory {
				if fchown(parentDescriptor, parentStatus.st_uid, parentStatus.st_gid) != 0 {
					logger.error("Could not restore the owner of '\(parent.path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
				}
				if fchmod(parentDescriptor, parentStatus.st_mode & 0o7777) != 0 {
					logger.error("Could not restore the permissions of '\(parent.path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
				}
			}

			if success {
				for (url, size) in fileSize {
					reportProgress(url: url, size: size)
				}
			} else if let error = error {
				logger.error("Error trashing '\(url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
			}
		} else {
			do {
				try fileManager.removeItem(at: url)
			} catch let error1 {
				error = error1
				let nsError = error1 as NSError
				if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError.domain == NSPOSIXErrorDomain, underlyingError.code == Int(ENOTEMPTY) {
					// ignore non-empty directories (they might contain blocklisted files and cannot be removed)
				} else {
					logger.error("Error removing '\(url.path, privacy: .public)': \(nsError, privacy: .public)")
				}
			}
		}
	}

	/// The deepest the ownership walk descends. Every level costs a descriptor and a stack frame,
	/// and a localization directory is a handful of levels deep: a tree built to be deeper than
	/// this is not one worth risking the daemon's stack on.
	private static let maximumDepth = 64

	/// Hands `descriptor` to `uid` and makes it writable by them, which is what a directory needs
	/// to be for what it holds to be moved out of it into the user's trash.
	private func setOwner(_ descriptor: Int32, uid: uid_t, path: String) {
		if fchown(descriptor, uid, uid_t.max) != 0 {
			logger.error("Could not change the owner of '\(path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
		}
		if fchmod(descriptor, S_IRWXU) != 0 {
			logger.error("Could not change the permissions of '\(path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
		}
	}

	/// Changes the owner of `directory` and of everything below it to `uid`, never following a
	/// symbolic link.
	///
	/// The helper runs as root and the tree belongs to the user, so anything the walk above saw can
	/// be replaced before it is acted on. Every level is therefore opened with `O_NOFOLLOW`
	/// relative to the descriptor of the level above, and the change is made to that descriptor
	/// rather than to the path again: a link is skipped instead of resolved, and an entry swapped
	/// for a link after the walk cannot redirect the change to a target outside the tree.
	///
	/// `FileManager.setAttributes` is what this replaces, and it is what made the walk dangerous:
	/// it looks the path up again and follows a link at the end of it.
	private func reown(_ directory: URL, uid: uid_t) {
		let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
		guard descriptor >= 0 else {
			logger.error("Could not open '\(directory.path, privacy: .public)' to change its owner: \(String(cString: strerror(errno)), privacy: .public)")
			return
		}
		reown(directoryDescriptor: descriptor, uid: uid, path: directory.path, depth: 0)
		close(descriptor)
	}

	/// Takes ownership of `descriptor` and of what is below it. The caller owns `descriptor`.
	///
	/// The names come from `FileManager` rather than from `readdir`, and are only ever used
	/// relative to the descriptor: a name that no longer names an entry there fails the call, and
	/// one that does names an entry of the directory that was opened — not of whatever the path
	/// names by now. That is what keeps this out of the `unsafe` pointer handling `readdir` needs
	/// without giving up the descriptor.
	private func reown(directoryDescriptor descriptor: Int32, uid: uid_t, path: String, depth: Int) {
		setOwner(descriptor, uid: uid, path: path)

		let names: [String]
		do {
			names = try fileManager.contentsOfDirectory(atPath: path)
		} catch {
			logger.error("Could not read '\(path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
			return
		}

		for name in names {
			var status = stat()
			guard fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
				continue
			}

			switch status.st_mode & S_IFMT {
			case S_IFLNK:
				// A link is never followed, whatever it points at: it is not part of the tree that
				// is being handed over, and its target may be a file only root may own.
				continue
			case S_IFDIR:
				guard depth < Self.maximumDepth else {
					logger.error("Not changing the owner below '\(path, privacy: .public)/\(name, privacy: .public)': the tree is deeper than \(Self.maximumDepth, privacy: .public) levels")
					continue
				}
				let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
				guard child >= 0 else {
					logger.error("Could not open '\(path, privacy: .public)/\(name, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
					continue
				}
				reown(directoryDescriptor: child, uid: uid, path: path + "/" + name, depth: depth + 1)
				close(child)
			default:
				// Not opened: a device node is not something to open just to change its owner, and
				// `fchownat` does not follow the last component.
				if fchownat(descriptor, name, uid, uid_t.max, AT_SYMLINK_NOFOLLOW) != 0 {
					logger.error("Could not change the owner of '\(path, privacy: .public)/\(name, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
				}
			}
		}
	}

	private func fileManager(_: FileManager, shouldProcessItemAtURL url: URL) -> Bool {
		if request.dryRun || isFileBlocklisted(url) || (isRootless && url.isProtected) {
			return false
		}

		// TODO: it is wrong to report process here, deletion might fail
		do {
			let resourceValues = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
			if let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize {
				reportProgress(url: url, size: size)
			}
		} catch {}
		return true
	}

	// MARK: - NSFileManagerDelegate

	func fileManager(_ fileManager: FileManager, shouldRemoveItemAt url: URL) -> Bool {
		self.fileManager(fileManager, shouldProcessItemAtURL: url)
	}

	func fileManager(_: FileManager, shouldProceedAfterError _: Error, removingItemAt _: URL) -> Bool {
		// https://github.com/IngmarStein/Monolingual/issues/102
		// logger.error("Error removing '\(url.path, privacy: .public)': \(error as NSError, privacy: .public)")

		true
	}
}
