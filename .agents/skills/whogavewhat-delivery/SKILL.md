---
name: whogavewhat-delivery
description: Deliver WhoGaveWhat features, fixes, improvements, and build work through implementation delegation, independent review, current-head CI visual evidence, autonomous merge, and receipt-backed TestFlight release. Use automatically for action requests; exclude read-only discussion and plan-only requests.
---

# WhoGaveWhat delivery

Own an authorized implementation-to-TestFlight outcome until it is demonstrated
on the current head and the resulting master build is recorded. Keep the Mac
optional: on Linux or Raspberry Pi, use the PR's macOS CI for native tests,
Simulator capture, screenshots, and video. Read [visual acceptance](../visual-acceptance/SKILL.md)
and [TestFlight operations](../../../docs/testflight.md) before those stages.

## Workflow

Before delegating implementation or review, follow
[agent model selection](../../../AGENTS.md#agent-model-selection).

1. Inspect the request, repository rules, current branch/PR, and relevant code.
   Define observable acceptance criteria and use the applicable SwiftUI or bug
   diagnosis guidance. Preserve unrelated changes. A read-only discussion or
   plan-only request ends after the requested answer or plan. A PR-only limit
   still runs implementation, review, CI, and media, then stops at a clean PR
   handoff. A do-not-deploy limit still permits an authorized merge and master
   CI, then stops before TestFlight.
2. Delegate bounded implementation to one implementation agent with explicit
   ownership, criteria, and validation. Keep branch, PR, merge, and release
   mutations with the coordinator. Register every worked PR with T3
   `link_pull_request` when available.
3. Obtain a distinct read-only review agent after implementation. The reviewer
   checks concrete correctness and requested behavior. Wait for terminal bot
   reviews, batch every actionable fix, rerun covering lightweight checks, and
   obtain re-review. Ensure the native journey covers the changed scenario
   before scheduling native CI.
4. Follow the [native CI budget](../../../docs/pr-evidence.md#native-ci-budget).
   Once the head is ready and reviews are terminal, apply `ci-ready` to run the
   complete PR Tests suite once. The label schedules acceptance; merge and
   release still require every gate. On Linux/Raspberry Pi,
   retrieve the current-head artifact with `scripts/pr-evidence.sh PR_NUMBER`.
   Inspect selected screenshots and the original video against each criterion.
   Obtain independent review of the inspected evidence. A later source fix
   requires current-head evidence and an explicit budget exception before
   another full run.
5. Confirm terminal independent and bot reviews and passing required checks.
   Publish an English PR description containing inspected current-head
   screenshots and video using the existing evidence helper; the evidence gate
   must pass.
6. When the current head is green, independent and bot reviews are terminal,
   no actionable conversation remains, and evidence is current, merge or enable
   auto-merge according to [AGENTS.md](../../../AGENTS.md#merge-and-approval-policy),
   unless the user explicitly requested PR-only.
   Dispatch the complete Tests workflow once on the resulting master commit
   and verify that exact source before release.
7. For a routine feature, fix, improvement, or build request, dispatch the
   protected TestFlight workflow from verified master unless the user explicitly
   requested PR-only or do-not-deploy. Use the
   canonical explicit `--repo`, prepared EN/RU notes, and the existing receipt
   helper. Resume the exact receipt after interrupted processing or uncertain
   upload; never create a duplicate build. Report version/build, Apple
   processing, beta review, and tester availability separately.

## Boundaries

Routine implementation-to-TestFlight authorization is standing in this
repository for every feature, fix, improvement, and build request. Explicit
discussion and plan-only requests opt out of delivery; PR-only stops after a
clean reviewed PR, and do-not-deploy stops after an authorized merge and master
CI. Do not ask for a second confirmation at merge or beta-release gates. Stop and report only a
genuine credential, Apple, or legal/account blocker, or a concrete one-way-door
action with substantial loss risk. Preserve the manual `workflow_dispatch`
release mechanism; never turn every push into a release. Local Mac access is
optional because CI provides native verification.

Follow the native execution policy in [AGENTS.md](../../../AGENTS.md#xcode-and-simulator-execution):
local and CI operations use direct Apple tools, with CI driven through the
evidence runner. XcodeBuildMCP is optional for specific capabilities. The signed Release archive and IPA export
may use Fastlane `gym` under the documented environment gate. Keep generated
artifacts outside the checkout and remove downloaded evidence after inspection.
