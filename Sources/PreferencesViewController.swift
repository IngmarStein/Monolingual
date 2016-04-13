//
//  PreferencesViewController
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2016 Ingmar Stein. All rights reserved.
//

import Cocoa

final class PreferencesViewController : NSViewController, NSTableViewDelegate {

	@IBOutlet private var roots: NSArrayController!
	@IBOutlet private var tableView: NSTableView!
	@IBOutlet weak var segmentedControl: NSSegmentedControl!

	func tableViewSelectionDidChange(notification: NSNotification) {
		segmentedControl.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
	}

	// Ugly workaround to force NSUserDefaultsController to notice the model changes from the UI.
	// This currently seems broken for view-based NSTableViews (the changes to the objectValue property are not propagated).
	@IBAction func togglePreference(sender: AnyObject) {
		let selectionIndex = roots.selectionIndex
		let dummy = []
		roots.addObject(dummy)
		roots.removeObject(dummy)
		roots.setSelectionIndex(selectionIndex)
		tableView.window?.makeFirstResponder(tableView)
	}

	@IBAction func modifyPaths(sender: NSSegmentedControl) {
		if sender.selectedSegment == 0 {
			let oPanel = NSOpenPanel()

			oPanel.allowsMultipleSelection = true
			oPanel.canChooseDirectories = true
			oPanel.canChooseFiles = false
			oPanel.treatsFilePackagesAsDirectories = true

			oPanel.beginWithCompletionHandler { result in
				if NSModalResponseOK == result {
					self.roots.addObjects(oPanel.URLs.map { [ "Path" : $0.path!, "Languages" : true, "Architectures" : true ] })
				}
			}
		} else if sender.selectedSegment == 1 {
			roots.remove(sender)
		}

		// Delegate will not respond when an item is added or removed.
		segmentedControl.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
	}

	@IBAction func restoreDefaults(sender: NSButton) {
		roots.content = nil
		roots.addObjects(Root.defaults)
	}

}
