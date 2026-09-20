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

/// Names and paths of the privileged helper, shared by the app and the helper itself.
public enum HelperService {
	/// The Mach service the helper serves and the app connects to.
	public static let machServiceName = "com.github.IngmarStein.Monolingual.PrivilegedHelper"

	/// Name of the launchd property list inside the app bundle.
	public static let daemonPlistName = "com.github.IngmarStein.Monolingual.PrivilegedHelper.plist"

	/// The Mach service served by helpers that older versions installed with SMJobBless.
	///
	/// It deliberately differs from `machServiceName`: a job left over in
	/// `/Library/LaunchDaemons` keeps the Mach service of its own name, and launchd prefers it
	/// over a daemon registered with SMAppService. Those helpers are only contacted once, to
	/// remove them.
	public static let legacyMachServiceName = "com.github.IngmarStein.Monolingual.Helper"

	/// Files left behind by the SMJobBless based versions of Monolingual.
	public static let legacyPaths = [
		"/Library/PrivilegedHelperTools/\(legacyMachServiceName)",
		"/Library/LaunchDaemons/\(legacyMachServiceName).plist"
	]
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
