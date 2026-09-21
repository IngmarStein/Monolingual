//
//  Preferences.swift
//  Monolingual
//
//  Created by Ingmar Stein on 19.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct PreferencesView: View {
	@State private var roots: [Root] = []
	@State private var sortOrder = [KeyPathComparator(\Root.path)]
	@State private var selection: Root.ID?
	@AppStorage("Trash") var trash: Bool = false
	@AppStorage("Strip") var strip: Bool = false
	@AppStorage("SUEnableAutomaticChecks") var automaticChecks: Bool = false

	var body: some View {
		VStack(alignment: .leading) {
			GroupBox("Directories") {
				Table(roots, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("Lang") { root in
						if let i = roots.firstIndex(where: { $0.id == root.id }) {
							Toggle(isOn: $roots[i].languages) {}.toggleStyle(.checkbox)
						}
					}
					.width(48)
					TableColumn("Arch") { root in
						if let i = roots.firstIndex(where: { $0.id == root.id }) {
							Toggle(isOn: $roots[i].architectures) {}.toggleStyle(.checkbox)
						}
					}
					.width(48)
					TableColumn("Path", value: \.path)
				}
				// Enough room for the directories, and the table grows when the window is
				// made larger instead of leaving empty rows below them.
				.frame(minHeight: tableHeight, maxHeight: .infinity)
				HStack {
					Button("+") {
						let oPanel = NSOpenPanel()

						oPanel.allowsMultipleSelection = true
						oPanel.canChooseDirectories = true
						oPanel.canChooseFiles = false
						oPanel.treatsFilePackagesAsDirectories = true

						oPanel.begin { result in
							if result == .OK {
								roots.append(contentsOf: oPanel.urls.map { Root(path: $0.path, languages: true, architectures: true) })
							}
						}
					}
					Button("-") {
						if let selection = selection, let i = roots.firstIndex(where: { $0.id == selection }) {
							roots.remove(at: i)
						}
					}.disabled(selection == nil)
					Spacer()
					Button("Standard") {
						roots = Root.defaultRoots
					}
				}
			}
			Toggle("Move language files to Trash", isOn: $trash)
			Toggle("Automatically check for updates", isOn: $automaticChecks)
			Toggle("Strip debug info when removing architectures", isOn: $strip)
		}
		.padding()
		.onAppear {
			if let pref = UserDefaults.standard.array(forKey: "Roots") as? [[String: Any]] {
				roots = pref.map { Root(dictionary: $0) }
			} else {
				roots = Root.defaultRoots
			}
			DispatchQueue.main.async {
				WindowTitleAdjuster.dropAppNameFromWindowTitles()
			}
		}
		.onChange(of: roots) { _, newRoots in
			let dicts = newRoots.map { root in
				["Path": root.path, "Languages": root.languages, "Architectures": root.architectures]
			}
			UserDefaults.standard.set(dicts, forKey: "Roots")
		}
	}

	/// Minimum height of the table: the window is sized to the directories, but can be made
	/// larger.
	private var tableHeight: CGFloat {
		min(CGFloat(roots.count) * 24 + 32, 240)
	}
}

/// The Settings scene titles its window "<app name>-<Settings>", for example
/// "Monolingual-Einstellungen". Drop the app name so the window just says "Settings",
/// keeping whatever localization the system used.
enum WindowTitleAdjuster {
	static func dropAppNameFromWindowTitles() {
		let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
			?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
			?? ""
		guard !name.isEmpty else { return }
		for window in NSApp.windows {
			for separator in ["-", " "] where window.title.hasPrefix(name + separator) {
				window.title = String(window.title.dropFirst(name.count + separator.count))
				break
			}
		}
	}
}

struct PreferencesView_Previews: PreviewProvider {
	static var previews: some View {
		PreferencesView()
	}
}
