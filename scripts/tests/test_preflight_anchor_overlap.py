#!/usr/bin/env python3
"""Adversarial tests for scripts/preflight_anchor_overlap.py.

Every coverage universe is synthetic and built inside a
tempfile.TemporaryDirectory. The real corpus and the real worktrees are never
read, written, or depended upon — except the bundled WEB Bible JSON, which is
read-only reference data and is the gate's declared versification authority.

No network. No repository mutation.

Run:
    python3 -m unittest scripts.tests.test_preflight_anchor_overlap -v
"""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))

from preflight_anchor_overlap import (  # noqa: E402
    EXIT_BLOCK, EXIT_ERROR, EXIT_PASS, EXIT_WARN,
    KNOWN_QUEUE_STATES, NON_OCCUPYING_STATES, OCCUPYING_STATES,
    CoverageIntegrityError, GateError, classify, evaluate, main,
    normalize_reference, is_boundary_adjacent, load_bible, verse_set,
)

SCRIPT = os.path.join(REPO_ROOT, "scripts", "preflight_anchor_overlap.py")


def make_worktree(root, stories):
    """stories: iterable of (storyId, scriptureAnchor)."""
    for sid, anchor in stories:
        d = os.path.join(root, "assets", "stories", "traditional", str(sid))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, f"meta_{sid}.json"), "w", encoding="utf-8") as fh:
            json.dump({"storyId": sid, "scriptureAnchor": anchor,
                       "mode": "traditional"}, fh)
    return root


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bible = load_bible()

    def run_gate(self, candidate, existing=(), **kw):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        make_worktree(self._tmp.name, existing)
        return evaluate(candidate, worktrees=[self._tmp.name], **kw)


# ---------------------------------------------------------------- overlap ---

class TestOverlapClassification(Base):

    def test_exact_duplicate_blocks(self):
        r = self.run_gate("Genesis 37:1-36", [(1, "Genesis 37:1-36")])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["matches"][0]["classification"], "EXACT")
        self.assertEqual(r["blockingStoryIds"], [1])

    def test_candidate_contained_blocks(self):
        r = self.run_gate("Luke 24:13-24", [(1, "Luke 24:13-35")])
        m = r["matches"][0]
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(m["classification"], "CANDIDATE_CONTAINED")
        self.assertEqual(m["candidateCoverage"], 1.0)
        self.assertLess(m["existingCoverage"], 1.0)

    def test_existing_contained_blocks(self):
        r = self.run_gate("Genesis 22:1-19", [(1, "Genesis 22:1-14")])
        m = r["matches"][0]
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(m["classification"], "EXISTING_CONTAINED")
        self.assertEqual(m["existingCoverage"], 1.0)
        # max() is what catches this; candidate side alone would under-report.
        self.assertLess(m["candidateCoverage"], 1.0)
        self.assertEqual(m["maxSideCoverage"], 1.0)

    def test_whole_chapter_vs_subrange_blocks(self):
        r = self.run_gate("Daniel 6", [(1, "Daniel 6:16-23")])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["matches"][0]["classification"], "EXISTING_CONTAINED")

    def test_partial_high_overlap_blocks(self):
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")])
        m = r["matches"][0]
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(m["classification"], "PARTIAL")
        self.assertGreaterEqual(m["sharedVerses"], 3)
        self.assertGreaterEqual(m["maxSideCoverage"], 0.50)

    def test_chapter_range_candidate_blocks_subrange(self):
        r = self.run_gate("Genesis 7-8", [(1, "Genesis 8:1-12")])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["matches"][0]["classification"], "EXISTING_CONTAINED")


