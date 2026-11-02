---
name: visual-acceptance
description: Capture, inspect and attach WhoGaveWhat Simulator screenshots (and a requested clip) to pull requests. Use for user-visible features and UI fixes before merge or TestFlight deployment.
---

# Visual acceptance

- **Capture** and inspect screenshots that show the requested UI change, then attach them to the PR. For non-UI changes, report functional checks instead. The `Tests` workflow runs no UI tests (only the `Store screenshots` workflow drives the UI, for the App Store set), so every PR capture is manual.
- **App:** wait for the PR head's `Simulator app` workflow, then `scripts/simulator-app.sh PR_NUMBER` prints the Release `WhoGaveWhat.app` for it (the Release build ignores `KS_SAMPLE_DATA`, so enter the data the scenario needs). Run it on the MacPro simulator pool. On MacPro itself that is the `local` device host; every other machine, MacAir included, uses the `macpro` host:
  - **Queue first:** take a ticket in MacPro's queue (`~/.local/state/simulator-queue/`, over `ssh macpro.remote` from another machine) per the `simulator-queue` skill, and start only when it is the oldest live ticket and MacPro is healthy (load, memory pressure and disk checked on MacPro; ssh is fine for this, never for UI actions). The ticket lists no process, so the heartbeat alone keeps it live: refresh it every 1–2 minutes while waiting and at least every 5 minutes while you hold the slot.
  - **Device:** then `device_list`, note whether the device is already `booted`, and `device_open` it. Use the pool devices (pool list: `~/myai/fleet/services/app-store-simulators/README.md`): iPhone 17 Pro by default, iPhone SE (3rd generation) for compact height, `GU iPad Pro 13` for regular width. Danis watches it in the thread's Device panel. Install with the returned `agent-device install pro.ziganshin.WhoGaveWhat PATH.app` (it uploads the local `.app`; never `reinstall`, which replaces the app and its data) and drive every tap, text entry and screenshot through that command, never `simctl` or ssh.
  - **Data:** pool devices keep WhoGaveWhat's data between threads, and installing over it keeps that data. Look at what is there first, and delete anything your scenario adds before you finish.
  - **Keyboard:** the Mac's hardware keyboard hides the software one until text is typed, so type a character before capturing a screen that must show the keyboard.
  - **Errors:** if `device_open` or the returned command fails, quote the error, follow its advice once, and if it still fails tell Danis and stop.
  - **Fallback:** only when `device_list` shows the `macpro` host missing or not `ready` (MacPro asleep or unreachable), tell Danis its status and error, then use an Expo cloud simulator with the `eas-simulator` skill; it spends a small shared trial budget.
- **Show:** walk the changed scenario by hand and screenshot each state that proves it.
- **Limit:** use 2–6 screenshots. Skip duplicates and unrelated screens.
- **Clip:** record a short clip only when Danis asks to review the flow manually or motion can't be shown in stills.
- **Check:** confirm that the media shows the requested behavior, then attach it with `gh pr comment PR_NUMBER --attach 'PATH#alt text' --body "..."` naming the reviewed commit, and check that it displays clearly.
- **HTML page:** when Danis asks for the screenshots as a page (to open in T3 on iPhone), write one self-contained file in `~/.t3/userdata/attachments/` with the images embedded, and give him its absolute path. Reuse `PAGE_STYLE` and the `ZOOM` viewer from `scripts/store-screenshots.py`, or build it with that script's `render_review`. Tapping a screenshot must open it full screen inside the page, the arrow keys and a swipe must step through every shot, and a tap or Escape must close it; a plain link to an embedded `data:` image does nothing in T3. Before handing the page over, run `scripts/check-review-page.py PAGE`, which checks those interactions in headless Chrome.
- **Clean up:** `device_close` every device you opened, with `shutdown: true` only for the ones you booted; delete your queue ticket (or stop the cloud session), and remove the downloaded app and media after publishing.
