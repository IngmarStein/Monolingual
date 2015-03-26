//
//  MonolingualHelperClient.swift
//  Monolingual
//
//  Created by Ingmar Stein on 12.07.14.
//
//

import Foundation

class MonolingualHelperClient : SMJClient {
	override class func serviceIdentifier() -> String {
		return "net.sourceforge.MonolingualHelper"
	}

	// the bridging of String to CFString is broken in Xcode 6 beta 3
	// remove the function below when this is fixed (still broken in Xcode 6.3 beta 3)
	class func cfIdentifier() -> CFString {
		return "net.sourceforge.MonolingualHelper"
	}
}
