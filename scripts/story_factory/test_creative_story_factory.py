#!/usr/bin/env python3
"""Tests for creative story factory helpers — no API/Ollama calls required."""

import unittest

# Import from the creative generator module
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from generate_creative_story import (
    LOCKED_RANGES,
    KID_LOCKED_RANGES,
    KID_REFLECTION_WORD_RANGE,
    REFLECTION_WORD_RANGE,
    REFLECTION_BANNED_PHRASES,
    META_TEXT_BLOCKLIST,
    MODEL,
    OLLAMA_URL,
    TEMPERATURE,
    NUM_PREDICT,
    MAX_REGEN,
    CREATIVE_VIOLATIONS,
    SYSTEM_PROMPTS_STORY,
    KID_SYSTEM_PROMPTS_STORY,
    check_meta_text,
    check_creative_compliance,
    check_forbidden_words,
    load_forbidden_words,
)


class TestEngineAssignment(unittest.TestCase):
    """Verify creative engine is locked to Gemma 7B via Ollama."""

    def test_model_is_gemma(self):
        self.assertEqual(MODEL, "gemma:7b",
                         "Creative engine MUST be gemma:7b")

    def test_ollama_url_is_local(self):
        self.assertIn("localhost", OLLAMA_URL,
                       "Creative engine MUST use local Ollama")
        self.assertNotIn("openai", OLLAMA_URL.lower(),
                         "Creative engine MUST NOT use OpenAI")

    def test_temperature_is_creative(self):
        # Creative should have higher temperature than traditional (0.7 vs typical 0.4-0.5)
        self.assertGreaterEqual(TEMPERATURE, 0.6,
                                "Creative temperature should be >= 0.6 for variety")
        self.assertLessEqual(TEMPERATURE, 1.0,
                             "Creative temperature should be <= 1.0 for coherence")

    def test_no_openai_import(self):
        """Verify generate_creative_story.py does not import or reference OpenAI."""
        script_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        content = script_path.read_text().lower()
        self.assertNotIn("openai_api_key", content,
                         "Creative generator MUST NOT reference OPENAI_API_KEY")
        self.assertNotIn("api.openai.com", content,
                         "Creative generator MUST NOT call OpenAI API")
        self.assertNotIn("gpt-4", content,
                         "Creative generator MUST NOT reference GPT-4")


class TestLockedRanges(unittest.TestCase):
    """Verify locked word-count ranges match spec (shorter than traditional)."""

    def test_short_range(self):
        self.assertEqual(LOCKED_RANGES["short"], (200, 400))

    def test_full_range(self):
        self.assertEqual(LOCKED_RANGES["full"], (401, 700))

    def test_long_range(self):
        self.assertEqual(LOCKED_RANGES["long"], (701, 1100))

    def test_exactly_three_buckets(self):
        self.assertEqual(set(LOCKED_RANGES.keys()), {"short", "full", "long"})


class TestKidLockedRanges(unittest.TestCase):
    """Verify kid mode word count ranges match contract."""

    def test_short_range(self):
        self.assertEqual(KID_LOCKED_RANGES["short"], (200, 500))

    def test_full_range(self):
        self.assertEqual(KID_LOCKED_RANGES["full"], (501, 900))

    def test_long_range(self):
        self.assertEqual(KID_LOCKED_RANGES["long"], (901, 1400))

    def test_exactly_three_buckets(self):
        self.assertEqual(set(KID_LOCKED_RANGES.keys()), {"short", "full", "long"})

    def test_kid_reflection_range(self):
        self.assertEqual(KID_REFLECTION_WORD_RANGE, (60, 120))


class TestTokenBudgets(unittest.TestCase):
    """Verify token budgets are sufficient for each length bucket."""

    def test_short_budget(self):
        lo, hi = LOCKED_RANGES["short"]
        # ~1.5 tokens per word + margin
        self.assertGreater(NUM_PREDICT["short"], hi * 1.3)

    def test_full_budget(self):
        lo, hi = LOCKED_RANGES["full"]
        self.assertGreater(NUM_PREDICT["full"], hi * 1.3)

    def test_long_budget(self):
        lo, hi = LOCKED_RANGES["long"]
        self.assertGreater(NUM_PREDICT["long"], hi * 1.3)

    def test_all_buckets_have_budgets(self):
        self.assertEqual(set(NUM_PREDICT.keys()), set(LOCKED_RANGES.keys()))


