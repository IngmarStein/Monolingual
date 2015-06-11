//
//  XPCService.swift
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

import Foundation
import SMJobKit
import XPC

final class XPCService: NSObject, XPCServiceProtocol {
	private var helperToolConnection: NSXPCConnection?

	func bundledHelperVersion(reply:(String) -> Void) {
		reply(MonolingualHelperClient.bundledVersion!)
	}

	func installHelperTool(reply:(NSError?) -> Void) {
		var error : NSError? = nil
		MonolingualHelperClient.installWithPrompt(nil, error:&error)
		if let error = error {
			let errorCode = ErrorCode(rawValue:error.code)!
			switch errorCode {
			case .BundleNotFound, .UnsignedBundle, .BadBundleSecurity, .BadBundleCodeSigningDictionary, .UnableToBless:
				NSLog("Failed to bless helper. Error: \(error)")
				reply(NSError(domain:"XPCService", code:error.code, userInfo:[ NSLocalizedDescriptionKey:NSLocalizedString("Failed to install helper utility.", comment:"") ]))
			case .AuthorizationDenied:
				reply(NSError(domain:"XPCService", code:error.code, userInfo:[ NSLocalizedDescriptionKey:NSLocalizedString("You entered an incorrect administrator password.", comment:"") ]))
			case .AuthorizationCanceled:
				reply(NSError(domain:"XPCService", code:error.code, userInfo:[ NSLocalizedDescriptionKey:NSLocalizedString("Monolingual is stopping without making any changes. Your OS has not been modified.", comment:"") ]))
			case .AuthorizationInteractionNotAllowed, .AuthorizationFailed:
				reply(NSError(domain:"XPCService", code:error.code, userInfo:[ NSLocalizedDescriptionKey:NSLocalizedString("Failed to authorize as an administrator.", comment:"") ]))
			}
		}
		reply(nil)
	}

	func connect(reply:(NSXPCListenerEndpoint?) -> Void) {
		if helperToolConnection == nil {
			let connection = NSXPCConnection(machServiceName: "net.sourceforge.MonolingualHelper", options: .Privileged)
			connection.remoteObjectInterface = NSXPCInterface(withProtocol:HelperProtocol.self)
			connection.invalidationHandler = {
				self.helperToolConnection = nil
			}
			connection.resume()
			helperToolConnection = connection
		}

		let helper = self.helperToolConnection!.remoteObjectProxyWithErrorHandler() { error in
			NSLog("XPCService failed to connect to helper: %@", error)
			reply(nil)
		} as! HelperProtocol
		helper.connectWithEndpointReply() { endpoint -> Void in
			reply(endpoint)
		}
	}

}
