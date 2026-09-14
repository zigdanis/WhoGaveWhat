---
include:
  - "**/*.swift"
  - "**/*.xcstrings"
  - "**/*.strings"
  - "**/*.entitlements"
  - "**/*.plist"
  - "**/*.xcassets/**"
  - "**/*.xcscheme"
  - "**/Package.resolved"
  - "WhoGaveWhat.xcodeproj/project.pbxproj"
  - ".github/workflows/**"
  - "scripts/**"
  - "fastlane/**"
  - "Gemfile"
  - "Gemfile.lock"
exclude:
  - "WhoGaveWhat.xcodeproj/xcuserdata/**"
---

# Shared WhoGaveWhat review policy

This file is the authoritative repository-specific review policy shared by Macroscope, CodeRabbit, Greptile, and Codex.

Review for concrete correctness, persistence, concurrency, localization, target-configuration, and user-visible regressions. Do not report formatting or style preferences. Do not request compatibility layers, migrations, or speculative abstractions: the app has not shipped and deliberately starts with a fresh schema. If a rule is unrelated to the changed code, ignore it. If there is no concrete issue, report no findings.

## Architecture and state

- This is an iOS 26 SwiftUI app. Keep feature UI and local presentation state in `WhoGaveWhat/Features`, framework-independent values in `Models`, scenarios in `UseCases`, persistence and service contracts in `Gateways`, SwiftData records and container setup in `Infrastructure`, and reusable visual primitives in `DesignSystem`.
- Feature views must use the existing use cases and gateway protocols for business and persistence operations. Flag direct SwiftData access from feature views or persistence records leaking into value models and use-case interfaces.
- App navigation and shared dependencies are owned by the composition root and router. Flag duplicated stores, routers, or feature-local dependency construction that can split application state.
- UI-bound models, gateways, and mutations run on the main actor. Flag work that can update observable UI state or a `ModelContext` from the wrong actor.

## Gift and persistence invariants

- A saved gift has nonempty trimmed text, distinct existing giver and recipient IDs, a stable ID, and a stable `createdAt` when edited. Its direction is derived from endpoint roles rather than trusted as independent persisted state.
- SwiftData writes must either save the full intended mutation or roll the context back and surface the error. Flag swallowed persistence failures, partial relationship updates, or deletes that leave related gifts invalid.
- People are represented by one unified value model with household/contact roles. Creating, renaming, and deleting people must preserve gift endpoint validity and the product's explicit delete behavior.
- The deliberately named `WhoGaveWhatSwiftData` store and the plain-value-model boundary are intentional. Do not introduce legacy imports, migration scaffolding, or alternate containers without a current product requirement.
- Home timelines, person totals, and insights must agree on direction, dates, values, and filtering. Flag changes that make the same gift count differently across those views.

## Product behavior and localization

- Sign-in options are placeholders that enter the local app. Do not treat them as real authentication or remote synchronization, and flag changes that imply protected or synchronized data without implementing that boundary.
- Preserve the add/edit validation rules and every success, failure, cancellation, and dismissal path. User-visible failures must not be silently discarded.
- User-visible copy belongs in the String Catalog or localized InfoPlist resources. English and Russian entries, format arguments, pluralization, and the correct bundle/target must remain consistent.
- Reuse established design-system tokens and components when they carry product behavior or accessibility. Flag clipped content, inaccessible controls, broken dynamic layout, or missing accessibility semantics introduced by a UI change.

## Project and validation

- When resources, files, build settings, signing, or dependencies change, verify target membership and Debug/Release behavior in `WhoGaveWhat.xcodeproj/project.pbxproj`.
- Require focused tests for changed use-case contracts, direction and validation logic, persistence transactions, routing, aggregation, or date/formatting behavior. Do not demand tests that duplicate compiler or framework behavior.
- Repository validation uses `xcodebuildmcp simulator test` locally and `.github/workflows/tests.yml` in CI. UI changes also require walking the changed scenario and visually checking a simulator snapshot.
