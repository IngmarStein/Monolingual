//
//  ArchitectureSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

// Cocoa Bindings requires NSObject
class ArchitectureSetting : NSObject {
	var enabled: Bool
	var name : String
	var displayName : String
	
	init(enabled : Bool, name : String, displayName : String) {
		self.enabled = enabled
		self.name = name
		self.displayName = displayName
	}
}
