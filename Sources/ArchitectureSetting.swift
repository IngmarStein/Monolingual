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
	@objc dynamic var displayName: String

	init(id: Int, enabled: Bool, name: String, displayName: String) {
		self.name = name
		self.displayName = displayName

		super.init(id: id, enabled: enabled)
	}
}
