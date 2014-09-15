//
//  ArchitectureSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

class ArchitectureSetting : Setting {
	var name : String
	dynamic var displayName : String
	
	init(enabled : Bool, name : String, displayName : String) {
		self.name = name
		self.displayName = displayName
		
		super.init(enabled: enabled)
	}
}
