"""
claude_validator.py — Unified story validation for Claude Opus 4.6 pipeline.

Combines:
- StoryModeValidator patterns (ported from lib/safety/story_mode_validator.dart)
- Traditional compliance phrases (from generate_traditional_story.py)
- Creative compliance phrases (from generate_creative_story.py)
- Meta-text detection
- Reflection banned phrases
- Kid forbidden word checking
"""

from __future__ import annotations

import json
import pathlib
import re
import time


# ── Meta-text blocklist ───────────────────────────────────────────────────
# Matched case-insensitively against the first ~200 chars of generated text.

META_TEXT_BLOCKLIST = [
    "here is", "here's", "this version", "certainly", "of course",
    "sure,", "sure!", "in this retelling", "expanded carefully",
    "staying true to", "the following", "this passage", "this story",
    "this verse", "this retelling", "this rendering", "this adaptation",
    "i've", "i have", "let me", "below is", "as requested", "as you asked",
    "happy to", "glad to", "i'd be", "i would be", "absolutely",
    "great question", "what a",
]


def check_meta_text(text: str) -> str | None:
    """Check for meta-text contamination in first ~200 chars.

    Returns the offending phrase if found, or None if clean.
    Uses word-boundary matching to avoid false positives
    (e.g., "There is" should NOT match "here is").
    """
    trimmed = text.lstrip()
    if not trimmed:
        return "empty output"
    opening = trimmed[:200].lower()
    for phrase in META_TEXT_BLOCKLIST:
        # Use word-boundary check: phrase must start at a word boundary
        pattern = r"(?:^|\b)" + re.escape(phrase)
        if re.search(pattern, opening):
            return phrase
    if trimmed.startswith("---") or trimmed.startswith("***"):
        return "leading separator"
    return None


# ── Traditional compliance phrases ────────────────────────────────────────
# High-confidence phrase patterns that indicate Traditional rule violations.

TRADITIONAL_VIOLATIONS = {
    "INNER_THOUGHTS": [
        "in their hearts", "in his heart", "in her heart",
        "every heart knows", "every heart knew",
        "hearts rested", "heart rested",
        "hearts stirred", "heart stirred",
        "hearts swelled", "heart swelled",
        "uncertainty fades", "uncertainty faded",
        "confidence settling", "confidence settled",
        "wide-eyed with trust",
        "felt a sense of", "felt a wave of", "felt the warmth of",
        "knew in that moment", "knowing deep",
        "hoped that", "hoping that",
        "wondered if", "wondered what",
    ],
    "INTERPRETIVE_THEOLOGY": [
        "every judgment is wise",
        "every act is kindness",
        "his words are a balm",
        "there is no bitterness in him",
        "he calls us back",
        "when we stray",
        "no shadow of burden",
        "no shadow of doubt",
    ],
    "SYMBOLISM_METAPHOR": [
        "golden thread",
        "river of song",
        "breathes with music", "breathed with music",
        "house breathes", "house breathed",
        "like an offering",
        "as if meeting an old friend",
    ],
    "FIRST_PERSON_TESTIMONY": [
        "i was a child once",
        "he formed my lungs",
        "he called my name",
        "painted the features of my face",
        "when i was lost",
        "lifted up by his mercy",
    ],
    "REALIZATION_EXPLANATION": [
        "she realized", "he realized", "they realized",
        "she understood", "he understood", "they understood",
        "something shifted", "something changed inside",
        "it meant", "the lesson was", "the lesson is",
        "what mattered was", "what mattered is",
    ],
    "SCENE_INTEGRITY": [
        "a yoke is", "a yoke was", "the yoke is", "the yoke was",
        "which meant", "which means",
        "in those days", "in that culture", "in their culture",
        "the word meant", "the word means",
        "the custom was", "the tradition was",
        "he had spent years", "she had spent years",
        "they had spent years",
        # Teacher voice leaks — contextualizing instead of showing
        "was commonly used for", "were commonly used for",
        "people in this region", "people of this region",
        "it was a symbol of", "it was a sign of",
        "this meant that", "this means that",
        "was known for", "were known for",
        "was considered", "were considered",
    ],
}


# ── Soft-flag patterns (warnings, not hard-fail) ─────────────────────────
# These indicate lyrical drift, especially in long-form. Logged for review.

LYRICAL_DRIFT_PHRASES = [
    "felt like",
    "as if",
    "as though",
    "the silence was",
    "the stillness was",
    "the darkness was",
    "the air seemed",
    "the world seemed",
    "something about",
]


