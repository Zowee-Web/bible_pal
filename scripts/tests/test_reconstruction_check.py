#!/usr/bin/env python3
"""Tests for scripts/lib/reconstruction_check.py (ADR-031 diagnostics).

Every fixture is synthetic and built inside a tempfile.TemporaryDirectory.
The real corpus is never read, written, or depended upon — except for the
canonical Bible JSON, which is read-only reference data and is the tool's
declared comparison authority.

Run:
    python3 -m unittest scripts.tests.test_reconstruction_check -v
"""

import difflib
import inspect
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from lib import reconstruction_check as rc  # noqa: E402


def bible(lane="web"):
    return rc.load_bible(lane)


def verses(anchor, lane="web"):
    """Canonical text for an anchor, as a single string."""
    from lib.bible_ref_parser import parse_bible_refs, extract_verses
    out = []
    for ref in parse_bible_refs(anchor):
        out.extend(extract_verses(bible(lane), ref))
    return " ".join(t for _, _, t in out)


class NormalizationTestCase(unittest.TestCase):
    def test_curly_apostrophes_and_dashes_normalized(self):
        a = rc.normalize_tokens("David’s heart — it smote him")
        b = rc.normalize_tokens("David's heart - it smote him")
        self.assertEqual(a, b)
        self.assertIn("david's", a)

    def test_intra_word_apostrophe_preserved_quotes_stripped(self):
        t = rc.normalize_tokens("'Behold,' said David's men")
        self.assertIn("david's", t)
        self.assertIn("behold", t)
        self.assertNotIn("'behold", t)

    def test_no_stemming_or_synonym_mapping(self):
        self.assertNotEqual(rc.normalize_tokens("came"), rc.normalize_tokens("cameth"))
        self.assertNotEqual(rc.normalize_tokens("house"), rc.normalize_tokens("dwelling"))

    def test_word_order_preserved(self):
        self.assertEqual(rc.normalize_tokens("a b c"), ["a", "b", "c"])


class ContiguousSpanTestCase(unittest.TestCase):
    def test_token_boundary_safe_not_substring(self):
        """'he came' must NOT match inside 'he cameth' — the naive-substring trap."""
        source = rc.normalize_tokens("and he cameth unto the house")
        story = rc.normalize_tokens("he came")
        self.assertIsNone(rc.find_contiguous_span(source, story))

    def test_exact_span_found_with_offset(self):
        source = rc.normalize_tokens("alpha beta gamma delta epsilon")
        story = rc.normalize_tokens("gamma delta")
        self.assertEqual(rc.find_contiguous_span(source, story), 2)

    def test_non_contiguous_rejected(self):
        source = rc.normalize_tokens("alpha beta gamma delta")
        story = rc.normalize_tokens("alpha gamma")
        self.assertIsNone(rc.find_contiguous_span(source, story))

    def test_story_longer_than_source_rejected(self):
        self.assertIsNone(rc.find_contiguous_span(["a"], ["a", "b"]))


