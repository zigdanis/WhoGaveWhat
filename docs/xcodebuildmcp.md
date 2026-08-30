# XcodeBuildMCP CLI

WhoGaveWhat uses the XcodeBuildMCP CLI as its only agent-facing Xcode execution path. Do not configure XcodeBuildMCP as an MCP server.

## Installed version

- Package: `xcodebuildmcp@2.7.0`
- Installation: `npm install --global xcodebuildmcp@2.7.0`
- Expected executable: `xcodebuildmcp` on `PATH`
- Current machine path: `/opt/homebrew/bin/xcodebuildmcp`
- npm global prefix: `/opt/homebrew`

The executable is machine-level and is not committed. Verify a machine with:

```bash
command -v xcodebuildmcp
xcodebuildmcp --version
xcodebuildmcp tools --json
```

Version `2.7.0` does not provide a `doctor` command. Validate the integration through the checks above, config-backed discovery, and real build/test/Simulator operations.

## Project files

- `.xcodebuildmcp/config.yaml` stores the project, scheme, iPhone 17 Pro preference, and telemetry opt-out.
- `.agents/skills/xcodebuildmcp-cli/SKILL.md` is the only Xcode execution skill.
- `AGENTS.md` defines the mandatory route and verification evidence.

The CLI skill was installed from `getsentry/XcodeBuildMCP`, tag `v2.7.0`, path `skills/xcodebuildmcp-cli`. The unmodified upstream `SKILL.md` SHA-256 is `afeaf4d088fd79760bb6c80ccf9b5e23e1587587d0c8a135d4b4427fc869a0b1`. The local copy changes only the installation guidance so it enforces this project's exact npm version instead of offering unpinned installation choices.

## Help-first workflow

Do not memorize or guess flags. Start with:

```bash
xcodebuildmcp --help
xcodebuildmcp tools --json
xcodebuildmcp <workflow> --help
xcodebuildmcp <workflow> <tool> --help
```

Use structured output when the command supports it:

```bash
xcodebuildmcp simulator list --output json
xcodebuildmcp simulator build-and-run --output json
xcodebuildmcp simulator test --output json
xcodebuildmcp ui-automation snapshot-ui --output json
xcodebuildmcp ui-automation screenshot --return-format path --output json
```

The project config supplies the project, scheme, and preferred Simulator name. If a compatible iPhone Simulator is already booted, use its UDID explicitly for the whole task instead of booting another Simulator.

For UI interaction, obtain a fresh snapshot first, use the returned `elementRef`, and refresh after navigation or a layout change:

```bash
xcodebuildmcp ui-automation snapshot-ui --simulator-id <udid> --output json
xcodebuildmcp ui-automation tap --simulator-id <udid> --element-ref <ref> --output json
```

## Visual verification

After UI-affecting changes:

1. Build and run through XcodeBuildMCP CLI.
2. Walk the complete modified scenario.
3. Capture a fresh accessibility snapshot.
4. Capture a screenshot with `--return-format path`.
5. Open the image and inspect state, spacing, clipping, overlap, contrast, and readability.
6. Report the Simulator name/UDID, scenario, accessibility evidence, screenshot path, and visual verdict.

Keep screenshots, logs, DerivedData, and other generated artifacts outside tracked source paths unless a task explicitly requires them in the repository.

## Upgrade procedure

Upgrades are deliberate repository work, never automatic:

1. Review the target XcodeBuildMCP release and its CLI skill changes.
2. Install one exact version with `npm install --global xcodebuildmcp@<version>`; never use `@latest` in project instructions.
3. Replace the vendored CLI skill from the matching Git tag.
4. Update the version, path, provenance, and SHA-256 in this document.
5. Re-run the complete build, test, launch, accessibility, interaction, screenshot, log, and clean-session checks.

## Failure policy

Do not silently fall back to raw `xcodebuild`, `xcrun`, or `simctl`. Capture the failing XcodeBuildMCP command and output, consult its help, and report the limitation to Danis before introducing another execution route.

## Sources

- [XcodeBuildMCP CLI documentation](https://www.xcodebuildmcp.com/docs/cli)
- [XcodeBuildMCP configuration documentation](https://www.xcodebuildmcp.com/docs/configuration)
- [XcodeBuildMCP skills documentation](https://www.xcodebuildmcp.com/docs/skills)
- [XcodeBuildMCP v2.7.0 CLI skill](https://github.com/getsentry/XcodeBuildMCP/tree/v2.7.0/skills/xcodebuildmcp-cli)
