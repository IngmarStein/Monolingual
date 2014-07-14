//
//  AppDelegate.swift
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
	let donateURL : NSURL = NSURL(string:"http://monolingual.sourceforge.net/donate.php")

	func applicationDidFinishLaunching(notification: NSNotification) {
		let applications = [ "Path" : "/Applications", "Languages" : true, "Architectures" : true ]
		let developer    = [ "Path" : "/Developer",    "Languages" : true, "Architectures" : true ]
		let library      = [ "Path" : "/Library",      "Languages" : true, "Architectures" : true ]
		let systemPath   = [ "Path" : "/System",       "Languages" : true, "Architectures" : false ]
		let defaultRoots = [ applications, developer, library, systemPath ]
		let defaultDict  = [ "Roots" : defaultRoots, "Trash" : false, "Strip" : false ]
		
		NSUserDefaults.standardUserDefaults().registerDefaults(defaultDict)
	}
	
	func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication!) -> Bool {
		return true
	}

	func application(sender: NSApplication!, openFile filename: String!) -> Bool {
		// TODO
		/*
		let dict = [ "Path" : filename, "Language" : true, "Architectures" : true ]
		
		self.processApplication = [ dict ]
		
		warningSelector(NSAlertAlternateReturn)
		*/
		
		return true
	}
	
	// #pragma mark - Actions
	
	@IBAction func documentationBundler(sender : NSMenuItem) {
		let docURL = NSBundle.mainBundle().URLForResource(sender.title, withExtension:nil)
		NSWorkspace.sharedWorkspace().openURL(docURL)
	}
	
	@IBAction func openWebsite(sender: AnyObject) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string:"http://monolingual.sourceforge.net/"))
	}
	
	@IBAction func donate(sender: AnyObject) {
		NSWorkspace.sharedWorkspace().openURL(self.donateURL)
	}
}
