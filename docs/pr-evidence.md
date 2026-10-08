# Project checks and PR evidence

Every PR includes reviewed screenshots **and** a video in its description, including changes to documentation, tooling and CI. A link to a workflow or a downloadable artifact alone does not satisfy this requirement.

The `Tests` workflow has no path filters. It runs Python helpers, Ruby release coordinator/archive/signing tests and secret checks on Linux, Swift formatting and SwiftLint on macOS, then unit tests and the native XCUITest acceptance journey on macOS 26 with Xcode 26.6. XcodeBuildMCP 2.7.0 performs all Xcode and Simulator operations. It reuses a booted iPhone when one exists and otherwise selects iPhone 17 Pro on the newest available runtime.

## Local development

Install the pinned CLI from the project skill and SwiftLint with Homebrew:

```sh
npm install --global xcodebuildmcp@2.7.0
brew install swiftlint ffmpeg
scripts/format-swift.sh
scripts/check-formatting.sh
scripts/lint-swift.sh
python3 -m unittest discover -s scripts/tests -v
```

Use a Swift 6.3 toolchain for formatting, matching Xcode 26.6 CI. The formatter applies four spaces. SwiftLint checks the explicit correctness rules in `.swiftlint.yml`; layout belongs to swift-format. New code follows the same checks without a suppression baseline. A narrowly scoped suppression explains a rule's false positive, such as a numeric `RankedPerson.count` rather than a collection count.

To run the same app validation on a Mac:

```sh
python3 scripts/run-app-smoke.py /tmp/whogavewhat-evidence
```

The runner invokes unit tests and `WhoGaveWhatUITests/AdaptiveGiftJourneyUITests/testAdaptiveGiftJourney` through XcodeBuildMCP. The native journey checks navigation, compact gift entry and keyboard, Details and value entry, calendar grids with different week counts, creation and automatic selection of people, duplicate-person reuse, save and relaunch persistence, currency selection, and bundled licenses. It creates uniquely named records through the real UI in the existing store; it never erases a reused Simulator. XCTest keeps named screenshots, and the runner exports them from the result bundle while recording video through XcodeBuildMCP. Failed tests retain screenshots, the accessibility hierarchy, and the result bundle for diagnosis.

## Retrieve and inspect current evidence

After opening the draft PR and after each push or CI rerun:

```sh
scripts/pr-evidence.sh PR_NUMBER
```

The helper waits for the latest PR `Tests` run, downloads only its current-attempt `ui-*` artifacts and verifies the PR head SHA, run ID and attempt before and after download. It prints a retained temporary directory. Failed runs remain diagnostic material and cannot be published as acceptance evidence.

When retrying CI, rerun the **whole** `Tests` workflow:

```sh
gh run rerun RUN_ID
```

Each new run attempt must regenerate screenshots and video. Rerunning only failed jobs skips a previously successful smoke job, so its old media belongs to the previous attempt and the retrieval and publishing helpers correctly reject it. After the full rerun finishes, retrieve, inspect and publish the new attempt.

Open the artifact's `index.html`, inspect every selected PNG, and watch `journeys.mp4`. On Linux, extract frames throughout the recording to inspect the transitions:

```sh
ffmpeg -i /tmp/ARTIFACT/journeys.mp4 -vf fps=1/2 /tmp/ARTIFACT/frame-%04d.png
```

PNG checkpoints are native XCTest screenshot attachments exported from the result bundle and mapped by their attachment names. The MP4 records the Simulator through MCP. Review the original video as well as frames where a transition, animation or transient failure matters. The report and metadata identify the source head, checkout merge commit, device, runtime, Xcode and capture outcome.

For a UI change, extend the recorded scenario to exercise that change and its success, error and dismissal paths as relevant. Set the resulting artifact's `evidence_kind` to `feature-acceptance` only when it records that scenario. Review the feature's checkpoints and recording; app smoke alone cannot establish feature acceptance. For infrastructure and documentation changes, describe the environment integrity demonstrated by the existing journey; do not claim acceptance of an unrelated feature.

## Embed screenshots and video

Use an authenticated user `gh` session. Native GitHub attachments use the existing user authorization; the Actions token cannot upload them. No extra PAT or repository secret is needed. The uploader follows the native attachment API used by `gh` 2.102+.

Write a short English review outside the repository, identifying what you inspected and any limitations. Publish both kinds of media:

```sh
python3 scripts/pr-visual-evidence.py PR_NUMBER /tmp/ARTIFACT \
  --summary-file /tmp/visual-review.md \
  --image attachments/home-start.png \
  --image attachments/people.png \
  --image attachments/insights.png \
  --image attachments/gift-compact-keyboard.png \
  --video journeys.mp4
python3 scripts/pr-evidence-gate.py PR_NUMBER
```

Each source must be a real, nonempty PNG or MP4 inside the artifact directory; the source may exceed 10 MiB. The publisher requires local `ffmpeg`, derives temporary upload copies, and removes them when it exits. PNGs are scaled without upscaling to fit within 320×640 while preserving aspect ratio. Videos keep their complete duration and timing, and are encoded as H.264/yuv420p MP4 with fast start and even dimensions, scaled to fit the same bounds. Every derived file must be nonempty, have a valid PNG or MP4 signature, and fit within the 10 MiB upload limit. All media is converted and checked before any attachment upload or PR edit. If ffmpeg is missing, install it with `brew install ffmpeg` on macOS or `sudo apt install ffmpeg` on Ubuntu.

Inspect every original checkpoint and the full recording before publication. After publishing, inspect every rendered compact attachment in the PR at a 1280×800 viewport: check screenshot sharpness and grouping, confirm each screenshot stays within the compact bounds, and play the native video to its end. The description places two screenshot embeds in one Markdown paragraph, separated by a space, with a blank line between pairs. Two per row fit typical MacBook PR widths; three 320-pixel images span 960 pixels before page margins. Descriptive filenames become English screenshot alt labels. Each video attachment URL stays on its own line so GitHub renders its native player.

Publication validates the latest successful run and attempt, uploads the compact native attachments and updates only the marked evidence section, preserving other PR text. It rechecks the PR and CI afterward and invalidates stale evidence if a concurrent push or rerun occurs. Upload failures do not partially replace the PR body.

The separate `PR evidence gate` runs on PR edits, pushes and completed `Tests` runs. It executes trusted base/default-branch scripts with a read-only source checkout, reads PR metadata and posts a `Visual evidence` status on the actual PR head. It checks that both native media links are embedded, labelled, and tied to the latest passing run and attempt. It does not execute PR code or artifacts and is independent of `Tests`, so publication has no circular dependency. Human or agent inspection remains the acceptance step; the gate cannot verify the contents of a reviewer's claims.

This workflow starts automatically after it exists on the base branch. The initial setup PR uses the same validator manually. The evidence workflow posts a status; it does not configure branch protection or required checks. Repository rules determine whether a failing status prevents merging. Merge autonomously after the current head passes all required checks, independent and bot review, and inspected evidence, subject to the scope and approval policy in `AGENTS.md`. Verify master CI before TestFlight delivery.

## Raspberry Pi

Run formatting with the installed Swift 6.3 toolchain and the Python helper tests locally. Native iOS tests, SwiftLint and Simulator capture run in GitHub's macOS CI. Retrieve the current run with `scripts/pr-evidence.sh`, inspect the PNG checkpoints and extracted video frames, write the English review, then publish attachments using the existing authenticated `gh` session. If the changed UI scenario needs deeper inspection, extend the native XCUITest journey in CI; a local Mac is optional; report any verification limitation explicitly.
