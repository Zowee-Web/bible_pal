#!/usr/bin/env python3
"""
Bible PAL — Opus 4.6 Story Generation Pipeline

Pipeline stages:
  1. Opus generates story text
  2. Deterministic lint pass (banned patterns)
  3. Cheap model audit (Haiku) for interpretation drift
  4. Surgical repair pass (Opus) if needed
  5. Write to disk only after passing all gates

Usage:
  python3 scripts/generate_story_opus.py --story-id 1064 --mode traditional \
    --mood anxious --anchor "Genesis 22:1-19" --bible-key "binding_of_isaac" \
    --voice VOICE_ELIJAH_SAGE --title "The Binding of Isaac"

  python3 scripts/generate_story_opus.py --story-id 2064 --mode creative \
    --mood anxious --voice VOICE_PETER_BOLD --title "The Envelope" \
    --theme "anxiety and the weight of waiting"

  # Dry run (generate but don't write)
  python3 scripts/generate_story_opus.py --story-id 1064 --mode traditional \
    --mood anxious --anchor "Genesis 22:1-19" --dry-run

  # Kid-friendly version
  python3 scripts/generate_story_opus.py --story-id 1064 --mode traditional \
    --mood anxious --anchor "Genesis 22:1-19" --kid
"""

import anthropic
import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OPUS_MODEL = "claude-opus-4-6"
HAIKU_MODEL = "claude-haiku-4-5-20251001"
SONNET_MODEL = "claude-sonnet-4-6"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
STORIES_DIR = PROJECT_ROOT / "assets" / "stories"

# Bridge to canonical lane-differentiation prompts (story_factory/story_prompts.py).
# Adds sacred-proclamation (KJV) and sacred-witnessing (WEB) structural blocks
# plus translation voice exemplars (Luke 2:8-14 in each lane).
sys.path.insert(0, str(PROJECT_ROOT / "scripts" / "story_factory"))
from story_prompts import (  # noqa: E402
    _CLASSIC_LANE_STRUCTURE,
    _MODERN_LANE_STRUCTURE,
    _KJV_AUDIO_RULES,
    _KJV_VOICE_EXEMPLAR,
    _WEB_VOICE_EXEMPLAR,
)

# Load .env
def load_env():
    env_path = PROJECT_ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                os.environ.setdefault(key.strip(), val.strip())

load_env()

# ---------------------------------------------------------------------------
# Prompt Components
# ---------------------------------------------------------------------------

TRADITIONAL_WORD_TARGETS = {
    "short": (350, 450),
    "full": (700, 850),
    "long": (1201, 1400),
}

CREATIVE_WORD_TARGETS = {
    "short": (250, 380),
    "full": (450, 650),
    "long": (750, 1050),
}

# Banned patterns for deterministic lint (case-insensitive)
BANNED_PATTERNS = [
    # Internal states
    r"\bhe felt\b",
    r"\bshe felt\b",
    r"\bhe knew\b",
    r"\bshe knew\b",
    r"\bhe believed\b",
    r"\bshe believed\b",
    r"\bhe thought\b",
    r"\bshe thought\b",
    r"\bhe wondered\b",
    r"\bshe wondered\b",
    r"\bhe realized\b",
    r"\bshe realized\b",
    r"\bhe understood\b",
    r"\bshe understood\b",
    r"\bmust have been thinking\b",
    r"\bmust have been terrifying\b",
    r"\bmust have been wondering\b",
    r"\bmust have felt\b",
    r"\bcould hardly believe\b",
    r"\bcouldn't understand\b",
    # Interpretation / meaning
    r"\bthis showed\b",
    r"\bthis meant\b",
    r"\bit meant\b",
    r"\bthe covenant was\b",
    r"\bthe kindness of god\b.*different",
    r"\bchanged .* life forever\b",
    r"\bthe strongest kind of promise\b",
    r"\beverything that showed who\b",
    r"\beverything that said who\b",
    r"\bevery piece of his identity\b",
    r"\bwore another man's life\b",
    r"\bwore another person's life\b",
    # Narrator editorial
    r"\bthe most wonderful words\b",
    r"\bthe best words .* could have heard\b",
    r"\bwords .* have been repeating for\b",
    r"\bpeople .* still .* repeating\b",
    r"\bthat still make .* stop and think\b",
    r"\bthose were ways people\b",
    # Poetic summary
    r"\bhidden\. forgotten\. lame\.\b",
]

