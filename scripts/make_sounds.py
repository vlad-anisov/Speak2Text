#!/usr/bin/env python3
"""Synthesizes 10 start/stop sound variants (stdlib only).

For every variant NN-name:
  Resources/sounds/NN-name-start.wav, NN-name-stop.wav  - what the app plays;
  docs/sounds/NN-name.wav                               - start, 0.6 s of silence, stop (to audition one file per variant).
All sounds: mono 44.1 kHz, <= 250 ms, peak <= 0.15, smooth attack and a fade to exactly zero (no clicks),
no energy above ~3 kHz. Variant 01 "classic" is the original sound (two sine notes a fourth apart).
"""
import math, os, random, struct, wave

RATE = 44100
PEAK = 0.13
FADE = 0.025          # final fade to zero, s

def n_of(ms): return int(RATE * ms / 1000)

def finish(x, ms):
    """Pads/cuts to ms, fades the tail to zero."""
    n = n_of(ms)
    x = (x + [0.0] * n)[:n]
    f = int(RATE * FADE)
    for i in range(f): x[n - 1 - i] *= i / f
    return x

def mix(parts, ms):
    out = [0.0] * n_of(ms)
    for onset_ms, p in parts:
        o = n_of(onset_ms)
        for i, v in enumerate(p):
            if o + i < len(out): out[o + i] += v
    return out

def tone(freq, ms, partials=((1, 1.0, 0),), attack=0.01, decay=16.0, glide=None):
    """Sum of partials (ratio, amp, extra decay); optional glide=(f_end) exponential pitch glide."""
    n = n_of(ms); out = []; ph = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq if glide is None else freq * (glide / freq) ** min(1.0, t / (ms / 1000))
        att = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / attack))
        s = 0.0
        for k, (r, a, d) in enumerate(partials):
            ph[k] += 2 * math.pi * f * r / RATE
            s += a * math.sin(ph[k]) * math.exp(-t * d)
        out.append(s * att * math.exp(-t * decay))
    return out

def noise(ms, lp=2500.0, hp=0.0, seed=1):
    """Band-limited noise (one-pole low-pass, optional high-pass)."""
    r = random.Random(seed); y = 0.0; z = 0.0; out = []
    a = 1 - math.exp(-2 * math.pi * lp / RATE)
    b = 1 - math.exp(-2 * math.pi * hp / RATE) if hp else 0
    for _ in range(n_of(ms)):
        y += a * (r.uniform(-1, 1) - y)
        z += b * (y - z) if hp else 0
        out.append(y - z if hp else y)
    return out

def shape(x, env):
    n = len(x)
    return [v * env(i / max(1, n - 1)) for i, v in enumerate(x)]

def norm(x, peak=PEAK):
    m = max(abs(v) for v in x)
    return [v / m * peak for v in x]

# ---- variants: each returns (start, stop) sample lists -------------------------------------------------------

def classic():
    B4, E5 = 493.88, 659.26
    def blip(f1, f2):
        note = lambda f: tone(f, 115, ((1, 1.0, 0), (2, 0.06, 20)), attack=0.020, decay=16.0)
        return norm(finish(mix([(0, note(f1)), (85, note(f2))], 200), 200))
    return blip(B4, E5), blip(E5, B4)

def pluck():
    p = lambda f: norm(finish(tone(f, 200, ((1, 1, 0), (2, 0.35, 14), (3, 0.12, 25)), attack=0.004, decay=17), 200))
    return p(440.0), p(293.66)

def marimba():
    def m(f1, f2):
        n = lambda f: tone(f, 130, ((1, 1, 0), (4, 0.28, 30)), attack=0.003, decay=22)
        return norm(finish(mix([(0, n(f1)), (70, n(f2))], 210), 210))
    return m(659.26, 987.77), m(987.77, 659.26)

def glass():
    g = lambda f: norm(finish(tone(f, 240, ((1, 1, 0), (2.76, 0.30, 9), (5.4, 0.08, 18)), attack=0.002, decay=11), 240))
    return g(1046.5), g(783.99)

def wood():
    def w(f):
        body = tone(f, 150, ((1, 1, 0), (2.3, 0.2, 25)), attack=0.002, decay=30, glide=f * 0.8)
        tick = shape(noise(25, lp=1400, seed=3), lambda u: (1 - u) ** 3)
        return norm(finish(mix([(0, body), (0, [v * 0.5 for v in tick])], 160), 160))
    return w(230.0), w(165.0)

def chime():
    def c(f1, f2):
        n = lambda f: tone(f, 120, ((1, 1, 0), (2, 0.1, 25)), attack=0.012, decay=15)
        return norm(finish(mix([(0, n(f1)), (80, n(f2))], 210), 210))
    G4, E5 = 392.0, 659.26     # major sixth
    return c(G4, E5), c(E5, G4)

def pop():
    s = tone(330, 90, ((1, 1, 0),), attack=0.004, decay=30, glide=620)
    t = tone(620, 90, ((1, 1, 0),), attack=0.004, decay=30, glide=300)
    return norm(finish(s, 90)), norm(finish(t, 90))

def breath():
    def b(rise):
        x = noise(230, lp=2200, hp=300, seed=7)
        env = lambda u: math.sin(math.pi * u ** (1.5 if rise else 0.7)) ** 2   # start swells, stop fades away
        return norm(finish(shape(x, env), 230))
    return b(True), b(False)

def bell():
    b = lambda f: norm(finish(tone(f, 245, ((1, 1, 0), (2, 0.4, 8), (3, 0.12, 14), (4.1, 0.05, 20)), attack=0.004, decay=9), 245))
    return b(783.99), b(587.33)

def tick():
    t = lambda f: norm(finish(tone(f, 45, ((1, 1, 0),), attack=0.002, decay=70), 45))
    return t(1568.0), t(1175.0)

VARIANTS = [
    ("01-classic", classic), ("02-pluck", pluck), ("03-marimba", marimba), ("04-glass", glass), ("05-wood", wood),
    ("06-chime", chime), ("07-pop", pop), ("08-breath", breath), ("09-bell", bell), ("10-tick", tick),
]

def save(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in samples))

if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    res, docs = os.path.join(root, "Resources", "sounds"), os.path.join(root, "docs", "sounds")
    os.makedirs(res, exist_ok=True); os.makedirs(docs, exist_ok=True)
    for name, fn in VARIANTS:
        a, b = fn()
        for x in (a, b):
            assert max(abs(v) for v in x) <= 0.15 and len(x) / RATE <= 0.25, name
        save(os.path.join(res, f"{name}-start.wav"), a)
        save(os.path.join(res, f"{name}-stop.wav"), b)
        save(os.path.join(docs, f"{name}.wav"), a + [0.0] * n_of(600) + b)
        print(f"{name}: start {len(a)/RATE*1000:.0f} ms, stop {len(b)/RATE*1000:.0f} ms")
