---
name: visual-acceptance
description: Capture, inspect and attach WhoGaveWhat Simulator screenshots (and a requested clip) to pull requests. Use for user-visible features and UI fixes before merge or TestFlight deployment.
---

# Visual acceptance

- **Capture** and inspect screenshots that show the requested UI change, then attach them to the PR. For non-UI changes, report functional checks instead. The `Tests` workflow runs no UI tests (only the `Store screenshots` workflow drives the UI, for the App Store set), so every PR capture is manual.
- **App:** wait for the PR head's `Simulator app` workflow, then `scripts/simulator-app.sh PR_NUMBER` prints the Release `WhoGaveWhat.app` for it (the Release build ignores `KS_SAMPLE_DATA`, so enter the data the scenario needs). On Linux, install and drive it on an Expo cloud simulator with the `eas-simulator` skill; on a Mac, use a local simulator.
- **Show:** walk the changed scenario by hand and screenshot each state that proves it.
- **Limit:** use 2–6 screenshots. Skip duplicates and unrelated screens.
- **Clip:** record a short clip only when Danis asks to review the flow manually or motion can't be shown in stills.
- **Check:** confirm that the media shows the requested behavior, then attach it with `gh pr comment PR_NUMBER --attach 'PATH#alt text' --body "..."` naming the reviewed commit, and check that it displays clearly.
- **HTML page:** when Danis asks for the screenshots as a page (to open in T3 on iPhone), write one self-contained file in `~/.t3/userdata/attachments/` with the images embedded, and give him its absolute path. Reuse `PAGE_STYLE` and the `ZOOM` viewer from `scripts/store-screenshots.py`, or build it with that script's `render_review`. Tapping a screenshot must open it full screen inside the page, the arrow keys and a swipe must step through every shot, and a tap or Escape must close it; a plain link to an embedded `data:` image does nothing in T3. Check those interactions in headless Chrome before handing the page over.
- **Clean up:** stop the cloud simulator session and remove the downloaded app and media after publishing.
