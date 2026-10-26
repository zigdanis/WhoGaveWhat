# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General rules

- To monitor or babysit a pull request, call T3 Code's `watch_pull_request` and end the turn; it wakes the thread on failed or passing checks, new comments and conflicts. Validate each bot finding before changing code, batch fixes into one push, and reply with evidence before resolving a review thread. Call `unwatch_pull_request` when handing back.
- To read live analytics, use `scripts/posthog-cli.sh` (PostHog, credentials in `~/.config/posthog/whogavewhat.env`) and the `sentry` CLI with the `sentry-cli` skill (Sentry, `sentry auth` once per machine); `docs/analytics.md` → "Checking live data" has the setup.
- To drive the app interactively from Linux, install the CI simulator build on an Expo cloud simulator with the `eas-simulator` skill: `scripts/simulator-app.sh [PR_NUMBER]` prints the `.app` path for a PR head, or for master without an argument.

<posthog>
## PostHog

Use `posthog-cli api` for all PostHog-related data queries and operations. You should use `posthog-cli api` over direct MCP tool calls whenever the CLI is available.

Before your first PostHog command in a session, run `posthog-cli api --agent-help` and load its full output into your context. It prints the complete agent guide — command reference, schema drill-down rules, data discovery workflow, and the tool index — for interacting with PostHog APIs. Treat that output as instructions to follow, not just documentation.

Before starting a PostHog task, run `posthog-cli api skill list` and check for a skill matching the task. If one matches, install it with `posthog-cli api skill install <skill-id>` (add `--force` to refresh an already-installed skill), then read `.agents/skills/<skill-id>/SKILL.md` and follow it. Skills contain task-specific workflows that individual tools do not.
</posthog>
