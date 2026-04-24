#!/usr/bin/env python3
"""Complete Ruth (VOICE_RUTH_COMFORT) audio set.

Fills in every line type so Ruth has full parity with Hope/Shepherd/
Stillwater:
  - Reflections: all moods (not just weary)
  - Framings: every bibleStoryKey in biblical_figure_registry
  - Creative: all 8 moods × 3 lines each
  - Legacy RESP: all microResponses in pal_lines.json
  - Onboarding + preview lines

Skips files that already exist — safe to re-run after partial failures.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.join(ROOT, ".env")
OUT_DIR = os.path.join(ROOT, "assets/pal/audio/VOICE_RUTH_COMFORT")
RUTH_VOICE_ID = "jBpfuIE2acCO8z3wKNLl"
MODEL_ID = "eleven_v3"

api_key = None
with open(ENV) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.split("#", 1)[0].strip()
        if k.strip() == "ELEVENLABS_API_KEY":
            api_key = v
if not api_key:
    sys.exit("ELEVENLABS_API_KEY missing from .env")

os.makedirs(OUT_DIR, exist_ok=True)


def collect_lines():
    out, seen = [], set()

    def add(_id, text):
        if _id in seen:
            return
        seen.add(_id)
        out.append((_id, text))

    # All reflections (every mood)
    rl = json.load(open(os.path.join(ROOT, "assets/pal/pal_reflection_lines.json")))
    for mood, arr in rl.get("moods", {}).items():
        for r in arr:
            add(r["id"], r["text"])

    # Tone-biased reflections
    tbr_path = os.path.join(
        ROOT, "assets/pal/pal_tone_biased_reflection_lines.json"
    )
    if os.path.exists(tbr_path):
        tbr = json.load(open(tbr_path))
        # structure is moods -> {tone -> [lines]} or similar; handle flexibly
        for mood, tones in tbr.get("moods", {}).items():
            if isinstance(tones, dict):
                for tone, arr in tones.items():
                    for r in arr:
                        add(r["id"], r["text"])
            elif isinstance(tones, list):
                for r in tones:
                    add(r["id"], r["text"])

    # All framings (every bibleStoryKey)
    br = json.load(
        open(os.path.join(ROOT, "assets/stories/biblical_figure_registry.json"))
    )
    for e in br["entries"]:
        for f in e.get("framingLines", []):
            add(f["id"], f["text"])

    # Creative opening lines (all 8 moods × 3)
    co = json.load(open(os.path.join(ROOT, "assets/pal/creative_opening_lines.json")))
    for mood, arr in co.get("moods", {}).items():
        for l in arr:
            add(l["id"], l["text"])

    # Legacy RESP + onboarding + preview from pal_lines.json
    pl = json.load(open(os.path.join(ROOT, "assets/pal/pal_lines.json")))
    for mood, arr in pl.get("microResponses", {}).items():
        for l in arr:
            add(l["id"], l["text"])
    for l in pl.get("onboarding", []):
        add(l["id"], l["text"])
    for l in pl.get("preview", []):
        add(l["id"], l["text"])

    return out


def tts(line_id, text):
    out = os.path.join(OUT_DIR, f"{line_id}.mp3")
    if os.path.exists(out):
        return ("skip", line_id, 0)
    body = json.dumps(
        {
            "text": text,
            "model_id": MODEL_ID,
            "voice_settings": {
                "stability": 0.55,
                "similarity_boost": 0.75,
                "style": 0.10,
                "use_speaker_boost": True,
            },
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{RUTH_VOICE_ID}",
        data=body,
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = resp.read()
            with open(out, "wb") as f:
                f.write(data)
            return ("ok", line_id, len(data))
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="ignore")[:120]
        return ("fail", line_id, f"HTTP {e.code} {err}")
    except Exception as e:
        return ("fail", line_id, str(e)[:160])


def main():
    lines = collect_lines()
    print(f"Ruth complete-set: {len(lines)} unique line IDs")
    ok = skip = fail = 0
    start = time.time()
    for i, (line_id, text) in enumerate(lines, 1):
        status, lid, info = tts(line_id, text)
        if status == "ok":
            ok += 1
        elif status == "skip":
            skip += 1
        else:
            fail += 1
        # Compact progress: print every 20, plus all fails
        if i % 20 == 0 or status == "fail":
            elapsed = time.time() - start
            print(
                f"  [{i}/{len(lines)}] {status} {lid} "
                f"(ok={ok} skip={skip} fail={fail}, {elapsed:.0f}s)"
            )
    print(
        f"\nok={ok} skip={skip} fail={fail}  "
        f"total files: {len(os.listdir(OUT_DIR))}"
    )
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
