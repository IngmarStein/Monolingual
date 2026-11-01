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
import XPC
#if canImport(LipoCore)
import LipoCore
#endif

extension URL {
	func hasExtendedAttribute(_ attribute: String) -> Bool {
		getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) != -1
	}

	var isProtected: Bool {
		hasExtendedAttribute("com.apple.rootless")
	}
}

public final class Helper: @unchecked Sendable {
	/// The queue messages are handled on. The work itself runs on `workerQueue` instead, so a
	/// second message — the app cancelling — is still handled while a removal is running.
	/// Sessions inherit this queue, which is what keeps everything below it serialized.
	private let messageQueue = DispatchQueue(label: "com.github.IngmarStein.Monolingual.Helper.messages")
	private let workerQueue = OperationQueue()
	private var listener: XPCListener?
	/// The session the app opened. Held on to, because the session lives only as long as this
	/// reference does.
	private var clientSession: XPCSession?
	/// The app's listener, which progress and the result are reported on.
	private var progressSession: XPCSession?
	/// The bookkeeping of the running request, so that the app can still cancel it.
	private var currentProgress: Progress?
	private var timer: Timer?
	private let timeoutInterval = TimeInterval(30.0)
	private var isRootless = true
	private let logger = Logger()

	/// The version of the Monolingual whose helper this is.
	///
	/// The helper is an executable in `Contents/MacOS` of the app bundle. For such an executable
	/// `Bundle.main` names the enclosing `.app` but answers `object(forInfoDictionaryKey:)` from
	/// the info dictionary compiled into the executable, which would make the app and its helper
	/// carry a version each — two hardcoded strings that a release has to bump together. The
	/// app's info dictionary is what the app compares against, so it is read here, and the
	/// version of the helper itself is only the fallback for running the binary on its own.
	public var version: String {
		let appPlist = Bundle.main.bundleURL.appending(path: "Contents/Info.plist")
		if let data = try? Data(contentsOf: appPlist),
		   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
		   let version = plist[kCFBundleVersionKey as String] as? String {
			return version
		}
		return Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "vUNKNOWN"
	}

	public init() {
		workerQueue.maxConcurrentOperationCount = 1
		isRootless = checkRootless()
		logger.debug("isRootless=\(self.isRootless ? "true" : "false", privacy: .public)")
	}

