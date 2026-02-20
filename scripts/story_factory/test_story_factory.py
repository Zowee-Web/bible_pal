#!/usr/bin/env python3
"""Tests for story factory helpers — no API calls required."""

import unittest

# Import from the generator module
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from generate_traditional_story import (
    TRANSIENT_CODES,
    LOCKED_RANGES,
    KID_LOCKED_RANGES,
    KID_REFLECTION_WORD_RANGE,
    BEDTIME_CLOSING_SIGNALS,
    PROTESTANT_BOOKS,
    REFLECTION_WORD_RANGE,
    REFLECTION_BANNED_PHRASES,
    META_TEXT_BLOCKLIST,
    META_TEXT_MAX_REGEN,
    TRADITIONAL_VIOLATIONS,
    check_meta_text,
    check_traditional_compliance,
    check_forbidden_words,
    check_bedtime_closing,
    load_forbidden_words,
    validate_anchor_format,
)


class TestTransientClassification(unittest.TestCase):
    """Verify transient vs non-transient HTTP code classification."""

    def test_transient_codes(self):
        for code in (429, 502, 503):
            self.assertIn(code, TRANSIENT_CODES, f"{code} should be transient")

    def test_non_transient_codes(self):
        for code in (400, 401, 403, 404, 422):
            self.assertNotIn(code, TRANSIENT_CODES, f"{code} should NOT be transient")


class TestLockedRanges(unittest.TestCase):
    """Verify locked word-count ranges match spec Section 5."""

    def test_short_range(self):
        self.assertEqual(LOCKED_RANGES["short"], (300, 500))

    def test_full_range(self):
        self.assertEqual(LOCKED_RANGES["full"], (501, 900))

    def test_long_range(self):
        self.assertEqual(LOCKED_RANGES["long"], (901, 1500))

    def test_exactly_three_buckets(self):
        self.assertEqual(set(LOCKED_RANGES.keys()), {"short", "full", "long"})


class TestProtestantCanon(unittest.TestCase):
    """Verify the book allowlist has exactly 66 books."""

    def test_book_count(self):
        self.assertEqual(len(PROTESTANT_BOOKS), 66,
                         f"Expected 66 books, got {len(PROTESTANT_BOOKS)}")


class TestAnchorFormatValidation(unittest.TestCase):
    """Validate anchor format per spec Section 2.2."""

    def test_valid_book_chapter(self):
        self.assertIsNone(validate_anchor_format("Psalm 23"))

    def test_valid_book_chapter_verse(self):
        self.assertIsNone(validate_anchor_format("Romans 8:28"))

    def test_valid_book_chapter_verse_range(self):
        # en-dash (–) required
        self.assertIsNone(validate_anchor_format("Matthew 11:28\u201330"))

    def test_valid_numbered_book(self):
        self.assertIsNone(validate_anchor_format("1 Corinthians 13"))

    def test_valid_multiword_book(self):
        self.assertIsNone(validate_anchor_format("Song of Solomon 2:1"))

    def test_reject_abbreviated_book(self):
        err = validate_anchor_format("Ps 23")
        self.assertIsNotNone(err)
        self.assertIn("Unknown", err)

    def test_reject_abbreviated_matt(self):
        err = validate_anchor_format("Matt 5:1")
        self.assertIsNotNone(err)

    def test_reject_hyphen_in_range(self):
        err = validate_anchor_format("Matthew 11:28-30")
        self.assertIsNotNone(err, "Hyphen in verse range should be rejected (en-dash required)")

    def test_reject_no_chapter(self):
        err = validate_anchor_format("Psalm")
        self.assertIsNotNone(err)

    def test_reject_translation_suffix(self):
        # "Psalm 23 (KJV)" should fail — extra text after chapter
        err = validate_anchor_format("Psalm 23 (KJV)")
        self.assertIsNotNone(err)

    def test_reject_empty(self):
        err = validate_anchor_format("")
        self.assertIsNotNone(err)


class TestReflectionWordRange(unittest.TestCase):
    """Verify reflection word count range (STORY_FACTORY.md Section 6)."""

    def test_range_defined(self):
        self.assertEqual(REFLECTION_WORD_RANGE, (120, 220))

    def test_range_contiguous(self):
        lo, hi = REFLECTION_WORD_RANGE
        self.assertGreater(hi, lo)
        self.assertGreater(lo, 0)


