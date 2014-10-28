//
//  Log.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa

class Log {
	let logFileName = NSURL(fileURLWithPath:"\(NSHomeDirectory())/Library/Logs/Monolingual.log", isDirectory: false)
	var logFile : NSFileHandle? = nil
	
	func open() {
		var error : NSError?
		NSFileManager.defaultManager().createFileAtPath(logFileName!.path!, contents: nil, attributes: nil)
		logFile = NSFileHandle(forWritingToURL:logFileName!, error: &error)
		if let error = error {
			NSLog("Failed to open log file: \(error)")
		}
		logFile?.seekToEndOfFile()
	}

	func message(message: String) {
		logFile?.writeData(message.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
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
