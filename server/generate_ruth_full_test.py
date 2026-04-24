#!/usr/bin/env python3
"""Generate Ruth (VOICE_RUTH_COMFORT) audio for the entire opening pool +
all prompts + weary reflections + transitions + David Anointed framings.

This makes the on-device test reliable: any random opening / prompt the
rotator picks will hit a Ruth audio file. Skips files that already exist.
"""
import json
import os
import sys
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.join(ROOT, ".env")
OUT_DIR = os.path.join(ROOT, "assets/pal/audio/VOICE_RUTH_COMFORT")
RUTH_VOICE_ID = "jBpfuIE2acCO8z3wKNLl"
MODEL_ID = "eleven_v3"

# Load .env
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
    out = []  # list of (id, text)
    seen = set()

    def add(_id, text):
        if _id in seen:
            return
        seen.add(_id)
        out.append((_id, text))

    # Openings (60)
    om = json.load(open(os.path.join(ROOT, "server/pal_opening_lines_manifest.json")))
    for l in om.get("lines", []):
        add(l["id"], l["text"])

    # Prompts (96)
    pl = json.load(open(os.path.join(ROOT, "assets/pal/pal_lines.json")))
    for bucket, items in pl.get("prompts", {}).items():
        for item in items:
            add(item["id"], item["text"])

    # Weary reflections (4 — we're testing the weary mood path)
    rl = json.load(open(os.path.join(ROOT, "assets/pal/pal_reflection_lines.json")))
    for r in rl.get("moods", {}).get("weary", []):
        add(r["id"], r["text"])

    # Transitions (12)
    tl = json.load(
        open(os.path.join(ROOT, "assets/pal/pal_transition_lines.json"))
    )
    for t in tl.get("lines", []):
        add(t["id"], t["text"])

    # David Anointed framings (2)
    br = json.load(
        open(os.path.join(ROOT, "assets/stories/biblical_figure_registry.json"))
    )
    for e in br["entries"]:
        if e.get("bibleStoryKey") == "david_anointed":
            for f in e.get("framingLines", []):
                add(f["id"], f["text"])
            break

    return out


def tts(line_id: str, text: str) -> str:
    out = os.path.join(OUT_DIR, f"{line_id}.mp3")
    if os.path.exists(out):
        return f"[skip] {line_id}"
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
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
            with open(out, "wb") as f:
                f.write(data)
            return f"[ok {len(data)}b] {line_id}"
    except urllib.error.HTTPError as e:
        return f"[FAIL {e.code}] {line_id}: {e.read().decode('utf-8', errors='ignore')[:120]}"
    except Exception as e:
        return f"[FAIL] {line_id}: {e}"


def main():
    lines = collect_lines()
    print(f"Lines to consider: {len(lines)}")
    ok = skip = fail = 0
    for line_id, text in lines:
        msg = tts(line_id, text)
        print(f"  {msg}")
        if msg.startswith("[ok"):
            ok += 1
        elif msg.startswith("[skip"):
            skip += 1
        else:
            fail += 1
    print()
    print(f"ok={ok} skip={skip} fail={fail}")
    print(f"files in {OUT_DIR}: {len(os.listdir(OUT_DIR))}")
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
