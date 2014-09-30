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
		logFile = NSFileHandle(forWritingToURL:logFileName!, error: nil)
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