BANNED_ENDING_PATTERNS = [
    r"\band they believed\b",
    r"\band he believed\b",
    r"\band she believed\b",
    r"\bhe trusted that\b",
    r"\bshe trusted that\b",
    r"\bthe covenant was made\b",
    r"\bthat's how .* began\b",
    r"\band it never ended\b",
    r"\band it held\b$",
    r"\bfull heart\b",
]

# Gold standard endings (for prompt)
GOLD_ENDINGS = """
GOLD STANDARD ENDINGS (match this quality):

1. David & Jonathan (1052):
"The court was quiet. The stone floor stretched between them. Somewhere outside
the high windows a bird called twice and stopped. The light shifted as a cloud
moved. Jonathan's hands hung at his sides. David's arms were full. Neither of
them moved."

2. The Potter (1050):
"The wheel turned. The potter lifted his hands away and the vessel stood on the
spinning stone — squat and broad and whole, its walls even, its rim true. Water
glistened on its surface. The potter reached for a wire to cut it free from the
wheel, sliding the thin cord beneath the base where clay met stone."

3. Job (1055):
"The torn robe lay across the floor, its edges frayed. The shorn hair lay in
the dust beside his knees. The four messengers stood in the doorway, breathing
hard, the light behind them. In all this Job did not sin or charge God with wrong."
"""

NEGATIVE_EXAMPLES = """
DO NOT write lines like these (real failures from prior batches):
- "He wore another man's life" (identity interpretation)
- "The kindness of God — a different thing entirely" (meaning explanation)
- "Hidden. Forgotten. Lame." (poetic summary)
- "And they believed in the Lord" (internal state as ending)
- "It was what pleased the potter" (intent interpretation)
- "The covenant was made in the giving" (significance statement)
- "He must have been thinking..." (invented inner monologue)
- "What he said next changed his life forever" (narrator editorial)
- "The most wonderful words" (narrator judgment)
- "Those were ways people showed the deepest sadness" (cultural explanation)
- "Kings did not search for heirs to show kindness. Kings searched for them to remove them." (editorial commentary)
"""

# ---------------------------------------------------------------------------
# Prompt Builder
# ---------------------------------------------------------------------------

