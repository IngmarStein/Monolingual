//
//  LanguageSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

final class LanguageSetting: Setting {
	var folders: [String]
	@objc var displayName: String

	init(id: Int, enabled: Bool, folders: [String], displayName: String) {
		self.folders = folders
		self.displayName = displayName

		super.init(id: id, enabled: enabled)
	}
}
