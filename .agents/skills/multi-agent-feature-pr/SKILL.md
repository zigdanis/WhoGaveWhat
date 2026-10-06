---
name: multi-agent-feature-pr
description: Work on a feature in a repository through a planning subagent, an implementation subagent, an independent review subagent, and a monitored GitHub pull request. Use when user asks for a feature to implement.
---

# Multi-Agent Feature PR

## Authorization boundary

Invoking this skill with a concrete implementation request authorizes fetching the remote base, creating a dedicated branch, editing and testing in-scope files, committing, pushing, opening a ready-for-review PR, and responding to review feedback on that PR. It does not authorize merging the PR, changing unrelated systems, or destructive operations outside the requested scope.

## Required workflow

### 1. Isolate the branch

1. Fetch `origin/master` before creating the feature branch.
2. Start a descriptively named branch from the fetched `origin/master` if nothing else specified by user. If the current worktree is dirty, isolate the task with a separate Git worktree or stop if safe isolation is impossible.

### 2. Plan with a dedicated subagent

1. Spawn one planning subagent first.
2. Require a concrete plan.
3. Wait for the planner before implementation begins.
4. Read the `html-plan` skill completely, turn the approved plan into a self-contained `<topic>-plan.html` in the repository, and immediately give Danis a clickable link. The plan must be readable while later stages continue.

### 3. Implement with a separate subagent

1. Spawn one implementation subagent with the user's original request plus the approved plan.
2. Let the implementer do a dedicated draft PR, set of reasonably short commits that build up step by step to make this feature complete.
3. Keep pushing commits to remote while implementer working on them.
4. The main agent remains responsible for progress updates and final Git/GitHub actions.

### 4. Review independently

1. After implementation stops, spawn one review subagent that did not implement the change.
2. Keep the first review read-only.
3. Send blocking findings back to the original implementation subagent with `followup_task` instead of spawning replacement implementers.
4. Make every findings corrected by implementer subagent to be committed individually. Don't make one, big, all-inclusve commit that holds everything. If some cases naturally fits under single commit - combine those.
5. Send the corrected worktree back to the original reviewer. Repeat implementer/reviewer follow-ups until the reviewer reports no blockers.
6. The main agent performs its own focused diff inspection and closes small, well-understood coverage or documentation gaps before commit.

### 5. Watch until green

1. Monitor required checks, PR reviews, issue comments, and inline review comments. Do not stop after merely opening the PR.
2. While waiting, provide concise status updates at meaningful transitions and at least once per minute during a long active wait.
3. When CI fails, inspect the failing job logs, apply an in-scope fix through the implementation subagent, re-run focused verification, obtain review again when the fix is material, commit, push, and resume monitoring.
4. When an actionable review comment appears, fix it or respond in English with concrete evidence when no code change is appropriate. Re-check unresolved conversations afterward.
5. Read [the PR evidence workflow](../../../docs/pr-evidence.md) for every PR, including documentation and infrastructure changes. After each final push or CI rerun, retrieve the latest current-head artifacts, inspect the selected screenshots and recording, and publish both in the description. UI changes require the changed scenario; app smoke alone covers environment checks. Recheck the validator after publication. Completion requires embedded current-head screenshots AND video, passing checks, a mergeable PR and no actionable review feedback.
6. Convert the completed draft to ready for review only after these conditions hold. Keep merging with Danis.

Do not merge unless Danis explicitly asks.

## Final handoff

Report the PR link, branch, final commit, check status, review status, key design outcome, and any verification that genuinely remains impossible. Include the local HTML plan link.
