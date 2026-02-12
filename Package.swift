// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Monolingual",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Helper", targets: ["Helper"]),
        .executable(name: "lipo", targets: ["lipo"]),
        .executable(name: "XPCService", targets: ["XPCService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/IngmarStein/SMJobKit", from: "0.0.21"),
    ],
    targets: [
        .target(
            name: "LipoCore",
            path: "lipo",
            exclude: ["main.swift"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "HelperShared",
            dependencies: ["LipoCore"],
            path: "Helper/Sources",
            exclude: ["main.swift", "MonolingualHelper-Info.plist", "MonolingualHelper-launchd.plist"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Helper",
            dependencies: [
                "LipoCore",
                "HelperShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Helper/Sources",
            exclude: ["Helper.swift", "HelperContext.swift", "HelperProtocol.swift", "HelperRequest.swift", "MonolingualHelper-Info.plist", "MonolingualHelper-launchd.plist"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lipo",
            dependencies: ["LipoCore"],
            path: "lipo",
            exclude: ["lipo.swift"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "XPCService",
            dependencies: [
                "HelperShared",
                .product(name: "SMJobKit", package: "SMJobKit")
            ],
            path: "XPCService",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HelperTests",
            dependencies: ["HelperShared"],
            path: "Helper/Tests",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/hello1"),
                .copy("Resources/hello2"),
                .copy("Resources/hello3")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
