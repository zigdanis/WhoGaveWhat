#!/usr/bin/env python3
"""Finds where the screen moves in each slow-motion recording.

For every clip in public/footage/slow it compares consecutive frames (small greyscale copies) and
prints the spans where something changes, merged across short pauses. These spans and the tap times
in the *.gesture-telemetry.json files are what src/data.ts cuts the speed ramps from.

Usage: python3 -I scripts/motion-spans.py [--dir=slow|story] [--thr=0.25] [clip ...]   (e.g. en-add ru-person)
"""
import json
import os
import subprocess
import sys

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'public', 'footage')
ROOT = os.path.join(BASE, 'slow')
W, H = 60, 130
FPS = 30


def diffs(path):
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', path, '-vf', f'scale={W}:{H},format=gray', '-f', 'rawvideo', '-'],
        check=True, capture_output=True).stdout
    n = len(raw) // (W * H)
    out = [0.0]
    for i in range(1, n):
        a = raw[(i - 1) * W * H:i * W * H]
        b = raw[i * W * H:(i + 1) * W * H]
        out.append(sum(abs(x - y) for x, y in zip(a, b)) / (W * H))
    return out


def spans(d, thr=0.25, gap=0.5, min_len=0.15):
    active = [v > thr for v in d]
    res = []
    start = None
    for i, a in enumerate(active + [False]):
        if a and start is None:
            start = i
        if not a and start is not None:
            res.append([start / FPS, i / FPS])
            start = None
    merged = []
    for s in res:
        if merged and s[0] - merged[-1][1] < gap:
            merged[-1][1] = s[1]
        else:
            merged.append(s)
    return [[round(a, 2), round(b, 2)] for a, b in merged if b - a >= min_len]


def main():
    args = sys.argv[1:]
    global ROOT
    thr = 0.25
    while args and args[0].startswith('--'):
        key, value = args.pop(0)[2:].split('=')
        if key == 'thr':
            thr = float(value)
        elif key == 'dir':
            ROOT = os.path.join(BASE, value)
    names = args or sorted(f[:-4] for f in os.listdir(ROOT) if f.endswith('.mp4'))
    for name in names:
        d = diffs(os.path.join(ROOT, name + '.mp4'))
        with open(os.path.join(ROOT, name + '.gesture-telemetry.json')) as f:
            taps = [round(e['tMs'] / 1000, 2) for e in json.load(f)['events']]
        print(name, 'taps', taps)
        for s in spans(d, thr=thr, gap=0.3 if thr < 0.1 else 0.5, min_len=0.05 if thr < 0.1 else 0.15):
            print(f'   move {s[0]:6.2f} - {s[1]:6.2f}  ({s[1] - s[0]:.2f}s)')


if __name__ == '__main__':
    main()
