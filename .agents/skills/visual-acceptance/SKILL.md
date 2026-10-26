---
name: visual-acceptance
description: Capture, inspect and attach WhoGaveWhat Simulator screenshots (and a requested clip) to pull requests. Use for user-visible features and UI fixes before merge or TestFlight deployment.
---

# Visual acceptance

- **Capture** and inspect screenshots that show the requested UI change, then attach them to the PR. For non-UI changes, report functional checks instead. CI runs no UI tests and produces no screenshots; every capture is manual.
- **App:** wait for the PR head's `Simulator app` workflow, then `scripts/simulator-app.sh PR_NUMBER` prints the Release `WhoGaveWhat.app` for it (the Release build ignores `KS_SAMPLE_DATA`, so enter the data the scenario needs). On Linux, install and drive it on an Expo cloud simulator with the `eas-simulator` skill; on a Mac, use a local simulator.
- **Show:** walk the changed scenario by hand and screenshot each state that proves it.
- **Limit:** use 2–6 screenshots. Skip duplicates and unrelated screens.
- **Clip:** record a short clip only when Danis asks to review the flow manually or motion can't be shown in stills.
- **Check:** confirm that the media shows the requested behavior, then attach it with `gh pr comment PR_NUMBER --attach 'PATH#alt text' --body "..."` naming the reviewed commit, and check that it displays clearly.
- **Clean up:** stop the cloud simulator session and remove the downloaded app and media after publishing.
