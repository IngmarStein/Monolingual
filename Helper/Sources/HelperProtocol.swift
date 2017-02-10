//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

@objc protocol HelperProtocol {

	func connectWithEndpointReply(_ reply: (NSXPCListenerEndpoint) -> Void)
	func getVersionWithReply(_ reply: (String) -> Void)
	func uninstall()
	func exitWithCode(_ exitCode: Int)
	func processRequest(_ request: HelperRequest, progress: ProgressProtocol?, reply: (Int) -> Void)

}

// This is a callback from the helper to the main app to report process
// Ideally, this would be unnecessary with remote Progress observation, but this
// seems to be broken in our setting (app <-> XPC <-> helper)
@objc protocol ProgressProtocol {

	func processed(file: String, size: Int, appName: String?)

}
