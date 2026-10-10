# Monolingual Project Context

## Project Overview
Monolingual is a macOS utility for removing unnecessary language localization files to reclaim disk space. It is written in Swift and utilizes a modular architecture involving a main application and a privileged helper tool.

### Key Technologies
- **Language:** Swift 6 (Swift 6 language mode), deployment target macOS 27 — every target names it
  (the app, the helper, `lipo` and the tests); the project-level default is still 26.0 and none of
  them inherits it
- **UI Framework:** SwiftUI & AppKit
- **Build System:** Xcode (`.xcodeproj`), shell scripts (`scripts/`), GitHub Actions
- **Dependency Management:** Swift Package Manager (SPM)
- **Dependencies:** Sparkle (updates), swift-argument-parser (for the `lipo` tool)

## Architecture
The application is composed of two main components:
1.  **Monolingual App:** The user-facing application (Sources: `Sources/`). It registers the helper as a launch daemon with `SMAppService` and talks to it directly over XPC. It is **not** sandboxed: macOS 27 refuses to register an unsandboxed launch daemon from a sandboxed app (`SMAppService target executable must be sandboxed because the app is sandboxed`), and sandboxing the helper is not an option for a tool that deletes files anywhere on disk. The app *was* sandboxed, from 2015 through 2.0.0, via `Monolingual.entitlements`; removing the sandbox is what makes 2.0.1 work. `SMJobBless`, which `SMAppService` replaced, had no such requirement — it trusted the client on code signature alone — so the entitlement and the helper install coexisted for a decade without anyone noticing the coupling.
2.  **Privileged Helper:** Performs operations requiring elevated privileges, such as file deletion (Sources: `Helper/`). It is an executable inside the app bundle (`Contents/MacOS`), together with its launchd property list in `Contents/Library/LaunchDaemons`.

## Build & Development

### Prerequisites
- Xcode 27+ (the app and the helper it carries both target macOS 27). `scripts/select-xcode.sh` picks a
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
`DEVELOPER_ID_CERT` has to hold that one identity and its chain, nothing else:
`security export -t identities` exports every identity and certificate in the keychain, which is
both past GitHub's 48 KB secret limit and a pile of private keys CI has no use for. Import the
export into a scratch keychain, delete the other identities and certificates, keep `Developer ID
Certification Authority` and `Apple Root CA`, and export that — about 3 KB, 4.3 KB in base64.
Sparkle's EdDSA key is exported from the login keychain with the `generate_keys -x` that ships
next to it in the Sparkle package artifacts; the same directory's `sign_update` is what
`scripts/release.sh` signs the appcast with, so the tool and the framework cannot drift apart.
A `workflow_dispatch` run builds, signs, notarizes and packages without publishing, and uploads
the artifacts — use it to check a release before tagging.

Three things a release has to be written into by hand, beyond the version numbers themselves.

**The changelog.** `README.markdown` carries a "What's new in `<version>`" section, and so do the
five help files in `Resources/*.rtfd/TXT.rtf` — `README` (English), `LEESMIJ` (Dutch), `Leggimi`
(Italian), `Lies-mich` (German) and `LisezMoi` (French). Those are what the Help menu shows and
what `release.sh` copies into the disk image. They are RTF, not text: the document is
`ansicpg1252`, a paragraph break is a lone backslash followed by a newline, and anything outside
ASCII is written as a `\'xx` escape (the German file spells "Oberfläche" as `Oberfl\'e4che`).
Check a change with `textutil -convert txt -stdout` rather than by reading the markup. Only the
German changelog is actually translated; the Dutch, Italian and French files keep their bullets in
English, and the screenshot each one embeds is named after the version whose window it shows.

**The screenshots.** Each help file embeds one and `README.markdown` points at the English one, so
a release renames all five and deletes the old ones — the name is in the `\NeXTGraphic` line of
`TXT.rtf` and in the README's `<img src=…>`. Take them a language at a time, with the window in
that language: `open -a Monolingual.app --args -AppleLanguages "(de)"`.

The help draws an image at half its pixel size — `\width` and `\height` are twips and equal the
pixel size times ten, and the README's `width` attribute is half the pixel width — so both have to
be recomputed from whatever the new captures measure, the window size deciding the pixels. It
cannot go below 640 points wide without the search field dropping out of the toolbar, which is
what fixes the smallest window worth photographing. `screencapture -l<window number>` takes the
picture, with `-o` left off because the shadow is part of it; the number comes from
`CGWindowListCopyWindowInfo`, or `screencapture -w` picks a window by clicking on it.

Two things go wrong. The window only draws its shadow, and its coloured traffic lights, while it
is the key window, and anything can take the focus back between activating the app and taking the
picture — including the person using the Mac. So measure what came out instead of trusting the
activation: the opaque part of the capture begins 112 pixels in from the left edge when the window
is active and 46 when it is not. `open -a <app>` and `System Events`' `set frontmost` are equally
reliable; the retry, not the incantation, is what makes this work. And these images are light
while the Mac is not necessarily: neither the `-AppleInterfaceStyle Light` launch argument nor an
`AppleInterfaceStyle` default in the app's own domain does anything, so it takes a temporary
`NSApp.appearance = NSAppearance(named: .aqua)` in `applicationDidFinishLaunching`, which has to
come back out again.

**The Sparkle feed.** `scripts/release.sh` writes an `appcast.xml` for the zip, but that only ever
becomes a release asset; nothing publishes it. The feed the app actually polls is
`SUFeedURL=https://ingmarstein.github.io/Monolingual/appcast.xml`, served from the `gh-pages`
branch, and it has no workflow behind it. That branch is a Jekyll site: the `appcast.xml` there is
a template that renders one `<item>` per `minimum` group from `_data/versions.yml`, taking
`limit:1` — so a release is a YAML entry added **at the top** of that file, because an entry
placed lower loses its group to the one above it and is never offered. The entry needs the
`edSignature` and `filesize` that `release.sh` computed, both readable from
`release-<version>/appcast.xml`; the download URL is built from `github_download_url` in
`_config.yml`, so it follows the version rather than being written out.

This feed is the only channel that reaches an existing installation, which matters more than it
looks: Sparkle compares `sparkle:version` against the running `CFBundleVersion`, so re-releasing a
version that is already out reaches nobody who already has it.

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