class TestReflectionBannedPhrases(unittest.TestCase):
    """Verify reflection language safety (INVARIANTS.md)."""

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
            self.assertIn(phrase, REFLECTION_BANNED_PHRASES,
                          f"{phrase!r} should be banned")

    def test_detection_works(self):
        """Validate that banned phrase detection works on sample text."""
        safe_text = "Stories like this often show how rest can be found in unexpected places."
        unsafe_text = "You should take some time to rest today."
        for phrase in REFLECTION_BANNED_PHRASES:
            self.assertNotIn(phrase, safe_text.lower(),
                             f"Safe text should not contain {phrase!r}")
        found = any(p in unsafe_text.lower() for p in REFLECTION_BANNED_PHRASES)
        self.assertTrue(found, "Unsafe text should trigger at least one banned phrase")


class TestMetaTextValidation(unittest.TestCase):
    """Verify meta-text detection (ported from meta_text_validator.dart)."""

    def test_blocklist_not_empty(self):
        self.assertGreater(len(META_TEXT_BLOCKLIST), 0)

    def test_max_regen_is_three(self):
        self.assertEqual(META_TEXT_MAX_REGEN, 3)

    def test_clean_text_passes(self):
        clean = "The morning sun rose over the hills, casting gold light across the land."
        self.assertIsNone(check_meta_text(clean))

    def test_certainly_detected(self):
        bad = "Certainly! This is a full retelling of Psalm 100..."
        self.assertIsNotNone(check_meta_text(bad))
        self.assertEqual("certainly", check_meta_text(bad))

    def test_here_is_detected(self):
        bad = "Here is the story of Psalm 23 retold in modern English."
        self.assertIsNotNone(check_meta_text(bad))

    def test_sure_detected(self):
        bad = "Sure! Below is Psalm 46 retold..."
        self.assertIsNotNone(check_meta_text(bad))

    def test_separator_line_detected(self):
        bad = "---\nThe morning sun rose..."
        self.assertIsNotNone(check_meta_text(bad))

    def test_empty_text_detected(self):
        self.assertIsNotNone(check_meta_text(""))
        self.assertIsNotNone(check_meta_text("   "))

    def test_leading_whitespace_stripped(self):
        # Clean text with leading whitespace should still pass
        clean = "  \n  The morning sun rose over the hills."
        self.assertIsNone(check_meta_text(clean))

    def test_meta_text_only_in_opening(self):
        # "here is" appearing after 200 chars should NOT trigger
        clean = ("A " * 120) + "here is a gift from God."
        self.assertIsNone(check_meta_text(clean))

    def test_all_dart_blocklist_phrases_present(self):
        """Verify Python blocklist matches Dart MetaTextValidator.defaultBlocklist."""
        dart_phrases = [
            "here is", "here's", "this version", "certainly", "of course",
            "sure,", "sure!", "in this retelling", "expanded carefully",
            "staying true to", "the following", "this passage", "this story",
            "this verse", "this retelling", "this rendering", "this adaptation",
            "i've", "i have", "let me", "below is", "as requested", "as you asked",
            "happy to", "glad to", "i'd be", "i would be", "absolutely",
            "great question", "what a",
        ]
        for phrase in dart_phrases:
            self.assertIn(phrase, META_TEXT_BLOCKLIST,
                          f"Dart phrase {phrase!r} missing from Python META_TEXT_BLOCKLIST")