	public func run() {
		logger.info("MonolingualHelper \(self.version, privacy: .public) started")

		do {
			// XPC checks the peer against this requirement before a session is handed over,
			// for every session — no pid to look up, and no window to reuse one in.
			//
			// A listener listens as soon as it is created; there is no `activate()` to call
			// here, and calling one would be an API misuse crash.
			listener = try XPCListener(service: HelperService.machServiceName,
			                           targetQueue: messageQueue,
			                           requirement: HelperService.appPeerRequirement) { [self] request in
				accept(request)
			}
		} catch {
			logger.error("Failed to serve \(HelperService.machServiceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
			Darwin.exit(EXIT_FAILURE)
		}

		startIdleTimer()
		RunLoop.current.run()
	}

	/// Starts the timeout that exits the daemon when it has nothing to do.
	///
	/// The timer belongs on the main run loop, which is the one `run()` keeps running: on the
	/// message queue — where requests arrive — a timer would be added to a run loop nobody runs.
	private func startIdleTimer() {
		DispatchQueue.main.async { [self] in
			timer?.invalidate()
			let timer = Timer(timeInterval: timeoutInterval, repeats: false) { [self] _ in
				logger.info("timeout while waiting for request")
				exit(code: Int(EXIT_SUCCESS))
			}
			RunLoop.main.add(timer, forMode: .common)
			self.timer = timer
		}
	}

	/// Stops the timeout while a request is being served.
	private func stopIdleTimer() {
		DispatchQueue.main.async { [self] in
			timer?.invalidate()
			timer = nil
		}
	}

	/// Stops the running request and exits with `code`.
	public func exit(code: Int) {
		logger.info("exiting with exit status \(code, privacy: .public)")
		// Anything but success means the app cancelled. The removal then stops at the next place it
		// looks — before the next root, and before the next entry of a directory being walked —
		// rather than working through the whole tree first. A subtree already handed to
		// `removeItem` is not interrupted, so this can wait for a while yet.
		currentProgress?.cancel()
		workerQueue.waitUntilAllOperationsAreFinished()
		// `code` arrives over XPC: `Int32(_:)` would trap on a value out of range, and trapping
		// here would take the daemon down mid-removal instead of exiting cleanly.
		Darwin.exit(Int32(clamping: code))
	}

	@discardableResult public func process(request: HelperRequest, report: ((HelperReply) -> Void)?, reply: @escaping (Int) -> Void) -> Progress {
		stopIdleTimer()

		// check if /usr/bin/strip is present
		var request = request
		request.doStrip = request.doStrip && FileManager.default.fileExists(atPath: "/usr/bin/strip")

		let context = HelperContext(request, rootless: isRootless)

		logger.debug("Received request: \(String(describing: request), privacy: .public)")

		// Progress is no longer shared across processes: this object only tallies what was
		// removed, which is what the tests check and what the helper reports as messages.
		// `totalUnitCount` starts at one rather than being indeterminate so that its counts
		// always add up.
		let progress = Progress(totalUnitCount: 1)
		progress.completedUnitCount = 0
		progress.cancellationHandler = {
			self.logger.info("Stopping MonolingualHelper")
		}
		context.progress = progress
		context.reportToClient = report
		currentProgress = progress

		struct SendableReply: @unchecked Sendable {
			let reply: (Int) -> Void
		}
		let sendableReply = SendableReply(reply: reply)

		// The request is a value: settling `doStrip` before this point means the operation can
		// capture it as a constant instead of sharing a mutable one.
		let pending = request

		workerQueue.addOperation {
			let roots = pending.includes?.map { URL(fileURLWithPath: $0, isDirectory: true) }

			// recursively delete directories
			if let roots, let directories = pending.directories, !directories.isEmpty {
				for root in roots {
					if progress.isCancelled {
						break
					}
					self.processDirectory(root, context: context)
				}
			}

			// thin fat binaries
			if let archs = pending.thin, let roots, !archs.isEmpty {
				if let lipo = Lipo(archs: archs) {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.thinDirectory(root, context: context, lipo: lipo)
					}
				}
			}

			sendableReply.reply(progress.isCancelled ? Int(EXIT_FAILURE) : Int(EXIT_SUCCESS))

			// The daemon goes back to timing itself out, which is also what takes it down when
			// the app never asks it to exit.
			self.startIdleTimer()
		}

		return progress
	}

	// MARK: - Serving the app

