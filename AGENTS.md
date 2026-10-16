# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General notes

- Always start every reply by addressing me by name: "Danis, ..." or "Данис, ...".
- For feature, fix, improvement, and build requests, read and apply [.agents/skills/full-send/SKILL.md](.agents/skills/full-send/SKILL.md). It runs implementation, independent review, CI, merge and TestFlight without further confirmation. Discussion and plan-only requests opt out; PR-only stops before merge, and do-not-deploy stops before TestFlight.
- if iPhone simulator is already launched - use it instead of launching a new one.
- Prefer using iPhone 17 Pro simulator otherwise.
- Always use English when filling in PRs and comments on GitHub. Nothing should be in the Russian language when facing GitHub (commit messages, coments, PR titles, descriptions, etc.)
- After UI changes, agent have to walk down the modified scenario, take a snapshot, and visually verify it.

## Agent model selection

- One coordinating thread runs the whole delivery and owns Git, PR, merge and release actions. Don't launch nested orchestrator threads per PR.
- Implementers: Sonnet 5.5 at high effort by default, each in an isolated worktree.
- Reviewers: Opus 5.5 at medium effort as the independent reviewer or a bounded advisor (not an open-ended or xhigh implementer), and `gpt-6.1-sol` at high effort as the second reviewer.
- `gpt-6.1-sol` remains authorized by Danis for any work, including implementation and review, and needs no additional permission.
- Run one combined fix round per review cycle: reviewer and bot findings go into a single push. When a sibling PR merges, merge master into the other open PRs right away so one CI run validates both.
- Use Luna only when Danis explicitly requests it.
- Check the actual provider/model mapping before delegating; role names do not select the model.
- Keep subagents at or below the primary thread's model rank. If a chosen model exceeds that ceiling or is unavailable, continue in the primary thread and report the limitation instead of silently substituting Luna.
- Independent review remains required. If a distinct eligible reviewer is unavailable, finish reviewable preparation and stop before merge or deployment until independent review can be completed.

# Xcode and Simulator execution

- Use direct Apple tools by default for local and CI native work: `xcodebuild`, `xcrun simctl`, `xcresulttool`, XCTest/XCUITest, and LLDB as appropriate. Discover supported arguments through the installed tools' help.
- CI uses direct Apple tools through `scripts/run-app-smoke.py`: `xcodebuild` for native tests, `simctl` for Simulator readiness and requested clips, and `xcresulttool` for screenshot export. Preserve bounded timeouts, failure diagnostics, and current-head screenshot evidence.
- TestFlight release exception: use Fastlane `gym` for the signed Release archive and IPA export, as authorized by Danis.
- XcodeBuildMCP is optional when a task needs a specific capability it provides. Ordinary build, test, Simulator, and evidence work requires no MCP installation, configuration, or daemon.

# Code review

- Before reviewing changes, read and apply `.macroscope/correctness/correctness.md`. It is the shared review policy for Codex, CodeRabbit, and Macroscope.
- Report only concrete, actionable problems introduced by the change. Do not repeat formatter or linter findings, demand speculative abstractions, or invent findings when no shared rule applies.
- To monitor or babysit a pull request, call T3 Code's `watch_pull_request` and end the turn; it wakes the thread on failed or passing checks, new comments and conflicts. Validate each bot finding before changing code, batch fixes into one push, and reply with evidence before resolving a review thread. Call `unwatch_pull_request` when handing back.
- Merge autonomously once the latest PR head has green checks, a clean independent review and no actionable conversation, plus inspected visual evidence for user-visible changes. Verify the resulting master commit's `Tests` run before deployment.

# Merge and approval policy

- Ask for approval only for a concrete one-way-door action: an irreversible or hard-to-reverse change, or one that could cause substantial losses. Complete the independent, reviewable preparation first. Routine reversible changes and TestFlight beta updates do not need another confirmation.
- TestFlight follows the receipt-based release in [docs/testflight.md](docs/testflight.md). Do not ask again at each gate. Genuine Apple, credential, legal, or account blockers remain reportable blockers. Device-only confirmation is a post-release state, and local Mac access is optional because CI is the native verification path.

# Quality and PR evidence

- Follow the [verification policy](.agents/skills/full-send/references/verification-policy.md): batch fixes before each push, reuse the automatic CI run, and classify failures before correcting them.
- A `Tests` failure matching a [known CI flake](.agents/skills/full-send/references/verification-policy.md#known-ci-flakes) in a flow the diff does not touch gets one `gh run rerun RUN_ID --failed`; anything else is classified and fixed.
- Spotlight retrieval in the Simulator is an optional diagnostic; app-owned Spotlight metadata and routing tests are required, and Spotlight search is confirmed on Danis's device after TestFlight.
- For user-visible changes, attach inspected current-head screenshots using [PR evidence](docs/pr-evidence.md); add a video clip only when Danis asks to review the flow manually or motion can't be shown in stills. Documentation, tooling and other non-UI changes report functional checks instead.
- Run `scripts/check-formatting.sh`, `scripts/lint-swift.sh` (when a Mac is available; otherwise macOS CI runs it) and the helper tests before pushing. Use `scripts/format-swift.sh` to fix layout; SwiftLint owns source correctness rules. Without a Swift toolchain, both install CI's pinned swift-format into the user cache on first run (`scripts/ensure-swift-format.sh`).
- On Raspberry Pi, use [the CI evidence workflow](docs/pr-evidence.md#raspberry-pi) for native app validation and visual review. A local Mac is optional convenience, not a dependency.
