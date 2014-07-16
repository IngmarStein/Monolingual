//
//  LanguageSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

// Cocoa Bindings requires NSObject
class LanguageSetting : NSObject {
	var enabled: Bool
	var folders : [String]
	var displayName : String
	
	init(enabled : Bool, folders : [String], displayName : String) {
		self.enabled = enabled
		self.folders = folders
		self.displayName = displayName
	}
}
