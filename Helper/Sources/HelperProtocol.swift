//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

public extension ProgressUserInfoKey {
	static let appName = ProgressUserInfoKey("MonolingualAppName")
	static let sizeDifference = ProgressUserInfoKey("MonolingualSizeDifference")
}

@objc public protocol HelperProtocol {
	func connect(_ reply: @escaping (NSXPCListenerEndpoint) -> Void)
	func getVersion(_ reply: @escaping (String) -> Void)
	func uninstall()
	func exit(code: Int)
	@discardableResult func process(request: HelperRequest, progress: ProgressProtocol?, reply: @escaping (Int) -> Void) -> Progress
}

// This shouldn't be necessary, but the cross-process Progress support seems to
// be broken as of macOS 10.14.
// See https://github.com/IngmarStein/Monolingual/issues/151
@objc public protocol ProgressProtocol {
	func processed(file: String, size: Int, appName: String?)
}