class TestCreativeCompliance(unittest.TestCase):
    """Verify creative compliance validator catches violations."""

    # Fixture: text that violates Creative mode rules
    FAILING_FIXTURE = (
        "And Jesus said to the crowd, 'Come follow me.' "
        "As the Bible says, faith can move mountains. "
        "God said, 'I will be with you always.' "
        "You should pray every day. "
        "If you don't repent, you will be punished."
    )

    # Fixture: clean Creative text
    PASSING_FIXTURE = (
        "The old baker rose before dawn, as he did every morning, "
        "to light the ovens and begin his work. His hands moved "
        "with the patience of years, kneading dough that would "
        "become bread for the village. He did not rush. He did "
        "not worry. There was something sacred in the rhythm of "
        "giving what one had."
    )

    def test_violations_dict_has_all_categories(self):
        expected = {"SCRIPTURE_RETELLING", "SCRIPTURE_AUTHORITY",
                    "DIRECT_GOD_DIALOGUE", "SPIRITUAL_COMMANDS",
                    "FEAR_FRAMING"}
        self.assertEqual(set(CREATIVE_VIOLATIONS.keys()), expected)

    def test_each_category_not_empty(self):
        for cat, phrases in CREATIVE_VIOLATIONS.items():
            self.assertGreater(len(phrases), 0,
                               f"Category {cat!r} has no phrases")

    def test_clean_text_passes(self):
        violations = check_creative_compliance(self.PASSING_FIXTURE)
        self.assertEqual(violations, [])

    def test_scripture_retelling_detected(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("SCRIPTURE_RETELLING", cats)

    def test_scripture_authority_detected(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("SCRIPTURE_AUTHORITY", cats)

    def test_direct_god_dialogue_detected(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("DIRECT_GOD_DIALOGUE", cats)

    def test_spiritual_commands_detected(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("SPIRITUAL_COMMANDS", cats)

    def test_fear_framing_detected(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("FEAR_FRAMING", cats)

    def test_contaminated_fixture_hits_all_categories(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        hit_cats = {cat for cat, _ in violations}
        self.assertEqual(hit_cats, set(CREATIVE_VIOLATIONS.keys()),
                         f"Expected all categories, got {hit_cats}")

    def test_specific_phrases_caught(self):
        violations = check_creative_compliance(self.FAILING_FIXTURE)
        phrases = [phrase for _, phrase in violations]
        self.assertIn("and jesus said", phrases)
        self.assertIn("as the bible says", phrases)
        self.assertIn("god said,", phrases)
        self.assertIn("you should", phrases)


class TestCreativeVsTraditionalSeparation(unittest.TestCase):
    """Verify creative and traditional validators don't overlap improperly."""

    def test_creative_prompts_forbid_bible_characters(self):
        """All creative system prompts must instruct against Bible character names."""
        for lane, prompt in SYSTEM_PROMPTS_STORY.items():
            self.assertIn("Do NOT retell", prompt,
                          f"Creative {lane} prompt must forbid Bible retellings")
            self.assertIn("ORIGINAL", prompt.upper(),
                          f"Creative {lane} prompt must emphasize original stories")

    def test_creative_prompts_no_traditional_rules(self):
        """Creative prompts must NOT contain Traditional-specific rules."""
        for lane, prompt in SYSTEM_PROMPTS_STORY.items():
            self.assertNotIn("TRADITIONAL HARD RULES", prompt,
                             f"Creative {lane} prompt must not include Traditional rules")
            self.assertNotIn("scripture-accurate", prompt.lower(),
                             f"Creative {lane} prompt must not require scripture accuracy")

    def test_creative_prompts_have_anti_repetition(self):
        """Creative prompts must include anti-repetition rules."""
        for lane, prompt in SYSTEM_PROMPTS_STORY.items():
            self.assertIn("ANTI-REPETITION RULES", prompt)

    def test_kid_creative_prompts_have_safety_rules(self):
        """Kid creative prompts must include kid safety rules."""
        for lane, prompt in KID_SYSTEM_PROMPTS_STORY.items():
            self.assertIn("KID STORY RULES", prompt)
            self.assertIn("CREATIVE MODE HARD RULES", prompt)
            self.assertIn("ANTI-REPETITION RULES", prompt)


class TestMetaTextValidation(unittest.TestCase):
    """Verify meta-text detection (shared with traditional)."""

    def test_blocklist_not_empty(self):
        self.assertGreater(len(META_TEXT_BLOCKLIST), 0)

    def test_clean_text_passes(self):
        clean = "The old baker rose before dawn, his hands steady and sure."
        self.assertIsNone(check_meta_text(clean))

    def test_certainly_detected(self):
        bad = "Certainly! Here is a story about kindness..."
        self.assertIsNotNone(check_meta_text(bad))

    def test_here_is_detected(self):
        bad = "Here is an original story about a baker."
        self.assertIsNotNone(check_meta_text(bad))

    def test_empty_text_detected(self):
        self.assertIsNotNone(check_meta_text(""))
        self.assertIsNotNone(check_meta_text("   "))

    def test_separator_line_detected(self):
        bad = "---\nThe morning sun rose..."
        self.assertIsNotNone(check_meta_text(bad))

    def test_meta_text_only_in_opening(self):
        clean = ("A " * 120) + "here is a moment of peace."
        self.assertIsNone(check_meta_text(clean))


class TestReflectionConstraints(unittest.TestCase):
    """Verify reflection constraints match INVARIANTS.md."""

    def test_adult_range(self):
        self.assertEqual(REFLECTION_WORD_RANGE, (120, 220))

    def test_kid_range(self):
        self.assertEqual(KID_REFLECTION_WORD_RANGE, (60, 120))

    def test_banned_list_not_empty(self):
        self.assertGreater(len(REFLECTION_BANNED_PHRASES), 0)

    def test_prescriptive_phrases_banned(self):
        for phrase in ["you should", "you must", "you need to", "try to"]:
            self.assertIn(phrase, REFLECTION_BANNED_PHRASES,
                          f"{phrase!r} should be banned")

    def test_diagnostic_phrases_banned(self):
        self.assertIn("you are feeling", REFLECTION_BANNED_PHRASES)

    def test_therapeutic_phrases_banned(self):
        for phrase in ["therapy", "therapist", "counselor"]:
            self.assertIn(phrase, REFLECTION_BANNED_PHRASES)


class TestForbiddenWords(unittest.TestCase):
    """Verify forbidden word loading and detection (shared with traditional)."""

    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).parent.parent.parent
        cls.forbidden = load_forbidden_words(root)

    def test_loads_nonempty_list(self):
        self.assertGreater(len(self.forbidden), 200,
                           f"Expected 200+ forbidden words, got {len(self.forbidden)}")

    def test_clean_text_passes(self):
        clean = "The gentle breeze blew through the trees and the birds sang softly."
        found = check_forbidden_words(clean, self.forbidden)
        self.assertEqual(found, [])

    def test_violence_word_detected(self):
        bad = "The warriors attacked the village."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertGreater(len(found), 0)

    def test_word_boundary_prevents_false_positive(self):
        clean = "She was making bread and baking cookies."
        found = check_forbidden_words(clean, self.forbidden)
        self.assertEqual(found, [])


class TestCreativeMetadataContract(unittest.TestCase):
    """Verify creative metadata does NOT include traditional-specific fields."""

    def test_no_scripture_anchor_in_generator(self):
        """Creative generator must not write scriptureAnchor to metadata."""
        script_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        content = script_path.read_text()
        # Look for scriptureAnchor in the meta dict construction
        # It should NOT be present (Creative mode forbids bibleSourceRef)
        lines_with_anchor = [
            line for line in content.split("\n")
            if "scriptureAnchor" in line and "meta" in line.lower()
        ]
        # Only allowed in comments, not in actual meta dict
        for line in lines_with_anchor:
            self.assertTrue(line.strip().startswith("#") or line.strip().startswith("//"),
                            f"scriptureAnchor should not be in meta dict: {line.strip()}")

    def test_mode_is_creative(self):
        """Creative generator must set mode to 'creative' in metadata."""
        script_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        content = script_path.read_text()
        self.assertIn('"mode": "creative"', content,
                      "Creative generator must set mode='creative' in metadata")

    def test_model_is_gemma_in_metadata(self):
        """Creative generator must record gemma:7b as createdByModel."""
        script_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        content = script_path.read_text()
        self.assertIn('"createdByModel": MODEL', content,
                      "Creative generator must record MODEL in metadata")


class TestBatchThemeSuggestions(unittest.TestCase):
    """Verify batch_generate_creative theme suggestions are valid."""

    def test_all_canonical_moods_have_themes(self):
        from batch_generate_creative import THEME_SUGGESTIONS, CANONICAL_MOODS
        for mood in CANONICAL_MOODS:
            self.assertIn(mood, THEME_SUGGESTIONS,
                          f"Mood {mood!r} missing from THEME_SUGGESTIONS")
            self.assertGreater(len(THEME_SUGGESTIONS[mood]), 0,
                               f"Mood {mood!r} has no theme suggestions")

    def test_sufficient_themes_per_mood(self):
        """Each mood should have at least 5 theme suggestions for scalability."""
        from batch_generate_creative import THEME_SUGGESTIONS
        for mood, themes in THEME_SUGGESTIONS.items():
            self.assertGreaterEqual(len(themes), 5,
                                    f"Mood {mood!r} needs more themes ({len(themes)} < 5)")

    def test_themes_are_nonempty_strings(self):
        from batch_generate_creative import THEME_SUGGESTIONS
        for mood, themes in THEME_SUGGESTIONS.items():
            for theme in themes:
                self.assertIsInstance(theme, str)
                self.assertGreater(len(theme.strip()), 10,
                                   f"Theme too short for {mood!r}: {theme!r}")

    def test_no_duplicate_themes_within_mood(self):
        from batch_generate_creative import THEME_SUGGESTIONS
        for mood, themes in THEME_SUGGESTIONS.items():
            self.assertEqual(len(themes), len(set(themes)),
                             f"Duplicate themes found for mood {mood!r}")

    def test_canonical_moods_match_traditional(self):
        """Creative and traditional pipelines must use the same canonical moods."""
        from batch_generate_creative import CANONICAL_MOODS as creative_moods
        from batch_generate import CANONICAL_MOODS as trad_moods
        self.assertEqual(creative_moods, trad_moods,
                         "Creative and Traditional must share canonical moods")


class TestBatchDryRun(unittest.TestCase):
    """Verify batch_generate_creative.py --dry-run works without side effects."""

    def test_dry_run_exits_zero(self):
        import subprocess
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate_creative.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0,
                         f"Dry run should exit 0, got {result.returncode}\n{result.stderr}")

    def test_dry_run_prints_all_moods(self):
        import subprocess
        from batch_generate_creative import CANONICAL_MOODS
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate_creative.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        for mood in CANONICAL_MOODS:
            self.assertIn(mood, result.stdout,
                          f"Dry run output should mention mood {mood!r}")

    def test_dry_run_mentions_gemma(self):
        import subprocess
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate_creative.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        self.assertIn("Gemma", result.stdout,
                      "Dry run should identify Gemma as the engine")

    def test_dry_run_does_not_mutate_theme_registry(self):
        import subprocess
        themes_file = pathlib.Path(__file__).parent.parent.parent / "used_creative_themes.json"
        before = themes_file.read_text() if themes_file.exists() else "NOT_EXISTS"
        subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate_creative.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        after = themes_file.read_text() if themes_file.exists() else "NOT_EXISTS"
        self.assertEqual(before, after,
                         "Dry run must NOT mutate used_creative_themes.json")


class TestDualEngineIsolation(unittest.TestCase):
    """Verify creative and traditional pipelines are properly isolated."""

    def test_creative_output_dir_is_separate(self):
        """Creative stories must go to assets/stories/creative/, not traditional/."""
        script_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        content = script_path.read_text()
        self.assertIn('"creative"', content)
        # Verify the outdir construction uses 'creative' not 'traditional'
        self.assertIn('/ "creative" /', content,
                      "Creative output must use 'creative' directory")

    def test_traditional_output_dir_is_separate(self):
        """Traditional stories must go to assets/stories/traditional/."""
        script_path = pathlib.Path(__file__).parent / "generate_traditional_story.py"
        content = script_path.read_text()
        self.assertIn('"traditional"', content)

    def test_registries_are_separate(self):
        """Creative and traditional must use different registries."""
        creative_path = pathlib.Path(__file__).parent / "generate_creative_story.py"
        trad_path = pathlib.Path(__file__).parent / "generate_traditional_story.py"
        creative_content = creative_path.read_text()
        trad_content = trad_path.read_text()

        # Creative uses theme registry
        self.assertIn("used_creative_themes.json", creative_content)
        # Traditional uses anchor registry
        self.assertIn("used_scripture_anchors.json", trad_content)
        # No cross-contamination
        self.assertNotIn("used_scripture_anchors.json", creative_content,
                         "Creative must not use traditional anchor registry")
        self.assertNotIn("used_creative_themes.json", trad_content,
                         "Traditional must not use creative theme registry")


class TestMaxRegenLimits(unittest.TestCase):
    """Verify regeneration limits are reasonable."""

    def test_max_regen_adult(self):
        self.assertGreaterEqual(MAX_REGEN, 3,
                                "Adult max regen should be >= 3")
        self.assertLessEqual(MAX_REGEN, 10,
                             "Adult max regen should be <= 10 to avoid infinite loops")

    def test_max_regen_kid(self):
        from generate_creative_story import KID_MAX_REGEN
        self.assertGreaterEqual(KID_MAX_REGEN, 3)
        self.assertLessEqual(KID_MAX_REGEN, 10)


if __name__ == "__main__":
    unittest.main()
