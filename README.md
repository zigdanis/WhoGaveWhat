# Gifts

A warm little ledger for every gift your family gives and gets. Native **iOS** app
built with **Swift + SwiftUI**, backed by **Core Data**, implementing a design from
Claude Design.

## Run

```bash
open Gifts.xcodeproj      # then ⌘R
# or build from the command line for a simulator:
xcodebuild -project Gifts.xcodeproj -scheme Gifts \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

- **Minimum iOS:** 18.0
- **Dependencies:** none yet (added via **Swift Package Manager** if/when needed)
- **Bundle id:** `pro.ziganshin.Gifts`

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

Storage is **Core Data** (`Gifts.xcdatamodeld`):

- `CDPerson` — family members (`isFamily == true`) and external people (`isFamily == false`).
- `CDGift` — a tracked gift, with `person` (external) and `member` (family) relationships.

`PersistenceController` owns the stack and seeds sample data on first launch.
`AppStore` reads via fetch requests and writes new gifts through the view context; the
SwiftUI layer consumes lightweight value types (`Gift`, `Member`, `Person`).

## Structure

| Path | Role |
|------|------|
| `Gifts/GiftsApp.swift` | App entry — builds the Core Data stack and `AppStore` |
| `Gifts/Support/Theme.swift` | Color tokens, rounded font, ruble formatting |
| `Gifts/Model/Models.swift` | `Gift`, `Member`, `Person`, `Flow`, `Suggestion` value types |
| `Gifts/Model/AppStore.swift` | Observable store over Core Data — derived stats, actions |
| `Gifts/Persistence/` | Core Data stack, managed-object subclasses, seeding |
| `Gifts/Gifts.xcdatamodeld` | Core Data model |
| `Gifts/Views/` | One file per screen + shared `Components` / `FlowLayout` |

### Testing entry points
Launch env vars jump straight to a state (used for verification / previews):
`KS_START=app|signin`, `KS_TAB=home|people|insights`, `KS_SHEET=1`, `KS_DETAIL=<id>`.

```bash
SIMCTL_CHILD_KS_START=app SIMCTL_CHILD_KS_TAB=insights xcrun simctl launch booted pro.ziganshin.Gifts
```
