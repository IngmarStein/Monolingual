//
//  LanguageSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct LanguageSetting: Identifiable, Equatable {
	let id: UUID
	var enabled: Bool
	let folders: [String]
	let displayName: String
	
	init(enabled: Bool, folders: [String], displayName: String) {
		self.id = UUID()
		self.enabled = enabled
		self.folders = folders
		self.displayName = displayName
	}
}
