Monolingual
===========

#### A tool for removing unneeded language localization files for macOS

## Screenshot

<img src="http://ingmarstein.github.io/Monolingual/images/Monolingual-1.6.7-en.png">

## Architecture

Monolingual consists of two parts: the sandboxed Monolingual app and a privileged helper program that
is registered as a launch daemon with Service Management (`SMAppService`). Both are written in Swift and
communicate with each other using XPC.

An administrator has to allow the helper in System Settings › General › Login Items & Extensions
before it can run.

## Dependencies

Monolingual uses Swift Package Manager to manage its dependencies. Currently, the following packages
are used:

- [Sparkle](https://github.com/sparkle-project/Sparkle) — app updates
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — argument parsing for the
  bundled `lipo` tool

## Building

- Install dependencies: `bundle install`
- Build (Debug): `make development`
- Build (Release): `make deployment`
- Release packaging (signing, notarization, disk image): `make release`
- Run the tests: `xcodebuild -scheme "Helper Tests" -destination 'platform=macOS' test`

The project uses [SwiftLint](https://github.com/realm/SwiftLint) and
[SwiftFormat](https://github.com/nicklockwood/SwiftFormat); their configurations are checked in as
`.swiftlint.yml` and `.swiftformat`.

## Contributors

### Main developer
Ingmar J. Stein

### Original idea
J. Schrier

### Localization

- Dutch localization by Tobias T.
- French localization by François Besoli
- German localization by Alex Thurley
- Greek localization by Ευριπίδης Αργυρόπουλος
- Hungarian localization by Alen Bajo
- Italian localization by Claudio Procida
- Japanese localization by Takehiko Hatatani
- Korean localization by Woosuk Park
- Polish localization by Mariusz Ostrowski
- Spanish localization by Fran Ramírez
- Swedish localization by Joel Arvidsson
- Turkish localization by Hasan Beder

### Artwork
Icon by Matt Davey

## License

GNU GENERAL PUBLIC LICENSE, Version 3, 29 June 2007

## Developers

Monolingual is written in Swift 6 and requires Xcode 27.0 or above.

## Status

![GitHub Build Status](https://github.com/IngmarStein/Monolingual/workflows/fastlane/badge.svg)