def build_generation_prompt(
    mode: str,
    mood: str,
    anchor: Optional[str],
    title: str,
    kid: bool,
    lengths: list[str],
    voice: str,
    theme: Optional[str] = None,
    bible_key: Optional[str] = None,
    passage_summary: Optional[str] = None,
) -> str:
    targets = TRADITIONAL_WORD_TARGETS if mode == "traditional" else CREATIVE_WORD_TARGETS

    length_instructions = []
    for length in lengths:
        lo, hi = targets[length]
        aim = (lo + hi) // 2
        length_instructions.append(f"- {length}: {lo}-{hi} words (aim {aim})")

    if mode == "traditional":
        # The WEB primary generation now carries Modern-lane sacred-witnessing
        # framing + WEB voice exemplar. The KJV rewrite (build_kjv_prompt) layers
        # sacred-proclamation framing on top of this base prose.
        mode_rules = (
            """
## TRADITIONAL MODE RULES (NON-NEGOTIABLE)
- Faithful retelling of the specific Bible passage
- Preserve ALL characters, event order, outcomes from scripture
- Third-person narrative
- NO invented motives, inner thoughts, or monologue
- NO devotional commentary or theology
- NO interpretation of what events mean
- NO symbolic or explanatory endings
- NO narrator editorial ("the most wonderful words", "this showed...")
- Story MUST end where the passage ends

## ENDING RULE (CRITICAL — most important rule)
Your FINAL PARAGRAPH must contain ONLY:
- What can be SEEN (physical image)
- What is HAPPENING (action)
- What is SAID (dialogue)

If your last sentence explains what something MEANS → DELETE IT.
If your last paragraph summarizes significance → DELETE IT.
End on a concrete image, a final action, or the last line of dialogue.
"""
            + _MODERN_LANE_STRUCTURE
            + _WEB_VOICE_EXEMPLAR
        )
    else:
        mode_rules = """
## CREATIVE MODE RULES
- Original story with biblical themes (NOT a Bible retelling)
- No scripture claims, no doctrine, no commands, no advice
- Third-person narrative
- End with quiet hope — but through IMAGE or ACTION, not explanation
- Interiority is allowed (unlike traditional) but use sparingly
"""

    kid_rules = ""
    if kid:
        kid_rules = """
## KID-FRIENDLY RULES (ages 5-10)
- Simple vocabulary, concrete imagery
- Warm gentle tone like a parent at bedtime
- Still scripture-faithful (traditional) or theme-faithful (creative)
- Short paragraphs (1-3 sentences)
- NO lessons, morals, or explanations of meaning
"""

    passage_info = ""
    if anchor and passage_summary:
        passage_info = f"""
## PASSAGE
Scripture: {anchor}
Summary: {passage_summary}
"""
    elif anchor:
        passage_info = f"\n## PASSAGE\nScripture: {anchor}\n"

    prompt = f"""Generate a Bible PAL {mode} story.

Title: {title}
Mood: {mood}
Voice: {voice}
{"Theme: " + theme if theme else ""}
{"Kid-friendly: yes" if kid else ""}
{passage_info}
{mode_rules}
{kid_rules}

## WORD COUNT TARGETS (HARD — YOU MUST HIT THESE)
{chr(10).join(length_instructions)}

WORD COUNT IS A HARD REQUIREMENT. Count your words. If you are under target:
- Traditional SHORT (350-450): expand scene transitions, physical environment,
  crowd/character reactions, sensory detail (sounds, smells, textures).
- Traditional FULL (700-850): this is a LONG story. Slow the pacing. Expand
  every scene. Add environmental detail between dialogue. Describe arrivals,
  departures, weather, terrain, clothing, tools, animals. Each verse of
  scripture should expand to 2-4 paragraphs of physical narration.
- Creative SHORT (250-380): tight and vivid. Every sentence earns its place.
- Creative FULL (450-650): more scene detail, more dialogue, more sensory
  moments than the short. But DO NOT exceed 650.

Exception: if the passage is structurally very short (< 4 verses), the full
version may fall below 700. Do NOT add interpretation to compensate.

## NARRATION RHYTHM
- Sentences 8-18 words preferred
- Short emphasis sentences (1-5 words) periodically
- Paragraphs 1-3 sentences
- Dialogue interrupts exposition
- Vary sentence lengths

## QUALITY: DANIEL STANDARD
Every paragraph has observable action or dialogue. Physical sensory detail.
Audio-ready pacing. No filler, no commentary.

{NEGATIVE_EXAMPLES}

{GOLD_ENDINGS}

## OUTPUT FORMAT
Generate each length as a separate section, clearly marked:

===SHORT===
[story text here]
===END_SHORT===

===FULL===
[story text here]
===END_FULL===

{"===LONG===" + chr(10) + "[story text here]" + chr(10) + "===END_LONG===" if "long" in lengths else ""}

Write ONLY prose inside the markers. No preamble, no word counts, no metadata.
"""
    return prompt


