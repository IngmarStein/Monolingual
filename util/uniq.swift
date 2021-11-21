import Foundation

var result: [[NSObject: AnyObject]] = []
if let blocklist = NSArray(contentsOfFile: "blocklist.plist") as? [[NSObject: AnyObject]] {
	var seen = Set<String>()
	for entry in blocklist {
		if let bundle = entry["bundle"] as? String {
			if seen.contains(bundle) {
				print("Duplicate: \(bundle)")
			} else {
				seen.insert(bundle)
				result.append(entry)
			}
		}
	}
}

(result as NSArray).write(toFile: "uniq.plist", atomically: true)
