#!/bin/bash

set -euo pipefail

# Requires authenticated gh, jq and python3. Publishes a combined App Store screenshots folder (written on MacPro
# by `scripts/store-screenshots.py OUT --combine PARTS`) as a private draft release, the hand-off to the manually
# dispatched App Store metadata workflow, and prints the tag to pass as its `screenshots_release` input.
# Draft releases are visible only to people with push access and never create a tag or a public release.
if [ $# -ne 1 ]; then
  echo "usage: $0 COMBINED_FOLDER" >&2
  exit 2
fi
DIRECTORY=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 "$ROOT/scripts/store-screenshots.py" "$DIRECTORY" --check >&2

REPO=$(gh api 'repos/{owner}/{repo}' --jq .full_name)
HEAD_SHA=$(jq -r .head_sha "$DIRECTORY/iphone-6.3/metadata.json")
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "error: no commit in $DIRECTORY/iphone-6.3/metadata.json" >&2; exit 1; }
gh api "repos/$REPO/commits/$HEAD_SHA" --silent \
  || { echo "error: commit $HEAD_SHA is not on GitHub; push it before publishing its screenshots" >&2; exit 1; }

TAG=store-screenshots/$(date -u +%Y%m%d-%H%M%S)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/store-screenshots.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# COPYFILE_DISABLE keeps macOS AppleDouble files out of the archive.
COPYFILE_DISABLE=1 tar -C "$DIRECTORY" -czf "$WORK/store-screenshots.tar.gz" --exclude '.DS_Store' .
gh release create "$TAG" "$WORK/store-screenshots.tar.gz" --repo "$REPO" --draft --prerelease --target "$HEAD_SHA" \
  --title "App Store screenshots $TAG (not a release)" \
  --notes "App Store screenshots captured on MacPro from $HEAD_SHA. Upload them with the App Store metadata workflow (screenshots_release: $TAG). Never publish this draft." >&2
echo "$TAG"