	/// Serves a session the app opened.
	private func accept(_ request: XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision {
		let (decision, session) = request.accept { [self] dictionary in
			handle(dictionary)
		}
		// XPC crashes if a session is released while it is active, so the previous one is
		// cancelled before it is let go — the app opens a new one for every removal.
		clientSession?.cancel(reason: "another session arrived")
		clientSession = session
		return decision
	}

	/// Handles one message from the app and returns the reply to send, if the app waits for one.
	private func handle(_ dictionary: XPCDictionary) -> XPCDictionary? {
		// The app sends the endpoint for progress and the result on its own, before the request
		// those belong to. It does not wait for an answer.
		if let endpoint = HelperWire.endpoint(in: dictionary) {
			openProgressConnection(to: endpoint)
			return nil
		}

		guard let message = try? HelperWire.message(HelperMessage.self, in: dictionary) else {
			logger.error("Ignoring an XPC message without a payload")
			return nil
		}

		switch message {
		case .version:
			return reply(.version(version))
		case let .process(request):
			// The removal runs on the worker queue, so answer before starting it.
			start(request)
			return reply(.accepted)
		case let .exit(code):
			exit(code: code)
			return nil
		}
	}

	/// Opens the connection the app's endpoint stands for, to report progress and the result on.
	private func openProgressConnection(to endpoint: XPCEndpoint) {
		// XPC crashes if a session is released while it is active: the one from a previous
		// removal is cancelled before it is replaced.
		progressSession?.cancel(reason: "another request arrived")
		progressSession = nil

		do {
			// A peer requirement can only be attached to a session that is not active yet, so
			// the session is created inactive and activated after. Sessions created from the
			// listener do not inherit its requirement, hence attaching one here as well.
			let session = try XPCSession(endpoint: endpoint, options: .inactive)
			session.setPeerRequirement(HelperService.appPeerRequirement)
			try session.activate()
			progressSession = session
		} catch {
			logger.error("Failed to open the connection to the app: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Carries out `request`, reporting progress and the result to the app.
	private func start(_ request: HelperRequest) {
		// Read here, on the message queue, so that the reports capture the session rather than
		// reaching for it from the worker queue later.
		let session = progressSession
		let reportProgress: (HelperReply) -> Void = { [self] reply in
			self.report(reply, on: session)
		}
		let reportResult: (Int) -> Void = { [self] exitCode in
			self.report(.finished(exitCode: exitCode), on: session)
		}

		process(request: request, report: reportProgress, reply: reportResult)
	}

	private func report(_ reply: HelperReply, on session: XPCSession?) {
		guard let session = session else { return }
		do {
			try session.send(message: HelperWire.dictionary(for: reply))
		} catch {
			logger.error("Failed to report to the app: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func reply(_ reply: HelperReply) -> XPCDictionary? {
		do {
			return try HelperWire.dictionary(for: reply)
		} catch {
			logger.error("Failed to encode a reply: \(error.localizedDescription, privacy: .public)")
			return nil
		}
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
		iterateDirectory(url, context: context, prefetchedProperties: [.isDirectoryKey, .isSymbolicLinkKey]) { theURL, dirEnumerator in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

				// A symbolic link is never removed, whatever it resolves to. `remove` runs as root
				// and the ownership it sets follows a link, so an entry merely *named* like a
				// localization would otherwise hand its target to the user. Nothing here relies on
				// that today — Foundation reports a link as neither a directory nor a regular file,
				// which is what an entry has to be to get this far — but the check is what keeps it
				// true if that changes.
				if let isDirectory = resourceValues.isDirectory, isDirectory, resourceValues.isSymbolicLink != true {
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
		iterateDirectory(url, context: context, prefetchedProperties: [.isDirectoryKey, .isRegularFileKey, .isExecutableKey, .isApplicationKey, .isSymbolicLinkKey]) { theURL, _ in
			do {
				let resourceValues = try theURL.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey, .isApplicationKey, .isSymbolicLinkKey])
				// A link is not a file to rewrite, and both `strip` and the `lipo` write path follow
				// it: a symbolic link named like an executable would have its target rewritten.
				if let isExecutable = resourceValues.isExecutable, let isRegularFile = resourceValues.isRegularFile, isExecutable, isRegularFile, resourceValues.isSymbolicLink != true, !context.isFileBlocklisted(theURL) {
					if theURL.pathExtension == "class" {
						return
					}

					let data = try Data(contentsOf: theURL, options: [.alwaysMapped, .uncached])
					if data.count >= MemoryLayout<UInt32>.size {
						data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
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
		if hasCodeSignature(url: url) {
			return
		}

		let path = url.path
		let oldSize: Int
		do {
			let resourceValues = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
			oldSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0
		} catch {
			return
		}

		// The file is opened without following a link, and everything that changes it goes through
		// that descriptor. The walk above refuses a link, but the entry can be replaced by one
		// afterwards: `strip` takes a path, looks it up and follows a link at the end of it, and so
		// did the `setAttributes` that restored the ownership. A link swapped in for a file would
		// therefore have had its target rewritten and then handed to the user, both as root.
		let descriptor = open(path, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
		guard descriptor >= 0 else {
			return
		}
		defer { close(descriptor) }

		var status = stat()
		guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else {
			return
		}

		guard let stripped = strippedCopy(of: descriptor) else {
			return
		}
		defer {
			close(stripped.descriptor)
			try? context.fileManager.removeItem(atPath: stripped.directory)
		}

		guard copyFile(from: stripped.descriptor, to: descriptor) else {
			logger.error("Could not write the stripped file back to '\(path, privacy: .public)'")
			return
		}

		// Whatever of these the file system reports, from the descriptor and back to it: `strip`
		// rewrote the contents, so the ownership and mode the file had are put back as they were.
		if fchown(descriptor, status.st_uid, status.st_gid) != 0 {
			logger.error("Could not restore the owner of '\(path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
		}
		if fchmod(descriptor, status.st_mode & 0o7777) != 0 {
			logger.error("Could not restore the permissions of '\(path, privacy: .public)': \(String(cString: strerror(errno)), privacy: .public)")
		}

		do {
			let resourceValues = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
			let newSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0

			if oldSize > newSize {
				let sizeDiff = oldSize - newSize
				context.reportProgress(url: url, size: sizeDiff)
			}
		} catch {}
	}

	/// Runs `strip` over what `descriptor` holds, in a private directory, and returns the result as
	/// an open descriptor together with the directory that holds it. The caller closes the
	/// descriptor and removes the directory.
	///
	/// `strip` is given a copy rather than the file itself because it takes a path: it looks that
	/// path up and follows a link at the end of it, so a file swapped for a link after the walk
	/// would have had its target rewritten. A copy in a directory of our own has no such path.
	private func strippedCopy(of descriptor: Int32) -> (descriptor: Int32, directory: String)? {
		var template = Array("\(NSTemporaryDirectory())Monolingual.XXXXXX".utf8CString)
		guard let created = mkdtemp(&template) else {
			logger.error("Could not create a directory to strip a copy in: \(String(cString: strerror(errno)), privacy: .public)")
			return nil
		}
		let directory = String(cString: created)
		let copyPath = directory + "/copy"

		let copyDescriptor = open(copyPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		guard copyDescriptor >= 0, copyFile(from: descriptor, to: copyDescriptor) else {
			if copyDescriptor >= 0 {
				close(copyDescriptor)
			}
			try? FileManager.default.removeItem(atPath: directory)
			return nil
		}
		close(copyDescriptor)

		do {
			let process = try Process.run(URL(fileURLWithPath: "/usr/bin/strip", isDirectory: false), arguments: ["-u", "-x", "-S", "-", copyPath])
			process.waitUntilExit()

			if process.terminationStatus != EXIT_SUCCESS {
				logger.error("/usr/bin/strip failed with exit status \(process.terminationStatus, privacy: .public)")
				try? FileManager.default.removeItem(atPath: directory)
				return nil
			}
		} catch {
			logger.error("Could not run /usr/bin/strip: \(error.localizedDescription, privacy: .public)")
			try? FileManager.default.removeItem(atPath: directory)
			return nil
		}

		let strippedDescriptor = open(copyPath, O_RDONLY)
		guard strippedDescriptor >= 0 else {
			try? FileManager.default.removeItem(atPath: directory)
			return nil
		}
		return (strippedDescriptor, directory)
	}

	/// Copies `source` to `destination` through the descriptors, truncating `destination` first.
	private func copyFile(from source: Int32, to destination: Int32) -> Bool {
		guard lseek(source, 0, SEEK_SET) >= 0, lseek(destination, 0, SEEK_SET) >= 0, ftruncate(destination, 0) == 0 else {
			return false
		}

		let reader = FileHandle(fileDescriptor: source, closeOnDealloc: false)
		let writer = FileHandle(fileDescriptor: destination, closeOnDealloc: false)
		do {
			while let chunk = try reader.read(upToCount: 1 << 16), !chunk.isEmpty {
				try writer.write(contentsOf: chunk)
			}
			return true
		} catch {
			logger.error("Could not copy a file to strip: \(error.localizedDescription, privacy: .public)")
			return false
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
