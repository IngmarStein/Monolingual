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
	var logFile : NSFileHandle? = nil

	func open() {
		if let path = logFileURL.path {
			NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)
			do {
				logFile = try NSFileHandle(forWritingToURL:logFileURL)
			} catch let error as NSError {
				NSLog("Failed to open log file: \(error)")
			}
			logFile?.seekToEndOfFile()
		}
	}

	func message(message: String) {
		if let data = message.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
			logFile?.writeData(data)
		}
	}

	func close() {
		logFile?.closeFile()
		logFile = nil
	}
	
	deinit {
		close()
	}
}

let log = Log()
