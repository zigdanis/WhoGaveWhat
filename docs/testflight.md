# Commanded WhoGaveWhat TestFlight releases

These operations belong to the canonical `zigdanis/WhoGaveWhat` repository,
which is public. Signing credentials remain in its protected `testflight`
environment; the signing repository remains private. Both command helpers require
an explicit `--repo`, verify the canonical repository, and check that the release
environment allows only `master` before proceeding. The workflow accepts manual
dispatches on the canonical repository's `master` only. Public forks and external
pull requests cannot use this release path. See [Publication boundaries](publication.md).

The delivery workflow uses a manual `workflow_dispatch` on verified `master`,
with no push/merge trigger. Every routine feature, fix, improvement, and build
request authorizes this beta release path; explicit PR-only and do-not-deploy
limits stop before release. Discussion and plan-only requests do not enter the
delivery workflow. No second deployment confirmation is needed. Each new release
advances version and build; retries keep the recorded identity. PR approval or
green CI alone does not start a release.

The implementation ports GrowingUp PRs 41, 43, 44, 45 and 47. WhoGaveWhat has one
app (`pro.ziganshin.WhoGaveWhat`) and generates its Info.plist from build settings;
there is no widget. Signing uses its own `whogavewhat-ci` branch.

## Setup and native release tooling

Use the repository's protected [testflight environment](https://github.com/zigdanis/WhoGaveWhat/settings/environments).
Its custom deployment branch policy must allow exactly the `master` branch and no
tags. Verify the current setup with `python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat ready`; secret
names alone do not establish valid Apple access or usable signing.

Required environment secrets:

- `ASC_PRIVATE_KEY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`: an App Store Connect team API key
  with Admin access for provisioning and certificate management.
- `MATCH_PASSWORD`: the password for the encrypted WhoGaveWhat signing branch.
- `MATCH_GIT_PRIVATE_KEY`: a write deploy key limited to the private signing repo.

Required environment variables: `APPLE_TEAM_ID` (your Apple Developer team),
`MATCH_GIT_URL` (the private signing repository SSH URL), and
`MATCH_GIT_BRANCH=whogavewhat-ci`. Optional `BETA_GROUP_ID` and `BETA_TESTER_ID`
resolve ambiguity in existing Apple records. Store `BETA_TESTER_EMAIL`,
`BETA_FEEDBACK_EMAIL` and missing review contact data in secrets, not variables.

XcodeBuildMCP 2.7.0 is pinned for native testing, app smoke and Simulator evidence.
Its `device build` supports extra arguments but always injects a build action,
project/scheme, destination and DerivedData arguments. It has no archive/export
command that exports an IPA. Consequently the release lane gates Fastlane `gym`
archive/export on `ALLOW_NATIVE_RELEASE_BUILD=true` in the environment variables.
Danis authorized this bounded exception in the deployment setup: Fastlane performs
the signed Release archive and IPA export; native tests, simulator operations and
visual evidence continue through XcodeBuildMCP. The exception is recorded in
`AGENTS.md` and the environment gate is enabled. Preflight, status and notes do
not archive or upload. A deployment without the gate fails before reserving a
version/build. Credential access and signing still require a successful preflight;
the presence of configuration does not claim they have been validated.

Use existing Mac T3 connections for missing credentials or Apple account setup.
Keep the shared signing branch, GrowingUp configuration and valid certificates
intact. Create a dedicated signing-only deploy key if the WhoGaveWhat environment
has none; pass its private half to `gh secret set` over stdin and remove temporary
copies. Never revoke certificates or run `match nuke` to make a retry pass.
Match reuses valid stored certificates and profiles. An expired stored certificate
stops the pinned Match version with an explicit validity error; inspect it through
the existing Mac setup and prepare a valid replacement without revoking another
app's working identity. Certificate renewal is not a supported Match lane option.

Back up the signing password in secure local storage before deleting input copies.

For the four Apple/match credentials, create temporary files outside every git
checkout with directory mode 700 and file mode 600:

```json
{
  "ASC_KEY_ID": "",
  "ASC_ISSUER_ID": "",
  "ASC_PRIVATE_KEY_PATH": "/absolute/private/path/AuthKey.p8",
  "MATCH_PASSWORD": ""
}
```

Run `python3 scripts/testflight-secrets.py --repo zigdanis/WhoGaveWhat /absolute/private/path/credentials.json`.
The temporary `.p8` copy must be beside the JSON. The importer passes secrets over
stdin, preserves the separately configured signing deploy key, and removes both
inputs only after all four saves succeed. Retain the original Apple key in secure
storage. Do not paste keys or passwords into a conversation or commit them.

## Manual commands

