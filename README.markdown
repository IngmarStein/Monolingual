Monolingual
===========

#### A tool for removing unneeded language localization files for macOS

## Screenshot

<img src="http://ingmarstein.github.io/Monolingual/images/Monolingual-1.6.7-en.png">

## Architecture

Monolingual consists of three parts: the sandboxed Monolingual app, a non-sandboxed XPC service and a privileged helper program.
All components are written in Swift and communicate with each other using XPC.

## Dependencies

Monolingual uses CocoaPods to manage its dependencies. Currently, the following pods are used:

- [SMJobKit](https://github.com/IngmarStein/SMJobKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Fabric](https://cocoapods.org/pods/Fabric)
- [Crashlytics](https://cocoapods.org/pods/Crashlytics)

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

### Artwork
Icon by Matt Davey

## License

GNU GENERAL PUBLIC LICENSE, Version 3, 29 June 2007

## Developers

Monolingual is written in Swift 3.1 and requires Xcode 8.3 or above.

## Status

[![Build Status](https://img.shields.io/travis/IngmarStein/Monolingual.svg)](https://travis-ci.org/IngmarStein/Monolingual)
[![Dependencies](https://img.shields.io/gemnasium/IngmarStein/Monolingual.svg)](https://gemnasium.com/IngmarStein/Monolingual)
[![Code Climate](https://img.shields.io/codeclimate/github/IngmarStein/Monolingual.svg)](https://codeclimate.com/github/IngmarStein/Monolingual)
