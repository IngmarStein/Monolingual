/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2014 Ingmar Stein
 */

import Cocoa

protocol ProgressViewControllerDelegate : class {
	func progressViewControllerDidCancel(progressViewController: ProgressViewController)
}

class ProgressViewController : NSViewController {
	@IBOutlet weak var progressBar: NSProgressIndicator!
	@IBOutlet weak var applicationText: NSTextField!
	@IBOutlet weak var fileText: NSTextField!
	
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
		self.applicationText.stringValue = NSLocalizedString("Removing...", comment:"")
		self.fileText.stringValue = ""
	}
	
	override func viewWillAppear() {
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
