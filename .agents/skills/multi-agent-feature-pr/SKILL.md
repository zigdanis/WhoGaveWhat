---
name: multi-agent-feature-pr
description: Route WhoGaveWhat feature requests to the repository's autonomous delivery workflow with an implementation agent, independent review, monitored PR, visual evidence, merge, and TestFlight release. Use for action requests; exclude read-only discussion and plan-only work.
---

# Multi-Agent Feature PR

For this repository, [whogavewhat-delivery](../whogavewhat-delivery/SKILL.md) is
authoritative. Read and apply it for routine feature work; it owns the complete
implementation, review, CI evidence, bot convergence, merge, and authorized
TestFlight path. This skill preserves the useful delegation shape but does not
add a separate HTML-plan or human-approval gate.

## Authorization boundary

Invoking this skill with a concrete implementation request authorizes the
normal repository delivery workflow, including merge and TestFlight by default.
Explicit discussion and plan-only requests opt out. PR-only stops after a clean
reviewed PR without merge or release; do-not-deploy completes authorized merge
and master CI while skipping TestFlight.
One-way-door changes and genuine account or Apple blockers still follow
[AGENTS.md](../../../AGENTS.md#merge-and-approval-policy).

### Agent model selection

Before each delegation, follow
[agent model selection](../../../AGENTS.md#agent-model-selection).

## Required workflow

### 1. Isolate the branch

1. Fetch `origin/master` before creating the feature branch.
2. Start a descriptively named branch from the fetched `origin/master` if nothing else specified by user. If the current worktree is dirty, isolate the task with a separate Git worktree or stop if safe isolation is impossible.

### 2. Delegate implementation

1. Delegate bounded implementation to one implementation agent with acceptance
   criteria and exclusive ownership. Use a plan only when the request asks for
   one or when the scope genuinely needs it.
2. Keep branch, PR, merge, and release mutations with the coordinator.

### 3. Review independently

1. After implementation stops, spawn one review subagent that did not implement the change.
2. Keep the first review read-only.
3. Send blocking findings back to the original implementation subagent with `followup_task` instead of spawning replacement implementers.
4. Have the implementation agent correct every finding and commit the fixes in
   focused commits; combine only findings that naturally belong together.
5. Send the corrected worktree back to the original reviewer. Repeat implementer/reviewer follow-ups until the reviewer reports no blockers.
6. The main agent performs its own focused diff inspection and closes small, well-understood coverage or documentation gaps before commit.

### 4. Watch until green

1. Monitor required checks, PR reviews, issue comments, and inline review comments. Do not stop after merely opening the PR.
2. While waiting, provide concise status updates at meaningful transitions and at least once per minute during a long active wait.
3. When CI fails, inspect the failing job logs, apply an in-scope fix through the implementation subagent, re-run focused verification, obtain review again when the fix is material, commit, push, and resume monitoring.
4. When an actionable review comment appears, fix it or respond in English with concrete evidence when no code change is appropriate. Re-check unresolved conversations afterward.
5. Read [the PR evidence workflow](../../../docs/pr-evidence.md) for every PR, including documentation and infrastructure changes. After each final push or CI rerun, retrieve the latest current-head artifacts, inspect the selected screenshots and recording, and publish both in the description. UI changes require the changed scenario; app smoke alone covers environment checks. Recheck the validator after publication. Completion requires embedded current-head screenshots AND video, passing checks, a mergeable PR and no actionable review feedback.
6. Convert the completed draft to ready for review only after these conditions hold. Follow `whogavewhat-delivery` for autonomous merge and authorized TestFlight release.

## Final handoff

Report the PR link, branch, final commit, check status, review status, key design outcome, release receipt, and any verification that genuinely remains impossible.
