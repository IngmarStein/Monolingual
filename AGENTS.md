# Monolingual Project Context

## Project Overview
Monolingual is a macOS utility for removing unnecessary language localization files to reclaim disk space. It is written in Swift and utilizes a modular architecture involving a sandboxed main application and a privileged helper tool.

### Key Technologies
- **Language:** Swift 5.5
- **UI Framework:** SwiftUI & AppKit
- **Build System:** Xcode (`.xcodeproj`), Fastlane (Swift)
- **Dependency Management:** Swift Package Manager (SPM), Bundler (for Fastlane)

## Architecture
The application is composed of two main components:
1.  **Monolingual App (Sandboxed):** The user-facing application (Sources: `Sources/`). It registers the helper as a launch daemon with `SMAppService` and talks to it directly over XPC.
2.  **Privileged Helper:** Performs operations requiring elevated privileges, such as file deletion (Sources: `Helper/`). It is an executable inside the app bundle (`Contents/MacOS`), together with its launchd property list in `Contents/Library/LaunchDaemons`.

## Build & Development

### Prerequisites
- Xcode 13+ (implied by Swift 5.5)
- Ruby & Bundler
- Python 3 (for helper scripts)

### Commands
- **Install Dependencies:** `bundle install`
- **Build (Debug):** `make development` (executes `bundle exec fastlane debug`)
- **Build (Release):** `make deployment` (executes `bundle exec fastlane release`)
- **Release Packaging:** `make release` (Handles signing, notarization, and DMG creation)
- **Linting/Formatting:** The project includes `.swiftlint.yml` and `.swiftformat` configurations. Ensure these tools are run to maintain code style.

## Key Directories & Files
- `Sources/`: Main application source code.
- `Helper/`: Source code for the privileged helper tool.
- `lipo/`: Source code for the custom `lipo` tool used for architecture stripping.
- `fastlane/`: Build automation configuration (using Fastlane Swift).
- `Makefile`: Entry points for build and release automation.
- `Package.swift`: Swift Package Manager definition for dependencies.

## Notes
- The privileged helper is registered with `SMAppService` (macOS 13+). An administrator has to allow it in System Settings › General › Login Items & Extensions before it can run.
- Helpers installed by Monolingual 1.9.0 and earlier (SMJobBless based) are no longer removed automatically; `util/uninstall.sh` removes them. They serve a Mach service named after themselves, so they do not collide with the daemon registered with `SMAppService`.
- The helper validates its XPC peers itself, with a declarative `XPCPeerRequirement` that XPC enforces for every session, since launchd no longer restricts access to the daemon's Mach service.
- The app and the helper talk over the Swift XPC API (`XPCListener`/`XPCSession`), not `NSXPCConnection`: messages are `Codable` types carried as JSON in an `XPCDictionary`, and the app sends an endpoint of its own for the helper to report progress and the result on.
