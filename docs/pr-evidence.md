# Project checks and PR evidence

Every PR includes reviewed screenshots **and** a video in its description, including changes to documentation, tooling and CI. A link to a workflow or a downloadable artifact alone does not satisfy this requirement.

The automatic `Checks` workflow runs Python helpers, Ruby release coordinator/archive/signing tests and secret checks on Linux, plus Swift formatting and SwiftLint on macOS, for PR updates and master pushes without path filters. The manually scheduled `Tests` workflow runs the required app-owned unit and native XCUITest acceptance suite on the default macOS 26 ARM runner with Xcode 26.6. Both the full native CI job and the optional Spotlight diagnostic job request the installed iOS 26.4 Simulator runtime with `--runtime 'iOS 26.4'`, using the same Xcode 26.6 SDK. This records a comparable native environment; the required scope and separate OS Spotlight diagnostic are defined below. The smoke runner uses Apple's `xcodebuild`, `xcrun simctl`, and `xcresulttool` directly. Both CI jobs opt into `--fresh-ci-simulator`, a GitHub Actions-only fixture experiment for the observed native app-catalog failures; it requires an explicit runtime and creates a run-owned iPhone 17 Pro using an available device's exact type and runtime identifiers. Metadata records the source device, created UDID, type and runtime identifiers, verified creation, and cleanup outcome; only that created device is shut down and deleted, after recording, logs and attachment export finish. This fixture does not establish or cure the Spotlight failure's cause and preserves every assertion in each selected native scenario. Local runs without `--runtime` reuse a booted iPhone when one exists and otherwise select iPhone 17 Pro on the newest available runtime. Without the CI fixture, an explicit runtime request reuses the chosen booted iPhone only if its runtime matches; a conflict fails before Simulator changes. With no booted iPhone, the requested runtime must have an available iPhone 17 Pro. Missing runtimes or devices fail without falling back. Metadata records the requested runtime even when selection fails, and the actual runtime and device ID after successful selection. A cold first boot can spend several minutes in Apple's data migration, so `simctl bootstatus` has a bounded 10-minute allowance; its progress log and process diagnostics are retained on timeout. Recording is stopped with SIGINT so `simctl` can finalize the MP4; command output and process diagnostics are retained when native operations fail or time out. Timed-out commands terminate their process group with bounded cleanup; if group signaling is denied, the runner signals its own process and preserves captured output even when children retain inherited pipes.

## Native CI budget

Each delivery has one full native run on the ready PR and one on the final master source. Batch implementation, lightweight checks, independent re-review and all actionable bot fixes first; wait until reviewers reach terminal states before scheduling acceptance. Automatic `Checks` cancels superseded lightweight runs. Native `Tests` keeps running if another commit is pushed, but evidence remains valid only for its exact head.

Apply `ci-ready` once to the final reviewed PR head to schedule its full `Tests` run. PR acceptance retains the `pull_request` event and existing trusted-base provenance checks. The label schedules testing; it does not authorize merge or release before current-head checks, terminal reviews and inspected screenshots/video pass. Labels other than `ci-ready` cannot execute native tests. Shared retrieval and validation ignore a later run only after its sole attempt and both known native jobs are verified as completed/skipped; failed, running, cancelled, rerun or ambiguous runs remain authoritative. Missing job information or a changing run stops selection, and the lookup fails closed if no scheduled acceptance is found in its bounded 100-run history.

After authorized merge, dispatch `Tests` once with `--ref master`, verify its source SHA is the actual final master commit, and require that exact successful run before the existing TestFlight receipt path. A dispatch always runs the required app-owned suite, including when optional Spotlight diagnostics are requested; diagnostic media cannot replace acceptance. Pushes, opening a PR and ordinary synchronization schedule only lightweight checks.

An additional full run, including an unchanged-head retry or a run after an acceptance-stage fix, requires Danis's explicit budget exception. Preserve the failed run's diagnostics, identify and batch concrete fixes, obtain re-review, and explain why another full run is necessary before requesting that exception. A rerun regenerates the whole suite and its current-attempt media; prior screenshots or successful jobs cannot substitute. This policy changes scheduling, while checkpoints for the declared required scope, Simulator/signature assertions, evidence and release gates remain required.

## Local development

Install SwiftLint with Homebrew. Xcode and its command line tools provide the native build and Simulator commands:

