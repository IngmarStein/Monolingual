//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

@objc protocol HelperProtocol {

	func connectWithEndpointReply(reply:(NSXPCListenerEndpoint) -> Void)
	func getVersionWithReply(reply:(String) -> Void)
	func uninstall()
	func exitWithCode(exitCode: Int)
	func processRequest(request: HelperRequest, reply:(Int) -> Void)

}
