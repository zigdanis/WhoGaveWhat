// Synthesizes the soundtrack from code, so no third-party music licence is involved.
// Usage: node scripts/make-music.mjs OUT.wav [seconds] [style]
// style "warm": felt-piano arpeggios, soft pad, light pulse (default)
// style "bright": faster plucks with a shaker, for the upbeat cut
import {mkdirSync, writeFileSync} from 'node:fs';
import {dirname} from 'node:path';

const out = process.argv[2] ?? 'public/music-warm.wav';
const seconds = Number(process.argv[3] ?? 30);
const style = process.argv[4] ?? 'warm';
const rate = 48000;
const n = Math.round(seconds * rate);
const L = new Float32Array(n);
const R = new Float32Array(n);

const bpm = style === 'bright' ? 112.5 : 96; // 112.5 bpm: a beat is exactly 16 frames at 30 fps
const beat = 60 / bpm;
const bar = beat * 4;
const midi = (m) => 440 * 2 ** ((m - 69) / 12);

// Cmaj9 - Am9 - Fmaj9 - G6/9 (one bar each), voiced around middle C.
const chords = [
  [48, 55, 59, 62, 64],
  [45, 52, 55, 59, 62],
  [41, 48, 52, 55, 57],
  [43, 50, 52, 57, 59],
];

let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

function add(buf, start, data, gain) {
  const s = Math.round(start * rate);
  for (let i = 0; i < data.length && s + i < n; i++) if (s + i >= 0) buf[s + i] += data[i] * gain;
}

// Felt-piano-ish tone: a few harmonics with fast attack and exponential decay.
function pluck(freq, dur, bright = 1) {
  const len = Math.round(dur * rate);
  const d = new Float32Array(len);
  const harm = [1, 0.45 * bright, 0.18 * bright, 0.08 * bright, 0.03];
  for (let i = 0; i < len; i++) {
    const t = i / rate;
    const env = Math.min(1, t / 0.006) * Math.exp(-t * (2.2 + freq / 900));
    let v = 0;
    for (let h = 0; h < harm.length; h++) v += harm[h] * Math.sin(2 * Math.PI * freq * (h + 1) * t * (1 + h * 0.0007)) * Math.exp(-t * h * 1.4);
    d[i] = v * env;
  }
  return d;
}

// Pad: detuned sines with slow attack and release.
function pad(freqs, dur) {
  const len = Math.round(dur * rate);
  const d = new Float32Array(len);
  for (let i = 0; i < len; i++) {
    const t = i / rate;
    const env = Math.min(1, t / 0.9) * Math.min(1, (dur - t) / 0.9);
    let v = 0;
    for (const f of freqs) {
      v += Math.sin(2 * Math.PI * f * t) + 0.6 * Math.sin(2 * Math.PI * f * 1.003 * t + 1) + 0.25 * Math.sin(2 * Math.PI * f * 2.001 * t);
    }
    d[i] = (v / freqs.length) * Math.max(0, env);
  }
  return d;
}

function kick(dur = 0.35) {
  const len = Math.round(dur * rate);
  const d = new Float32Array(len);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / rate;
    const f = 48 + 90 * Math.exp(-t * 30);
    ph += (2 * Math.PI * f) / rate;
    d[i] = Math.sin(ph) * Math.exp(-t * 9);
  }
  return d;
}

function shaker(dur = 0.07) {
  const len = Math.round(dur * rate);
  const d = new Float32Array(len);
  let prev = 0;
  for (let i = 0; i < len; i++) {
    const t = i / rate;
    const w = rnd() * 2 - 1;
    const hp = w - prev; // crude high-pass
    prev = w;
    d[i] = hp * Math.exp(-t * 60) * Math.min(1, t / 0.004);
  }
  return d;
}

