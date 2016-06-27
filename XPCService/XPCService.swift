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

// TODO: remove the following as soon as the new logging API is available for Swift
var OS_LOG_DEFAULT = 0
func os_log_debug(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_error(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_info(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}

final class XPCService: NSObject, XPCServiceProtocol {
	private var helperToolConnection: NSXPCConnection?

	func bundledHelperVersion(reply: (String) -> Void) {
		reply(MonolingualHelperClient.bundledVersion!)
	}

	func installHelperTool(withReply reply: (NSError?) -> Void) {
		do {
			try MonolingualHelperClient.installWithPrompt(prompt: nil)
		} catch let error as SMJError {
			switch error {
			case SMJError.bundleNotFound, SMJError.unsignedBundle, SMJError.badBundleSecurity, SMJError.badBundleCodeSigningDictionary, SMJError.unableToBless:
				os_log_error(OS_LOG_DEFAULT, "Failed to bless helper. Error: \(error)")
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [ NSLocalizedDescriptionKey as NSString: NSLocalizedString("Failed to install helper utility.", comment: "") as NSString ]))
			case SMJError.authorizationDenied:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [ NSLocalizedDescriptionKey as NSString: NSLocalizedString("You entered an incorrect administrator password.", comment: "") as NSString ]))
			case SMJError.authorizationCanceled:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [ NSLocalizedDescriptionKey as NSString: NSLocalizedString("Monolingual is stopping without making any changes. Your OS has not been modified.", comment: "") as NSString ]))
			case SMJError.authorizationInteractionNotAllowed, SMJError.authorizationFailed:
				reply(NSError(domain: "XPCService", code: error.code, userInfo: [ NSLocalizedDescriptionKey as NSString: NSLocalizedString("Failed to authorize as an administrator.", comment: "") as NSString ]))
			}
		} catch {
			reply(NSError(domain: "XPCService", code: 0, userInfo: [ NSLocalizedDescriptionKey as NSString: NSLocalizedString("An unknown error occurred.", comment: "") as NSString ]))
		}
		reply(nil)
	}

	func connect(withReply reply: (NSXPCListenerEndpoint?) -> Void) {
		if helperToolConnection == nil {
			let connection = NSXPCConnection(machServiceName: "com.github.IngmarStein.Monolingual.Helper", options: .privileged)
			connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
			connection.invalidationHandler = {
				self.helperToolConnection = nil
			}
			connection.resume()
			helperToolConnection = connection
		}

		let helper = self.helperToolConnection!.remoteObjectProxyWithErrorHandler { error in
			os_log_error(OS_LOG_DEFAULT, "XPCService failed to connect to helper: %@", error)
			reply(nil)
		} as! HelperProtocol
		helper.connectWithEndpointReply { endpoint -> Void in
			reply(endpoint)
		}
	}

}
