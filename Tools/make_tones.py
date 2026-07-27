"""Synthesises the alarm tones bundled with the app.

Stdlib only — no numpy — so it runs anywhere with `uv run`.

Each tone is built from a short pattern repeated to fill ~29.5 s. The total
length is an exact multiple of the pattern period, so when the system loops the
file for a long-ringing alarm there is no seam or click at the wrap point.

Output is 16-bit mono WAV; `make_tones.sh` converts these to the .caf files the
app actually ships.
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 44100
TARGET_SECONDS = 29.5
OUT_DIR = os.path.join(os.path.dirname(__file__), "build")


# --------------------------------------------------------------------- helpers

def env_percussive(t, decay):
    """Struck-instrument envelope: instant attack, exponential decay."""
    attack = min(1.0, t / 0.004) if t < 0.004 else 1.0
    return attack * math.exp(-t * decay)


def env_soft(t, duration, rise=0.05, fall=0.12):
    """Gentle swell with eased edges, so tones never click on or off."""
    if t < rise:
        return 0.5 - 0.5 * math.cos(math.pi * t / rise)
    if t > duration - fall:
        remaining = (duration - t) / fall
        return max(0.0, 0.5 - 0.5 * math.cos(math.pi * remaining))
    return 1.0


def add_bell(buf, start, freq, duration, gain, decay=4.0, partials=None):
    """Additive bell: a few inharmonic partials over a percussive envelope."""
    if partials is None:
        # Ratios roughly following a struck metal bar — warm, not clangy.
        partials = [(1.0, 1.0), (2.01, 0.45), (2.99, 0.22), (4.21, 0.10)]

    start_i = int(start * SAMPLE_RATE)
    n = int(duration * SAMPLE_RATE)
    for i in range(n):
        if start_i + i >= len(buf):
            break
        t = i / SAMPLE_RATE
        amp = env_percussive(t, decay) * gain
        # Only bail out once the tail has actually decayed — the envelope is
        # legitimately zero during the attack ramp at t=0.
        if t > 0.01 and amp < 1e-5:
            break
        sample = 0.0
        for ratio, weight in partials:
            sample += weight * math.sin(2 * math.pi * freq * ratio * t)
        buf[start_i + i] += sample * amp


def add_tone(buf, start, freq, duration, gain, harmonics=(1.0, 0.3, 0.12)):
    """Sustained tone with a soft envelope — used for the calmer patterns."""
    start_i = int(start * SAMPLE_RATE)
    n = int(duration * SAMPLE_RATE)
    for i in range(n):
        if start_i + i >= len(buf):
            break
        t = i / SAMPLE_RATE
        amp = env_soft(t, duration) * gain
        sample = 0.0
        for h, weight in enumerate(harmonics, start=1):
            sample += weight * math.sin(2 * math.pi * freq * h * t)
        buf[start_i + i] += sample * amp


def add_sweep(buf, start, f0, f1, duration, gain):
    """Rising tone. Phase is integrated so the sweep stays continuous."""
    start_i = int(start * SAMPLE_RATE)
    n = int(duration * SAMPLE_RATE)
    phase = 0.0
    for i in range(n):
        if start_i + i >= len(buf):
            break
        t = i / SAMPLE_RATE
        freq = f0 + (f1 - f0) * (t / duration)
        phase += 2 * math.pi * freq / SAMPLE_RATE
        amp = env_soft(t, duration, rise=0.08, fall=0.25) * gain
        buf[start_i + i] += (math.sin(phase) + 0.25 * math.sin(2 * phase)) * amp


def render(pattern_fn, period):
    """Repeats `pattern_fn` every `period` seconds for the full file length."""
    repeats = max(1, int(round(TARGET_SECONDS / period)))
    total = period * repeats
    buf = [0.0] * int(total * SAMPLE_RATE)
    for r in range(repeats):
        pattern_fn(buf, r * period)
    return buf


def write_wav(name, buf):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")

    peak = max((abs(s) for s in buf), default=0.0)
    # Normalise to -1.5 dBFS. Alarms should be loud; headroom avoids clipping
    # once the system applies its own gain.
    scale = (0.84 / peak) if peak > 0 else 0.0

    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for s in buf:
            v = int(max(-1.0, min(1.0, s * scale)) * 32767)
            frames += struct.pack("<h", v)
        f.writeframes(bytes(frames))
    print(f"  {name}.wav  ({len(buf) / SAMPLE_RATE:.2f}s)")
    return path


# ---------------------------------------------------------------------- tones

def radiate(buf, t0):
    """Warm ascending triad, repeated — the signature tone."""
    for i, freq in enumerate([523.25, 659.25, 783.99]):   # C5 E5 G5
        add_bell(buf, t0 + i * 0.16, freq, 1.6, 0.55, decay=3.2)
    add_bell(buf, t0 + 0.62, 1046.50, 2.0, 0.40, decay=2.6)


def chime(buf, t0):
    """Soft two-note doorbell-style bell, long tail."""
    add_bell(buf, t0, 659.25, 2.4, 0.60, decay=2.0)
    add_bell(buf, t0 + 0.45, 523.25, 2.8, 0.55, decay=1.7)


def pulse(buf, t0):
    """Clean modern triple beep. Insistent without being shrill."""
    for i in range(3):
        add_tone(buf, t0 + i * 0.22, 880.0, 0.14, 0.55, harmonics=(1.0, 0.22))


def sunrise(buf, t0):
    """Slow rising sweep with a bell at the top — gentlest of the set."""
    add_sweep(buf, t0, 330.0, 660.0, 1.9, 0.42)
    add_bell(buf, t0 + 1.7, 880.0, 1.6, 0.34, decay=2.4)


def beacon(buf, t0):
    """Urgent double beep — the one to pick if you sleep through things."""
    add_tone(buf, t0, 987.77, 0.17, 0.62, harmonics=(1.0, 0.4, 0.18))
    add_tone(buf, t0 + 0.26, 1318.51, 0.17, 0.62, harmonics=(1.0, 0.4, 0.18))


TONES = [
    ("blur-radiate", radiate, 2.95),
    ("blur-chime", chime, 3.6875),
    ("blur-pulse", pulse, 1.475),
    ("blur-sunrise", sunrise, 4.2142857),
    ("blur-beacon", beacon, 1.475),
]


def main():
    print("Rendering tones…")
    for name, fn, period in TONES:
        write_wav(name, render(fn, period))

    # True silence. AlarmKit has no "no sound" option, so "No Tone" rings this.
    write_wav("blur-silent", [0.0] * int(TARGET_SECONDS * SAMPLE_RATE))
    print(f"\nWrote {len(TONES) + 1} files to {OUT_DIR}")


if __name__ == "__main__":
    main()
