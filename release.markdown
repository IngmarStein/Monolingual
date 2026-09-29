# How to create a Monolingual release

1. Bump the version number in
    * `Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`)
    * `Helper/Sources/MonolingualHelper-Info.plist`
    * the screenshot in each `Resources/*.rtfd` help bundle: rename
      `Monolingual-<version>-<lang>.png` and update the `\NeXTGraphic` reference to it in that
      bundle's `TXT.rtf`
2. Add the changelog to the readmes.
3. Check the release on a dry run: Actions › Release › Run workflow. It builds, signs, notarizes
   and packages without publishing, and uploads the artifacts to the run. Download them and open
   the disk image.
4. Commit the version bump and push it to `main`.
5. Tag the release (`git tag -s vX.Y.Z -m 'X.Y.Z'`) and push the tag
   (`git push origin vX.Y.Z`). The tag has to match `Info.plist`; the workflow refuses it
   otherwise. It builds the release and attaches the disk image, the app zip, the debug symbols
   and `appcast.xml` to a new GitHub release. The release notes are generated from the commits;
   edit them afterwards if they need a human touch.
6. On the website, take `appcast.xml` from the release and add the version to `_data/versions.yml`.
7. Upload the website (`git push origin gh-pages`).
8. Announce the release on http://www.macupdate.com

Without the repository secrets (see AGENTS.md), or to build a release by hand, `make release`
does the same work locally and writes `release-<version>/`.
