# How to create a Monolingual release

1. Bump version number in
    * Info.plist
    * MonolingualHelper-Info.plist
    * InfoPlist.strings
    * Makefile
2. Add changelog to readmes
3. make release
4. Update index.html
5. Update changelog.html
6. Update _data/versions.yml
7. Tag release (git tag -s vX.Y.Z -m 'X.Y.Z')
8. Push tags (git push --tags)
9. Create release on GitHub (https://github.com/IngmarStein/Monolingual/releases)
10. Upload website (git push origin gh-pages)
11. Announce release on http://www.macupdate.com
