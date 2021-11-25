//
//  MainView.swift
//  MainView
//
//  Created by Ingmar Stein on 27.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct MainView: View {
	@State var languages: [LanguageSetting]
	@State var architectures: [ArchitectureSetting]

	var body: some View {
		TabView {
			VStack(alignment: .leading) {
				Text("Select the items you wish to remove:")
				Table(languages) {
					TableColumn("Remove language") { setting in
						Toggle(setting.displayName, isOn: $languages[setting.id].enabled)
							.toggleStyle(.checkbox)
					}
				}
				HStack {
					Spacer()
					Button("Remove …") {}
				}.padding()
			}
			.padding()
			.tabItem {
				Text("Languages")
			}
			VStack(alignment: .leading) {
				Text("Select the items you wish to remove:")
				Table(languages) {
					TableColumn("Remove language") { setting in
						Toggle(setting.displayName, isOn: $languages[setting.id].enabled)
							.toggleStyle(.checkbox)
					}
				}
				HStack {
					Spacer()
					Button("Remove …") {}
				}.padding()
			}
			.padding()
			.tabItem {
				Text("Architectures")
			}
		}.padding()
	}
}

struct MainView_Previews: PreviewProvider {
	static var previews: some View {
		MainView(languages:
			[
				LanguageSetting(id: 0, enabled: true, folders: ["de.lproj"], displayName: "German"),
			],
			architectures: [
				ArchitectureSetting(id: 0, enabled: true, name: "arm", displayName: "ARM"),
			])
	}
}
