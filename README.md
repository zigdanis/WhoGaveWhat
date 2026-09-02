# Who Gave What

A warm little ledger for every gift your family gives and gets. Native **iOS** app
built with **Swift + SwiftUI**, backed by **SwiftData**, implementing a design from
Claude Design.

## Run

```bash
open WhoGaveWhat.xcodeproj      # then ⌘R
# or use the repository-configured CLI:
xcodebuildmcp simulator build-and-run
```

- **Minimum iOS:** 26.0 — built against the iOS 26 SDK, native **Liquid Glass** throughout (no back-deployment).
- **Dependencies:** none yet (added via **Swift Package Manager** if/when needed)
- **Bundle id:** `pro.ziganshin.WhoGaveWhat`

## What's implemented

- **Onboarding** — three floating intro cards.
- **Sign in** — *placeholder only* (Apple / email / "keep it on this phone" all just
  enter the app). Real auth + remote sync is intentionally deferred.
- **Home** — year summary (↙ Received / ↗ Given), filter chips, gifts grouped by month.
- **Add a gift** — type a name → live emoji + value guess; Received/Given segment,
  unified person picker, "Paid by you" toggle, occasion, date. Saving writes
  to SwiftData and updates the timeline.
- **People** — family + friends/relatives, each with running totals.
- **Person detail** — per-person stats, by-occasion chart, full history.
- **Insights** — received vs. given split, "Who's really paying" card, top people, by occasion.

## Persistence

Storage is **SwiftData**, isolated behind `GiftGateway` and `PeopleGateway`:

- `StoredPerson` persists one unified person model with a household or contact role.
- `StoredGift` persists required giver and recipient relationships, occasion, gift
  date, and explicit creation time. Direction is derived from the endpoint roles.

`SwiftDataStore` owns a distinctly named `WhoGaveWhatSwiftData` store. The app has not
shipped, so this schema intentionally starts fresh: there is no legacy import,
migration, or cleanup path. Features and use cases continue to work with plain Swift
value models rather than SwiftData records.

## Structure

| Path | Role |
|------|------|
| `WhoGaveWhat/App/` | Composition root, app entry, shared data and navigation router |
| `WhoGaveWhat/Features/` | SwiftUI screens grouped by user-facing feature; local UI state stays here |
| `WhoGaveWhat/Models/` | Framework-independent app value types |
| `WhoGaveWhat/UseCases/` | Named gift, people, insights and onboarding scenarios |
| `WhoGaveWhat/Gateways/` | Persistence, intelligence and preferences contracts plus adapters |
| `WhoGaveWhat/Infrastructure/` | SwiftData container and private persistence records |
| `WhoGaveWhat/DesignSystem/` | Colors, theme tokens, reusable components and layouts |
| `WhoGaveWhat/Helpers/` | Small cross-feature formatting extensions |
| `WhoGaveWhat/Resources/` | Assets, fonts and localization catalogs |
| `WhoGaveWhatTests/` | Swift Testing coverage for use cases, router and gateway-backed integration |
| `fastlane/` | `tests`, `beta` (TestFlight), and diagnostic lanes |
| `.github/workflows/tests.yml` | CI — runs the test suite on push to `master` + PRs |

### Testing entry points
Launch env vars jump straight to a state (used for verification / previews):
`KS_START=app|signin`, `KS_TAB=home|people|insights`, `KS_SHEET=1`.

```bash
xcodebuildmcp simulator launch-app --bundle-id pro.ziganshin.WhoGaveWhat --json '{"env":{"KS_START":"app","KS_TAB":"insights"}}'
```

## Tests & CI

Unit tests live in `WhoGaveWhatTests/` (Swift Testing) and cover formatting, gift
suggestions, save validation and direction, router behavior, insights, and persistence
write-through against isolated in-memory SwiftData stores.

```bash
xcodebuildmcp simulator test
# or: bundle exec fastlane tests
```

GitHub Actions (`.github/workflows/tests.yml`) runs the suite on every push to
`master` and on pull requests.

## Shipping

`bundle exec fastlane beta` runs the tests first, then fetches signing via **match**,
bumps the build number above the latest TestFlight build, builds with **gym**, and
uploads to **TestFlight** with **pilot**. Requires the App Store Connect API key env
vars (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).

## License

Who Gave What is available under the [MIT License](LICENSE). Bundled third-party
fonts and icons remain subject to the licenses listed in
[`WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md`](WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md).
