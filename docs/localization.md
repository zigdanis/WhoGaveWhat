# String Catalog synchronization

Use Xcode 27.1 for local builds, matching the native CI jobs. Xcode can rewrite
`WhoGaveWhat/Resources/Localizable.xcstrings` when synchronizing extracted strings,
including reordering entries and removing unused untranslated strings. A different
Xcode version can produce another rewrite even when translation values are unchanged.

After changing localizable text, build the app and synchronize the catalog with the
compiler-produced strings data:

```sh
xcodebuild build \
  -project WhoGaveWhat.xcodeproj \
  -scheme WhoGaveWhat \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/whogavewhat-localization \
  CODE_SIGNING_ALLOWED=NO
python3 scripts/sync-localizations.py --derived-data /tmp/whogavewhat-localization
```

Review and commit the catalog update together with the source changes. The `Tests`
workflow runs the same synchronization check after each unit test build. Its
`--check` option compares a synchronized temporary copy with the tracked catalog
and fails if they differ, leaving the checkout unchanged:

```sh
python3 scripts/sync-localizations.py --derived-data /tmp/whogavewhat-localization --check
```

Keep the selected local Xcode and all native workflow pins aligned when upgrading
the toolchain. The CI check catches catalog drift; matching the Xcode version alone
does not replace synchronizing and committing the catalog.
