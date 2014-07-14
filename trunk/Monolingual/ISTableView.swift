//
//  ISTableView.swift
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2014 Ingmar Stein. All rights reserved.
//

import Cocoa

class ISTableView : NSTableView {
	@IBOutlet var arrayController: NSArrayController

	override func keyDown(theEvent: NSEvent!) {
		var row: Int
		let key = theEvent.charactersIgnoringModifiers.substringToIndex(1)

		switch (key) {
			case " ":
				row = self.selectedRow
				if row != -1 {
					let arrangedObjects = self.arrayController.arrangedObjects as [NSMutableDictionary]
					var dict = arrangedObjects[row]
					dict["Enabled"] = !dict["Enabled"].boolValue
				}
			default:
				super.keyDown(theEvent)
		}
	}
}

