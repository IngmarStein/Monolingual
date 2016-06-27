//
//  Log.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Foundation

// TODO: remove the following as soon as the new logging API is available for Swift
var OS_LOG_DEFAULT = 0
func os_log_debug(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_error(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}
func os_log_info(_ log: Any, _ format: String, _ arguments: CVarArg...) {
	NSLog("%@", String(format: format, arguments: arguments))
}

final class Log {

	// use the real (non-sandboxed) directory $HOME/Library/Logs for the log file as long as we have the temporary exception com.apple.security.temporary-exception.files.home-relative-path.read-write.
	// NSHomeDirectory() points to $HOME/Library/Containers/com.github.IngmarStein.Monolingual/Data
	class var realHomeDirectory: String {
		if let pw = getpwuid(getuid()) {
			return String(cString: pw.pointee.pw_dir)
		} else {
			return NSHomeDirectory()
		}
	}

	let logFileURL = URL(fileURLWithPath: "\(Log.realHomeDirectory)/Library/Logs/Monolingual.log", isDirectory: false)
	var logFile: NSOutputStream? = nil

	func open() {
		logFile = NSOutputStream(url: logFileURL, append: true)
		logFile?.open()
	}

	func message(_ message: String) {
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
