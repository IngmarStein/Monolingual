# How to create a Monolingual release

1. Bump version number in
    * Info.plist
    * MonolingualHelper-Info.plist
    * InfoPlist.strings
    * Makefile
2. Add changelog to readmes
3. make release
4. Update _data/versions.yml
5. Tag release (git tag -s vX.Y.Z -m 'X.Y.Z')
6. Push tags (git push --tags)
7. Create release on GitHub (https://github.com/IngmarStein/Monolingual/releases)
8. Upload website (git push origin gh-pages)
9. Announce release on http://www.macupdate.com
