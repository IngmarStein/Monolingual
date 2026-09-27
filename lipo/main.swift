//
//  main.swift
//  lipo
//
//  Created by Ingmar Stein on 22.04.15.
//
//

import Foundation
#if canImport(LipoCore)
import LipoCore
#endif

private let arguments = CommandLine.arguments

// Both callers reach this because the invocation was wrong, so it is not a success.
private func usage() {
	print("usage: lipo <executables> --arch <architecture>")
	exit(EXIT_FAILURE)
}

// The path of this executable plus at least one file and one architecture.
if arguments.count < 4 {
	usage()
}

private var inputFiles = [String]()
private var architectures = [String]()

// The first argument is the path of this executable, which is not one of the files to thin.
private var args = arguments.dropFirst().makeIterator()
while let arg = args.next() {
	if arg == "--arch" {
		if let arch = args.next() {
			architectures.append(arch)
		}
	} else {
		inputFiles.append(arg)
	}
}

if let lipo = Lipo(archs: architectures), !inputFiles.isEmpty, !architectures.isEmpty {
	var sizeDiff = 0
	var didFail = false
	for file in inputFiles {
		if lipo.run(path: file, sizeDiff: &sizeDiff) {
			print("\(file): saved \(sizeDiff) bytes")
		} else {
			print("\(file): lipo failed")
			didFail = true
		}
	}
	// A file that could not be thinned is a failure of the run, and the exit status is what a
	// caller sees: reporting it only on stdout would leave the failure to be read by a human.
	if didFail {
		exit(EXIT_FAILURE)
	}
} else {
	usage()
}
