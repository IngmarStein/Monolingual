//
//  Preferences.swift
//  Monolingual
//
//  Created by Ingmar Stein on 19.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct PreferencesView: View {
	@State var roots: [Root]
	@State private var sortOrder = [KeyPathComparator(\Root.path)]
	@State private var selection: Root.ID?
	@AppStorage("Trash") var trash: Bool = false
	@AppStorage("Strip") var strip: Bool = false
	@AppStorage("SUEnableAutomaticChecks") var automaticChecks: Bool = false

	var body: some View {
		VStack(alignment: .leading) {
			GroupBox("Directories") {
				Table(roots, selection: $selection, sortOrder: $sortOrder) {
					TableColumn("Languages") { root in
						let i = roots.firstIndex(of: root)!
						Toggle(isOn: $roots[i].languages) {}.toggleStyle(.checkbox)
					}.width(20.0)
					TableColumn("Architectures") { root in
						let i = roots.firstIndex(of: root)!
						Toggle(isOn: $roots[i].architectures) {}.toggleStyle(.checkbox)
					}.width(20.0)
					TableColumn("Path", value: \.path)
				}
				HStack {
					Button("+") {
						let oPanel = NSOpenPanel()

						oPanel.allowsMultipleSelection = true
						oPanel.canChooseDirectories = true
						oPanel.canChooseFiles = false
						oPanel.treatsFilePackagesAsDirectories = true

						oPanel.begin { result in
							if NSApplication.ModalResponse.OK == result {
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
					Button("Standard") {}
				}
			}
			Toggle("Move language files to Trash", isOn: $trash)
			Toggle("Automatically check for updates", isOn: $automaticChecks)
			Toggle("Strip debug info when removing architectures", isOn: $strip)
		}
		.padding()
	}
}

struct PreferencesView_Previews: PreviewProvider {
	static var previews: some View {
		PreferencesView(roots: Root.defaults.map(Root.init(dictionary:)))
	}
}
