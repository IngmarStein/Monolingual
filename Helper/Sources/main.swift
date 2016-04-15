//
//  main.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation
import CommandLine

private let cli = CommandLine()
private let uninstall = BoolOption(shortFlag: "u", longFlag: "uninstall", helpMessage: "Uninstall helper.")
private let version = BoolOption(shortFlag: "v", longFlag: "version", helpMessage: "Print version and exit.")
private let dryRun = BoolOption(shortFlag: "n", longFlag: "dry", helpMessage: "Dry run: don't make any changes to the filesystem.")
private let strip = BoolOption(shortFlag: "s", longFlag: "strip", helpMessage: "Strip debug info from executables.")
private let trash = BoolOption(shortFlag: "t", longFlag: "trash", helpMessage: "Don't delete files but move them to the trash.")
private let includes = MultiStringOption(shortFlag: "i", longFlag: "include", required: false, helpMessage: "Include directory.")
private let excludes = MultiStringOption(shortFlag: "x", longFlag: "exclude", required: false, helpMessage: "Exclude directory.")
private let bundles = MultiStringOption(shortFlag: "b", longFlag: "bundle", required: false, helpMessage: "Exclude a bundle from processing (e.g. \"com.apple.iPhoto\").")
private let delete = MultiStringOption(shortFlag: "d", longFlag: "delete", required: false, helpMessage: "Name of a file or directory to delete (e.g. \"fr.lproj\").")
private let thin = MultiStringOption(shortFlag: "a", longFlag: "thin", required: false, helpMessage: "Remove architecture from universal binary (e.g. \"ppc\").")

cli.addOptions(uninstall, version, dryRun, strip, trash, includes, excludes, bundles, delete, thin)

do {
	try cli.parse(strict: true)

	let helper = Helper()

	if uninstall.value {
		helper.uninstall()
		exit(EXIT_SUCCESS)
	}

	if version.value {
		print("MonolingualHelper version \(helper.version)")
		exit(EXIT_SUCCESS)
	}

	if includes.wasSet {
		let request = HelperRequest()
		request.dryRun = dryRun.value
		request.doStrip = strip.value
		request.trash = trash.value
		request.includes = includes.value
		request.excludes = excludes.value
		request.bundleBlacklist = bundles.value.flatMap { Set<String>($0) }
		request.directories = delete.value.flatMap { Set<String>($0) }
		request.thin = thin.value
		helper.processRequest(request, progress: nil) { (result) -> Void in
			exit(Int32(result))
		}
		NSRunLoop.current().run()
	} else {
		helper.run()
	}
} catch {
	print(error)
	cli.printUsage()
	exit(EX_USAGE)
}
