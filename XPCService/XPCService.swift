//
//  XPCService.swift
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

import Foundation
import OSLog
import SMJobKit
import XPC

final class XPCService: NSObject, XPCServiceProtocol {
	private var helperToolConnection: NSXPCConnection?
	private let logger = Logger()

	func bundledHelperVersion(reply: @escaping (String) -> Void) {
		reply(MonolingualHelperClient.bundledVersion!)
	}

	func installHelperTool(withReply reply: @escaping (NSError?) -> Void) {
		do {
			try MonolingualHelperClient.installWithPrompt(prompt: nil)
		} catch let error as SMJError {
			switch error {
			case SMJError.bundleNotFound, SMJError.unsignedBundle, SMJError.badBundleSecurity, SMJError.badBundleCodeSigningDictionary:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to install helper utility.", comment: "")]))
			case let SMJError.unableToBless(blessError):
				logger.error("Failed to bless helper. Error: \(blessError.localizedDescription, privacy: .public)")
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to install helper utility.", comment: "")]))
			case SMJError.authorizationDenied:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("You entered an incorrect administrator password.", comment: "")]))
			case SMJError.authorizationCanceled:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Monolingual is stopping without making any changes.", comment: "")]))
			case SMJError.authorizationInteractionNotAllowed, SMJError.authorizationFailed:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to authorize as an administrator.", comment: "")]))
			}
		} catch {
			reply(NSError(domain: "XPCService", code: 0, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("An unknown error occurred.", comment: "")]))
		}
		reply(nil)
	}

	func connect(withReply reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
		if helperToolConnection == nil {
			let connection = NSXPCConnection(machServiceName: "com.github.IngmarStein.Monolingual.Helper", options: .privileged)
			connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
			connection.invalidationHandler = {
				self.helperToolConnection = nil
			}
			connection.resume()
			helperToolConnection = connection
		}

		guard let helper = helperToolConnection!.remoteObjectProxyWithErrorHandler({ error in
			self.logger.error("XPCService failed to connect to helper: \(error.localizedDescription, privacy: .public)")
			reply(nil)
		}) as? HelperProtocol else {
			reply(nil)
			return
		}
		helper.connect { endpoint -> Void in
			reply(endpoint)
		}
	}

	func disconnect() {
		helperToolConnection = nil
	}
}
