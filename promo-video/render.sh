#!/bin/bash
# Renders every composition (or the ones given) and transcodes it to the App Store app preview spec:
# 886x1920, 30 fps, H.264 High@4.0 at ~11 Mbps, AAC stereo 256 kbps 48 kHz at -16 LUFS (constant 11 Mbps, inside Apple's 10-12 Mbps target). Output: out/final/<id>.mp4
set -euo pipefail
cd "$(dirname "$0")"
IDS=("$@")
if [ ${#IDS[@]} -eq 0 ]; then
  IDS=(A-Clean-en A-Clean-ru B-Showcase-en B-Showcase-ru C-Story-en C-Story-ru D-StoryMotion-en D-StoryMotion-ru)
fi
mkdir -p out/raw out/final
for id in "${IDS[@]}"; do
  nice -n 10 npx remotion render src/index.ts "$id" "out/raw/$id.mp4" --codec=h264 --crf=14 \
    --audio-codec=aac --audio-bitrate=320k --log=error
  nice -n 10 ffmpeg -v error -y -i "out/raw/$id.mp4" \
    -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30 \
    -b:v 11M -minrate 11M -maxrate 11M -bufsize 11M -x264-params nal-hrd=cbr -preset slow \
    -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart "out/final/$id.mp4"
  echo "$id: $(ffprobe -v error -show_entries format=duration -of csv=p=0 "out/final/$id.mp4")s"
done
