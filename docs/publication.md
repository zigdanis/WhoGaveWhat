# Public repository and release boundaries

[WhoGaveWhat](https://github.com/zigdanis/WhoGaveWhat) is the canonical public
repository, under the MIT license. Its published `master` starts with fresh Git
history. Personal Apple account and signing configuration is supplied through
the environment rather than embedded in source. New publication commits use
GitHub noreply metadata.

Original history, release identities and durable receipts are preserved in
private backups. GitHub-managed pull request refs and cached commit pages can
retain old commit metadata, including a private contact email. The maintainer
explicitly accepted this remaining exposure when authorizing publication; a fresh
branch history does not claim to erase those surfaces. The separate signing
certificate repository remains private.

## Contributions and builds

Open contributions against `WhoGaveWhat`. Its test workflows run without signing
secrets. The evidence gate uses trusted default-branch scripts and does not execute
contributor artifacts. Simulator builds do not require the maintainer's Apple
account. Device builds require your own signing team and, where needed, your own
bundle identifier. Do not commit account emails, credentials or personal signing
configuration.

Publication does not enable automatic distribution. TestFlight uses a manual
`workflow_dispatch` on the canonical repository's verified `master` and the
protected `testflight` environment, whose custom deployment policy allows only
`master` and no tags. The delivery agent may invoke this protected dispatch after
each routine feature or fix passes its review, bot, CI, visual-evidence, merge,
and master-CI gates, unless the user explicitly limits the work to no deployment.
Pushes, pull requests and forks do not run that release job.
Release helpers require an explicit `--repo` and validate the canonical target
and environment policy before dispatching or importing credentials.

Release secrets stay in the protected environment. `MATCH_GIT_URL`, `APPLE_TEAM_ID`
and optional Appfile settings `FASTLANE_USER` and `APP_STORE_CONNECT_TEAM_ID` come
from the environment. API-key release operations do not require a personal Apple
ID. See [TestFlight operations](testflight.md) for setup and the preserved receipt
recovery limits after replacing branch history.

## Preserved work in progress

[Pull request #20](https://github.com/zigdanis/WhoGaveWhat/pull/20) retains the
unmerged Spotlight discovery and bilingual launcher-name changes for later review
and merge. They are not part of this publication snapshot. The publication does
not replace its outstanding bilingual Spotlight acceptance checks.
