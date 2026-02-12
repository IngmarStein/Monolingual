//
//  MainView.swift
//  MainView
//
//  Created by Ingmar Stein on 27.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI
import OSLog
#if canImport(HelperShared)
import HelperShared
#endif

func mach_task_self() -> mach_port_t {
	mach_task_self_
}

struct MainView: View {
	enum MonolingualMode: Int {
		case languages = 0
		case architectures
	}

	struct ArchitectureInfo {
		let name: String
		let displayName: String
		let cpuType: cpu_type_t
		let cpuSubtype: cpu_subtype_t
	}

	@State private var languages: [LanguageSetting] = []
	@State private var architectures: [ArchitectureSetting] = []
	@State private var currentArchitecture = "unknown"
	@State private var showingRemoveLanguagesAlert = false
	@State private var showingUnchangedAlert = false
	@State private var showingEnglishAlert = false
	@State private var showingProgressView = false
	@State private var showingAllArchitecturesAlert = false

	@State private var blocklist: [BlocklistEntry]?

	@State private var mode: MonolingualMode = .languages
	@StateObject private var helperTask = HelperTask()
	@State private var processApplication: Root?
	@State private var processApplicationObserver: NSObjectProtocol?

	private let sipProtectedLocations = ["/System", "/bin"]

	private let logger = Logger()

	private var roots: [Root] {
		if let application = self.processApplication {
			return [application]
		} else {
			if let pref = UserDefaults.standard.array(forKey: "Roots") as? [[String: AnyObject]] {
				return pref.map { Root(dictionary: $0) }
			} else {
				return [Root]()
			}
		}
	}

	func removeArchitectures() {
		mode = .architectures

		log.open()

		let version = (Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String) ?? "vUNKNOWN"
		log.message("Monolingual \(version) started\n")
		log.message("Removing architectures:")

		let archs = architectures.filter(\.enabled).map(\.name)
		for arch in archs {
			log.message(" \(arch)", timestamp: false)
		}

		log.message("\nModified files:\n")

		let numArchs = archs.count
		if numArchs == architectures.count {
			showingAllArchitecturesAlert = true
			log.close()
		} else if numArchs > 0 {
			// start things off if we have something to remove!
			let roots = roots

			let request = HelperRequest()
			request.doStrip = UserDefaults.standard.bool(forKey: "Strip")
			request.bundleBlocklist = Set<String>(blocklist!.filter(\.architectures).map(\.bundle))
			request.includes = roots.filter(\.architectures).map(\.path)
			request.excludes = roots.filter { !$0.architectures }.map(\.path) + sipProtectedLocations
			request.thin = archs

			for item in request.bundleBlocklist! {
				logger.info("Blocking \(item, privacy: .public)")
			}
			for include in request.includes! {
				logger.info("Adding root \(include, privacy: .public)")
			}
			for exclude in request.excludes! {
				logger.info("Excluding root \(exclude, privacy: .public)")
			}

			helperTask.checkAndRunHelper(arguments: request)
		} else {
			log.close()
		}
	}

	private func checkAndRemove() {
		if checkRoots(), checkLanguages() {
			removeLanguages()
		}
	}

	private func checkRoots() -> Bool {
		var languageEnabled = false
		let roots = roots
		for root in roots where root.languages {
			languageEnabled = true
			break
		}

		if !languageEnabled {
			showingUnchangedAlert = true
		}

		return languageEnabled
	}

	private func checkLanguages() -> Bool {
		var englishChecked = false
		for language in languages where language.enabled && language.folders[0] == "en.lproj" {
			englishChecked = true
			break
		}

		if englishChecked {
			// Display a warning
			showingEnglishAlert = true
		}

		return !englishChecked
	}

