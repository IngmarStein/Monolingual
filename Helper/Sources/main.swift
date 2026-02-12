//
//  main.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import ArgumentParser
import Foundation
#if canImport(HelperShared)
import HelperShared
#endif

struct Options: ParsableArguments {
	@Flag(name: .shortAndLong, help: "Uninstall helper.")
	var uninstall: Bool = false

	@Flag(name: .shortAndLong, help: "Print version and exit.")
	var version: Bool = false

	@Flag(name: [.customShort("n"), .long], help: "Dry run: don't make any changes to the filesystem.")
	var dryRun: Bool = false

	@Flag(name: .shortAndLong, help: "Strip debug info from executables.")
	var strip: Bool = false

	@Flag(name: .shortAndLong, help: "Don't delete files but move them to the trash.")
	var trash: Bool = false

	@Option(name: .shortAndLong, help: "Include directory.")
	var include: [String]

	@Option(name: [.customShort("x"), .long], help: "Exclude directory.")
	var exclude: [String]

	@Option(name: .shortAndLong, help: "Exclude a bundle from processing (e.g. \"com.apple.iPhoto\").")
	var bundle: [String]

	@Option(name: .shortAndLong, help: "Name of a file or directory to delete (e.g. \"fr.lproj\").")
	var delete: [String]

	@Option(name: [.customShort("a"), .long], help: "Remove architecture from universal binary (e.g. \"ppc\").")
	var thin: [String]
}

let options = Options.parseOrExit()

let helper = Helper()

if options.uninstall {
	helper.uninstall()
	exit(EXIT_SUCCESS)
}

if options.version {
	print("MonolingualHelper version \(helper.version)")
	exit(EXIT_SUCCESS)
}

if options.include.isEmpty {
	helper.run()
} else {
	let request = HelperRequest()
	request.dryRun = options.dryRun
	request.doStrip = options.strip
	request.trash = options.trash
	request.includes = options.include
	request.excludes = options.exclude
	request.bundleBlocklist = Set<String>(options.bundle)
	request.directories = Set<String>(options.delete)
	request.thin = options.thin
	helper.process(request: request, progress: nil) { result -> Void in
		exit(Int32(result))
	}
	RunLoop.current.run()
}
