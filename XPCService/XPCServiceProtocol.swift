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
	func bundledHelperVersion(reply: (String) -> Void)
	func installHelperTool(withReply: (NSError?) -> Void)
	func connect(withReply: @escaping (NSXPCListenerEndpoint?) -> Void)
}
