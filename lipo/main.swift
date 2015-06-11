//
//  main.swift
//  lipo
//
//  Created by Ingmar Stein on 22.04.15.
//
//

import Foundation

private let arguments = Process.arguments

private func usage() {
	print("usage: lipo <executables> --arch <architecture>")
	exit(EXIT_SUCCESS)
}

if arguments.count < 4 {
	usage()
}

private var inputFiles = [String]()
private var architectures = [String]()

for var i=1; i<arguments.count; ++i {
	let arg = arguments[i]
	if arg == "--arch" && i+1<arguments.count {
		architectures.append(arguments[++i])
	} else {
		inputFiles.append(arg)
	}
}

if let lipo = Lipo(archs: architectures) where !inputFiles.isEmpty && !architectures.isEmpty {
	var sizeDiff = 0
	for file in inputFiles {
		if lipo.run(file, sizeDiff: &sizeDiff) {
			print("\(file): saved \(sizeDiff) bytes")
		} else {
			print("\(file): lipo failed")
		}
	}
} else {
	usage()
}
