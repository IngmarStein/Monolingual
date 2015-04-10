//
//  main.swift
//  Monolingual
//
//  Created by Ingmar Stein on 10.04.15.
//
//

import Foundation

let helper = Helper()

let arguments = Process.arguments

if arguments.count == 2 && arguments[1] == "--uninstall" {
	helper.uninstall()
	exit(EXIT_SUCCESS)
}

if arguments.count == 2 && arguments[1] == "--version" {
	println("MonolingualHelper version \(helper.version)")
	exit(EXIT_SUCCESS)
}

helper.run()
