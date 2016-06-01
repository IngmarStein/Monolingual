/*
*  Copyright (C) 2001, 2002  Joshua Schrier (jschrier@mac.com),
*                2004-2016 Ingmar Stein
*  Released under the GNU GPL.  For more information, see the header file.
*/
//
//  MainViewController.swift
//  Monolingual
//
//  Created by Ingmar Stein on 13.07.14.
//
//

import Cocoa

enum MonolingualMode: Int {
	case Languages = 0
	case Architectures
}

struct ArchitectureInfo {
	let name: String
	let displayName: String
	let cpu_type: cpu_type_t
	let cpu_subtype: cpu_subtype_t
}

// these defines are not (yet) visible to Swift
let CPU_TYPE_X86 : cpu_type_t					= 7
let CPU_TYPE_X86_64 : cpu_type_t				= CPU_TYPE_X86 | CPU_ARCH_ABI64
let CPU_TYPE_ARM : cpu_type_t					= 12
let CPU_TYPE_ARM64 : cpu_type_t					= CPU_TYPE_ARM | CPU_ARCH_ABI64
let CPU_TYPE_POWERPC : cpu_type_t				= 18
let CPU_TYPE_POWERPC64 : cpu_type_t				= CPU_TYPE_POWERPC | CPU_ARCH_ABI64
let CPU_SUBTYPE_ARM_ALL : cpu_subtype_t			= 0
let CPU_SUBTYPE_POWERPC_ALL : cpu_subtype_t		= 0
let CPU_SUBTYPE_POWERPC_750 : cpu_subtype_t		= 9
let CPU_SUBTYPE_POWERPC_7400 : cpu_subtype_t	= 10
let CPU_SUBTYPE_POWERPC_7450 : cpu_subtype_t	= 11
let CPU_SUBTYPE_POWERPC_970 : cpu_subtype_t		= 100
let CPU_SUBTYPE_X86_ALL : cpu_subtype_t			= 3
let CPU_SUBTYPE_X86_64_ALL : cpu_subtype_t		= 3
let CPU_SUBTYPE_X86_64_H : cpu_subtype_t		= 8

func mach_task_self() -> mach_port_t {
	return mach_task_self_
}

final class MainViewController: NSViewController, ProgressViewControllerDelegate, ProgressProtocol {

	@IBOutlet private weak var currentArchitecture: NSTextField!

	private var progressViewController: ProgressViewController?

	private var blacklist: [BlacklistEntry]?
	dynamic var languages: [LanguageSetting]!
	dynamic var architectures: [ArchitectureSetting]!

	private var mode: MonolingualMode = .Languages
	private var processApplication: Root?
	private var processApplicationObserver: NSObjectProtocol?
	private var helperConnection: NSXPCConnection?
	private var progress: NSProgress?

	private let sipProtectedLocations = [ "/System", "/bin" ]

	private lazy var xpcServiceConnection: NSXPCConnection = {
		let connection = NSXPCConnection(serviceName: "com.github.IngmarStein.Monolingual.XPCService")
		connection.remoteObjectInterface = NSXPCInterface(with: XPCServiceProtocol.self)
		connection.resume()
		return connection
	}()

