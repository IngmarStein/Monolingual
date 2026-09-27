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
				open(bundleResource: NSLocalizedString("README.rtfd", comment: ""))
			}
			Button("LICENSE.txt") {
				open(bundleResource: "LICENSE.txt")
			}
			Button("Donate") {
				open(url: "https://ingmarstein.github.io/Monolingual/donate.html")
			}
			Button("Monolingual Website") {
				open(url: "https://ingmarstein.github.io/Monolingual")
			}
		}
	}

	/// Opens a document from the app bundle.
	///
	/// The help document is named per language by the strings file, so a translation that names
	/// one the bundle does not carry — or a copy stripped of its resources — would be a trap if
	/// the lookup were unwrapped.
	private func open(bundleResource name: String) {
		let resource = (name as NSString).deletingPathExtension
		let ext = (name as NSString).pathExtension
		guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return }
		NSWorkspace.shared.open(url)
	}

	private func open(url: String) {
		guard let url = URL(string: url) else { return }
		NSWorkspace.shared.open(url)
	}
}
