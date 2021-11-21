//
//  Setting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 17.07.14.
//
//

import Foundation

// Cocoa Bindings requires NSObject
class Setting: NSObject, Identifiable {
	@objc dynamic var enabled: Bool = false
	var id: Int

	init(id: Int, enabled: Bool) {
		self.id = id
		self.enabled = enabled
	}
}
