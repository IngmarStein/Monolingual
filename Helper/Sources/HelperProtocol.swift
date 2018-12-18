//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

extension ProgressUserInfoKey {
	public static let appName = ProgressUserInfoKey("MonolingualAppName")
	public static let sizeDifference = ProgressUserInfoKey("MonolingualSizeDifference")
}

@objc protocol HelperProtocol {

	func connect(_ reply: @escaping (NSXPCListenerEndpoint) -> Void)
	func getVersion(_ reply: @escaping (String) -> Void)
	func uninstall()
	func exit(code: Int)
	@discardableResult func process(request: HelperRequest, reply: @escaping (Int) -> Void) -> Progress

}
