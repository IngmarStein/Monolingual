//
//  Root.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct Root {
	let path : String
	let languages : Bool
	let architectures : Bool
	
	init(dictionary: [NSObject:AnyObject]) {
		self.path = dictionary["Path"] as NSString
		self.languages = dictionary["Languages"]!.boolValue
		self.architectures = dictionary["Architectures"]!.boolValue
	}
}