class TestTraditionalCompliance(unittest.TestCase):
    """Verify Traditional compliance validator catches violations."""

    # Fixture: excerpt from the contaminated Psalm 100 full story (known violations)
    FAILING_FIXTURE = (
        "Men and women gather, wide-eyed, from every land. Some come to the "
        "temple gates, bearing baskets of grain or oil, their steps quickened "
        "by the hope in their hearts. There is no shadow of burden or weight; "
        "all who come are wrapped in the warmth of joy. "
        "Every judgment is wise. His words are a balm. "
        "The song goes on, a golden thread passed from one voice to another. "
        "I was a child once, lifted up by his mercy. He formed my lungs, "
        "painted the features of my face."
    )

    # Fixture: clean Traditional text (no violations)
    PASSING_FIXTURE = (
        "The morning sun rose over the hills, casting gold light across the land. "
        "People from every village drew near to the house of the Lord, their "
        "voices rising. Men, women, and children walked along the dusty road, "
        "clapping hands and singing aloud, for the day was bright with gladness."
    )

    def test_violations_dict_has_all_categories(self):
        expected = {"INNER_THOUGHTS", "INTERPRETIVE_THEOLOGY",
                    "SYMBOLISM_METAPHOR", "FIRST_PERSON_TESTIMONY"}
        self.assertEqual(set(TRADITIONAL_VIOLATIONS.keys()), expected)

    def test_each_category_not_empty(self):
        for cat, phrases in TRADITIONAL_VIOLATIONS.items():
            self.assertGreater(len(phrases), 0,
                               f"Category {cat!r} has no phrases")

    def test_clean_text_passes(self):
        violations = check_traditional_compliance(self.PASSING_FIXTURE)
        self.assertEqual(violations, [])

    def test_inner_thoughts_detected(self):
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("INNER_THOUGHTS", cats)

    def test_interpretive_theology_detected(self):
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("INTERPRETIVE_THEOLOGY", cats)

    def test_symbolism_detected(self):
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("SYMBOLISM_METAPHOR", cats)

    def test_first_person_testimony_detected(self):
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        cats = [cat for cat, _ in violations]
        self.assertIn("FIRST_PERSON_TESTIMONY", cats)

    def test_specific_phrases_caught(self):
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        phrases = [phrase for _, phrase in violations]
        self.assertIn("in their hearts", phrases)
        self.assertIn("every judgment is wise", phrases)
        self.assertIn("golden thread", phrases)
        self.assertIn("i was a child once", phrases)

    def test_reflection_fixture_passes(self):
        """Verify the Psalm 100 reflection passes Traditional check too."""
        reflection = (
            "Psalm 100 brings a portrait of collective praise and joyful "
            "thanksgiving. It speaks with imagery of people entering gates "
            "with gratitude, voices raised in song."
        )
        violations = check_traditional_compliance(reflection)
        self.assertEqual(violations, [])

    def test_contaminated_fixture_hits_all_four_categories(self):
        """Validator hit-rate: contaminated fixture must hit all 4 categories."""
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        hit_cats = {cat for cat, _ in violations}
        self.assertEqual(hit_cats, set(TRADITIONAL_VIOLATIONS.keys()),
                         f"Expected all 4 categories, got {hit_cats}")

    def test_contaminated_fixture_minimum_hit_count(self):
        """Contaminated fixture should trigger at least 6 violations."""
        violations = check_traditional_compliance(self.FAILING_FIXTURE)
        self.assertGreaterEqual(len(violations), 6,
                                f"Expected ≥6 hits, got {len(violations)}: {violations}")

    def test_sanitized_fixture_passes(self):
        """Simulate a post-sanitize output: same passage but compliant."""
        sanitized = (
            "Men and women gather from every land. Some come to the "
            "temple gates, bearing baskets of grain or oil, their steps "
            "quickened on the dusty road. All who come are wrapped in "
            "the bright morning light. "
            "The people lift their voices together, clapping and singing. "
            "An elder speaks aloud the words: "
            "'Yahweh is good. His loving kindness endures forever.' "
            "Children spin in circles near the courtyard stones."
        )
        violations = check_traditional_compliance(sanitized)
        self.assertEqual(violations, [],
                         f"Sanitized fixture should pass, but got: {violations}")


class TestBatchAnchorSuggestions(unittest.TestCase):
    """Verify batch_generate anchor suggestions are valid."""

    def test_all_canonical_moods_have_anchors(self):
        from batch_generate import ANCHOR_SUGGESTIONS, CANONICAL_MOODS
        for mood in CANONICAL_MOODS:
            self.assertIn(mood, ANCHOR_SUGGESTIONS,
                          f"Mood {mood!r} missing from ANCHOR_SUGGESTIONS")
            self.assertGreater(len(ANCHOR_SUGGESTIONS[mood]), 0,
                               f"Mood {mood!r} has no anchor suggestions")

    def test_anchor_suggestions_are_valid_format(self):
        from batch_generate import ANCHOR_SUGGESTIONS
        for mood, anchors in ANCHOR_SUGGESTIONS.items():
            for anchor in anchors:
                err = validate_anchor_format(anchor)
                self.assertIsNone(err,
                    f"Anchor {anchor!r} for mood {mood!r} is invalid: {err}")

    def test_no_duplicate_anchors_across_moods(self):
        from batch_generate import ANCHOR_SUGGESTIONS
        all_anchors = []
        for anchors in ANCHOR_SUGGESTIONS.values():
            all_anchors.extend(anchors)
        self.assertEqual(len(all_anchors), len(set(all_anchors)),
                         "Duplicate anchors found across mood suggestions")


class TestKidLockedRanges(unittest.TestCase):
    """Verify kid mode word count ranges match contract."""

    def test_short_range(self):
        self.assertEqual(KID_LOCKED_RANGES["short"], (250, 600))

    def test_full_range(self):
        self.assertEqual(KID_LOCKED_RANGES["full"], (601, 1200))

    def test_long_range(self):
        self.assertEqual(KID_LOCKED_RANGES["long"], (1201, 1800))

    def test_exactly_three_buckets(self):
        self.assertEqual(set(KID_LOCKED_RANGES.keys()), {"short", "full", "long"})

    def test_kid_reflection_range(self):
        self.assertEqual(KID_REFLECTION_WORD_RANGE, (60, 120))


