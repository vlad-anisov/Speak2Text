#!/usr/bin/env python3
"""Synthesizes the soft start/stop sounds into Resources/start.wav and Resources/stop.wav (stdlib only).

start: two short rising marimba-like notes, stop: the same two notes falling.
Each note is a sine with a faint 2nd partial, 6 ms linear attack and an exponential decay that is
faded to exactly zero at the end, so there are no clicks. Peak level is kept low (~0.30).
"""
import math, os, struct, wave

RATE = 44100
NOTE_MS = 50          # note spacing; each note rings NOTE_MS + OVERLAP_MS, ~120 ms in total
OVERLAP_MS = 20
PEAK = 0.30

def note(freq, ms):
    n = int(RATE * ms / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.006) * math.exp(-t * 28)          # attack, then marimba-like decay
        fade = min(1.0, (n - 1 - i) / (RATE * 0.012))           # fade to zero at the end
        s = math.sin(2 * math.pi * freq * t) + 0.18 * math.sin(2 * math.pi * 2 * freq * t) * math.exp(-t * 40)
        out.append(s * env * fade)
    return out

def blip(f1, f2):
    a, b = note(f1, NOTE_MS + OVERLAP_MS), note(f2, NOTE_MS + OVERLAP_MS)
    shift = int(RATE * NOTE_MS / 1000)
    out = [0.0] * (shift + len(b))
    for i, v in enumerate(a): out[i] += v
    for i, v in enumerate(b): out[shift + i] += v
    m = max(abs(v) for v in out)
    return [v / m * PEAK for v in out]

def save(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in samples))
    print(f"{path}: {len(samples) / RATE * 1000:.0f} ms, peak {max(abs(v) for v in samples):.2f}")

if __name__ == "__main__":
    res = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
    E5, A5 = 659.26, 880.00
    save(os.path.join(res, "start.wav"), blip(E5, A5))
    save(os.path.join(res, "stop.wav"), blip(A5, E5))
