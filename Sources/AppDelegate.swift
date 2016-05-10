//
//  AppDelegate.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa
import Fabric
import Crashlytics

let ProcessApplicationNotification = "ProcessApplicationNotification"

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	var preferencesWindowController: NSWindowController?

	// validate values stored in NSUserDefaults and reset to default if necessary
	private func validateDefaults() {
		let defaults = NSUserDefaults.standard()

		let roots = defaults.array(forKey: "Roots")
		if roots == nil || roots!.index(where: { (root) -> Bool in
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

	func applicationDidFinishLaunching(_: NSNotification) {
		let defaultDict: [String: AnyObject]  = [ "Roots" : Root.defaults as AnyObject, "Trash" : false, "Strip" : false, "NSApplicationCrashOnExceptions" : true ]

		NSUserDefaults.standard().register(defaultDict)

		validateDefaults()

		Fabric.with([Crashlytics()])
	}

	func applicationShouldTerminate(afterLastWindowClosed sender: NSApplication) -> Bool {
		return true
	}

	@objc(application:openFile:) func application(_ sender: NSApplication, openFile filename: String) -> Bool {
		let dict: [NSObject: AnyObject] = [ "Path": filename as NSString, "Language": true, "Architectures": true ]

		NSNotificationCenter.default().post(name: ProcessApplicationNotification, object: self, userInfo: dict)
		
		return true
	}
	
	//MARK: - Actions
	
	@IBAction func documentationBundler(_ sender : NSMenuItem) {
		let docURL = NSBundle.main().urlForResource(sender.title, withExtension:nil)
		NSWorkspace.shared().open(docURL!)
	}
	
	@IBAction func openWebsite(_: AnyObject) {
		NSWorkspace.shared().open(NSURL(string:"https://ingmarstein.github.io/Monolingual")!)
	}
	
	@IBAction func donate(_: AnyObject) {
		NSWorkspace.shared().open(NSURL(string:"https://ingmarstein.github.io/Monolingual/donate.html")!)
	}

	@IBAction func showPreferences(_ sender: AnyObject) {
		if preferencesWindowController == nil {
			let storyboard = NSStoryboard(name:"Main", bundle:nil)
			preferencesWindowController = storyboard.instantiateController(withIdentifier: "PreferencesWindow") as? NSWindowController
		}
		preferencesWindowController?.showWindow(sender)
	}
}
