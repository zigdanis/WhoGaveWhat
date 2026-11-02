---
name: app-store-screenshots
description: Re-shoot and upload the WhoGaveWhat App Store screenshots (EN + RU) after a design change. Use when the UI changes and the store screenshots must be refreshed, or a new device set is added. Not for app preview videos.
---

# App Store screenshots

One real UI test captures the real app on a simulator and the captures go to the editable App Store version. Do not invent another route: no hand-made mocks, no extra tests, no injected dates.

## What exists here and what does not

- **Exists:** the 6.9-inch, 6.3-inch, iPhone Duo outer-display and 13-inch iPad sets (`scripts/store-screenshots.py OUT --display DISPLAY`, where DISPLAY is `iphone-6.9`, `iphone-6.3`, `iphone-duo` or `ipad-13`; the `Store screenshots` workflow shoots all four in CI and merges them with `--combine` into one `store-screenshots` artifact whose `index.html` is the review page of every set by device and locale), `WhoGaveWhatUITests/StoreScreenshotsUITests.swift` (the capture test, EN and RU, Debug sample data, one attachment per screen), `scripts/store-screenshots.py` (runs it on a simulator it creates itself and deletes afterward, and lays the files out per locale with an `index.html` contact sheet; its tests are `scripts/tests/test_store_screenshots.py`), the `Store screenshots` workflow, the `App Store metadata` workflow with the `store_metadata` lane in `fastlane/Fastfile`, and `docs/app-store.md`.
- **Does not exist yet:** running on an existing simulator chosen by the caller (the script only selects a model, which breaks the rule below, so add and test that option before any local capture), composed store cards with headlines, and a local upload command. Create what is needed on first use, next to the existing script and with tests in `scripts/tests`, and say so in the PR; do not point at tooling that is not in the repo.

## What gets shot (flexible)

The story follows the app's *current* design; nothing about the screens or sample data is fixed. Rules that stay:

- **The main screens are in the set.** Whatever the app's primary screens are today, each gets a shot. A screen that no longer exists gets none; a new main screen must get one.
- **One test, rewritten per design.** `StoreScreenshotsUITests` is the only capture test. When the design changes, edit it so it walks the new flow through the real UI and attaches one named shot per screen. Delete the steps for screens that are gone; do not add a second test.
- **Demo data serves the story.** Use the app's Debug sample data and change it only when the story needs it.
- **Follow the test.** Attachment names are the contract between the test and `scripts/store-screenshots.py`; change both together and update `scripts/tests`.
- **Copy is short, EN and RU.** If cards with headlines are added, take the wording from the design and check that the RU text fits.

## Steps

1. **Adapt the test to the current design.** List the main screens and rewrite the capture test for them.
2. **Pick the sets from what App Store Connect requires, not from the deployment target.** Check Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) for the current rules. The required set is the iPhone Dynamic Island medium one. Beyond it shoot only the optional sets Danis wants: Dynamic Island, notch, Home Button, and iPhone Duo with the outer display only. Everything else stays unshot; Apple scales or falls back. Take the pixel sizes from Apple's page, not from memory, and verify each capture has exactly the size of its set.
3. **Simulators: the shared MacPro pool.** Never run the script as it is locally, because it creates and deletes its own simulator; use it locally only after the existing-simulator option exists. Run the capture on MacPro (from another machine, `ssh macpro.remote` for xcodebuild and the script only) on the pool device whose native pixel size matches the set (pool list: `~/myai/fleet/services/app-store-simulators/README.md`). Create a missing device only for a set the pool README lists as required, on the newest compatible runtime, and keep it; for any other size, such as one the pool deliberately leaves out, ask Danis. One simulator at a time; shut it down after, keeping the device and its data.
4. **Xcode: the newest installed one, with its newest simulator runtime.** Never pin or fall back to an older major version.
5. **Before every capture, take a slot in MacPro's simulator queue** with the `simulator-queue` skill: wait behind other jobs and for a healthy machine instead of capturing through the slowdown or killing their work. Then boot the one simulator and set a clean status bar (9:41, full battery and signal); `scripts/store-screenshots.py` already sets it.
6. **Capture one set at a time.** EN and RU run in one command. Confirm both locales passed with no failed tests, and never delete a passing capture before its replacement exists.
7. **Look at every PNG.** Open all shots one by one: correct locale, no clipped text (RU is longer), correct pixel size, no alpha channel, nothing from another app.
8. **Build the review page.** One browsable file with every uploaded screenshot, grouped by device and locale. The combined artifact's `index.html` (`scripts/store-screenshots.py --combine`) is the CI copy. For Danis, download the green run's `store-screenshots` artifact and run `scripts/store-screenshots.py ARTIFACT_DIR --review-page ~/.t3/userdata/attachments/NAME.html --note "run ID, PR"`, which writes one self-contained page with the images embedded, and give him the page's absolute path. He opens it in T3, often on iPhone, so the page must work without its folder:
   - Tapping a screenshot opens it full screen inside the page. The arrow keys and a swipe go to the next or previous shot across the whole page, and a tap or Escape closes it. The `ZOOM` viewer in the script does this; never replace it with plain links, because a link to an embedded `data:` image does nothing in T3.
   - Before handing the page over, run `scripts/check-review-page.py PAGE`. It loads a copy of the page with a probe script in headless Chrome, taps the first shot, presses the arrows and taps again, and fails unless the viewer opens, steps through every shot and closes. That the file exists is not enough.
9. **Upload without waiting for approval.** The `App Store metadata` workflow (manual dispatch on `master`) sends the screenshots of a green `Store screenshots` run to the editable version. It also sends the listing text from `fastlane/metadata`, so make sure that text is what should go live. Never print or commit the App Store Connect key and never submit for App Review. Then open the review page for Danis so he can check what was uploaded without opening App Store Connect.
10. **Deliver.** Open the PR through `full-send`. Shut down any simulator you booted and remove temporary keys and DerivedData.

## Rules that save time

- Never run extra "probe" tests, diagnostics or re-captures to check consistency. If a capture passed and no input changed, use it.
- Do not change app code to make a screenshot work; if the app looks wrong on a device, report it.
- Do not touch simulators you did not start.
- No full-screen or browser screenshots while working; they can expose unrelated content.
- Do not submit for App Review and do not edit other store metadata or delete other devices' screenshots.
