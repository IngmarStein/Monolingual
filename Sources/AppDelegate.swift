//
//  AppDelegate.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
	/// The bundle the user opened with Monolingual, if any. A removal then covers only that
	/// bundle. It is kept here rather than posted as a notification: opening a bundle can
	/// launch the app, and this runs before the window exists to hear one.
	private(set) var openedApplication: Root?

	// validate values stored in NSUserDefaults and reset to default if necessary
	private func validateDefaults() {
		let defaults = UserDefaults.standard

		// A root is only usable if it carries all three of the keys the app reads back, so a
		// stored array that is missing or holds anything else is replaced by the default roots.
		// An empty array is a user who removed every row on purpose, and is left alone.
		let roots = defaults.array(forKey: "Roots")
		let usable = roots?.allSatisfy { root in
			guard let root = root as? NSDictionary else { return false }
			return root.object(forKey: "Path") != nil
				&& root.object(forKey: "Languages") != nil
				&& root.object(forKey: "Architectures") != nil
		} ?? false

		if !usable {
			defaults.set(Root.defaults as NSArray, forKey: "Roots")
		}
	}

	func applicationDidFinishLaunching(_: Notification) {
		let defaultDict: [String: Any] = ["Roots": Root.defaults, "Trash": false, "Strip": false, "NSApplicationCrashOnExceptions": true]

		UserDefaults.standard.register(defaults: defaultDict)

		validateDefaults()

		// Without a delegate the system keeps a notification to itself while the app is
		// frontmost, which is where the user is when a removal finishes.
		UNUserNotificationCenter.current().delegate = self
	}

	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
		true
	}

	func application(_: NSApplication, openFile filename: String) -> Bool {
		openedApplication = Root(path: filename, languages: true, architectures: true)

		return true
	}

	// MARK: - UNUserNotificationCenterDelegate

	func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
		[.banner]
	}
}
