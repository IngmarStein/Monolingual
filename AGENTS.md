# Monolingual Project Context

## Project Overview
Monolingual is a macOS utility for removing unnecessary language localization files to reclaim disk space. It is written in Swift and utilizes a modular architecture involving a sandboxed main application and a privileged helper tool.

### Key Technologies
- **Language:** Swift 6 (Swift 6 language mode), app deployment target macOS 27 (the helper and `lipo` target macOS 26)
- **UI Framework:** SwiftUI & AppKit
- **Build System:** Xcode (`.xcodeproj`), shell scripts (`scripts/`), GitHub Actions
- **Dependency Management:** Swift Package Manager (SPM)
- **Dependencies:** Sparkle (updates), swift-argument-parser (for the `lipo` tool)

## Architecture
The application is composed of two main components:
1.  **Monolingual App (Sandboxed):** The user-facing application (Sources: `Sources/`). It registers the helper as a launch daemon with `SMAppService` and talks to it directly over XPC.
2.  **Privileged Helper:** Performs operations requiring elevated privileges, such as file deletion (Sources: `Helper/`). It is an executable inside the app bundle (`Contents/MacOS`), together with its launchd property list in `Contents/Library/LaunchDaemons`.

## Build & Development

### Prerequisites
- Xcode 27+ (the app targets macOS 27, its helper macOS 26). `scripts/select-xcode.sh` picks a
  suitable Xcode from `/Applications` and is what the build uses.

### Commands
- **Build (Debug):** `make development` (executes `scripts/build.sh Debug`)
- **Build (Release):** `make deployment` (executes `scripts/build.sh Release`)
- **Release Packaging:** `make release` (executes `scripts/release.sh`: build, sign, notarize,
  staple, disk image, appcast; see *Releases* below)
- **Tests:** `swift test`, or `xcodebuild -scheme Helper -destination 'platform=macOS' test`
  (the `Helper` scheme's test action runs the `Helper Tests` target).
- **Linting/Formatting:** The project includes `.swiftlint.yml` and `.swiftformat` configurations. Ensure these tools are run to maintain code style. CI runs `shellcheck` over `make-diskimage.sh`, `scripts/` and `util/`, and SwiftLint (not `--strict`: `HelperContext.swift` carries a TODO that is a real caveat) over the Swift sources.
- Building the `Helper` target directly (`xcodebuild -target Helper`) fails dependency scanning
  for SPM's ArgumentParser; build the schemes instead (`-scheme Helper`, `-scheme Monolingual`).

### Releases
`Info.plist` is the single source of truth for the version; nothing rewrites it. To release, bump
`CFBundleShortVersionString`/`CFBundleVersion` there and in `Helper/Sources/MonolingualHelper-Info.plist`,
commit, then either tag the commit `v<version>` and let `.github/workflows/release.yml` build and
publish it, or run `make release` locally (same `scripts/release.sh`, writes `release-<version>/`).

The release workflow takes these secrets and variables:

| Name | Kind | Holds |
| --- | --- | --- |
| `DEVELOPER_ID_CERT` | secret | base64 of the Developer ID Application certificate and key (`.p12`) |
| `DEVELOPER_ID_PASSWORD` | secret | the password that `.p12` was exported with |
| `NOTARY_KEY` | secret | the App Store Connect API key (`.p8`), as text |
| `NOTARY_KEY_ID` | variable | that key's id |
| `NOTARY_ISSUER` | variable | the issuer id of the team the key belongs to |
| `SPARKLE_ED_KEY` | secret | the EdDSA private key that signs the update feed, base64 |
| `DEVELOPER_ID` | variable | optional; the codesigning identity, if not the project's default |

No provisioning profile is needed: the app and its helper carry no restricted entitlements.
Sparkle's EdDSA key is exported from the login keychain with the `generate_keys -x` that ships
next to it in the Sparkle package artifacts; the same directory's `sign_update` is what
`scripts/release.sh` signs the appcast with, so the tool and the framework cannot drift apart.
A `workflow_dispatch` run builds, signs, notarizes and packages without publishing, and uploads
the artifacts — use it to check a release before tagging.

## Key Directories & Files
- `Sources/`: Main application source code.
- `Helper/`: Source code for the privileged helper tool.
- `lipo/`: Source code for the custom `lipo` tool used for architecture stripping.
- `scripts/`: Build and release shell scripts — `select-xcode.sh`, `build.sh`, `notarize.sh`,
  `release.sh`. The workflows and `make release` run the same scripts.
- `.github/workflows/`: `ci.yml` (lint, build, test), `release.yml` (tagged releases and dry runs),
  `codeql.yml`.
- `make-diskimage.sh` and `dmg.js`: build the disk image and lay out its Finder window.
- `Makefile`: Entry points for build and release automation.
- `Package.swift`: Swift Package Manager definition for dependencies.

## Notes
- The privileged helper is registered with `SMAppService` (macOS 13+). An administrator has to allow it in System Settings › General › Login Items & Extensions before it can run.
- Helpers installed by Monolingual 1.9.0 and earlier (SMJobBless based) are no longer removed automatically; `util/uninstall.sh` removes them. They serve a Mach service named after themselves, so they do not collide with the daemon registered with `SMAppService`.
- The helper validates its XPC peers itself, with a declarative `XPCPeerRequirement` that XPC enforces for every session, since launchd no longer restricts access to the daemon's Mach service.
- The app and the helper talk over the Swift XPC API (`XPCListener`/`XPCSession`), not `NSXPCConnection`: messages are `Codable` types carried as JSON in an `XPCDictionary`, and the app sends an endpoint of its own for the helper to report progress and the result on.
- The helper handles messages on a serial queue but runs a removal on a separate `OperationQueue`, so an `exit` message is received while a removal is in progress; cancellation is the helper process exiting, which is also how the app ends the session.
