# App Store listing

The listing text lives in [`fastlane/metadata`](../fastlane/metadata) in fastlane `deliver`
layout, in English (`en-US`) and Russian (`ru`). Screenshots are generated, not committed: the
`Store screenshots` workflow captures them from the Debug sample data and keeps them as a
`store-screenshots` artifact for review; its `index.html` shows every set by device and language. There are
four sets:

- **6.9" iPhone** (`NN_slug.png`, 1320×2868) on iPhone 18 Pro Max.
- **6.3" iPhone** (`medium_NN_slug.png`, 1206×2622) on iPhone 18 Pro. Apple requires at least one
  screenshot for iPhone with Dynamic Island (medium display) and doesn't say the 6.9" set counts.
- **iPhone Duo** (`duo_NN_slug.png`, 1398×2034) on the folded iPhone Duo Simulator, so it shows the
  outer display. Apple doesn't say which display to show, and only the folded pose can be captured
  in CI. With Duo screenshots the product page shows the "optimized for iPhone Duo" badge; Apple
  requires them from April 2027 for apps built with the iOS 27.1 SDK. Uploading this set needs
  fastlane 2.241.1 or later (`APP_IPHONE_DUO`).
- **13" iPad** (`ipad_NN_slug.png`, 2064×2752, portrait) on the newest 13-inch iPad Pro. Apple requires it once
  the app runs on iPad and scales it down for the smaller iPads. In regular width the app shows its iPad layout:
  "Add a gift" in the toolbar, Save in the form's header, pickers as popovers and Insights in two columns, so the
  set shows the comparison on the Insights shot and has no separate compare shot. fastlane files 2064×2752 under
  the 13-inch display type (`APP_IPAD_PRO_3GEN_129`).

fastlane `deliver` sorts each language folder's files into sets by pixel size, in file name order.

The `App Store metadata` workflow uploads the text and, when given a screenshots run ID, those
screenshots to the editable App Store version. `deliver` replaces every set of each language it uploads, so the
run must contain all four sets; the `Store screenshots` workflow refuses to combine an incomplete run. It never uploads a build and never submits for
review. It runs only by manual dispatch on `master`, after Danis approves the listing.

| Field | Limit | Notes |
|---|---|---|
| `subtitle.txt` | 30 | Searchable, so it carries the main search phrase ("gift tracker", «учёт подарков»). |
| `keywords.txt` | 100 | Comma-separated, no spaces after commas; don't repeat words from the name or subtitle. |
| `promotional_text.txt` | 170 | Can change at any time without review. |
| `description.txt` | 4000 | Not searchable. Plain text. |
| `release_notes.txt` | 4000 | What's New of the version being uploaded. Covers every user-visible change since the version on the App Store; replace it for each update. |
| `review_information/notes.txt` | 4000 | Reviewer notes. Contact details are never committed (see App Review Information below). |

## Search by name

Each storefront indexes only its own languages, so «Кто Че Подарил» must be searchable in storefronts that
never read the `ru` localization. Apple's [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/)
table lists each storefront's default and additional languages. AppTweak's [cross-localization
tests](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store) (updated
November 2025) agree on the indexed languages and conclude: "Other than in Canada and the US, apps globally rank
for keywords included in the English (UK) or English (US) metadata, depending on which one is set as the primary
locale." Our primary locale is `en-US`, and we have no `en-GB`. In the table the default language comes first.

| Storefronts | Their languages | What we get indexed |
|---|---|---|
| Russia | **Russian**, English (U.K.), Ukrainian | `ru`, likely also `en-US` |
| Ukraine | **English (U.K.)**, Russian, Ukrainian | `en-US` (fallback), `ru` |
| United States | **English (U.S.)**, Russian, Spanish (Mexico), Arabic, Chinese, French, Korean, Portuguese (Brazil), Vietnamese | `en-US`, `ru` |
| Kazakhstan, Belarus, Uzbekistan, Kyrgyzstan, Tajikistan, Turkmenistan, Azerbaijan, Armenia, Georgia, Moldova, Latvia, Lithuania, Estonia, Mongolia | **English (U.K.)** only | `en-US` (fallback) |
| Israel, Türkiye, United Arab Emirates, Cyprus, Serbia, Montenegro | **English (U.K.)** plus Hebrew, Turkish, Arabic, Greek or Croatian | `en-US` (fallback) |
| Germany, France, Italy, Spain, Poland, Czechia and most of Europe | **their language** plus English (U.K.) | `en-US` (fallback) |

The iTunes Search API agreed on 2026-11-01: «кто че подарил» found the app in ru, ua and us and nothing in kz,
by, ge, am, rs, de, ae, il and tr, while "who gave what" found it in kz, by and il. So `en-US` is what those
storefronts read.

**Scheme.** The `en-US` keywords carry the words of the Russian name, `кто,че,подарил`, and `что`, so «кто че
подарил» and «кто что подарил» match through `en-US` everywhere English is indexed. Apple combines words from the
name, subtitle and keywords of one localization, never across localizations. The `ru` keywords add `что` (the
name already has the rest) and `др` (short for «день рождения»). App Store search treats ё as е («кто чё
подарил» found the app in ru on 2026-11-01), so `чё` is not needed. Only the name is covered this way: generic
Russian searches such as «учёт подарков» still find the app only where `ru` is indexed.
`scripts/tests/test_store_listing_text.py` checks this and that keywords don't repeat the name or subtitle.

**Adding `en-GB`.** It would replace the `en-US` fallback in all the English (U.K.) storefronts above, so its
keywords would have to carry the Russian words instead. It could also change which language Russian-speaking
customers in those storefronts see. We don't add it for now.

Keywords and the name change only with a new version. Indexing takes from a few hours to two days after
release; then check with `https://itunes.apple.com/search?term=кто+че+подарил&country=kz&entity=software` per
storefront (the API rate-limits, so wait a few seconds between requests).

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
  off, and the PostHog anonymous ID): App Functionality and Analytics; not linked to the user; not
  used for tracking.
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

**Header and Search Results:** the product page header (3840 × 1646) and search results
(3840 × 2560) images live in [`store-assets/creative`](store-assets/creative/README.md) with their
sources and prompts. Upload them by hand on the version page for each language; fastlane does not
support these placements.

## Sample portraits

The faces of the sample people in the screenshots are fictional portraits generated with Codex's
built-in image generation; the prompts are in [`sample-faces-prompts.json`](sample-faces-prompts.json).
They live in `WhoGaveWhat/SampleContent`, a development asset path that Xcode leaves out of
archives, and the TestFlight lane rejects an archive that still contains them.
