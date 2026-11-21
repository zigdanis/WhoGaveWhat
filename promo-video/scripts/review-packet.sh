#!/bin/bash
# Builds a review packet for one round: contact sheets at 4 fps (cell i, row-major, 10 per row, is t = i/4 s)
# and half-size stills every 0.5 s of the English cut. Usage: scripts/review-packet.sh ROUND [VARIANT]
# VARIANT is the composition ID without the language (default D-StoryMotion); ROUND names review/r<ROUND>.
set -euo pipefail
cd "$(dirname "$0")/.."
R=review/r$1
V=${2:-D-StoryMotion}
rm -rf "$R" && mkdir -p "$R/stills"
for L in en ru; do
  ffmpeg -v error -y -i "out/final/$V-$L.mp4" -vf "fps=4,scale=200:-1,tile=10x13" -frames:v 1 "$R/sheet-$L.jpg"
done
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out/final/$V-en.mp4)
python3 - "$D" "$R" "$V" <<'PY'
import subprocess, sys
d, r, v = float(sys.argv[1]), sys.argv[2], sys.argv[3]
t = 0.25
while t < d:
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.2f}', '-i', f'out/final/{v}-en.mp4',
                    '-frames:v', '1', '-vf', 'scale=443:-1', f'{r}/stills/t{t:05.2f}.jpg'], check=True)
    t += 0.5
PY
ls "$R" "$R/stills" | wc -l
