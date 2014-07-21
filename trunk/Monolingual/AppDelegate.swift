//
//  AppDelegate.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa

let ProcessApplicationNotification = "ProcessApplicationNotification"

class AppDelegate: NSObject, NSApplicationDelegate {
	var preferencesWindowController : NSWindowController?

	func applicationDidFinishLaunching(NSNotification) {
		let applications = [ "Path" : "/Applications", "Languages" : true, "Architectures" : true ]
		let developer    = [ "Path" : "/Developer",    "Languages" : true, "Architectures" : true ]
		let library      = [ "Path" : "/Library",      "Languages" : true, "Architectures" : true ]
		let systemPath   = [ "Path" : "/System",       "Languages" : true, "Architectures" : false ]
		let defaultRoots = [ applications, developer, library, systemPath ]
		let defaultDict  = [ "Roots" : defaultRoots, "Trash" : false, "Strip" : false ]

		NSUserDefaults.standardUserDefaults().registerDefaults(defaultDict)
	}
	
	func applicationShouldTerminateAfterLastWindowClosed(NSApplication!) -> Bool {
		return true
	}

	func application(sender: NSApplication!, openFile filename: String!) -> Bool {
		let dict = [ "Path" : filename, "Language" : true, "Architectures" : true ]
		
		NSNotificationCenter.defaultCenter().postNotificationName(ProcessApplicationNotification, object: self, userInfo: dict)
		
		return true
	}
	
	// #pragma mark - Actions
	
	@IBAction func documentationBundler(sender : NSMenuItem) {
		let docURL = NSBundle.mainBundle().URLForResource(sender.title, withExtension:nil)
		NSWorkspace.sharedWorkspace().openURL(docURL)
	}
	
	@IBAction func openWebsite(AnyObject) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string:"http://monolingual.sourceforge.net/"))
	}
	
	@IBAction func donate(AnyObject) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string:"http://monolingual.sourceforge.net/donate.php"))
	}

	@IBAction func showPreferences(sender: AnyObject) {
		if preferencesWindowController == nil {
			let storyboard = NSStoryboard(name:"Main", bundle:nil)
			preferencesWindowController = storyboard.instantiateControllerWithIdentifier("PreferencesWindow") as? NSWindowController
		}
		preferencesWindowController?.showWindow(sender)
	}
}
