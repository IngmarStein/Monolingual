//
//  MonolingualHelperClient.swift
//  Monolingual
//
//  Created by Ingmar Stein on 12.07.14.
//
//

import Foundation
import SMJobKit

class MonolingualHelperClient : SMJClient {
	override class func serviceIdentifier() -> String {
		return "net.sourceforge.MonolingualHelper"
	}

	// the bridging of String to CFStringRef is broken in Xcode 6 beta 3
	// remove the function below when this is fixed
	class func cfIdentifier() -> CFStringRef {
		return "net.sourceforge.MonolingualHelper"
	}
}
