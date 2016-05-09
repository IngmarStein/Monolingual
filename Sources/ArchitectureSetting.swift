//
//  ArchitectureSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

final class ArchitectureSetting: Setting {
	var name: String
	var displayName: String

	init(enabled: Bool, name: String, displayName: String) {
		self.name = name
		self.displayName = displayName

		super.init(enabled: enabled)
	}
}
