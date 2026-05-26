#!/usr/bin/env python3
"""
lane_diagnostic.py — Generate the same scripture anchor in both KJV (Classic) and
WEB (Modern) lanes for side-by-side comparison.

NO TTS, NO registry update, NO metadata, NO compliance gates beyond meta-text strip.
Outputs plain .txt files to assets/diagnostics/lane_compare/{anchor_slug}/.

Used during Phase 2 of the lane-differentiation initiative to discover what each
lane naturally drifts toward BEFORE prompt restructuring.

Default backend is Claude (matches recent production batches). OpenAI optional.

Usage:
    # Default: 5-anchor corpus, Claude, short length
    python3 scripts/story_factory/lane_diagnostic.py

    # Single anchor
    python3 scripts/story_factory/lane_diagnostic.py --anchor "Psalm 23"

    # OpenAI backend
    python3 scripts/story_factory/lane_diagnostic.py --backend openai
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from story_prompts import SYSTEM_PROMPTS_STORY_TRADITIONAL, TRADITIONAL_RANGES

DEFAULT_CORPUS = [
    "Psalm 23",        # lyric
    "Ezra 3:10–13",   # procedural/historical narrative
    "Isaiah 6:1–8",   # apocalyptic vision
    "Mark 4:35–41",   # gospel narrative
    "Matthew 5:3–12", # patterned list (Beatitudes)
]

LENGTH_PROMPTS = {
    "short": (
        "Build the scene with concrete, observable details — "
        "setting, weather, sounds, physical actions — "
        "to reach the required length. "
        "Render the passage as a lived, narrated moment."
    ),
    "full": (
        "Expand detail and pacing: describe the setting, "
        "the people, their physical actions, the sounds and sights. "
        "Do not add new events beyond the passage."
    ),
    "long": (
        "Slow the narrative, enrich scene detail with "
        "concrete sensory description (sights, sounds, textures). "
        "Introduce no new events or meaning beyond the passage."
    ),
}

CLAUDE_MODEL = "claude-opus-4-7"  # matches recent B26-B28 stories
OPENAI_MODEL = "gpt-4.1"
TEMPERATURE = 0.7


def load_env(root: pathlib.Path) -> None:
    env_file = root / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = re.sub(r"\s+#.*$", "", value)
        os.environ[key.strip()] = value.strip()


def slugify_anchor(anchor: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "_", anchor).strip("_").lower()


def build_user_prompt(anchor: str, length: str) -> str:
    lo, hi = TRADITIONAL_RANGES[length]
    return (
        f"Create a {length.upper()} Traditional Bible PAL story "
        f"retelling {anchor}. "
        f"HARD WORD COUNT: you MUST produce between {lo} and {hi} words. "
        f"This is a strict requirement — do not go under {lo} or over {hi}. "
        + LENGTH_PROMPTS[length]
    )


def strip_separators(text: str) -> str:
    text = re.sub(r"^-{3,}\s*\n?", "", text.lstrip())
    text = re.sub(r"\n?-{3,}\s*$", "", text.rstrip())
    return text.strip()


def call_claude(system: str, user: str) -> str:
    import anthropic
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    resp = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=4096,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return resp.content[0].text


def call_openai(system: str, user: str) -> str:
    payload = json.dumps({
        "model": OPENAI_MODEL,
        "temperature": TEMPERATURE,
        "input": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=payload,
        headers={
            "Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
    for output in data.get("output", []):
        if output.get("type") == "message":
            for content in output.get("content", []):
                if content.get("type") == "output_text":
                    return content["text"]
    raise RuntimeError(f"No text in OpenAI response: {json.dumps(data)[:500]}")


def run_anchor(anchor: str, outdir: pathlib.Path, length: str, backend: str) -> None:
    user_prompt = build_user_prompt(anchor, length)
    slug = slugify_anchor(anchor)
    anchor_dir = outdir / slug
    anchor_dir.mkdir(parents=True, exist_ok=True)
    (anchor_dir / "anchor.txt").write_text(
        f"{anchor}\nlength: {length}\nbackend: {backend}\n"
    )
    call_fn = call_claude if backend == "claude" else call_openai

    for lane in ("kjv", "web"):
        print(f"  [{lane}] generating {anchor} ({length}, {backend})...")
        t0 = time.time()
        system_prompt = SYSTEM_PROMPTS_STORY_TRADITIONAL[lane]
        text = strip_separators(call_fn(system_prompt, user_prompt))
        elapsed = time.time() - t0
        fname = f"{backend}_{lane}.txt"
        (anchor_dir / fname).write_text(text + "\n")
        wc = len(text.split())
        print(f"    saved {fname} ({wc} words, {elapsed:.1f}s)")


def main() -> int:
    p = argparse.ArgumentParser(
        description="Side-by-side lane diagnostic generator (NO audio, NO registry)."
    )
    p.add_argument(
        "--anchor", action="append",
        help="Scripture anchor. Repeatable. Defaults to 5-anchor corpus.",
    )
    p.add_argument(
        "--length", choices=("short", "full", "long"), default="short",
        help="Length tier (default: short, cheapest).",
    )
    p.add_argument(
        "--backend", choices=("claude", "openai"), default="claude",
        help="Generation backend (default: claude, matches recent production).",
    )
    p.add_argument(
        "--outdir", default="assets/diagnostics/lane_compare",
        help="Output directory (relative to repo root or absolute).",
    )
    args = p.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    load_env(root)

    required = "ANTHROPIC_API_KEY" if args.backend == "claude" else "OPENAI_API_KEY"
    if not os.environ.get(required, "").strip():
        print(f"ABORT: env var {required} is missing")
        return 1

    outdir_arg = pathlib.Path(args.outdir)
    outdir = outdir_arg if outdir_arg.is_absolute() else (root / outdir_arg)
    outdir.mkdir(parents=True, exist_ok=True)

    anchors = args.anchor or DEFAULT_CORPUS
    for anchor in anchors:
        print(f"=== {anchor} ===")
        run_anchor(anchor, outdir, args.length, args.backend)

    print(f"\nDONE. Diagnostic outputs at {outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
