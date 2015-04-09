//
//  XPCService.swift
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

import Foundation
import XPC

class XPCService: NSObject, XPCServiceProtocol {
	var helperToolConnection: NSXPCConnection?

	func bundledHelperVersion(reply:(String) -> Void) {
		reply(MonolingualHelperClient.bundledVersion!)
	}

	func installHelperTool(reply:(NSError?) -> Void) {
		var error : NSError? = nil
		MonolingualHelperClient.installWithPrompt(nil, error:&error)
		reply(error)
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
