//
//  HelperRequest.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

@objc(HelperRequest) class HelperRequest : NSObject, NSSecureCoding {

	var dryRun : Bool
	var doStrip : Bool
	var uid : uid_t
	var trash : Bool
	var includes : [String]?
	var excludes : [String]?
	var bundleBlacklist : Set<String>?
	var directories : Set<String>?
	var files : [String]?
	var thin : [String]?

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
		includes = aDecoder.decodeObjectOfClasses(stringArray, forKey:"includes") as? [String]
		excludes = aDecoder.decodeObjectOfClasses(stringArray, forKey:"excludes") as? [String]
		bundleBlacklist = aDecoder.decodeObjectOfClasses(stringSet, forKey:"bundleBlacklist") as? Set<String>
		directories = aDecoder.decodeObjectOfClasses(stringSet, forKey:"directories") as? Set<String>
		files = aDecoder.decodeObjectOfClasses(stringArray, forKey:"files") as? [String]
		thin = aDecoder.decodeObjectOfClasses(stringArray, forKey:"thin") as? [String]

		super.init()
	}

	// https://bugs.swift.org/browse/SR-1208
	@objc(encodeWithCoder:)
	func encode(with coder: NSCoder) {
		coder.encode(dryRun, forKey:"dryRun")
		coder.encode(doStrip, forKey:"doStrip")
		coder.encode(Int(uid), forKey:"uid")
		coder.encode(trash, forKey:"trash")
		coder.encode(includes, forKey:"includes")
		coder.encode(excludes, forKey:"excludes")
		coder.encode(bundleBlacklist, forKey:"bundleBlacklist")
		coder.encode(directories, forKey:"directories")
		coder.encode(files, forKey:"files")
		coder.encode(thin, forKey:"thin")
	}

	static func supportsSecureCoding() -> Bool {
		return true
	}
}
