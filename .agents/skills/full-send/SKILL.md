---
name: full-send
description: Deliver WhoGaveWhat features, fixes, improvements and new builds through implementation, review, checks, merge and TestFlight. Discussion, plan-only and read-only questions do not start delivery.
---

# Full send

- **Lead:** one coordinating thread runs the workflow for every PR and handles Git, PR, merge and release actions. No nested orchestrator thread per PR. After a sibling PR merges, sync the other open PRs with master immediately.
- **Helpers:** a Sonnet 5.5 (high) implementer in an isolated worktree, an Opus 5.5 (medium) independent reviewer and a `gpt-6.1-sol` (high) second reviewer, as in [AGENTS.md](../../../AGENTS.md#agent-model-selection). They handle only their assigned tasks and do not delegate further. Fold reviewer and bot findings into one fix round per review cycle.

## Authorization and ownership

- **Default:** a feature, fix, improvement or build request authorizes the full path through PR, merge and TestFlight after checks and reviews pass. Don't ask for permission again at any gate.
- **Limits:** `PR-only` stops before merge. `Do-not-deploy` stops before TestFlight. App Store actions need separate approval.
- **Discussion:** loading or discussing this skill, or a plan-only request, does not authorize a release.
- **Verification:** read the [verification policy](references/verification-policy.md) once at the start. Follow its batching, failure-handling and waiting rules throughout.

## Understand the task

- **Understand:** identify the requested change and what a successful result looks like.
- **Continue:** reuse existing task work and its PR when possible. Leave unrelated changes alone.
- **UI:** use `visual-acceptance` for user-visible changes.

## Implement and review

- **Assign:** give the implementer a focused task, expected result and file ownership. If delegation is unavailable, implement it yourself.
- **Implement:** make the requested change, add appropriate tests and run `scripts/check-formatting.sh` and `python3 -m unittest discover -s scripts/tests`. SwiftLint and native tests run in macOS CI when no Mac is available.
- **Review:** have an independent reviewer check correctness against `.macroscope/correctness/correctness.md` and the requested behavior. Fix confirmed issues before pushing.
- **Sync and push:** batch reviewed fixes, fetch `origin/master` and integrate it before pushing. Run relevant local checks on the combined result, then push once. Create or update the PR, register it with `link_pull_request`, and let the automatic CI run.

## Verify and merge

- **Verify:** the `Checks` and `Tests` workflows run automatically on the PR. Retrieve native screenshots and video with `scripts/pr-evidence.sh PR_NUMBER` when needed.
- **Show:** for user-visible changes, attach inspected current-head screenshots and video with `visual-acceptance`. Non-UI changes report functional checks instead.
- **Fix:** address real review issues, test the fixes and reply before resolving comments. Batch them into one push.
- **Watch:** while PR checks or reviews are pending, call T3 Code's `watch_pull_request` and end the turn. Recheck when notified. Don't poll, sleep or run your own watcher.
- **Merge:** when the current head has green checks, independent review is clean and no actionable comment is open, merge. Then confirm the `Tests` run on the merged master commit passed before TestFlight. If that commit skipped `Tests` (docs or agent files only), dispatch `gh workflow run tests.yml --repo zigdanis/WhoGaveWhat --ref master` once while it is still master's head.

## Release and report

- **Reuse:** for a release-only request, use existing verified master instead of inventing changes.
- **Notes:** save plain-text English/Russian JSON with `en` and `ru` in `docs/releases/`, based on user-facing changes since the last shipped source. Separate What's New from What to Test; omit emoji and `<`. See [TestFlight operations](../../../docs/testflight.md#prepared-enru-notes).
- **Release:** run `python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat deploy next MASTER_SHA NOTES_JSON` for the verified merge commit. Keep the run ID, receipt and version/build. Use `preflight` only for setup or diagnosis; deployment already checks signing.
- **Resume:** use `status RUN_ID` or `resume RUN_ID` for an interrupted release, never a duplicate upload. Use `notes RUN_ID NOTES_JSON` for text-only corrections.
- **Wait:** Apple processing and beta review are normal waiting states. Report them; don't upload again.
- **Report:** share the PR, version/build, checks, CI attempts and actual release status. Call `unwatch_pull_request` before handing back. Device-only checks, such as Spotlight search on the phone, are requested after release, not gates before it.
