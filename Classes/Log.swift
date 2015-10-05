//
//  Log.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Foundation

final class Log {

	// use the real (non-sandboxed) directory $HOME/Library/Logs for the log file as long as we have the temporary exception com.apple.security.temporary-exception.files.home-relative-path.read-write.
	// NSHomeDirectory() points to $HOME/Library/Containers/com.github.IngmarStein.Monolingual/Data
	class var realHomeDirectory : String {
		let pw = getpwuid(getuid())
		if pw != nil {
			return String.fromCString(pw.memory.pw_dir)!
		} else {
			return NSHomeDirectory()
		}
	}

	let logFileURL = NSURL(fileURLWithPath:"\(Log.realHomeDirectory)/Library/Logs/Monolingual.log", isDirectory: false)
	var logFile : NSOutputStream? = nil

	func open() {
		logFile = NSOutputStream(URL: logFileURL, append: true)
		logFile?.open()
	}

	func message(message: String) {
		let data = [UInt8](message.utf8)
		logFile?.write(data, maxLength: data.count)
	}

	func close() {
		logFile?.close()
		logFile = nil
	}
	
	deinit {
		close()
	}
}

let log = Log()
