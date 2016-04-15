//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

@objc protocol HelperProtocol {

	func connectWithEndpointReply(_ reply:(NSXPCListenerEndpoint) -> Void)
	func getVersionWithReply(_ reply:(String) -> Void)
	func uninstall()
	func exitWithCode(_ exitCode: Int)
	func processRequest(_ request: HelperRequest, progress: ProgressProtocol?, reply:(Int) -> Void)

}

@objc protocol ProgressProtocol {

	func processed(file: String, size: Int, appName: String?)

}