def check_lyrical_drift(text: str) -> list[str]:
    """Check for lyrical/simile drift patterns. Returns list of phrases found.

    These are soft warnings for review, not hard violations.
    """
    found = []
    lower = text.lower()
    for phrase in LYRICAL_DRIFT_PHRASES:
        if phrase in lower:
            found.append(phrase)
    return found


# ── LONG version drift detection (hard-fail for LONG outputs) ─────────────
# LONG versions must match SHORT discipline. These patterns indicate drift.

LONG_VERSION_DRIFT_PHRASES = [
    # Meta-narration
    "the text declareth",
    "it is written",
    "it was known",
    "as it is said",
    "the scripture saith",
    "the passage telleth",
    # Commentary verbs (narrator stepping outside the camera)
    " seemed to ",
    " appeared to ",
]


def check_long_version_drift(text: str) -> list[str]:
    """Check LONG version for drift from SHORT discipline.

    Returns list of phrases found. These are hard violations for LONG outputs —
    if any are found, regenerate using SHORT as reference.
    """
    found = []
    lower = text.lower()
    for phrase in LONG_VERSION_DRIFT_PHRASES:
        if phrase in lower:
            found.append(phrase)
    return found


def check_traditional_compliance(text: str) -> list[tuple[str, str]]:
    """Check story text for Traditional mode violations.

    Returns list of (category, phrase) tuples for each violation found.
    Empty list means compliant.
    """
    violations = []
    lower = text.lower()
    for category, phrases in TRADITIONAL_VIOLATIONS.items():
        for phrase in phrases:
            if phrase in lower:
                violations.append((category, phrase))
    return violations


# ── Creative compliance phrases ───────────────────────────────────────────

CREATIVE_VIOLATIONS = {
    "SCRIPTURE_RETELLING": [
        "and jesus said", "and jesus spoke", "and jesus answered",
        "and moses said", "moses led the", "moses lifted",
        "and david said", "david picked up", "david took his",
        "and paul said", "paul wrote to",
        "and god said to", "the lord said to",
        "and the angel said",
    ],
    "SCRIPTURE_AUTHORITY": [
        "as the bible says", "as scripture says", "as it is written",
        "the word says", "the word of god says",
        "scripture tells us", "the bible tells us",
        "according to scripture", "in the book of",
        "chapter ", "verse ",
    ],
    "DIRECT_GOD_DIALOGUE": [
        "god said,", "god spoke,", "god replied,",
        "the lord said,", "the lord spoke,", "the lord replied,",
        "thus saith", "thus says the lord",
    ],
    "SPIRITUAL_COMMANDS": [
        "you should", "you must", "you need to",
        "remember to", "make sure you",
        "god commands", "the lord requires",
    ],
    "FEAR_FRAMING": [
        "you will be punished", "god will judge",
        "eternal damnation", "hellfire",
        "if you don't", "unless you repent",
    ],
    "REALIZATION_EXPLANATION": [
        "she realized", "he realized", "they realized",
        "she understood", "he understood", "they understood",
        "something shifted", "something changed inside",
        "it meant", "the lesson was", "the lesson is",
        "what mattered was", "what mattered is",
    ],
}


def check_creative_compliance(text: str) -> list[tuple[str, str]]:
    """Check story text for Creative mode violations.

    Returns list of (category, phrase) tuples for each violation found.
    Empty list means compliant.
    """
    violations = []
    lower = text.lower()
    for category, phrases in CREATIVE_VIOLATIONS.items():
        for phrase in phrases:
            if phrase in lower:
                violations.append((category, phrase))
    return violations


# ── Dart StoryModeValidator regex patterns (ported) ───────────────────────
# These supplement the phrase-based checks above with regex patterns from
# lib/safety/story_mode_validator.dart.

# Traditional: MoDC companionship patterns (forbidden)
_MODC_COMPANIONSHIP_PATTERNS = [
    r"\bI sit with you\b",
    r"\bI am here with you\b",
    r"\bI am beside you\b",
    r"\blet me walk with you\b",
    r"\bwe journey together\b",
    r"\byou are not alone.*I\b",
    r"\bI hold space\b",
    r"\bI'm here for you\b",
]

# Traditional: spiritual guide posture (forbidden)
_SPIRITUAL_GUIDE_PATTERNS = [
    r"^Dear (friend|listener|child)",
    r"\blet me (tell|share|guide) you\b",
    r"\byou see,\b",
    r"\bremember, dear one\b",
    r"\bI want you to\b",
    r"\bI invite you to\b",
]

