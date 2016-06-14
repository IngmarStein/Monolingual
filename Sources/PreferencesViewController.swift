//
//  PreferencesViewController
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2016 Ingmar Stein. All rights reserved.
//

import Cocoa

final class PreferencesViewController: NSViewController, NSTableViewDelegate {

	@IBOutlet private var roots: NSArrayController!
	@IBOutlet private var tableView: NSTableView!
	@IBOutlet weak var segmentedControl: NSSegmentedControl!

	func tableViewSelectionDidChange(_ notification: Notification) {
		segmentedControl.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
	}

	// Ugly workaround to force NSUserDefaultsController to notice the model changes from the UI.
	// This currently seems broken for view-based NSTableViews (the changes to the objectValue property are not propagated).
	@IBAction func togglePreference(_ sender: AnyObject) {
		let selectionIndex = roots.selectionIndex
		let dummy = []
		roots.add(dummy)
		roots.remove(dummy)
		roots.setSelectionIndex(selectionIndex)
		tableView.window?.makeFirstResponder(tableView)
	}

	@IBAction func modifyPaths(_ sender: NSSegmentedControl) {
		if sender.selectedSegment == 0 {
			let oPanel = NSOpenPanel()

			oPanel.allowsMultipleSelection = true
			oPanel.canChooseDirectories = true
			oPanel.canChooseFiles = false
			oPanel.treatsFilePackagesAsDirectories = true

			oPanel.begin { result in
				if NSModalResponseOK == result {
					self.roots.add(oPanel.urls.map { [ "Path": $0.path!, "Languages": true, "Architectures": true ] })
				}
			}
		} else if sender.selectedSegment == 1 {
			// FIXME: Swift 3 (2016-03-09) maps -[NSArrayController remove:] and -[NSArrayController removeObject:] to NSArrayController.remove(_ sender: AnyObject?) .remove(_ object: AnyObject), respectively
			roots.remove(sender as AnyObject?)
		}

		// Delegate will not respond when an item is added or removed.
		segmentedControl.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
	}

	@IBAction func restoreDefaults(_ sender: NSButton) {
		roots.content = nil
		roots.add(Root.defaults)
	}

}
