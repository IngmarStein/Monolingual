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
	println("usage: lipo <executable> <architectures>")
	exit(EXIT_SUCCESS)
}

if arguments.count < 3 {
	usage()
}

private let inputFile = arguments[1]
private let architectures = Array(arguments[2..<arguments.count])

if let lipo = Lipo(archs: architectures) {
	var sizeDiff = 0
	if lipo.run(inputFile, sizeDiff: &sizeDiff) {
		println("saved \(sizeDiff) bytes")
	} else {
		println("lipo failed")
	}
} else {
	usage()
}