# Creative: Bible retelling signals (forbidden)
_BIBLE_RETELLING_SIGNALS = [
    r"\b(Noah|Noach).*ark\b",
    r"\b(Moses|Moshe).*Red Sea\b",
    r"\b(Moses|Moshe).*burning bush\b",
    r"\b(David).*Goliath\b",
    r"\b(Daniel).*lion('s)? den\b",
    r"\b(Jonah).*whale\b",
    r"\b(Jonah).*fish\b",
    r"\b(Jonah).*Nineveh\b",
    r"\b(Abraham|Abram).*Isaac.*sacrifice\b",
    r"\b(Joseph).*coat of many colors\b",
    r"\b(Samson).*Delilah\b",
    r"\b(Elijah).*prophets of Baal\b",
    r"\bthe (Bible|scripture) (tells|records|says) (of|that|how)\b",
    r"\bin the (book of|gospel of)\b",
]

# Creative + KJV: scripture-claim markers (forbidden)
_SCRIPTURE_CLAIM_MARKERS_KJV = [
    r"\bthus saith\b",
    r"\bverily\b.*\bsaith\b",
    r"\bchapter\s+\d+\b",
    r"\bverse\s+\d+\b",
    r"\b\d+:\d+\b",
    r"\bthis is the Word\b",
    r"\bhear the Word\b",
    r"\bthe Word of (the Lord|God)\b",
    r"\bsaith the Lord\b",
    r"\bspake unto\b",
]


def check_traditional_regex(text: str) -> list[tuple[str, str]]:
    """Check Traditional story against regex patterns from Dart validator.

    Returns list of (category, pattern) tuples for violations found.
    """
    violations = []
    for pattern in _MODC_COMPANIONSHIP_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            violations.append(("MODC_COMPANIONSHIP", pattern))
            break  # One per category
    for pattern in _SPIRITUAL_GUIDE_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
            violations.append(("SPIRITUAL_GUIDE", pattern))
            break
    return violations


def check_creative_regex(text: str, language_style: str = "WEB") -> list[tuple[str, str]]:
    """Check Creative story against regex patterns from Dart validator.

    Returns list of (category, pattern) tuples for violations found.
    """
    violations = []
    for pattern in _BIBLE_RETELLING_SIGNALS:
        if re.search(pattern, text, re.IGNORECASE):
            violations.append(("BIBLE_RETELLING_SIGNAL", pattern))
            break
    if language_style == "KJV":
        for pattern in _SCRIPTURE_CLAIM_MARKERS_KJV:
            if re.search(pattern, text, re.IGNORECASE):
                violations.append(("SCRIPTURE_CLAIM_KJV", pattern))
                break
    return violations


# ── Combined validation entry points ─────────────────────────────────────

def validate_traditional(text: str) -> list[tuple[str, str]]:
    """Full Traditional mode validation (phrases + regex). Returns all violations."""
    return check_traditional_compliance(text) + check_traditional_regex(text)


def validate_creative(text: str, language_style: str = "WEB") -> list[tuple[str, str]]:
    """Full Creative mode validation (phrases + regex). Returns all violations."""
    return check_creative_compliance(text) + check_creative_regex(text, language_style)


# ── Lane identity validators (WARN-only during calibration) ──────────────
# Added 2026-05-26 for Phase 5 of lane differentiation initiative.
# Currently advisory only — violations logged but never block generation.
# Promotion to BLOCKING is a separate deferred decision; see plan.

KJV_ARCHAIC_MARKERS = [
    # Archaic pronouns — no modern collision risk.
    r"\bthou\b", r"\bthee\b", r"\bthy\b", r"\bthine\b", r"\bye\b",
    # Archaic verb forms — explicitly enumerated to avoid the false positives
    # produced by a blanket \w+eth / \w+est suffix match (which hits "breath",
    # "death", "teeth", "chest", "nearest", "honest", "interest", etc.).
    r"\bhath\b", r"\bdoth\b", r"\bsaith\b", r"\bsayeth\b",
    r"\bspake\b", r"\bbrake\b",
    r"\bcometh\b", r"\bgoeth\b", r"\bmaketh\b", r"\bseeth\b",
    r"\bknoweth\b", r"\bwalketh\b", r"\bgiveth\b", r"\bliveth\b",
    r"\bleadeth\b", r"\briseth\b", r"\bstandeth\b",
    r"\bhast\b", r"\bwilt\b", r"\bshalt\b", r"\bdost\b",
    # Archaic adverbs / connectors — rare in modern English.
    # NOTE: "behold" intentionally excluded — the WEB translation uses it
    # frequently ("Behold, an angel..."), so it cannot be a Classic-only marker.
    r"\bunto\b", r"\bverily\b", r"\bhenceforth\b",
    r"\bwhence\b", r"\bwhither\b", r"\bwhatsoever\b",
    r"\btherein\b", r"\bthereof\b",
]

