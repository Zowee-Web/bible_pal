#!/usr/bin/env python3
"""
Render biblical-figure FRAMING clips (the accept-path "announce" line).

When a user accepts a journey continuation ("yes"), PAL speaks a short
framing line naming what the next story is about *before* the player opens
(main_menu_screen.dart `_playJourneyStoryIntro` →
`BiblicalFigureRegistry.getFramingLineRef`). Those lines live in
assets/stories/biblical_figure_registry.json as `framingLines[{id,text}]`
per bibleStoryKey. This script renders each line's audio to:

    assets/pal/audio/<VOICE>/<framingId>.mp3       (ROOT of the voice dir)

Note the path: framing clips sit at the voice-dir ROOT, NOT the `journey/`
subdir (that holds the offer clips rendered by render_journey_audio.py) and
NOT the `memory/` subdir. `playLine(id, voiceKey)` resolves
`assets/pal/audio/<voiceKey>/<id>.mp3`.

All PAL voice audio uses eleven_v3 (see feedback_pal_voice_audio_uses_v3 /
render_journey_audio.py header). This script reuses that module's proven
ElevenLabs plumbing (voice table, settings, atomic render) so there is one
source of truth for TTS config.

Idempotent: skips any clip already on disk unless --force. `--keys` narrows
to specific bibleStoryKeys (comma-separated); default renders every framing
line whose mp3 is missing.

Usage:
    ./scripts/render_figure_framing_audio.py                       # dry-run, all missing
    ./scripts/render_figure_framing_audio.py --render              # render all missing
    ./scripts/render_figure_framing_audio.py --render --keys joseph_in_prison,genesis_41
    ./scripts/render_figure_framing_audio.py --render --force --keys elijah_taken_up
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import urllib.error
from pathlib import Path

# Reuse the journey renderer's ElevenLabs plumbing (single source of truth
# for voice IDs, settings, and the atomic render helper).
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_journey_audio import (  # noqa: E402
    ASSETS_ROOT,
    ELEVENLABS_DEFAULT_MODEL,
    PROJECT_ROOT,
    VOICES,
    load_env_var,
    render_elevenlabs,
)

REGISTRY = PROJECT_ROOT / "assets" / "stories" / "biblical_figure_registry.json"

CREDITS_PER_CHAR_LOW = 0.5
CREDITS_PER_CHAR_HIGH = 0.7


def framing_clip_path(voice_key: str, clip_id: str) -> Path:
    """Root-of-voice-dir path — where playLine() resolves framing clips."""
    return ASSETS_ROOT / voice_key / f"{clip_id}.mp3"


def collect_lines(keys: set[str] | None) -> list[dict]:
    reg = json.loads(REGISTRY.read_text())
    out: list[dict] = []
    for e in reg["entries"]:
        key = e["bibleStoryKey"]
        if keys is not None and key not in keys:
            continue
        for ref in e.get("framingLines", []):
            out.append({
                "bibleStoryKey": key,
                "clip_id": ref["id"],
                "text": ref["text"],
            })
    return out


def build_plan(voice_key: str, keys: set[str] | None, force: bool) -> list[dict]:
    plan: list[dict] = []
    for line in collect_lines(keys):
        out = framing_clip_path(voice_key, line["clip_id"])
        plan.append({
            **line,
            "model": ELEVENLABS_DEFAULT_MODEL,  # eleven_v3
            "out_path": out,
            "exists": out.exists(),
            "would_skip": out.exists() and not force,
            "chars": len(line["text"]),
        })
    return plan


def print_plan(voice_key: str, voice_meta: dict, plan: list[dict], *,
               render_mode: bool, force: bool) -> None:
    print("=" * 72)
    print("Figure framing audio — accept-path 'announce' line render plan")
    print("=" * 72)
    print(f"Mode:            {'RENDER (will spend credits)' if render_mode else 'DRY-RUN (no API calls)'}")
    print(f"Voice:           {voice_key} — {voice_meta['display_name']}")
    print(f"TTS model:       {ELEVENLABS_DEFAULT_MODEL}")
    print(f"Force overwrite: {force}")
    print(f"Output root:     {ASSETS_ROOT.relative_to(PROJECT_ROOT)}/{voice_key}/")
    print()
    print(f"{'clip_id':<52} {'chars':>5} {'exists':>7} {'action':<14} text")
    print("-" * 130)
    for e in plan:
        if e["would_skip"]:
            action = "skip (exists)"
        elif e["exists"] and force:
            action = "OVERWRITE"
        else:
            action = "render" if render_mode else "WOULD render"
        print(f"{e['clip_id']:<52} {e['chars']:>5} "
              f"{'yes' if e['exists'] else 'no':>7} {action:<14} {e['text']!r}")

    to_render = [e for e in plan if not e["would_skip"]]
    chars = sum(e["chars"] for e in to_render)
    print()
    print(f"Clips total:              {len(plan)}")
    print(f"Clips to render this run: {len(to_render)}  (skipping {len(plan) - len(to_render)})")
    print(f"Billed characters:        {chars}")
    print(f"Estimated credits:        {int(chars * CREDITS_PER_CHAR_LOW)}–{int(chars * CREDITS_PER_CHAR_HIGH)}")


def run(plan: list[dict], voice_meta: dict, *, api_key: str) -> tuple[list[str], list[str]]:
    """Atomic write per clip — API output → .partial → rename to final."""
    rendered: list[str] = []
    failed: list[str] = []
    for e in plan:
        if e["would_skip"]:
            continue
        clip_id = e["clip_id"]
        final = e["out_path"]
        try:
            final.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                dir=final.parent, prefix=f".{clip_id}.", suffix=".partial.mp3", delete=False
            ) as tmp:
                partial = Path(tmp.name)
            render_elevenlabs(
                text=e["text"],
                elevenlabs_id=voice_meta["elevenlabs_id"],
                api_key=api_key,
                output_path=partial,
                model=e["model"],
            )
            partial.replace(final)
            print(f"  ok      {clip_id}")
            rendered.append(clip_id)
        except urllib.error.HTTPError as ex:
            detail = ex.read().decode("utf-8", errors="replace")[:200]
            print(f"  FAIL    {clip_id}  HTTP {ex.code}: {detail}")
            failed.append(clip_id)
        except Exception as ex:  # noqa: BLE001 — keep batch going
            print(f"  FAIL    {clip_id}  {type(ex).__name__}: {ex}")
            failed.append(clip_id)
    return rendered, failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--render", action="store_true",
                        help="Actually call ElevenLabs and write audio. Default is dry-run.")
    parser.add_argument("--voice", type=str, default="STILLWATER",
                        help="Voice short name (HOPE / SHEPHERD / STILLWATER).")
    parser.add_argument("--keys", type=str, default=None,
                        help="Comma-separated bibleStoryKeys to render. Default: all missing.")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing clips. Default skips clips already on disk.")
    args = parser.parse_args()

    short = args.voice.upper().replace("VOICE_", "")
    voice_key = f"VOICE_{short}"
    voice_meta = VOICES.get(voice_key)
    if voice_meta is None:
        print(f"Unknown voice: {args.voice}. Pick from HOPE / SHEPHERD / STILLWATER.")
        return 2

    keys = None
    if args.keys:
        keys = {k.strip() for k in args.keys.split(",") if k.strip()}

    plan = build_plan(voice_key=voice_key, keys=keys, force=args.force)
    if not plan:
        print("No framing lines matched. (Check --keys, or the registry has no framingLines.)")
        return 0
    print_plan(voice_key, voice_meta, plan, render_mode=args.render, force=args.force)

    if not args.render:
        print()
        print("This was a dry-run. To actually render:")
        print(f"  ./scripts/render_figure_framing_audio.py --render --voice {short}"
              + (f" --keys {args.keys}" if args.keys else ""))
        return 0

    api_key = load_env_var("ELEVENLABS_API_KEY")
    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY not found in .env")
        return 1

    print()
    print("Rendering…")
    rendered, failed = run(plan, voice_meta, api_key=api_key)
    print()
    print(f"Rendered: {len(rendered)}   Failed: {len(failed)}")
    if failed:
        print("FAILED:", ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
