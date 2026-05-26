#!/usr/bin/env python3
"""
generate_story_claude.py — Bible PAL Story Factory (Claude Opus 4.6)

Unified generation script for both Traditional and Creative stories.
All prose is authored by Claude Opus 4.6 via the Anthropic Python SDK.
This script generates NO prose itself.

Usage:
    # Traditional
    python3 generate_story_claude.py \\
        --story_id 1000 --mode traditional --mood weary \\
        --anchor "Matthew 11:28-30" --bible_story_key "rest_for_the_weary" \\
        --batch PAL_CLAUDE_BATCH_01

    # Creative
    python3 generate_story_claude.py \\
        --story_id 2000 --mode creative --mood joyful \\
        --theme "a lighthouse keeper who discovers that sharing light multiplies it" \\
        --kid --batch PAL_CLAUDE_BATCH_01
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import sys
import time

import anthropic

from story_prompts import (
    SYSTEM_PROMPTS_STORY_TRADITIONAL,
    SYSTEM_PROMPTS_STORY_CREATIVE,
    KID_SYSTEM_PROMPTS_STORY_TRADITIONAL,
    KID_SYSTEM_PROMPTS_STORY_CREATIVE,
    SYSTEM_PROMPT_REFLECTION,
    KID_SYSTEM_PROMPT_REFLECTION,
    SYSTEM_PROMPT_REFLECTION_QUESTION,
    KID_SYSTEM_PROMPT_REFLECTION_QUESTION,
    SYSTEM_PROMPT_TITLE,
    TRADITIONAL_SANITIZE_PROMPT,
    CREATIVE_SANITIZE_PROMPT,
    META_TEXT_REPAIR_INSTRUCTION,
    TRADITIONAL_RANGES,
    CREATIVE_RANGES,
    KID_TRADITIONAL_RANGES,
    KID_CREATIVE_RANGES,
    REFLECTION_WORD_RANGE,
    KID_REFLECTION_WORD_RANGE,
    build_traditional_story_prompt,
    build_creative_story_prompt,
    build_reflection_prompt,
    build_reflection_question_prompt,
    build_title_prompt,
)
from claude_validator import (
    check_meta_text,
    validate_traditional,
    validate_creative,
    log_lane_warnings,
    check_reflection_banned,
    check_lyrical_drift,
    load_forbidden_words,
    check_forbidden_words,
    apply_kid_word_replacements,
)

# ── Constants ─────────────────────────────────────────────────────────────

MODEL = "claude-opus-4-6"
TEMPERATURE = 0.7
MAX_REGEN = 5

VALID_MOODS = [
    "joyful", "grateful", "weary", "anxious",
    "hurting", "brave_courage", "calm_peaceful", "encouraging",
]

LANE_STYLE = {"kjv": "KJV", "web": "WEB"}

# 66-book Protestant canon — full unabbreviated English names
PROTESTANT_BOOKS = {
    "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
    "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
    "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
    "Ezra", "Nehemiah", "Esther", "Job", "Psalm", "Proverbs",
    "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
    "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah",
    "Haggai", "Zechariah", "Malachi",
    "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
    "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
    "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
    "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
    "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
    "Jude", "Revelation",
}

_ANCHOR_RE = re.compile(
    r"^(?P<book>.+?)\s+(?P<chapter>\d+)(?::(?P<verse>\d+)(?:[\u2013-](?P<verse_end>\d+))?)?$"
)


# ── .env loader ───────────────────────────────────────────────────────────

def load_env(root: pathlib.Path) -> None:
    """Load .env from repo root safely."""
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


# ── Anchor validation ─────────────────────────────────────────────────────

def validate_anchor_format(anchor: str) -> str | None:
    """Validate anchor against spec Section 2.2. Returns error message or None."""
    m = _ANCHOR_RE.match(anchor)
    if not m:
        return f"Anchor does not match format 'Book Chapter[:Verse[-Verse]]': {anchor!r}"
    book = m.group("book")
    if book not in PROTESTANT_BOOKS:
        return f"Unknown or abbreviated book name: {book!r} (must be full Protestant English name)"
    return None


# ── Claude API helper ─────────────────────────────────────────────────────

_client: anthropic.Anthropic | None = None


def get_client() -> anthropic.Anthropic:
    """Get or create the Anthropic client (lazy singleton)."""
    global _client
    if _client is None:
        _client = anthropic.Anthropic()
    return _client


def call_claude(system: str, user: str, max_tokens: int = 4096) -> str:
    """Call Claude Opus 4.6 via Anthropic SDK. Returns output text.

    Retries up to 3 times for transient errors (429, 502, 503).
    """
    client = get_client()
    for attempt in range(4):
        try:
            message = client.messages.create(
                model=MODEL,
                max_tokens=max_tokens,
                temperature=TEMPERATURE,
                system=system,
                messages=[{"role": "user", "content": user}],
            )
            return message.content[0].text.strip()
        except anthropic.RateLimitError:
            if attempt < 3:
                wait = 2 ** attempt
                print(f"    Rate limited, retry {attempt + 1}/3 in {wait}s...")
                time.sleep(wait)
                continue
            raise
        except anthropic.APIStatusError as exc:
            if exc.status_code in (502, 503) and attempt < 3:
                wait = 2 ** attempt
                print(f"    API error {exc.status_code}, retry {attempt + 1}/3 in {wait}s...")
                time.sleep(wait)
                continue
            raise


# ── Text cleanup ──────────────────────────────────────────────────────────

def clean_generated_text(text: str) -> str:
    """Strip common LLM artifacts from generated text."""
    # Strip leading/trailing separator lines
    text = re.sub(r"^-{3,}\s*\n?", "", text.lstrip())
    text = re.sub(r"\n?-{3,}\s*$", "", text.rstrip())
    # Strip leading markdown headings
    text = re.sub(r"^#{1,3}\s+[^\n]+\n+", "", text.lstrip())
    text = re.sub(r"^\*\*[^\n]+\*\*\s*\n+", "", text.lstrip())
    # Strip meta-text preamble: if text starts with a known meta-text phrase,
    # remove everything up to and including the first ":\n", ":\n\n", or just
    # the first line if it's a standalone preamble.
    meta_prefixes = [
        "here is", "here's", "this story", "this version", "this passage",
        "this retelling", "this rendering", "this adaptation",
        "certainly", "of course", "absolutely", "sure,", "sure!",
    ]
    stripped = text.lstrip()
    opening = stripped[:80].lower()
    for prefix in meta_prefixes:
        if opening.startswith(prefix):
            # Try to strip up to colon+whitespace first
            colon_match = re.match(r"^[^\n]*?:\s*\n?", stripped, re.IGNORECASE)
            if colon_match:
                text = stripped[colon_match.end():]
            else:
                # Otherwise strip the entire first line
                first_nl = stripped.find("\n")
                if first_nl > 0:
                    text = stripped[first_nl + 1:]
            break
    return text.strip()


# ── Main pipeline ─────────────────────────────────────────────────────────

def main() -> int:
    t0 = time.time()

    parser = argparse.ArgumentParser(
        description="Generate a Bible PAL story using Claude Opus 4.6."
    )
    parser.add_argument("--story_id", type=int, required=True,
                        help="Story ID (1000-1999 for traditional, 2000-2999 for creative)")
    parser.add_argument("--mode", type=str, required=True,
                        choices=["traditional", "creative"])
    parser.add_argument("--mood", type=str, required=True,
                        help=f"One of: {', '.join(VALID_MOODS)}")
    parser.add_argument("--anchor", type=str, default=None,
                        help='Scripture anchor for traditional, e.g. "Psalm 23"')
    parser.add_argument("--bible_story_key", type=str, default=None,
                        help='Canonical key for traditional, e.g. "the_lord_is_my_shepherd"')
    parser.add_argument("--theme", type=str, default=None,
                        help='Story theme for creative mode')
    parser.add_argument("--lane", type=str, default="web",
                        choices=["web", "kjv"],
                        help="web = modern WEB style, kjv = classic KJV style")
    parser.add_argument("--voice_key", type=str, default=None,
                        help="Voice key for metadata (required for audio, set after generation)")
    parser.add_argument("--batch", type=str, default="PAL_CLAUDE_BATCH_01",
                        help="Generation batch label")
    parser.add_argument("--kid", action="store_true",
                        help="Kid mode (ages 5-9)")
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite existing output directory")
    args = parser.parse_args()

    sid = args.story_id
    mode = args.mode
    lane = args.lane
    root = pathlib.Path(__file__).resolve().parents[2]  # repo root
    outdir = root / "assets" / "stories" / mode / str(sid)

    # ── Preflight ─────────────────────────────────────────────────────

    print(f"=== Bible PAL Story Factory (Claude Opus 4.6) ===")
    print(f"  Mode: {mode}")
    print(f"  Story ID: {sid}")
    print(f"  Mood: {args.mood}")
    print(f"  Lane: {lane}")
    print(f"  Kid: {args.kid}")
    print()

    # 1. Load env
    load_env(root)

    # 2. Validate mood
    if args.mood not in VALID_MOODS:
        print(f"ABORT: invalid mood {args.mood!r}. Must be one of: {', '.join(VALID_MOODS)}")
        return 1

    # 3. Validate ID range
    if mode == "traditional" and not (1000 <= sid <= 1999):
        print(f"ABORT: Traditional story ID must be 1000-1999, got {sid}")
        return 1
    if mode == "creative" and not (2000 <= sid <= 2999):
        print(f"ABORT: Creative story ID must be 2000-2999, got {sid}")
        return 1

    # 3b. KJV lane enforcement (STRICT)
    # KJV is ONLY for adult Traditional stories. Kid KJV and Creative KJV must NEVER exist.
    if lane == "kjv":
        if mode == "creative":
            print("ABORT: KJV lane is FORBIDDEN for Creative stories. KJV is Traditional adult only.")
            return 1
        if args.kid:
            print("ABORT: KJV lane is FORBIDDEN for Kid stories. KJV is Traditional adult only.")
            return 1

    # 4. Mode-specific validation
    if mode == "traditional":
        if not args.anchor:
            print("ABORT: --anchor is required for traditional mode")
            return 1
        if not args.bible_story_key:
            print("ABORT: --bible_story_key is required for traditional mode")
            return 1
        anchor_err = validate_anchor_format(args.anchor)
        if anchor_err:
            print(f"ABORT: {anchor_err}")
            return 1
    else:  # creative
        if not args.theme:
            print("ABORT: --theme is required for creative mode")
            return 1

    # 5. Check ANTHROPIC_API_KEY
    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        print("ABORT: ANTHROPIC_API_KEY is missing or empty")
        return 1

    # 6. Check registries for duplicates (--overwrite clears existing entry)
    # When adding a KJV lane to an existing story, skip anchor check (already registered)
    existing_story_dir = root / "assets" / "stories" / mode / str(sid)
    adding_new_lane = existing_story_dir.exists() and lane != "web"
    if mode == "traditional":
        anchors_file = root / "used_scripture_anchors.json"
        if not anchors_file.exists():
            anchors_file.write_text("[]\n")
        anchors = json.loads(anchors_file.read_text())
        if args.anchor in anchors and not adding_new_lane:
            if args.overwrite:
                anchors = [a for a in anchors if a != args.anchor]
                print(f"  Cleared anchor from registry for overwrite: {args.anchor}")
            else:
                print(f"ABORT: anchor already used: {args.anchor}")
                return 1
    else:
        themes_file = root / "used_creative_themes.json"
        if not themes_file.exists():
            themes_file.write_text("[]\n")
        themes = json.loads(themes_file.read_text())
        theme_key = f"{args.mood}:{args.theme}"
        if theme_key in themes:
            if args.overwrite:
                themes = [t for t in themes if t != theme_key]
                print(f"  Cleared theme from registry for overwrite: {theme_key}")
            else:
                print(f"ABORT: theme already used for this mood: {theme_key}")
                return 1

    # 7. Handle existing output dir
    adding_lane = False
    if outdir.exists():
        # Check if we're adding a new lane to an existing story
        existing_lane_file = outdir / f"story_{sid}_{mode}_{lane}_short.txt"
        if existing_lane_file.exists() and not args.overwrite:
            print(f"ABORT: {lane} lane files already exist for story {sid}")
            print(f"  Use --overwrite to replace.")
            return 1
        if not existing_lane_file.exists():
            # Directory exists with different lane — adding KJV alongside WEB
            adding_lane = True
            print(f"  Adding {lane.upper()} lane to existing story {sid}")
        elif args.overwrite:
            print(f"  Overwriting {lane.upper()} lane files for story {sid}")
    else:
        outdir.mkdir(parents=True)
        print(f"Created {outdir}")

    def fail_clean(msg: str) -> int:
        print(f"FAIL: {msg}")
        if not adding_lane:
            # Only delete directory if we created it fresh (not adding to existing)
            shutil.rmtree(outdir, ignore_errors=True)
            print(f"Cleaned up {outdir}")
        else:
            # Clean up only the lane files we created
            for f in outdir.glob(f"*_{lane}_*"):
                f.unlink()
            print(f"Cleaned up {lane.upper()} lane files")
        return 1

    try:
        # ── Mode configuration ────────────────────────────────────────
        is_kid = args.kid
        if mode == "traditional":
            if is_kid:
                ranges = KID_TRADITIONAL_RANGES
                system_story = KID_SYSTEM_PROMPTS_STORY_TRADITIONAL[lane]
                refl_system = KID_SYSTEM_PROMPT_REFLECTION
                rq_system = KID_SYSTEM_PROMPT_REFLECTION_QUESTION
                refl_range = KID_REFLECTION_WORD_RANGE
            else:
                ranges = TRADITIONAL_RANGES
                system_story = SYSTEM_PROMPTS_STORY_TRADITIONAL[lane]
                refl_system = SYSTEM_PROMPT_REFLECTION
                rq_system = SYSTEM_PROMPT_REFLECTION_QUESTION
                refl_range = REFLECTION_WORD_RANGE
            validate_fn = validate_traditional
            sanitize_prompt = TRADITIONAL_SANITIZE_PROMPT
            anchor_or_theme = args.anchor
        else:
            if is_kid:
                ranges = KID_CREATIVE_RANGES
                system_story = KID_SYSTEM_PROMPTS_STORY_CREATIVE[lane]
                refl_system = KID_SYSTEM_PROMPT_REFLECTION
                rq_system = KID_SYSTEM_PROMPT_REFLECTION_QUESTION
                refl_range = KID_REFLECTION_WORD_RANGE
            else:
                ranges = CREATIVE_RANGES
                system_story = SYSTEM_PROMPTS_STORY_CREATIVE[lane]
                refl_system = SYSTEM_PROMPT_REFLECTION
                rq_system = SYSTEM_PROMPT_REFLECTION_QUESTION
                refl_range = REFLECTION_WORD_RANGE
            validate_fn = lambda text: validate_creative(text, LANE_STYLE[lane])
            sanitize_prompt = CREATIVE_SANITIZE_PROMPT
            anchor_or_theme = args.theme

        # Load kid forbidden words if needed
        forbidden = []
        if is_kid:
            forbidden = load_forbidden_words(root)
            print(f"Kid mode: loaded {len(forbidden)} forbidden words")

        # ── Generate 3 length variants ────────────────────────────────
        # RULE: LONG is generated using SHORT as reference (wider camera, same discipline)
        saved_short_text = None

        for length, (lo, hi) in ranges.items():
            print(f"\n=== Generating {length.upper()} {mode} story ===")

            # For LONG, pass the SHORT text as reference
            short_ref = saved_short_text if length == "long" else None

            if mode == "traditional":
                base_prompt = build_traditional_story_prompt(
                    args.anchor, length, lo, hi, is_kid,
                    short_reference=short_ref,
                )
            else:
                # Load used character names to avoid repetition
                names_file = root / "used_creative_names.json"
                used_names = []
                if names_file.exists():
                    used_names = json.loads(names_file.read_text())
                base_prompt = build_creative_story_prompt(
                    args.theme, args.mood, length, lo, hi, is_kid,
                    used_names=used_names,
                    short_reference=short_ref,
                )

            text = None
            for attempt in range(1, MAX_REGEN + 1):
                if attempt > 1:
                    print(f"  Fresh generation attempt {attempt}/{MAX_REGEN}...")

                text = call_claude(system_story, base_prompt)
                text = clean_generated_text(text)

                # Gate 1: meta-text check
                offending = check_meta_text(text)
                if offending is not None:
                    print(f"  Meta-text detected: {offending!r} (attempt {attempt})")
                    continue

                # Gate 2: word count
                wc = len(text.split())
                print(f"  Word count: {wc} (required: {lo}-{hi})")
                if wc < lo or wc > hi:
                    print(f"  Word count out of range (attempt {attempt})")
                    continue

                # Gate 3: mode compliance
                violations = validate_fn(text)
                if not violations:
                    # Kid mode: apply deterministic word replacements before gate
                    if forbidden:
                        text = apply_kid_word_replacements(text)
                        found_forbidden = check_forbidden_words(text, forbidden)
                        if found_forbidden:
                            print(f"  Forbidden words ({len(found_forbidden)}): {found_forbidden[:5]}")
                            continue
                    break  # all gates passed

                print(f"  Compliance violations ({len(violations)}):")
                for cat, phrase in violations:
                    print(f"    [{cat}] {phrase!r}")

                # Try one sanitize rewrite before fresh retry
                violation_lines = "\n".join(
                    f"- [{cat}] \"{phrase}\"" for cat, phrase in violations
                )
                print(f"  Attempting sanitize rewrite...")
                text = call_claude(
                    system_story,
                    sanitize_prompt + violation_lines + "\n\nORIGINAL STORY:\n" + text
                )
                text = clean_generated_text(text)

                # Re-check all gates after sanitize
                offending = check_meta_text(text)
                if offending is not None:
                    print(f"  Sanitize introduced meta-text: {offending!r}")
                    continue

                wc = len(text.split())
                print(f"  Post-sanitize word count: {wc} (required: {lo}-{hi})")
                if wc < lo or wc > hi:
                    continue

                remaining = validate_fn(text)
                if remaining:
                    print(f"  Still {len(remaining)} violations after sanitize")
                    continue

                if forbidden:
                    text = apply_kid_word_replacements(text)
                    found_forbidden = check_forbidden_words(text, forbidden)
                    if found_forbidden:
                        print(f"  Post-sanitize forbidden words: {found_forbidden[:5]}")
                        continue

                print(f"  Sanitize pass cleared all violations")
                break
            else:
                return fail_clean(
                    f"{length} story failed all gates after {MAX_REGEN} attempts"
                )

            # Lane identity validator (WARN-only, adult only).
            # Logs to assets/diagnostics/lane_validator_log.jsonl, never blocks.
            if mode == "traditional" and not is_kid:
                log_lane_warnings(root, sid, lane, length, text)

            fname = f"story_{sid}_{mode}_{lane}_{length}.txt"
            (outdir / fname).write_text(text)
            print(f"  Saved {fname}")

            # Save short text for use as LONG reference
            if length == "short":
                saved_short_text = text

            # LONG version: hard-check for drift from SHORT discipline
            if length == "long":
                from claude_validator import check_long_version_drift
                long_drift = check_long_version_drift(text)
                if long_drift:
                    print(f"  WARNING (LONG drift from SHORT discipline): {long_drift}")

            # Soft-flag: lyrical drift warnings (logged, not blocking)
            drift = check_lyrical_drift(text)
            if drift:
                print(f"  WARNING (lyrical drift, review recommended): {drift}")

        # ── Generate reflection ───────────────────────────────────────
        print(f"\n=== Generating REFLECTION ===")
        refl_prompt = build_reflection_prompt(
            mode, anchor_or_theme, lane, refl_range, is_kid
        )

        reflection = None
        for attempt in range(1, MAX_REGEN + 1):
            prompt = refl_prompt
            if attempt > 1:
                print(f"  Regeneration attempt {attempt}/{MAX_REGEN}...")

            reflection = call_claude(refl_system, prompt)
            reflection = clean_generated_text(reflection)

            # Gate 1: meta-text
            offending = check_meta_text(reflection)
            if offending is not None:
                print(f"  Meta-text in reflection: {offending!r} (attempt {attempt})")
                continue

            # Gate 2: word count
            refl_wc = len(reflection.split())
            print(f"  Reflection word count: {refl_wc} (target: {refl_range[0]}-{refl_range[1]})")
            if refl_wc < refl_range[0] or refl_wc > refl_range[1]:
                continue

            # Gate 3: banned phrases
            banned_hit = check_reflection_banned(reflection)
            if banned_hit:
                print(f"  Banned phrase in reflection: {banned_hit!r} (attempt {attempt})")
                continue

            # Gate 4 (kid only): forbidden words
            if forbidden:
                reflection = apply_kid_word_replacements(reflection)
                found_forbidden = check_forbidden_words(reflection, forbidden)
                if found_forbidden:
                    print(f"  Forbidden words in reflection: {found_forbidden[:5]}")
                    continue

            break
        else:
            return fail_clean(f"Reflection failed gates after {MAX_REGEN} attempts")

        refl_fname = f"reflection_{sid}_{mode}_{lane}.txt"
        (outdir / refl_fname).write_text(reflection)
        print(f"  Saved {refl_fname} ({refl_wc} words)")

        # ── Generate reflection question ──────────────────────────────
        print(f"\n=== Generating REFLECTION QUESTION ===")
        rq_prompt = build_reflection_question_prompt(
            mode, anchor_or_theme, lane, is_kid
        )
        reflection_question = call_claude(rq_system, rq_prompt, max_tokens=200).strip()

        # Validate: single line only
        if "\n" in reflection_question:
            reflection_question = reflection_question.split("\n")[0].strip()

        # Validate banned phrases
        banned_hit = check_reflection_banned(reflection_question)
        if banned_hit:
            print(f"  Reflection question contained banned phrase {banned_hit!r}, clearing")
            reflection_question = ""

        # Kid mode: forbidden word check
        if reflection_question and forbidden:
            found_forbidden = check_forbidden_words(reflection_question, forbidden)
            if found_forbidden:
                print(f"  Forbidden words in question {found_forbidden[:3]}, clearing")
                reflection_question = ""

        if reflection_question:
            print(f"  Question: {reflection_question}")
        else:
            print(f"  Question: (empty)")

        # ── Generate title ────────────────────────────────────────────
        print(f"\n=== Generating TITLE ===")
        title_prompt = build_title_prompt(mode, anchor_or_theme, args.mood)
        title = call_claude(SYSTEM_PROMPT_TITLE, title_prompt, max_tokens=100).strip()
        # Strip any quotes the model might add
        title = title.strip('"\'')
        print(f"  Title: {title}")

        # ── Write metadata ────────────────────────────────────────────
        print(f"\n=== Writing metadata ===")
        meta_fname = f"meta_{sid}.json"
        meta_path = outdir / meta_fname

        if adding_lane and meta_path.exists():
            # Adding KJV lane to existing story — merge into existing meta
            meta = json.loads(meta_path.read_text())
            meta["lanes"] = list(set(meta.get("lanes", ["web"]) + [lane]))
            # Add KJV file entries alongside existing WEB entries
            kjv_files = {
                f"{lane}_short": {
                    "storyText": f"story_{sid}_{mode}_{lane}_short.txt",
                },
                f"{lane}_full": {
                    "storyText": f"story_{sid}_{mode}_{lane}_full.txt",
                },
                f"{lane}_long": {
                    "storyText": f"story_{sid}_{mode}_{lane}_long.txt",
                },
                f"{lane}_reflection": {
                    "reflectionText": f"reflection_{sid}_{mode}_{lane}.txt",
                },
            }
            meta["files"].update(kjv_files)
            meta[f"reflectionQuestion_{lane}"] = reflection_question
            meta[f"title_{lane}"] = title
        else:
            # New story — create full meta
            meta = {
                "schemaVersion": 2,
                "storyId": sid,
                "mode": mode,
                "kidFriendly": is_kid,
                "languageStyle": LANE_STYLE[lane],
                "lanes": [lane],
                "mood": args.mood,
                "lengths": ["short", "full", "long"],
                "voiceKey": args.voice_key,
                "createdByModel": MODEL,
                "generationBatch": args.batch,
                "reflectionQuestion": reflection_question,
                "title": title,
                "files": {
                    "short": {
                        "storyText": f"story_{sid}_{mode}_{lane}_short.txt",
                        "storyAudio": f"audio_{sid}_story_short.mp3",
                    },
                    "full": {
                        "storyText": f"story_{sid}_{mode}_{lane}_full.txt",
                        "storyAudio": f"audio_{sid}_story_full.mp3",
                    },
                    "long": {
                        "storyText": f"story_{sid}_{mode}_{lane}_long.txt",
                        "storyAudio": f"audio_{sid}_story_long.mp3",
                    },
                    "reflection": {
                        "reflectionText": f"reflection_{sid}_{mode}_{lane}.txt",
                        "reflectionAudio": f"audio_{sid}_reflection.mp3",
                    },
                },
            }

            # Mode-specific metadata
            if mode == "traditional":
                meta["scriptureAnchor"] = args.anchor
                meta["bibleStoryKey"] = args.bible_story_key
            else:
                meta["theme"] = args.theme

        meta_path.write_text(json.dumps(meta, indent=2) + "\n")
        print(f"  Saved {meta_fname}")

        # ── Update manifest.json ──────────────────────────────────────
        print(f"\n=== Updating manifest.json ===")
        manifest_file = root / "assets" / "stories" / "manifest.json"
        manifest_data = json.loads(manifest_file.read_text())

        # Manifest is {"parables": [...]}
        parables = manifest_data.get("parables", [])

        # Remove any existing entries for this story_id (idempotent)
        prefix = f"story_{sid}_"
        parables = [e for e in parables if not e.get("storyId", "").startswith(prefix)]

        # Add new entries (one per length)
        for length in ["short", "full", "long"]:
            if is_kid:
                story_id_str = f"story_{sid}_{args.mood}_{length}_kid_{mode}"
            else:
                story_id_str = f"story_{sid}_{args.mood}_{length}_{mode}"

            entry = {
                "storyId": story_id_str,
                "title": title,
                "mood": args.mood,
                "emotionalTags": [],
                "storytellingMode": mode,
                "kidFriendly": is_kid,
                "audioFilePath": None,
                "textFilePath": f"{mode}/{sid}/story_{sid}_{mode}_{lane}_{length}.txt",
                "reflectionAudioPath": None,
                "translationId": "WEB",
                "languageStyle": LANE_STYLE[lane],
                "narratorVoiceKey": args.voice_key,
                "storyLength": length,
                "reflectionQuestion": reflection_question,
            }

            if mode == "traditional":
                entry["bibleSourceRef"] = args.anchor
                entry["bibleStoryKey"] = args.bible_story_key

            parables.append(entry)

        manifest_data["parables"] = parables
        manifest_file.write_text(json.dumps(manifest_data, indent=2) + "\n")
        print(f"  Added 3 manifest entries for story {sid}")

        # ── Update creative names registry ────────────────────────────
        if mode == "creative":
            names_file = root / "used_creative_names.json"
            used_names = []
            if names_file.exists():
                used_names = json.loads(names_file.read_text())
            # Extract likely character names from the short story text
            # Look for capitalized words that appear after common name-introducing patterns
            short_text = (outdir / f"story_{sid}_{mode}_{lane}_short.txt").read_text()
            # Find proper nouns: capitalized words not at sentence start, not common words
            common_words = {
                "The", "He", "She", "They", "It", "His", "Her", "But", "And",
                "Then", "When", "What", "Where", "How", "After", "Before",
                "One", "Some", "Every", "Each", "This", "That", "For", "From",
                "God", "Lord", "Christ", "Jesus", "Bible", "Scripture",
                "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                "Saturday", "Sunday", "January", "February", "March", "April",
                "May", "June", "July", "August", "September", "October",
                "November", "December",
            }
            # Pattern: "named X", "X's", "X had", "X was", "X walked" etc.
            name_patterns = [
                r"(?:named|called)\s+([A-Z][a-z]{2,})",
                r"\b([A-Z][a-z]{2,})'s\b",
                r"\b([A-Z][a-z]{2,})\s+(?:had|was|is|walked|sat|stood|looked|turned|said|spoke|picked|set|ran|held|put|got|came|went|took|made|let|gave|felt|knew|saw|heard|asked|told|watched|waited|laughed|smiled|nodded|sighed|paused|leaned|pressed|lifted|pulled|pushed|carried|placed|opened|closed|reached|touched|moved|started|stopped|began|tried|kept|found|left)\b",
            ]
            new_names = set()
            for pattern in name_patterns:
                for match in re.finditer(pattern, short_text):
                    name = match.group(1)
                    if name not in common_words and len(name) >= 3:
                        new_names.add(name)
            # Add any new names to the registry
            added = []
            for name in new_names:
                if name not in used_names:
                    used_names.append(name)
                    added.append(name)
            if added:
                names_file.write_text(json.dumps(sorted(used_names), indent=2) + "\n")
                print(f"  Registered character names: {added}")

        # ── Update registries ─────────────────────────────────────────
        if mode == "traditional":
            print(f"\n=== Updating anchor registry ===")
            anchors.append(args.anchor)
            anchors.sort()
            anchors_file.write_text(json.dumps(anchors, indent=2) + "\n")
            print(f"  Registered anchor: {args.anchor}")
        else:
            print(f"\n=== Updating theme registry ===")
            themes.append(theme_key)
            themes.sort()
            themes_file.write_text(json.dumps(themes, indent=2) + "\n")
            print(f"  Registered theme: {theme_key}")

    except Exception as exc:
        return fail_clean(str(exc))

    # ── Verification ──────────────────────────────────────────────────
    print(f"\n=== Verification ===")
    for f in sorted(outdir.iterdir()):
        size = f.stat().st_size
        extra = ""
        if f.suffix == ".txt" and "story" in f.name:
            extra = f" ({len(f.read_text().split())} words)"
        print(f"  {f.name}: {size:,} bytes{extra}")

    elapsed = time.time() - t0
    print(f"\nDONE. Story {sid} ({mode}) generated in {elapsed:.1f}s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
