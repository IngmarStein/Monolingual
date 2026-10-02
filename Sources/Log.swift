//
//  Log.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Foundation

final class Log {
	// The log belongs with the user's other logs, in the real $HOME/Library/Logs. Ask the
	// password database rather than FileManager, which reports the app's container directory
	// whenever the app is sandboxed.
	static var realHomeDirectory: String {
		if let pw = getpwuid(getuid()) {
			return String(cString: pw.pointee.pw_dir)
		} else {
			return FileManager.default.homeDirectoryForCurrentUser.path
		}
	}

	lazy var logFileURL: URL = {
		URL(fileURLWithPath: "\(Log.realHomeDirectory)/Library/Logs/Monolingual.log", isDirectory: false)
	}()

	var logFile: OutputStream?

	let dateFormatter = ISO8601DateFormatter()

	func open() {
		// Opening a log that is already open would drop the stream that is being written to,
		// leaking its file descriptor and splitting one run's entries over two handles.
		guard logFile == nil else { return }

		logFile = OutputStream(url: logFileURL, append: true)
		logFile?.open()
	}

	func message(_ message: String, timestamp: Bool = true) {
		let entry = timestamp ? "\(dateFormatter.string(from: Date())) \(message)" : message
		let data = [UInt8](entry.utf8)
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

@MainActor let log = Log()
