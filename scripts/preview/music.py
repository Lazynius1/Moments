#!/usr/bin/env python3
"""Música original para el vídeo de previsualización (sintetizada aquí, sin derechos de terceros).

Pop ligero a 116 BPM en La mayor (F#m – D – A – E). Intro suave con pad y arpegio mientras se
rasca el corazón; entra la batería y el bajo en DROP_AT segundos (la primera tarjeta) y cierra con
un acorde largo sobre el logo.

Uso: python3 scripts/preview/music.py <salida.wav> [duración_s] [drop_s]
Requiere numpy.
"""

import sys
import wave

import numpy as np

SR = 44100
BPM = 116
BEAT = 60 / BPM

OUT = sys.argv[1]
DURATION = float(sys.argv[2]) if len(sys.argv) > 2 else 28.7
DROP_AT = float(sys.argv[3]) if len(sys.argv) > 3 else 4.5
N = int(DURATION * SR)
t_all = np.arange(N) / SR
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(x, cutoff):
    """Filtro de un polo, suficiente para suavizar sierras."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def env(n, attack, release, total=None):
    total = total or n
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    f = freq * (1 + detune)
    return 2 * ((t * f) % 1) - 1


def add(buf, start, sig):
    i = int(round(start * SR))
    if i < 0:  # empieza antes del vídeo: se recorta el principio
        sig = sig[-i:]
        i = 0
    if i >= len(buf):
        return
    sig = sig[: len(buf) - i]
    buf[i: i + len(sig)] += sig


# Acordes (una redonda cada uno): F#m, D, A, E
CHORDS = [[54, 57, 61], [50, 54, 57], [57, 61, 64], [52, 56, 59]]
BASS = [42, 38, 45, 40]
BAR = 4 * BEAT
END_CHORD_AT = DURATION - 2.6

pad = np.zeros(N)
pluck = np.zeros(N)
bass = np.zeros(N)
kick = np.zeros(N)
clap = np.zeros(N)
hats = np.zeros(N)

# Rejilla de compases alineada para que uno empiece justo en DROP_AT.
bars_before = int(np.ceil(DROP_AT / BAR))
bar = 0
start = DROP_AT - bars_before * BAR
while start < END_CHORD_AT:
    chord = CHORDS[bar % 4]
    n = int(BAR * SR)
    # Pad: sierras desafinadas
    p = sum(saw(midi(m), n, d) for m in chord for d in (-0.004, 0.004)) / 6
    add(pad, start, p * env(n, 0.25, 0.3))
    # Arpegio de corcheas (subido una octava)
    notes = chord + [chord[0] + 12]
    for k in range(8):
        m = notes[[0, 1, 2, 3, 2, 1, 2, 3][k]] + 12
        ln = int(0.32 * SR)
        tt = np.arange(ln) / SR
        tone = np.sin(2 * np.pi * midi(m) * tt) + 0.3 * np.sin(4 * np.pi * midi(m) * tt)
        add(pluck, start + k * BEAT / 2, tone * np.exp(-tt * 9) * 0.5)
    if start >= DROP_AT - 0.01:
        # Bajo en corcheas
        for k in range(8):
            ln = int(BEAT / 2 * SR * 0.9)
            b = saw(midi(BASS[bar % 4]), ln) * env(ln, 0.005, 0.05)
            add(bass, start + k * BEAT / 2, b)
        # Bombo 1-2-3-4, palmas 2 y 4, charles en contratiempo
        for k in range(4):
            ln = int(0.35 * SR)
            tt = np.arange(ln) / SR
            f = 50 + 90 * np.exp(-tt * 28)
            add(kick, start + k * BEAT, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7))
            if k in (1, 3):
                ln2 = int(0.18 * SR)
                noise = rng.uniform(-1, 1, ln2) * np.exp(-np.arange(ln2) / SR * 22)
                add(clap, start + k * BEAT, noise)
            ln3 = int(0.05 * SR)
            hn = rng.uniform(-1, 1, ln3)
            hn = hn - lowpass(hn, 6000)
            add(hats, start + k * BEAT + BEAT / 2, hn * np.exp(-np.arange(ln3) / SR * 60))
    bar += 1
    start += BAR

# Subida antes del drop: ruido que crece
riser_len = int(1.6 * SR)
r = rng.uniform(-1, 1, riser_len) * np.linspace(0, 1, riser_len) ** 2
add(hats, DROP_AT - 1.6, (r - lowpass(r, 2500)) * 0.6)

# Acorde final sobre el logo
n = N - int(END_CHORD_AT * SR)
final = sum(saw(midi(m), n, d) for m in [57, 61, 64, 69] for d in (-0.004, 0.004)) / 8
add(pad, END_CHORD_AT, final * env(n, 0.02, 2.2) * 1.3)

pad = lowpass(pad, 1800)
bass = lowpass(bass, 500)

# Bombeo: el pad y el bajo se apartan con cada bombo tras el drop
duck = np.ones(N)
k = DROP_AT
while k < END_CHORD_AT:
    i = int(k * SR)
    ln = int(BEAT * SR)
    duck[i: i + ln] = np.minimum(duck[i: i + ln], 0.35 + 0.65 * np.linspace(0, 1, len(duck[i: i + ln])) ** 0.6)
    k += BEAT

mix = 0.45 * pad * duck + 0.30 * pluck + 0.55 * bass * duck + 0.9 * kick + 0.25 * clap + 0.18 * hats
mix *= env(N, 0.4, 1.2)
mix /= np.max(np.abs(mix)) + 1e-9
mix *= 0.9

# Estéreo con un poco de anchura en el pad y el arpegio
wide = 0.12 * (lowpass(pluck, 3000) - pad * 0.2)
left = np.clip(mix + wide, -1, 1)
right = np.clip(mix - wide, -1, 1)
data = (np.stack([left, right], axis=1) * 32767).astype(np.int16)
with wave.open(OUT, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data.tobytes())
print(f"Música: {OUT} ({DURATION:.1f} s, drop en {DROP_AT:.1f} s)")
