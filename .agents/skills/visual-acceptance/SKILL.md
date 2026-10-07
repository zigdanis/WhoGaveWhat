---
name: visual-acceptance
description: Capture, inspect, and embed current WhoGaveWhat screenshots and video in PR descriptions for feature, fix, documentation, and tooling delivery, using macOS CI when local iOS execution is unavailable.
---

# Visual acceptance

Read [docs/pr-evidence.md](../../../docs/pr-evidence.md) for the maintained
capture, retrieval, and publication commands.

1. Define observable criteria. For UI changes, exercise the changed interaction
   and relevant success, error, and dismissal paths in the CI journey. For
   documentation, tooling, and infrastructure changes, app-smoke evidence
   covers environment integrity and must be labelled accordingly.
2. Use XcodeBuildMCP for native operations. Reuse a booted iPhone or prefer
   iPhone 17 Pro. On Linux/Raspberry Pi, retrieve the PR's macOS CI artifact
   with `scripts/pr-evidence.sh PR_NUMBER`.
3. Inspect every selected PNG and the original MP4 against the criteria. Use
   extracted frames for transitions and inspect the recording itself when
   timing or animation matters. Write a short English review outside the
   checkout, publish screenshots and video with
   `scripts/pr-visual-evidence.py`, then run `scripts/pr-evidence-gate.py`.
4. After every push or full CI rerun, retrieve and inspect the latest attempt
   and republish evidence. Old media cannot establish current-head acceptance.

Finish only when current inspected evidence and functional checks demonstrate
the requested outcome. Report exact gaps when a capture or publication step is
blocked. Follow [TestFlight operations](../../../docs/testflight.md) for every
routine feature, fix, improvement, and build request; only explicit discussion,
plan-only, PR-only, or do-not-deploy limits suppress the beta release path.
