// Synthesizes the soft sound accents for variant D's payoffs (price appears, row saved, "Even").
// Usage: node scripts/make-sfx.mjs   → public/sfx-chime.wav (a two-note bell) and public/sfx-pop.wav
import {mkdirSync, writeFileSync} from 'node:fs';

const rate = 48000;

function wav(path, samples) {
  const n = samples.length;
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
    const v = Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767);
    data.writeInt16LE(v, 44 + i * 4);
    data.writeInt16LE(v, 46 + i * 4);
  }
  mkdirSync('public', {recursive: true});
  writeFileSync(path, data);
}

function bell(freqs, dur, gain) {
  const n = Math.round(dur * rate);
  const out = new Float32Array(n);
  freqs.forEach(([f, start, amp]) => {
    const s0 = Math.round(start * rate);
    for (let i = s0; i < n; i++) {
      const t = (i - s0) / rate;
      const env = Math.min(1, t / 0.004) * Math.exp(-t * 7);
      out[i] += amp * env * (Math.sin(2 * Math.PI * f * t) + 0.35 * Math.sin(2 * Math.PI * f * 2.76 * t) * Math.exp(-t * 12));
    }
  });
  let peak = 0;
  for (const v of out) peak = Math.max(peak, Math.abs(v));
  return out.map((v) => (v / peak) * gain);
}

// E6 then B6: bright but soft, 0.7 s.
wav('public/sfx-chime.wav', bell([[1318.5, 0, 1], [1975.5, 0.07, 0.8]], 0.7, 0.5));
// A short low pop for small arrivals.
wav('public/sfx-pop.wav', bell([[660, 0, 1]], 0.25, 0.4));
console.log('wrote public/sfx-chime.wav, public/sfx-pop.wav');
