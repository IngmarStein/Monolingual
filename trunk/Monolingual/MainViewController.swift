/*
*  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
*                2004-2014 Ingmar Stein
*  Released under the GNU GPL.  For more information, see the header file.
*/
//
//  MyResponder.swift
//  Monolingual
//
//  Created by Ingmar Stein on 13.07.14.
//
//

import Cocoa

enum MonolingualMode : Int {
	case Languages = 0
	case Architectures
}

struct ArchitectureInfo {
	let name : String
	let displayName : String
	let cpu_type : cpu_type_t
	let cpu_subtype : cpu_subtype_t
}

func mach_task_self() -> mach_port_t {
	return mach_task_self_
}

enum SMJErrorCodeSwift : Int {
	case BundleNotFound = 1000
	case UnsignedBundle = 1001
	case BadBundleSecurity = 1002
	case BadBundleCodeSigningDictionary = 1003
	
	case UnableToBless = 1010
	
	case AuthorizationDenied = 1020
	case AuthorizationCanceled = 1021
	case AuthorizationInteractionNotAllowed = 1022
	case AuthorizationFailed = 1023
}

class MainViewController : NSViewController {

	@IBOutlet strong var progressWindowController : ProgressWindowController!
	@IBOutlet strong var preferencesController : PreferencesController!
	@IBOutlet var currentArchitecture : NSTextField!

	var blacklist : NSArray!
	var languages : NSArray!
	var architectures : NSArray!

	var bytesSaved : CUnsignedLongLong = 0
	var mode : MonolingualMode = .Languages
	var processApplication : NSArray?
	var listener_queue : dispatch_queue_t?
	var peer_event_queue : dispatch_queue_t?
	var connection : xpc_connection_t?
	var progressConnection : xpc_connection_t?

	init() {
		super.init()
	}
	
	init(coder: NSCoder!) {
		super.init(coder: coder)
	}

	func finishProcessing() {
		self.progressWindowController.window.orderOut(self)
		self.progressWindowController.stop()
		NSApp.endSheet(self.progressWindowController.window, returnCode:0)
	}

	@IBAction func showPreferences(sender: AnyObject) {
		self.preferencesController.showWindow(self)
	}
	