class StoryAnalysisTestCase(unittest.TestCase):
    """Each test writes a synthetic story file and analyzes it."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        self.dir = self.root / "assets" / "stories" / "traditional" / "9001"
        self.dir.mkdir(parents=True)
        self.source = rc.WorkingTreeSource(self.root)

    def tearDown(self):
        self._tmp.cleanup()

    def analyze(self, text, anchor="1 Samuel 24", lane="web", length="full"):
        name = f"story_9001_traditional_{lane}_{length}.txt"
        p = self.dir / name
        if isinstance(text, bytes):
            p.write_bytes(text)
        else:
            p.write_text(text, encoding="utf-8")
        rel = f"assets/stories/traditional/9001/{name}"
        return rc.analyze_story_rel(rel, "9001", lane, length, anchor,
                                    self.source)

    # -- 1. exact whole-passage copy ------------------------------------

    def test_exact_whole_passage_copy_is_reconstructible(self):
        f = self.analyze(verses("1 Samuel 24"))
        self.assertTrue(f.reconstructible)
        self.assertEqual(f.source_offset, 0)
        self.assertEqual(f.metrics.unmatched_words, 0)

    # -- 2. punctuation / capitalization / quotes / paragraphs only -----

    def test_punctuation_and_paragraph_only_differences_still_reconstructible(self):
        src = verses("1 Samuel 24")
        mangled = src.upper().replace(". ", ".\n\n").replace(",", " ,")
        mangled = '"' + mangled.replace("'", "’") + '"'
        f = self.analyze(mangled)
        self.assertTrue(f.reconstructible,
                        "cosmetic-only changes must not defeat the test")

    # -- 3. contiguous excerpt from a larger anchor ---------------------

    def test_contiguous_excerpt_of_larger_anchor_is_reconstructible(self):
        toks = rc.normalize_tokens(verses("1 Samuel 24"))
        excerpt = " ".join(toks[40:140])
        f = self.analyze(excerpt)
        self.assertTrue(f.reconstructible)
        self.assertEqual(f.source_offset, 40)

    # -- 4. one or two added connective sentences -----------------------

    def test_added_connective_sentences_not_level_1_but_long_run_visible(self):
        src = verses("1 Samuel 24")
        story = ("The day had come that the men had spoken of. " + src +
                 " And so they parted from that place.")
        f = self.analyze(story)
        self.assertFalse(f.reconstructible,
                         "added narration means it is not a contiguous span")
        self.assertGreater(f.metrics.longest_run, 500,
                           "the copied body must still surface as a long run")
        self.assertGreater(f.metrics.unmatched_words, 0)

    # -- 5. genuine retelling preserving essential dialogue -------------

    def test_genuine_retelling_with_preserved_dialogue(self):
        story = (
            "Saul returned from chasing the Philistines. Word reached him that "
            "David was hiding near En Gedi. He gathered three thousand men and "
            "went out to search the crags where wild goats climb.\n\n"
            "He stopped at a cave beside the sheep pens and went inside alone. "
            "Far back in the dark, David and his men were sitting still.\n\n"
            '"Yahweh forbid that I should do this thing to my lord," David told them.'
        )
        f = self.analyze(story)
        self.assertFalse(f.reconstructible)
        self.assertGreater(f.metrics.unmatched_words, 20,
                           "a real retelling carries substantial original narration")

    # -- 6. KJV classical retelling -------------------------------------

    def test_kjv_classical_retelling_not_penalized(self):
        story = (
            "Saul was come again from following the Philistines, and word was "
            "brought unto him concerning David. He took chosen men out of Israel "
            "and sought him among the rocks.\n\n"
            "And David said unto his men, The Lord forbid that I should do this "
            "thing unto my master."
        )
        f = self.analyze(story, lane="kjv")
        self.assertFalse(f.reconstructible,
                         "classical diction alone must not trigger Level 1")

    # -- 7. long exact dialogue surrounded by transformed narration -----

    def test_long_exact_dialogue_inside_transformed_narration(self):
        dialogue = ("Yahweh forbid that I should do this thing to my lord, "
                    "Yahweh's anointed, to stretch out my hand against him, "
                    "since he is Yahweh's anointed.")
        story = ("David rose in the dark and came back to the men who waited "
                 "for him among the stones at the back of the cave. "
                 f'He said to them, "{dialogue}" '
                 "They did not lift a hand after that. The king rose, walked "
                 "out through the mouth of the cave into the light, and went "
                 "on down the road none the wiser.")
        f = self.analyze(story)
        self.assertFalse(f.reconstructible)
        self.assertGreaterEqual(f.metrics.longest_run, 15,
                                "the preserved dialogue should surface as a run")
        # Substantial original narration around the quotation. The number is a
        # property of this fixture, not an acceptance threshold.
        self.assertGreater(f.metrics.unmatched_words, 25)

    # -- 8. high-overlap poetry / epistle: metrics, no verdict ----------

    def test_high_overlap_epistle_emits_metrics_without_verdict(self):
        f = self.analyze(verses("1 Corinthians 13:1-13"),
                         anchor="1 Corinthians 13:1-13")
        self.assertTrue(f.reconstructible)
        # The tool reports the fact and refuses to classify the anchor.
        self.assertEqual(f.anchor_category, "unknown")
        rendered = rc.format_reconstruction(f, "x.txt")
        for forbidden in ("defective", "must regenerate", "acceptable overlap",
                          "narrative", "non-narrative"):
            self.assertNotIn(forbidden, rendered.lower())

    # -- 9. whole-chapter anchor ----------------------------------------

    def test_whole_chapter_anchor_resolves(self):
        toks = rc.resolve_source_tokens("Daniel 6", "web")
        self.assertGreater(len(toks), 400)

    # -- 10. multi-chapter anchor ---------------------------------------

    def test_multi_chapter_anchor_resolves_all_chapters(self):
        four_only = rc.resolve_source_tokens("Esther 4", "web")
        multi = rc.resolve_source_tokens("Esther 4-7", "web")
        self.assertGreater(len(multi), len(four_only) * 2,
                           "multi-chapter must not truncate to the first chapter")

    # -- 11. discontinuous anchor ---------------------------------------

    def test_discontinuous_anchor_resolves(self):
        toks = rc.resolve_source_tokens("John 14:1-3, 18-19, 27", "web")
        joined = " ".join(toks)
        # WEB wording (the KJV lane reads "let not your heart be troubled").
        self.assertIn("don't let your heart be troubled", joined)   # vv1-3
        self.assertIn("i will not leave you orphans", joined)        # vv18-19
        self.assertIn("peace i leave with you", joined)              # v27
        # v4 sits between the ranges and must NOT be pulled in.
        self.assertNotIn("you know where i am going", joined)

    # -- 12. en-dash reference ------------------------------------------

    def test_en_dash_reference_resolves(self):
        hyphen = rc.resolve_source_tokens("Isaiah 40:28-31", "web")
        endash = rc.resolve_source_tokens("Isaiah 40:28–31", "web")
        self.assertEqual(hyphen, endash)

    # -- 13. intentionally missing verse (Acts 8:37) --------------------

    def test_intentionally_missing_verse_does_not_crash(self):
        toks = rc.resolve_source_tokens("Acts 8:26-40", "web")
        self.assertGreater(len(toks), 100)

    # -- 14. unparseable reference --------------------------------------

    def test_unparseable_reference_is_unresolved_not_false_pass(self):
        f = self.analyze("anything at all", anchor="Nonexistent Book 99:1-2")
        self.assertIsNotNone(f.unresolved)
        self.assertFalse(f.reconstructible,
                         "an unresolved anchor must never report a pass")

    def test_empty_anchor_is_unresolved(self):
        f = self.analyze("some text", anchor="")
        self.assertIsNotNone(f.unresolved)
        self.assertFalse(f.reconstructible)

    # -- 15. conflicting sibling scripture extract ----------------------

    def test_sibling_extract_is_ignored_canonical_json_decides(self):
        """A misleading scripture_*.txt sibling must not affect the result."""
        (self.dir / "scripture_9001_web.txt").write_text(
            "1 Samuel 24 (WEB)\n\nTOTALLY DIFFERENT TEXT THAT MATCHES NOTHING\n",
            encoding="utf-8")
        f = self.analyze(verses("1 Samuel 24"))
        self.assertTrue(f.reconstructible,
                        "result must be determined solely by canonical JSON")

    # -- 16. autojunk=False ---------------------------------------------

    def test_sequence_matcher_uses_autojunk_false(self):
        src = inspect.getsource(rc.compute_metrics)
        self.assertIn("autojunk=False", src)

    def test_autojunk_false_matters_on_repetitive_text(self):
        """With autojunk on, common tokens in long inputs get treated as junk."""
        source = rc.normalize_tokens(("and the lord said unto him " * 60))
        story = rc.normalize_tokens(("and the lord said unto him " * 60))
        m = rc.compute_metrics(source, story)
        self.assertEqual(m.longest_run, len(story))


class MetaTraversalTestCase(unittest.TestCase):
    META_REL = "assets/stories/traditional/9002/meta_9002.json"

    def test_maps_lanes_and_lengths_and_excludes_reflections(self):
        meta = {"storyId": 9002, "files": {
            "short": {"storyText": "story_9002_traditional_web_short.txt"},
            "short_kjv": {"storyText": "story_9002_traditional_kjv_short.txt"},
            "full": {"storyText": "story_9002_traditional_web_full.txt"},
            "full_kjv": {"storyText": "story_9002_traditional_kjv_full.txt"},
            "reflection": {"reflectionText": "reflection_9002_web.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(rejected, [])
        self.assertEqual(len(got), 4, "reflections must be excluded")
        self.assertEqual(
            sorted({(lane, length) for _, _, lane, length in got}),
            [("kjv", "full"), ("kjv", "short"), ("web", "full"), ("web", "short")])

    def test_unsuffixed_key_pointing_at_kjv_rejected_outside_allowlist(self):
        """A 25th such declaration must NOT inherit the legacy exception."""
        meta = {"storyId": 9002, "files": {
            "short": {"storyText": "story_9002_traditional_kjv_short.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(got, [])
        self.assertIn("24 enumerated legacy declarations",
                      rejected[0].unresolved)

    def test_legacy_allowlisted_unsuffixed_kjv_key_accepted(self):
        """One of the exact 24 documented corpus declarations still resolves."""
        self.assertEqual(len(rc.LEGACY_UNSUFFIXED_KJV_ALLOWLIST), 24)
        meta = {"storyId": 1000, "files": {
            "short": {"storyText": "story_1000_traditional_kjv_short.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(
            "assets/stories/traditional/1000/meta_1000.json", meta)
        self.assertEqual(rejected, [])
        self.assertEqual(got[0][2], "kjv", "lane comes from the filename")

    def test_kjv_key_pointing_at_web_file_rejected(self):
        meta = {"storyId": 9002, "files": {
            "short_kjv": {"storyText": "story_9002_traditional_web_short.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(got, [])
        self.assertIn("KJV key but the filename is WEB", rejected[0].unresolved)

    def test_key_length_mismatch_rejected(self):
        meta = {"storyId": 9002, "files": {
            "short": {"storyText": "story_9002_traditional_web_full.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(got, [])
        self.assertIn("declares length", rejected[0].unresolved)

    def test_absolute_and_traversal_values_rejected(self):
        for bad in ("/etc/passwd", "../9003/story_9003_traditional_web_short.txt",
                    "sub/story_9002_traditional_web_short.txt"):
            meta = {"storyId": 9002, "files": {"short": {"storyText": bad}}}
            got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
            self.assertEqual(got, [], f"{bad!r} must not resolve")
            self.assertTrue(rejected, f"{bad!r} must be reported")

    def test_story_id_disagreement_rejected(self):
        meta = {"storyId": 9999, "files": {
            "short": {"storyText": "story_9002_traditional_web_short.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(got, [])
        self.assertIn("story id disagreement", rejected[0].unresolved)

    def test_non_canonical_basename_rejected_not_guessed(self):
        meta = {"storyId": 9002,
                "files": {"short_kjv": {"storyText": "legacy_story_file.txt"}}}
        got, rejected = rc.story_files_from_meta_checked(self.META_REL, meta)
        self.assertEqual(got, [])
        self.assertIn("not a canonical", rejected[0].unresolved)



class ExplicitStoryPathTestCase(unittest.TestCase):
    """Files absent from meta.files are still analyzed when supplied explicitly."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name)
        self.dir = self.root / "assets" / "stories" / "traditional" / "9100"
        self.dir.mkdir(parents=True)
        self.source = rc.WorkingTreeSource(self.root)
        self.meta = {"storyId": 9100, "scriptureAnchor": "1 Samuel 24",
                     "files": {"short": {
                         "storyText": "story_9100_traditional_web_short.txt"}}}
        (self.dir / "meta_9100.json").write_text(json.dumps(self.meta),
                                                 encoding="utf-8")
        (self.dir / "story_9100_traditional_web_short.txt").write_text(
            "Saul went out with his men to look for David among the rocks.",
            encoding="utf-8")

    def tearDown(self):
        self._tmp.cleanup()

    UNDECLARED = "assets/stories/traditional/9100/story_9100_traditional_kjv_full.txt"
    META_REL = "assets/stories/traditional/9100/meta_9100.json"

    def write_undeclared(self, text):
        (self.dir / "story_9100_traditional_kjv_full.txt").write_text(
            text, encoding="utf-8")

    def analyze(self, rel):
        return rc.analyze_explicit_story_paths([rel], self.source, self.root)

    def test_meta_traversal_alone_misses_the_undeclared_file(self):
        self.write_undeclared(verses("1 Samuel 24", "kjv"))
        found = rc.analyze_meta(self.META_REL, self.meta, self.source, self.root)
        names = {pathlib.PurePosixPath(f.path).name for f in found}
        self.assertNotIn("story_9100_traditional_kjv_full.txt", names)

    def test_undeclared_explicit_path_is_analyzed(self):
        self.write_undeclared("A short retelling in plain words.")
        out = self.analyze(self.UNDECLARED)
        self.assertEqual(len(out), 1)
        self.assertIsNone(out[0].unresolved)
        self.assertEqual(out[0].anchor, "1 Samuel 24")

    def test_undeclared_exact_reproduction_is_flagged(self):
        self.write_undeclared(verses("1 Samuel 24", "kjv"))
        out = self.analyze(self.UNDECLARED)
        self.assertTrue(out[0].reconstructible)

    def test_filename_determines_lane_and_length(self):
        self.write_undeclared("text")
        out = self.analyze(self.UNDECLARED)
        self.assertEqual((out[0].lane, out[0].length), ("kjv", "full"))

    def test_declared_path_not_reported_twice(self):
        declared = "assets/stories/traditional/9100/story_9100_traditional_web_short.txt"
        combined = (rc.analyze_meta(self.META_REL, self.meta, self.source, self.root)
                    + self.analyze(declared))
        self.assertEqual(len(combined), 2)
        self.assertEqual(len(rc.dedupe_findings(combined)), 1)

    def test_dedupe_prefers_explicit_origin(self):
        declared = "assets/stories/traditional/9100/story_9100_traditional_web_short.txt"
        combined = (rc.analyze_meta(self.META_REL, self.meta, self.source, self.root)
                    + self.analyze(declared))
        merged = rc.dedupe_findings(combined)
        self.assertEqual(merged[0].origin, rc.ORIGIN_EXPLICIT)
        self.assertEqual(merged[0].story_id, "9100", "identity must be retained")
        self.assertEqual(merged[0].lane, "web")
        self.assertEqual(merged[0].length, "short")

    def test_conflicting_identities_become_unresolved(self):
        a = rc.Finding(path="p.txt", story_id="1", lane="web", length="short",
                       anchor="x", origin=rc.ORIGIN_METADATA)
        b = rc.Finding(path="p.txt", story_id="2", lane="kjv", length="full",
                       anchor="x", origin=rc.ORIGIN_EXPLICIT)
        merged = rc.dedupe_findings([a, b])
        self.assertEqual(len(merged), 1)
        self.assertIn("conflicting records for the same path",
                      merged[0].unresolved)

    def test_malformed_filename_is_unresolved_not_silent(self):
        bad = "assets/stories/traditional/9100/story_9100_traditional_greek_short.txt"
        (self.dir / "story_9100_traditional_greek_short.txt").write_text("t")
        out = self.analyze(bad)
        self.assertIsNotNone(out[0].unresolved)

    def test_id_directory_mismatch_is_unresolved(self):
        bad = "assets/stories/traditional/9100/story_9999_traditional_web_short.txt"
        (self.dir / "story_9999_traditional_web_short.txt").write_text("t")
        out = self.analyze(bad)
        self.assertIn("does not match its directory", out[0].unresolved)

    def test_missing_sibling_metadata_is_unresolved(self):
        (self.dir / "meta_9100.json").unlink()
        self.write_undeclared("text")
        out = self.analyze(self.UNDECLARED)
        self.assertIn("sibling metadata not found", out[0].unresolved)

    def test_absent_path_is_unresolved_not_silently_skipped(self):
        out = self.analyze(self.UNDECLARED)
        self.assertEqual(len(out), 1)
        self.assertIn("not present in the prospective commit", out[0].unresolved)

    def test_external_absolute_path_rejected(self):
        out = rc.analyze_explicit_story_paths(
            ["/tmp/elsewhere/assets/stories/traditional/1/"
             "story_1_traditional_web_short.txt"], self.source, self.root)
        self.assertIn("not inside the approved repository root",
                      out[0].unresolved)

    def test_symlink_story_is_rejected_not_followed(self):
        target = self.dir / "real.txt"
        target.write_text(verses("1 Samuel 24", "kjv"), encoding="utf-8")
        link = self.dir / "story_9100_traditional_kjv_full.txt"
        link.symlink_to("real.txt")
        out = self.analyze(self.UNDECLARED)
        self.assertIn("symlink", out[0].unresolved.lower())
        self.assertFalse(out[0].reconstructible)


class UndeclaredInventoryTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name) / "assets" / "stories" / "traditional"
        d = self.root / "9200"
        d.mkdir(parents=True)
        (d / "meta_9200.json").write_text(json.dumps({
            "storyId": 9200, "scriptureAnchor": "Daniel 6",
            "files": {"short": {"storyText": "story_9200_traditional_web_short.txt"}},
        }), encoding="utf-8")
        for name in ("story_9200_traditional_web_short.txt",
                     "story_9200_traditional_kjv_short.txt",
                     "story_9200_traditional_kjv_long.txt"):
            (d / name).write_text("x", encoding="utf-8")

    def tearDown(self):
        self._tmp.cleanup()

    def test_undeclared_inventory_reported_separately(self):
        got = rc.undeclared_story_files(self.root)
        names = sorted(p.split("/")[-1] for p in got)
        self.assertEqual(names, ["story_9200_traditional_kjv_long.txt",
                                 "story_9200_traditional_kjv_short.txt"])

    def test_kid_directories_excluded_from_adult_inventory(self):
        kid = self.root / "9201"
        kid.mkdir()
        (kid / "meta_9201.json").write_text(json.dumps(
            {"storyId": 9201, "kidFriendly": True, "files": {}}), encoding="utf-8")
        (kid / "story_9201_traditional_web_short.txt").write_text("x")
        got = rc.undeclared_story_files(self.root)
        self.assertFalse(any("9201" in p for p in got),
                         "kid stories must not leak into the adult inventory")

    def test_directory_with_missing_metadata_still_contributes(self):
        orphan = self.root / "9202"
        orphan.mkdir()
        (orphan / "story_9202_traditional_web_short.txt").write_text("x")
        got = rc.undeclared_story_files(self.root)
        self.assertTrue(any("9202" in p for p in got),
                        "missing metadata must not silently omit a directory")

    def test_directory_with_malformed_metadata_still_contributes(self):
        bad = self.root / "9203"
        bad.mkdir()
        (bad / "meta_9203.json").write_text("{ not json")
        (bad / "story_9203_traditional_web_short.txt").write_text("x")
        got = rc.undeclared_story_files(self.root)
        self.assertTrue(any("9203" in p for p in got))


