---
name: whogavewhat-delivery
description: Deliver WhoGaveWhat fixes, features, improvements, and TestFlight build requests with bounded implementation, independent review, visual verification, and a monitored PR. Use for action requests in this repository; exclude read-only questions and general discussion.
---

# WhoGaveWhat delivery

Own the requested outcome until it is demonstrated on the current head. Follow
repository instructions and existing helpers; keep unrelated user changes intact.

## Establish and implement

1. Inspect the request and relevant code, including actual screenshots when supplied.
   Define observable acceptance criteria and checks for each. For bugs, use
   `diagnosing-bugs` when available. Apply the relevant SwiftUI skills to native UI
   work. Read [visual-acceptance](../visual-acceptance/SKILL.md) before validation.
2. Inspect the working tree, branch, existing PR and current checks. Continue an
   existing task PR where appropriate. Register every PR worked on using T3
   `link_pull_request` when available; verify the thread's PR list before handoff.
3. Delegate bounded implementation with acceptance criteria, relevant files,
   exclusive ownership and validation requirements. Keep branch/push/PR mutations
   with the coordinator. If delegation is unavailable, continue the authorized
   work and state that limitation.
4. Integrate the smallest appropriate change and focused contract tests. Use
   XcodeBuildMCP for native operations and reuse a launched iPhone; the authorized
   TestFlight Release archive/IPA export exception uses Fastlane `gym` as described
   in `docs/testflight.md`.
   On Raspberry Pi, use the macOS CI workflow from
   [docs/pr-evidence.md](../../../docs/pr-evidence.md). After a UI iteration, walk
   the changed scenario and inspect its screenshots and recording against every
   criterion; correct failures on the same PR before declaring acceptance.

Finish implementation when relevant checks and current visual evidence demonstrate
all acceptance criteria. Distinguish observed behavior from code-based hypotheses.

## Review and convergence

1. Open a draft task PR while acceptance is being established. Run formatting,
   SwiftLint and helper tests as repository instructions require. Native tests
   and app smoke run through the existing Tests workflow.
2. Have an independent agent review concrete correctness against
   [.macroscope/correctness/correctness.md](../../../.macroscope/correctness/correctness.md)
   and request coverage. For visible changes, an independent reviewer also checks
   actual feature screenshots and the relevant video. No findings is valid.
3. Write an English PR description around the resulting behavior and validation.
   Every PR, including documentation and infrastructure, embeds inspected current
   screenshots and video using `visual-acceptance`; app smoke covers changes with
   no visible effect. Run the evidence gate and verify the published description.
4. Once implementation, checks, independent review and evidence pass, mark the
   draft ready and await bot reviews. Use `babysit-pr` when available. Validate
   each finding, fix concrete problems, run the covering checks, and reply with
   evidence before resolving its conversation.
5. After every push, recheck the latest head, required checks, new reviews and
   unresolved conversations. Refresh evidence invalidated by a push or CI rerun.
   Repeat for new changes, failed checks or actionable findings.

Hand off when the current head is green, reviewers have reached a terminal state,
no actionable conversation remains and the PR contains current inspected media.
Follow repository merge instructions; do not infer merge authority from deployment
or feature authorization. Report the PR, verified outcome and exact remaining gaps.

## TestFlight

For deployment-only work, inspect the selected existing source and evidence instead
of manufacturing app changes. Follow
[docs/testflight.md](../../../docs/testflight.md) for source/CI checks, prepared EN/RU
notes, manual dispatch, receipts and recovery. Ordinary fixes, green CI and PR
approval do not authorize TestFlight; honor explicit release authorization already
present in the session without asking again for the same scope.

Deploy only verified master source. Resume the recorded release after interrupted
processing or upload; never create another build to compensate for an uncertain
result. Report actual version/build, Apple processing, locale read-back and tester
availability separately. Device delivery requires Danis's confirmation.
