---
name: app-store-screenshots
description: Re-shoot and upload the WhoGaveWhat App Store screenshots (EN + RU) after a design change. Use when the UI changes and the store screenshots must be refreshed, or a new device set is added. Not for app preview videos.
---

# App Store screenshots

One real UI test captures the real app on a simulator and the captures go to the editable App Store version. Do not invent another route: no hand-made mocks, no extra tests, no injected dates.

## What exists here and what does not

- **Where:** only on MacPro, never in CI (no workflow captures screenshots, and none may be added). Which pool device each set uses, taking the queue slot, reaching MacPro from Linux, health checks and cleanup are in the Fleet `simulator-queue` skill (`~/myai/fleet/skills/simulator-queue/SKILL.md`); this skill does not repeat them.
- **Exists:** `scripts/store-screenshots.py OUT --display DISPLAY --simulator UDID` captures one set on an existing pool device and never creates or deletes one. DISPLAY is `iphone-6.3` (Dynamic Island medium, `medium_NN_slug.png`), `iphone-6.5` (Face ID large, `large_NN_slug.png`), `iphone-duo` (outer display, `duo_NN_slug.png`) or `ipad-13` (`ipad_NN_slug.png`); the script refuses a device of the wrong model. It builds before booting, boots the device only if it is shut down, sets the 9:41 status bar, and afterwards clears it, uninstalls the UI test runner and shuts down only a device it booted. `--combine PARTS` merges `PARTS/store-screenshots-<display>/` into one folder per language with an `index.html` of every set; `--check` confirms a combined folder has every set from one commit; `--review-page` writes the self-contained page. The capture test is `WhoGaveWhatUITests/StoreScreenshotsUITests.swift` (EN and RU, Debug sample data, one attachment per screen); the script's tests are `scripts/tests/test_store_screenshots.py`. `scripts/publish-store-screenshots.sh COMBINED` hands the folder to the upload as a private draft release and prints its tag; the `App Store metadata` workflow (`store_metadata` lane in `fastlane/Fastfile`) uploads it. Background: `docs/app-store.md`.
- **Does not exist yet:** composed store cards with headlines, and a Home Button (iPhone SE) set. Create what is needed on first use, next to the existing script and with tests in `scripts/tests`, and say so in the PR; do not point at tooling that is not in the repo.

## What gets shot (flexible)

The story follows the app's *current* design; nothing about the screens or sample data is fixed. Rules that stay:

- **The main screens are in the set.** Whatever the app's primary screens are today, each gets a shot. A screen that no longer exists gets none; a new main screen must get one.
- **One test, rewritten per design.** `StoreScreenshotsUITests` is the only capture test. When the design changes, edit it so it walks the new flow through the real UI and attaches one named shot per screen. Delete the steps for screens that are gone; do not add a second test.
- **Demo data serves the story.** Use the app's Debug sample data and change it only when the story needs it.
- **Follow the test.** Attachment names are the contract between the test and `scripts/store-screenshots.py`; change both together and update `scripts/tests`.
- **Copy is short, EN and RU.** If cards with headlines are added, take the wording from the design and check that the RU text fits.

## Steps

1. **Adapt the test to the current design.** List the main screens and rewrite the capture test for them.
2. **Pick the sets from what App Store Connect requires, not from the deployment target.** Check Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) for the current rules. The required sets are Dynamic Island medium and, because only one Dynamic Island set is shot, Face ID large; the app runs on iPad, so the 13-inch iPad set too. Beyond them shoot only the optional sets Danis wants: iPhone Duo with the outer display only (and Home Button once it exists). Everything else stays unshot; Apple scales or falls back. Take the pixel sizes from Apple's page, not from memory; the script checks each capture against its set.
3. **Prepare off the slot.** Push the commit to shoot, check it out on MacPro (a separate worktree of `~/Projects/whogavewhat`, never someone else's checkout), and join MacPro's queue per `simulator-queue`. The script builds itself, so the slot covers build and capture; nothing else needs the simulator.
4. **Xcode: the newest installed one.** Never pin or fall back to an older major version.
5. **Capture one set at a time** on its pool device, EN and RU in one command, into `PARTS/store-screenshots-<display>`: `python3 scripts/store-screenshots.py PARTS/store-screenshots-iphone-6.3 --display iphone-6.3 --simulator UDID`, then the other sets. Confirm both locales passed with no failed tests, and never delete a passing capture before its replacement exists. Then `python3 scripts/store-screenshots.py COMBINED --combine PARTS`, release the slot as `simulator-queue` says, and copy `COMBINED` to your machine if you work from Linux.
6. **Look at every PNG.** Open all shots one by one: correct locale, no clipped text (RU is longer), correct pixel size, no alpha channel, nothing from another app.
7. **Build the review page.** `scripts/store-screenshots.py COMBINED --review-page ~/.t3/userdata/attachments/NAME.html --note "commit, PR"` writes one self-contained page with the images embedded; give Danis its absolute path. He opens it in T3, often on iPhone, so the page must work without its folder:
   - Tapping a screenshot opens it full screen inside the page. The arrow keys and a swipe go to the next or previous shot across the whole page, and a tap or Escape closes it. The `ZOOM` viewer in the script does this; never replace it with plain links, because a link to an embedded `data:` image does nothing in T3.
   - Before handing the page over, run `scripts/check-review-page.py PAGE`. It loads a copy of the page with a probe script in headless Chrome, taps the first shot, presses the arrows and taps again, and fails unless the viewer opens, steps through every shot and closes. That the file exists is not enough.
8. **Upload without waiting for approval.** `scripts/publish-store-screenshots.sh COMBINED` (needs `gh`; run it where `gh` is signed in) checks the folder and prints a tag such as `store-screenshots/20261108-174500`. Dispatch `gh workflow run app-store-metadata.yml --ref master -f app_version=X.Y -f screenshots_release=TAG`. The workflow also sends the listing text from `fastlane/metadata`, so make sure that text is what should go live, and `deliver` replaces every set of each language, so the folder must hold every set. Never print or commit the App Store Connect key and never submit for App Review. After a green upload, delete older `store-screenshots/` drafts (`gh release delete TAG --yes`) and keep the uploaded one. Then open the review page for Danis so he can check what was uploaded without opening App Store Connect.
9. **Deliver.** Open the PR through `full-send` (test or script changes only; the screenshots themselves are never committed). Remove the MacPro worktree, temporary files and DerivedData.

## Rules that save time

- Never run extra "probe" tests, diagnostics or re-captures to check consistency. If a capture passed and no input changed, use it.
- Never add a CI workflow or job that captures screenshots, even "just once"; MacPro is the only place, and waiting in its queue is expected.
- Do not change app code to make a screenshot work; if the app looks wrong on a device, report it.
- No full-screen or browser screenshots while working; they can expose unrelated content.
- Do not submit for App Review and do not edit other store metadata or delete other devices' screenshots.
