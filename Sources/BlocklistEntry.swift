//
//  BlocklistEntry.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct BlocklistEntry: Decodable {
	let bundle: String
	let languages: Bool
	let architectures: Bool
}
