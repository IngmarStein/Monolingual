//
//  PreferencesViewController
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2014 Ingmar Stein. All rights reserved.
//

import Cocoa

final class PreferencesViewController : NSViewController {

	@IBOutlet private var roots: NSArrayController!
	@IBOutlet private var tableView: NSTableView!

	// Ugly workaround to force NSUserDefaultsController to notice the model changes from the UI.
	// This currently seems broken for view-based NSTableViews (the changes to the objectValue property are not propagated).
	@IBAction func togglePreference(sender: AnyObject) {
		let selectionIndex = self.roots.selectionIndex
		let dummy = []
		self.roots.addObject(dummy)
		self.roots.removeObject(dummy)
		self.roots.setSelectionIndex(selectionIndex)
		self.view.window?.makeFirstResponder(tableView)
	}

	@IBAction func add(sender: AnyObject) {
		let oPanel = NSOpenPanel()

		oPanel.allowsMultipleSelection = true
		oPanel.canChooseDirectories = true
		oPanel.canChooseFiles = false
		oPanel.treatsFilePackagesAsDirectories = true

		oPanel.beginWithCompletionHandler { result in
			if NSModalResponseOK == result {
				if let urls = oPanel.URLs as? [NSURL] {
					self.roots.addObjects(urls.map { [ "Path" : $0.path!, "Languages" : true, "Architectures" : true ] })
				}
			}
		}
	}
}
