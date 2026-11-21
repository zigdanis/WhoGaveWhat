#!/bin/bash
# Cuts the cards variant E lifts off the screen out of the story recordings, at source resolution.
# Rects are in video pixels (886x1920, footage drawn with objectFit cover); they must match LIFTS in
# src/variants/Kinetic.tsx.
set -euo pipefail
cd "$(dirname "$0")/.."
crop() { # locale clip time name x y w h [ffmpeg filters after the crop]
  python3 - "$@" <<'PY'
import subprocess, sys
loc, clip, t, name, x, y, w, h = sys.argv[1:9]
extra = ''.join(',' + f for f in sys.argv[9:])
k = 886 / 1206; off = (2622 * k - 1920) / 2
sx, sy, sw, sh = [round(v) for v in (float(x) / k, (float(y) + off) / k, float(w) / k, float(h) / k)]
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', t, '-i', f'public/footage/story/{loc}-{clip}.mp4', '-frames:v', '1',
                '-vf', f'crop={sw}:{sh}:{sx}:{sy}{extra}', f'public/lift/{loc}-{name}.png'], check=True)
PY
}
crop en add 79.5 row 36 446 814 152
crop ru add 78.9 row 36 446 814 152
crop en person 24.0 rows 38 1242 808 310
crop ru person 24.0 rows 38 1242 808 310
# The Even rows hide the money under the pill (row colour #1A1A1C): the payoff is one gift each way.
crop en insights 53.6 even 36 566 812 124 'drawbox=x=930:y=100:w=160:h=56:color=0x1A1A1C:t=fill'
crop ru insights 53.6 even 36 488 812 150 'drawbox=x=880:y=108:w=210:h=56:color=0x1A1A1C:t=fill'

# The Even pills alone, popped over the lifted row at the chime (rects in video px; PILLS in Kinetic.tsx).
crop en insights 53.6 pill 646 575 174 56
crop ru insights 53.6 pill 581 511 239 55
echo "wrote public/lift/*.png"
