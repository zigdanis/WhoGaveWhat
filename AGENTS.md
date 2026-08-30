# General notes

- Always start every reply by addressing me by name: "Danis, ..." or "Данис, ...".
- if iPhone simulator is already launched - use it instead of launching a new one.
- Prefer using iPhone 17 Pro simulator
- Always use English when filling in PRs and comments on GitHub. Nothing should be in the Russian language when facing GitHub (commit messages, coments, PR titles, descriptions, etc.)
- After UI changes, agent have to walk down the modified scenario, take a snapshot, and visually verify it.

# Xcode and Simulator execution

- Use the `xcodebuildmcp` CLI for all project discovery, build, test, install, launch, Simulator management, logging, debugging, accessibility inspection, UI automation, and screenshots.
- Read `.agents/skills/xcodebuildmcp-cli/SKILL.md` before using the CLI. Follow help-first discovery with `xcodebuildmcp --help` and command-specific `--help`; do not guess flags.
- Do not configure or call XcodeBuildMCP as an MCP server.
- Do not silently use raw `xcodebuild`, `xcrun`, or `simctl` for these operations. If XcodeBuildMCP is broken or lacks a required capability, report the exact command and limitation to Danis before adopting another route.
- The project pins XcodeBuildMCP `2.7.0`. Never install or invoke `xcodebuildmcp@latest`. Follow `docs/xcodebuildmcp.md` for installation and upgrades.
- Reuse an already-running compatible iPhone Simulator. Prefer iPhone 17 Pro and keep the same Simulator UDID for the whole task.
- Prefer `simulator build-and-run` for launch intent. Use structured JSON or JSONL output when supported.
- Before UI interaction, capture a fresh accessibility snapshot and target its stable `elementRef`, accessibility identifier, or label. Refresh the snapshot after navigation, scrolling, sheet changes, or visible layout changes. Use coordinates only as an explained last resort.
- After UI-affecting changes, walk the complete modified scenario, inspect the final accessibility state, capture a screenshot, open it, and explicitly verify state, spacing, clipping, overlap, contrast, and readability.
- Before reporting success, state the project, scheme, Simulator name/UDID, exact test result, scenario walked, accessibility evidence, screenshot path, visual verdict, and whether any fallback was used.
- Keep screenshots, logs, DerivedData, and machine-specific output outside tracked source paths unless the task explicitly requests committed artifacts.

# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project
