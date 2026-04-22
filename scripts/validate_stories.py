#!/usr/bin/env python3
"""
Bible PAL Traditional Story Validator

Scans assets/stories/traditional/**/story_*.txt for:
  1. Ending discipline violations (stacked imagery, atmosphere)
  2. Mid-scene cinematic layering
  3. Zero-interpretation banned words
  4. Audio readability risks (long sentences, comma overload)

Read-only — never modifies files.

Usage:
  python3 scripts/validate_stories.py
  python3 scripts/validate_stories.py --fix-suggestions
  python3 scripts/validate_stories.py --path assets/stories/traditional/1111
"""

import argparse
import glob
import os
import re
import sys

# --- Constants ---

ATMOSPHERE_WORDS = [
    "light", "silence", "quiet", "dark", "shadow", "evening", "air",
    "stillness", "warmth", "glow", "hush",
]

BANNED_PHRASES = [
    "felt", "realized", "perhaps", "seemed", "understood",
    "this showed", "this shows",
    "they were changed",
]

# These need context-aware matching (not simple substring)
CONTEXT_BANNED = {
    # "meant" is banned in explanatory use ("the robe meant") but OK in
    # scripture action ("asked what these things meant")
    "meant": {
        "allow_patterns": [r"what\s+\w+\s+meant", r"things\s+meant"],
    },
    # "they knew" is banned in interpretation ("they knew he was right") but OK
    # in scripture recognition ("they knew him")
    "they knew": {
        "allow_patterns": [r"they knew him"],
    },
    "he knew": {
        "allow_patterns": [r"he knew that he had been", r"he knew her not"],
    },
    "she knew": {
        "allow_patterns": [],
    },
    "it meant": {
        "allow_patterns": [],
    },
}

# Verbs that indicate static/descriptive (not action) sentences
PASSIVE_VERBS = {"was", "were", "lay", "sat", "stood", "hung", "stretched", "fell"}

# Thresholds
MAX_SENTENCE_WORDS = 28
MAX_COMMAS = 3  # flag at >= 4

# --- Helpers ---


def split_sentences(line: str) -> list[str]:
    """Split a line into sentences on period boundaries."""
    parts = re.split(r'(?<=[.!?])\s+', line.strip())
    return [p for p in parts if p.strip()]


def word_count(text: str) -> int:
    return len(text.split())


def get_lines(filepath: str) -> list[str]:
    with open(filepath, "r", encoding="utf-8") as f:
        return f.readlines()


def get_content_lines(lines: list[str]) -> list[tuple[int, str]]:
    """Return (1-based line number, stripped text) for non-empty lines."""
    result = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped:
            result.append((i + 1, stripped))
    return result


# --- Check 1: Ending Discipline ---


def check_ending(filepath: str, content_lines: list[tuple[int, str]]) -> list[str]:
    issues = []
    if not content_lines:
        return issues

    last_lineno, last_line = content_lines[-1]

    # Only check image sentences at the tail of the final line.
    # Scripture action sentences ("And they rose up...", "So David...") are
    # not images — only count static/descriptive sentences.
    ACTION_STARTS = (
        "and they", "and he", "and she", "and it", "so ", "then ",
        "they ", "he ", "she ", "but ", "for ",
    )
    sentences = split_sentences(last_line)
    image_tail = 0
    for s in reversed(sentences):
        s_lower = s.strip().lower()
        # Stop counting if we hit dialogue or a scripture action sentence
        if (s_lower.startswith('"') or s_lower.startswith('\u201c') or
                any(s_lower.startswith(p) for p in ACTION_STARTS)):
            break
        image_tail += 1
    if image_tail > 2:
        issues.append(
            f"[ENDING] {os.path.basename(filepath)} "
            f"→ stacked imagery ({image_tail} image sentences at end)"
        )

    # Check for atmosphere words in final line
    lower = last_line.lower()
    found = [w for w in ATMOSPHERE_WORDS if w in lower]
    if found:
        # Allow "light" only in compound nouns like "morning light" if part of
        # scripture action — but flag standalone atmosphere
        # Filter out false positives in dialogue (inside quotes)
        outside_quotes = re.sub(r'"[^"]*"', '', lower)
        found_outside = [w for w in ATMOSPHERE_WORDS if w in outside_quotes]
        if found_outside:
            issues.append(
                f"[ENDING] {os.path.basename(filepath)} "
                f"→ atmosphere word in final line: {found_outside}"
            )

    # Check if second-to-last content line is also a physical image (not dialogue)
    if len(content_lines) >= 2:
        prev_lineno, prev_line = content_lines[-2]
        if (not prev_line.startswith('"') and
                not prev_line.startswith('"') and
                not prev_line.startswith("And ") and
                not prev_line.startswith("So ") and
                not prev_line.startswith("Then ") and
                not prev_line.startswith("They ")):
            # Both last two lines are non-dialogue, non-action — possible stacking
            pass  # handled by mid-scene check

    return issues


