# Who Gave What

A warm little ledger for every gift you give and get. Native **iOS** app
built with **Swift + SwiftUI**, backed by **SwiftData**, implementing a design from
Claude Design.

## Run

```bash
open WhoGaveWhat.xcodeproj      # then ⌘R
# or build for an installed Simulator:
xcodebuild -project WhoGaveWhat.xcodeproj -scheme WhoGaveWhat \
  -destination 'platform=iOS Simulator,name=iPhone Duo' build
```

Debug builds launched with `KS_SAMPLE_DATA=1` use the seeded in-memory sample store, for screenshots; Release builds ignore it.
Its amounts are in the currency the device resolves (dollars or rubles).
To show the save and delete error states, Debug builds launched with `KS_FAIL_SAVE=N` fail the next N gift saves and
`KS_FAIL_DELETE=N` the next N gift or person deletions; later attempts go through. Release builds, including the
`Simulator app` workflow's app, ignore both, so show these states from a local Debug build.
`KS_STORE_FAULT=open|load|people` (or the launch arguments `-KS_STORE_FAULT open|load|people`) makes a Debug
build fail the first attempt to open the store, to fetch the gifts or to fetch the people, so the recovery
screens can be checked without touching the data; Retry then succeeds. Release builds ignore it.

`WhoGaveWhatTests/Fixtures/StoreFixtures` holds a SwiftData store written by each shipped schema version;
`StoreFixtureMigrationTests` opens copies with the current models and expects every record. A schema change
adds a fixture written by `scripts/store-fixtures/generate.py` (macOS with Xcode), which compiles the
models of the given commit unchanged.

App Store screenshots are plain captures of that sample data, shot only on MacPro's pool Simulators (never in CI)
with `python3 scripts/store-screenshots.py OUT --display DISPLAY --simulator UDID`, which writes `screenshots/en-US`
and `screenshots/ru` for fastlane; the manual `App Store metadata` workflow uploads `fastlane/metadata` and, when
given the draft release that `scripts/publish-store-screenshots.sh` created, those images. See
[docs/app-store.md](docs/app-store.md).

- **Minimum iOS:** 18.4 — built with **Xcode 27.1** against the iOS 27.1 SDK; native **Liquid Glass** on iOS 26 and later, with system materials and bordered buttons on iOS 18. iOS 26-only APIs live behind `WhoGaveWhat/DesignSystem/PlatformCompatibility.swift`.
  The iOS 27.1 SDK lets the app fill both iPhone Duo displays. The iPhone Duo Simulator needs the iOS 27.1 runtime
  (`xcodebuild -downloadPlatform iOS`, or `scripts/install-simulator-runtime.sh 'iOS 27.1' 'iPhone Duo'`).
- **Dependencies:** [PostHog iOS](https://github.com/PostHog/posthog-ios) (product analytics) and
  [Sentry Cocoa](https://github.com/getsentry/sentry-cocoa) (crash reporting) via **Swift Package Manager**;
  both stay silent until their keys are set, see [docs/analytics.md](docs/analytics.md).
- **Bundle id:** `pro.ziganshin.WhoGaveWhat`

## License

Who Gave What is available under the [MIT License](LICENSE). Bundled third-party
icons remain subject to the licenses listed in
[`WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md`](WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md).