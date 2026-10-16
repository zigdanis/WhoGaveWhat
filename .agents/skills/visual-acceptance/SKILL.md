---
name: visual-acceptance
description: Capture, inspect and attach WhoGaveWhat Simulator screenshots (and a requested clip) to pull requests. Use for user-visible features and UI fixes before merge or TestFlight deployment.
---

# Visual acceptance

- **Capture** and inspect screenshots that show the requested UI change, then attach them to the PR. For non-UI changes, report functional checks instead.
- **Show:** add a focused XCUITest for the changed scenario then use media from the current head's CI run.
- **Limit:** use 2–6 screenshots. Skip duplicates and unrelated screens.
- **Clip:** add a video clip only when Danis asks to review the flow manually or motion can't be shown in stills. Never attach a full-suite recording.
- **Check:** confirm that the media shows the requested behavior, publish it with `scripts/pr-visual-evidence.py` and check that it displays clearly.
- **Clean up:** remove downloaded evidence after publishing.
