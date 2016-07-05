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
		// https://devforums.apple.com/message/1124684
		let stringClass = NSString.self as AnyObject as! NSObject
		let arrayClass = NSArray.self as AnyObject as! NSObject
		let setClass = NSSet.self as AnyObject as! NSObject
		let stringArray = Set([stringClass, arrayClass])
		let stringSet = Set([stringClass, setClass])

		dryRun = aDecoder.decodeBool(forKey: "dryRun")
		doStrip = aDecoder.decodeBool(forKey: "doStrip")
		uid = uid_t(aDecoder.decodeInteger(forKey: "uid"))
		trash = aDecoder.decodeBool(forKey: "trash")
		includes = aDecoder.decodeObjectOfClasses(stringArray as NSSet, forKey: "includes") as? [String]
		excludes = aDecoder.decodeObjectOfClasses(stringArray as NSSet, forKey: "excludes") as? [String]
		bundleBlacklist = aDecoder.decodeObjectOfClasses(stringSet as NSSet, forKey: "bundleBlacklist") as? Set<String>
		directories = aDecoder.decodeObjectOfClasses(stringSet as NSSet, forKey: "directories") as? Set<String>
		files = aDecoder.decodeObjectOfClasses(stringArray as NSSet, forKey: "files") as? [String]
		thin = aDecoder.decodeObjectOfClasses(stringArray as NSSet, forKey: "thin") as? [String]

		super.init()
	}

	// https://bugs.swift.org/browse/SR-1208
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
