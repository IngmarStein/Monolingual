//
//  App.swift
//  App
//
//  Created by Ingmar Stein on 02.10.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

@main
struct MonolingualApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

	var body: some Scene {
		WindowGroup {
			MainView()
		}
		.commands {
			HelpCommands()
		}
		Settings {
			PreferencesView(roots: [])
		}
	}
}
