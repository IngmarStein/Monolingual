//
//  HelperRequest.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

@objc(HelperRequest) class HelperRequest: NSObject, NSSecureCoding {
	var dryRun: Bool
	var doStrip: Bool
	var uid: uid_t
	var trash: Bool
	var includes: [String]?
	var excludes: [String]?
	var bundleBlocklist: Set<String>?
	var directories: Set<String>?
	var files: [String]?
	var thin: [String]?

	override init() {
		dryRun = false
		doStrip = false
		uid = 0
		trash = false

		super.init()
	}

	required init?(coder aDecoder: NSCoder) {
		let stringArray: [AnyClass] = [NSString.self, NSArray.self]
		let stringSet: [AnyClass] = [NSString.self, NSSet.self]

		dryRun = aDecoder.decodeBool(forKey: "dryRun")
		doStrip = aDecoder.decodeBool(forKey: "doStrip")
		uid = uid_t(aDecoder.decodeInteger(forKey: "uid"))
		trash = aDecoder.decodeBool(forKey: "trash")
		includes = aDecoder.decodeObject(of: stringArray, forKey: "includes") as? [String]
		excludes = aDecoder.decodeObject(of: stringArray, forKey: "excludes") as? [String]
		bundleBlocklist = aDecoder.decodeObject(of: stringSet, forKey: "bundleBlocklist") as? Set<String>
		directories = aDecoder.decodeObject(of: stringSet, forKey: "directories") as? Set<String>
		files = aDecoder.decodeObject(of: stringArray, forKey: "files") as? [String]
		thin = aDecoder.decodeObject(of: stringArray, forKey: "thin") as? [String]

		super.init()
	}

	func encode(with coder: NSCoder) {
		coder.encode(dryRun, forKey: "dryRun")
		coder.encode(doStrip, forKey: "doStrip")
		coder.encode(Int(uid), forKey: "uid")
		coder.encode(trash, forKey: "trash")
		if let includes = includes {
			coder.encode(includes as NSArray, forKey: "includes")
		}
		if let excludes = excludes {
			coder.encode(excludes as NSArray, forKey: "excludes")
		}
		if let bundleBlocklist = bundleBlocklist {
			coder.encode(bundleBlocklist as NSSet, forKey: "bundleBlocklist")
		}
		if let directories = directories {
			coder.encode(directories as NSSet, forKey: "directories")
		}
		if let files = files {
			coder.encode(files as NSArray, forKey: "files")
		}
		if let thin = thin {
			coder.encode(thin as NSArray, forKey: "thin")
		}
	}

	static var supportsSecureCoding: Bool {
		true
	}
}