# --- Check 2: Mid-Scene Layering ---


def check_midscene(filepath: str, content_lines: list[tuple[int, str]]) -> list[str]:
    issues = []

    # Look for runs of 2+ consecutive non-dialogue lines where the main verbs
    # are all passive/static
    run_start = None
    run_length = 0

    for i, (lineno, line) in enumerate(content_lines):
        # Skip dialogue lines
        if line.startswith('"') or line.startswith('"') or '"' in line[:5]:
            if run_length >= 3:
                issues.append(
                    f"[MID-SCENE] {os.path.basename(filepath)} "
                    f"→ cinematic layering block "
                    f"(lines {run_start}–{content_lines[i-1][0]})"
                )
            run_length = 0
            run_start = None
            continue

        # Check if line is primarily static/descriptive
        words = set(line.lower().split())
        has_passive = bool(words & PASSIVE_VERBS)
        # Check if line has active verbs (not just passive)
        # Simple heuristic: short line with only passive verbs = descriptive
        sentences = split_sentences(line)
        all_static = True
        for sent in sentences:
            sent_words = sent.lower().split()
            # If sentence has an active verb (not in passive set), it's action
            verbs_found = [w.rstrip(".,;:!?") for w in sent_words
                           if w.rstrip(".,;:!?") in PASSIVE_VERBS]
            if not verbs_found and len(sent_words) > 3:
                # No passive verbs and not trivially short — likely action
                all_static = False
                break

        # Only count as static if line doesn't contain proper nouns (names)
        # and has atmosphere-adjacent content. Scripture narration with "was/were"
        # is not cinematic layering.
        has_atmosphere = any(w in line.lower() for w in ATMOSPHERE_WORDS)
        is_short_fragment = len(line.split()) <= 8

        if all_static and has_passive and (has_atmosphere or is_short_fragment):
            if run_start is None:
                run_start = lineno
            run_length += 1
        else:
            if run_length >= 3:
                issues.append(
                    f"[MID-SCENE] {os.path.basename(filepath)} "
                    f"→ cinematic layering block "
                    f"(lines {run_start}–{content_lines[i-1][0]})"
                )
            run_length = 0
            run_start = None

    # Check trailing run
    if run_length >= 3:
        issues.append(
            f"[MID-SCENE] {os.path.basename(filepath)} "
            f"→ cinematic layering block "
            f"(lines {run_start}–{content_lines[-1][0]})"
        )

    return issues


# --- Check 3: Zero-Interpretation ---


def check_interpretation(
    filepath: str, content_lines: list[tuple[int, str]]
) -> list[str]:
    issues = []

    for lineno, line in content_lines:
        lower = line.lower()

        # Skip content inside dialogue quotes
        outside_quotes = re.sub(r'"[^"]*"', '', lower)
        outside_quotes = re.sub(r'\u201c[^\u201d]*\u201d', '', outside_quotes)

        # Simple banned phrases (no context needed)
        for phrase in BANNED_PHRASES:
            if phrase in outside_quotes:
                idx = outside_quotes.index(phrase)
                start = max(0, idx - 10)
                end = min(len(outside_quotes), idx + len(phrase) + 10)
                context = outside_quotes[start:end].strip()
                issues.append(
                    f"[INTERPRETATION] {os.path.basename(filepath)} "
                    f"line {lineno} → \"{phrase}\" in: ...{context}..."
                )

        # Context-aware banned phrases (check allow patterns first)
        for phrase, rules in CONTEXT_BANNED.items():
            if phrase in outside_quotes:
                # Check if any allow pattern matches
                allowed = False
                for pattern in rules.get("allow_patterns", []):
                    if re.search(pattern, outside_quotes):
                        allowed = True
                        break
                if not allowed:
                    idx = outside_quotes.index(phrase)
                    start = max(0, idx - 10)
                    end = min(len(outside_quotes), idx + len(phrase) + 10)
                    context = outside_quotes[start:end].strip()
                    issues.append(
                        f"[INTERPRETATION] {os.path.basename(filepath)} "
                        f"line {lineno} → \"{phrase}\" in: ...{context}..."
                    )

    return issues


# --- Check 4: Audio Readability ---