def build_kjv_prompt(web_text: str, length: str) -> str:
    """Rewrite a WEB-lane story into the Classic (KJV-style) lane.

    This is not a translation pass — it is a re-voicing into the Sacred
    Proclamation register. Same events, same scene structure, same ending
    style, but the prose itself is rewritten in KJV cadence and diction
    (NOT in copy-pasted KJV phrasing).
    """
    return (
        "Rewrite this Bible PAL story in the Classic (KJV-style) lane voice. "
        "You are re-voicing it, not merely translating individual words.\n\n"
        "Structural requirements (do NOT change these):\n"
        "- Same events, same scene order, same scene expansion\n"
        "- Same paragraph structure and beats\n"
        "- Same ending (action/image/dialogue — no interpretation)\n"
        "- Do NOT add or remove any content\n"
        "- Do NOT change the length tier (this is a "
        f"{length.upper()} story; keep its word count within ±10%)\n\n"
        "Voice transformation (this is where the work happens):"
        + _CLASSIC_LANE_STRUCTURE
        + _KJV_AUDIO_RULES
        + _KJV_VOICE_EXEMPLAR
        + f"\n\nORIGINAL (Modern / WEB lane):\n{web_text}\n\n"
        "Now write the Classic (KJV-style) lane version. Output ONLY the "
        "rewritten prose. No preamble, no markers, no commentary."
    )


def build_reflection_prompt(mode: str, title: str, mood: str, kid: bool) -> str:
    if kid:
        return f"""Write a single reflection question for a child (ages 5-10) about this story: "{title}" (mood: {mood}).
The question should be warm, simple, and open-ended. 1-2 sentences max.
No commands, no advice, no theology. Just a gentle question.
Write ONLY the question text."""
    else:
        return f"""Write a single reflection question for an adult about this story: "{title}" (mood: {mood}, mode: {mode}).
The question should be contemplative and non-directive. 2-3 sentences max.
No commands, no advice, no doctrine. Just a question that sits with the listener.
Write ONLY the question text."""


# ---------------------------------------------------------------------------
# Lint Pass (deterministic)
# ---------------------------------------------------------------------------

def lint_story(text: str, mode: str) -> list[dict]:
    """Run deterministic pattern checks. Returns list of violations."""
    if mode != "traditional":
        return []  # Creative stories allow more interiority

    violations = []
    lines = text.strip().split("\n")

    # Check all lines for banned patterns
    for i, line in enumerate(lines):
        for pattern in BANNED_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                violations.append({
                    "line": i + 1,
                    "type": "banned_pattern",
                    "pattern": pattern,
                    "text": line.strip(),
                })

    # Check last 5 lines specifically for ending patterns
    last_lines = "\n".join(lines[-5:])
    for pattern in BANNED_ENDING_PATTERNS:
        if re.search(pattern, last_lines, re.IGNORECASE):
            violations.append({
                "line": len(lines),
                "type": "banned_ending",
                "pattern": pattern,
                "text": last_lines.strip()[-200:],
            })

    return violations


# ---------------------------------------------------------------------------
# Audit Pass (Haiku)
# ---------------------------------------------------------------------------

def audit_story(client: anthropic.Anthropic, text: str, mode: str) -> list[str]:
    """Use cheap model to audit for interpretation drift. Returns flagged lines."""
    if mode != "traditional":
        return []

    # Focus on ending first (most common violation location)
    lines = text.strip().split("\n")
    last_section = "\n".join(lines[-8:]) if len(lines) > 8 else text

    prompt = f"""Read this Traditional Bible story ending. Flag any line that contains:
1. Internal thoughts or emotions stated as fact ("he believed", "she felt", "he knew")
2. Narrator interpretation ("this showed", "the covenant was", "it meant")
3. Identity/significance statements ("everything that made him who he was")
4. Cultural explanation ("those were ways people showed...")
5. Narrator editorial ("the most wonderful words", "words people have been repeating")

Text to audit:
{last_section}

IMPORTANT: Direct scripture quotations (God speaking, characters quoting scripture) are NOT violations.
Only flag NARRATOR prose that interprets, explains, or assigns internal states.

If ALL narrator lines are clean observable prose (action/image/dialogue), respond with exactly: CLEAN
If any violations found, list ONLY the violating NARRATOR lines, one per line, prefixed with "FLAG: "
"""

    response = client.messages.create(
        model=HAIKU_MODEL,
        max_tokens=500,
        messages=[{"role": "user", "content": prompt}],
    )

    result = response.content[0].text.strip()
    if result == "CLEAN":
        return []

    flagged = []
    for line in result.split("\n"):
        if line.startswith("FLAG:"):
            flagged.append(line[5:].strip())
    return flagged


