# Analytics and crash reporting

Who Gave What records anonymous product events with [PostHog](https://posthog.com) and crashes,
hangs and handled failures with [Sentry](https://sentry.io). Both run through one
`AnalyticsGateway` owned by the composition root; features never talk to an SDK directly.

## What is recorded

Every event carries categories and counts only. Names, gift titles, amounts, photos and exact
dates never leave the device. The full list lives in `WhoGaveWhat/Models/AnalyticsEvent.swift`;
`AnalyticsEventCatalogTests` keeps names and keys in snake_case.

| Event | Properties | Fires when |
|-------|------------|------------|
| `tab_selected` | `tab` | A tab bar tap changes the tab |
| `gift_sheet_opened` | `mode` create/edit, `source` welcome_card/floating_button/gift_detail | The Add or Edit gift sheet opens |
| `gift_sheet_closed` | `mode`, `outcome` saved/cancelled/failed | The sheet closes |
| `gift_picker_opened` | `picker` giver/recipient/occasion/icon/date | A picker opens inside the sheet |
| `gift_icon_picked` | `source` list/custom | The user overrides the inferred icon |
| `gift_price_edited` | `had_estimate` | The first edit of the price field in a sheet |
| `gift_suggestion_completed` | `provider` cloud/on_device, `outcome`, `has_icon`, `has_price`, `latency_ms` | An icon/price inference returns |
| `occasion_added` | – | A custom occasion is typed |
| `cloud_icons_consent_changed` | `consent` allowed/declined, `source` add_gift/settings | The cloud icon choice changes |
| `gift_saved` | `mode`, `direction` received/given/unrelated/no_viewpoint, `icon_source`, `value_source` user/estimate/none, `occasion` (built-in key or `custom`), `paid_by_you`, `date_offset`, `gifts_count` | A gift is stored |
| `gift_deleted` | `source` home/person_detail/gift_detail, `gifts_count` | A gift is removed |
| `gift_detail_viewed` | – | A gift screen appears |
| `person_detail_viewed` | `is_self`, `gifts_count` | A person screen appears |
| `person_created` | `source` people_tab/gift_picker, `people_count` | A new person is stored (not a duplicate name) |
| `person_updated` | `name_changed`, `photo` added/replaced/removed/unchanged | The person editor saves |
| `person_deleted` | `source` people_list/person_editor, `gifts_removed`, `people_count` | A person is removed |
| `viewpoint_changed` | `is_set` | "This is me" is switched |
| `insights_person_picked` | `slot` subject/compareA/compareB | An Insights picker choice |
| `insights_year_changed` | `is_current_year` | The Insights year menu |
| `currency_changed` | `currency` | Settings → Currency |
| `privacy_policy_opened`, `licenses_opened` | – | Settings → About |
| `analytics_consent_changed` | `enabled` | Settings → Diagnostics; `false` is the last event sent |
| `app_opened_from_spotlight` | – | The Spotlight launcher opened the app |

PostHog adds its own `Application Installed / Opened / Updated / Backgrounded` events and attaches
these super properties to everything: `app_environment` (testflight/appstore), `gifts_count`,
`people_count`, `has_viewpoint`, `currency`, `cloud_icons`. The same values travel to Sentry as the
`app_state` context, and every product event becomes a Sentry breadcrumb.

Handled failures (`AnalyticsFailure`) go to Sentry only, tagged with `operation`: `load_gifts`,
`load_people`, `save_gift`, `delete_gift`, `create_person`, `rename_person`, `update_person`,
`delete_person`, `load_person_photo`, `cloud_icon_request`, `cloud_icon_decode`,
`on_device_inference`, `spotlight_index`. A duplicate person name, being offline and cancellation
are ordinary and are not reported.

## When nothing is sent

- Debug builds, the Simulator and verification launches (any `KS_` environment variable) never
  start the SDKs; Debug builds log every call to the unified log instead
  (`subsystem pro.ziganshin.WhoGaveWhat`, category `Analytics`).
- A missing key leaves that service off: the app ships silent until the keys below are set.
- Settings → Diagnostics → "Share usage and crash reports" is on by default; turning it off opts
  PostHog out and closes Sentry until it is turned on again.

## Keys

The keys are public client identifiers and live in the `WhoGaveWhat` target build settings, both
Debug and Release, exposed through `Info.plist`:

| Build setting | Info.plist key | Value |
|---------------|----------------|-------|
| `POSTHOG_API_KEY` | `PostHogAPIKey` | The project API key (`phc_…`) |
| `POSTHOG_HOST` | `PostHogHost` | `https://eu.i.posthog.com` or `https://us.i.posthog.com`; empty means EU |
| `SENTRY_DSN` | `SentryDSN` | The project DSN |

Set them in `WhoGaveWhat.xcodeproj/project.pbxproj` (or Xcode → target → Build Settings → User-Defined)
and commit; the TestFlight lane builds from the committed project.

The packages are pinned to "up to next major" ranges. The first build on a Mac writes
`WhoGaveWhat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; commit it (it is
ignored by the `Package.resolved` rule in `.gitignore`, so add it with `git add -f`) so release builds
resolve the same versions.

## Crash symbols

The TestFlight workflow uploads the archive's dSYMs after a successful `deploy` when these exist in
the `testflight` environment:

- secret `SENTRY_AUTH_TOKEN`, an organization auth token with the `project:releases` and
  `project:write` scopes;
- variables `SENTRY_ORG` and `SENTRY_PROJECT`.

The step runs whenever the run archived a build, even if a later distribution step failed, and
the archive's dSYMs are also kept as the `dsyms-RUN_ID-ATTEMPT` workflow artifact for 90 days. It
downloads the pinned `sentry-cli` release binary and checks its SHA-256 before running it. Without
the secret and variables it prints a skip notice and the release continues; crashes then show
unsymbolicated frames until the symbols are uploaded by hand with
`sentry-cli debug-files upload PATH/dSYMs`. Release builds produce dSYMs
(`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`).

## App Store privacy

`WhoGaveWhat/PrivacyInfo.xcprivacy` declares Product Interaction, Crash Data, Performance Data and
Other Diagnostic Data, not linked to the user and not used for tracking. Keep the App Store Connect
answers in [app-store.md](app-store.md) and the privacy policy in step with that list.