class TestSeamsAndAdjacency(Base):
    """Legitimate 'untold second half' episodes must survive the gate."""

    def test_adjacent_no_overlap_passes(self):
        r = self.run_gate("2 Kings 5:15-27", [(1, "2 Kings 5:1-14")])
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(r["matches"], [])
        self.assertEqual(r["cumulative"]["unionSharedVerses"], 0)

    def test_one_verse_seam_passes(self):
        r = self.run_gate("Genesis 22:14-19", [(1, "Genesis 22:1-14")])
        m = r["matches"][0]
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(m["classification"], "SEAM")
        self.assertEqual(m["sharedVerses"], 1)
        self.assertTrue(m["boundaryAdjacent"])

    def test_gospel_hinge_seam_passes(self):
        r = self.run_gate("Matthew 14:13-21", [(1, "Matthew 14:1-13")])
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(r["matches"][0]["classification"], "SEAM")

    def test_two_verse_seam_passes(self):
        r = self.run_gate("2 Chronicles 20:18-26", [(1, "2 Chronicles 20:1-19")])
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(r["matches"][0]["sharedVerses"], 2)

    def test_fifty_percent_seam_regression(self):
        """2 Kings 2:1-12 vs 2:11-14 scores 50% on a 2-verse hinge.

        A naive `maxSideCoverage >= 0.50` rule blocks this legitimate episode.
        Absolute shared-verse count plus boundary adjacency is the correct
        discriminator. This is the single false positive the measured design
        was built to avoid.
        """
        r = self.run_gate("2 Kings 2:11-14", [(1, "2 Kings 2:1-12")])
        m = r["matches"][0]
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(m["classification"], "SEAM")
        self.assertEqual(m["sharedVerses"], 2)
        self.assertEqual(m["maxSideCoverage"], 0.5)
        self.assertTrue(m["boundaryAdjacent"])

    def test_same_chapter_no_shared_verse_passes(self):
        r = self.run_gate("Daniel 6:1-9", [(1, "Daniel 6:16-23")])
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(r["matches"], [])

    def test_midrange_overlap_is_not_a_seam(self):
        """A 2-verse overlap in the MIDDLE of a range is not a seam."""
        shared_mid = classify(verse_set("Genesis 22:1-10", self.bible),
                              verse_set("Genesis 22:5-6", self.bible))
        self.assertEqual(shared_mid, "EXISTING_CONTAINED")
        self.assertFalse(is_boundary_adjacent(
            verse_set("Genesis 22:5-6", self.bible),
            verse_set("Genesis 22:1-10", self.bible),
            verse_set("Genesis 22:5-6", self.bible)))


class TestWarnBand(Base):

    def test_five_shared_verses_warns(self):
        r = self.run_gate("Acts 12:1-11", [(1, "Acts 12:7-25")])
        self.assertIn(r["verdict"], ("WARN", "BLOCK"))
        self.assertGreaterEqual(r["matches"][0]["sharedVerses"], 5)

    def test_composite_coverage_does_not_silently_pass(self):
        """2 Kings 22:8-20 is fully covered by 22:8-13 + 22:14-20 together,
        though neither half individually contains it."""
        r = self.run_gate("2 Kings 22:8-20",
                          [(1, "2 Kings 22:8-13"), (2, "2 Kings 22:14-20")])
        self.assertNotEqual(r["verdict"], "PASS")
        self.assertEqual(r["cumulative"]["candidateCoverageByUnion"], 1.0)
        self.assertEqual(r["cumulative"]["verdict"], "WARN")

    def test_cumulative_warn_fires_without_any_single_block(self):
        """Two disjoint slices each too small to block, together >= 60%."""
        r = self.run_gate("Genesis 24:1-10",
                          [(1, "Genesis 24:1-3"), (2, "Genesis 24:4-7")])
        self.assertGreaterEqual(r["cumulative"]["candidateCoverageByUnion"], 0.60)
        self.assertNotEqual(r["verdict"], "PASS")


# ---------------------------------------------------------- normalization ---

class TestNormalization(Base):

    def test_lowercase_and_extra_whitespace(self):
        self.assertEqual(
            normalize_reference("  luke   24:13-35  ", self.bible), "Luke 24:13-35")

    def test_uppercase_numbered_book(self):
        self.assertEqual(
            normalize_reference("1 SAMUEL 17:1-54", self.bible), "1 Samuel 17:1-54")

    def test_lowercase_book_resolves_end_to_end(self):
        r = self.run_gate("  luke   24:13-35  ", [(1, "Luke 24:13-35")])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["candidate"]["normalizedReference"], "Luke 24:13-35")

    def test_en_dash_variant(self):
        vs = verse_set("Isaiah 40:28–31", self.bible)
        self.assertEqual(len(vs), 4)

    def test_disjoint_multi_range(self):
        vs = verse_set("Matthew 13:24-30, 36-43", self.bible)
        self.assertEqual(len(vs), 15)

    def test_disjoint_multi_range_overlap_detected(self):
        r = self.run_gate("Matthew 13:24-30, 36-43", [(1, "Matthew 13:36-43")])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["matches"][0]["classification"], "EXISTING_CONTAINED")

    def test_malformed_references_fail_closed(self):
        for bad in ("", "   ", "Gnesis 1", "Genesis 999:1-5", "not a reference"):
            with self.subTest(bad=bad):
                with self.assertRaises(GateError):
                    self.run_gate(bad, [(1, "Genesis 1:1-5")])