# ---------------------------------------------------------------------------
# Repair Pass (Opus)
# ---------------------------------------------------------------------------

def repair_story(client: anthropic.Anthropic, text: str, violations: list[str]) -> str:
    """Surgical fix of flagged lines. One pass only."""
    violation_list = "\n".join(f"- {v}" for v in violations)

    prompt = f"""Fix this Traditional Bible story by removing ONLY the violating lines listed below.

RULES:
- Remove or replace ONLY the listed violations
- Do NOT rewrite the whole story
- Do NOT add new content
- Do NOT change the ending style (must end on action/image/dialogue)
- Keep all surrounding prose unchanged
- Replace internal states with observable action where possible

VIOLATIONS TO FIX:
{violation_list}

FULL STORY:
{text}

Output the COMPLETE corrected story. Nothing else."""

    response = client.messages.create(
        model=OPUS_MODEL,
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )

    return response.content[0].text.strip()


# ---------------------------------------------------------------------------
# Text Extraction
# ---------------------------------------------------------------------------

def extract_sections(response_text: str) -> dict[str, str]:
    """Extract ===SHORT===, ===FULL===, ===LONG=== sections from response."""
    sections = {}
    for length in ["SHORT", "FULL", "LONG"]:
        pattern = f"==={length}===(.*?)===END_{length}==="
        match = re.search(pattern, response_text, re.DOTALL)
        if match:
            sections[length.lower()] = match.group(1).strip()
    return sections


# ---------------------------------------------------------------------------
# Main Pipeline
# ---------------------------------------------------------------------------

