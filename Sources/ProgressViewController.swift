/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2021 Ingmar Stein
 */

import Cocoa

protocol ProgressViewControllerDelegate: AnyObject {
	func progressViewControllerDidCancel(_ progressViewController: ProgressViewController)
}

final class ProgressViewController: NSViewController {
	@IBOutlet private weak var progressBar: NSProgressIndicator!
	@IBOutlet private weak var applicationText: NSTextField!
	@IBOutlet private weak var fileText: NSTextField!

	weak var delegate: ProgressViewControllerDelegate?

	var file: String {
	get {
		return self.fileText.stringValue
	}
	set {
		self.fileText.stringValue = newValue
	}
	}

	var text: String {
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
		self.applicationText.stringValue = NSLocalizedString("Removing...", comment: "")
		self.fileText.stringValue = ""
		self.progressBar.startAnimation(self)
	}

	override func viewWillDisappear() {
		self.progressBar.stopAnimation(self)
	}

	@IBAction func cancelButton(_ sender: AnyObject) {
		self.applicationText.stringValue = NSLocalizedString("Canceling operation...", comment: "")
		self.fileText.stringValue = ""

		self.delegate?.progressViewControllerDidCancel(self)
	}

}
