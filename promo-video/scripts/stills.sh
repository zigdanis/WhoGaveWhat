#!/bin/bash
# Renders stills of a composition side by side for a quick look: scripts/stills.sh ID OUT.jpg FRAME...
set -euo pipefail
cd "$(dirname "$0")/.."
ID=$1
OUT=$2
shift 2
TMP=$(mktemp -d)
INPUTS=()
for F in "$@"; do
  npx remotion still src/index.ts "$ID" "$TMP/$F.jpg" --frame="$F" --scale=0.4 --log=error >/dev/null
  INPUTS+=(-i "$TMP/$F.jpg")
done
if [ $# -gt 1 ]; then
  ffmpeg -v error -y "${INPUTS[@]}" -filter_complex "hstack=inputs=$#" "$OUT"
else
  cp "$TMP/$1.jpg" "$OUT"
fi
rm -rf "$TMP"