# ------------------------------------------------------- universe / queue ---

class TestUniverse(Base):

    def test_untracked_story_in_another_worktree_is_seen(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            make_worktree(a, [(1, "Genesis 1:1-31")])
            make_worktree(b, [(2, "Ruth 2:1-23")])  # untracked lane
            r = evaluate("Ruth 2:1-23", worktrees=[a, b])
            self.assertEqual(r["verdict"], "BLOCK")
            self.assertEqual(r["blockingStoryIds"], [2])
            self.assertTrue(r["matches"][0]["origin"].startswith("worktree:"))

    def test_dedupe_identical_story_across_worktrees(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            make_worktree(a, [(1, "Ruth 2:1-23")])
            make_worktree(b, [(1, "Ruth 2:1-23")])
            r = evaluate("Ruth 2:1-23", worktrees=[a, b])
            self.assertEqual(r["universe"]["distinctStories"], 1)
            self.assertEqual(len(r["matches"]), 1)

    def test_same_id_different_anchor_conflict_blocks(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            make_worktree(a, [(1, "Ruth 2:1-23")])
            make_worktree(b, [(1, "Esther 4:1-17")])
            r = evaluate("Jonah 1:1-17", worktrees=[a, b])
            self.assertEqual(r["verdict"], "BLOCK")
            codes = [w["code"] for w in r["warnings"]]
            self.assertIn("WORKTREE_ANCHOR_CONFLICT", codes)

    def test_candidate_does_not_overlap_itself(self):
        r = self.run_gate("Ruth 2:1-23", [(77, "Ruth 2:1-23")], story_id=77)
        self.assertEqual(r["verdict"], "PASS")
        self.assertEqual(r["matches"], [])



class TestCoverageIntegrity(Base):
    """Any condition preventing full knowledge of the occupied universe must
    yield CoverageIntegrityError -> verdict ERROR / exit 30. Never PASS, never
    WARN, and never disguised as an ordinary overlap BLOCK."""

    def _expect_integrity(self, candidate, existing, condition_fragment):
        with tempfile.TemporaryDirectory() as t:
            for name, payload in existing:
                d = os.path.join(t, "assets", "stories", "traditional", name)
                os.makedirs(d, exist_ok=True)
                with open(os.path.join(d, f"meta_{name}.json"), "w",
                          encoding="utf-8") as fh:
                    fh.write(payload if isinstance(payload, str)
                             else json.dumps(payload))
            with self.assertRaises(CoverageIntegrityError) as ctx:
                evaluate(candidate, worktrees=[t])
            conds = [f["condition"] for f in ctx.exception.failures]
            self.assertTrue(any(condition_fragment in c for c in conds),
                            f"expected {condition_fragment!r} in {conds}")
            return ctx.exception

    def test_unparseable_existing_anchor_hiding_overlap_is_error(self):
        """The unparseable anchor is a real Emmaus story the candidate collides
        with. The advisory-and-continue policy would have returned PASS here —
        that policy is rejected; this must be ERROR."""
        exc = self._expect_integrity(
            "Luke 24:13-24",
            [("1", {"storyId": 1, "scriptureAnchor": "Lk 24:13-35 (Emmaus)"})],
            "existing scriptureAnchor cannot be parsed")
        self.assertEqual(exc.failures[0]["storyId"], 1)
        self.assertIn("Lk 24:13-35", exc.failures[0]["rawAnchor"])

    def test_malformed_json_meta_is_error(self):
        self._expect_integrity(
            "Luke 24:13-24",
            [("1", "{ this is not json "),
             ("2", {"storyId": 2, "scriptureAnchor": "Ruth 2:1-23"})],
            "not valid JSON")

    def test_missing_scripture_anchor_is_error(self):
        self._expect_integrity("Luke 24:13-24",
                               [("1", {"storyId": 1})],
                               "missing or empty scriptureAnchor")

    def test_empty_scripture_anchor_is_error(self):
        self._expect_integrity("Luke 24:13-24",
                               [("1", {"storyId": 1, "scriptureAnchor": "   "})],
                               "missing or empty scriptureAnchor")

    def test_missing_story_id_is_error(self):
        self._expect_integrity("Luke 24:13-24",
                               [("1", {"scriptureAnchor": "Luke 24:13-35"})],
                               "missing or invalid storyId")

    def test_unreadable_story_directory_is_error(self):
        """B4: directory ENUMERATION failure, not merely unreadable contents.
        glob.glob() collapsed EACCES into an empty (passing) universe."""
        tmp = tempfile.mkdtemp()
        d = os.path.join(tmp, "assets", "stories", "traditional")
        os.makedirs(os.path.join(d, "1"))
        with open(os.path.join(d, "1", "meta_1.json"), "w", encoding="utf-8") as fh:
            json.dump({"storyId": 1, "scriptureAnchor": "Luke 24:13-35"}, fh)
        os.chmod(d, 0o000)
        self.addCleanup(os.chmod, d, 0o755)
        if os.access(d, os.R_OK):
            self.skipTest("running as root; see mocked variant below")
        with self.assertRaises(CoverageIntegrityError) as ctx:
            evaluate("Luke 24:13-24", worktrees=[tmp])
        self.assertIn("could not be enumerated",
                      ctx.exception.failures[0]["condition"])

    def test_unreadable_story_directory_is_error_mocked(self):
        """Deterministic variant that does not depend on platform permission
        semantics: os.scandir on the story area raises PermissionError."""
        from unittest import mock
        import preflight_anchor_overlap as gate_mod
        with tempfile.TemporaryDirectory() as t:
            base = os.path.join(t, "assets", "stories", "traditional")
            os.makedirs(base)
            real_scandir = os.scandir

            def deny(path, *a, **kw):
                if os.path.realpath(str(path)) == os.path.realpath(base):
                    raise PermissionError(13, "Permission denied", str(path))
                return real_scandir(path, *a, **kw)

            with mock.patch.object(gate_mod.os, "scandir", side_effect=deny):
                with self.assertRaises(CoverageIntegrityError) as ctx:
                    evaluate("Luke 24:13-24", worktrees=[t])
        f = ctx.exception.failures[0]
        self.assertIn("could not be enumerated", f["condition"])
        self.assertEqual(f["detail"], "Permission denied")

    def test_failed_worktree_is_not_reported_as_scanned(self):
        """A worktree whose story area cannot be enumerated must not appear in
        worktreesScanned — surfaced via the integrity failure instead."""
        from unittest import mock
        import preflight_anchor_overlap as gate_mod
        with tempfile.TemporaryDirectory() as bad:
            os.makedirs(os.path.join(bad, "assets", "stories", "traditional"))
            with mock.patch.object(
                    gate_mod.os, "scandir",
                    side_effect=PermissionError(13, "Permission denied", bad)):
                with self.assertRaises(CoverageIntegrityError):
                    evaluate("Luke 24:13-24", worktrees=[bad])

    def test_unreachable_parent_directory_is_error(self):
        """F3: an unreadable PARENT (assets/stories/) makes os.path.exists()
        on the story area return False, silently treating the whole worktree
        as coverage-free — the gate returned PASS/0 while an EXACT duplicate
        was hidden inside. Repaired: only FileNotFoundError means "legitimately
        absent"; any other OSError is a coverage-integrity ERROR."""
        tmp = tempfile.mkdtemp()
        stories = os.path.join(tmp, "assets", "stories")
        d = os.path.join(stories, "traditional", "1")
        os.makedirs(d)
        with open(os.path.join(d, "meta_1.json"), "w", encoding="utf-8") as fh:
            json.dump({"storyId": 1, "scriptureAnchor": "Ruth 2:1-23"}, fh)

        # Readable control: the duplicate must BLOCK.
        r = evaluate("Ruth 2:1-23", worktrees=[tmp])
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["blockingStoryIds"], [1])

        os.chmod(stories, 0o000)
        self.addCleanup(os.chmod, stories, 0o755)
        if os.access(stories, os.R_OK):
            self.skipTest("running privileged; mocked variant covers this")
        with self.assertRaises(CoverageIntegrityError) as ctx:
            evaluate("Ruth 2:1-23", worktrees=[tmp])
        self.assertIn("could not be reached",
                      ctx.exception.failures[0]["condition"])

    def test_unreachable_parent_directory_is_error_mocked(self):
        """Deterministic F3 variant, independent of platform permission
        semantics: os.stat on the story area raises PermissionError while a
        hidden exact-duplicate meta exists behind it. Fails against the
        pre-repair implementation (which used os.path.exists and PASSed)."""
        from unittest import mock
        import preflight_anchor_overlap as gate_mod
        with tempfile.TemporaryDirectory() as t:
            base = os.path.join(t, "assets", "stories", "traditional")
            d = os.path.join(base, "1")
            os.makedirs(d)
            with open(os.path.join(d, "meta_1.json"), "w",
                      encoding="utf-8") as fh:
                json.dump({"storyId": 1, "scriptureAnchor": "Ruth 2:1-23"}, fh)

            real_stat = os.stat

            def deny(path, *a, **kw):
                if os.path.realpath(str(path)) == os.path.realpath(base):
                    raise PermissionError(13, "Permission denied", str(path))
                return real_stat(path, *a, **kw)

            with mock.patch.object(gate_mod.os, "stat", side_effect=deny):
                with self.assertRaises(CoverageIntegrityError) as ctx:
                    evaluate("Ruth 2:1-23", worktrees=[t])
        f = ctx.exception.failures[0]
        self.assertIn("could not be reached", f["condition"])
        self.assertEqual(f["detail"], "Permission denied")

    def test_absent_story_area_is_still_a_legitimate_skip(self):
        """FileNotFoundError remains the ONE non-error absence: a worktree with
        no Traditional story area at all is skipped, not an integrity failure."""
        with tempfile.TemporaryDirectory() as t:
            r = evaluate("Ruth 2:1-23", worktrees=[t])
            self.assertEqual(r["verdict"], "PASS")
            self.assertEqual(r["universe"]["worktreesScanned"], 0)

    def test_boolean_story_id_is_error(self):
        """Python bools subclass int; {"storyId": true} must never masquerade
        as story 1. Pins the isinstance(int)-with-bool-exclusion guard that
        Window 3 independently verified."""
        for value in (True, False):
            with self.subTest(storyId=value):
                self._expect_integrity(
                    "Ruth 2:1-23",
                    [("1", {"storyId": value,
                            "scriptureAnchor": "Ruth 2:1-23"})],
                    "missing or invalid storyId")

    def test_integrity_error_carries_locators_not_contents(self):
        exc = self._expect_integrity(
            "Luke 24:13-24", [("1", '{ "storyId": 1, "secret": "S3CR3T" ')],
            "not valid JSON")
        blob = json.dumps(exc.failures)
        self.assertNotIn("S3CR3T", blob)
        self.assertIn("meta_1.json", blob)


class TestReservations(Base):

    def _queue(self, entries):
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump({"reservations": entries}, f)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_reserved_proposal_blocks_before_files_exist(self):
        q = self._queue([{"storyId": 1700, "proposedAnchor": "Nahum 1:1-15",
                          "state": "reserved"}])
        r = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertEqual(r["blockingStoryIds"], [1700])
        self.assertEqual(r["matches"][0]["origin"], "queue")

    def test_authoring_and_locked_states_occupy(self):
        for state in ("authoring", "locked"):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1701, "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                r = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
                self.assertEqual(r["verdict"], "BLOCK")

    def test_abandoned_and_expired_do_not_occupy(self):
        for state in ("abandoned", "expired", "released"):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1702, "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                r = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
                self.assertEqual(r["verdict"], "PASS")
                self.assertEqual(r["universe"]["occupyingReservations"], 0)

    def test_materialized_state_fails_closed(self):
        # The producer defect that motivated the closed vocabulary: the
        # controller once emitted "materialized", which is not a gate state.
        # It was silently dropped, so a materialized story occupied nothing.
        q = self._queue([{"storyId": 1704, "proposedAnchor": "Nahum 1:1-15",
                          "state": "materialized"}])
        with self.assertRaises(GateError) as ctx:
            self.run_gate("Nahum 1:1-15", [], reservations_path=q)
        self.assertIn("materialized", str(ctx.exception))

    def test_arbitrary_future_state_fails_closed(self):
        for state in ("suspended", "claimed", "recoverable", "authoring_v2",
                      "reservd", "materialised", "retired", "aborted"):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1705,
                                  "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                with self.assertRaises(GateError):
                    self.run_gate("Nahum 1:1-15", [], reservations_path=q)

    def test_case_and_whitespace_are_normalised_before_the_vocabulary_check(self):
        # Pre-existing loader behaviour, pinned deliberately: the state is
        # .strip().lower()-ed first, so "LOCKED " is the known state "locked"
        # and must still BLOCK.  Only a genuinely unrecognised NAME fails
        # closed -- the vocabulary check is not a formatting check.
        for state in ("LOCKED ", "  Reserved", "AUTHORING"):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1708,
                                  "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                result = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
                self.assertEqual(result["verdict"], "BLOCK")
        for state in (" Released ", "EXPIRED"):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1709,
                                  "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                result = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
                self.assertEqual(result["verdict"], "PASS")

    def test_unknown_state_fails_closed_even_when_it_cannot_collide(self):
        # An unknown state is refused on sight, not merely when it would have
        # blocked something.  The gate has no basis for deciding an unfamiliar
        # name is free, so it must not reach a verdict at all.
        q = self._queue([{"storyId": 1706, "proposedAnchor": "Jonah 1:1-17",
                          "state": "suspended"}])
        with self.assertRaises(GateError):
            self.run_gate("Nahum 1:1-15", [], reservations_path=q)

    def test_known_vocabulary_is_closed_and_partitioned(self):
        self.assertEqual(KNOWN_QUEUE_STATES,
                         OCCUPYING_STATES | NON_OCCUPYING_STATES)
        self.assertEqual(OCCUPYING_STATES & NON_OCCUPYING_STATES, frozenset())
        self.assertEqual(OCCUPYING_STATES, {"reserved", "authoring", "locked"})
        self.assertEqual(NON_OCCUPYING_STATES,
                         {"abandoned", "expired", "released"})

    def test_every_known_state_is_accepted_and_classified(self):
        # Pins legacy semantics: every name in the vocabulary parses, and each
        # one lands on the side of the partition it is declared on.
        for state in sorted(KNOWN_QUEUE_STATES):
            with self.subTest(state=state):
                q = self._queue([{"storyId": 1707,
                                  "proposedAnchor": "Nahum 1:1-15",
                                  "state": state}])
                result = self.run_gate("Nahum 1:1-15", [], reservations_path=q)
                if state in OCCUPYING_STATES:
                    self.assertEqual(result["verdict"], "BLOCK")
                    self.assertEqual(result["universe"]["occupyingReservations"], 1)
                else:
                    self.assertEqual(result["verdict"], "PASS")
                    self.assertEqual(result["universe"]["occupyingReservations"], 0)

    def test_malformed_reservation_fails_closed(self):
        q = self._queue([{"storyId": 1703}])
        with self.assertRaises(GateError):
            self.run_gate("Nahum 1:1-15", [], reservations_path=q)

    def test_missing_reservations_file_fails_closed(self):
        with self.assertRaises(GateError):
            self.run_gate("Nahum 1:1-15", [], reservations_path="/nonexistent/q.json")


# ------------------------------------------------------------- approvals ---

class TestApprovals(Base):

    def _approvals(self, entries):
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump({"approvals": entries}, f)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    OWNER = {
        "approvedBy": "owner",
        "candidateAnchor": "Joshua 6:15-21",
        "acknowledgedStoryIds": [1],
        "maxPermittedSharedVerses": 6,
        "maxPermittedCandidateCoverage": 1.0,
        "reason": "Second telling from the seventh-day perspective.",
    }

    def test_absent_approvals_file_is_not_an_error(self):
        r = self.run_gate("Ruth 2:1-23", [], approvals_path="/nonexistent/a.json")
        self.assertEqual(r["verdict"], "PASS")

    def test_bounded_owner_approval_permits_overlap(self):
        a = self._approvals([self.OWNER])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")], approvals_path=a)
        self.assertEqual(r["verdict"], "PASS")
        self.assertTrue(r["exception"]["applied"])
        self.assertEqual(r["blockingStoryIds"], [])

    def test_overlap_exceeding_approved_shared_verses_still_blocks(self):
        ap = dict(self.OWNER, maxPermittedSharedVerses=2)
        a = self._approvals([ap])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")], approvals_path=a)
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertFalse(r["exception"]["applied"])
        self.assertIn("exceeds approved", r["exception"]["reason"])

    def test_overlap_exceeding_approved_coverage_still_blocks(self):
        ap = dict(self.OWNER, maxPermittedCandidateCoverage=0.10)
        a = self._approvals([ap])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")], approvals_path=a)
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertFalse(r["exception"]["applied"])

    def test_unacknowledged_blocking_story_still_blocks(self):
        ap = dict(self.OWNER, acknowledgedStoryIds=[999])
        a = self._approvals([ap])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")], approvals_path=a)
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertIn("does not acknowledge", r["exception"]["reason"])

    def test_non_allowlisted_identity_is_rejected(self):
        """Authorization is approvedBy IN allowlist, never NOT-IN a denylist.
        Known agents, denylist-evading names, and arbitrary unknown strings
        must all be equally powerless."""
        for who in ("Claude", "Codex", "Assistant", "AI", "Gemini",
                    "gpt-5.6-sol", "automation-bot", "agent:window2",
                    "Mistral", "future-model-x", "random-stranger", "system"):
            with self.subTest(approvedBy=who):
                a = self._approvals([dict(self.OWNER, approvedBy=who)])
                r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")],
                                  approvals_path=a)
                self.assertEqual(r["verdict"], "BLOCK")
                self.assertFalse(r["exception"]["applied"])
                self.assertIn("APPROVAL_REJECTED",
                              [w["code"] for w in r["warnings"]])

    def test_owner_is_the_default_allowlist(self):
        a = self._approvals([self.OWNER])  # approvedBy == "owner"
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")],
                          approvals_path=a)
        self.assertEqual(r["verdict"], "PASS")
        self.assertTrue(r["exception"]["applied"])

    def test_configured_extra_human_approver_is_accepted(self):
        a = self._approvals([dict(self.OWNER, approvedBy="adam")])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")],
                          approvals_path=a,
                          authorized_approvers=frozenset({"owner", "adam"}))
        self.assertEqual(r["verdict"], "PASS")
        self.assertTrue(r["exception"]["applied"])

    def test_unconfigured_human_name_is_still_rejected(self):
        a = self._approvals([dict(self.OWNER, approvedBy="adam")])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")],
                          approvals_path=a)  # default allowlist: owner only
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertFalse(r["exception"]["applied"])

    def test_incomplete_approval_is_rejected(self):
        ap = {k: v for k, v in self.OWNER.items() if k != "reason"}
        a = self._approvals([ap])
        r = self.run_gate("Joshua 6:15-21", [(1, "Joshua 6:1-20")], approvals_path=a)
        self.assertEqual(r["verdict"], "BLOCK")
        self.assertIn("APPROVAL_REJECTED", [w["code"] for w in r["warnings"]])


