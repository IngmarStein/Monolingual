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

	public var version: String {
		Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
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

		timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [self] _ in
			logger.info("timeout while waiting for request")
			exit(code: Int(EXIT_SUCCESS))
		}
		RunLoop.current.run()
	}

	/// Removes a helper that an older version of Monolingual installed with SMJobBless.
	///
	/// Helpers registered with SMAppService live inside the app bundle and are removed by
	/// unregistering them, so this only has to clean up after the SMJobBless based versions.
	public func uninstall() {
		do {
			try FileManager.default.removeItem(atPath: "/Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper")
			try FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist")
		} catch {}
	}

	/// Stops the running request and exits with `code`.
	public func exit(code: Int) {
		logger.info("exiting with exit status \(code, privacy: .public)")
		// Anything but success means the app cancelled, so the removal stops at the next file
		// instead of working through the whole tree first.
		currentProgress?.cancel()
		workerQueue.waitUntilAllOperationsAreFinished()
		Darwin.exit(Int32(code))
	}

	@discardableResult public func process(request: HelperRequest, report: ((HelperReply) -> Void)?, reply: @escaping (Int) -> Void) -> Progress {
		timer?.invalidate()

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
			// delete regular files
			if let files = pending.files {
				for file in files {
					if progress.isCancelled {
						break
					}
					context.remove(URL(fileURLWithPath: file, isDirectory: false))
				}
			}

			let roots = pending.includes?.map { URL(fileURLWithPath: $0, isDirectory: true) }

			if let roots = roots {
				// recursively delete directories
				if let directories = pending.directories, !directories.isEmpty {
					for root in roots {
						if progress.isCancelled {
							break
						}
						self.processDirectory(root, context: context)
					}
				}
			}

			// thin fat binaries
			if let archs = pending.thin, let roots = roots, !archs.isEmpty {
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
