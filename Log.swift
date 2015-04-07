//
//  Log.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa

final class Log {
	let logFileName = NSURL(fileURLWithPath:"\(NSHomeDirectory())/Library/Logs/Monolingual.log", isDirectory: false)
	var logFile : NSFileHandle? = nil

	func open() {
		if let fileName = logFileName, path = fileName.path {
			NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)
			var error : NSError? = nil
			logFile = NSFileHandle(forWritingToURL:logFileName!, error: &error)
			if let error = error {
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
