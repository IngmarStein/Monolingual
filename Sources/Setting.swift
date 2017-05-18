//
//  Setting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 17.07.14.
//
//

import Foundation

// Cocoa Bindings requires NSObject
class Setting: NSObject {
	@objc dynamic var enabled: Bool = false

	init(enabled: Bool) {
		self.enabled = enabled
	}
}
