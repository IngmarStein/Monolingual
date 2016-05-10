import PackageDescription

let package = Package(
	name: "Helper",
	dependencies: [
		.Package(url: "https://github.com/IngmarStein/CommandLine.git", versions: Version(2, 2, 0, prereleaseIdentifiers: ["pre3"])..<Version(3, 0, 0)),
	]
)