def generate_story(
    story_id: int,
    mode: str,
    mood: str,
    voice: str,
    title: str,
    anchor: Optional[str] = None,
    bible_key: Optional[str] = None,
    kid: bool = False,
    theme: Optional[str] = None,
    passage_summary: Optional[str] = None,
    batch: str = "PAL_OPUS_BATCH_04",
    dry_run: bool = False,
    skip_long: bool = False,
):
    client = anthropic.Anthropic()

    mode_dir = "traditional" if story_id < 2000 else "creative"
    story_dir = STORIES_DIR / mode_dir / str(story_id)
    story_dir.mkdir(parents=True, exist_ok=True)

    # Determine lengths
    lengths = ["short", "full"]
    if not skip_long:
        lengths.append("long")

    has_kjv = not kid and mode == "traditional"
    lanes = ["web", "kjv"] if has_kjv else ["web"]

    print(f"\n{'='*60}")
    print(f"  Story {story_id} — {mode} {'kid ' if kid else ''}— {mood}")
    print(f"  {title}")
    print(f"{'='*60}")

    # ── Stage 1: Generate ──────────────────────────────────────
    print("\n[1/5] Generating with Opus...")
    prompt = build_generation_prompt(
        mode=mode, mood=mood, anchor=anchor, title=title,
        kid=kid, lengths=lengths, voice=voice, theme=theme,
        bible_key=bible_key, passage_summary=passage_summary,
    )

    response = client.messages.create(
        model=OPUS_MODEL,
        max_tokens=8192,
        messages=[{"role": "user", "content": prompt}],
    )

    sections = extract_sections(response.content[0].text)
    if not sections:
        print("  ERROR: No sections found in response. Raw output:")
        print(response.content[0].text[:500])
        return False

    # Check if long was actually generated
    if "long" in lengths and "long" not in sections:
        lengths = ["short", "full"]
        print("  Note: Long not generated (passage may be too short)")

    # Word count check
    targets = TRADITIONAL_WORD_TARGETS if mode == "traditional" else CREATIVE_WORD_TARGETS
    for length, text in sections.items():
        wc = len(text.split())
        lo, hi = targets[length]
        status = "✓" if lo <= wc <= hi else "⚠"
        print(f"  {length}: {wc}w {status} (target {lo}-{hi})")

    # ── Stage 2: Deterministic Lint ────────────────────────────
    print("\n[2/5] Running lint pass...")
    all_violations = {}
    for length, text in sections.items():
        violations = lint_story(text, mode)
        if violations:
            all_violations[length] = violations
            for v in violations:
                print(f"  ⚠ {length} line {v['line']}: {v['type']} — {v['text'][:80]}")

    if not all_violations:
        print("  ✓ Lint clean")

    # ── Stage 3: Model Audit ───────────────────────────────────
    print("\n[3/5] Running Haiku audit...")
    all_flagged = {}
    for length, text in sections.items():
        flagged = audit_story(client, text, mode)
        if flagged:
            all_flagged[length] = flagged
            for f in flagged:
                print(f"  ⚠ {length}: {f[:80]}")

    if not all_flagged:
        print("  ✓ Audit clean")

    # ── Stage 4: Surgical Repair ───────────────────────────────
    needs_repair = set(all_violations.keys()) | set(all_flagged.keys())
    if needs_repair:
        print(f"\n[4/5] Repairing {len(needs_repair)} sections...")
        for length in needs_repair:
            violations = []
            if length in all_violations:
                violations.extend(v["text"] for v in all_violations[length])
            if length in all_flagged:
                violations.extend(all_flagged[length])

            repaired = repair_story(client, sections[length], violations)
            sections[length] = repaired

            # Re-lint after repair
            post_violations = lint_story(repaired, mode)
            if post_violations:
                print(f"  ⚠ {length}: {len(post_violations)} violations remain after repair — MANUAL REVIEW")
            else:
                print(f"  ✓ {length}: repaired and clean")
    else:
        print("\n[4/5] No repairs needed")

    # ── Stage 5: Write to Disk ─────────────────────────────────
    if dry_run:
        print("\n[5/5] DRY RUN — not writing to disk")
        for length, text in sections.items():
            print(f"\n--- {length} ({len(text.split())}w) ---")
            print(text[:300] + "..." if len(text) > 300 else text)
        return True

    print("\n[5/5] Writing to disk...")

    # Write WEB stories
    actual_lengths = []
    for length, text in sections.items():
        fname = f"story_{story_id}_{mode}_web_{length}.txt"
        (story_dir / fname).write_text(text.strip() + "\n")
        actual_lengths.append(length)
        print(f"  ✓ {fname} ({len(text.split())}w)")

    # Generate and write KJV versions
    if has_kjv:
        print("  Generating KJV versions...")
        for length in actual_lengths:
            web_text = sections[length]
            kjv_prompt = build_kjv_prompt(web_text, length)
            kjv_response = client.messages.create(
                model=OPUS_MODEL,
                max_tokens=4096,
                messages=[{"role": "user", "content": kjv_prompt}],
            )
            kjv_text = kjv_response.content[0].text.strip()
            fname = f"story_{story_id}_{mode}_kjv_{length}.txt"
            (story_dir / fname).write_text(kjv_text + "\n")
            print(f"  ✓ {fname} ({len(kjv_text.split())}w)")

    # Generate reflections
    print("  Generating reflections...")
    refl_prompt = build_reflection_prompt(mode, title, mood, kid)
    refl_response = client.messages.create(
        model=OPUS_MODEL,
        max_tokens=200,
        messages=[{"role": "user", "content": refl_prompt}],
    )
    refl_text = refl_response.content[0].text.strip()
    refl_fname = f"reflection_{story_id}_{mode}_web.txt"
    (story_dir / refl_fname).write_text(refl_text + "\n")
    print(f"  ✓ {refl_fname}")

    if has_kjv:
        kjv_refl_prompt = (
            "Rewrite this Bible PAL reflection in the Classic (KJV-style) lane "
            "voice. This is re-voicing, not word-for-word translation.\n\n"
            "Keep:\n"
            "- Same observations and invitations to notice\n"
            "- Same length (±10%)\n"
            "- The reverent, non-prescriptive register (no advice, no commands)\n\n"
            "Transform the voice:\n"
            "- Permit (do NOT mandate) thou/thee/thy, -eth/-est verb forms, "
            "and archaic markers ('unto', 'spake', 'hath', 'saith') where they "
            "aid solemnity. Real KJV varies — do not force these on every line.\n"
            "- No contractions. Use 'do not', 'is not', etc.\n"
            "- Maintain Hebraic parallelism in cadence where possible.\n"
            "- Avoid pastiche or comedy-bit register. If it sounds like a "
            "costume drama, simplify.\n\n"
            f"ORIGINAL (Modern / WEB lane):\n{refl_text}\n\n"
            "Write ONLY the rewritten reflection."
        )
        kjv_refl_response = client.messages.create(
            model=HAIKU_MODEL,
            max_tokens=200,
            messages=[{"role": "user", "content": kjv_refl_prompt}],
        )
        kjv_refl_text = kjv_refl_response.content[0].text.strip()
        kjv_refl_fname = f"reflection_{story_id}_{mode}_kjv.txt"
        (story_dir / kjv_refl_fname).write_text(kjv_refl_text + "\n")
        print(f"  ✓ {kjv_refl_fname}")

    # Write meta JSON
    actual_lengths_sorted = sorted(actual_lengths, key=lambda x: ["short", "full", "long"].index(x))
    files = {}
    for l in actual_lengths_sorted:
        files[l] = {"storyText": f"story_{story_id}_{mode}_web_{l}.txt"}
    if has_kjv:
        for l in actual_lengths_sorted:
            files[f"{l}_kjv"] = {"storyText": f"story_{story_id}_{mode}_kjv_{l}.txt"}
    files["reflection"] = {"reflectionText": refl_fname}
    if has_kjv:
        files["reflection_kjv"] = {"reflectionText": f"reflection_{story_id}_{mode}_kjv.txt"}

    meta = {
        "schemaVersion": 2,
        "storyId": story_id,
        "mode": mode,
        "kidFriendly": kid,
        "languageStyle": "WEB",
        "lanes": lanes,
        "mood": mood,
        "lengths": actual_lengths_sorted,
        "voiceKey": voice,
        "createdByModel": "claude-opus-4-6",
        "generationBatch": batch,
        "reflectionQuestion": refl_text,
        "title": title,
        "files": files,
        "reflectionSource": "llm",
        "storyVoiceKey": voice,
    }

    if anchor:
        meta["scriptureAnchor"] = anchor
    if bible_key:
        meta["bibleStoryKey"] = bible_key
    if theme:
        meta["theme"] = theme
    if has_kjv:
        meta["reflections"] = {
            "web": refl_fname,
            "kjv": f"reflection_{story_id}_{mode}_kjv.txt",
        }

    meta_fname = f"meta_{story_id}.json"
    (story_dir / meta_fname).write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    print(f"  ✓ {meta_fname}")

    total_files = len(list(story_dir.iterdir()))
    print(f"\n  COMPLETE: {total_files} files in {story_dir.relative_to(PROJECT_ROOT)}")
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Bible PAL Opus Story Generator")
    parser.add_argument("--story-id", type=int, required=True)
    parser.add_argument("--mode", choices=["traditional", "creative"], required=True)
    parser.add_argument("--mood", required=True)
    parser.add_argument("--voice", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--anchor", help="Scripture reference (traditional)")
    parser.add_argument("--bible-key", help="Bible story key")
    parser.add_argument("--kid", action="store_true")
    parser.add_argument("--theme", help="Story theme (creative)")
    parser.add_argument("--passage-summary", help="Brief summary of the passage")
    parser.add_argument("--batch", default="PAL_OPUS_BATCH_04")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-long", action="store_true")

    args = parser.parse_args()

    success = generate_story(
        story_id=args.story_id,
        mode=args.mode,
        mood=args.mood,
        voice=args.voice,
        title=args.title,
        anchor=args.anchor,
        bible_key=args.bible_key,
        kid=args.kid,
        theme=args.theme,
        passage_summary=args.passage_summary,
        batch=args.batch,
        dry_run=args.dry_run,
        skip_long=args.skip_long,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
