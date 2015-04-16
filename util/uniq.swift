import Foundation

var result : [[NSObject:AnyObject]] = []
if let blacklist = NSArray(contentsOfFile:"blacklist.plist") as? [[NSObject:AnyObject]] {
	var seen = Set<String>()
	for entry in blacklist {
		let bundle = entry["bundle"] as! String
		if seen.contains(bundle) {
			println("Duplicate: \(bundle)")
		} else {
			seen.insert(bundle)
			result.append(entry)
		}
	}
}
(result as! NSArray).writeToFile("uniq.plist", atomically:true)
