# App Store preview videos

Remotion project that builds the WhoGaveWhat App Store app previews (886×1920, 30 fps, under 30 s) in English and Russian from real Simulator recordings.

## Variants

| Composition | Style | Length |
|---|---|---|
| `E-Kinetic-en/ru` | **Chosen.** Big kinetic headlines on navy/emerald cards alternate with full-bleed app footage; a real row from the screen lifts off at each payoff. Cut on the 112.5 bpm beat. | 27.6 s |
| `F-Calm-en/ru` | Calm alternative: title card, app footage with crossfades, end card. No headlines. | 23.1 s |
| `D-StoryMotion-en/ru` | Story with drawn schematic interludes (rejected: reads as an explainer). | |
| `A-Clean`, `B-Showcase`, `C-Story` | First drafts. | |

`src/variants/Kinetic.tsx` holds variant E: copy (`cards`), lift-off crops (`LIFTS`), source-time cuts (`addSegs` and the other segment lists) and the scene plan (`kineticPlan`).

## Setup

```sh
npm ci
npm run studio            # preview at http://localhost:3000
```

Large and generated inputs are not in git (see `.gitignore`):

| Path | How to get it |
|---|---|
| `public/footage/` | Record with `capture/record.sh` on an iPhone 17 Pro Simulator (follow the Fleet simulator-queue skill). Variants D–F use `story/` (`STORY=1`, slow animations, `SLOW≈6`). An archived copy of the footage used for the current renders is on MacPro in `~/.t3/userdata/attachments/whogavewhat-promo/source/footage/`. |
| `public/lift/` | `scripts/lift-crops.sh` (needs the footage). |
| `public/music-*.wav` | `node scripts/make-music.mjs` |
| `public/sfx-*.wav` | `node scripts/make-sfx.mjs` |
| `.agents/`, `.claude/` | Remotion agent skills, pinned in `skills-lock.json`: `npx skills add remotion-dev/skills`. |

## Render

```sh
./render.sh E-Kinetic-en E-Kinetic-ru    # → out/final/<id>.mp4
```

`render.sh` renders each composition and transcodes it to Apple's app preview spec: H.264 High@4.0 at a constant 11 Mbps, AAC 256 kbps 48 kHz, loudness normalised to −16 LUFS.

## Other scripts

- `scripts/stills.sh ID OUT.jpg FRAME...` puts stills side by side for a quick look.
- `scripts/review-packet.sh ROUND [VARIANT]` builds a contact sheet and stills for a review round in `review/`.
- `scripts/extract-taps.py` and `scripts/motion-spans.py` find tap times and moving spans in the recordings, used to cut the footage.