class ContentSourceTestCase(unittest.TestCase):
    def test_infrastructure_and_advisory_errors_are_distinct_types(self):
        self.assertTrue(issubclass(rc.UnresolvedAnchor, rc.ContentUnavailable))
        self.assertFalse(issubclass(rc.InfrastructureError, rc.ContentUnavailable))

    def test_repo_relative_rejects_outside_and_traversal(self):
        root = pathlib.Path("/repo")
        self.assertIsNone(rc.repo_relative("/elsewhere/a.txt", root))
        self.assertIsNone(rc.repo_relative("../a.txt", root))
        self.assertEqual(rc.repo_relative("/repo/a/b.txt", root), "a/b.txt")
        self.assertEqual(rc.repo_relative("a/b.txt", root), "a/b.txt")

    def test_repo_relative_does_not_resolve_symlinks(self):
        """Identity is lexical, so two paths never merge via a symlink."""
        root = pathlib.Path("/repo")
        self.assertNotEqual(rc.repo_relative("/repo/a.txt", root),
                            rc.repo_relative("/repo/b.txt", root))

    def test_invalid_utf8_is_advisory(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            (root / "x.txt").write_bytes(b"\xff\xfe bad")
            src = rc.WorkingTreeSource(root)
            with self.assertRaises(rc.ContentUnavailable):
                src.read_text("x.txt")


class HookContractTestCase(unittest.TestCase):
    """The hook's accurate description; the stale disclosure must be gone."""

    HOOK = REPO_ROOT / "scripts" / "git_hooks" / "pre-commit"

    def test_hook_reads_index_bytes(self):
        self.assertIn("--reconstruction-from-index", self.HOOK.read_text())

    def test_stale_staged_content_limitation_api_removed(self):
        module = (REPO_ROOT / "scripts" / "lib" / "reconstruction_check.py").read_text()
        self.assertNotIn("STAGED_CONTENT_LIMITATION", module)
        self.assertNotIn("format_staged_content_limitation", module)
        self.assertFalse(hasattr(rc, "format_staged_content_limitation"))
        self.assertNotIn("[STAGED-CONTENT LIMITATION]", self.HOOK.read_text())

    def test_hook_uses_one_checked_nul_snapshot(self):
        hook = self.HOOK.read_text()
        self.assertIn("--name-status -z", hook)
        self.assertIn("--diff-filter=ACMRDT", hook,
                      "deletions AND type changes must be enumerated")
        # Substring-safe: ACMRDT contains ACMRD, so assert the exact token.
        self.assertRegex(hook, r"--diff-filter=ACMRDT(?![A-Z])")
        self.assertIn("--index-change-snapshot", hook)
        self.assertIn("set -f", hook, "pathname expansion must be disabled")
        # Exactly ONE enumeration: no second git diff/ls-files for the kid gate.
        # Match the invocation form specifically -- the FATAL message also
        # mentions `git diff --cached` and must not be counted as a second call.
        code = [ln for ln in hook.splitlines()
                if not ln.lstrip().startswith("#")]
        self.assertEqual(
            sum("git diff --cached --name-status" in ln for ln in code), 1,
            "there must be exactly one staged-change enumeration")
        self.assertFalse(any("git ls-files" in ln for ln in code))

    def test_hook_does_not_use_unquoted_word_splitting_for_paths(self):
        hook = self.HOOK.read_text()
        self.assertNotIn("for s in $STORY_PATHS", hook)
        self.assertNotIn("for m in $META_PATHS", hook)

    def test_hook_checks_git_status_without_suppression(self):
        hook = self.HOOK.read_text()
        self.assertIn("if ! git diff --cached", hook)
        # `git cat-file -e` may appear in a comment explaining why it is NOT
        # used; assert only that no executable line invokes it as a filter.
        code_lines = [ln for ln in hook.splitlines()
                      if not ln.lstrip().startswith("#")]
        self.assertFalse(any("git cat-file -e" in ln for ln in code_lines),
                         "must not silently drop paths via cat-file -e")


class AdvisoryContractTestCase(unittest.TestCase):
    """The tool must never emit an editorial verdict or a threshold."""

    MODULE = REPO_ROOT / "scripts" / "lib" / "reconstruction_check.py"

    def test_module_defines_no_acceptable_overlap_constant(self):
        src = self.MODULE.read_text()
        for banned in ("ACCEPTABLE_OVERLAP", "MAX_OVERLAP", "OVERLAP_THRESHOLD",
                       "PASS_THRESHOLD"):
            self.assertNotIn(banned, src)

    def test_display_cutoff_is_labelled_output_volume_control(self):
        src = self.MODULE.read_text()
        self.assertIn("Output-volume control only", src)
        self.assertIn("NOT an acceptance boundary", src)

    def test_reconstruction_report_never_prints_passage_text(self):
        f = rc.Finding(path="p.txt", story_id="1", lane="web", length="full",
                       anchor="1 Samuel 24", story_words=662, source_words=662,
                       reconstructible=True, source_offset=0, story_offset=0)
        out = rc.format_reconstruction(f, "p.txt")
        self.assertIn("source[0:662]", out)
        self.assertNotIn("Saul", out)
        self.assertNotIn("David", out)

    def test_anchor_category_always_unknown(self):
        f = rc.Finding(path="p.txt", story_id="1", lane="web", length="full",
                       anchor="Romans 8:18-39")
        self.assertEqual(f.anchor_category, "unknown")

    def test_metric_labels_are_precise(self):
        src = (REPO_ROOT / "scripts" / "validate_corpus.py").read_text()
        self.assertIn("SequenceMatcher block coverage", src)
        self.assertIn("unmatched story tokens", src)
        self.assertNotIn("connective {", src)

    def test_counts_are_labelled_post_deduplication(self):
        src = (REPO_ROOT / "scripts" / "validate_corpus.py").read_text()
        self.assertIn("all counts post-deduplication", src)
        self.assertIn("duplicates collapsed", src)

    def test_ratio_formatting_shows_one_decimal(self):
        """199/200 must not display as 100%."""
        m = rc.Metrics(matched_words=199, unmatched_words=1)
        f = rc.Finding(path="p", story_id="1", lane="web", length="short",
                       anchor="x", story_words=200, metrics=m)
        self.assertEqual(f"{f.block_coverage_ratio * 100:5.1f}", " 99.5")


if __name__ == "__main__":
    unittest.main()


# ---------------------------------------------------------------------------
# Final correction pass: type changes, current-vs-historical paths, relevance.
# ---------------------------------------------------------------------------


class TypeChangeParsingTestCase(unittest.TestCase):
    """Status T must survive parsing and count as CURRENT content."""

    def test_t_status_is_parsed_as_a_single_token_record(self):
        changes = rc.parse_change_snapshot(b"T\0assets/stories/x.txt\0M\0b.txt\0")
        self.assertEqual([c.status for c in changes], ["T", "M"])
        self.assertEqual(changes[0].path, "assets/stories/x.txt")
        self.assertIsNone(changes[0].src)

    def test_t_path_is_current_content(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            b"T\0assets/stories/traditional/1/story_1_traditional_kjv_short.txt\0"))
        self.assertEqual(
            c.story_paths,
            ["assets/stories/traditional/1/story_1_traditional_kjv_short.txt"])
        self.assertEqual(c.historical_paths, [])

    def test_t_on_schema_and_kid_inputs_is_recognized(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            b"T\0assets/stories/meta.schema.json\0"
            b"T\0assets/stories/kids_manifest.json\0"))
        self.assertTrue(c.schema_changed)
        self.assertIn(rc.KID_MANIFEST_PATH, c.kid_paths)


