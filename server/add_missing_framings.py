#!/usr/bin/env python3
"""Add the 21 missing bibleStoryKey entries to biblical_figure_registry.json
and generate audio for all 42 new framing lines across all 4 PAL voices.

Run once. Idempotent — re-running detects existing entries and audio
files and skips them.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.join(ROOT, ".env")
REGISTRY = os.path.join(ROOT, "assets/stories/biblical_figure_registry.json")
AUDIO_BASE = os.path.join(ROOT, "assets/pal/audio")
MODEL_ID = "eleven_v3"

VOICES = {
    "VOICE_RUTH_COMFORT": "jBpfuIE2acCO8z3wKNLl",
    "VOICE_HOPE": "qBDvhofpxp92JgXJxDjB",
    "VOICE_SHEPHERD": "EkK5I93UQWFDigLMpZcX",
    "VOICE_STILLWATER": "uju3wxzG5OhpWcoi3SMy",
}

# 21 entries × 2 framing lines each. Tone matches existing 67 entries:
# short, evocative, contrast-driven, story-specific, no spoilers.
NEW_ENTRIES = [
    {
        "bibleStoryKey": "daniel_lions_den",
        "primaryFigure": "Daniel",
        "secondaryFigures": ["Darius"],
        "framingLines": [
            {"id": "FRAME_DANIEL_LIONS_DEN_01",
             "text": "Daniel kept praying — even when it could cost him everything."},
            {"id": "FRAME_DANIEL_LIONS_DEN_02",
             "text": "The lions were real. So was the One who closed their mouths."},
        ],
    },
    {
        "bibleStoryKey": "david_goliath",
        "primaryFigure": "David",
        "secondaryFigures": ["Goliath", "Saul"],
        "framingLines": [
            {"id": "FRAME_DAVID_GOLIATH_01",
             "text": "Everyone saw a giant. David saw something different."},
            {"id": "FRAME_DAVID_GOLIATH_02",
             "text": "David walked toward what scared everyone else away."},
        ],
    },
    {
        "bibleStoryKey": "elijah_at_horeb",
        "primaryFigure": "Elijah",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_ELIJAH_AT_HOREB_01",
             "text": "Elijah was done. God met him in a whisper."},
            {"id": "FRAME_ELIJAH_AT_HOREB_02",
             "text": "He expected thunder. What came was softer than that."},
        ],
    },
    {
        "bibleStoryKey": "hagar_in_wilderness",
        "primaryFigure": "Hagar",
        "secondaryFigures": ["Ishmael"],
        "framingLines": [
            {"id": "FRAME_HAGAR_IN_WILDERNESS_01",
             "text": "Hagar felt invisible. Then God called her by name."},
            {"id": "FRAME_HAGAR_IN_WILDERNESS_02",
             "text": "Out in the wilderness, someone saw her — really saw her."},
        ],
    },
    {
        "bibleStoryKey": "healing_at_bethesda",
        "primaryFigure": "Jesus",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_HEALING_AT_BETHESDA_01",
             "text": "He had been waiting for years. Then someone finally asked the right question."},
            {"id": "FRAME_HEALING_AT_BETHESDA_02",
             "text": "He didn't know who Jesus was yet. Jesus already knew him."},
        ],
    },
    {
        "bibleStoryKey": "jehoshaphat_praise_battle",
        "primaryFigure": "Jehoshaphat",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_JEHOSHAPHAT_PRAISE_BATTLE_01",
             "text": "Jehoshaphat was outmatched. So he started by listening."},
            {"id": "FRAME_JEHOSHAPHAT_PRAISE_BATTLE_02",
             "text": "They marched into battle singing — before they even saw the enemy fall."},
        ],
    },
    {
        "bibleStoryKey": "jericho_falls",
        "primaryFigure": "Joshua",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_JERICHO_FALLS_01",
             "text": "The walls were thick. The instructions sounded strange."},
            {"id": "FRAME_JERICHO_FALLS_02",
             "text": "They walked. They waited. They trusted the silence before the noise."},
        ],
    },
    {
        "bibleStoryKey": "jonah_in_nineveh",
        "primaryFigure": "Jonah",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_JONAH_IN_NINEVEH_01",
             "text": "Jonah said the words. Nineveh actually listened."},
            {"id": "FRAME_JONAH_IN_NINEVEH_02",
             "text": "He didn't expect them to change. They did anyway."},
        ],
    },
    {
        "bibleStoryKey": "joseph_interprets_pharaohs_dreams",
        "primaryFigure": "Joseph",
        "secondaryFigures": ["Pharaoh"],
        "framingLines": [
            {"id": "FRAME_JOSEPH_INTERPRETS_PHARAOHS_DREAMS_01",
             "text": "Joseph went from prison to palace in a single day."},
            {"id": "FRAME_JOSEPH_INTERPRETS_PHARAOHS_DREAMS_02",
             "text": "Pharaoh's dreams unsettled him. Joseph knew Who they were from."},
        ],
    },
    {
        "bibleStoryKey": "mary_at_empty_tomb",
        "primaryFigure": "Mary Magdalene",
        "secondaryFigures": ["Jesus"],
        "framingLines": [
            {"id": "FRAME_MARY_AT_EMPTY_TOMB_01",
             "text": "Mary came expecting grief. She found a name spoken in love."},
            {"id": "FRAME_MARY_AT_EMPTY_TOMB_02",
             "text": "He said her name. That's how she knew."},
        ],
    },
    {
        "bibleStoryKey": "moses_and_jethro",
        "primaryFigure": "Moses",
        "secondaryFigures": ["Jethro"],
        "framingLines": [
            {"id": "FRAME_MOSES_AND_JETHRO_01",
             "text": "Moses was carrying too much alone. Jethro told him the truth."},
            {"id": "FRAME_MOSES_AND_JETHRO_02",
             "text": "Sometimes the help we need comes from someone who knows us."},
        ],
    },
    {
        "bibleStoryKey": "peter_prison_escape",
        "primaryFigure": "Peter",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_PETER_PRISON_ESCAPE_01",
             "text": "Peter was sleeping the night he was supposed to die."},
            {"id": "FRAME_PETER_PRISON_ESCAPE_02",
             "text": "The chains fell. The door opened. He thought he was dreaming."},
        ],
    },
    {
        "bibleStoryKey": "prodigal_son",
        "primaryFigure": "The Father",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_PRODIGAL_SON_01",
             "text": "He came home expecting nothing. His father had been watching the road."},
            {"id": "FRAME_PRODIGAL_SON_02",
             "text": "There was a long way back. The welcome was longer."},
        ],
    },
    {
        "bibleStoryKey": "red_sea_crossing",
        "primaryFigure": "Moses",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_RED_SEA_CROSSING_01",
             "text": "Behind them was Pharaoh. In front of them was the sea."},
            {"id": "FRAME_RED_SEA_CROSSING_02",
             "text": "They walked through what shouldn't have been a path."},
        ],
    },
    {
        "bibleStoryKey": "road_to_emmaus",
        "primaryFigure": "Jesus",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_ROAD_TO_EMMAUS_01",
             "text": "Two friends walked home grieving. Someone they didn't recognize joined them."},
            {"id": "FRAME_ROAD_TO_EMMAUS_02",
             "text": "He was right there with them — long before they realized who He was."},
        ],
    },
    {
        "bibleStoryKey": "ruth_and_naomi",
        "primaryFigure": "Ruth",
        "secondaryFigures": ["Naomi"],
        "framingLines": [
            {"id": "FRAME_RUTH_AND_NAOMI_01",
             "text": "Ruth had every reason to leave. She stayed anyway."},
            {"id": "FRAME_RUTH_AND_NAOMI_02",
             "text": "Naomi felt empty. Ruth refused to let her walk alone."},
        ],
    },
    {
        "bibleStoryKey": "saul_on_road_to_damascus",
        "primaryFigure": "Saul",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_SAUL_ON_ROAD_TO_DAMASCUS_01",
             "text": "Saul was sure he was right. Then a light stopped him cold."},
            {"id": "FRAME_SAUL_ON_ROAD_TO_DAMASCUS_02",
             "text": "He started the road as one man and finished it as another."},
        ],
    },
    {
        "bibleStoryKey": "transfiguration",
        "primaryFigure": "Jesus",
        "secondaryFigures": ["Peter", "James", "John"],
        "framingLines": [
            {"id": "FRAME_TRANSFIGURATION_01",
             "text": "Just for a moment, the disciples saw who Jesus really was."},
            {"id": "FRAME_TRANSFIGURATION_02",
             "text": "They wanted to stay. They had to come back down the mountain."},
        ],
    },
    {
        "bibleStoryKey": "woman_anoints_jesus_feet",
        "primaryFigure": "Jesus",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_WOMAN_ANOINTS_JESUS_FEET_01",
             "text": "She came uninvited. She left forgiven."},
            {"id": "FRAME_WOMAN_ANOINTS_JESUS_FEET_02",
             "text": "The room judged her. Jesus called her gift beautiful."},
        ],
    },
    {
        "bibleStoryKey": "woman_at_well",
        "primaryFigure": "Jesus",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_WOMAN_AT_WELL_01",
             "text": "She came for water at noon to avoid people. He was already waiting."},
            {"id": "FRAME_WOMAN_AT_WELL_02",
             "text": "He knew everything about her. He spoke to her anyway."},
        ],
    },
    {
        "bibleStoryKey": "woman_caught_in_adultery",
        "primaryFigure": "Jesus",
        "secondaryFigures": [],
        "framingLines": [
            {"id": "FRAME_WOMAN_CAUGHT_IN_ADULTERY_01",
             "text": "The crowd had stones. Jesus knelt in the dust."},
            {"id": "FRAME_WOMAN_CAUGHT_IN_ADULTERY_02",
             "text": "He didn't condemn her. He didn't pretend nothing happened either."},
        ],
    },
]


def load_env():
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
    return api_key


def update_registry():
    br = json.load(open(REGISTRY))
    existing_keys = {e["bibleStoryKey"] for e in br["entries"]}
    added = 0
    for entry in NEW_ENTRIES:
        if entry["bibleStoryKey"] in existing_keys:
            continue
        br["entries"].append(entry)
        added += 1
    if added:
        # Sort entries by bibleStoryKey for stable diffs.
        br["entries"].sort(key=lambda e: e["bibleStoryKey"])
        with open(REGISTRY, "w") as f:
            json.dump(br, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Registry updated: +{added} entries (total {len(br['entries'])})")
    else:
        print("Registry already has all 21 entries — no edit needed")
    return br


def tts(api_key, voice_id, line_id, text, voice_dir):
    out = os.path.join(voice_dir, f"{line_id}.mp3")
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
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
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
    api_key = load_env()
    update_registry()

    new_lines = [
        (l["id"], l["text"]) for entry in NEW_ENTRIES for l in entry["framingLines"]
    ]
    total_calls = len(new_lines) * len(VOICES)
    print(
        f"\nGenerating {len(new_lines)} new framings × {len(VOICES)} voices = "
        f"{total_calls} TTS calls (skips existing)"
    )

    grand_ok = grand_skip = grand_fail = 0
    start = time.time()
    for voice_key, voice_id in VOICES.items():
        voice_dir = os.path.join(AUDIO_BASE, voice_key)
        os.makedirs(voice_dir, exist_ok=True)
        v_ok = v_skip = v_fail = 0
        print(f"\n--- {voice_key} ---")
        for line_id, text in new_lines:
            status, lid, info = tts(api_key, voice_id, line_id, text, voice_dir)
            if status == "ok":
                v_ok += 1; grand_ok += 1
            elif status == "skip":
                v_skip += 1; grand_skip += 1
            else:
                v_fail += 1; grand_fail += 1
                print(f"  FAIL {lid}: {info}")
        print(f"  {voice_key}: ok={v_ok} skip={v_skip} fail={v_fail}")
    elapsed = time.time() - start
    print(
        f"\nGrand total: ok={grand_ok} skip={grand_skip} fail={grand_fail}  "
        f"({elapsed:.0f}s)"
    )
    if grand_fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