	private var roots: [Root] {
		if let application = self.processApplication {
			return [ application ]
		} else {
			let pref = NSUserDefaults.standard().array(forKey: "Roots") as? [[NSObject : AnyObject]]
			return pref?.map { Root(dictionary: $0) } ?? [Root]()
		}
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	private func finishProcessing() {
		progressDidEnd(completed: true)
	}

	@IBAction func removeLanguages(_ sender: AnyObject) {
		// Display a warning first
		let alert = NSAlert()
		alert.alertStyle = .warningAlertStyle
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
		alert.messageText = NSLocalizedString("Are you sure you want to remove these languages? You will not be able to restore them without reinstalling OS X.", comment: "")
		alert.beginSheetModal(for: self.view.window!) { responseCode in
			if NSAlertSecondButtonReturn == responseCode {
				self.checkAndRemove()
			}
		}
	}

	@IBAction func removeArchitectures(_ sender: AnyObject) {
		self.mode = .Architectures

		log.open()

		let now = NSDateFormatter.localizedString(from: NSDate(), dateStyle: .shortStyle, timeStyle: .shortStyle)
		log.message("Monolingual started at \(now)\nRemoving architectures: ")

		let archs = self.architectures.filter { $0.enabled } .map { $0.name }
		for arch in archs {
			log.message(" \(arch)")
		}

		log.message("\nModified files:\n")

		let num_archs = archs.count
		if num_archs == self.architectures.count {
			let alert = NSAlert()
			alert.alertStyle = .informationalAlertStyle
			alert.messageText = NSLocalizedString("Removing all architectures will make OS X inoperable. Please keep at least one architecture and try again.", comment: "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
			//NSLocalizedString("Cannot remove all architectures", "")
			log.close()
		} else if num_archs > 0 {
			// start things off if we have something to remove!
			let roots = self.roots

			let request = HelperRequest()
			request.doStrip = NSUserDefaults.standard().bool(forKey: "Strip")
			request.bundleBlacklist = Set<String>(self.blacklist!.filter { $0.architectures } .map { $0.bundle })
			request.includes = roots.filter { $0.architectures } .map { $0.path }
			request.excludes = roots.filter { !$0.architectures } .map { $0.path } + sipProtectedLocations
			request.thin = archs

			for item in request.bundleBlacklist! {
				NSLog("Blacklisting \(item)")
			}
			for include in request.includes! {
				NSLog("Adding root \(include)")
			}
			for exclude in request.excludes! {
				NSLog("Excluding root \(exclude)")
			}

			self.checkAndRunHelper(arguments: request)
		} else {
			log.close()
		}
	}

	func processed(file: String, size: Int, appName: String?) {
		if let progress = self.progress {
			let count = progress.userInfo[NSProgressFileCompletedCountKey as NSString] as? Int ?? 0
			progress.setUserInfoObject((count + 1) as NSNumber, forKey: NSProgressFileCompletedCountKey)
			progress.setUserInfoObject(NSURL(fileURLWithPath: file), forKey: NSProgressFileURLKey)
			progress.setUserInfoObject(size as NSNumber, forKey: "sizeDifference")
			if let appName = appName {
				progress.setUserInfoObject(appName as NSString, forKey: "appName")
			}
			progress.completedUnitCount += size
		}
	}

	override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>?) {
		if keyPath == "completedUnitCount" {
			if let progress = object as? NSProgress, url = progress.userInfo[NSProgressFileURLKey as NSString] as? NSURL, size = progress.userInfo["sizeDifference"] as? Int {
				processProgress(file: url, size:size, appName:progress.userInfo["appName"] as? String)
			}
		}
	}

	private func processProgress(file: NSURL, size: Int, appName: String?) {
		log.message("\(file.path!): \(size)\n")

		let message : String
		if self.mode == .Architectures {
			message = NSLocalizedString("Removing architecture from universal binary", comment: "")
		} else {
			// parse file name
			var lang : String?

			if self.mode == .Languages {
				for pathComponent in file.pathComponents! {
					if (pathComponent as NSString).pathExtension == "lproj" {
						for language in self.languages {
							if language.folders.contains(pathComponent) {
								lang = language.displayName
								break
							}
						}
					}
				}
			}
			if let app = appName, lang = lang {
				message = String(format: NSLocalizedString("Removing language %@ from %@…", comment: ""), lang as NSString, app as NSString)
			} else if let lang = lang {
				message = String(format: NSLocalizedString("Removing language %@…", comment: ""), lang as NSString)
			} else {
				message = String(format: NSLocalizedString("Removing %@…", comment: ""), file)
			}
		}

		dispatch_async(dispatch_get_main_queue()) {
			if let viewController = self.progressViewController, path = file.path {
				viewController.text = message
				viewController.file = path
				NSApp.setWindowsNeedUpdate(true)
			}
		}
	}

	func installHelper(reply:(Bool) -> Void) {
		let xpcService = self.xpcServiceConnection.remoteObjectProxyWithErrorHandler() { error -> Void in
			NSLog("XPCService error: %@", error)
		} as? XPCServiceProtocol

		if let xpcService = xpcService {
			xpcService.installHelperTool { error in
				if let error = error {
					dispatch_async(dispatch_get_main_queue()) {
						let alert = NSAlert()
						alert.alertStyle = .criticalAlertStyle
						alert.messageText = error.localizedDescription
						alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
						log.close()
					}
					reply(false)
				} else {
					reply(true)
				}
			}
		}
	}

	private func runHelper(arguments: HelperRequest) {
		NSProcessInfo.processInfo().disableSuddenTermination()

		let progress = NSProgress(totalUnitCount: -1)
		progress.becomeCurrent(withPendingUnitCount: -1)
		progress.addObserver(self, forKeyPath: "completedUnitCount", options: .new, context: nil)

		// DEBUG
		//arguments.dryRun = true

		let helper = helperConnection!.remoteObjectProxyWithErrorHandler() { error in
			NSLog("Error communicating with helper: %@", error)
			dispatch_async(dispatch_get_main_queue()) {
				self.finishProcessing()
			}
		} as! HelperProtocol

		helper.processRequest(arguments, progress:self) { exitCode in
			NSLog("helper finished with exit code: \(exitCode)")
			helper.exitWithCode(exitCode)
			if exitCode == Int(EXIT_SUCCESS) {
				dispatch_async(dispatch_get_main_queue()) {
					self.finishProcessing()
				}
			}
		}

		progress.resignCurrent()
		self.progress = progress

		if self.progressViewController == nil {
			let storyboard = NSStoryboard(name:"Main", bundle:nil)
			self.progressViewController = storyboard.instantiateController(withIdentifier: "ProgressViewController") as? ProgressViewController
		}
		self.progressViewController?.delegate = self
		if self.progressViewController!.presenting == nil {
			self.present(asSheet: self.progressViewController!)
		}

		let notification = NSUserNotification()
		notification.title = NSLocalizedString("Monolingual started", comment: "")
		notification.informativeText = NSLocalizedString("Started removing files", comment: "")

		NSUserNotificationCenter.default().deliver(notification)
	}

	private func checkAndRunHelper(arguments: HelperRequest) {
		let xpcService = self.xpcServiceConnection.remoteObjectProxyWithErrorHandler() { error -> Void in
			NSLog("XPCService error: %@", error)
		} as? XPCServiceProtocol

		if let xpcService = xpcService {
			xpcService.connect() { endpoint -> Void in
				if let endpoint = endpoint {
					var performInstallation = false
					let connection = NSXPCConnection(listenerEndpoint: endpoint)
					let interface = NSXPCInterface(with: HelperProtocol.self)
					interface.setInterface(NSXPCInterface(with: ProgressProtocol.self), for: #selector(HelperProtocol.processRequest(_:progress:reply:)), argumentIndex: 1, ofReply: false)
					connection.remoteObjectInterface = interface
					connection.invalidationHandler = {
						NSLog("XPC connection to helper invalidated.")
						self.helperConnection = nil
						if performInstallation {
							self.installHelper() { success in
								if success {
									self.checkAndRunHelper(arguments: arguments)
								}
							}
						}
					}
					connection.resume()
					self.helperConnection = connection

					if let connection = self.helperConnection {
						let helper = connection.remoteObjectProxyWithErrorHandler() { error in
							NSLog("Error connecting to helper: %@", error)
						} as! HelperProtocol

						helper.getVersionWithReply() { installedVersion in
							xpcService.bundledHelperVersion() { bundledVersion in
								if installedVersion == bundledVersion {
									// helper is current
									dispatch_async(dispatch_get_main_queue()) {
										self.runHelper(arguments: arguments)
									}
								} else {
									// helper is different version
									performInstallation = true
									helper.uninstall()
									helper.exitWithCode(Int(EXIT_SUCCESS))
									connection.invalidate()
								}
							}
						}
					}
				} else {
					NSLog("Failed to get XPC endpoint.")
					self.installHelper() { success in
						if success {
							self.checkAndRunHelper(arguments: arguments)
						}
					}
				}
			}
		}
	}

	func progressViewControllerDidCancel(_ progressViewController: ProgressViewController) {
		progressDidEnd(completed: false)
	}

	private func progressDidEnd(completed: Bool) {
		if self.progress == nil {
			return
		}

		self.processApplication = nil
		self.dismiss(self.progressViewController!)

		let progress = self.progress!
		let byteCount = NSByteCountFormatter.string(fromByteCount: max(progress.completedUnitCount, 0), countStyle: .file)
		self.progress = nil

		if !completed {
			// cancel the current progress which tells the helper to stop
			progress.cancel()
			NSLog("Closing progress connection")

			if let helper = self.helperConnection?.remoteObjectProxy as? HelperProtocol {
				helper.exitWithCode(Int(EXIT_FAILURE))
			}

			let alert = NSAlert()
			alert.alertStyle = .informationalAlertStyle
			alert.messageText = String(format: NSLocalizedString("You cancelled the removal. Some files were erased, some were not. Space saved: %@.", comment: ""), byteCount as NSString)
			//alert.informativeText = NSLocalizedString("Removal cancelled", "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
		} else {
			let alert = NSAlert()
			alert.alertStyle = .informationalAlertStyle
			alert.messageText = String(format: NSLocalizedString("Files removed. Space saved: %@.", comment: ""), byteCount as NSString)
			//alert.informativeText = NSBeginAlertSheet(NSLocalizedString("Removal completed", comment: "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: nil)

			let notification = NSUserNotification()
			notification.title = NSLocalizedString("Monolingual finished", comment: "")
			notification.informativeText = NSLocalizedString("Finished removing files", comment: "")

			NSUserNotificationCenter.default().deliver(notification)
		}

		if let connection = self.helperConnection {
			NSLog("Closing connection to helper")
			connection.invalidate()
			self.helperConnection = nil
		}

		log.close()

		NSProcessInfo.processInfo().enableSuddenTermination()
	}

	private func checkAndRemove() {
		if checkRoots() && checkLanguages() {
			doRemoveLanguages()
		}
	}

	private func checkRoots() -> Bool {
		var languageEnabled = false
		let roots = self.roots
		for root in roots {
			if root.languages {
				languageEnabled = true
				break
			}
		}

		if !languageEnabled {
			let alert = NSAlert()
			alert.alertStyle = .informationalAlertStyle
			alert.messageText = NSLocalizedString("Monolingual is stopping without making any changes. Your OS has not been modified.", comment: "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
			//NSLocalizedString("Nothing done", comment: "")
		}

		return languageEnabled
	}

	private func checkLanguages() -> Bool {
		var englishChecked = false
		for language in self.languages {
			if language.enabled && language.folders[0] == "en.lproj" {
				englishChecked = true
				break
			}
		}

		if englishChecked {
			// Display a warning
			let alert = NSAlert()
			alert.alertStyle = .criticalAlertStyle
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
			alert.messageText = NSLocalizedString("You are about to delete the English language files. Are you sure you want to do that?", comment: "")

			alert.beginSheetModal(for: self.view.window!) { response in
				if response == NSAlertSecondButtonReturn {
					self.doRemoveLanguages()
				}
			}
		}

		return !englishChecked
	}

	private func doRemoveLanguages() {
		self.mode = .Languages

		log.open()
		let now = NSDateFormatter.localizedString(from: NSDate(), dateStyle: .shortStyle, timeStyle: .shortStyle)
		log.message("Monolingual started at \(now)\nRemoving languages: ")

		let roots = self.roots

		let includes = roots.filter { $0.languages } .map { $0.path }
		let excludes = roots.filter { !$0.languages } .map { $0.path } + sipProtectedLocations
		let bl = self.blacklist!.filter { $0.languages } .map { $0.bundle }

		for item in bl {
			NSLog("Blacklisting \(item)")
		}
		for include in includes {
			NSLog("Adding root \(include)")
		}
		for exclude in excludes {
			NSLog("Excluding root \(exclude)")
		}

		var rCount = 0
		var folders = Set<String>()
		for language in self.languages {
			if language.enabled {
				for path in language.folders {
					folders.insert(path)
					if rCount != 0 {
						log.message(" ")
					}
					log.message(path)
					rCount += 1
				}
			}
		}
		if NSUserDefaults.standard().bool(forKey: "NIB") {
			folders.insert("designable.nib")
		}

		log.message("\nDeleted files: \n")
		if rCount == self.languages.count {
			let alert = NSAlert()
			alert.alertStyle = .informationalAlertStyle
			alert.messageText = NSLocalizedString("Cannot remove all languages", comment: "")
			alert.informativeText = NSLocalizedString("Removing all languages will make OS X inoperable. Please keep at least one language and try again.", comment: "")
			alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
			log.close()
		} else if rCount > 0 {
			// start things off if we have something to remove!

			let request = HelperRequest()
			request.trash = NSUserDefaults.standard().bool(forKey: "Trash")
			request.uid = getuid()
			request.bundleBlacklist = Set<String>(bl)
			request.includes = includes
			request.excludes = excludes
			request.directories = folders

			checkAndRunHelper(arguments: request)
		} else {
			log.close()
		}
	}

	override func viewDidLoad() {
		let currentLocale = NSLocale.current()

		// never check the user's preferred languages, English the the user's locale be default
		let userLanguages = Set<String>((NSLocale.preferredLanguages()).map {
			return $0.replacingOccurrences(of: "-", with:"_")
		} + ["en", currentLocale.localeIdentifier])

		let availableLocalizations = Set<String>((NSLocale.availableLocaleIdentifiers())
			// add some known locales not contained in availableLocaleIdentifiers
			+ ["ach", "an", "ast", "ay", "bi", "co", "fur", "gd", "gn", "ia", "jv", "ku", "la", "mi", "md", "no", "oc", "qu", "sa", "sd", "se", "su", "tet", "tk_Cyrl", "tl", "tlh", "tt", "wa", "yi", "zh_CN", "zh_TW" ])

		let systemLocale = NSLocale(localeIdentifier: "en_US_POSIX")
		self.languages = [String](availableLocalizations).map { (localeIdentifier) -> LanguageSetting in
			var folders = ["\(localeIdentifier).lproj"]
			let components = NSLocale.components(fromLocaleIdentifier: localeIdentifier)
			if let language = components[NSLocaleLanguageCode], country = components[NSLocaleCountryCode] {
				folders.append("\(language)-\(country).lproj")
				folders.append("\(language)_\(country).lproj")
			} else if let displayName = systemLocale.displayName(forKey: NSLocaleIdentifier as NSString, value: localeIdentifier as NSString) {
				folders.append("\(displayName).lproj")
			}
			let displayName = currentLocale.displayName(forKey: NSLocaleIdentifier as NSString, value: localeIdentifier as NSString) ?? NSLocalizedString("locale_\(localeIdentifier)", comment: "")
			return LanguageSetting(enabled: !userLanguages.contains(localeIdentifier), folders: folders, displayName: displayName)
		}.sorted { $0.displayName < $1.displayName }

		let archs = [
			ArchitectureInfo(name:"arm",       displayName:"ARM",                    cpu_type: CPU_TYPE_ARM,       cpu_subtype: CPU_SUBTYPE_ARM_ALL),
			ArchitectureInfo(name:"ppc",       displayName:"PowerPC",                cpu_type: CPU_TYPE_POWERPC,   cpu_subtype: CPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name:"ppc750",    displayName:"PowerPC G3",             cpu_type: CPU_TYPE_POWERPC,   cpu_subtype: CPU_SUBTYPE_POWERPC_750),
			ArchitectureInfo(name:"ppc7400",   displayName:"PowerPC G4",             cpu_type: CPU_TYPE_POWERPC,   cpu_subtype: CPU_SUBTYPE_POWERPC_7400),
			ArchitectureInfo(name:"ppc7450",   displayName:"PowerPC G4+",            cpu_type: CPU_TYPE_POWERPC,   cpu_subtype: CPU_SUBTYPE_POWERPC_7450),
			ArchitectureInfo(name:"ppc970",    displayName:"PowerPC G5",             cpu_type: CPU_TYPE_POWERPC,   cpu_subtype: CPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name:"ppc64",     displayName:"PowerPC 64-bit",         cpu_type: CPU_TYPE_POWERPC64, cpu_subtype: CPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name:"ppc970-64", displayName:"PowerPC G5 64-bit",      cpu_type: CPU_TYPE_POWERPC64, cpu_subtype: CPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name:"x86",       displayName:"Intel 32-bit",           cpu_type: CPU_TYPE_X86,       cpu_subtype: CPU_SUBTYPE_X86_ALL),
			ArchitectureInfo(name:"x86_64",    displayName:"Intel 64-bit",           cpu_type: CPU_TYPE_X86_64,    cpu_subtype: CPU_SUBTYPE_X86_64_ALL),
			ArchitectureInfo(name:"x86_64h",   displayName:"Intel 64-bit (Haswell)", cpu_type: CPU_TYPE_X86_64,    cpu_subtype: CPU_SUBTYPE_X86_64_H)
		]

		var infoCount = mach_msg_type_number_t(sizeof(host_basic_info_data_t)/sizeof(integer_t)) // HOST_BASIC_INFO_COUNT
		var hostInfo = host_basic_info_data_t(max_cpus: 0, avail_cpus: 0, memory_size: 0, cpu_type: 0, cpu_subtype: 0, cpu_threadtype: 0, physical_cpu: 0, physical_cpu_max: 0, logical_cpu: 0, logical_cpu_max: 0, max_mem: 0)
		let my_mach_host_self = mach_host_self()
		let ret = withUnsafeMutablePointer(&hostInfo) {
			(pointer: UnsafeMutablePointer<host_basic_info_data_t>) in
			host_info(my_mach_host_self, HOST_BASIC_INFO, UnsafeMutablePointer<integer_t>(pointer), &infoCount)
		}
		mach_port_deallocate(mach_task_self(), my_mach_host_self)

		if hostInfo.cpu_type == CPU_TYPE_X86 {
			// fix host_info
			var x86_64 : Int = 0
			var x86_64_size = Int(sizeof(Int))
			let ret = sysctlbyname("hw.optional.x86_64", &x86_64, &x86_64_size, nil, 0)
			if ret == 0 {
				if x86_64 != 0 {
					hostInfo = host_basic_info_data_t(
						max_cpus: hostInfo.max_cpus,
						avail_cpus: hostInfo.avail_cpus,
						memory_size: hostInfo.memory_size,
						cpu_type: CPU_TYPE_X86_64,
						cpu_subtype: (hostInfo.cpu_subtype == CPU_SUBTYPE_X86_64_H) ? CPU_SUBTYPE_X86_64_H : CPU_SUBTYPE_X86_64_ALL,
						cpu_threadtype: hostInfo.cpu_threadtype,
						physical_cpu: hostInfo.physical_cpu,
						physical_cpu_max: hostInfo.physical_cpu_max,
						logical_cpu: hostInfo.logical_cpu,
						logical_cpu_max: hostInfo.logical_cpu_max,
						max_mem: hostInfo.max_mem)
				}
			}
		}

		self.currentArchitecture.stringValue = NSLocalizedString("unknown", comment: "")

		self.architectures = archs.map { arch in
			let enabled = (ret == KERN_SUCCESS && hostInfo.cpu_type != arch.cpu_type)
			let architecture = ArchitectureSetting(enabled: enabled, name: arch.name, displayName: arch.displayName)
			if hostInfo.cpu_type == arch.cpu_type && hostInfo.cpu_subtype == arch.cpu_subtype {
				self.currentArchitecture.stringValue = String(format: NSLocalizedString("Current architecture: %@", comment: ""), arch.displayName as NSString)
			}
			return architecture
		}

		// load blacklist from bundle
		if let blacklistBundle = NSBundle.main().urlForResource("blacklist", withExtension:"plist"), entries = NSArray(contentsOf: blacklistBundle) as? [[NSObject:AnyObject]] {
			self.blacklist = entries.map { BlacklistEntry(dictionary: $0) }
		}
		// load remote blacklist asynchronously
		dispatch_async(dispatch_get_main_queue()) {
			if let blacklistURL = NSURL(string:"https://ingmarstein.github.io/Monolingual/blacklist.plist"), entries = NSArray(contentsOf: blacklistURL) as? [[NSObject:AnyObject]] {
				self.blacklist = entries.map { BlacklistEntry(dictionary: $0) }
			}
		}

		self.processApplicationObserver = NSNotificationCenter.default().addObserver(forName: ProcessApplicationNotification, object: nil, queue: nil) { notification in
			self.processApplication = Root(dictionary: notification.userInfo!)
		}
	}

	deinit {
		if let observer = self.processApplicationObserver {
			NSNotificationCenter.default().removeObserver(observer)
		}
		xpcServiceConnection.invalidate()
	}

}