Review the workflow and its current screenshots/video using
[PR evidence](pr-evidence.md) before enabling it on master. Follow the repository's
the [merge and approval policy](../AGENTS.md#merge-and-approval-policy); routine
deployment authorization includes the normal merge after all gates pass.

```sh
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat ready
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat preflight
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat deploy next master /tmp/whogavewhat-notes.json
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat status ORIGINAL_RUN_ID
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat resume ORIGINAL_RUN_ID
python3 scripts/testflight.py --repo zigdanis/WhoGaveWhat notes ORIGINAL_RUN_ID /tmp/whogavewhat-notes.json
```

The CLI resolves the source to a full SHA. The workflow independently verifies it
belongs to `origin/master`. Deployment requires the latest `Tests` run for that
SHA to have succeeded. Both the CLI and workflow reject overlapping operations;
the workflow serializes releases without cancelling an in-progress operation.
It returns the exact run URL and a monitoring command.

`preflight` inventories the existing app, groups, testers, Apple versions and
builds, then checks signing without uploading. It prefers an existing `External`
group and identifies Danis from the app's tester records. It may add the identified
existing tester to the selected group. Ambiguous records require the reported
group/tester ID; a missing tester needs Danis's actual email and a separate invite.
Reports omit the private roster. External distribution reuses review contacts and
feedback email. Missing contacts can be supplied as a `BETA_REVIEW_INFO` JSON secret
with `contact_first_name`, `contact_last_name`, `contact_email`, `contact_phone`
and optional `notes`.

`status` reads the exact recorded Apple build and localizations. `resume` completes
that release's processing, metadata and distribution, without repeating an
attempted upload. If it stopped before upload intent was saved, resume can archive
and attempt its first upload. `notes` updates and verifies both locales on the
existing processed build, without archiving, uploading, changing membership or
resubmitting review.

## Prepared EN/RU notes

The JSON file contains exactly nonempty `en` and `ru` strings, at most 4000 UTF-8
bytes each. Use plain text without emoji or `<`; validation rejects text Fastlane
would silently sanitize. Prepare the wording before dispatch, with separate
**What's New / Что нового** and **What to Test / Что проверить** sections.

Compare the selected SHA with the last verified published source from a durable
receipt or historic `testflight/BUILD` tag. Check intervening Apple builds and
state any unknown-source gap. Existing features belong in testing instructions
unless the comparison changed them. Save reviewed notes and source comparison in
`docs/releases/` for reuse. The workflow sends these prepared strings unchanged;
it invokes no model or translation service and never substitutes raw git messages.

Apple stores this at build-level localized TestFlight **What to Test**, separate
from App Store version release notes. Deploy, resume, notes and processed status
read the text back from Apple and fail on a missing/mismatched locale. Receipts
include `apple_notes` and `notes_status`; a saved draft is not proof of publication.

## Receipts, recovery and completion

Unpublished draft GitHub releases under `testflight/receipts/RUN` store durable
nonsecret receipts. Each update is a single API mutation. Receipts are never
published and create no release tags. They reserve source SHA, app, version/build,
group/tester IDs and phases before uploading. The lane neither commits version
bumps nor pushes branches; all project mutations happen in the isolated source
worktree and are removed afterward.

Publication replaces the published branch history. Existing receipt identities,
version/build numbers and original source SHAs are preserved in durable receipts
and private backups, alongside the original history bundle. An old receipt's
source SHA may no longer be an ancestor of the new `master`; the workflow's
ancestry check then rejects `status`, `notes` and `resume` as well as deployment.
Inspect the preserved receipt and source backup before planning recovery. Do not
change its identity or create a replacement release to bypass that check.

`next` chooses a patch version above Apple versions/uploads, all reserved receipts
and the source project version. An explicit version must exceed them too. Build
numbers exceed Apple builds/uploads, reserved receipts and the source build.
The archived app's identifier, version/build and encryption declaration are
verified before upload; unexpected app extensions are rejected.

Upload intent is saved **before** Transporter starts. An interrupted or uncertain
upload is polled as that exact identity, never blindly retried. The bounded Apple
wait may finish while visibility or review is pending: resume or inspect status
on the same receipt. A processing rejection requires diagnosis and a corrected
release. Account agreements and beta review decisions require the account holder
or Apple; they cannot be bypassed.

The app declares no nonexempt encryption. Distribution assigns the recorded group,
checks Danis's membership, verifies both notes and enables external notifications.
Distinguish workflow success, Apple processing, beta review and tester availability.
Keys, temporary keychains, logs, archive and DerivedData are removed after the run;
only nonsecret receipts remain as artifacts and summaries.

Report the concrete version/build and actual Apple state. Phone delivery and note
visibility require Danis to confirm in TestFlight; while waiting, inspect the
existing build instead of sending another upload.
