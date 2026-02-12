//
//  Root.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
//

import Foundation

struct Root: Identifiable, Equatable, Codable {
	let path: String
	var languages: Bool
	var architectures: Bool

	static var defaultRoots: [Root] {
		[
			Root(path: "/Applications", languages: true, architectures: true),
			Root(path: "/Library", languages: true, architectures: true)
		]
	}

	static var defaults: [[String: Any]] {
		defaultRoots.map { root in
			["Path": root.path, "Languages": root.languages, "Architectures": root.architectures]
		}
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