```sh
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

The runner invokes the required app-owned `WhoGaveWhat` unit and UI tests with `xcodebuild test`; the exact OS Spotlight method is excluded from required acceptance. The native journey checks navigation, compact gift entry and keyboard, Details and value entry, calendar grids with different week counts, creation and automatic selection of people, duplicate-person reuse, save and relaunch persistence, currency selection, and bundled licenses. It creates uniquely named records through the real UI in the existing store; it never erases a reused Simulator. XCTest keeps named screenshots, which the runner exports from the result bundle, while `simctl io recordVideo` captures the journey. Reusing the same evidence directory removes only the runner's known generated outputs first; unrelated files and Simulator data remain. Failed tests retain their new screenshots, the accessibility hierarchy, command logs, and result bundle for diagnosis.

## App-owned acceptance and device Spotlight

Required CI passes `--verify-app-names` on a disposable Simulator. The runner prepares English as the primary system language and Russian as a secondary language while the Simulator is shut down, then boots it and waits for readiness. `AppDiscoveryUITests.testRussianAppLanguagePreservesNavigationDraftAndColdOnboarding` verifies the language order in real Settings and selects Russian through the app's Settings language picker. It checks the actual English/Russian app interface, backgrounds and directly activates the app to verify navigation and unsaved draft preservation, checks cancellation, and cold-launches normally into Russian onboarding. It never requires a Home-screen launcher, Calendar search, or Spotlight result. Language cleanup remains an assertion and failures block acceptance.

Compiled English/Russian `CFBundleName`, `CFBundleDisplayName`, the canonical bilingual public indexed display-name resource, and the Spotlight activity declaration are mandatory. Native `AppDiscoveryTests` verify the searchable item's public metadata and stable identifier, indexing retry/coalescing, and real activity routing across onboarding, sign-in, navigation and draft states. Every unrelated unit and UI test remains required. Plain local smoke excludes the disposable Settings journey; use `--verify-app-names` only on a disposable Simulator.

OS-owned app-catalog initialization and Spotlight retrieval are optional diagnostics and post-release real-device checks. This scope follows Danis's explicit request to deliver a TestFlight build for device verification after repeated Simulator catalog failures; it does not establish an Apple root cause or waive app-owned failures. Required metadata states `acceptance_scope=app-owned`, `spotlight_search_outcome=not-run`, and `spotlight_device_acceptance=pending`. Its scenario, native-test description and required PNGs describe only the behavior actually executed. Successful app-owned CI and media do not claim Spotlight retrieval passed.

The original strict `testRussianAppLanguageAndBilingualSpotlightPreserveDraftAndOnboarding` remains available with:

```sh
python3 scripts/run-app-smoke.py /tmp/spotlight-diagnostic --verify-app-names --discovery-only
```

This selects only that exact OS method. It preserves genuine indexed public-payload recognition, exact English/Cyrillic queries and keyboard selection, actual result taps, navigation/draft preservation, cold onboarding, bounded waits and failure artifacts. A missing catalog or result still fails the diagnostic command and is recorded as failure; it is never converted into acceptance. Its metadata and media are diagnostic-only. The manual workflow's optional `spotlight_diagnostics` job may fail without blocking the required app-owned job; inspect its actual logs and metadata even when the overall workflow succeeds.

Publish current-head app-owned screenshots and recording with the pending-device declaration. After TestFlight is available, ask Danis to open the app once, use an English iPhone with Russian app language, search both public names, and open each genuine app result while an unsaved gift draft is present. Check existing people and gifts and a cold launch. Record device result as pending until Danis reports it; device confirmation is not a pre-release gate. Any app-owned metadata, activity-routing, Settings-language, draft, lifecycle or persistence failure remains blocking.

## Retrieve and inspect current evidence

After the scheduled ready-PR full run completes:

```sh
scripts/pr-evidence.sh PR_NUMBER
```

The helper waits for the latest scheduled native PR `Tests` run, downloads only its current-attempt `ui-*` artifacts and verifies the PR head SHA, run ID and attempt before and after download. It prints a retained temporary directory. Failed runs remain diagnostic material and cannot be published as acceptance evidence.

If Danis authorizes an additional full attempt, rerun the **whole** `Tests` workflow for an unchanged head, or apply `ci-ready` again after the reviewed head changes. Retrieve, inspect and publish that attempt's new screenshots and video. A push alone does not schedule native acceptance; stale media and partial-job reruns cannot pass the current-head gate.

Open the artifact's `index.html`, inspect every selected PNG, and watch `journeys.mp4`. On Linux, extract frames throughout the recording to inspect the transitions:

```sh
ffmpeg -i /tmp/ARTIFACT/journeys.mp4 -vf fps=1/2 /tmp/ARTIFACT/frame-%04d.png
```

PNG checkpoints are native XCTest screenshot attachments exported from the result bundle and mapped by their attachment names. The MP4 records the Simulator through `simctl`. Review the original video as well as frames where a transition, animation or transient failure matters. The report and metadata identify the source head, checkout merge commit, device, runtime, Xcode and capture outcome.

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

Publication requires the latest scheduled native run and its current attempt to pass, uploads the compact native attachments and updates only the marked evidence section, preserving other PR text. It rechecks the PR and CI afterward and invalidates stale evidence if a concurrent push or rerun occurs. Upload failures do not partially replace the PR body.

The separate `PR evidence gate` validates body edits only when the current or previous body contains a visual-evidence marker. Publication, evidence edits and removal therefore trigger validation, while title-only changes and ordinary descriptions without media skip the validator. Pushes and completed `Tests` runs do not schedule this gate; the coordinator checks current-head evidence before merge. It executes trusted base/default-branch scripts with a read-only source checkout, reads PR metadata and posts a `Visual evidence` status on the actual PR head. It checks that both native media links are embedded, labelled, and tied to the latest passing run and attempt. It does not execute PR code or artifacts and is independent of `Tests`, so publication has no circular dependency. Human or agent inspection remains the acceptance step; the gate cannot verify the contents of a reviewer's claims.

The edited-event policy takes effect after this workflow is on the base branch; its own policy PR still uses the existing trusted-base workflow. The same validator remains available manually for current-head checks. The evidence workflow posts a status; it does not configure branch protection or required checks. Repository rules determine whether a failing status prevents merging. Merge autonomously after the current head passes all required checks, independent and bot review, and inspected evidence, subject to the scope and approval policy in `AGENTS.md`. Verify master CI before TestFlight delivery.

## Raspberry Pi

Run formatting with the installed Swift 6.3 toolchain and the Python helper tests locally. Native iOS tests, SwiftLint and Simulator capture run in GitHub's macOS CI. Retrieve the current run with `scripts/pr-evidence.sh`, inspect the PNG checkpoints and extracted video frames, write the English review, then publish attachments using the existing authenticated `gh` session. If the changed UI scenario needs deeper inspection, extend the native XCUITest journey in CI; a local Mac is optional; report any verification limitation explicitly.