	private func removeLanguages() {
		mode = .languages

		log.open()
		let version = (Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String) ?? "vUNKNOWN"
		log.message("Monolingual \(version) started\n")
		log.message("Removing languages:")

		let roots = roots

		let includes = roots.filter(\.languages).map(\.path)
		let excludes = roots.filter { !$0.languages }.map(\.path) + sipProtectedLocations
		let bl = blocklist!.filter(\.languages).map(\.bundle)

		for item in bl {
			logger.info("Blocklisting \(item, privacy: .public)")
		}
		for include in includes {
			logger.info("Adding root \(include, privacy: .public)")
		}
		for exclude in excludes {
			logger.info("Excluding root \(exclude, privacy: .public)")
		}

		var rCount = 0
		var folders = Set<String>()
		for language in languages where language.enabled {
			for path in language.folders {
				folders.insert(path)
				log.message(" \(path)", timestamp: false)
				rCount += 1
			}
		}
		if UserDefaults.standard.bool(forKey: "NIB") {
			folders.insert("designable.nib")
		}

		log.message("\n", timestamp: false)
		if UserDefaults.standard.bool(forKey: "Trash") {
			log.message("Trashed files:\n")
		} else {
			log.message("Deleted files:\n")
		}

		if rCount > 0 {
			// start things off if we have something to remove!

			let request = HelperRequest()
			request.trash = UserDefaults.standard.bool(forKey: "Trash")
			request.uid = getuid()
			request.bundleBlocklist = Set<String>(bl)
			request.includes = includes
			request.excludes = excludes
			request.directories = folders

			helperTask.checkAndRunHelper(arguments: request)
		} else {
			log.close()
		}
	}

