# How to create a Monolingual release

1. Bump version number in
    * Info.plist
    * MonolingualHelper-Info.plist
    * InfoPlist.strings
    * Makefile
2. Add changelog to readmes
3. make release
4. Notarize app (`xcrun altool --notarize-app -f release-x.y.z/Monolingual-x.y.z.dmg -u <email> --primary-bundle-id com.github.IngmarStein.Monolingual`)
5. Update _data/versions.yml
6. Tag release (git tag -s vX.Y.Z -m 'X.Y.Z')
7. Push tags (git push --tags)
8. Create release on GitHub (https://github.com/IngmarStein/Monolingual/releases)
9. Upload website (git push origin gh-pages)
10. Announce release on http://www.macupdate.com
