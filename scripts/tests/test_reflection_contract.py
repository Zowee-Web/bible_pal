#!/usr/bin/env python3
"""Contract tests for the Option B reflection length policy.

Boundaries, authorization, and the two pieces of corpus evidence that motivated
the change: the owner exemplars must pass the standard band, and the current
proving-packet reflections must not.  Neither of those stories is read from a
mutable location and none is modified.
"""

from __future__ import annotations

import pathlib
import sys
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "story_factory"))

import reflection_contract as contract  # noqa: E402


class StandardBoundaries(unittest.TestCase):
    def test_24_words_fails(self):
        with self.assertRaises(contract.ReflectionContractError):
            contract.validate_reflection_word_count(24)

    def test_boundary_values_pass(self):
        for words in (25, 35, 60, 80):
            self.assertEqual(
                contract.validate_reflection_word_count(words), (25, 80),
                f"{words} words should pass the standard band",
            )

    def test_81_words_fails(self):
        with self.assertRaises(contract.ReflectionContractError):
            contract.validate_reflection_word_count(81)


class ExceptionBoundaries(unittest.TestCase):
    def test_exception_forms_span_25_to_120(self):
        for form in sorted(contract.EXCEPTION_FORMS):
            for words in (25, 80, 81, 120):
                self.assertEqual(
                    contract.validate_reflection_word_count(words, form), (25, 120),
                    f"{words} words should pass {form}",
                )
            with self.assertRaises(contract.ReflectionContractError):
                contract.validate_reflection_word_count(121, form)
            with self.assertRaises(contract.ReflectionContractError):
                contract.validate_reflection_word_count(24, form)

    def test_exception_target_is_60_to_100(self):
        for form in sorted(contract.EXCEPTION_FORMS):
            self.assertEqual(contract.target_reflection_range(form), (60, 100))


class Authorization(unittest.TestCase):
    def test_absent_forms_normalize_to_standard(self):
        for value in (None, "", "   "):
            self.assertEqual(contract.normalize_reflection_form(value), contract.STANDARD_FORM)

    def test_standard_assignment_rejects_exception_metadata(self):
        for declared in sorted(contract.EXCEPTION_FORMS):
            with self.assertRaises(contract.ReflectionContractError):
                contract.assert_assignment_matches_metadata(contract.STANDARD_FORM, declared)

    def test_exception_assignment_accepts_matching_metadata(self):
        for form in sorted(contract.EXCEPTION_FORMS):
            self.assertEqual(contract.assert_assignment_matches_metadata(form, form), form)

    def test_exception_assignment_rejects_a_different_exception(self):
        with self.assertRaises(contract.ReflectionContractError):
            contract.assert_assignment_matches_metadata("observation", "image_cascade")

    def test_exception_assignment_accepts_absent_metadata_only_when_standard(self):
        # Absent metadata normalizes to standard, so it may not silently satisfy
        # an exception assignment.
        with self.assertRaises(contract.ReflectionContractError):
            contract.assert_assignment_matches_metadata("observation", None)
        self.assertEqual(
            contract.assert_assignment_matches_metadata(contract.STANDARD_FORM, None),
            contract.STANDARD_FORM,
        )

    def test_unknown_and_non_string_forms_fail_closed(self):
        for bad in ("Observation", "poem", "STANDARD", 1, True, [], {}):
            with self.assertRaises(contract.ReflectionContractError):
                contract.normalize_reflection_form(bad)

    def test_boolean_word_count_is_not_an_integer(self):
        for bad in (True, False, 40.0, "40", None):
            with self.assertRaises(contract.ReflectionContractError):
                contract.validate_reflection_word_count(bad)


class ContractDescription(unittest.TestCase):
    def test_describe_contract_carries_form_and_both_ranges(self):
        standard = contract.describe_contract(None)
        self.assertEqual(standard, {
            "reflectionForm": "standard",
            "validWordRange": [25, 80],
            "targetWordRange": [35, 60],
            "explicitlyAssignedException": False,
        })
        cascade = contract.describe_contract("image_cascade")
        self.assertEqual(cascade["validWordRange"], [25, 120])
        self.assertEqual(cascade["targetWordRange"], [60, 100])
        self.assertTrue(cascade["explicitlyAssignedException"])


class CorpusEvidence(unittest.TestCase):
    """Read-only evidence. No corpus file is written by these tests."""

    def _words(self, story_id: int, lane: str) -> int:
        path = (REPO_ROOT / "assets" / "stories" / "traditional" / str(story_id)
                / f"reflection_{story_id}_traditional_{lane}.txt")
        return len(path.read_text(encoding="utf-8").split())

    def test_owner_exemplars_pass_the_standard_band(self):
        for story_id in (1242, 1537):
            for lane in ("web", "kjv"):
                words = self._words(story_id, lane)
                self.assertEqual(
                    contract.validate_reflection_word_count(words), (25, 80),
                    f"owner exemplar {story_id} {lane} ({words}w) must pass standard",
                )

    def test_named_reflection_voice_benchmarks_pass(self):
        # 1096/1121 were compressed to ~80 by REFLECTION_VOICE; 1111-1115 are the
        # image-cascade examples. All must remain valid under the new contract.
        for story_id in (1096, 1121, 1111, 1112, 1114, 1115):
            for lane in ("web", "kjv"):
                words = self._words(story_id, lane)
                contract.validate_reflection_word_count(words, "image_cascade")

    def test_proving_packet_reflections_fail_the_standard_band(self):
        # Evidence only: 3000-3004 are 171-207 words and are NOT modified here.
        source = pathlib.Path(
            "/private/tmp/bible_pal_proving_packet_001_correction_round_2"
        )
        if not source.is_dir():
            self.skipTest("proving-packet correction source is not present")
        for story_id in range(3000, 3005):
            for lane in ("web", "kjv"):
                path = source / str(story_id) / f"reflection_{story_id}_traditional_{lane}.txt"
                words = len(path.read_text(encoding="utf-8").split())
                self.assertGreater(words, 120, f"{story_id} {lane} expected long")
                with self.assertRaises(contract.ReflectionContractError):
                    contract.validate_reflection_word_count(words)


if __name__ == "__main__":
    unittest.main()