	private func loadData() {
		let currentLocale = Locale.current

		// never check the user's preferred languages, English and the user's locale by default
		let userLanguages = Set<String>(Locale.preferredLanguages.flatMap { language -> [String] in
			let components = language.components(separatedBy: "-")
			if components.count == 1 {
				return [components[0]]
			} else {
				return [components[0], components.joined(separator: "_")]
			}
		} + ["en", currentLocale.identifier, currentLocale.languageCode ?? ""])

		let knownLocales: [String] = ["ach", "an", "ast", "ay", "bi", "co", "fur", "gd", "gn", "ia", "jv", "ku", "la", "mi", "md", "no", "oc", "qu", "sa", "sd", "se", "su", "tet", "tk_Cyrl", "tl", "tlh", "tt", "wa", "yi", "zh_CN", "zh_TW"]
		// add some known locales not contained in availableLocaleIdentifiers
		let availableLocalizations = Set<String>(Locale.availableIdentifiers + knownLocales)

		let systemLocale = Locale(identifier: "en_US_POSIX")
		languages = [String](availableLocalizations).map { localeIdentifier -> LanguageSetting in
			var folders = ["\(localeIdentifier).lproj"]
			let locale = Locale(identifier: localeIdentifier)
			if let language = locale.languageCode, let region = locale.regionCode {
				if let variantCode = locale.variantCode {
					// e.g. en_US_POSIX
					folders.append("\(language)-\(region)_\(variantCode).lproj")
					folders.append("\(language)_\(region)_\(variantCode).lproj")
				} else if let script = locale.scriptCode {
					// e.g. zh_Hans_SG
					folders.append("\(language)-\(script)-\(region).lproj")
					folders.append("\(language)_\(script)_\(region).lproj")
				} else {
					folders.append("\(language)-\(region).lproj")
					folders.append("\(language)_\(region).lproj")
				}
			} else if let language = locale.languageCode, let script = locale.scriptCode {
				// e.g. zh_Hans
				folders.append("\(language)-\(script).lproj")
				folders.append("\(language)_\(script).lproj")
			} else if let displayName = systemLocale.localizedString(forIdentifier: localeIdentifier) {
				folders.append("\(displayName).lproj")
			}
			let displayName = currentLocale.localizedString(forIdentifier: localeIdentifier) ?? NSLocalizedString("locale_\(localeIdentifier)", comment: "")
			let setting = LanguageSetting(enabled: !userLanguages.contains(localeIdentifier), folders: folders, displayName: displayName)
			return setting
		}.sorted { $0.displayName < $1.displayName }

		// swiftlint:disable comma
		let archs = [
			ArchitectureInfo(name: "arm", displayName: "ARM", cpuType: CPU_TYPE_ARM, cpuSubtype: CPU_SUBTYPE_ARM_ALL),
			ArchitectureInfo(name: "arm64", displayName: "ARM64", cpuType: CPU_TYPE_ARM64, cpuSubtype: CPU_SUBTYPE_ARM64_ALL),
			ArchitectureInfo(name: "arm64v8", displayName: "ARM64v8", cpuType: CPU_TYPE_ARM64, cpuSubtype: CPU_SUBTYPE_ARM64_V8),
			ArchitectureInfo(name: "arm64e", displayName: "ARM64E", cpuType: CPU_TYPE_ARM64, cpuSubtype: CPU_SUBTYPE_ARM64E),
			ArchitectureInfo(name: "ppc", displayName: "PowerPC", cpuType: CPU_TYPE_POWERPC, cpuSubtype: CPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name: "ppc750", displayName: "PowerPC G3", cpuType: CPU_TYPE_POWERPC, cpuSubtype: CPU_SUBTYPE_POWERPC_750),
			ArchitectureInfo(name: "ppc7400", displayName: "PowerPC G4", cpuType: CPU_TYPE_POWERPC, cpuSubtype: CPU_SUBTYPE_POWERPC_7400),
			ArchitectureInfo(name: "ppc7450", displayName: "PowerPC G4+", cpuType: CPU_TYPE_POWERPC, cpuSubtype: CPU_SUBTYPE_POWERPC_7450),
			ArchitectureInfo(name: "ppc970", displayName: "PowerPC G5", cpuType: CPU_TYPE_POWERPC, cpuSubtype: CPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name: "ppc64", displayName: "PowerPC 64-bit", cpuType: CPU_TYPE_POWERPC64, cpuSubtype: CPU_SUBTYPE_POWERPC_ALL),
			ArchitectureInfo(name: "ppc970-64", displayName: "PowerPC G5 64-bit", cpuType: CPU_TYPE_POWERPC64, cpuSubtype: CPU_SUBTYPE_POWERPC_970),
			ArchitectureInfo(name: "x86", displayName: "Intel 32-bit", cpuType: CPU_TYPE_X86, cpuSubtype: CPU_SUBTYPE_X86_ALL),
			ArchitectureInfo(name: "x86_64", displayName: "Intel 64-bit", cpuType: CPU_TYPE_X86_64, cpuSubtype: CPU_SUBTYPE_X86_64_ALL),
			ArchitectureInfo(name: "x86_64h", displayName: "Intel 64-bit (Haswell)", cpuType: CPU_TYPE_X86_64, cpuSubtype: CPU_SUBTYPE_X86_64_H),
		]
		// swiftlint:enable comma

		var infoCount = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size) // HOST_BASIC_INFO_COUNT
		let hostInfoPointer = host_basic_info_t.allocate(capacity: 1)
		let myMachHostSelf = mach_host_self()
		let ret = hostInfoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { pointer in
				host_info(myMachHostSelf, HOST_BASIC_INFO, pointer, &infoCount)
		}
		mach_port_deallocate(mach_task_self(), myMachHostSelf)
		var hostInfo = hostInfoPointer.move()
		hostInfoPointer.deallocate()

