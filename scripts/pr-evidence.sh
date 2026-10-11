#!/bin/bash

set -euo pipefail

# Requires authenticated gh, jq, python3 and an existing PR.
: "${1:?Usage: scripts/pr-evidence.sh PR_NUMBER}"
REPO=$(gh api 'repos/{owner}/{repo}' --jq .full_name)
PR=$(gh api "repos/$REPO/pulls/$1")
NUMBER=$(jq -r .number <<< "$PR")
HEAD_SHA=$(jq -r .head.sha <<< "$PR")
SCRIPT_DIRECTORY=$(dirname "${BASH_SOURCE[0]}")
select_latest_run() {
  python3 "$SCRIPT_DIRECTORY/evidence_validation.py" "$REPO" "$HEAD_SHA"
}
require_current_run() {
  local latest
  latest=$(select_latest_run)
  test "$(jq -r .id <<< "$latest")" = "$RUN_ID" || {
    echo 'Scheduled native acceptance changed; retrieve the current run.' >&2; exit 1;
  }
}
RUN=$(select_latest_run)
RUN_ID=$(jq -r .id <<< "$RUN")
echo "PR #$NUMBER at $HEAD_SHA: $(jq -r .html_url <<< "$RUN")"

CI_STATUS=0
gh run watch "$RUN_ID" --repo "$REPO" --exit-status --interval 15 || CI_STATUS=$?
CURRENT_HEAD=$(gh api "repos/$REPO/pulls/$NUMBER" --jq .head.sha)
test "$CURRENT_HEAD" = "$HEAD_SHA" || { echo 'PR head changed; rerun for the new commit.' >&2; exit 1; }
require_current_run
RUN_ATTEMPT=$(gh api "repos/$REPO/actions/runs/$RUN_ID" --jq .run_attempt)

EVIDENCE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/whogavewhat-pr-$NUMBER.XXXXXX")
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$EVIDENCE_DIR"' EXIT
echo "Downloading evidence to $EVIDENCE_DIR"
gh run download "$RUN_ID" --repo "$REPO" --pattern "ui-*-attempt-$RUN_ATTEMPT" --dir "$EVIDENCE_DIR"
for DIRECTORY in "$EVIDENCE_DIR"/ui-*; do
  jq -e --arg sha "$HEAD_SHA" --arg run "$RUN_ID" --arg attempt "$RUN_ATTEMPT" \
    '.head_sha == $sha and .run_id == $run and .run_attempt == $attempt' "$DIRECTORY/metadata.json" > /dev/null
  echo "Report: $DIRECTORY/index.html"
done

CURRENT_HEAD=$(gh api "repos/$REPO/pulls/$NUMBER" --jq .head.sha)
test "$CURRENT_HEAD" = "$HEAD_SHA" || { echo 'PR head changed during download; rerun for the new commit.' >&2; exit 1; }
require_current_run
CURRENT_ATTEMPT=$(gh api "repos/$REPO/actions/runs/$RUN_ID" --jq .run_attempt)
test "$CURRENT_ATTEMPT" = "$RUN_ATTEMPT" || { echo 'CI attempt changed during download; rerun for the new attempt.' >&2; exit 1; }
trap - EXIT
echo "Inspect attachments/*.png, metadata.json and journeys.mp4."
echo "For video review on Linux: ffmpeg -i PATH/journeys.mp4 -vf fps=1/2 PATH/frame-%04d.png"
echo "Remove $EVIDENCE_DIR after review. CI exit status: $CI_STATUS"
exit "$CI_STATUS"
