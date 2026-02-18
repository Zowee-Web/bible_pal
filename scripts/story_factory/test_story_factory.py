#!/usr/bin/env python3
"""Tests for story factory helpers — no API calls required."""

import unittest

# Import from the generator module
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from generate_traditional_story import (
    TRANSIENT_CODES,
    LOCKED_RANGES,
    PROTESTANT_BOOKS,
    REFLECTION_WORD_RANGE,
    REFLECTION_BANNED_PHRASES,
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
