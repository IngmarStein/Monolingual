//
//  XPCServiceProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 08.04.15.
//
//

import Foundation
import XPC

@objc protocol XPCServiceProtocol {
	func bundledHelperVersion(reply: @escaping (String) -> Void)
	func installHelperTool(withReply: @escaping (NSError?) -> Void)
	func connect(withReply: @escaping (NSXPCListenerEndpoint?) -> Void)
	func disconnect()
}
