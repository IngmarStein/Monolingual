//
//  PreferencesViewController
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2021 Ingmar Stein. All rights reserved.
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
	// see rdar://32840640
	@IBAction func togglePreference(_ sender: AnyObject) {
		let selectionIndex = roots.selectionIndex
		let dummy = [String: Any]()
		roots.addObject(dummy)
		roots.removeObject(dummy)
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
				if NSApplication.ModalResponse.OK == result {
					self.roots.add(contentsOf: oPanel.urls.map { [ "Path": $0.path, "Languages": true, "Architectures": true ] })
				}
			}
		} else if sender.selectedSegment == 1 {
			roots.remove(sender)
		}

		// Delegate will not respond when an item is added or removed.
		segmentedControl.setEnabled(tableView.numberOfSelectedRows > 0, forSegment: 1)
	}

	@IBAction func restoreDefaults(_ sender: NSButton) {
		roots.content = nil
		roots.add(contentsOf: Root.defaults)
	}

}
