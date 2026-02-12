//
//  App.swift
//  App
//
//  Created by Ingmar Stein on 02.10.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI
import Sparkle

@main
struct MonolingualApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
	private let updaterController: SPUStandardUpdaterController

	init() {
		updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
	}

	var body: some Scene {
		WindowGroup {
			MainView()
		}
		.commands {
			CommandGroup(after: .appInfo) {
				Button("Check for Updates…") {
					updaterController.checkForUpdates(nil)
				}
			}
			HelpCommands()
		}
		Settings {
			PreferencesView()
		}
	}
}
