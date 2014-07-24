//
//  ISTableView.swift
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2014 Ingmar Stein. All rights reserved.
//

import Cocoa

class ISTableView : NSTableView {
	@IBOutlet var arrayController: NSArrayController!

	override func keyDown(theEvent: NSEvent!) {
		if theEvent.charactersIgnoringModifiers.hasPrefix(" ") {
			let row = self.selectedRow
			if row != -1 {
				let arrangedObjects = self.arrayController.arrangedObjects as [Setting]
				var setting = arrangedObjects[row]
				setting.enabled = !setting.enabled
			}
		} else {
			super.keyDown(theEvent)
		}
	}
}
