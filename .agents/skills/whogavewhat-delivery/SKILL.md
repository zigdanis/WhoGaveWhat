---
name: whogavewhat-delivery
description: Deliver WhoGaveWhat features, fixes, improvements, and explicitly requested TestFlight builds through implementation delegation, independent review, current-head CI visual evidence, autonomous merge, and receipt-backed beta release. Use for action requests in this repository; exclude read-only discussion and plan-only requests.
---

# WhoGaveWhat delivery

Own an authorized implementation-to-TestFlight outcome until it is demonstrated
on the current head and the resulting master build is recorded. Keep the Mac
optional: on Linux or Raspberry Pi, use the PR's macOS CI for native tests,
Simulator capture, screenshots, and video. Read [visual acceptance](../visual-acceptance/SKILL.md)
and [TestFlight operations](../../../docs/testflight.md) before those stages.

## Workflow

1. Inspect the request, repository rules, current branch/PR, and relevant code.
   Define observable acceptance criteria and use the applicable SwiftUI or bug
   diagnosis guidance. Preserve unrelated changes. A plan-only or discussion
   request ends after the requested plan or answer.
2. Delegate bounded implementation to one implementation agent with explicit
   ownership, criteria, and validation. Keep branch, PR, merge, and release
   mutations with the coordinator. Register every worked PR with T3
   `link_pull_request` when available.
3. Obtain a distinct read-only review agent after implementation. The reviewer
   checks concrete correctness, requested behavior, and current visual evidence
   where relevant. Fix every actionable finding through the implementation
   agent, rerun covering checks, and send the result back for re-review.
4. Run repository checks and the full Tests workflow. On Linux/Raspberry Pi,
   retrieve the current-head artifact with `scripts/pr-evidence.sh PR_NUMBER`.
   Inspect selected screenshots and the original video against each criterion;
   extend the CI journey when app smoke does not exercise the changed feature.
   Fix concrete evidence failures on the same PR and refresh evidence after
   every push or rerun.
5. Wait for terminal bot reviews and required checks. Validate each finding,
   fix concrete issues, rerun the covering checks, and re-review. Publish an
   English PR description containing inspected current-head screenshots and
   video using the existing evidence helper; the evidence gate must pass.
6. When the current head is green, independent and bot reviews are terminal,
   no actionable conversation remains, and evidence is current, merge or enable
   auto-merge according to [AGENTS.md](../../../AGENTS.md#merge-and-approval-policy).
   Verify the resulting master commit and its Tests run before release.
7. For an implementation request that includes deployment or full launch,
   dispatch the protected TestFlight workflow from verified master. Use the
   canonical explicit `--repo`, prepared EN/RU notes, and the existing receipt
   helper. Resume the exact receipt after interrupted processing or uncertain
   upload; never create a duplicate build. Report version/build, Apple
   processing, beta review, and tester availability separately.

## Boundaries

Routine implementation-to-TestFlight authorization is standing in this
repository once the request asks to implement and deploy. Do not ask for a
second confirmation at merge or beta-release gates. Stop and report only a
genuine credential, Apple, legal/account, or device-availability blocker, or a
concrete one-way-door action with substantial loss risk. Preserve the manual
`workflow_dispatch` release mechanism; never turn every push into a release.

Native operations use XcodeBuildMCP. The signed Release archive and IPA export
may use Fastlane `gym` under the documented environment gate. Keep generated
artifacts outside the checkout and remove downloaded evidence after inspection.
