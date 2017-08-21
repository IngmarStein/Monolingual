//
//  BlacklistEntry.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct BlacklistEntry: Decodable {
	let bundle: String
	let languages: Bool
	let architectures: Bool
}
