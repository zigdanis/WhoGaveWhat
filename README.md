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

- **Minimum iOS:** 26.0 — built with **Xcode 27.1** against the iOS 27.1 SDK, native **Liquid Glass** throughout.
  The iOS 27.1 SDK lets the app fill both iPhone Duo displays. The iPhone Duo Simulator needs the iOS 27.1 runtime
  (`xcodebuild -downloadPlatform iOS`, or `scripts/install-simulator-runtime.sh 'iOS 27.1' 'iPhone Duo'`).
- **Dependencies:** none yet (added via **Swift Package Manager** if/when needed)
- **Bundle id:** `pro.ziganshin.WhoGaveWhat`

## License

Who Gave What is available under the [MIT License](LICENSE). Bundled third-party
icons remain subject to the licenses listed in
[`WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md`](WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md).