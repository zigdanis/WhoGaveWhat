---
name: multi-agent-feature-pr
description: Deliver a substantial repository change through a planning subagent, an implementation subagent, an independent review subagent, and a monitored GitHub pull request. Use when Danis asks for an end-to-end feature or refactor with delegated implementation and a green PR. Do not use for plan-only backlog notes, reviews without implementation, or small direct edits.
---

# Multi-Agent Feature PR

Orchestrate the requested repository change from current base branch through an independently reviewed, green pull request. Preserve every product and technical constraint in the user's prompt; delegation must not dilute or reinterpret those requirements.

## Authorization boundary

Invoking this skill with a concrete implementation request authorizes fetching the remote base, creating a dedicated branch, editing and testing in-scope files, committing, pushing, opening a ready-for-review PR, and responding to review feedback on that PR. It does not authorize merging the PR, changing unrelated systems, or destructive operations outside the requested scope.

## Required workflow

### 1. Isolate the branch

1. Read the repository's applicable `AGENTS.md` instructions and any task-specific skills before acting.
2. Inspect the worktree and remotes. Preserve user-owned changes.
3. Fetch `origin/master` before creating the feature branch.
4. Start a descriptively named branch from the fetched `origin/master`. If the current worktree is dirty, isolate the task with a separate Git worktree or stop if safe isolation is impossible.

### 2. Plan with a dedicated subagent

1. Spawn one planning subagent first. Give it the user's complete requirements and instruct it to inspect the repository read-only.
2. Require a concrete plan covering the proposed architecture/model, file-level changes, risks, tests, verification, and explicit non-goals.
3. Wait for the planner before implementation begins.
4. Read the `html-plan` skill completely, turn the approved plan into a self-contained `<topic>-plan.html` in the repository, and immediately give Danis a clickable link. The plan must be readable while later stages continue.

### 3. Implement with a separate subagent

1. Spawn one implementation subagent with the user's original request plus the approved plan.
2. Let the implementer own the in-scope code, tests, and documentation changes in the shared worktree. Tell it not to commit, push, or open the PR.
3. Require the implementer to run every locally available relevant verification and clearly report environment-limited checks.
4. The main agent remains responsible for progress updates, scope control, and final Git/GitHub actions.

### 4. Review independently

1. After implementation stops, spawn one review subagent that did not implement the change.
2. Keep the first review read-only. Require severity-ordered findings with exact file/line references, actionable fixes, and verification gaps.
3. Treat correctness, data integrity, concurrency, persistence/schema behavior, failure atomicity, tests, and the user's explicit constraints as blocking when applicable.
4. Send blocking findings back to the original implementation subagent with `followup_task` instead of spawning replacement implementers.
5. Send the corrected worktree back to the original reviewer. Repeat implementer/reviewer follow-ups until the reviewer reports no blockers.
6. The main agent performs its own focused diff inspection and closes small, well-understood coverage or documentation gaps before commit.

### 5. Verify and publish

1. Run repository-mandated build/test tools and static hygiene checks. For this iOS repository, all Xcode and Simulator work must go through the `xcodebuildmcp` CLI skill.
2. If UI behavior changed, walk the modified scenario on an already-running compatible Simulator or the preferred iPhone 17 Pro, capture an accessibility snapshot and screenshot, and inspect them. Never claim visual verification when the environment cannot provide it.
3. Commit only the scoped implementation and its HTML plan with an English commit message.
4. Push the feature branch and create a non-draft PR against `master`. The English PR description must summarize the design, explicit exclusions, and verification evidence, including any local environment limitation.

### 6. Watch until green

1. Monitor required checks, PR reviews, issue comments, and inline review comments. Do not stop after merely opening the PR.
2. While waiting, provide concise status updates at meaningful transitions and at least once per minute during a long active wait.
3. When CI fails, inspect the failing job logs, apply an in-scope fix through the implementation subagent, re-run focused verification, obtain review again when the fix is material, commit, push, and resume monitoring.
4. When an actionable review comment appears, fix it or respond in English with concrete evidence when no code change is appropriate. Re-check unresolved conversations afterward.
5. Finish only when all required checks succeed, the PR is mergeable, and no actionable bot or human review feedback remains unresolved.

Do not merge unless Danis explicitly asks.

## Final handoff

Report the PR link, branch, final commit, check status, review status, key design outcome, and any verification that genuinely remains impossible. Include the local HTML plan link.
