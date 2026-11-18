"""Generates the game's chiptune sound effects and music. Python 3 stdlib only.

Run from the project root:
    python tools/gen_audio.py
Writes mono 16-bit 22050 Hz WAVs into assets/audio/sfx/ and assets/audio/music/.
Then re-import in Godot (open the editor, or run `godot --headless --path . --import`).

Every sound is built from a few simple voices (square, triangle, sine, noise) with
envelopes and pitch slides. Tweak a function below and re-run to change a sound.
"""

import math
import random
import struct
import wave
from pathlib import Path
from typing import Callable

Buffer = list[float]

RATE = 22050
SFX_PEAK = 0.7  # every file is normalised to this peak (1.0 = full scale)...
SFX_RMS = 0.25  # ...unless that would make its average loudness higher than this
MUSIC_PEAK = 0.75
MUSIC_RMS = 0.25
ROOT = Path(__file__).resolve().parent.parent / "assets" / "audio"

_rng = random.Random(1234)  # fixed seed so re-running gives the same files


# --- Building blocks --------------------------------------------------------

def silence(seconds: float) -> Buffer:
    return [0.0] * int(seconds * RATE)


def note_freq(name: str) -> float:
    """'A4' -> 440.0, 'C#5' -> 554.37. Octave is the last character."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semitone = names[name[0]]
    if "#" in name:
        semitone += 1
    elif "b" in name[1:]:
        semitone -= 1
    octave = int(name[-1])
    midi = 12 * (octave + 1) + semitone
    return 440.0 * 2 ** ((midi - 69) / 12)


def _wave_sample(kind: str, phase: float, duty: float) -> float:
    """One sample of a periodic wave. phase is in cycles (0..1)."""
    p = phase % 1.0
    if kind == "square":
        return 1.0 if p < duty else -1.0
    if kind == "triangle":
        return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    raise ValueError(kind)


def envelope(i: int, n: int, attack: float, release: float) -> float:
    """Linear attack, flat body, linear release that reaches 0 on the last sample."""
    a = int(attack * RATE)
    r = int(release * RATE)
    if a > 0 and i < a:
        return i / a
    if r > 0 and i >= n - r:
        return max(0.0, (n - 1 - i) / r)
    return 1.0


def tone(seconds: float, f0: float, f1: float | None = None, kind: str = "square", vol: float = 0.5,
         duty: float = 0.5, attack: float = 0.004, release: float = 0.03, decay: float = 0.0,
         vibrato: float = 0.0, vibrato_rate: float = 6.0) -> Buffer:
    """A pitched voice sliding exponentially from f0 to f1.
    decay > 0 adds an exponential fade (bigger = faster) on top of the envelope."""
    f1 = f0 if f1 is None else f1
    n = int(seconds * RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = i / max(n - 1, 1)
        freq = f0 * (f1 / f0) ** k
        if vibrato:
            freq *= 1.0 + vibrato * math.sin(2 * math.pi * vibrato_rate * t)
        phase += freq / RATE
        amp = vol * envelope(i, n, attack, release) * math.exp(-decay * t)
        out[i] = amp * _wave_sample(kind, phase, duty)
    return out


def noise(seconds: float, vol: float = 0.4, cutoff: float = 0.3, cutoff_end: float | None = None,
          attack: float = 0.002, release: float = 0.03, decay: float = 0.0) -> Buffer:
    """White noise through a one-pole low-pass. cutoff is 0..1 (1 = no filtering);
    it can sweep linearly to cutoff_end for whooshes."""
    cutoff_end = cutoff if cutoff_end is None else cutoff_end
    n = int(seconds * RATE)
    out = [0.0] * n
    smooth = 0.0
    for i in range(n):
        k = i / max(n - 1, 1)
        c = cutoff + (cutoff_end - cutoff) * k
        smooth += c * (_rng.uniform(-1.0, 1.0) - smooth)
        amp = vol * envelope(i, n, attack, release) * math.exp(-decay * i / RATE)
        out[i] = amp * smooth
    return out


def mix_into(buf: Buffer, sound: Buffer, at_seconds: float = 0.0) -> Buffer:
    """Adds sound into buf starting at at_seconds, growing buf if needed."""
    start = int(at_seconds * RATE)
    end = start + len(sound)
    if end > len(buf):
        buf.extend([0.0] * (end - len(buf)))
    for i, s in enumerate(sound):
        buf[start + i] += s
    return buf


def sequence(parts: list[tuple[float, Buffer]]) -> Buffer:
    """parts = [(at_seconds, sound), ...] mixed into one buffer."""
    buf: Buffer = []
    for at, sound in parts:
        mix_into(buf, sound, at)
    return buf


def normalise(buf: Buffer, peak: float, rms: float) -> Buffer:
    """Scales buf so its peak is `peak`, or quieter if its RMS would go above `rms`
    (square waves are loud for their peak)."""
    top = max((abs(s) for s in buf), default=0.0)
    if top == 0.0:
        return buf
    level = math.sqrt(sum(s * s for s in buf) / len(buf))
    gain = min(peak / top, rms / level)
    return [s * gain for s in buf]


def write_wav(path: Path, buf: Buffer) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in buf)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(frames)


# --- Sound effects ----------------------------------------------------------

def sfx_till() -> Buffer:
    return sequence([
        (0.0, noise(0.12, vol=0.8, cutoff=0.25, cutoff_end=0.05, release=0.08, decay=18)),
        (0.0, tone(0.1, 140, 60, "triangle", vol=0.6, release=0.06)),
    ])


def sfx_water() -> Buffer:
    parts = [(0.0, noise(0.35, vol=0.35, cutoff=0.5, cutoff_end=0.15, attack=0.02, release=0.2))]
    for i in range(5):
        f = _rng.uniform(700, 1100)
        parts.append((0.03 + i * 0.055, tone(0.05, f, f * 1.6, "sine", vol=0.35, release=0.03)))
    return sequence(parts)


def sfx_plant() -> Buffer:
    return sequence([
        (0.0, tone(0.09, 260, 620, "triangle", vol=0.7, release=0.05)),
        (0.0, noise(0.05, vol=0.3, cutoff=0.2, release=0.04)),
    ])


def sfx_harvest() -> Buffer:
    notes = ["C6", "E6", "G6"]
    return sequence([(i * 0.06, tone(0.1, note_freq(n), kind="square", duty=0.25, vol=0.4, release=0.05))
                     for i, n in enumerate(notes)])


def sfx_sell() -> Buffer:
    # Classic two-note coin.
    return sequence([
        (0.0, tone(0.07, note_freq("B5"), kind="square", duty=0.5, vol=0.35, release=0.01)),
        (0.07, tone(0.3, note_freq("E6"), kind="square", duty=0.5, vol=0.35, release=0.2, decay=5)),
    ])


def sfx_buy() -> Buffer:
    return sequence([
        (0.0, tone(0.05, note_freq("G5"), kind="square", duty=0.25, vol=0.35, release=0.01)),
        (0.05, tone(0.14, note_freq("C6"), kind="square", duty=0.25, vol=0.35, release=0.1)),
    ])


def sfx_error() -> Buffer:
    return sequence([
        (0.0, tone(0.09, 196, kind="square", duty=0.5, vol=0.3, release=0.02)),
        (0.11, tone(0.14, 147, kind="square", duty=0.5, vol=0.3, release=0.06)),
    ])


def sfx_sword_swing() -> Buffer:
    return noise(0.18, vol=0.9, cutoff=0.05, cutoff_end=0.45, attack=0.04, release=0.1)


def sfx_slime_hit() -> Buffer:
    return sequence([
        (0.0, tone(0.14, 420, 140, "triangle", vol=0.7, release=0.06, vibrato=0.08, vibrato_rate=40)),
        (0.0, noise(0.06, vol=0.5, cutoff=0.4, release=0.04)),
    ])


def sfx_slime_die() -> Buffer:
    return sequence([
        (0.0, tone(0.45, 700, 70, "square", duty=0.25, vol=0.35, release=0.15, vibrato=0.12, vibrato_rate=18)),
        (0.0, noise(0.12, vol=0.4, cutoff=0.5, cutoff_end=0.1, release=0.08)),
    ])


def sfx_crop_eaten() -> Buffer:
    parts = []
    for i in range(3):
        parts.append((i * 0.09, noise(0.06, vol=0.7, cutoff=0.35, release=0.04, decay=20)))
    parts.append((0.0, tone(0.3, 220, 90, "triangle", vol=0.35, release=0.12)))
    return sequence(parts)


def sfx_night_start() -> Buffer:
    notes = ["A4", "F4", "D4", "A3"]
    parts = [(i * 0.22, tone(0.4, note_freq(n), kind="triangle", vol=0.6, release=0.2, vibrato=0.01))
             for i, n in enumerate(notes)]
    parts.append((0.66, tone(0.6, note_freq("A2"), kind="square", duty=0.5, vol=0.12, release=0.4)))
    return sequence(parts)


def sfx_day_start() -> Buffer:
    notes = ["C5", "E5", "G5", "C6"]
    parts = [(i * 0.1, tone(0.3 if i == 3 else 0.12, note_freq(n), kind="square", duty=0.25,
                            vol=0.35, release=0.2 if i == 3 else 0.05))
             for i, n in enumerate(notes)]
    return sequence(parts)


def sfx_win() -> Buffer:
    melody = [("C5", 0.12), ("E5", 0.12), ("G5", 0.12), ("C6", 0.3), ("G5", 0.12), ("C6", 0.7)]
    parts = []
    t = 0.0
    for name, length in melody:
        parts.append((t, tone(length, note_freq(name), kind="square", duty=0.25, vol=0.35,
                              release=min(0.3, length * 0.5))))
        t += length
    parts.append((0.66, tone(0.82, note_freq("C4"), kind="triangle", vol=0.5, release=0.4)))
    parts.append((0.66, tone(0.82, note_freq("E4"), kind="triangle", vol=0.35, release=0.4)))
    return sequence(parts)


def sfx_ui_select() -> Buffer:
    return tone(0.05, note_freq("A5"), note_freq("E6"), "square", duty=0.25, vol=0.3, release=0.02)


# --- Music ------------------------------------------------------------------

def kick(vol: float) -> Buffer:
    return tone(0.12, 130, 45, "sine", vol=vol, attack=0.002, release=0.08)


def hat(vol: float) -> Buffer:
    return noise(0.04, vol=vol, cutoff=1.0, release=0.03, decay=40)


Bar = list[tuple[str | None, float]]


def render_song(bpm: float, bars: int, melody: list[Bar], chords: list[list[str]],
                bass_pattern: list[tuple[float, int, int, float]], melody_voice: tuple[str, float, float],
                arp_vol: float, kick_beats: list[float], hat_beats: list[float], hat_vol: float) -> Buffer:
    """melody = list of bars, each a list of (note or None, beats).
    chords = one chord (list of note names, root first) per bar.
    bass_pattern = (beat, chord tone index, octave shift, beats) tuples within a bar.
    Every note ends with a release before the loop end, so the loop seam is silent."""
    beat = 60.0 / bpm
    bar_len = 4 * beat
    total = bars * bar_len
    buf = silence(total)
    kind, duty, vol = melody_voice

    for bar in range(bars):
        start = bar * bar_len
        # Melody
        t = start
        for name, beats in melody[bar]:
            if name is not None:
                mix_into(buf, tone(beats * beat * 0.95, note_freq(name), kind=kind, duty=duty, vol=vol,
                                   release=min(0.08, beats * beat * 0.4), vibrato=0.006), t)
            t += beats * beat
        chord = chords[bar]
        # Bass (triangle, two octaves under the chord root)
        for at, index, octave, beats in bass_pattern:
            name = chord[index]
            freq = note_freq(name) / 4 * (2 ** octave)
            mix_into(buf, tone(beats * beat * 0.9, freq, kind="triangle", vol=0.45, release=0.04),
                     start + at * beat)
        # Quiet arpeggio of the chord in eighth notes
        if arp_vol > 0:
            for step in range(8):
                name = chord[step % len(chord)]
                mix_into(buf, tone(beat * 0.45, note_freq(name), kind="square", duty=0.125, vol=arp_vol,
                                   release=0.04), start + step * beat / 2)
        # Percussion
        for b in kick_beats:
            mix_into(buf, kick(0.5), start + b * beat)
        for b in hat_beats:
            mix_into(buf, hat(hat_vol), start + b * beat)

    del buf[int(total * RATE):]  # drop anything that spilled past the loop end
    fade = int(0.005 * RATE)  # tiny fade so the last sample is exactly 0
    for i in range(fade):
        buf[-1 - i] *= i / fade
    return buf


def music_day() -> Buffer:
    a = [
        [("E5", 1), ("G5", 1), ("C6", 1.5), ("G5", 0.5)],
        [("A5", 1), ("G5", 1), ("E5", 2)],
        [("F5", 1), ("A5", 1), ("C6", 1), ("A5", 1)],
        [("G5", 1.5), ("F5", 0.5), ("E5", 1), ("D5", 1)],
    ]
    b = [
        [("E5", 0.5), ("F5", 0.5), ("G5", 1), ("E5", 1), ("C5", 1)],
        [("A4", 1), ("C5", 1), ("E5", 2)],
        [("F5", 0.5), ("E5", 0.5), ("D5", 1), ("C5", 1), ("A4", 1)],
        [("B4", 1), ("D5", 1), ("G5", 2)],
    ]
    ending = a[:3] + [[("D5", 1), ("E5", 1), ("D5", 1), ("B4", 1)]]
    melody = a + b + ending
    progression = [["C4", "E4", "G4"], ["A3", "C4", "E4"], ["F3", "A3", "C4"], ["G3", "B3", "D4"]]
    chords = progression * 3
    bass = [(0, 0, 0, 1), (1, 2, 0, 1), (2, 0, 0, 1), (3, 2, 0, 1)]
    return render_song(bpm=120, bars=12, melody=melody, chords=chords, bass_pattern=bass,
                       melody_voice=("square", 0.25, 0.22), arp_vol=0.05, kick_beats=[0, 2],
                       hat_beats=[0.5, 1.5, 2.5, 3.5], hat_vol=0.08)


def music_night() -> Buffer:
    melody = [
        [("A4", 2), ("C5", 1), ("B4", 1)],
        [("A4", 2), ("F4", 2)],
        [("D5", 1.5), ("C5", 0.5), ("A4", 2)],
        [("G#4", 2), ("B4", 1), ("E5", 1)],
        [("E5", 2), ("D5", 1), ("C5", 1)],
        [("C5", 1), ("A4", 1), ("F4", 2)],
        [("F4", 1), ("A4", 1), ("D5", 1), ("F5", 1)],
        [("E5", 2), ("G#4", 2)],
        [("A4", 1), ("C5", 1), ("F5", 2)],
        [("E5", 1), ("D5", 1), ("B4", 1), ("G#4", 1)],
    ]
    am = ["A3", "C4", "E4"]
    f = ["F3", "A3", "C4"]
    dm = ["D4", "F4", "A4"]
    e = ["E3", "G#3", "B3"]
    chords = [am, f, dm, e, am, f, dm, e, f, e]
    # Pulsing eighth-note bass on the root: keeps the tension up.
    bass = [(i * 0.5, 0, 0 if i % 4 else 1, 0.5) for i in range(8)]
    return render_song(bpm=100, bars=10, melody=melody, chords=chords, bass_pattern=bass,
                       melody_voice=("square", 0.5, 0.16), arp_vol=0.0, kick_beats=[0, 0.75, 2, 2.75],
                       hat_beats=[i * 0.5 + 0.25 for i in range(8)], hat_vol=0.05)


SFX: dict[str, Callable[[], Buffer]] = {
    "till": sfx_till,
    "water": sfx_water,
    "plant": sfx_plant,
    "harvest": sfx_harvest,
    "sell": sfx_sell,
    "buy": sfx_buy,
    "error": sfx_error,
    "sword_swing": sfx_sword_swing,
    "slime_hit": sfx_slime_hit,
    "slime_die": sfx_slime_die,
    "crop_eaten": sfx_crop_eaten,
    "night_start": sfx_night_start,
    "day_start": sfx_day_start,
    "win": sfx_win,
    "ui_select": sfx_ui_select,
}

MUSIC: dict[str, Callable[[], Buffer]] = {
    "day": music_day,
    "night": music_night,
}


def main() -> None:
    total = 0
    for name, make in SFX.items():
        path = ROOT / "sfx" / (name + ".wav")
        buf = normalise(make(), SFX_PEAK, SFX_RMS)
        write_wav(path, buf)
        total += path.stat().st_size
        print("sfx   %-12s %.2fs" % (name, len(buf) / RATE))
    for name, make in MUSIC.items():
        path = ROOT / "music" / (name + ".wav")
        buf = normalise(make(), MUSIC_PEAK, MUSIC_RMS)
        write_wav(path, buf)
        total += path.stat().st_size
        print("music %-12s %.2fs" % (name, len(buf) / RATE))
    print("total %.2f MB" % (total / 1024 / 1024))


if __name__ == "__main__":
    main()
