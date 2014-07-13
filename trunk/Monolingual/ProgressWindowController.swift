/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2014 Ingmar Stein
 */

import Cocoa

class ProgressWindowController : NSWindowController {
	@IBOutlet var progressBar: NSProgressIndicator
	@IBOutlet var applicationText: NSTextField
	@IBOutlet var fileText: NSTextField

	@IBAction func cancelButton(sender: AnyObject) {
		self.applicationText.stringValue = NSLocalizedString("Canceling operation...", comment:"")
		self.fileText.stringValue = ""

		self.window.orderOut(sender)
		NSApp.endSheet(self.window, returnCode:1)
	}

	func start() {
		self.progressBar.usesThreadedAnimation = true
		self.progressBar.startAnimation(self)
		self.applicationText.stringValue = NSLocalizedString("Removing...", comment:"")
		self.fileText.stringValue = ""
	}

	func stop() {
		self.progressBar.stopAnimation(self)
	}

	func setFile(file: String) {
		self.fileText.stringValue = file
	}

	func setText(text: String) {
		self.applicationText.stringValue = text
	}

}