# ---------------------------------------------------------------- CLI/IO ---

class TestCli(Base):

    def _run(self, args, cwd=None):
        return subprocess.run([sys.executable, SCRIPT] + args,
                              capture_output=True, text=True, timeout=180,
                              cwd=cwd or REPO_ROOT)

    def test_exit_code_pass(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Genesis 1:1-31")])
            p = self._run(["--anchor", "Nahum 1:1-15", "--worktree", t])
            self.assertEqual(p.returncode, EXIT_PASS)
            self.assertEqual(json.loads(p.stdout)["verdict"], "PASS")

    def test_exit_code_block(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Nahum 1:1-15")])
            p = self._run(["--anchor", "Nahum 1:1-15", "--worktree", t])
            self.assertEqual(p.returncode, EXIT_BLOCK)

    def test_exit_code_warn_exact(self):
        """Deterministic WARN: Psalm 119:10-25 vs 119:1-12 + 119:23-35.
        Each match: PARTIAL, 3 shared, max-side 0.25/0.23 -> WARN band only
        (>=3 shared and >=0.20, below every BLOCK rule). Cumulative union is
        6/16 = 0.375 < 0.60, so nothing escalates. Exit must be exactly 10."""
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Psalm 119:1-12"), (2, "Psalm 119:23-35")])
            p = self._run(["--anchor", "Psalm 119:10-25", "--worktree", t])
            self.assertEqual(p.returncode, EXIT_WARN)
            d = json.loads(p.stdout)
            self.assertEqual(d["verdict"], "WARN")
            self.assertEqual([m["verdict"] for m in d["matches"]],
                             ["WARN", "WARN"])
            self.assertEqual(d["blockingStoryIds"], [])

    def test_exit_code_composite_warn_vs_block_distinction(self):
        """The composite fixture BLOCKS (each half is EXISTING_CONTAINED);
        kept to pin that it is a block, not a warn."""
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "2 Kings 22:8-13"), (2, "2 Kings 22:14-20")])
            p = self._run(["--anchor", "2 Kings 22:8-20", "--worktree", t,
                           "--story-id", "9999"])
            self.assertEqual(p.returncode, EXIT_BLOCK)

    def test_exit_code_error_on_malformed_and_never_pass(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Genesis 1:1-31")])
            p = self._run(["--anchor", "Gnesis 1", "--worktree", t])
            self.assertEqual(p.returncode, EXIT_ERROR)
            out = json.loads(p.stdout)
            self.assertEqual(out["verdict"], "ERROR")
            self.assertNotEqual(out["verdict"], "PASS")

    def test_stdout_is_pure_json(self):
        """extract_verses narrates omitted verses on stderr; stdout must stay
        machine-readable."""
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Acts 8:26-40")])
            p = self._run(["--anchor", "Acts 8:26-40", "--worktree", t])
            json.loads(p.stdout)  # must not raise

    def test_report_contract_fields_present(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Genesis 1:1-31")])
            p = self._run(["--anchor", "Nahum 1:1-15", "--worktree", t])
            d = json.loads(p.stdout)
            for k in ("gateVersion", "evaluatedAt", "versification", "candidate",
                      "universe", "matches", "cumulative", "exception",
                      "verdict", "blockingStoryIds", "warnings"):
                self.assertIn(k, d)
            self.assertEqual(d["versification"], "WEB")
            self.assertIn("anchor_coverage.json",
                          " ".join(d["universe"]["sourcesRefused"]))

    def test_cli_integrity_error_shape(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(2, "Ruth 2:1-23")])
            bad = os.path.join(t, "assets", "stories", "traditional", "1")
            os.makedirs(bad)
            with open(os.path.join(bad, "meta_1.json"), "w") as fh:
                fh.write("{ not json ")
            p = self._run(["--anchor", "Nahum 1:1-15", "--worktree", t])
            self.assertEqual(p.returncode, EXIT_ERROR)
            d = json.loads(p.stdout)
            self.assertEqual(d["verdict"], "ERROR")
            self.assertEqual(d["errorCode"], "COVERAGE_INTEGRITY_FAILURE")
            self.assertTrue(d["integrityFailures"])
            self.assertIn("condition", d["integrityFailures"][0])

    def test_cli_approver_flag_extends_allowlist(self):
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Joshua 6:1-20")])
            f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
            json.dump({"approvals": [{
                "approvedBy": "adam", "candidateAnchor": "Joshua 6:15-21",
                "acknowledgedStoryIds": [1], "maxPermittedSharedVerses": 6,
                "maxPermittedCandidateCoverage": 1.0, "reason": "cli test"}]}, f)
            f.close()
            self.addCleanup(os.unlink, f.name)
            without = self._run(["--anchor", "Joshua 6:15-21", "--worktree", t,
                                 "--approvals", f.name])
            self.assertEqual(without.returncode, EXIT_BLOCK)
            withf = self._run(["--anchor", "Joshua 6:15-21", "--worktree", t,
                               "--approvals", f.name, "--approver", "adam"])
            self.assertEqual(withf.returncode, EXIT_PASS)

    def test_gate_does_not_write_to_repository(self):
        before = subprocess.run(["git", "status", "--porcelain=v1"], cwd=REPO_ROOT,
                                capture_output=True, text=True).stdout
        with tempfile.TemporaryDirectory() as t:
            make_worktree(t, [(1, "Genesis 1:1-31")])
            self._run(["--anchor", "Nahum 1:1-15", "--worktree", t])
        after = subprocess.run(["git", "status", "--porcelain=v1"], cwd=REPO_ROOT,
                               capture_output=True, text=True).stdout
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main(verbosity=2)
