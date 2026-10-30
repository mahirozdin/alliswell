#!/usr/bin/env python3
"""
The film's music bed (ADR-0061), composed here rather than licensed: a calm
ambient piece in D major, synthesised from sine partials so the project owns
it outright and anyone can regenerate the exact file.

    python3 media/hyperframes/scripts/music.py [seconds] [out.wav]

Deterministic: a fixed seed, no clock, no input. Output is 48 kHz 16-bit
stereo WAV, written to assets/audio/film-bed.wav by default.
"""
import math
import os
import sys
import wave

import numpy as np

SR = 48000
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 56.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, '..', 'assets', 'audio', 'film-bed.wav')
rng = np.random.default_rng(20261030)

N = int(SR * SECONDS)
t = np.arange(N) / SR
left = np.zeros(N)
right = np.zeros(N)

BPM = 70.0
BEAT = 60.0 / BPM
CHORD_LEN = 8 * BEAT  # two bars per chord


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# D major, at dusk: Dmaj9, Bm9, Gmaj7#11, A6sus, then a lift to Em9 before home.
CHORDS = [
    [50, 57, 62, 66, 69, 76],  # Dmaj9
    [47, 54, 61, 62, 66, 73],  # Bm9
    [43, 50, 57, 61, 66, 71],  # Gmaj7#11
    [45, 52, 59, 62, 66, 71],  # A6sus
    [50, 57, 62, 66, 69, 76],  # Dmaj9
    [40, 47, 54, 59, 62, 66],  # Em9
    [43, 50, 59, 62, 66, 69],  # Gmaj9
    [45, 52, 57, 61, 64, 69],  # A (home)
]


def envelope(length, attack, release):
    env = np.ones(length)
    a = min(int(attack * SR), length)
    r = min(int(release * SR), length - a)
    if a:
        env[:a] = np.sin(np.linspace(0, math.pi / 2, a)) ** 2
    if r:
        env[length - r :] *= np.cos(np.linspace(0, math.pi / 2, r)) ** 2
    return env


def pad_voice(freq, length, detune_cents):
    tt = np.arange(length) / SR
    out = np.zeros(length)
    for d in (-detune_cents, detune_cents):
        f = freq * 2 ** (d / 1200)
        phase = rng.uniform(0, 2 * math.pi)
        for n, amp in ((1, 1.0), (2, 0.32), (3, 0.14), (4, 0.06)):
            out += amp * np.sin(2 * math.pi * f * n * tt + phase * n)
    return out


# Pads: overlapping chords with long swells.
for i in range(int(math.ceil(SECONDS / CHORD_LEN)) + 1):
    chord = CHORDS[i % len(CHORDS)]
    start = int(i * CHORD_LEN * SR)
    length = int((CHORD_LEN + 2.5) * SR)
    if start >= N:
        break
    length = min(length, N - start)
    env = envelope(length, 2.2, 2.6)
    for k, note in enumerate(chord):
        level = 0.05 if k == 0 else 0.032
        voice = pad_voice(hz(note), length, 6 + k) * env * level
        pan = 0.5 + 0.35 * math.sin(k * 1.7)
        left[start : start + length] += voice * (1 - pan) * 1.2
        right[start : start + length] += voice * pan * 1.2

# Sub bass: the root, softly.
for i in range(int(math.ceil(SECONDS / CHORD_LEN)) + 1):
    root = CHORDS[i % len(CHORDS)][0] - 12
    start = int(i * CHORD_LEN * SR)
    if start >= N:
        break
    length = min(int(CHORD_LEN * SR), N - start)
    tt = np.arange(length) / SR
    bass = np.sin(2 * math.pi * hz(root) * tt) * envelope(length, 0.8, 1.6) * 0.09
    left[start : start + length] += bass
    right[start : start + length] += bass


# Bells: a sparse arpeggio of chord tones, an octave up, with soft decays.
def bell(freq, length):
    tt = np.arange(length) / SR
    decay = np.exp(-tt * 2.4)
    tone = np.sin(2 * math.pi * freq * tt) + 0.28 * np.sin(2 * math.pi * freq * 2.01 * tt) * np.exp(-tt * 5)
    attack = np.minimum(1.0, tt / 0.006)
    return tone * decay * attack


PATTERN = [0, None, 2, 3, None, 4, 2, None, 5, None, 3, 4, None, 2, None, None]
step = BEAT / 2
intro = 4.0  # the bells enter after the opening title settles
outro = SECONDS - 5.0
s = 0
while True:
    at = intro + s * step
    if at >= outro:
        break
    idx = PATTERN[s % len(PATTERN)]
    chord = CHORDS[int(at // CHORD_LEN) % len(CHORDS)]
    if idx is not None and rng.uniform() > 0.18:
        note = chord[idx % len(chord)] + 12
        start = int(at * SR)
        length = min(int(2.8 * SR), N - start)
        b = bell(hz(note), length) * (0.030 + 0.012 * rng.uniform())
        pan = 0.5 + 0.3 * math.sin(s * 0.9)
        left[start : start + length] += b * (1 - pan)
        right[start : start + length] += b * pan
    s += 1


# Reverb: a decaying noise impulse, convolved in the frequency domain.
def reverb(signal, seconds=3.2, seed=1):
    r = np.random.default_rng(seed)
    length = int(seconds * SR)
    tt = np.arange(length) / SR
    impulse = r.standard_normal(length) * np.exp(-tt * 2.1)
    impulse[: int(0.012 * SR)] = 0
    size = 1 << int(math.ceil(math.log2(len(signal) + length)))
    wet = np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(impulse, size), size)[: len(signal)]
    return wet / (np.max(np.abs(wet)) + 1e-9)


dry_l, dry_r = left.copy(), right.copy()
wet_l, wet_r = reverb(dry_l, seed=11), reverb(dry_r, seed=12)
peak_dry = max(np.max(np.abs(dry_l)), np.max(np.abs(dry_r)))
left = dry_l + wet_l * peak_dry * 0.55
right = dry_r + wet_r * peak_dry * 0.55

# Master: fades, gentle soft clip, normalise to -3 dBFS.
fade = envelope(N, 2.0, 3.5)
left *= fade
right *= fade
peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
left, right = left / peak, right / peak
left, right = np.tanh(left * 1.2) / np.tanh(1.2), np.tanh(right * 1.2) / np.tanh(1.2)
gain = 10 ** (-3 / 20)
stereo = np.stack([left, right], axis=1) * gain

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with wave.open(OUT, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype('<i2').tobytes())
print(f'wrote {OUT} ({SECONDS:.0f} s)')
