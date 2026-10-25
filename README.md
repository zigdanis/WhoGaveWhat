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

App Store screenshots are plain captures of that sample data. The `Store screenshots` workflow (or
`python3 scripts/store-screenshots.py OUT`) writes `screenshots/en-US` and `screenshots/ru` for fastlane;
the manual `App Store metadata` workflow uploads `fastlane/metadata` and, when given a screenshots run ID, those images.

- **Minimum iOS:** 26.0 — built with **Xcode 27.1** against the iOS 27.1 SDK, native **Liquid Glass** throughout.
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