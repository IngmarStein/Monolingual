//
//  main.swift
//  lipo
//
//  Created by Ingmar Stein on 22.04.15.
//
//

import Foundation

private let arguments = CommandLine.arguments

private func usage() {
	print("usage: lipo <executables> --arch <architecture>")
	exit(EXIT_SUCCESS)
}

if arguments.count < 4 {
	usage()
}

private var inputFiles = [String]()
private var architectures = [String]()

private var args = arguments.makeIterator()
while let arg = args.next() {
	if arg == "--arch" {
		if let arch = args.next() {
			architectures.append(arch)
		}
	} else {
		inputFiles.append(arg)
	}
}

if let lipo = Lipo(archs: architectures), !inputFiles.isEmpty && !architectures.isEmpty {
	var sizeDiff = 0
	for file in inputFiles {
		if lipo.run(path: file, sizeDiff: &sizeDiff) {
			print("\(file): saved \(sizeDiff) bytes")
		} else {
			print("\(file): lipo failed")
		}
	}
} else {
	usage()
}
