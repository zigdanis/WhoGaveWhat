# Optional XcodeBuildMCP CLI

The default Xcode and Simulator workflow uses Apple's `xcodebuild`, `xcrun simctl`, and `xcresulttool` directly. The CI smoke runner and its evidence capture use these tools without installing XcodeBuildMCP.

Use XcodeBuildMCP only when a task benefits from a capability it provides, such as structured UI automation or accessibility snapshots. It is optional and does not replace the direct Apple-tool workflow for builds, tests, Simulator lifecycle, logs, or screenshots.

## Optional installation

If needed, install the version documented by the local CLI skill:

```bash
npm install --global xcodebuildmcp@2.7.0
```

Verify the local installation with:

```bash
command -v xcodebuildmcp
xcodebuildmcp --version
xcodebuildmcp tools --json
```

Start with the CLI's current help instead of assuming flags:

```bash
xcodebuildmcp --help
xcodebuildmcp tools --json
xcodebuildmcp <workflow> --help
xcodebuildmcp <workflow> <tool> --help
```

The repository configuration in `.xcodebuildmcp/config.yaml` supplies project and scheme defaults. Keep XcodeBuildMCP optional: native operation failures from `xcodebuild` or `simctl` should be diagnosed directly, not routed through a second runner.

## Sources

- [XcodeBuildMCP CLI documentation](https://www.xcodebuildmcp.com/docs/cli)
- [XcodeBuildMCP configuration documentation](https://www.xcodebuildmcp.com/docs/configuration)
- [XcodeBuildMCP skills documentation](https://www.xcodebuildmcp.com/docs/skills)
- [XcodeBuildMCP v2.7.0 CLI skill](https://github.com/getsentry/XcodeBuildMCP/tree/v2.7.0/skills/xcodebuildmcp-cli)