class CurrentVersusHistoricalPathTestCase(unittest.TestCase):
    """R/C sources and D paths are history, never content to validate."""

    STORY = "assets/stories/traditional/1/story_1_traditional_kjv_short.txt"
    OLD = "assets/stories/traditional/1/story_1_traditional_web_short.txt"
    META = "assets/stories/traditional/1/meta_1.json"

    def test_rename_destination_is_current_source_is_historical(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"R100\0{self.OLD}\0{self.STORY}\0".encode()))
        self.assertEqual(c.story_paths, [self.STORY])
        self.assertEqual(c.historical_paths, [self.OLD])
        self.assertNotIn(self.OLD, c.story_paths)

    def test_copy_destination_is_current_source_is_not_duplicated(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"C75\0{self.OLD}\0{self.STORY}\0".encode()))
        self.assertEqual(c.story_paths, [self.STORY])
        self.assertEqual(c.historical_paths, [self.OLD])

    def test_renamed_metadata_source_is_never_validated(self):
        old = "assets/stories/traditional/1/meta_old.json"
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"R100\0{old}\0{self.META}\0".encode()))
        self.assertEqual(c.canonical_metas, [self.META])
        self.assertNotIn(old, c.canonical_metas)
        self.assertEqual([p for p, _ in c.bad_metadata_paths], [],
                         "a historical source must not raise a path review")

    def test_deleted_story_is_only_a_deletion(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"D\0{self.STORY}\0".encode()))
        self.assertEqual(c.story_paths, [], "a deleted path is not content")
        self.assertEqual([d.path for d in c.deletions], [self.STORY])
        self.assertIn(self.STORY, c.historical_paths)

    def test_deleted_metadata_is_only_a_deletion(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"D\0{self.META}\0".encode()))
        self.assertEqual(c.canonical_metas, [],
                         "a deleted meta must never be validated or reported "
                         "as a missing file")
        self.assertEqual([d.path for d in c.deletions], [self.META])

    def test_delete_plus_add_remains_two_final_state_operations(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"D\0{self.OLD}\0A\0{self.STORY}\0".encode()))
        self.assertEqual(c.story_paths, [self.STORY])
        self.assertEqual([d.path for d in c.deletions], [self.OLD])

    def test_renamed_kid_manifest_still_triggers_the_kid_gate(self):
        c = rc.classify_changes(rc.parse_change_snapshot(
            f"R100\0{rc.KID_MANIFEST_PATH}\0docs/moved.json\0".encode()))
        self.assertIn(rc.KID_MANIFEST_PATH, c.kid_paths,
                      "moving a required input away still changes the commit")


