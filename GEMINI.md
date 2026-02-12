# Monolingual Project Context

## Project Overview
Monolingual is a macOS utility for removing unnecessary language localization files to reclaim disk space. It is written in Swift and utilizes a modular architecture involving a sandboxed main application, an XPC service, and a privileged helper tool.

### Key Technologies
- **Language:** Swift 5.5
- **UI Framework:** SwiftUI & AppKit
- **Build System:** Xcode (`.xcodeproj`), Fastlane (Swift)
- **Dependency Management:** Swift Package Manager (SPM), Bundler (for Fastlane)

## Architecture
The application is composed of three main components:
1.  **Monolingual App (Sandboxed):** The user-facing application (Sources: `Sources/`, `Monolingual/`).
2.  **XPC Service:** Handles communication between the app and the helper (Sources: `XPCService/`).
3.  **Privileged Helper:** Performs operations requiring elevated privileges, such as file deletion (Sources: `Helper/`).

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
- `XPCService/`: Source code for the XPC service.
- `lipo/`: Source code for the custom `lipo` tool used for architecture stripping.
- `fastlane/`: Build automation configuration (using Fastlane Swift).
- `Makefile`: Entry points for build and release automation.
- `Package.swift`: Swift Package Manager definition for dependencies.

## Notes
- The project uses `SMJobBless` for installing the privileged helper.
- `SMJobBlessUtil.py` is used to verify the code signing requirements for the helper tool.
