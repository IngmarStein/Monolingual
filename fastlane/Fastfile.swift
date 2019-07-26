// This file contains the fastlane.tools configuration
// You can find the documentation at https://docs.fastlane.tools
//
// For a list of all available actions, check out
//
//     https://docs.fastlane.tools/actions
//

import Foundation

class Fastfile: LaneFile {
	var fastlaneVersion: String { return "2.69.3" }

	func beforeAll() {
		swiftlint(mode: "lint", configFile: ".swiftlint.yml", strict: false, ignoreExitStatus: false, quiet: false)
	}

	func testLane() {
		desc("Runs all the tests")
		scan(scheme: "Monolingual")
	}

	func betaLane() {
		desc("Build a new beta version with debug information")
		buildApp(project: "Monolingual.xcodeproj", scheme: "Monolingual", outputDirectory: "./build", configuration: "Debug")
	}

	func releaseLane() {
		desc("Build a new release version")
		buildApp(project: "Monolingual.xcodeproj", scheme: "Monolingual", clean: true, outputDirectory: "./build", configuration: "Release")
	}
}
