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


if __name__ == "__main__":
    unittest.main()
