//
//  HelpCommands.swift
//  HelpCommands
//
//  Created by Ingmar Stein on 02.10.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct HelpCommands: Commands {
	var body: some Commands {
		CommandGroup(before: .help) {
			Button("README.rtfd") {
				let docURL = Bundle.main.url(forResource: NSLocalizedString("README.rtfd", comment: ""), withExtension: nil)
				NSWorkspace.shared.open(docURL!)
			}
			Button("LICENSE.txt") {
				let docURL = Bundle.main.url(forResource: "LICENSE", withExtension: "txt")
				NSWorkspace.shared.open(docURL!)
			}
			Button("Donate") {
				NSWorkspace.shared.open(URL(string: "https://ingmarstein.github.io/Monolingual/donate.html")!)
			}
			Button("Monolingual Website") {
				NSWorkspace.shared.open(URL(string: "https://ingmarstein.github.io/Monolingual")!)
			}
		}
	}
}
