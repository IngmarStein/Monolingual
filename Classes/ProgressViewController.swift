/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2016 Ingmar Stein
 */

import Cocoa

protocol ProgressViewControllerDelegate : class {
	func progressViewControllerDidCancel(progressViewController: ProgressViewController)
}

final class ProgressViewController : NSViewController {
	@IBOutlet private weak var progressBar: NSProgressIndicator!
	@IBOutlet private weak var applicationText: NSTextField!
	@IBOutlet private weak var fileText: NSTextField!
	
	weak var delegate : ProgressViewControllerDelegate?
	
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
	
	override func viewDidLoad() {
		self.progressBar.usesThreadedAnimation = true
	}
	
	override func viewWillAppear() {
		self.applicationText.stringValue = NSLocalizedString("Removing...", comment:"")
		self.fileText.stringValue = ""
		self.progressBar.startAnimation(self)
	}

	override func viewWillDisappear() {
		self.progressBar.stopAnimation(self)
	}
	
	@IBAction func cancelButton(sender: AnyObject) {
		self.applicationText.stringValue = NSLocalizedString("Canceling operation...", comment:"")
		self.fileText.stringValue = ""

		self.delegate?.progressViewControllerDidCancel(self)
	}
}
