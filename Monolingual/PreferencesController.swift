//
//  PreferencesController.swift
//  Monolingual
//
//  Created by Ingmar Stein on Mon Apr 19 2004.
//  Copyright (c) 2004-2014 Ingmar Stein. All rights reserved.
//

import Cocoa

class PreferencesController : NSWindowController {

	@IBOutlet var roots: NSArrayController

	override func awakeFromNib() {
		self.window.setFrameAutosaveName("PreferencesWindow")
	}

	@IBAction func add(sender: AnyObject) {
		let oPanel = NSOpenPanel()

		oPanel.allowsMultipleSelection = true
		oPanel.canChooseDirectories = true
		oPanel.canChooseFiles = false
		oPanel.treatsFilePackagesAsDirectories = true

		oPanel.beginWithCompletionHandler {
			(result: NSInteger) in
			if NSOKButton == result {
				for obj in oPanel.URLs {
					let url = obj as NSURL
					self.roots.addObject([ "Path" : url.path,
										   "Languages" : true,
										   "Architectures" : true ])
				}
			}
		}
	}
}
