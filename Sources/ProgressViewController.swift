/*
 *  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
 *  2004-2021 Ingmar Stein
 */

import Cocoa

protocol ProgressViewControllerDelegate: AnyObject {
	func progressViewControllerDidCancel(_ progressViewController: ProgressViewController)
}

final class ProgressViewController: NSViewController {
	@IBOutlet private var progressBar: NSProgressIndicator!
	@IBOutlet private var applicationText: NSTextField!
	@IBOutlet private var fileText: NSTextField!

	weak var delegate: ProgressViewControllerDelegate?

	var file: String {
		get {
			fileText.stringValue
		}
		set {
			fileText.stringValue = newValue
		}
	}

	var text: String {
		get {
			self.applicationText.stringValue
		}
		set {
			self.applicationText.stringValue = newValue
		}
	}

	override func viewDidLoad() {
		progressBar.usesThreadedAnimation = true
	}

	override func viewWillAppear() {
		applicationText.stringValue = NSLocalizedString("Removing...", comment: "")
		fileText.stringValue = ""
		progressBar.startAnimation(self)
	}

	override func viewWillDisappear() {
		progressBar.stopAnimation(self)
	}

	@IBAction func cancelButton(_: AnyObject) {
		applicationText.stringValue = NSLocalizedString("Canceling operation...", comment: "")
		fileText.stringValue = ""

		delegate?.progressViewControllerDidCancel(self)
	}
}
