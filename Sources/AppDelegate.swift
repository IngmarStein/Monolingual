//
//  AppDelegate.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa

let processApplicationNotification = NSNotification.Name(rawValue: "ProcessApplicationNotification")

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {

	// validate values stored in NSUserDefaults and reset to default if necessary
	private func validateDefaults() {
		let defaults = UserDefaults.standard

		let roots = defaults.array(forKey: "Roots")
		if roots == nil || roots!.firstIndex(where: { (root) -> Bool in
			if let rootDictionary = root as? NSDictionary {
				return rootDictionary.object(forKey: "Path") == nil
					|| rootDictionary.object(forKey: "Languages") == nil
					|| rootDictionary.object(forKey: "Architectures") == nil
			} else {
				return true
			}
		}) != nil {
			defaults.set(Root.defaults as NSArray, forKey: "Roots")
		}
	}

	func applicationDidFinishLaunching(_: Notification) {
		let defaultDict: [String: Any]  = [ "Roots": Root.defaults, "Trash": false, "Strip": false, "NSApplicationCrashOnExceptions": true ]

		UserDefaults.standard.register(defaults: defaultDict)

		validateDefaults()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	func application(_ sender: NSApplication, openFile filename: String) -> Bool {
		let dict: [String: Any] = [ "Path": filename, "Language": true, "Architectures": true ]

		NotificationCenter.default.post(name: processApplicationNotification, object: self, userInfo: dict)

		return true
	}

	// MARK: - Actions

	@IBAction func documentationBundler(_ sender: NSMenuItem) {
		let docURL = Bundle.main.url(forResource: sender.title, withExtension: nil)
		NSWorkspace.shared.open(docURL!)
	}

	@IBAction func openWebsite(_: AnyObject) {
		NSWorkspace.shared.open(URL(string: "https://ingmarstein.github.io/Monolingual")!)
	}

	@IBAction func donate(_: AnyObject) {
		NSWorkspace.shared.open(URL(string: "https://ingmarstein.github.io/Monolingual/donate.html")!)
	}

}
