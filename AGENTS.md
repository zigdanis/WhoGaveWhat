# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General rules

- To monitor or babysit a pull request, call T3 Code's `watch_pull_request` and end the turn; it wakes the thread on failed or passing checks, new comments and conflicts. Validate each bot finding before changing code, batch fixes into one push, and reply with evidence before resolving a review thread. Call `unwatch_pull_request` when handing back.
- To read live analytics, use `scripts/posthog-cli.sh` (PostHog, credentials in `~/.config/posthog/whogavewhat.env`) and the `sentry` CLI with the `sentry-cli` skill (Sentry, `sentry auth` once per machine); `docs/analytics.md` → "Checking live data" has the setup.
- Simulators: every simulator run, test, capture or Device panel follows the Fleet `simulator-queue` skill (`~/myai/fleet/skills/simulator-queue/SKILL.md`), which is shared by all projects: which device, how to reach MacPro from Linux, the queue, the cloud fallback and cleanup. `scripts/simulator-app.sh [PR_NUMBER]` prints the path of the Debug `.app` that the `Tests` run of a PR head (or of master, without an argument) built and tested.

# CI and pushing

GitHub's free plan runs about five macOS jobs at once for all PRs together, so every needless macOS run makes someone wait. Minutes cost nothing; waiting does.

- **What runs by itself:** `Checks` (Linux, every PR and master push: script tests, secret patterns, Icon Worker) and `Tests` (one macOS job, 7–12 minutes; skipped when only docs, agent files or `icon-worker/` change): Swift format and lint, one Debug build, the unit suite, and the tested app kept as the `simulator-app` artifact. Nothing else starts on its own.
- **Only on request:** TestFlight (`scripts/testflight.py`) and `App Store metadata` are dispatched by hand. App Store screenshots are never shot in CI, only on MacPro (`app-store-screenshots` skill). Dispatch `Tests` by hand only for a master head that skipped it, or for a branch that needs a `simulator-app` and has no run.
- **Push a batch, not a commit.** Commit locally as often as you like, but push only when the change is implemented, reviewed, master is merged in and the local checks below pass. Fold review and bot findings into one push. Each push to a PR cancels its running `Tests` and starts it again, even a docs-only commit: the path filter looks at the whole PR diff, not at the pushed commit.
- **A PR that must open before it is ready** (draft for review or screenshots): put `[skip ci]` in the pushed head commit's message. The last push, without it, runs CI once for the final head. A draft PR without `[skip ci]` still runs everything.
- **Never** rerun a green run for an unchanged commit, push to "see if CI passes", or push again only to trigger a rerun of an unrelated flake; use "Re-run failed jobs" once and diagnose a repeat.
- **Local checks before a push:** on any machine `scripts/check-formatting.sh`, `scripts/check-secrets.sh` and `python3 -m unittest discover -s scripts/tests`; for `icon-worker/`, `npx tsc --noEmit && npx vitest run` there. For Swift changes, when MacPro answers, compile there over `ssh macpro.remote` (`xcodebuild build-for-testing -scheme WhoGaveWhat -destination 'generic/platform=iOS Simulator'` in a checkout of your branch, plus `scripts/lint-swift.sh`); a build needs no simulator slot. Run unit tests on MacPro only while fixing a failing test, with `-only-testing` for the touched classes and through the `simulator-queue` queue; the full suite runs once in CI on the final push.

<posthog>
## PostHog

Use `posthog-cli api` for all PostHog-related data queries and operations. You should use `posthog-cli api` over direct MCP tool calls whenever the CLI is available.

Before your first PostHog command in a session, run `posthog-cli api --agent-help` and load its full output into your context. It prints the complete agent guide — command reference, schema drill-down rules, data discovery workflow, and the tool index — for interacting with PostHog APIs. Treat that output as instructions to follow, not just documentation.

Before starting a PostHog task, run `posthog-cli api skill list` and check for a skill matching the task. If one matches, install it with `posthog-cli api skill install <skill-id>` (add `--force` to refresh an already-installed skill), then read `.agents/skills/<skill-id>/SKILL.md` and follow it. Skills contain task-specific workflows that individual tools do not.
</posthog>
