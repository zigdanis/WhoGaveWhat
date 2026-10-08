# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General notes

- Always start every reply by addressing me by name: "Danis, ..." or "Данис, ...".
- For feature, fix, improvement, and requested build work, always read and apply [.agents/skills/whogavewhat-delivery/SKILL.md](.agents/skills/whogavewhat-delivery/SKILL.md). It is the default delivery workflow: delegate implementation, obtain a distinct read-only review, fix concrete review and bot findings with re-review, validate native behavior through macOS CI, inspect current screenshots and video, publish both in the PR, merge when all gates pass, then deliver the verified master source to TestFlight. Routine feature and fix requests include this full beta path by default. Discussion and plan-only requests opt out; PR-only stops at a clean reviewed PR, and do-not-deploy stops after authorized merge and master CI.
- Use [.agents/skills/multi-agent-feature-pr/SKILL.md](.agents/skills/multi-agent-feature-pr/SKILL.md) as the feature-PR routing entry point; it hands routine work to `whogavewhat-delivery` and adds no separate human approval or HTML-plan gate.
- if iPhone simulator is already launched - use it instead of launching a new one.
- Prefer using iPhone 17 Pro simulator otherwise.
- Always use English when filling in PRs and comments on GitHub. Nothing should be in the Russian language when facing GitHub (commit messages, coments, PR titles, descriptions, etc.)
- After UI changes, agent have to walk down the modified scenario, take a snapshot, and visually verify it.

## Subagent model budget

- Keep every subagent at or below the primary thread's model rank. Default to the primary thread model or a cheaper one.
- Use any Astra or Sol family model only when Danis explicitly authorizes it, including `gpt-6-astra`, `gpt-6-sol`, `gpt-6.1-sol`, and `gpt-5.6-sol`.
- If a skill or workflow would select Astra, Sol, or any model above the primary thread, ask Danis early with one concise question. Continue useful work using the primary model or a cheaper one while waiting; if Danis does not reply, do not escalate.
- Check a subagent role's actual model mapping. A role name such as `reviewer` is not approval to use its mapped model; choose a suitable role at or below the primary thread rank.
- Explicit authorization is required before using any Astra or Sol family model. Authorization never overrides the primary-thread model ceiling: use only the primary-thread model or a cheaper model.

# Xcode and Simulator execution

- Use the `xcodebuildmcp` CLI for all project discovery, build, test, install, launch, Simulator management, logging, debugging, accessibility inspection, UI automation, and screenshots.
- TestFlight release exception: use Fastlane `gym` for the signed Release archive and IPA export, as authorized by Danis. All other native operations, including tests and Simulator evidence, continue through `xcodebuildmcp`.

# Code review

- Before reviewing changes, read and apply `.macroscope/correctness/correctness.md`. It is the shared review policy for Codex, CodeRabbit, and Macroscope.
- Report only concrete, actionable problems introduced by the change. Do not repeat formatter or linter findings, demand speculative abstractions, or invent findings when no shared rule applies.
- When asked to babysit a pull request, use the `babysit-pr` skill when available. Validate each bot finding before changing code, use bounded subagents when useful, run the checks that cover each fix, push only to the pull request branch, and reply with evidence before resolving a review thread.
- After every push, re-check the latest head commit, required checks, new reviews, and unresolved conversations. Continue until the current head is green, reviewers have reached a terminal state, and no actionable thread remains.
- Merge or enable auto-merge autonomously once the latest PR head has green required checks, completed independent and bot reviews with no actionable findings or unresolved conversations, and current inspected visual evidence where applicable. Recheck the head before merging and verify the resulting master commit and its CI before deployment.

# Merge and approval policy

- Ask for approval only for a concrete one-way-door action: an irreversible or hard-to-reverse change, or one that could cause substantial losses. Complete the independent, reviewable preparation first. Routine reversible changes and TestFlight beta updates do not need another confirmation.
- TestFlight follows the source, CI, evidence, and receipt gates in [docs/testflight.md](docs/testflight.md). Routine feature and fix requests authorize the merge and TestFlight beta path; PR-only stops before merge and release, while do-not-deploy stops before release. Do not ask again at each gate. Genuine Apple, credential, legal, or account blockers remain reportable blockers. Device-only confirmation is a post-release state, and local Mac access is optional because CI is the native verification path.

# Quality and PR evidence

- Before handing over any PR, follow [PR evidence](docs/pr-evidence.md) for current-head inspection and compact screenshot and video attachments, including documentation and infrastructure PRs. App smoke verifies the environment; UI changes also require the changed scenario.
- Run `scripts/check-formatting.sh`, `scripts/lint-swift.sh` and the helper tests before pushing. Use `scripts/format-swift.sh` to fix layout; SwiftLint owns source correctness rules.
- On Raspberry Pi, use [the CI evidence workflow](docs/pr-evidence.md#raspberry-pi) for native app validation and visual review. A local Mac is optional convenience, not a dependency.