CONTRACTIONS = [
    r"\bdidn['’]t\b", r"\bwasn['’]t\b", r"\bwouldn['’]t\b",
    r"\bisn['’]t\b", r"\baren['’]t\b", r"\bcan['’]t\b",
    r"\bdon['’]t\b", r"\bwon['’]t\b", r"\bcouldn['’]t\b",
    r"\bshouldn['’]t\b", r"\bhaven['’]t\b", r"\bhadn['’]t\b",
    r"\bit['’]s\b", r"\bthat['’]s\b", r"\bhe['’]s\b",
    r"\bshe['’]s\b", r"\bthey['’]re\b",
    r"\bI['’]m\b", r"\bwe['’]re\b", r"\byou['’]re\b",
]

KJV_MIN_ARCHAIC_MARKERS = 3  # KJV-lane story must contain at least this many archaic markers


def validate_lane_identity(text: str, lane: str) -> list[tuple[str, str]]:
    """Lane identity validator (WARN-only during calibration period).

    Returns a list of (category, marker_or_pattern) tuples for each violation.
    Empty list means the text is lane-compliant.

    Categories:
        KJV lane:
        - KJV_TOO_FEW_ARCHAIC_MARKERS: fewer than KJV_MIN_ARCHAIC_MARKERS markers
        - KJV_CONTRACTION: contractions banned in Classic register

        WEB lane:
        - WEB_ARCHAIC_BLEED: any KJV archaic marker present
        - WEB_CONTRACTION: contractions banned in Modern register (still reverent)

    Intentionally does NOT consider whether the text reproduces Scripture verbatim —
    that's enforced by _KJV_AUDIO_RULES at prompt-time.
    """
    violations: list[tuple[str, str]] = []
    archaic_hits = [
        pat for pat in KJV_ARCHAIC_MARKERS
        if re.search(pat, text, re.IGNORECASE)
    ]
    contraction_hits = [
        pat for pat in CONTRACTIONS
        if re.search(pat, text, re.IGNORECASE)
    ]

    if lane == "kjv":
        if len(archaic_hits) < KJV_MIN_ARCHAIC_MARKERS:
            violations.append((
                "KJV_TOO_FEW_ARCHAIC_MARKERS",
                f"found {len(archaic_hits)}, need >= {KJV_MIN_ARCHAIC_MARKERS}",
            ))
        for pat in contraction_hits:
            violations.append(("KJV_CONTRACTION", pat))
    elif lane == "web":
        for pat in archaic_hits:
            violations.append(("WEB_ARCHAIC_BLEED", pat))
        for pat in contraction_hits:
            violations.append(("WEB_CONTRACTION", pat))

    return violations


def log_lane_warnings(
    repo_root: pathlib.Path,
    story_id: int,
    lane: str,
    length: str,
    text: str,
) -> int:
    """Run validate_lane_identity() and log violations as WARN-only.

    Writes a JSONL line to assets/diagnostics/lane_validator_log.jsonl and
    prints `LANE-WARN [{lane}] ...` lines to stdout. Does NOT block generation.

    Returns the number of violations (0 = clean). Callers should not gate on
    this value during the calibration period.
    """
    violations = validate_lane_identity(text, lane)
    if not violations:
        return 0
    for cat, marker in violations:
        print(f"  LANE-WARN [{lane}] [{cat}] {marker}")
    log_dir = repo_root / "assets" / "diagnostics"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "lane_validator_log.jsonl"
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "story_id": story_id,
        "lane": lane,
        "length": length,
        "violations": [{"category": c, "marker": m} for c, m in violations],
    }
    with log_file.open("a") as fh:
        fh.write(json.dumps(entry) + "\n")
    return len(violations)


# ── Reflection validation ─────────────────────────────────────────────────

REFLECTION_BANNED_PHRASES = [
    "you should", "you must", "you need to", "try to",
    "you are feeling", "this will help you", "this will make you",
    "healing journey", "healing process", "inner healing",
    "coping", "therapy", "therapist", "counselor",
]


