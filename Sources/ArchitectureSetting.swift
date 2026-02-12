//
//  ArchitectureSetting.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct ArchitectureSetting: Identifiable, Equatable {
	let id: UUID
	var enabled: Bool
	let name: String
	let displayName: String

	init(enabled: Bool, name: String, displayName: String) {
		self.id = UUID()
		self.enabled = enabled
		self.name = name
		self.displayName = displayName
	}
}
