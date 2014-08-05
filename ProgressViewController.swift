/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2014 Ingmar Stein
 */

import Cocoa

class ProgressViewController : NSViewController {
	@IBOutlet weak var progressBar: NSProgressIndicator!
	@IBOutlet weak var applicationText: NSTextField!
	@IBOutlet weak var fileText: NSTextField!
	
	var file : String {
	get {
		return self.fileText.stringValue
	}
	set {
		self.fileText.stringValue = newValue
	}
	}

	var text : String {
	get {
		return self.applicationText.stringValue
	}
	set {
		self.applicationText.stringValue = newValue
	}
	}
	
	@IBAction func cancelButton(sender: AnyObject) {
		self.applicationText.stringValue = NSLocalizedString("Canceling operation...", comment:"")
		self.fileText.stringValue = ""

		self.view.window?.orderOut(sender)
		NSApp.endSheet(self.view.window, returnCode:1)
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
}
