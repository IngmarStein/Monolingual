//
//  ISTableView.swift
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2016 Ingmar Stein. All rights reserved.
//

import Cocoa

final class ISTableView : NSTableView {
	@IBOutlet private var arrayController: NSArrayController!

	override func keyDown(theEvent: NSEvent) {
		if let characters = theEvent.charactersIgnoringModifiers where characters.hasPrefix(" ") {
			let row = self.selectedRow
			if row != -1 {
				if let arrangedObjects = self.arrayController.arrangedObjects as? [Setting] {
					let setting = arrangedObjects[row]
					setting.enabled = !setting.enabled
				}
			}
		} else {
			super.keyDown(theEvent)
		}
	}
}
