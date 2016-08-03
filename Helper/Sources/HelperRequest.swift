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
	var bundleBlacklist: Set<String>?
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
		bundleBlacklist = aDecoder.decodeObject(of: stringSet, forKey: "bundleBlacklist") as? Set<String>
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
		if let includes = self.includes {
			coder.encode(includes as NSArray, forKey: "includes")
		}
		if let excludes = self.excludes {
			coder.encode(excludes as NSArray, forKey: "excludes")
		}
		if let bundleBlacklist = self.bundleBlacklist {
			coder.encode(bundleBlacklist as NSSet, forKey: "bundleBlacklist")
		}
		if let directories = self.directories {
			coder.encode(directories as NSSet, forKey: "directories")
		}
		if let files = self.files {
			coder.encode(files as NSArray, forKey: "files")
		}
		if let thin = self.thin {
			coder.encode(thin as NSArray, forKey: "thin")
		}
	}

	static var supportsSecureCoding: Bool {
		return true
	}

}
