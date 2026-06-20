#!/usr/bin/env python3
"""
audio_endclip.py — detect the ElevenLabs v3 "synthesis-drop" end-clip.

The v3 TTS non-deterministically drops the last word's *audio* during
synthesis (Pattern A in docs/.../feedback_audio_end_clip). The 400ms tail-pad
in generate_audio.py cannot fix it — silence appended after a clipped word does
not restore the word. Soft-consonant endings reduce but do not eliminate it,
and reflections (which always end on the meaning-bearing word of a question)
can't use the story-style trailing-safety-phrase.

This module measures whether a clip's final word DECAYED to a natural release
(clean) or was CUT while still at speaking energy (clipped). It is the
detection half of the auto-regenerate guard: because the artifact is
non-deterministic, a flagged take is simply re-rendered (a fresh take is
almost always clean).

Metric — clip_score = RMS(final 30 ms of speech) / RMS(average speech):
  A clean ending decays well below average speaking energy in its last 30 ms
  (a vowel/consonant release). A clipped ending is cut while hot, so the final
  30 ms is still a large fraction of (or above) the average.

Calibrated 2026-06-18 on 5 kid reflections Adam ear-verified:
  CLIP: 1836 (1.39), 1839 (0.63), 1840 (0.56)
  OK:   1838 (0.21), 1837 (0.19)
  -> threshold 0.40 separates with margin (min clip 0.56 >> max ok 0.21).

USAGE
  python3 scripts/audio_endclip.py <audio.mp3> [--threshold 0.40] [--json]
"""
from __future__ import annotations

import argparse
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

DEFAULT_THRESHOLD = 0.40
SILENCE_FRAC = 0.04   # speech = windows above 4% of peak (ignores the tail-pad)
WIN_MS = 10
TAIL_MS = 30          # final-word release window


def _decode_pcm(mp3_path: str) -> tuple[list[int], int]:
    """Decode any audio file to mono 16 kHz PCM samples via ffmpeg."""
    tmp = tempfile.mktemp(suffix=".wav")
    try:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", mp3_path,
             "-ac", "1", "-ar", "16000", tmp],
            check=True,
        )
        w = wave.open(tmp, "rb")
        n = w.getnframes()
        sr = w.getframerate()
        samples = list(struct.unpack("<%dh" % n, w.readframes(n)))
        w.close()
        return samples, sr
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def _envelope(samples: list[int], sr: int, win_ms: int = WIN_MS) -> list[float]:
    win = int(sr * win_ms / 1000)
    env = []
    for i in range(0, len(samples) - win, win):
        seg = samples[i:i + win]
        env.append(math.sqrt(sum(s * s for s in seg) / len(seg)))
    return env


def clip_score(mp3_path: str) -> float:
    """Return the end-clip score (higher = more likely clipped). See module doc.

    Returns 0.0 for a file with no detectable speech (treated as not-clipped;
    the retry loop should not spin on a silent/odd file)."""
    samples, sr = _decode_pcm(mp3_path)
    env = _envelope(samples, sr)
    if not env:
        return 0.0
    peak = max(env)
    if peak <= 0:
        return 0.0
    thr = peak * SILENCE_FRAC
    speech_idx = [i for i, v in enumerate(env) if v > thr]
    if not speech_idx:
        return 0.0
    last = speech_idx[-1]
    speech = [env[i] for i in speech_idx]
    avg = sum(speech) / len(speech)
    if avg <= 0:
        return 0.0
    n_tail = max(1, TAIL_MS // WIN_MS)
    tail = env[max(0, last - n_tail + 1):last + 1]
    tail_rms = sum(tail) / len(tail)
    return tail_rms / avg


def is_clipped(mp3_path: str, threshold: float = DEFAULT_THRESHOLD) -> bool:
    return clip_score(mp3_path) > threshold


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio", help="path to an audio file (mp3/wav/...)")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    if not os.path.exists(args.audio):
        print(f"ABORT: not found: {args.audio}", file=sys.stderr)
        return 2
    score = clip_score(args.audio)
    clipped = score > args.threshold
    if args.json:
        import json
        print(json.dumps({"file": args.audio, "clip_score": round(score, 3),
                          "threshold": args.threshold, "clipped": clipped}))
    else:
        verdict = "CLIPPED" if clipped else "ok"
        print(f"{verdict:8} score={score:.2f} (thr {args.threshold})  {args.audio}")
    return 1 if clipped else 0


if __name__ == "__main__":
    sys.exit(main())
