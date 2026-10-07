---
name: future-work-plan-pr
description: Turn a raw idea for future work in this repository into a detailed HTML plan and publish only that plan as a draft GitHub PR. Use when Danis wants to capture an idea as a backlog note, reminder, or plan for later implementation. Do not use when he asks to implement the work now.
---

# Future Work Plan PR

Convert user's prompt into a durable, implementation-free draft PR. 
The PR is the backlog artifact: it records enough context and decisions for the work to be resumed later without beginning the implementation.

## Required workflow

1. Read the `html-plan` skill completely and follow it when creating the plan.
2. Inspect the repository, relevant source, existing documentation, Git state, remotes, and open PRs as needed. Investigation must be read-only.
3. Expand the raw idea into a concrete plan. Make reasonable low-risk assumptions, label uncertainty, and record genuinely consequential open questions rather than blocking on minor details.
4. Create one self-contained HTML plan in the repository. Give it a descriptive kebab-case name ending in `-plan.html`.
5. Create a dedicated branch from the current `origin/master`, named `codex/plan-<short-kebab-case-topic>`. Never mix existing working-tree changes into the branch. If the current checkout is dirty, isolate the work with a separate Git worktree or stop if safe isolation is not possible.
6. Commit only the HTML plan. Use an English commit message such as `Add <topic> implementation plan`.
7. Push the dedicated branch and create a draft PR against `master`.
8. Verify the published PR and report its URL, draft state, base/head branches, and changed files.

Invoking this skill with a concrete idea authorizes creating the plan artifact, branch, commit, push, and draft PR. It never authorizes product implementation, merging the PR, or changing unrelated files.