class RelevanceParserTestCase(unittest.TestCase):
    """A newline inside a filename must never forge a relevant record."""

    FORGED = b"M\0docs/nope\nassets/stories/meta.schema.json\0"

    def test_embedded_newline_cannot_forge_relevance(self):
        self.assertFalse(rc.snapshot_is_relevant(self.FORGED))

    def test_shell_tr_grep_would_have_been_fooled(self):
        """Documents WHY the tr|grep pipeline was removed."""
        lines = self.FORGED.replace(b"\0", b"\n").decode().split("\n")
        self.assertIn("assets/stories/meta.schema.json", lines,
                      "tr would have produced a forged relevant line")

    def test_genuinely_relevant_path_containing_a_newline_is_relevant(self):
        data = b"A\0assets/stories/traditional/9/story_9\nweird.txt\0"
        self.assertTrue(rc.snapshot_is_relevant(data))

    def test_rename_source_and_destination_are_both_considered(self):
        self.assertTrue(rc.snapshot_is_relevant(
            b"R100\0assets/stories/kids_manifest.json\0docs/moved.json\0"))
        self.assertTrue(rc.snapshot_is_relevant(
            b"R100\0docs/moved.json\0assets/stories/kids_manifest.json\0"))

    def test_irrelevant_snapshot_is_irrelevant(self):
        self.assertFalse(rc.snapshot_is_relevant(b"M\0README.md\0A\0docs/a.md\0"))

    def test_exotic_characters_remain_atomic(self):
        for name in ("story_1 space.txt", "story_1\ttab.txt", "story_1_*.txt",
                     "story_1_[a-z].txt", "story_1_back\\slash.txt"):
            data = f"A\0assets/stories/traditional/1/{name}\0".encode()
            self.assertTrue(rc.snapshot_is_relevant(data), name)
            self.assertEqual(rc.parse_change_snapshot(data)[0].path,
                             f"assets/stories/traditional/1/{name}")

    def test_relevance_cli_does_not_import_jsonschema(self):
        """The relevance decision must not depend on a validation-only dep."""
        proc = subprocess.run(
            [sys.executable, "-c",
             "import sys; sys.path.insert(0, 'scripts');"
             "import lib.reconstruction_check;"
             "print('jsonschema' in sys.modules)"],
            cwd=str(REPO_ROOT), capture_output=True, text=True)
        self.assertEqual(proc.stdout.strip(), "False")

    def test_relevance_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as td:
            snap = pathlib.Path(td) / "snap"
            def run(data):
                snap.write_bytes(data)
                return subprocess.run(
                    [sys.executable, "-m", "lib.reconstruction_check",
                     "--relevance-check", str(snap)],
                    cwd=str(REPO_ROOT), capture_output=True, text=True,
                    env={**os.environ,
                         "PYTHONPATH": str(REPO_ROOT / "scripts")}).returncode
            self.assertEqual(run(b"M\0assets/stories/meta.schema.json\0"), 0)
            self.assertEqual(run(b"M\0README.md\0"), 1)
            self.assertEqual(run(b"R100\0only-one-path\0"), 2,
                             "a truncated snapshot must block, not look clean")


