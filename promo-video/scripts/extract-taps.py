#!/usr/bin/env python3
"""Writes src/taps.json: the taps agent-device logged while recording public/footage/story.

Each entry is {t, x, y} in source seconds and video pixels (886 px wide, the footage scaled to cover
886x1920), so StoryMotion can draw its own tap rings instead of the Simulator's touch dots.
Usage: python3 -I scripts/extract-taps.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SCALE = 886 / 402  # points to video pixels
Y_OFFSET = (874 * SCALE - 1920) / 2  # objectFit cover crops the top and bottom equally

out = {}
for name in sorted(os.listdir(os.path.join(ROOT, 'public', 'footage', 'story'))):
    if not name.endswith('.gesture-telemetry.json'):
        continue
    with open(os.path.join(ROOT, 'public', 'footage', 'story', name)) as f:
        events = json.load(f)['events']
    out[name.split('.')[0]] = [
        {'t': round(e['tMs'] / 1000, 3), 'x': round(e['x'] * SCALE), 'y': round(e['y'] * SCALE - Y_OFFSET)}
        for e in events if e['kind'] == 'tap'
    ]
with open(os.path.join(ROOT, 'src', 'taps.json'), 'w') as f:
    json.dump(out, f, indent=1)
print({k: len(v) for k, v in out.items()})
