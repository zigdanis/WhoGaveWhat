# Who Gave What

A warm little ledger for every gift your family gives and gets. Native **iOS** app
built with **Swift + SwiftUI**, backed by **Core Data**, implementing a design from
Claude Design.

## Run

```bash
open WhoGaveWhat.xcodeproj      # then ⌘R
# or build from the command line for a simulator:
xcodebuild -project WhoGaveWhat.xcodeproj -scheme WhoGaveWhat \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
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
  person + family-member pickers, "Paid by you" toggle, celebration, date. Saving writes
  to Core Data and updates the timeline.
- **People** — family + friends/relatives, each with running totals.
- **Person detail** — per-person stats, by-occasion chart, full history.
- **Insights** — received vs. given split, "Who's really paying" card, top people, by occasion.

## Persistence

Storage is currently **Core Data** (`Infrastructure/Persistence/WhoGaveWhat.xcdatamodeld`):

- `CDPerson` — family members (`isFamily == true`) and external people (`isFamily == false`).
- `CDGift` — a tracked gift, with `person` (external) and `member` (family) relationships.

`CoreDataStack` owns the stack and seeds sample data on first launch. Core Data is
contained behind `GiftGateway` and `PeopleGateway`; features and use cases work with
plain Swift models. This boundary is intended to make a later SwiftData migration a
separate persistence change rather than another UI rewrite.

## Structure

| Path | Role |
|------|------|
| `WhoGaveWhat/App/` | Composition root, app entry, shared data and navigation router |
| `WhoGaveWhat/Features/` | SwiftUI screens grouped by user-facing feature; local UI state stays here |
| `WhoGaveWhat/Models/` | Framework-independent app value types |
| `WhoGaveWhat/UseCases/` | Named gift, people, insights and onboarding scenarios |
| `WhoGaveWhat/Gateways/` | Persistence, intelligence and preferences contracts plus adapters |
| `WhoGaveWhat/Infrastructure/` | Core Data stack, managed-object subclasses and schema |
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
SIMCTL_CHILD_KS_START=app SIMCTL_CHILD_KS_TAB=insights xcrun simctl launch booted pro.ziganshin.WhoGaveWhat
```

## Tests & CI

Unit tests live in `WhoGaveWhatTests/` (Swift Testing) and cover formatting, gift
suggestions, save validation and direction, router behavior, insights, and persistence
write-through against isolated in-memory Core Data stacks.

```bash
xcodebuild test -project WhoGaveWhat.xcodeproj -scheme WhoGaveWhat \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
# or: bundle exec fastlane tests
```

GitHub Actions (`.github/workflows/tests.yml`) runs the suite on every push to
`master` and on pull requests.

## Shipping

`bundle exec fastlane beta` runs the tests first, then fetches signing via **match**,
bumps the build number above the latest TestFlight build, builds with **gym**, and
uploads to **TestFlight** with **pilot**. Requires the App Store Connect API key env
vars (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`).
