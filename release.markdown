# How to create a Monolingual release

1. Bump version number in
    * Info.plist
    * MonolingualHelper-Info.plist
    * InfoPlist.strings
    * Makefile
2. Add changelog to readmes
3. make release
4. Check code signature (spctl --verbose=4 --assess --type execute ./build/Monolingual.app)
4. Check SMJobBless code signing setup (SMJobBlessUtil.py check ./build/Monolingual.app)
5. Update index.html
6. Update changelog.html
7. Update appcast.xml
8. Tag release (git tag -s vX.Y.Z -m 'X.Y.Z')
9. Push tags (git push --tags)
10. Create release on GitHub (https://github.com/IngmarStein/Monolingual/releases)
11. Upload website (git push origin gh-pages)
12. Announce release on http://www.macupdate.com
