//
//  BlacklistEntry.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct BlacklistEntry {
	let bundle: String
	let languages: Bool
	let architectures: Bool

	init(dictionary: [NSObject: AnyObject]) {
		self.bundle = dictionary["bundle"] as? String ?? ""
		self.languages = dictionary["languages"]!.boolValue
		self.architectures = dictionary["architectures"]!.boolValue
	}
}
