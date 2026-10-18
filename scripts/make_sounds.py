#!/usr/bin/env python3
"""Synthesizes the soft start/stop sounds into Resources/start.wav and Resources/stop.wav (stdlib only).

start: two soft notes rising a fourth (B4 494 Hz -> E5 659 Hz); stop: the same two notes falling.
Each note is a pure sine plus a very quiet 2nd harmonic (-24 dB, dies faster), 20 ms raised-cosine attack and a smooth
exponential decay that is faded to exactly zero at the end (no clicks). No partials above 1.4 kHz.
Total length 200 ms, peak 0.13.
"""
import math, os, struct, wave

RATE = 44100
TOTAL_MS = 200
NOTE_START_MS = (0, 85)     # onsets of the two notes
NOTE_MS = 115               # each note rings this long
PEAK = 0.13
ATTACK = 0.020
DECAY = 16.0                # 1/s, exponential
H2 = 0.06                   # 2nd harmonic amplitude relative to the fundamental (-24 dB)
FADE = 0.025                # final fade to zero, s

def note(freq):
    n = int(RATE * NOTE_MS / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        att = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / ATTACK))
        env = att * math.exp(-t * DECAY)
        fade = min(1.0, (n - 1 - i) / (RATE * FADE))
        s = math.sin(2 * math.pi * freq * t) + H2 * math.sin(4 * math.pi * freq * t) * math.exp(-t * 20)
        out.append(s * env * fade)
    return out

def blip(f1, f2):
    out = [0.0] * int(RATE * TOTAL_MS / 1000)
    for f, onset in zip((f1, f2), NOTE_START_MS):
        o = int(RATE * onset / 1000)
        for i, v in enumerate(note(f)):
            if o + i < len(out): out[o + i] += v
    m = max(abs(v) for v in out)
    return [v / m * PEAK for v in out]

def save(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in samples))
    print(f"{path}: {len(samples) / RATE * 1000:.0f} ms, peak {max(abs(v) for v in samples):.3f}")

if __name__ == "__main__":
    res = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
    B4, E5 = 493.88, 659.26
    save(os.path.join(res, "start.wav"), blip(B4, E5))
    save(os.path.join(res, "stop.wav"), blip(E5, B4))