def check_reflection_banned(text: str) -> str | None:
    """Check reflection for banned phrases. Returns first hit or None."""
    lower = text.lower()
    for phrase in REFLECTION_BANNED_PHRASES:
        if phrase in lower:
            return phrase
    return None


# ── Kid forbidden word checking ───────────────────────────────────────────

def load_forbidden_words(root: pathlib.Path) -> list[str]:
    """Load forbidden words from server/kid_bedtime_forbidden.txt."""
    forbidden_file = root / "server" / "kid_bedtime_forbidden.txt"
    if not forbidden_file.exists():
        raise FileNotFoundError(f"Forbidden words file not found: {forbidden_file}")
    words = []
    for line in forbidden_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        words.append(line.lower())
    return words


# ── Kid-safe word replacements (deterministic post-processing) ────────
# Maps forbidden words to gentle alternatives for kid mode.
# Applied as whole-word replacements (case-preserving) before the
# forbidden-word gate. This is orchestration, not authoring.
KID_WORD_REPLACEMENTS = {
    "shadows": "shade",
    "shadowy": "dim",
    "shadow": "shade",
    "darkness": "nighttime",
    "creatures": "animals",
    "creature": "animal",
    "chased": "followed",
    "chase": "follow",
    "chasing": "following",
    "kingdom": "village",
    "king": "leader",
    "throne": "chair",
    "crown": "hat",
    "devoured": "ate happily",
    "devour": "enjoy",
    "abandoned": "left waiting",
    "stalk": "walk quietly",
    "stalked": "walked quietly",
    "fierce": "strong",
    "wicked": "unkind",
    "prey": "friend",
    "lurk": "wait",
    "lurking": "waiting",
    "prowl": "wander",
    "prowled": "wandered",
    "monster": "big helper",
    "beast": "animal",
    "sword": "tool",
    "battle": "challenge",
    "enemy": "stranger",
    "alone": "by themselves",
    "lonely": "quiet",
    "lost": "looking around",
    "escaped": "hurried away",
    "flee": "hurry away",
    "fled": "hurried away",
    "soldiers": "helpers",
    "lifeless": "still",
    "teeth": "smile",
    "jaws": "mouth",
    "claws": "paws",
    "hunt": "search",
    "danger": "surprise",
    "dangerous": "surprising",
    "terror": "worry",
    "death": "sleep",
    "dead": "still",
    "afraid": "nervous",
    "frightened": "surprised",
    "scared": "unsure",
    "scary": "tricky",
    "fear": "worry",
    "kings": "leaders",
    "ruler": "leader",
    "rulers": "leaders",
    "palace": "great house",
    "palaces": "great houses",
    "decree": "announcement",
    "commanded": "asked",
}


def apply_kid_word_replacements(text: str) -> str:
    """Apply deterministic kid-safe word replacements (case-preserving).

    Also fixes article mismatches (e.g., 'A announcement' -> 'An announcement')
    caused by replacements changing the initial letter/sound.
    """
    for bad, good in KID_WORD_REPLACEMENTS.items():
        def _replace(m: re.Match) -> str:
            orig = m.group(0)
            if orig.isupper():
                return good.upper()
            if orig[0].isupper():
                return good[0].upper() + good[1:]
            return good
        text = re.sub(r"\b" + re.escape(bad) + r"\b", _replace, text, flags=re.IGNORECASE)

    # Fix article mismatches after replacements
    # "a" before vowel sound -> "an", "an" before consonant sound -> "a"
    vowels = "aeiouAEIOU"
    text = re.sub(
        r"\b(A|a)\s+([A-Za-z])",
        lambda m: (
            (m.group(1)[0] + "n " if m.group(2) in vowels else m.group(1) + " ")
            + m.group(2)
        ),
        text,
    )
    text = re.sub(
        r"\b(An|an)\s+([A-Za-z])",
        lambda m: (
            (m.group(1) + " " if m.group(2) in vowels else m.group(1)[0] + " ")
            + m.group(2)
        ),
        text,
    )
    return text


def check_forbidden_words(text: str, forbidden: list[str]) -> list[str]:
    """Check text for forbidden kid-safety words.

    Multi-word phrases use substring matching.
    Single words use word-boundary matching to avoid false positives.
    """
    found = []
    lower = text.lower()
    for word in forbidden:
        if " " in word:
            if word in lower:
                found.append(word)
        else:
            if re.search(r"\b" + re.escape(word) + r"\b", lower):
                found.append(word)
    return found
