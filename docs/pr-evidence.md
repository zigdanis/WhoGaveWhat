# Project checks and PR evidence

User-visible changes include reviewed screenshots **and** a video in the PR description. Documentation, tooling, CI and other non-UI changes report their functional checks instead.

## CI

- **`Checks`** runs automatically on every PR update and master push: Python helper tests, Ruby release tests and secret checks on Linux, plus Swift formatting and SwiftLint on macOS.
- **`Tests`** runs automatically on PR updates and master pushes that touch app, test, script or workflow files. It runs the required app-owned unit and native XCUITest suite through `scripts/run-app-smoke.py` on macOS 26 with Xcode 26.6 and the iOS 26.4 Simulator runtime, in a run-owned iPhone 17 Pro (`--fresh-ci-simulator`). Changes confined to Markdown, HTML, `docs/`, `.agents/` or `.claude/` skip it.
- A new push cancels the superseded run for the same PR; master runs are never cancelled. Batch fixes before pushing; see the [verification policy](../.agents/skills/full-send/references/verification-policy.md).
- TestFlight deployment requires a successful `Tests` run on the exact master SHA. If that commit skipped `Tests`, dispatch it once: `gh workflow run tests.yml --repo zigdanis/WhoGaveWhat --ref master`.

The runner uses Apple's `xcodebuild`, `xcrun simctl` and `xcresulttool` directly, with bounded timeouts. Failed tests retain screenshots, the accessibility hierarchy, command logs and the result bundle for diagnosis.

## Local development

```sh
brew install swiftlint ffmpeg
scripts/format-swift.sh
scripts/check-formatting.sh
scripts/lint-swift.sh
python3 -m unittest discover -s scripts/tests -v
```

Use a Swift 6.3 toolchain for formatting, matching Xcode 26.6 CI. SwiftLint checks the correctness rules in `.swiftlint.yml`; layout belongs to swift-format. A narrowly scoped suppression explains a rule's false positive.

To run the native journey on a Mac (it reuses a booted iPhone or picks iPhone 17 Pro on the newest runtime, and never erases a reused Simulator):

```sh
python3 scripts/run-app-smoke.py /tmp/whogavewhat-evidence
```

## App-owned acceptance and device Spotlight

Required CI passes `--verify-app-names` on a disposable Simulator. It checks compiled English/Russian app names, the bilingual indexed display name `Who Gave · кто че`, real Settings-based Russian app language, launcher-activity routing, navigation and draft preservation across background/resume, cancellation and cold onboarding.

Simulator Spotlight retrieval is unreliable on hosted runners, so it is an optional diagnostic, not acceptance. Run it with the `spotlight_diagnostics` input of a manual `Tests` dispatch, or locally:

```sh
python3 scripts/run-app-smoke.py /tmp/spotlight-diagnostic --verify-app-names --discovery-only
```

Evidence metadata records `spotlight_search_outcome=not-run` and `spotlight_device_acceptance=pending`. After TestFlight, ask Danis to search both names on the phone. Device confirmation is not a pre-release gate.

## Retrieve and inspect evidence

```sh
scripts/pr-evidence.sh PR_NUMBER
```

The helper waits for the latest PR `Tests` run for the current head, downloads its current-attempt `ui-*` artifact and verifies head SHA, run ID and attempt. Open `index.html`, inspect the selected PNGs, and review `journeys.mp4`. On Linux, extract frames:

```sh
ffmpeg -i /tmp/ARTIFACT/journeys.mp4 -vf fps=1/2 /tmp/ARTIFACT/frame-%04d.png
```

For a UI change, extend the native journey to exercise that change; app smoke alone does not establish feature acceptance.

## Embed screenshots and video

Use the authenticated user `gh` session; no extra token is needed. Write a short English review outside the repository, then publish:

```sh
python3 scripts/pr-visual-evidence.py PR_NUMBER /tmp/ARTIFACT \
  --summary-file /tmp/visual-review.md \
  --image attachments/home-start.png \
  --image attachments/gift-compact-keyboard.png \
  --video journeys.mp4
python3 scripts/pr-evidence-gate.py PR_NUMBER
```

The publisher scales media to fit 320×640, uploads native GitHub attachments, and replaces only the marked evidence section of the PR body. It refuses stale or failed runs.

The `PR evidence gate` workflow runs only when a PR body edit adds, changes or removes that evidence section. It runs trusted base-branch scripts and posts a `Visual evidence` status for the current head. It never executes PR code.

## Raspberry Pi

Run formatting and the Python helper tests locally. Native tests, SwiftLint and Simulator capture run in macOS CI. Retrieve the current run with `scripts/pr-evidence.sh`, inspect PNGs and video frames, and publish. A local Mac is optional.