		if hostInfo.cpu_type == CPU_TYPE_X86 {
			// fix host_info
			var x8664: Int = 0
			var x8664Size = Int(MemoryLayout<Int>.size)
			let ret = sysctlbyname("hw.optional.x86_64", &x8664, &x8664Size, nil, 0)
			if ret == 0 {
				if x8664 != 0 {
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
						max_mem: hostInfo.max_mem
					)
				}
			}
		}

		var curArch = NSLocalizedString("unknown", comment: "")
		architectures = archs.map { arch in
			let enabled = ret == KERN_SUCCESS && hostInfo.cpu_type != arch.cpuType
			let architecture = ArchitectureSetting(enabled: enabled, name: arch.name, displayName: arch.displayName)
			if hostInfo.cpu_type == arch.cpuType, hostInfo.cpu_subtype == arch.cpuSubtype {
				curArch = arch.displayName
			}
			return architecture
		}
		currentArchitecture = curArch

		// load blocklist from asset catalog
		if let blocklist = NSDataAsset(name: "blocklist") {
			let decoder = PropertyListDecoder()
			self.blocklist = try? decoder.decode([BlocklistEntry].self, from: blocklist.data)
		}
		/*
		 self.processApplicationObserver = NotificationCenter.default.addObserver(forName: processApplicationNotification, object: nil, queue: nil) { [weak self] notification in
		 if let dictionary = notification.userInfo {
		 self?.processApplication = Root(dictionary: dictionary)
		 }
		 }
		 */
	}

	/*
	deinit {
		if let observer = self.processApplicationObserver {
			NotificationCenter.default.removeObserver(observer)
		}
		xpcServiceConnection.invalidate()
	}
	 */

	var body: some View {
		TabView {
			VStack(alignment: .leading) {
				Text("Select the items you wish to remove:")
				Table(languages) {
					TableColumn("Remove language") { setting in
						if let index = languages.firstIndex(where: { $0.id == setting.id }) {
							Toggle(setting.displayName, isOn: $languages[index].enabled)
								.toggleStyle(.checkbox)
								.disabled(setting.folders.contains("en.lproj"))
						}
					}
				}
				HStack {
					Spacer()
					Button("Remove …") {
						// Display a warning first
						showingRemoveLanguagesAlert = true
					}
					.sheet(isPresented: $showingProgressView) {
						ProgressView(task: helperTask)
					}
					.alert("Are you sure you want to remove these languages?", isPresented: $showingRemoveLanguagesAlert) {
						//alertStyle = .warning
						Button("Cancel", role: .cancel) {}
						Button("Continue", role: .destructive) {
							checkAndRemove()
						}
					} message: {
						Text("You will not be able to restore them without reinstalling macOS.")
					}
					.alert("Monolingual is stopping without making any changes.", isPresented: $showingUnchangedAlert) {
						Button("OK", role: .cancel) {}
					} message: {
						Text("Your OS has not been modified.")
					}
					.alert("Removing all architectures will make macOS inoperable.", isPresented: $showingAllArchitecturesAlert) {
						Button("OK", role: .cancel) {}
					} message: {
						// alertStyle = .informational
						Text("Please keep at least one architecture and try again.")
					}
				}.padding()
			}
			.padding()
			.tabItem {
				Text("Languages")
			}
			VStack(alignment: .leading) {
				Text("Select the items you wish to remove:")
				Table(architectures) {
					TableColumn("Remove architecture") { setting in
						if let index = architectures.firstIndex(where: { $0.id == setting.id }) {
							Toggle(setting.displayName, isOn: $architectures[index].enabled)
								.toggleStyle(.checkbox)
						}
					}
				}
				HStack {
					Text("Current architecture: \(currentArchitecture)")
					Spacer()
					Button("Remove …") {
						removeArchitectures()
					}
				}.padding()
			}
			.padding()
			.tabItem {
				Text("Architectures")
			}
		}
		.padding()
		.task {
			loadData()
			// load remote blocklist asynchronously
			if let blocklistURL = URL(string: "https://ingmarstein.github.io/Monolingual/blocklist.plist"),
			   let (data, _) = try? await URLSession.shared.data(from: blocklistURL) {
				let decoder = PropertyListDecoder()
				self.blocklist = try? decoder.decode([BlocklistEntry].self, from: data)
			}
		}
	}
}

struct MainView_Previews: PreviewProvider {
	static var previews: some View {
		MainView()
	}
}
