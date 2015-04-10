Monolingual
===========

#### A tool for removing unneeded language localization files for OS X

## Screenshot

<img src="http://ingmarstein.github.io/Monolingual/images/Monolingual-1.5.3-en.png">

## Architecture

Monolingual consists of three parts: the sandboxed Monolingual app, a non-sandboxed XPC service and a privileged helper program.
The user-visible app and the XPC service are written in Swift and communicate with the Objective-C-based helper using XPC.

## Dependencies

Monolingual uses CocoaPods to manage its dependencies. Currently, the following pods are used:

- [SMJobKit](https://github.com/IngmarStein/SMJobKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)

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
