//
//  HelperProtocol.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation
import XPC

public extension ProgressUserInfoKey {
	static let appName = ProgressUserInfoKey("MonolingualAppName")
	static let sizeDifference = ProgressUserInfoKey("MonolingualSizeDifference")
}

/// Names and identities of the privileged helper, shared by the app and the helper itself.
public enum HelperService {
	/// The Mach service the helper serves and the app connects to.
	public static let machServiceName = "com.github.IngmarStein.Monolingual.PrivilegedHelper"

	/// Name of the launchd property list inside the app bundle.
	public static let daemonPlistName = "com.github.IngmarStein.Monolingual.PrivilegedHelper.plist"

	/// The signing identifier of the app. XPC only accepts sessions from code that is signed by
	/// the same team and carries this identifier.
	public static let appSigningIdentifier = "com.github.IngmarStein.Monolingual"

	/// The signing identifier of the helper.
	public static let helperSigningIdentifier = "com.github.IngmarStein.Monolingual.Helper"

	/// What the helper requires of its clients: the Monolingual app, signed by the same team.
	///
	/// This replaces the pid-based check the `NSXPCConnection` version needed, and unlike that one
	/// it is enforced by XPC itself, for every session, without a race.
	public static var appPeerRequirement: XPCPeerRequirement {
		.isFromSameTeam(andMatchesSigningIdentifier: appSigningIdentifier)
	}

	/// What the app requires of the helper it talks to.
	public static var helperPeerRequirement: XPCPeerRequirement {
		.isFromSameTeam(andMatchesSigningIdentifier: helperSigningIdentifier)
	}
}

/// What the app asks the helper to do. Sent as JSON in an XPC dictionary.
public enum HelperMessage: Codable, Sendable, Equatable {
	/// Report the version of the app bundle the helper belongs to.
	case version
	/// Carry out a request; progress and the result arrive on the endpoint sent with it.
	case process
	case uninstall
	case exit(Int)
}

/// What the helper sends back.
public enum HelperReply: Codable, Sendable, Equatable {
	case version(String)
	case progress(file: String, size: Int, appName: String?)
	case finished(exitCode: Int)
	/// The request has been accepted; the result follows as a `finished` reply.
	case accepted
}

/// Keys of the XPC dictionaries the two sides exchange.
///
/// A message travels as its JSON representation in `payload`, because XPC values and `Codable`
/// values are different worlds: the endpoint for progress and results is an XPC value, so it goes
/// in a key of its own.
public enum HelperMessageKey {
	public static let kind = "kind"
	public static let payload = "payload"
	public static let progress = "progress"
}