def check_audio(filepath: str, content_lines: list[tuple[int, str]]) -> list[str]:
    issues = []
    basename = os.path.basename(filepath)
    is_kjv = "_kjv_" in basename

    for lineno, line in content_lines:
        # Check if this line is dialogue (contains quotes)
        is_dialogue = '"' in line or '\u201c' in line

        sentences = split_sentences(line)
        for sent in sentences:
            wc = word_count(sent)
            commas = sent.count(",")

            # Scripture dialogue is inherently verbose — flag as INFO not WARNING
            severity = "INFO" if is_dialogue else "AUDIO"

            if wc > MAX_SENTENCE_WORDS:
                issues.append(
                    f"[{severity}] {basename} "
                    f"line {lineno} → long sentence ({wc} words)"
                )

            if commas > MAX_COMMAS:
                issues.append(
                    f"[{severity}] {basename} "
                    f"line {lineno} → comma-heavy ({commas} commas)"
                )

    return issues


# --- Fix Suggestions ---

ENDING_SUGGESTIONS = {
    "stacked imagery": "Reduce to a single concrete moment. Keep one image, cut the rest.",
    "atmosphere word": "Remove atmosphere words (light, silence, quiet, etc.) from final line.",
}


def suggest_fix(issue: str) -> str:
    for key, suggestion in ENDING_SUGGESTIONS.items():
        if key in issue:
            return f"  → Suggestion: {suggestion}"
    if "[MID-SCENE]" in issue:
        return "  → Suggestion: Keep 1-2 physical details. Cut descriptive stacking."
    if "[INTERPRETATION]" in issue:
        return "  → Suggestion: Remove or rephrase. Use observable action instead."
    if "[AUDIO]" in issue:
        if "long sentence" in issue:
            return "  → Suggestion: Split into two shorter sentences."
        if "comma" in issue:
            return "  → Suggestion: Break into shorter clauses or separate sentences."
    return ""


# --- Main ---


def find_story_files(base_path: str) -> list[str]:
    pattern = os.path.join(base_path, "**", "story_*.txt")
    return sorted(glob.glob(pattern, recursive=True))


def validate_file(filepath: str) -> list[str]:
    lines = get_lines(filepath)
    content_lines = get_content_lines(lines)

    issues = []
    issues.extend(check_ending(filepath, content_lines))
    issues.extend(check_midscene(filepath, content_lines))
    issues.extend(check_interpretation(filepath, content_lines))
    issues.extend(check_audio(filepath, content_lines))
    return issues


def main():
    parser = argparse.ArgumentParser(
        description="Validate Bible PAL Traditional story files"
    )
    parser.add_argument(
        "--path",
        default="assets/stories/traditional",
        help="Path to scan (default: assets/stories/traditional)",
    )
    parser.add_argument(
        "--fix-suggestions",
        action="store_true",
        help="Show fix suggestions for each issue",
    )
    args = parser.parse_args()

    base_path = args.path
    if not os.path.isabs(base_path):
        # Try relative to script location (project root)
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(script_dir)
        base_path = os.path.join(project_root, base_path)

    files = find_story_files(base_path)
    if not files:
        print(f"No story files found in {base_path}")
        sys.exit(1)

    all_issues: dict[str, list[str]] = {
        "ENDING": [],
        "MID-SCENE": [],
        "INTERPRETATION": [],
        "AUDIO": [],
        "INFO": [],
    }

    for filepath in files:
        issues = validate_file(filepath)
        for issue in issues:
            for category in all_issues:
                if f"[{category}]" in issue:
                    all_issues[category].append(issue)
                    break

    # Output — INFO is separate (not counted as failures)
    warn_categories = ["ENDING", "MID-SCENE", "INTERPRETATION", "AUDIO"]
    total = sum(len(all_issues[c]) for c in warn_categories)
    info_count = len(all_issues["INFO"])

    print(f"\n=== VALIDATION REPORT ===")
    print(f"Scanned {len(files)} files\n")

    for category in warn_categories:
        issues = all_issues[category]
        print(f"[{category}] ({len(issues)} issues)")
        if issues:
            for issue in issues:
                print(f"  {issue}")
                if args.fix_suggestions:
                    suggestion = suggest_fix(issue)
                    if suggestion:
                        print(f"  {suggestion}")
        else:
            print("  ✓ Clean")
        print()

    if info_count > 0:
        print(f"[INFO] ({info_count} notes — KJV dialogue, not failures)")
        if args.fix_suggestions:
            for issue in all_issues["INFO"]:
                print(f"  {issue}")
        print()

    if total == 0:
        print("✓ All files passed validation.")
        if info_count > 0:
            print(f"  ({info_count} informational notes — use --fix-suggestions to see)")
    else:
        print(f"⚠ {total} issues found across {len(files)} files.")

    sys.exit(1 if total > 0 else 0)


if __name__ == "__main__":
    main()