	@IBAction func removeLanguages(sender: AnyObject) {
		// Display a warning first
		let alert = NSAlert()
		alert.alertStyle = .WarningAlertStyle
		alert.addButtonWithTitle(NSLocalizedString("Stop", comment:""))
		alert.addButtonWithTitle(NSLocalizedString("Continue", comment:""))
		alert.messageText = NSLocalizedString("Are you sure you want to remove these languages? You will not be able to restore them without reinstalling OS X.", comment:"")
		alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: {
			(responseCode: Int) in
			self.warningSelector(responseCode)
		})
	}
	
	@IBAction func removeArchitectures(sender: AnyObject) {
		self.mode = .Architectures

		log.open()
		
		let now = NSDateFormatter.localizedStringFromDate(NSDate(), dateStyle: .ShortStyle, timeStyle: .ShortStyle)
		log.message("Monolingual started at \(now)Removing architectures: ")

		let roots = self.processApplication != nil ? self.processApplication : NSUserDefaults.standardUserDefaults().arrayForKey("Roots")
	
		let archs = xpc_array_create(nil, 0)
		self.architectures.enumerateObjectsUsingBlock {
			(obj: AnyObject!, idx: Int, stop: UnsafePointer<ObjCBool>) in
			let dict = obj as NSDictionary
			let enabled = dict["Enabled"] as NSNumber
			if enabled.boolValue {
				let arch = dict["Name"] as NSString
				xpc_array_set_string(archs, kXPC_ARRAY_APPEND, arch.UTF8String)
				log.message(" \(arch)")
			}
		}
	
		log.message("\nModified files:\n")
	
		let num_archs = xpc_array_get_count(archs)
		if num_archs == self.architectures.count {
			let alert = NSAlert()
			alert.alertStyle = .InformationalAlertStyle
			alert.messageText = NSLocalizedString("Removing all architectures will make OS X inoperable. Please keep at least one architecture and try again.", comment:"")
			alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
			//NSLocalizedString("Cannot remove all architectures", "")
			log.close()
		} else if num_archs > 0 {
			// start things off if we have something to remove!
			let includes = xpc_array_create(nil, 0)
			let excludes = xpc_array_create(nil, 0)
			for root in roots as [NSDictionary] {
				let path = root["Path"] as NSString
				if root["Architectures"].boolValue {
					NSLog("Adding root %@", path)
					xpc_array_set_string(includes, kXPC_ARRAY_APPEND, path.UTF8String)
				} else {
					NSLog("Excluding root %@", path)
					xpc_array_set_string(excludes, kXPC_ARRAY_APPEND, path.UTF8String)
				}
			}
			xpc_array_set_string(excludes, kXPC_ARRAY_APPEND, "/System/Library/Frameworks")
			xpc_array_set_string(excludes, kXPC_ARRAY_APPEND, "/System/Library/PrivateFrameworks")
		
			let bl = xpc_array_create(nil, 0)
			for item in self.blacklist as [NSDictionary] {
				if item["architectures"].boolValue {
					xpc_array_set_string(bl, kXPC_ARRAY_APPEND, item["bundle"].UTF8String)
				}
			}
		
			let xpc_message = xpc_dictionary_create(nil, nil, 0)
			xpc_dictionary_set_bool(xpc_message, "strip", NSUserDefaults.standardUserDefaults().boolForKey("Strip"))
			xpc_dictionary_set_value(xpc_message, "blacklist", bl)
			xpc_dictionary_set_value(xpc_message, "includes", includes)
			xpc_dictionary_set_value(xpc_message, "excludes", excludes)
			xpc_dictionary_set_value(xpc_message, "thin", archs)
		
			self.runDeleteHelperWithArgs(xpc_message)
		} else {
			log.close()
		}
	}
	
	func processProgress(progress: xpc_object_t) {
		if xpc_dictionary_get_count(progress) == 0 {
			return
		}
		
		let file = NSString(UTF8String: xpc_dictionary_get_string(progress, "file"))
		let size = xpc_dictionary_get_uint64(progress, "size")
		self.bytesSaved += size
		
		log.message("\(file): \(size)\n")

		var message : String
		if self.mode == .Architectures {
			message = NSLocalizedString("Removing architecture from universal binary", comment:"")
		} else {
			/* parse file name */
			var lang : String? = nil
			var app : String? = nil
			
			if self.mode == .Languages {
				let pathComponents = file.componentsSeparatedByString("/")
				for pathComponent in pathComponents {
					if pathComponent.hasSuffix(".app") {
						app = pathComponent.substringToIndex(pathComponent.length - 4)
					} else if pathComponent.hasSuffix(".lproj") {
						for language in self.languages as [NSDictionary] {
							let folders = language.objectForKey("Folders") as NSArray
							if folders.containsObject(pathComponent) {
								lang = language.objectForKey("DisplayName") as? String
								break
							}
						}
					}
				}
			}
			if app {
				let removing = NSLocalizedString("Removing language", comment:"")
				let from = NSLocalizedString("from", comment:"")
				message = "\(removing) \(lang) \(from) \(app)…"
			} else if lang {
				let removing = NSLocalizedString("Removing language", comment:"")
				message = "\(removing) \(lang)…"
			} else {
				let removing = NSLocalizedString("Removing", comment:"")
				message = "\(removing) \(file)"
			}
		}
		
		self.progressWindowController.setText(message)
		self.progressWindowController.setFile(file)
		NSApp.setWindowsNeedUpdate(true)
	}
		
	func runDeleteHelperWithArgs(arguments: xpc_object_t) {
		self.bytesSaved = 0
	
		var error : NSError?
		if !MonolingualHelperClient.installWithPrompt(nil, error:&error) {
			let errorCode = SMJErrorCodeSwift.fromRaw(error!.code)
			switch errorCode! {
			case .BundleNotFound, .UnsignedBundle, .BadBundleSecurity, .BadBundleCodeSigningDictionary, .UnableToBless:
				NSLog("Failed to bless helper. Error: %@", error!)
			case .AuthorizationDenied:
				// If you can't do it because you're not administrator, then let the user know!
				let alert = NSAlert()
				alert.alertStyle = .CriticalAlertStyle
				alert.messageText = NSLocalizedString("You entered an incorrect administrator password.", comment:"")
				// NSLocalizedString("Permission Error", "")
				alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
			case .AuthorizationCanceled:
				let alert = NSAlert()
				alert.alertStyle = .CriticalAlertStyle
				alert.messageText = NSLocalizedString("Monolingual is stopping without making any changes. Your OS has not been modified.", comment:"")
				//NSLocalizedString("Nothing done", comment:"")
				alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
			case .AuthorizationInteractionNotAllowed, .AuthorizationFailed:
				let alert = NSAlert()
				alert.alertStyle = .CriticalAlertStyle
				alert.messageText = NSLocalizedString("Failed to authorize as an administrator.", comment:"")
				//NSLocalizedString("Authorization Error", comment:"")
				alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
			default: ()
			}
			log.close()
			return
		}
	
		self.connection = xpc_connection_create_mach_service("net.sourceforge.MonolingualHelper", nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
	
		if self.connection == nil {
			NSLog("Failed to create XPC connection.")
			return
		}
	
		NSProcessInfo.processInfo().disableSuddenTermination()
	
		xpc_connection_set_event_handler(self.connection) {
			(event: xpc_object_t!) in
			let type = xpc_get_type(event)
		
			if type == xpc_type_error {
				if event == xpc_error_connection_interrupted {
					NSLog("XPC connection interrupted.")
				} else if event == xpc_error_connection_invalid {
					NSLog("XPC connection invalid.")
				} else {
					NSLog("Unexpected XPC connection error.")
				}
			} else {
				NSLog("Unexpected XPC connection event.")
			}
		}
	
		// Create an anonymous listener connection that collects progress updates.
		self.progressConnection = xpc_connection_create(CString(UnsafePointer<CChar>.null()), self.listener_queue)
	
		if self.progressConnection {
			xpc_connection_set_event_handler(self.progressConnection) {
				(event: xpc_object_t!) in
				let type = xpc_get_type(event)
			
				if type == xpc_type_error {
					if event == xpc_error_termination_imminent {
						NSLog("received XPC_ERROR_TERMINATION_IMMINENT")
					} else if event == xpc_error_connection_invalid {
						NSLog("progress connection is closed")
					}
				} else if xpc_type_connection == type {
					let peer = event as xpc_connection_t
				
					xpc_connection_set_target_queue(peer, self.peer_event_queue)
					xpc_connection_set_event_handler(peer) {
						(nevent: xpc_object_t!) in
						let ntype = xpc_get_type(nevent)
					
						if xpc_type_dictionary == ntype {
							self.processProgress(nevent)
						}
					}
					xpc_connection_resume(peer)
				}
			}
			xpc_connection_resume(self.progressConnection)
		
			xpc_dictionary_set_connection(arguments, "connection", self.progressConnection)
		} else {
			NSLog("Couldn't create progress connection")
		}
	
		xpc_connection_resume(self.connection)
	
		// DEBUG
		//xpc_dictionary_set_bool(arguments, "dry_run", true)

		xpc_connection_send_message_with_reply(self.connection, arguments, dispatch_get_main_queue()) {
			(event: xpc_object_t!) in
			let type = xpc_get_type(event)
			if xpc_type_dictionary == type {
				let exit_code = xpc_dictionary_get_int64(event, "exit_code")
				NSLog("helper finished with exit code: %lld", exit_code)
			
				if self.connection {
					let exit_message = xpc_dictionary_create(nil, nil, 0)
					xpc_dictionary_set_int64(exit_message, "exit_code", exit_code)
					xpc_connection_send_message(self.connection, exit_message)
				}

				if exit_code == 0 {
					self.finishProcessing()
				}
			}
		}
	
		self.progressWindowController.start()
		self.progressWindowController.window.beginSheet(NSApp.mainWindow) {
			(response: NSModalResponse) in
			self.progressDidEnd(response)
		}
	
		let notification = NSUserNotification()
		notification.title = NSLocalizedString("Monolingual started", comment:"")
		notification.informativeText = NSLocalizedString("Started removing files", comment:"")
		
		NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
	}
	
	func progressDidEnd(returnCode:Int) {
		self.processApplication = nil

		let byteCount = NSByteCountFormatter.stringFromByteCount(Int64(self.bytesSaved), countStyle:.File)
	
		if returnCode == 1 {
			if self.progressConnection {
				if self.connection {
					let exit_message = xpc_dictionary_create(nil, nil, 0)
					xpc_dictionary_set_int64(exit_message, "exit_code", Int64(EXIT_FAILURE))
					xpc_connection_send_message(self.connection, exit_message)
				}
			
				// Cancel and release the anonymous connection which signals the remote
				// service to stop, if working.
				NSLog("Closing progress connection")
				xpc_connection_cancel(self.progressConnection)
				self.progressConnection = nil
			}

			let alert = NSAlert()
			alert.alertStyle = .InformationalAlertStyle
			alert.messageText = NSString(format: NSLocalizedString("You cancelled the removal. Some files were erased, some were not. Space saved: %@.", comment:""), byteCount)
			//alert.informativeText = NSLocalizedString("Removal cancelled", "")
			alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
		} else {
			let alert = NSAlert()
			alert.alertStyle = .InformationalAlertStyle
			alert.messageText = NSString(format:NSLocalizedString("Files removed. Space saved: %@.", comment:""), byteCount)
			//alert.informativeText = NSBeginAlertSheet(NSLocalizedString("Removal completed", comment:"")
			alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
		
			let notification = NSUserNotification()
			notification.title = NSLocalizedString("Monolingual finished", comment:"")
			notification.informativeText = NSLocalizedString("Finished removing files", comment:"")
			
			NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
		}
	
		if self.connection {
			NSLog("Closing connection")
			xpc_connection_cancel(self.connection)
			self.connection = nil
		}
	
		log.close()
	
		NSProcessInfo.processInfo().enableSuddenTermination()
	}
	
	func warningSelector(returnCode:Int) {
		if NSAlertDefaultReturn != returnCode {
			for language in self.languages as [NSDictionary] {
				let folders = language["Folders"] as [String]
				let enabled = language["Enabled"].boolValue

				if enabled && folders[0] as NSString == "en.lproj" {
					// Display a warning
					let alert = NSAlert()
					alert.alertStyle = .CriticalAlertStyle
					alert.addButtonWithTitle(NSLocalizedString("Stop", comment:""))
					alert.addButtonWithTitle(NSLocalizedString("Continue", comment:""))
					alert.messageText = NSLocalizedString("You are about to delete the English language files. Are you sure you want to do that?", comment:"")

					alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: {
						(response: NSModalResponse) in
						self.englishWarningSelector(response)
					})
					return
				}
			}
			englishWarningSelector(NSAlertSecondButtonReturn)
		}
	}
	
	func englishWarningSelector(returnCode: Int) {
		self.mode = .Languages
	
		log.open()
		let now = NSDateFormatter.localizedStringFromDate(NSDate(), dateStyle: .ShortStyle, timeStyle: .ShortStyle)
		log.message("Monolingual started at \(now)Removing languages: ")
	
		let roots = self.processApplication != nil ? self.processApplication : NSUserDefaults.standardUserDefaults().arrayForKey("Roots")

		var languageEnabled = false
		for root in roots as [NSDictionary] {
			if root["Languages"].boolValue {
				languageEnabled = true
				break
			}
		}
	
		if NSAlertFirstButtonReturn == returnCode || !languageEnabled {
			let alert = NSAlert()
			alert.alertStyle = .InformationalAlertStyle
			alert.messageText = NSLocalizedString("Monolingual is stopping without making any changes. Your OS has not been modified.", comment:"")
			alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
			//NSLocalizedString("Nothing done", comment:"")
		} else {
			let includes = xpc_array_create(nil, 0)
			let excludes = xpc_array_create(nil, 0)
			for root in roots as [NSDictionary] {
				let path = root["Path"] as NSString
				if root["Languages"].boolValue {
					NSLog("Adding root %@", path)
					xpc_array_set_string(includes, kXPC_ARRAY_APPEND, path.fileSystemRepresentation)
				} else {
					NSLog("Excluding root %@", path)
					xpc_array_set_string(excludes, kXPC_ARRAY_APPEND, path.fileSystemRepresentation)
				}
			}
			let bl = xpc_array_create(nil, 0)
			for item in self.blacklist as [NSDictionary] {
				if item["languages"].boolValue {
					let bundle = item["bundle"] as NSString
					NSLog("Blacklisting %@", bundle)
					xpc_array_set_string(bl, kXPC_ARRAY_APPEND, bundle.UTF8String)
				}
			}
			
			var rCount = 0
			let files = xpc_array_create(nil, 0)
			for language in self.languages as [NSDictionary] {
				if language["Enabled"].boolValue {
					let paths = language["Folders"] as [NSString]
					for path in paths {
						xpc_array_set_string(files, kXPC_ARRAY_APPEND, path.fileSystemRepresentation)
						if rCount != 0 {
							log.message(" ")
						}
						log.message(path)
						rCount++
					}
				}
			}
			if NSUserDefaults.standardUserDefaults().boolForKey("NIB") {
				xpc_array_set_string(files, kXPC_ARRAY_APPEND, "designable.nib")
			}
		
			log.message("\nDeleted files: \n")
			if rCount == self.languages.count {
				let alert = NSAlert()
				alert.alertStyle = .InformationalAlertStyle
				alert.messageText = NSLocalizedString("Cannot remove all languages", comment:"")
				alert.informativeText = NSLocalizedString("Removing all languages will make OS X inoperable. Please keep at least one language and try again.", comment:"")
				alert.beginSheetModalForWindow(NSApp.mainWindow, completionHandler: nil)
				log.close()
			} else if rCount > 0 {
				/* start things off if we have something to remove! */
			
				let xpc_message = xpc_dictionary_create(nil, nil, 0)
				xpc_dictionary_set_bool(xpc_message, "trash", NSUserDefaults.standardUserDefaults().boolForKey("Trash"))
				xpc_dictionary_set_int64(xpc_message, "uid", Int64(getuid()))
				xpc_dictionary_set_value(xpc_message, "blacklist", bl)
				xpc_dictionary_set_value(xpc_message, "includes", includes)
				xpc_dictionary_set_value(xpc_message, "excludes", excludes)
				xpc_dictionary_set_value(xpc_message, "directories", files)
			
				runDeleteHelperWithArgs(xpc_message)
			} else {
				log.close()
			}
		}
	}
	
	override func awakeFromNib() {
		self.listener_queue = dispatch_queue_create("net.sourceforge.Monolingual.ProgressQueue", nil)
		assert(self.listener_queue != nil)
		
		self.peer_event_queue = dispatch_queue_create("net.sourceforge.Monolingual.ProgressPanel", nil)
		assert(self.peer_event_queue != nil)
			
		var languagePref = NSUserDefaults.standardUserDefaults().objectForKey("AppleLanguages") as NSArray
			
		// Since OS X 10.9, AppleLanguages contains the standard languages even if they are not present in System Preferences
		let numUserLanguages = NSUserDefaults.standardUserDefaults().integerForKey("AppleUserLanguages")
		if numUserLanguages != 0 && numUserLanguages <= languagePref.count {
			languagePref = languagePref.subarrayWithRange(NSRange(location: 0, length: numUserLanguages))
		}
		
		var userLanguages = NSMutableSet(array: languagePref)

		// never check "English" by default
		userLanguages.addObject("en")
		
		// never check user locale by default
		let appleLocale = NSUserDefaults.standardUserDefaults().stringForKey("AppleLocale")
		if appleLocale {
			userLanguages.addObject(appleLocale.stringByReplacingOccurrencesOfString("_", withString:"-"))
		}

		let numKnownLanguages = 134
		var knownLanguages = NSMutableArray(capacity: numKnownLanguages)

		func addLanguage(code:String, name:String, folders: String...) {
			knownLanguages.addObject([ "DisplayName" : NSLocalizedString(name, comment:""),
									   "Folders" : folders,
									   "Enabled" : !userLanguages.containsObject(code)
									 ].mutableCopy())
		}
		
		addLanguage("af",      "Afrikaans",            "af.lproj", "Afrikaans.lproj")
		addLanguage("am",      "Amharic",              "am.lproj", "Amharic.lproj")
		addLanguage("ar",      "Arabic",               "ar.lproj", "Arabic.lproj")
		addLanguage("as",      "Assamese",             "as.lproj", "Assamese.lproj")
		addLanguage("ay",      "Aymara",               "ay.lproj", "Aymara.lproj.lproj")
		addLanguage("az",      "Azerbaijani",          "az.lproj", "Azerbaijani.lproj")
		addLanguage("be",      "Byelorussian",         "be.lproj", "Byelorussian.lproj")
		addLanguage("bg",      "Bulgarian",            "bg.lproj", "Bulgarian.lproj")
		addLanguage("bi",      "Bislama",              "bi.lproj", "Bislama.lproj")
		addLanguage("bn",      "Bengali",              "bn.lproj", "Bengali.lproj")
		addLanguage("bo",      "Tibetan",              "bo.lproj", "Tibetan.lproj")
		addLanguage("br",      "Breton",               "bt.lproj", "Breton.lproj")
		addLanguage("ca",      "Catalan",              "ca.lproj", "Catalan.lproj")
		addLanguage("chr",     "Cherokee",             "chr.lproj", "Cherokee.lproj")
		addLanguage("cs",      "Czech",                "cs.lproj", "cs_CZ.lproj", "Czech.lproj")
		addLanguage("cy",      "Welsh",                "cy.lproj", "Welsh.lproj")
		addLanguage("da",      "Danish",               "da.lproj", "da_DK.lproj", "Danish.lproj")
		addLanguage("de",      "German",               "de.lproj", "de_DE.lproj", "German.lproj")
		addLanguage("de-AT",   "German (Austria)",     "de_AT.lproj")
		addLanguage("de-CH",   "German (Switzerland)", "de_CH.lproj")
		addLanguage("dz",      "Dzongkha",             "dz.lproj", "Dzongkha.lproj")
		addLanguage("el",      "Greek",                "el.lproj", "el_GR.lproj", "Greek.lproj")
		addLanguage("en",      "English",              "en.lproj", "English.lproj")
		addLanguage("en-AU",   "English (Australia)",      "en_AU.lproj")
		addLanguage("en-CA",   "English (Canada)",         "en_CA.lproj")
		addLanguage("en-GB",   "English (United Kingdom)", "en_GB.lproj")
		addLanguage("en-NZ",   "English (New Zealand)",    "en_NZ.lproj")
		addLanguage("en-US",   "English (United States)",  "en_US.lproj")
		addLanguage("eo",      "Esperanto",            "eo.lproj", "Esperanto.lproj")
		addLanguage("es",      "Spanish",              "es.lproj", "es_ES.lproj", "es_419.lproj", "Spanish.lproj")
		addLanguage("et",      "Estonian",             "et.lproj", "Estonian.lproj")
		addLanguage("eu",      "Basque",               "eu.lproj", "Basque.lproj")
		addLanguage("fa",      "Farsi",                "fa.lproj", "Farsi.lproj")
		addLanguage("fi",      "Finnish",              "fi.lproj", "fi_FI.lproj", "Finnish.lproj")
		addLanguage("fil",     "Filipino",             "fil.lproj")
		addLanguage("fo",      "Faroese",              "fo.lproj", "Faroese.lproj")
		addLanguage("fr",      "French",               "fr.lproj", "fr_FR.lproj", "French.lproj")
		addLanguage("fr-CA",   "French (Canada)",      "fr_CA.lproj")
		addLanguage("fr-CH",   "French (Switzerland)", "fr_CH.lproj")
		addLanguage("ga",      "Irish",                "ga.lproj", "Irish.lproj")
		addLanguage("gd",      "Scottish",             "gd.lproj", "Scottish.lproj")
		addLanguage("gl",      "Galician",             "gl.lproj", "Galician.lproj")
		addLanguage("gn",      "Guarani",              "gn.lproj", "Guarani.lproj")
		addLanguage("gu",      "Gujarati",             "gu.lproj", "Gujarati.lproj")
		addLanguage("gv",      "Manx",                 "gv.lproj", "Manx.lproj")
		addLanguage("haw",     "Hawaiian",             "haw.lproj", "Hawaiian.lproj")
		addLanguage("he",      "Hebrew",               "he.lproj", "Hebrew.lproj")
		addLanguage("hi",      "Hindi",                "hi.lproj", "Hindi.lproj")
		addLanguage("hr",      "Croatian",             "hr.lproj", "Croatian.lproj")
		addLanguage("hu",      "Hungarian",            "hu.lproj", "hu_HU.lproj", "Hungarian.lproj")
		addLanguage("hy",      "Armenian",             "hy.lproj", "Armenian.lproj")
		addLanguage("id",      "Indonesian",           "id.lproj", "Indonesian.lproj")
		addLanguage("is",      "Icelandic",            "is.lproj", "Icelandic.lproj")
		addLanguage("it",      "Italian",              "it.lproj", "it_IT.lproj", "Italian.lproj")
		addLanguage("iu",      "Inuktitut",            "iu.lproj", "Inuktitut.lproj")
		addLanguage("ja",      "Japanese",             "ja.lproj", "ja_JP.lproj", "Japanese.lproj")
		addLanguage("jv",      "Javanese",             "jv.lproj", "Javanese.lproj")
		addLanguage("ka",      "Georgian",             "ka.lproj", "Georgian.lproj")
		addLanguage("kk",      "Kazakh",               "kk.lproj", "Kazakh.lproj")
		addLanguage("kk-Cyrl", "Kazakh (Cyrillic)",    "kk-Cyrl.lproj")
		addLanguage("kl",      "Greenlandic",          "kl.lproj", "Greenlandic.lproj")
		addLanguage("km",      "Khmer",                "km.lproj", "Khmer.lproj")
		addLanguage("kn",      "Kannada",              "kn.lproj", "Kannada.lproj")
		addLanguage("ko",      "Korean",               "ko.lproj", "ko_KR.lproj", "Korean.lproj")
		addLanguage("ks",      "Kashmiri",             "ks.lproj", "Kashmiri.lproj")
		addLanguage("ku",      "Kurdish",              "ku.lproj", "Kurdish.lproj")
		addLanguage("kw",      "Kernowek",             "kw.lproj", "Kernowek.lproj")
		addLanguage("ky",      "Kirghiz",              "ky.lproj", "Kirghiz.lproj")
		addLanguage("la",      "Latin",                "la.lproj", "Latin.lproj")
		addLanguage("lo",      "Lao",                  "lo.lproj", "Lao.lproj")
		addLanguage("lt",      "Lithuanian",           "lt.lproj", "Lithuanian.lproj")
		addLanguage("lv",      "Latvian",              "lv.lproj", "Latvian.lproj")
		addLanguage("mg",      "Malagasy",             "mg.lproj", "Malagasy.lproj")
		addLanguage("mi",      "Maori",                "mi.lproj", "Maori.lproj")
		addLanguage("mk",      "Macedonian",           "mk.lproj", "Macedonian.lproj")
		addLanguage("mr",      "Marathi",              "mr.lproj", "Marathi.lproj")
		addLanguage("ml",      "Malayalam",            "ml.lproj", "Malayalam.lproj")
		addLanguage("mn",      "Mongolian",            "mn.lproj", "Mongolian.lproj")
		addLanguage("mo",      "Moldavian",            "mo.lproj", "Moldavian.lproj")
		addLanguage("ms",      "Malay",                "ms.lproj", "Malay.lproj")
		addLanguage("mt",      "Maltese",              "mt.lproj", "Maltese.lproj")
		addLanguage("my",      "Burmese",              "my.lproj", "Burmese.lproj")
		addLanguage("ne",      "Nepali",               "ne.lproj", "Nepali.lproj")
		addLanguage("nl",      "Dutch",                "nl.lproj", "nl_NL.lproj", "Dutch.lproj")
		addLanguage("nl-BE",   "Flemish",              "nl_BE.lproj")
		addLanguage("no",      "Norwegian",            "no.lproj", "no_NO.lproj", "Norwegian.lproj")
		addLanguage("nb",      "Norwegian Bokmal",     "nb.lproj")
		addLanguage("nn",      "Norwegian Nynorsk",    "nn.lproj")
		addLanguage("om",      "Oromo",                "om.lproj", "Oromo.lproj")
		addLanguage("or",      "Oriya",                "or.lproj", "Oriya.lproj")
		addLanguage("pa",      "Punjabi",              "pa.lproj", "Punjabi.lproj")
		addLanguage("pl",      "Polish",               "pl.lproj", "pl_PL.lproj", "Polish.lproj")
		addLanguage("ps",      "Pashto",               "ps.lproj", "Pashto.lproj")
		addLanguage("pt",      "Portuguese",           "pt.lproj", "pt_PT.lproj", "pt-PT.lproj", "Portuguese.lproj")
		addLanguage("pt-BR",   "Portuguese (Brazil)",  "pt_BR.lproj", "PT_br.lproj", "pt-BR.lproj")
		addLanguage("qu",      "Quechua",              "qu.lproj", "Quechua.lproj")
		addLanguage("rn",      "Rundi",                "rn.lproj", "Rundi.lproj")
		addLanguage("ro",      "Romanian",             "ro.lproj", "Romanian.lproj")
		addLanguage("ru",      "Russian",              "ru.lproj", "Russian.lproj")
		addLanguage("rw",      "Kinyarwanda",          "rw.lproj", "Kinyarwanda.lproj")
		addLanguage("sa",      "Sanskrit",             "sa.lproj", "Sanskrit.lproj")
		addLanguage("sd",      "Sindhi",               "sd.lproj", "Sindhi.lproj")
		addLanguage("se",      "Sami",                 "se.lproj", "Sami.lproj")
		addLanguage("si",      "Sinhalese",            "si.lproj", "Sinhalese.lproj")
		addLanguage("sk",      "Slovak",               "sk.lproj", "sk_SK.lproj", "Slovak.lproj")
		addLanguage("sl",      "Slovenian",            "sl.lproj", "Slovenian.lproj")
		addLanguage("so",      "Somali",               "so.lproj", "Somali.lproj")
		addLanguage("sq",      "Albanian",             "sq.lproj", "Albanian.lproj")
		addLanguage("sr",      "Serbian",              "sr.lproj", "Serbian.lproj")
		addLanguage("su",      "Sundanese",            "su.lproj", "Sundanese.lproj")
		addLanguage("sv",      "Swedish",              "sv.lproj", "sv_SE.lproj", "Swedish.lproj")
		addLanguage("sw",      "Swahili",              "sw.lproj", "Swahili.lproj")
		addLanguage("ta",      "Tamil",                "ta.lproj", "Tamil.lproj")
		addLanguage("te",      "Telugu",               "te.lproj", "Telugu.lproj")
		addLanguage("tg",      "Tajiki",               "tg.lproj", "Tajiki.lproj")
		addLanguage("th",      "Thai",                 "th.lproj", "Thai.lproj")
		addLanguage("ti",      "Tigrinya",             "ti.lproj", "Tigrinya.lproj")
		addLanguage("tk",      "Turkmen",              "tk.lproj", "Turkmen.lproj")
		addLanguage("tk-Cyrl", "Turkmen (Cyrillic)",   "tk-Cyrl.lproj")
		addLanguage("tk-Latn", "Turkmen (Latin)",      "tk-Latn.lproj")
		addLanguage("tl",      "Tagalog",              "tl.lproj", "Tagalog.lproj")
		addLanguage("tlh",     "Klingon",              "tlh.lproj", "Klingon.lproj")
		addLanguage("tr",      "Turkish",              "tr.lproj", "tr_TR.lproj", "Turkish.lproj")
		addLanguage("tt",      "Tatar",                "tt.lproj", "Tatar.lproj")
		addLanguage("to",      "Tongan",               "to.lproj", "Tongan.lproj")
		addLanguage("ug",      "Uighur",               "ug.lproj", "Uighur.lproj")
		addLanguage("uk",      "Ukrainian",            "uk.lproj", "Ukrainian.lproj")
		addLanguage("ur",      "Urdu",                 "ur.lproj", "Urdu.lproj")
		addLanguage("uz",      "Uzbek",                "uz.lproj", "Uzbek.lproj")
		addLanguage("vi",      "Vietnamese",           "vi.lproj", "Vietnamese.lproj")
		addLanguage("yi",      "Yiddish",              "yi.lproj", "Yiddish.lproj")
		addLanguage("zh",      "Chinese",              "zh.lproj")
		addLanguage("zh-Hans", "Chinese (Simplified Han)",   "zh_Hans.lproj", "zh-Hans.lproj", "zh_CN.lproj", "zh_SC.lproj")
		addLanguage("zh-Hant", "Chinese (Traditional Han)",  "zh_Hant.lproj", "zh-Hant.lproj", "zh_TW.lproj", "zh_HK.lproj")
		
		knownLanguages.sortUsingComparator {
			(obj1: AnyObject!, obj2: AnyObject!) in
			let lang1 = obj1 as NSDictionary
			let lang2 = obj2 as NSDictionary
			return lang1["DisplayName"].compare(lang2["DisplayName"])
		}
		self.languages = knownLanguages
			
		let archs = [
			ArchitectureInfo(name:"arm",       displayName:"ARM",               cpu_type: kCPU_TYPE_ARM,       cpu_subtype: kCPU_SUBTYPE_ARM_ALL),
			ArchitectureInfo(name:"ppc",       displayName:"PowerPC",           cpu_type: kCPU_TYPE_POWERPC,   cpu_subtype: kCPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name:"ppc750",    displayName:"PowerPC G3",        cpu_type: kCPU_TYPE_POWERPC,   cpu_subtype: kCPU_SUBTYPE_POWERPC_750),
			ArchitectureInfo(name:"ppc7400",   displayName:"PowerPC G4",        cpu_type: kCPU_TYPE_POWERPC,   cpu_subtype: kCPU_SUBTYPE_POWERPC_7400),
			ArchitectureInfo(name:"ppc7450",   displayName:"PowerPC G4+",       cpu_type: kCPU_TYPE_POWERPC,   cpu_subtype: kCPU_SUBTYPE_POWERPC_7450),
			ArchitectureInfo(name:"ppc970",    displayName:"PowerPC G5",        cpu_type: kCPU_TYPE_POWERPC,   cpu_subtype: kCPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name:"ppc64",     displayName:"PowerPC 64-bit",    cpu_type: kCPU_TYPE_POWERPC64, cpu_subtype: kCPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name:"ppc970-64", displayName:"PowerPC G5 64-bit", cpu_type: kCPU_TYPE_POWERPC64, cpu_subtype: kCPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name:"x86",       displayName:"Intel",             cpu_type: kCPU_TYPE_X86,       cpu_subtype: kCPU_SUBTYPE_X86_ALL),
			ArchitectureInfo(name:"x86_64",    displayName:"Intel 64-bit",      cpu_type: kCPU_TYPE_X86_64,    cpu_subtype: kCPU_SUBTYPE_X86_64_ALL)
		]
			
		var infoCount : mach_msg_type_number_t = kHOST_BASIC_INFO_COUNT
		var hostInfo = host_basic_info_data_t(max_cpus: 0, avail_cpus: 0, memory_size: 0, cpu_type: 0, cpu_subtype: 0, cpu_threadtype: 0, physical_cpu: 0, physical_cpu_max: 0, logical_cpu: 0, logical_cpu_max: 0, max_mem: 0)
		let my_mach_host_self = mach_host_self()
		let ret = withUnsafePointer(&hostInfo) {
			(pointer: UnsafePointer<host_basic_info_data_t>) -> kern_return_t in
			return host_info(my_mach_host_self, HOST_BASIC_INFO, UnsafePointer<integer_t>(pointer), &infoCount)
		}
		mach_port_deallocate(mach_task_self(), my_mach_host_self)
			
		if hostInfo.cpu_type == kCPU_TYPE_X86 {
			// fix host_info
			var x86_64 : Int? = nil
			var x86_64_size = UInt(sizeof(Int))
			let ret = sysctlbyname("hw.optional.x86_64".bridgeToObjectiveC().UTF8String, &x86_64, &x86_64_size, nil, 0)
			if ret == 0 {
				if x86_64 {
					hostInfo = host_basic_info_data_t(
						max_cpus: hostInfo.max_cpus,
						avail_cpus: hostInfo.avail_cpus,
						memory_size: hostInfo.memory_size,
						cpu_type: kCPU_TYPE_X86_64,
						cpu_subtype: kCPU_SUBTYPE_X86_64_ALL,
						cpu_threadtype: hostInfo.cpu_threadtype,
						physical_cpu: hostInfo.physical_cpu,
						physical_cpu_max: hostInfo.physical_cpu_max,
						logical_cpu: hostInfo.logical_cpu,
						logical_cpu_max: hostInfo.logical_cpu_max,
						max_mem: hostInfo.max_mem)
				}
			}
		}

		self.currentArchitecture.stringValue = "unknown"

		var knownArchitectures = NSMutableArray(capacity: archs.count)
		for arch in archs {
			let enabled = (ret == KERN_SUCCESS && (hostInfo.cpu_type != arch.cpu_type || hostInfo.cpu_subtype < arch.cpu_subtype) && ((hostInfo.cpu_type & CPU_ARCH_ABI64) == 0 || (arch.cpu_type != (hostInfo.cpu_type & ~CPU_ARCH_ABI64))))
			let architecture : NSDictionary = [
				"Enabled" : enabled,
				"Name" : arch.name,
				"DisplayName" : arch.displayName
			]
			knownArchitectures.addObject(architecture.mutableCopy())
			if hostInfo.cpu_type == arch.cpu_type && hostInfo.cpu_subtype == arch.cpu_subtype {
				let label = NSString(format:NSLocalizedString("Current architecture: %@", comment:""), arch.displayName)
				self.currentArchitecture.stringValue = label
			}
		}
		self.architectures = knownArchitectures
		
		// load blacklist from URL
		let blacklistURL = NSURL(string:"http://monolingual.sourceforge.net/blacklist.plist")
		self.blacklist = NSArray(contentsOfURL:blacklistURL)
			
		// use blacklist from bundle as a fallback
		if self.blacklist == nil {
			let blacklistBundle = NSBundle.mainBundle().pathForResource("blacklist", ofType:"plist")
			self.blacklist = NSArray(contentsOfFile:blacklistBundle)
		}
	}
}
