//
//  HelperRequest.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

/// A body of work for the helper.
///
/// This crosses an XPC connection as a value, so it is a plain `Codable` struct rather than the
/// `NSSecureCoding` object the `NSXPCConnection` interface used to require.
public struct HelperRequest: Codable, Sendable, Equatable {
	public var dryRun = false
	public var doStrip = false
	public var uid: uid_t = 0
	public var trash = false
	public var includes: [String]?
	public var excludes: [String]?
	public var bundleBlocklist: Set<String>?
	public var directories: Set<String>?
	public var files: [String]?
	public var thin: [String]?

	public init() {}
}
