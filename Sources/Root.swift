//
//  Root.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct Root: Identifiable, Equatable {
	let path: String
	var languages: Bool
	var architectures: Bool

	static var defaults: [[String: Any]] {
		let applications: [String: Any] = ["Path": "/Applications", "Languages": true, "Architectures": true]
		let localLibrary: [String: Any] = ["Path": "/Library", "Languages": true, "Architectures": true]
		return [applications, localLibrary]
	}

	init(dictionary: [AnyHashable: Any]) {
		path = dictionary["Path"] as? String ?? ""
		languages = dictionary["Languages"] as? Bool ?? false
		architectures = dictionary["Architectures"] as? Bool ?? false
	}

	init(path: String, languages: Bool, architectures: Bool) {
		self.path = path
		self.languages = languages
		self.architectures = architectures
	}

	var id: String { path }
}