class ModeFieldRemovalTestCase(unittest.TestCase):
    def test_invisible_mode_note_field_is_gone(self):
        self.assertNotIn("mode_note", rc.Finding.__dataclass_fields__,
                         "a field that is never printed must not exist")
        module = (REPO_ROOT / "scripts" / "lib" / "reconstruction_check.py")
        self.assertNotIn("mode_note", module.read_text())


class DeletionReviewContractTestCase(unittest.TestCase):
    """review_deletions separates advisory classification from blocking defects."""

    class FakeSource:
        name = "git-index"

        def __init__(self, modes, jsons=None):
            self._modes = modes
            self._jsons = jsons or {}

        def entries(self):
            return {p: (m, "0" * 40) for p, m in self._modes.items()}

        def exists(self, rel):
            return rel in self._modes

        def mode(self, rel):
            return self._modes.get(rel)

        def read_json(self, rel):
            if rel not in self._jsons:
                raise AssertionError(
                    f"read_json({rel!r}) must not be reached for a "
                    f"non-ordinary metadata mode")
            return self._jsons[rel]

    STORY = "assets/stories/traditional/9500/story_9500_traditional_kjv_short.txt"
    META = "assets/stories/traditional/9500/meta_9500.json"

    def _classification(self):
        return rc.classify_changes(rc.parse_change_snapshot(
            f"D\0{self.STORY}\0".encode()))

    def test_returns_reviews_and_structural_errors(self):
        src = self.FakeSource({self.META: rc.NORMAL_FILE_MODE},
                              {self.META: {"storyId": 9500, "files": {}}})
        reviews, structural = rc.review_deletions(self._classification(), src)
        self.assertEqual(len(reviews), 1)
        self.assertEqual(structural, [])
        self.assertEqual(reviews[0].category, "declaration-removed-consistently")

    def test_executable_metadata_is_not_parsed_and_is_structural(self):
        # read_json raises AssertionError if reached -- proving mode is checked
        # BEFORE any parse, not after.
        src = self.FakeSource({self.META: rc.EXECUTABLE_FILE_MODE})
        reviews, structural = rc.review_deletions(self._classification(), src)
        self.assertEqual(len(reviews), 1, "the deletion is still classified")
        self.assertEqual(reviews[0].category,
                         "story-deleted-metadata-not-ordinary-data")
        self.assertEqual(len(structural), 1, "and it blocks independently")
        self.assertIn("executable mode 100755", structural[0])

    def test_symlink_metadata_is_not_parsed_and_is_structural(self):
        src = self.FakeSource({self.META: rc.SYMLINK_MODE})
        reviews, structural = rc.review_deletions(self._classification(), src)
        self.assertEqual(len(structural), 1)
        self.assertIn("symlink", structural[0])

    def test_gitlink_metadata_is_not_parsed_and_is_structural(self):
        src = self.FakeSource({self.META: rc.GITLINK_MODE})
        reviews, structural = rc.review_deletions(self._classification(), src)
        self.assertEqual(len(structural), 1)
        self.assertIn("gitlink", structural[0])

    def test_deletion_review_uses_the_shared_mode_helper(self):
        """Policy must not be duplicated; one helper governs every data read."""
        module = (REPO_ROOT / "scripts" / "lib" / "reconstruction_check.py"
                  ).read_text()
        self.assertIn("require_ordinary_data_mode(source, meta_rel", module)
        vc = (REPO_ROOT / "scripts" / "validate_corpus.py").read_text()
        self.assertIn("require_ordinary_data_mode", vc)
        self.assertNotIn("def require_ordinary_data_mode", vc,
                         "the helper lives in one module only")
