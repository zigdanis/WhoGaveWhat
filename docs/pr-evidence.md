# Project checks and PR evidence

Every PR includes reviewed screenshots **and** a video in its description, including changes to documentation, tooling and CI. A link to a workflow or a downloadable artifact alone does not satisfy this requirement.

The `Tests` workflow has no path filters. It runs Python helpers, Ruby release coordinator/archive/signing tests and secret checks on Linux, Swift formatting and SwiftLint on macOS, then unit tests and an app smoke scenario on macOS 26 with Xcode 26.6. XcodeBuildMCP 2.7.0 performs all Xcode and Simulator operations. It reuses a booted iPhone when one exists and otherwise selects iPhone 17 Pro on the newest available runtime.

## Local development

Install the pinned CLI from the project skill and SwiftLint with Homebrew:

```sh
npm install --global xcodebuildmcp@2.7.0
brew install swiftlint
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

It tests the app, builds and launches it, then records Home → People → Insights → Add a gift. Existing `KS_START` / `KS_TAB` launch settings open the app in English at Home. This scenario visits the real app with its existing store; it does not modify or erase a reused Simulator. The smoke checks navigation and media capture. It does not assert gift creation or acceptance of a UI feature.

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

PNG checkpoints are normalized from XcodeBuildMCP's optimized JPEG captures (up to 800 pixels). The MP4 records the Simulator through MCP. Review the original video as well as frames where a transition, animation or transient failure matters. The report and metadata identify the source head, checkout merge commit, device, runtime, Xcode and capture outcome.

For a UI change, extend the recorded scenario to exercise that change and its success, error and dismissal paths as relevant. Set the resulting artifact's `evidence_kind` to `feature-acceptance` only when it records that scenario. Review the feature's checkpoints and recording; app smoke alone cannot establish feature acceptance. For infrastructure and documentation changes, use `app-smoke` and describe the basic screens inspected.

## Embed screenshots and video

Use an authenticated user `gh` session. Native GitHub attachments use the existing user authorization; the Actions token cannot upload them. No extra PAT or repository secret is needed. The uploader follows the native attachment API used by `gh` 2.102+.

Write a short English review outside the repository, identifying what you inspected and any limitations. Publish both kinds of media:

```sh
python3 scripts/pr-visual-evidence.py PR_NUMBER /tmp/ARTIFACT \
  --summary-file /tmp/visual-review.md \
  --image attachments/home.png \
  --image attachments/people.png \
  --image attachments/insights.png \
  --image attachments/add-gift.png \
  --video journeys.mp4
python3 scripts/pr-evidence-gate.py PR_NUMBER
```

Each selected file must be a real, nonempty PNG or MP4 inside the artifact directory and at most 10 MiB. For an oversized recording, use ffmpeg to produce a smaller MP4 inside that directory, inspect it and pass its relative filename. Keep the same source metadata. Publication validates the latest successful run and attempt, uploads native attachments and updates only the marked evidence section, preserving other PR text. It rechecks the PR and CI afterward and invalidates stale evidence if a concurrent push or rerun occurs. Upload failures do not partially replace the PR body.

The separate `PR evidence gate` runs on PR edits, pushes and completed `Tests` runs. It executes trusted base/default-branch scripts with a read-only source checkout, reads PR metadata and posts a `Visual evidence` status on the actual PR head. It checks that both native media links are embedded, labelled, and tied to the latest passing run and attempt. It does not execute PR code or artifacts and is independent of `Tests`, so publication has no circular dependency. Human or agent inspection remains the acceptance step; the gate cannot verify the contents of a reviewer's claims.

This workflow starts automatically after it exists on the base branch. The initial setup PR uses the same validator manually. GitHub currently returns HTTP 403 for branch protection and rulesets in this private repository because of the account plan: a failing evidence status is visible, but automatic prevention of merging cannot be configured here. Hand over only passing, reviewed PRs and leave merging to Danis.

## Raspberry Pi

Run formatting with the installed Swift 6.3 toolchain and the Python helper tests locally. Native iOS tests, SwiftLint and Simulator capture run in GitHub's macOS CI. Retrieve the current run with `scripts/pr-evidence.sh`, inspect the PNG checkpoints and extracted video frames, write the English review, then publish attachments using the existing authenticated `gh` session. If the changed UI scenario needs deeper inspection, use the established Mac execution environment or extend the CI scenario; report any verification limitation explicitly.
