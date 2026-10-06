---
name: visual-acceptance
description: Capture, inspect, and embed current WhoGaveWhat app screenshots and video in PR descriptions, including documentation and infrastructure PRs. Use before PR handoff and when validating visible changes from Linux or Raspberry Pi.
---

# Visual acceptance

Read [docs/pr-evidence.md](../../../docs/pr-evidence.md) for the maintained capture,
retrieval and publishing commands. Every PR needs screenshots **and** video from
its current head and latest passing Tests attempt.

1. Define observable acceptance criteria. For UI changes, extend the scenario in
   `scripts/run-app-smoke.py` or a focused native UI journey to exercise the changed
   interaction and its relevant success, error and dismissal paths. Include
   language/appearance variants when affected. Mark evidence `feature-acceptance`
   only when it actually demonstrates that scenario. Documentation and tooling
   changes use the existing `app-smoke` evidence with their functional checks.
2. Use XcodeBuildMCP for all native operations. Reuse a booted iPhone; otherwise
   prefer iPhone 17 Pro. On Raspberry Pi, push the task branch and retrieve its
   macOS CI evidence with `scripts/pr-evidence.sh PR_NUMBER`. Inspect every selected
   screenshot and the relevant recording against the criteria. Fix concrete
   failures and repeat on the same PR.
3. Write a short English review outside the checkout with what was inspected,
   outcomes and material limitations. Publish both screenshots and video with
   `scripts/pr-visual-evidence.py`, then run `scripts/pr-evidence-gate.py`. Inspect
   the original recording when timing, animation or transient failures matter;
   extracted frames demonstrate states but cannot prove animation smoothness.
4. Read back the PR description and verify native media attachments are embedded.
   After a push or CI rerun, retrieve, inspect and republish the latest evidence.
   Rerun the whole Tests workflow so the new attempt generates its own media.

Finish when current inspected evidence and functional checks demonstrate the
requested outcome. Mockups, old baselines and artifact-download links cannot
replace that evidence. Name exact verification gaps if capture or publication
fails, and continue independent authorized work.

For releases, follow [docs/testflight.md](../../../docs/testflight.md). Honor an
explicit deployment instruction already given for this scope; an ordinary feature
request or PR approval does not authorize a release.
