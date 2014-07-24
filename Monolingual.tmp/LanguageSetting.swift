//
//  LanguageSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

class LanguageSetting : Setting {
	var folders : [String]
	var displayName : String
	
	init(enabled : Bool, folders : [String], displayName : String) {
		self.folders = folders
		self.displayName = displayName

		super.init(enabled: enabled)
	}
}