const totalBars = Math.ceil(seconds / bar);
const endAt = seconds - 2.2; // last notes ring out
for (let b = 0; b < totalBars; b++) {
  const t0 = b * bar;
  if (t0 > endAt) break;
  const ch = chords[b % 4];
  const isLast = t0 + bar > endAt;
  // Pad, quieter in the first bar so the opening breathes.
  const p = pad(ch.slice(1, 4).map((m) => midi(m)), isLast ? seconds - t0 : bar + 0.4);
  add(L, t0, p, b === 0 ? 0.035 : 0.05);
  add(R, t0, p, b === 0 ? 0.035 : 0.05);
  // Bass note.
  const bass = pluck(midi(ch[0] - 12), bar * 1.1, 0.4);
  add(L, t0, bass, 0.22);
  add(R, t0, bass, 0.22);
  if (isLast) {
    // Final chord: a soft strum.
    ch.forEach((m, i) => {
      const pl = pluck(midi(m + 12), 2.4, 0.7);
      add(L, t0 + i * 0.045, pl, 0.07 * (i % 2 ? 0.8 : 1.1));
      add(R, t0 + i * 0.045, pl, 0.07 * (i % 2 ? 1.1 : 0.8));
    });
    break;
  }
  // Arpeggio: eighth notes up and down the chord an octave higher.
  const pattern = style === 'bright' ? [0, 2, 4, 3, 1, 3, 4, 2] : [1, 2, 4, 3, 2, 4, 3, 2];
  const steps = 8;
  for (let s = 0; s < steps; s++) {
    if (b === 0 && s < 2 && style !== 'bright') continue;
    const m = ch[pattern[s]] + 12;
    const tt = t0 + s * (bar / steps) + (s % 2 ? 0.012 : 0); // a touch of swing
    const pl = pluck(midi(m), 1.2, style === 'bright' ? 1 : 0.75);
    const g = (s % 2 ? 0.055 : 0.075) * (b === 0 ? 0.8 : 1);
    const pan = 0.5 + 0.35 * Math.sin(s * 1.3 + b);
    add(L, tt, pl, g * (1 - pan) * 2);
    add(R, tt, pl, g * pan * 2);
  }
  // Pulse from bar 2: a soft kick on 1 and 3, shaker on offbeats.
  if (b >= 1) {
    for (const q of [0, 2]) {
      const k = kick();
      add(L, t0 + q * beat, k, 0.12);
      add(R, t0 + q * beat, k, 0.12);
    }
    for (let e = 0; e < 8; e++) {
      if (style !== 'bright' && e % 2 === 0) continue;
      const sh = shaker();
      const g = style === 'bright' ? (e % 2 ? 0.05 : 0.025) : 0.03;
      add(L, t0 + e * (beat / 2), sh, g * 0.8);
      add(R, t0 + e * (beat / 2), sh, g * 1.2);
    }
  }
}

// Simple stereo reverb: four combs and two all-passes per side.
function reverb(x, delays, fb = 0.78, damp = 0.35) {
  const y = new Float32Array(n);
  for (const dms of delays) {
    const D = Math.round((dms / 1000) * rate);
    const buf = new Float32Array(D);
    let idx = 0;
    let lp = 0;
    for (let i = 0; i < n; i++) {
      const out = buf[idx];
      lp = out * (1 - damp) + lp * damp;
      buf[idx] = x[i] + lp * fb;
      idx = (idx + 1) % D;
      y[i] += out / delays.length;
    }
  }
  for (const dms of [5.0, 1.7]) {
    const D = Math.round((dms / 1000) * rate);
    const buf = new Float32Array(D);
    let idx = 0;
    for (let i = 0; i < n; i++) {
      const bo = buf[idx];
      const v = y[i] + bo * 0.5;
      buf[idx] = v;
      y[i] = bo - v * 0.5;
      idx = (idx + 1) % D;
    }
  }
  return y;
}
const wetL = reverb(L, [29.7, 37.1, 41.1, 43.7]);
const wetR = reverb(R, [31.3, 36.7, 40.3, 44.9]);

// Mix, fade the edges, normalise to -3 dBFS and write 16-bit WAV.
let peak = 0;
for (let i = 0; i < n; i++) {
  const t = i / rate;
  const fade = Math.min(1, t / 0.05) * Math.min(1, (seconds - t) / 1.2);
  L[i] = (L[i] * 0.8 + wetL[i] * 0.45) * fade;
  R[i] = (R[i] * 0.8 + wetR[i] * 0.45) * fade;
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const gain = 0.708 / peak;
const data = Buffer.alloc(44 + n * 4);
data.write('RIFF', 0);
data.writeUInt32LE(36 + n * 4, 4);
data.write('WAVEfmt ', 8);
data.writeUInt32LE(16, 16);
data.writeUInt16LE(1, 20);
data.writeUInt16LE(2, 22);
data.writeUInt32LE(rate, 24);
data.writeUInt32LE(rate * 4, 28);
data.writeUInt16LE(4, 32);
data.writeUInt16LE(16, 34);
data.write('data', 36);
data.writeUInt32LE(n * 4, 40);
for (let i = 0; i < n; i++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * gain)) * 32767), 44 + i * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * gain)) * 32767), 46 + i * 4);
}
mkdirSync(dirname(out), {recursive: true});
writeFileSync(out, data);
console.log(`wrote ${out}: ${seconds}s, ${style}, ${bpm} bpm`);
