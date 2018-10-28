//
//  ISTableView.swift
//  Monolingual
//
//  Created by Ingmar Stein on 27.01.06.
//  Copyright 2006-2018 Ingmar Stein. All rights reserved.
//

import Cocoa

final class ISTableView: NSTableView {
	@IBOutlet private var arrayController: NSArrayController!

	override func keyDown(with theEvent: NSEvent) {
		if let characters = theEvent.charactersIgnoringModifiers, characters.hasPrefix(" ") {
			let row = self.selectedRow
			if row != -1 {
				if let arrangedObjects = self.arrayController.arrangedObjects as? [Setting] {
					let setting = arrangedObjects[row]
					setting.enabled = !setting.enabled
				}
			}
		} else {
			super.keyDown(with: theEvent)
		}
	}

}
