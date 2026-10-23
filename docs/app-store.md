# App Store listing

The listing text lives in [`fastlane/metadata`](../fastlane/metadata) in fastlane `deliver`
layout, in English (`en-US`) and Russian (`ru`). Screenshots are generated, not committed: the
`Store screenshots` workflow captures them on a 6.9" iPhone Simulator from the Debug sample data
and keeps them as a `store-screenshots` artifact for review.

The `App Store metadata` workflow uploads the text and, when given a screenshots run ID, those
screenshots to the editable App Store version. It never uploads a build and never submits for
review. It runs only by manual dispatch on `master`, after Danis approves the listing.

| Field | Limit | Notes |
|---|---|---|
| `subtitle.txt` | 30 | Searchable, so it carries the main search phrase ("gift tracker", «учёт подарков»). |
| `keywords.txt` | 100 | Comma-separated, no spaces after commas; don't repeat words from the name or subtitle. |
| `promotional_text.txt` | 170 | Can change at any time without review. |
| `description.txt` | 4000 | Not searchable. Plain text. |
| `review_information/notes.txt` | 4000 | Reviewer notes. Contact details come from the `BETA_REVIEW_INFO` secret and are never committed. |

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

- Do you collect data? **Yes** — only when the user allows cloud suggestions.
- **User Content → Other User Content** (the typed gift name): App Functionality; not linked to
  the user; not used for tracking.
- **Identifiers → Device ID** (the random rate-limit ID, recreated whenever the feature is turned
  off): App Functionality; not linked to the user; not used for tracking.
- Nothing else. No tracking.

**Age Rating:** answer None / No to every question. No unrestricted web access, no user-generated
content shared with others, no messaging, no gambling, no loot boxes. Expected result: 4+.

**App Review Information:** sign-in not required.

**Export compliance:** already declared in the build (`ITSAppUsesNonExemptEncryption = NO`).
