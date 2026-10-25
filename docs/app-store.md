# App Store listing

The listing text lives in [`fastlane/metadata`](../fastlane/metadata) in fastlane `deliver`
layout, in English (`en-US`) and Russian (`ru`). Screenshots are generated, not committed: the
`Store screenshots` workflow captures them from the Debug sample data and keeps them as a
`store-screenshots` artifact for review. There are three sets:

- **6.9" iPhone** (`NN_slug.png`, 1320×2868) on iPhone 18 Pro Max.
- **6.3" iPhone** (`medium_NN_slug.png`, 1206×2622) on iPhone 18 Pro. Apple requires at least one
  screenshot for iPhone with Dynamic Island (medium display) and doesn't say the 6.9" set counts.
- **iPhone Duo** (`duo_NN_slug.png`, 1398×2034) on the folded iPhone Duo Simulator, so it shows the
  outer display. Apple doesn't say which display to show, and only the folded pose can be captured
  in CI. With Duo screenshots the product page shows the "optimized for iPhone Duo" badge; Apple
  requires them from April 2027 for apps built with the iOS 27.1 SDK. Uploading this set needs
  fastlane 2.241.1 or later (`APP_IPHONE_DUO`).

fastlane `deliver` sorts each language folder's files into sets by pixel size, in file name order.

The `App Store metadata` workflow uploads the text and, when given a screenshots run ID, those
screenshots to the editable App Store version. It never uploads a build and never submits for
review. It runs only by manual dispatch on `master`, after Danis approves the listing.

| Field | Limit | Notes |
|---|---|---|
| `subtitle.txt` | 30 | Searchable, so it carries the main search phrase ("gift tracker", «учёт подарков»). |
| `keywords.txt` | 100 | Comma-separated, no spaces after commas; don't repeat words from the name or subtitle. |
| `promotional_text.txt` | 170 | Can change at any time without review. |
| `description.txt` | 4000 | Not searchable. Plain text. |
| `review_information/notes.txt` | 4000 | Reviewer notes. Contact details are never committed (see App Review Information below). |

## Set in App Store Connect by hand

These can't be set through the API key upload, or are kept by hand on purpose.

**Name:** "Who Gave What" (en-US) and «Кто Че Подарил» (ru). There is no `name.txt`, so the upload
never changes the name.

**Content Rights:** Yes, the app contains third-party content (Lucide icons under the ISC License,
see `WhoGaveWhat/Resources/THIRD_PARTY_NOTICES.md`, and the cloud gift icons), and you have the
rights to use it.

**Pricing and Availability:** Free, all countries. Apple Vision Pro availability off (the account
is not eligible to publish on visionOS; see ITMS-90984).

**App Privacy** (must match `WhoGaveWhat/PrivacyInfo.xcprivacy` and the privacy policy):

- Do you collect data? **Yes** — the typed gift name only when the user allows cloud
  suggestions; anonymous usage events and crash reports unless the user turns off
  Settings → Diagnostics (see [analytics.md](analytics.md)).
- **User Content → Other User Content** (the typed gift name): App Functionality; not linked to
  the user; not used for tracking.
- **Identifiers → Device ID** (the random rate-limit ID, recreated whenever the feature is turned
  off, and the PostHog anonymous ID): App Functionality; not linked to the user; not used for tracking.
- **Usage Data → Product Interaction** (screens opened, pickers used, counts): Analytics; not
  linked to the user; not used for tracking.
- **Diagnostics → Crash Data, Performance Data, Other Diagnostic Data** (Sentry crash and hang
  reports with device model and OS version): App Functionality; not linked to the user; not used
  for tracking.
- Nothing else. No tracking.

**Age Rating:** answer None / No to every question. No unrestricted web access, no user-generated
content shared with others, no messaging, no gambling, no loot boxes. Expected result: 4+.

**App Review Information:** sign-in not required. Enter the contact (first and last name, email,
phone) here once, and keep the reviewer notes in step with `review_information/notes.txt`. The
upload leaves this section alone unless the `BETA_REVIEW_INFO` secret holds all four contact fields:
App Store Connect rejects review detail updates without the contact.

**Export compliance:** already declared in the build (`ITSAppUsesNonExemptEncryption = NO`).

## Sample portraits

The faces of the sample people in the screenshots are fictional portraits generated with Codex's
built-in image generation; the prompts are in [`sample-faces-prompts.json`](sample-faces-prompts.json).
They live in `WhoGaveWhat/SampleContent`, a development asset path that Xcode leaves out of
archives, and the TestFlight lane rejects an archive that still contains them.