class TestForbiddenWords(unittest.TestCase):
    """Verify forbidden word loading and detection."""

    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).parent.parent.parent
        cls.forbidden = load_forbidden_words(root)

    def test_loads_nonempty_list(self):
        self.assertGreater(len(self.forbidden), 200,
                           f"Expected 200+ forbidden words, got {len(self.forbidden)}")

    def test_no_comment_lines_loaded(self):
        for word in self.forbidden:
            self.assertFalse(word.startswith("#"),
                             f"Comment line loaded as forbidden word: {word!r}")

    def test_no_empty_entries(self):
        for word in self.forbidden:
            self.assertTrue(word.strip(), "Empty forbidden word entry found")

    def test_clean_text_passes(self):
        clean = "The gentle breeze blew through the trees and the birds sang softly."
        found = check_forbidden_words(clean, self.forbidden)
        self.assertEqual(found, [])

    def test_violence_word_detected(self):
        bad = "The warriors attacked the village with their swords."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertGreater(len(found), 0)
        # Should catch multiple: warrior(s), attack(ed), sword(s)
        self.assertTrue(any("warrior" in w for w in found) or
                        any("attack" in w for w in found))

    def test_death_word_detected(self):
        bad = "The old man died peacefully in his bed."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertIn("died", found)

    def test_fear_word_detected(self):
        bad = "The children were terrified of the darkness."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertGreater(len(found), 0)

    def test_word_boundary_prevents_false_positive(self):
        """'king' should NOT match 'making' or 'baking'."""
        clean = "She was making bread and baking cookies."
        found = check_forbidden_words(clean, self.forbidden)
        self.assertEqual(found, [],
                         f"False positive: {found}")

    def test_king_detected_standalone(self):
        bad = "The king sat on the throne."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertIn("king", found)
        self.assertIn("throne", found)

    def test_multiword_phrase_detected(self):
        bad = "And so David became king of Israel."
        found = check_forbidden_words(bad, self.forbidden)
        self.assertIn("became king", found)


class TestBedtimeClosing(unittest.TestCase):
    """Verify bedtime closing signal detection."""

    def test_closing_signals_not_empty(self):
        self.assertGreater(len(BEDTIME_CLOSING_SIGNALS), 10)

    def test_detects_sleep_closing(self):
        story = ("Once upon a time a kind shepherd watched over his sheep. " * 20 +
                 "And as the stars twinkled softly overhead, the little lamb "
                 "closed her eyes and drifted to sleep.")
        self.assertTrue(check_bedtime_closing(story))

    def test_detects_resting_closing(self):
        story = ("A gentle morning came over the hillside. " * 20 +
                 "Wrapped in the cozy blanket of night, everyone was resting.")
        self.assertTrue(check_bedtime_closing(story))

    def test_rejects_missing_closing(self):
        story = ("The people gathered and praised God together. " * 20 +
                 "The morning sun continued to shine over the hills.")
        self.assertFalse(check_bedtime_closing(story))

    def test_signal_must_be_in_last_20_percent(self):
        """Sleep words early in the story don't count."""
        story = ("The child fell asleep early. " +
                 "The morning brought new adventures to the hillside. " * 30)
        self.assertFalse(check_bedtime_closing(story))

    def test_empty_text(self):
        self.assertFalse(check_bedtime_closing(""))


class TestBatchDryRun(unittest.TestCase):
    """Verify batch_generate.py --dry-run produces a stable plan without side effects."""

    def test_dry_run_exits_zero(self):
        import subprocess
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0,
                         f"Dry run should exit 0, got {result.returncode}\n{result.stderr}")

    def test_dry_run_prints_all_moods(self):
        import subprocess
        from batch_generate import CANONICAL_MOODS
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        for mood in CANONICAL_MOODS:
            self.assertIn(mood, result.stdout,
                          f"Dry run output should mention mood {mood!r}")

    def test_dry_run_assigns_story_ids(self):
        import subprocess
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        # Should contain bracketed story IDs like [905]
        import re
        ids = re.findall(r"\[(\d+)\]", result.stdout)
        self.assertGreater(len(ids), 0, "Dry run should print story IDs")
        # All IDs should be unique
        self.assertEqual(len(ids), len(set(ids)), "Story IDs should be unique")

    def test_dry_run_does_not_mutate_anchor_registry(self):
        import subprocess
        anchors_file = pathlib.Path(__file__).parent.parent.parent / "used_scripture_anchors.json"
        before = anchors_file.read_text() if anchors_file.exists() else "[]"
        subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).parent / "batch_generate.py"),
             "--lane", "web", "--voice_key", "VOICE_JAMES_HUSKY", "--dry-run"],
            capture_output=True, text=True,
        )
        after = anchors_file.read_text() if anchors_file.exists() else "[]"
        self.assertEqual(before, after,
                         "Dry run must NOT mutate used_scripture_anchors.json")


if __name__ == "__main__":
    unittest.main()
