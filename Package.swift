import PackageDescription

let package = Package(
	name: "Monolingual",
	exclude: ["build", "Monolingual", "XPCService"],
	targets: [
//		Target(name: "Monolingual", dependencies: [.Target(name: "XPCService")]),
		Target(name: "XPCService", dependencies: [.Target(name: "Helper")]),
		Target(name: "Helper"),
		Target(name: "lipo")
	],
	dependencies: [
		// .Package(url: "https://github.com/jatoben/CommandLine.git", versions: Version(2, 2, 0, prereleaseIdentifiers: ["pre1"])..<Version(3, 0, 0)),
		.Package(url: "https://github.com/IngmarStein/CommandLine.git", versions: Version(2, 2, 0, prereleaseIdentifiers: ["pre3"])..<Version(3, 0, 0)),
		.Package(url: "https://github.com/IngmarStein/SMJobKit.git", versions: Version(0, 0, 8)..<Version(1, 0, 0))
	]
)
