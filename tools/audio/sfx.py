"""Synthesises the sound effects from data/sfx.json (stdlib only), so every sound can be made again.

Each sound is a few layers (sine/triangle/square/noise) with a pitch glide, an envelope and an optional vibrato.
The mix is normalised to the peak in sfx.json (styleguide: effects peak <= -3 dBFS).

  python -I tools/audio/sfx.py                     WAVs into build/audio/ (deterministic; checks the peak)
  python -I tools/audio/sfx.py --ffmpeg ffmpeg     also: Ogg Vorbis into assets/audio/sfx/ (never Opus: Godot
                                                   can't play it) and measure every Ogg with ffmpeg's ebur128;
                                                   fails if a true peak is above -3 dBFS. CI runs this before the
                                                   Godot import; the Oggs are build output, not in git.
"""
import json
import math
import os
import random
import re
import subprocess
import sys
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SPEC = json.load(open(os.path.join(ROOT, "data", "sfx.json"), encoding="utf-8"))
WAV_DIR = os.path.join(ROOT, "build", "audio")
OGG_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
PEAK_LIMIT_DBFS = -3.0


def layer(spec: dict, rate: int, rng: random.Random) -> tuple:
    """Returns (start sample, samples) for one layer."""
    n = max(1, int(spec["dur"] * rate))
    attack = max(1, int(spec.get("attack", 0.002) * rate))
    curve = float(spec.get("curve", 2.0))
    f0, f1 = float(spec["f0"]), float(spec["f1"])
    vib_hz, vib_depth = spec.get("vib", [0, 0])
    kind = spec["type"]
    out = []
    phase = 0.0
    lp = 0.0
    for i in range(n):
        p = i / n
        f = f0 * (f1 / f0) ** p  # exponential glide sounds even to the ear
        if vib_depth:
            f *= 2 ** (vib_depth * math.sin(math.tau * vib_hz * i / rate) / 12)
        if i < attack:
            env = i / attack
        else:
            env = (1.0 - (i - attack) / max(1, n - attack)) ** curve
        if kind == "noise":
            a = 1.0 - math.exp(-math.tau * f / rate)  # one-pole low-pass, cutoff glides
            lp += a * (rng.uniform(-1.0, 1.0) - lp)
            s = lp * 1.6
        else:
            phase = (phase + f / rate) % 1.0
            if kind == "sine":
                s = math.sin(math.tau * phase)
            elif kind == "triangle":
                s = 4.0 * abs(phase - 0.5) - 1.0
            elif kind == "square":
                s = 0.6 if phase < 0.5 else -0.6
            else:
                raise ValueError(f"unknown layer type {kind}")
        out.append(s * env * float(spec.get("gain", 1.0)))
    return int(spec.get("t", 0.0) * rate), out


def render(name: str, sound: dict, rate: int, peak_dbfs: float) -> list:
    rng = random.Random(name)  # stable per sound: same json, same samples
    parts = [layer(l, rate, rng) for l in sound["layers"]]
    total = max(start + len(s) for start, s in parts) + int(0.01 * rate)
    mix = [0.0] * total
    for start, s in parts:
        for i, v in enumerate(s):
            mix[start + i] += v
    fade = int(0.003 * rate)  # no clicks at the end
    for i in range(fade):
        mix[total - 1 - i] *= i / fade
    peak = max(abs(v) for v in mix) or 1.0
    gain = 10 ** (peak_dbfs / 20) / peak
    return [v * gain for v in mix]


def write_wav(path: str, samples: list, rate: int) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(int(max(-1.0, min(1.0, v)) * 32767).to_bytes(2, "little", signed=True) for v in samples))


def to_ogg_and_measure(ffmpeg: str, wav: str, ogg: str) -> float:
    subprocess.run([ffmpeg, "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    r = subprocess.run([ffmpeg, "-hide_banner", "-nostats", "-i", ogg, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True, check=True)
    summary = r.stderr[r.stderr.rfind("Summary:"):]
    m = re.search(r"True peak:\s*\n\s*Peak:\s*(-?[\d.]+|-inf)", summary)
    if not m:
        sys.exit(f"could not read the true peak of {ogg}:\n{summary}")
    return float(m.group(1)) if m.group(1) != "-inf" else -200.0


def main() -> None:
    rate = int(SPEC["rate"])
    ffmpeg = sys.argv[sys.argv.index("--ffmpeg") + 1] if "--ffmpeg" in sys.argv else ""
    os.makedirs(WAV_DIR, exist_ok=True)
    failures = []
    for name, sound in SPEC["sounds"].items():
        samples = render(name, sound, rate, float(SPEC["peak_dbfs"]))
        wav = os.path.join(WAV_DIR, f"{name}.wav")
        write_wav(wav, samples, rate)
        peak = 20 * math.log10(max(abs(v) for v in samples))
        line = f"{name:7s} {len(samples) / rate:5.2f} s  sample peak {peak:6.2f} dBFS"
        if ffmpeg:
            os.makedirs(OGG_DIR, exist_ok=True)
            true_peak = to_ogg_and_measure(ffmpeg, wav, os.path.join(OGG_DIR, f"{name}.ogg"))
            line += f"  ogg true peak {true_peak:6.2f} dBFS"
            if true_peak > PEAK_LIMIT_DBFS:
                failures.append(f"{name}: true peak {true_peak} dBFS > {PEAK_LIMIT_DBFS}")
        elif peak > PEAK_LIMIT_DBFS:
            failures.append(f"{name}: peak {peak:.2f} dBFS > {PEAK_LIMIT_DBFS}")
        print(line)
    if failures:
        sys.exit("loudness check failed:\n  " + "\n  ".join(failures))


if __name__ == "__main__":
    main()
