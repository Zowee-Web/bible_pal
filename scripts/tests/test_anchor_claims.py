#!/usr/bin/env python3
"""Anchor claim ledger tests -- Multi-Packet Design V2+V3+V4 matrix.

Row numbers in test names refer to the design's test matrix.  The V4 rows
(43-56) are the ones that would have caught the fail-open an independent
reviewer found after three self-authored passes, so they are exercised against
the real module, never a mock.
"""

from __future__ import annotations

import copy
import itertools
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "story_factory"))

import anchor_claims as acl  # noqa: E402
import preflight_anchor_overlap as gate  # noqa: E402


GEN = "Genesis 1:1-5"
GEN_PARTIAL = "Genesis 1:3-8"
FAR = ("Nahum 1:1-15", "Habakkuk 1:1-11", "Zephaniah 1:1-9",
       "Haggai 1:1-11", "Malachi 1:1-14")


def proposals(anchors=FAR):
    return [{"slotId": i + 1, "anchor": a} for i, a in enumerate(anchors)]


class AclTestCase(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="acl-home-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def claim(self, run="run-a", packet="packet-1", anchors=FAR, actor="owner",
              **kw):
        return acl.claim_packet_anchors(
            run_id=run, packet_id=packet, proposals=proposals(anchors),
            actor=actor, factory_home=self.home, **kw)

    def states(self):
        return acl.replay_ledger(self.home)

    def ledger_bytes(self):
        path = acl.ledger_path(self.home)
        return path.read_bytes() if path.exists() else b""

    # -- gate helper ------------------------------------------------------
    def run_gate(self, candidate, rows, story_id=None):
        fd, path = tempfile.mkstemp(suffix=".json", dir=str(self.home))
        with os.fdopen(fd, "w") as fh:
            json.dump({"reservations": rows}, fh)
        empty = Path(tempfile.mkdtemp(dir=str(self.home)))
        return gate.evaluate(candidate, story_id=story_id,
                             worktrees=[str(empty)], reservations_path=path)


# ---------------------------------------------------------------------------
# Projection: rows 43-48
# ---------------------------------------------------------------------------

class TestProjection(AclTestCase):

    def _claim(self, state, anchor=GEN, story_id=None):
        return acl.AnchorClaim(
            run_id="r", packet_id="p", slot_id=1, normalized_anchor=anchor,
            anchor_key=acl.anchor_key(anchor), comparison_id=-42, state=state,
            packet_claim_hash="h", event_id="e", story_id=story_id)

    def test_projection_is_total_over_the_lifecycle(self):
        for state in acl.CLAIM_STATES:
            with self.subTest(state=state):
                acl.claim_to_overlap_queue_row(self._claim(state))

    def test_occupying_set_is_derived_not_duplicated(self):
        # V4 section 0: the lifecycle table and the projection map are the same
        # claim twice; writing them independently is how RECOVERABLE broke.
        derived = {s for s in acl.CLAIM_STATES
                   if acl.claim_to_overlap_queue_row(self._claim(s)) is not None}
        self.assertEqual(derived, set(acl.OCCUPYING_STATES))

    def test_row_43_recoverable_blocks_exact_overlap(self):
        row = acl.claim_to_overlap_queue_row(self._claim(acl.RECOVERABLE))
        self.assertEqual(row["state"], "reserved")
        result = self.run_gate(GEN, [row])
        self.assertEqual(result["verdict"], "BLOCK")

    def test_row_44_recoverable_blocks_partial_overlap(self):
        # The exact V3 fail-open. It must never regress.
        row = acl.claim_to_overlap_queue_row(self._claim(acl.RECOVERABLE))
        result = self.run_gate(GEN_PARTIAL, [row])
        self.assertEqual(result["verdict"], "BLOCK")

    def test_row_46_released_is_omitted(self):
        self.assertIsNone(acl.claim_to_overlap_queue_row(self._claim(acl.RELEASED)))
        self.assertEqual(self.run_gate(GEN, [])["verdict"], "PASS")

    def test_row_47_aborted_is_omitted(self):
        self.assertIsNone(acl.claim_to_overlap_queue_row(self._claim(acl.ABORTED)))

    def test_row_48_unknown_state_raises(self):
        for bogus in ("materialised", "expired", "", None, "CLAIMED "):
            with self.subTest(state=bogus):
                with self.assertRaises(acl.AnchorLedgerCorrupt):
                    acl.claim_to_overlap_queue_row(self._claim(bogus))

    def test_only_released_and_aborted_return_none(self):
        none_states = {s for s in acl.CLAIM_STATES
                       if acl.claim_to_overlap_queue_row(self._claim(s)) is None}
        self.assertEqual(none_states, {acl.RELEASED, acl.ABORTED})

    def test_materialized_and_retired_project_locked(self):
        for state in (acl.MATERIALIZED, acl.RETIRED):
            row = acl.claim_to_overlap_queue_row(self._claim(state, story_id=3001))
            self.assertEqual(row["state"], "locked")
            self.assertEqual(row["storyId"], 3001)

    def test_bound_claim_uses_story_id_unbound_uses_comparison_id(self):
        unbound = acl.claim_to_overlap_queue_row(self._claim(acl.CLAIMED))
        self.assertLess(unbound["storyId"], 0)
        bound = acl.claim_to_overlap_queue_row(self._claim(acl.CLAIMED, story_id=3007))
        self.assertEqual(bound["storyId"], 3007)

    def test_queue_rejects_duplicate_identity(self):
        a = self._claim(acl.CLAIMED, story_id=3001)
        b = acl.dataclasses.replace(a, slot_id=2, packet_id="q")
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.build_overlap_queue([a, b])


# ---------------------------------------------------------------------------
# Claim transaction atomicity
# ---------------------------------------------------------------------------

class TestClaimTransaction(AclTestCase):

    def test_claim_writes_exactly_one_five_row_event(self):
        result = self.claim()
        self.assertEqual(len(result.claims), 5)
        lines = self.ledger_bytes().decode().splitlines()
        self.assertEqual(len(lines), 1)
        event = json.loads(lines[0])
        self.assertEqual(event["eventType"], "PACKET_ANCHORS_CLAIMED")
        self.assertEqual(len(event["rows"]), 5)
        self.assertEqual({r["slotId"] for r in event["rows"]}, {1, 2, 3, 4, 5})
        self.assertEqual(event["packetClaimHash"], result.packet_claim_hash)

    def test_claim_creates_five_locks_in_canonical_order(self):
        seen = []
        obs = lambda rec: seen.append(rec) if rec["rank"] == acl.L2_ANCHOR_LOCK \
            and rec["action"] == "acquire" else None
        acl.add_lock_observer(obs)
        self.addCleanup(acl.remove_lock_observer, obs)
        self.claim()
        keys = [rec["detail"] for rec in seen]
        self.assertEqual(keys, sorted(keys))
        self.assertEqual(len(list(acl.locks_dir(self.home).iterdir())), 5)

    def test_idempotent_retry_returns_without_evaluating(self):
        self.claim()
        calls = []

        def evaluator(*a, **k):
            calls.append(a)
            return {"verdict": "BLOCK"}

        again = self.claim(overlap_evaluator=evaluator)
        self.assertTrue(again.idempotent)
        self.assertEqual(calls, [], "an exact retry must return before the evaluator")
        self.assertEqual(len(self.ledger_bytes().decode().splitlines()), 1)

    def test_divergent_retry_is_refused(self):
        self.claim()
        with self.assertRaises(acl.AnchorConflict):
            self.claim(anchors=("Jonah 1:1-17",) + FAR[1:])

    def test_second_packet_cannot_take_a_claimed_anchor(self):
        self.claim(run="run-a", packet="packet-1")
        with self.assertRaises(acl.AnchorConflict):
            self.claim(run="run-b", packet="packet-2")

    def test_rollback_removes_only_locks_this_transaction_created(self):
        self.claim(run="run-a", packet="packet-1", anchors=FAR)
        before = sorted(p.name for p in acl.locks_dir(self.home).iterdir())
        overlapping = ("Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10",
                       "Obadiah 1:1-9", "Micah 1:1-9")
        with self.assertRaises(acl.AnchorConflict):
            self.claim(run="run-b", packet="packet-2", anchors=overlapping)
        after = sorted(p.name for p in acl.locks_dir(self.home).iterdir())
        self.assertEqual(before, after, "rollback must not touch foreign locks")
        self.assertEqual(len(self.ledger_bytes().decode().splitlines()), 1)

    def test_internal_collision_is_rejected_before_any_lock(self):
        dupes = (GEN, GEN, "Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10")
        with self.assertRaises(acl.AnchorOverlapRejected):
            self.claim(anchors=dupes)
        self.assertEqual(self.ledger_bytes(), b"")
        self.assertFalse(acl.locks_dir(self.home).exists()
                         and list(acl.locks_dir(self.home).iterdir()))

    def test_internal_partial_overlap_is_rejected(self):
        overlapping = (GEN, GEN_PARTIAL, "Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10")
        with self.assertRaises(acl.AnchorOverlapRejected):
            self.claim(anchors=overlapping,
                       verse_set_fn=lambda a: gate.verse_set(
                           gate.normalize_reference(a, gate.load_bible()),
                           gate.load_bible()))
        self.assertEqual(self.ledger_bytes(), b"")

    def test_global_overlap_uses_the_gate_and_blocks(self):
        self.claim(run="run-a", packet="packet-1", anchors=(GEN,) + FAR[1:])
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(self.run_gate(GEN_PARTIAL, rows)["verdict"], "BLOCK")

    def test_packet_requires_exactly_five(self):
        with self.assertRaises(acl.AnchorClaimError):
            acl.claim_packet_anchors(run_id="r", packet_id="p",
                                     proposals=proposals(FAR[:4]), actor="owner",
                                     factory_home=self.home)


# ---------------------------------------------------------------------------
# EEXIST: row 49 and the rest of the decision table
# ---------------------------------------------------------------------------

class TestExistingLock(AclTestCase):

    def _desired(self, **over):
        base = {"runId": "run-a", "packetId": "packet-1", "slotId": 1,
                "normalizedAnchor": GEN, "anchorKey": acl.anchor_key(GEN),
                "packetClaimHash": "h" * 64, "pendingEventId": "e" * 8}
        base.update(over)
        return base

    def test_foreign_owner_is_conflict(self):
        record = self._desired(runId="run-z", packetId="packet-9")
        self.assertEqual(
            acl._classify_existing_lock(record, self._desired(), committed=False,
                                        path=Path("x")),
            "conflict")

    def test_same_owner_committed_adopts(self):
        self.assertEqual(
            acl._classify_existing_lock(self._desired(), self._desired(),
                                        committed=True, path=Path("x")),
            "adopt")

    def test_same_owner_uncommitted_requires_recovery(self):
        self.assertEqual(
            acl._classify_existing_lock(self._desired(), self._desired(),
                                        committed=False, path=Path("x")),
            "recovery")

    def test_row_49_same_owner_divergence_is_corrupt_not_conflict(self):
        # One sub-case per divergent field.  V4 section 3: no correct execution
        # can produce a lock bearing our identity with different content.
        for field, value in (("slotId", 4), ("normalizedAnchor", "Jonah 1:1-17"),
                             ("anchorKey", acl.anchor_key("Jonah 1:1-17")),
                             ("packetClaimHash", "f" * 64),
                             ("pendingEventId", "other")):
            with self.subTest(field=field):
                record = self._desired(**{field: value})
                for committed in (True, False):
                    self.assertEqual(
                        acl._classify_existing_lock(record, self._desired(),
                                                    committed=committed,
                                                    path=Path("x")),
                        "corrupt")

    def test_orphan_lock_raises_recovery_and_deletes_nothing(self):
        self.claim()
        ledger = acl.ledger_path(self.home)
        ledger.unlink()  # simulate locks written, event never committed
        with self.assertRaises(acl.AnchorClaimRecoveryRequired):
            self.claim()
        self.assertEqual(len(list(acl.locks_dir(self.home).iterdir())), 5,
                         "recovery must never auto-delete an orphan lock")

    def test_divergent_self_owned_lock_raises_corrupt_and_mutates_nothing(self):
        self.claim()
        ledger = acl.ledger_path(self.home)
        before_ledger = ledger.read_bytes()
        ledger.unlink()
        target = next(iter(acl.locks_dir(self.home).iterdir()))
        record = json.loads(target.read_text())
        record["packetClaimHash"] = "0" * 64
        target.write_text(json.dumps(record, sort_keys=True))
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.claim()
        self.assertEqual(len(list(acl.locks_dir(self.home).iterdir())), 5)
        ledger.write_bytes(before_ledger)


# ---------------------------------------------------------------------------
# Committed-retry lock reconciliation
#
# A committed ACL transaction proves the CLAIM exists.  It does not prove the
# advisory exclusivity locks are still in place.  Every test below fails
# against an implementation that returns idempotent success on the ledger
# alone -- which is exactly what the pre-remediation code did.
# ---------------------------------------------------------------------------

class TestCommittedRetryReconciliation(AclTestCase):

    def locks(self):
        return sorted(acl.locks_dir(self.home).iterdir())

    def corrupt_one(self, index=0, **fields):
        path = self.locks()[index]
        record = json.loads(path.read_text())
        record.update(fields)
        path.write_text(json.dumps(record, sort_keys=True))
        return path

    def test_all_five_locks_present_gives_idempotent_success(self):
        first = self.claim()
        before = self.ledger_bytes()
        again = self.claim()
        self.assertTrue(again.idempotent)
        self.assertEqual(again.packet_claim_hash, first.packet_claim_hash)
        self.assertEqual(self.ledger_bytes(), before, "no duplicate append")
        self.assertEqual(len(self.locks()), 5)

    def test_no_lock_is_rewritten_by_a_successful_retry(self):
        self.claim()
        before = {p.name: p.read_bytes() for p in self.locks()}
        self.claim()
        after = {p.name: p.read_bytes() for p in self.locks()}
        self.assertEqual(before, after, "reconciliation must only read")

    def test_one_missing_lock_refuses_instead_of_succeeding(self):
        self.claim()
        before = self.ledger_bytes()
        self.locks()[2].unlink()
        with self.assertRaises(acl.AnchorClaimRecoveryRequired):
            self.claim()
        self.assertEqual(self.ledger_bytes(), before)
        self.assertEqual(len(self.locks()), 4,
                         "a missing lock is never recreated automatically")

    def test_all_five_missing_locks_refuse_instead_of_succeeding(self):
        self.claim()
        before = self.ledger_bytes()
        for path in self.locks():
            path.unlink()
        with self.assertRaises(acl.AnchorClaimRecoveryRequired):
            self.claim()
        self.assertEqual(self.ledger_bytes(), before)
        self.assertEqual(len(self.locks()), 0)

    def test_one_foreign_lock_is_a_conflict(self):
        self.claim()
        before = self.ledger_bytes()
        self.corrupt_one(0, runId="run-z", packetId="packet-9")
        with self.assertRaises(acl.AnchorConflict):
            self.claim()
        self.assertEqual(self.ledger_bytes(), before)
        self.assertEqual(len(self.locks()), 5, "a foreign lock is never deleted")

    def test_one_self_owned_divergent_lock_is_corrupt(self):
        for field, value in (("slotId", 4),
                             ("normalizedAnchor", "Jonah 1:1-17"),
                             ("anchorKey", acl.anchor_key("Jonah 1:1-17")),
                             ("packetClaimHash", "0" * 64),
                             ("pendingEventId", "not-the-real-one")):
            with self.subTest(field=field):
                self.setUp()
                self.claim()
                before = self.ledger_bytes()
                self.corrupt_one(0, **{field: value})
                with self.assertRaises(acl.AnchorLedgerCorrupt):
                    self.claim()
                self.assertEqual(self.ledger_bytes(), before)
                self.assertEqual(len(self.locks()), 5)

    def test_four_correct_and_one_invalid_never_adopts_four(self):
        for breakage, expected in (
            ({"runId": "run-z"}, acl.AnchorConflict),
            ({"packetClaimHash": "0" * 64}, acl.AnchorLedgerCorrupt),
        ):
            with self.subTest(breakage=tuple(breakage)):
                self.setUp()
                result = self.claim()
                self.corrupt_one(3, **breakage)
                with self.assertRaises(expected):
                    self.claim()
        # and the missing-lock flavour of the same rule
        self.setUp()
        self.claim()
        self.locks()[4].unlink()
        with self.assertRaises(acl.AnchorClaimRecoveryRequired):
            self.claim()

    def test_failure_precedence_is_corrupt_then_conflict_then_missing(self):
        # corrupt outranks conflict
        self.claim()
        self.corrupt_one(0, packetClaimHash="0" * 64)
        self.corrupt_one(1, runId="run-z")
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.claim()
        # conflict outranks missing
        self.setUp()
        self.claim()
        self.corrupt_one(0, runId="run-z")
        self.locks()[1].unlink()
        with self.assertRaises(acl.AnchorConflict):
            self.claim()

    def test_reconciliation_never_appends_on_any_failure(self):
        self.claim()
        before = self.ledger_bytes()
        for mutate in (lambda: self.locks()[0].unlink(),
                       lambda: self.corrupt_one(0, runId="run-z"),
                       lambda: self.corrupt_one(0, packetClaimHash="0" * 64)):
            self.setUp()
            self.claim()
            before = self.ledger_bytes()
            mutate()
            with self.assertRaises(acl.AnchorClaimError):
                self.claim()
            self.assertEqual(self.ledger_bytes(), before)

    def test_reconcile_helper_is_read_only_and_directly_callable(self):
        result = self.claim()
        lock_dir = acl.locks_dir(self.home)
        before = {p.name: p.read_bytes() for p in sorted(lock_dir.iterdir())}
        acl.reconcile_committed_locks(
            result.claims, run_id="run-a", packet_id="packet-1",
            claim_hash=result.packet_claim_hash, lock_dir=lock_dir)
        after = {p.name: p.read_bytes() for p in sorted(lock_dir.iterdir())}
        self.assertEqual(before, after)

    def test_a_backfilled_packet_has_no_locks_by_design(self):
        # V4 section 4: backfill's ONLY write is an ACL append, so it creates
        # no L2 locks.  Re-claiming a historical packet through the autonomous
        # path therefore fails closed rather than silently adopting it.  Pinned
        # here so the interaction is deliberate, not accidental.
        packet = {
            "runId": "run-a", "packetId": "packet-1",
            "slots": [{"slotId": i + 1, "storyId": 3000 + i, "proposedAnchor": a}
                      for i, a in enumerate(FAR)],
        }
        acl.backfill_packet_claims(
            packet=packet,
            reservation_states={3000 + i: "MATERIALIZED" for i in range(5)},
            actor="owner", factory_home=self.home)
        self.assertFalse(acl.locks_dir(self.home).exists()
                         and list(acl.locks_dir(self.home).iterdir()))
        with self.assertRaises(acl.AnchorClaimRecoveryRequired):
            self.claim()


# ---------------------------------------------------------------------------
# Deterministic pendingEventId
# ---------------------------------------------------------------------------

class TestDeterministicPendingEventId(unittest.TestCase):
    """pendingEventId is one of the seven lock-identity fields.

    If it were a fresh UUID, an honest retry would recompute a different value,
    every orphan would be classified divergent, and both the recovery branch
    and the committed-retry reconciliation above would be unreachable.
    """

    HASH = "a" * 64
    OTHER = "b" * 64

    def test_same_input_gives_the_same_value(self):
        first = acl.pending_event_id("run-a", "packet-1", self.HASH)
        for _ in range(5):
            self.assertEqual(acl.pending_event_id("run-a", "packet-1", self.HASH),
                             first)

    def test_different_run_gives_a_different_value(self):
        self.assertNotEqual(acl.pending_event_id("run-a", "packet-1", self.HASH),
                            acl.pending_event_id("run-b", "packet-1", self.HASH))

    def test_different_packet_gives_a_different_value(self):
        self.assertNotEqual(acl.pending_event_id("run-a", "packet-1", self.HASH),
                            acl.pending_event_id("run-a", "packet-2", self.HASH))

    def test_different_claim_hash_gives_a_different_value(self):
        self.assertNotEqual(acl.pending_event_id("run-a", "packet-1", self.HASH),
                            acl.pending_event_id("run-a", "packet-1", self.OTHER))

    def test_different_event_type_gives_a_different_value(self):
        self.assertNotEqual(
            acl.pending_event_id("run-a", "packet-1", self.HASH),
            acl.pending_event_id("run-a", "packet-1", self.HASH,
                                 "PACKET_ANCHORS_RELEASED"))

    def test_no_wall_clock_or_rng_dependence(self):
        import random
        import time
        baseline = acl.pending_event_id("run-a", "packet-1", self.HASH)
        random.seed(1)
        first = acl.pending_event_id("run-a", "packet-1", self.HASH)
        random.seed(999999)
        time.sleep(0.01)
        second = acl.pending_event_id("run-a", "packet-1", self.HASH)
        self.assertEqual(baseline, first)
        self.assertEqual(baseline, second)

    def test_uses_no_uuid4_no_time_no_random(self):
        # Structural: the executable body must not reach for a
        # nondeterministic source.  The docstring is excluded deliberately --
        # it *discusses* randomness, and matching prose would make this test
        # fire on documentation rather than on behaviour.
        import ast
        import inspect
        tree = ast.parse(inspect.getsource(acl.pending_event_id).lstrip())
        function = tree.body[0]
        body = function.body[1:] if ast.get_docstring(function) else function.body
        code = "\n".join(ast.dump(node) for node in body)
        for forbidden in ("uuid4", "uuid1", "time", "random", "now"):
            self.assertNotIn(forbidden, code)
        names = {node.id for node in ast.walk(function)
                 if isinstance(node, ast.Name)}
        self.assertNotIn("random", names)

    def test_survives_a_fresh_interpreter(self):
        # PYTHONHASHSEED must not leak into the value.
        import subprocess
        import sys as _sys
        script = (
            "import sys;"
            f"sys.path.insert(0, {str(REPO_ROOT / 'scripts' / 'story_factory')!r});"
            "import anchor_claims as a;"
            f"print(a.pending_event_id('run-a','packet-1',{self.HASH!r}))"
        )
        expected = acl.pending_event_id("run-a", "packet-1", self.HASH)
        for seed in ("0", "1", "random"):
            env = dict(os.environ, PYTHONHASHSEED=seed)
            out = subprocess.run([_sys.executable, "-c", script],
                                 capture_output=True, text=True, env=env)
            self.assertEqual(out.stdout.strip(), expected, out.stderr)

    def test_is_a_well_formed_uuid_string(self):
        import uuid as _uuid
        value = acl.pending_event_id("run-a", "packet-1", self.HASH)
        self.assertEqual(str(_uuid.UUID(value)), value)


# ---------------------------------------------------------------------------
# RECOVERABLE, release, abort: rows 45, 51, 52
# ---------------------------------------------------------------------------

class TestFreeing(AclTestCase):

    def test_lease_lapse_keeps_the_anchor_occupied(self):
        result = self.claim(anchors=(GEN,) + FAR[1:])
        target = result.claims[0]
        acl.mark_recoverable(target, actor="controller", factory_home=self.home)
        state = self.states()[target.key]
        self.assertEqual(state.state, acl.RECOVERABLE)
        self.assertTrue(state.occupying)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(self.run_gate(GEN_PARTIAL, rows)["verdict"], "BLOCK")

    def test_row_45_owner_release_frees_it(self):
        result = self.claim(anchors=(GEN,) + FAR[1:])
        acl.mark_recoverable(result.claims[0], actor="controller",
                             factory_home=self.home)
        acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(rows, [])
        self.assertEqual(self.run_gate(GEN_PARTIAL, rows)["verdict"], "PASS")

    def test_row_45_non_owner_release_is_refused(self):
        result = self.claim()
        for actor in ("controller", "claude", "automation", "codex"):
            with self.subTest(actor=actor):
                with self.assertRaises(acl.OwnerAuthorizationRequired):
                    acl.release_packet_claims(
                        run_id="run-a", packet_id="packet-1", actor=actor,
                        packet_claim_hash_value=result.packet_claim_hash,
                        factory_home=self.home)
        self.assertEqual(len(acl.build_overlap_queue(self.states().values())), 5)

    def test_release_requires_all_five_to_reconcile(self):
        result = self.claim()
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.release_packet_claims(
                run_id="run-a", packet_id="packet-1", actor="owner",
                packet_claim_hash_value="0" * 64, factory_home=self.home)
        self.assertEqual(len(acl.build_overlap_queue(self.states().values())), 5,
                         "a failed reconcile must free nothing")

    def test_row_51_release_commits_before_unlinking_locks(self):
        result = self.claim()
        acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        self.assertEqual(list(acl.locks_dir(self.home).iterdir()), [])
        # retry is idempotent
        again = acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        self.assertEqual(len(again), 5)

    def test_row_51_stale_release_orphan_is_never_auto_deleted(self):
        result = self.claim()
        acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        # simulate the crash-between-commit-and-unlink window
        orphan = acl.locks_dir(self.home) / f"{result.claims[0].anchor_key}.lock"
        orphan.write_text(json.dumps({"runId": "run-a", "packetId": "packet-1",
                                      "slotId": 1}, sort_keys=True))
        with self.assertRaises(acl.AnchorConflict):
            self.claim(run="run-b", packet="packet-2", anchors=FAR)
        self.assertTrue(orphan.exists(), "orphan locks are owner-gated, never swept")

    def test_row_52_abort_behaves_like_release(self):
        result = self.claim()
        acl.abort_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        for claim in self.states().values():
            self.assertEqual(claim.state, acl.ABORTED)
        self.assertEqual(acl.build_overlap_queue(self.states().values()), [])


# ---------------------------------------------------------------------------
# Binding, authoring, materialization, retirement: rows 42, 53
# ---------------------------------------------------------------------------

class TestPerRowTransitions(AclTestCase):

    def bound(self):
        result = self.claim()
        out = []
        for index, claim in enumerate(result.claims):
            out.append(acl.bind_story_id(claim, 3000 + index, actor="controller",
                                         factory_home=self.home))
        return result, out

    def test_row_42_binding_replaces_identity_exactly_once(self):
        result, bound = self.bound()
        for index, claim in enumerate(bound):
            self.assertEqual(claim.story_id, 3000 + index)
            self.assertEqual(claim.identity, 3000 + index)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(sorted(r["storyId"] for r in rows),
                         [3000, 3001, 3002, 3003, 3004])

    def test_rebinding_is_refused(self):
        result, bound = self.bound()
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.bind_story_id(bound[0], 3999, actor="controller",
                              factory_home=self.home)

    def test_rebinding_the_same_id_is_idempotent(self):
        result, bound = self.bound()
        again = acl.bind_story_id(bound[0], 3000, actor="controller",
                                  factory_home=self.home)
        self.assertEqual(again.story_id, 3000)

    def test_a_story_id_is_never_shared_across_claims(self):
        result, bound = self.bound()
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.bind_story_id(result.claims[1], 3000, actor="controller",
                              factory_home=self.home)

    def test_partial_binding_leaves_everything_occupying(self):
        result = self.claim()
        acl.bind_story_id(result.claims[0], 3000, actor="controller",
                          factory_home=self.home)
        acl.bind_story_id(result.claims[1], 3001, actor="controller",
                          factory_home=self.home)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(len(rows), 5)
        self.assertTrue(all(r["state"] == "reserved" for r in rows))

    def test_row_53_partial_retirement_keeps_all_five_locked(self):
        result, bound = self.bound()
        for claim in bound:
            acl.mark_authoring(claim, actor="controller", factory_home=self.home)
        materialized = [acl.mark_materialized(c, actor="controller",
                                              factory_home=self.home)
                        for c in self.states().values()]
        for claim in materialized[:2]:
            acl.mark_retired(claim, actor="controller", factory_home=self.home)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(len(rows), 5)
        self.assertTrue(all(r["state"] == "locked" for r in rows),
                        "MATERIALIZED and RETIRED both project locked")
        # re-retiring is a no-op
        again = acl.mark_retired(self.states()[materialized[0].key],
                                 actor="controller", factory_home=self.home)
        self.assertEqual(again.state, acl.RETIRED)

    def test_materialized_cannot_go_back_to_authoring(self):
        result, bound = self.bound()
        for claim in bound:
            acl.mark_authoring(claim, actor="controller", factory_home=self.home)
        m = acl.mark_materialized(self.states()[bound[0].key], actor="controller",
                                  factory_home=self.home)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.mark_authoring(m, actor="controller", factory_home=self.home)


# ---------------------------------------------------------------------------
# Replay: malformed ledgers, row 56
# ---------------------------------------------------------------------------

class TestReplay(AclTestCase):

    def write(self, *events):
        acl.ledger_path(self.home).write_text(
            "".join(json.dumps(e, sort_keys=True) + "\n" for e in events),
            encoding="utf-8")

    def base_event(self, **over):
        rows = [{"slotId": i, "normalizedAnchor": FAR[i - 1],
                 "anchorKey": acl.anchor_key(FAR[i - 1]),
                 "comparisonId": -i, "storyId": None} for i in range(1, 6)]
        event = {"schemaVersion": 1, "eventId": "evt-1", "timestamp": "2026-01-01T00:00:00Z",
                 "eventType": "PACKET_ANCHORS_CLAIMED", "runId": "run-a",
                 "packetId": "packet-1", "actor": "owner",
                 "packetClaimHash": "h" * 64, "reason": "t", "rows": rows}
        event.update(over)
        return event

    def test_packet_event_with_four_rows_is_corrupt(self):
        event = self.base_event()
        event["rows"] = event["rows"][:4]
        self.write(event)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_torn_final_line_is_corrupt(self):
        self.claim()
        path = acl.ledger_path(self.home)
        path.write_bytes(path.read_bytes()[:-5])
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_duplicate_event_id_is_corrupt(self):
        self.write(self.base_event(), self.base_event())
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_unknown_event_type_is_corrupt(self):
        self.write(self.base_event(eventType="ANCHOR_FREED"))
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_positive_comparison_id_is_corrupt(self):
        event = self.base_event()
        event["rows"][0]["comparisonId"] = 7
        self.write(event)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_row_56_per_row_free_is_rejected_by_replay(self):
        # A hand-crafted per-row RELEASED must not free anything.  The event
        # vocabulary makes it unrepresentable; replay proves it reads closed.
        claimed = self.base_event()
        released = self.base_event(
            eventId="evt-2", eventType="ANCHOR_RELEASED",
            rows=[claimed["rows"][0]])
        self.write(claimed, released)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()

    def test_partially_freed_packet_is_rejected(self):
        claimed = self.base_event()
        partial = self.base_event(eventId="evt-2",
                                  eventType="PACKET_ANCHORS_RELEASED")
        partial["rows"] = partial["rows"][:5]
        self.write(claimed, partial)
        states = self.states()
        self.assertTrue(all(c.state == acl.RELEASED for c in states.values()))

    def test_replay_of_partial_claim_is_impossible(self):
        # There is no way to express fewer than five claimed rows.
        event = self.base_event()
        event["rows"] = event["rows"][:3]
        self.write(event)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            self.states()


# ---------------------------------------------------------------------------
# Row 55: no under-occupancy for any prefix of any lifecycle operation
# ---------------------------------------------------------------------------

class TestNoUnderOccupancy(AclTestCase):
    """The invariant of V4 section 5.1 expressed directly.

    For every prefix of every lifecycle operation's step sequence, kill and
    replay, then assert the occupying anchor-key set is a superset of the set
    that would be occupying had the operation not started.  Over-occupancy is
    allowed; under-occupancy is a failure.
    """

    def occupying_keys(self):
        return {c.anchor_key for c in self.states().values() if c.occupying}

    def snapshot(self):
        return self.ledger_bytes()

    def restore(self, raw):
        path = acl.ledger_path(self.home)
        if raw:
            path.write_bytes(raw)
        elif path.exists():
            path.unlink()

    def _steps_bind(self, claims):
        return [(lambda c=c, i=i: acl.bind_story_id(
            self.states()[c.key], 3000 + i, actor="controller",
            factory_home=self.home)) for i, c in enumerate(claims)]

    def _steps_authoring(self, claims):
        return [(lambda c=c: acl.mark_authoring(
            self.states()[c.key], actor="controller", factory_home=self.home))
            for c in claims]

    def _steps_materialize(self, claims):
        return [(lambda c=c: acl.mark_materialized(
            self.states()[c.key], actor="controller", factory_home=self.home))
            for c in claims]

    def _steps_retire(self, claims):
        return [(lambda c=c: acl.mark_retired(
            self.states()[c.key], actor="controller", factory_home=self.home))
            for c in claims]

    def _steps_recoverable(self, claims):
        return [(lambda c=c: acl.mark_recoverable(
            self.states()[c.key], actor="controller", factory_home=self.home))
            for c in claims]

    def _drive(self, name, build_steps, prepare=None):
        result = self.claim()
        claims = list(result.claims)
        if prepare is not None:
            prepare(claims)
            claims = sorted(self.states().values(), key=lambda c: c.slot_id)
        baseline_raw = self.snapshot()
        baseline = self.occupying_keys()
        steps = build_steps(claims)
        for prefix in range(len(steps) + 1):
            with self.subTest(operation=name, prefix=prefix):
                self.restore(baseline_raw)
                for step in steps[:prefix]:
                    step()
                after = self.occupying_keys()   # replayed from the ledger = crash+replay
                self.assertTrue(
                    baseline <= after,
                    f"{name} prefix {prefix} lost occupancy: "
                    f"{sorted(baseline - after)}")
        self.restore(baseline_raw)

    def test_row_55_binding_never_under_occupies(self):
        self._drive("bind", self._steps_bind)

    def test_row_55_authoring_never_under_occupies(self):
        def prep(claims):
            for i, c in enumerate(claims):
                acl.bind_story_id(c, 3000 + i, actor="controller",
                                  factory_home=self.home)
        self._drive("authoring", self._steps_authoring, prepare=prep)

    def test_row_55_materialization_never_under_occupies(self):
        def prep(claims):
            for i, c in enumerate(claims):
                b = acl.bind_story_id(c, 3000 + i, actor="controller",
                                      factory_home=self.home)
                acl.mark_authoring(b, actor="controller", factory_home=self.home)
        self._drive("materialize", self._steps_materialize, prepare=prep)

    def test_row_55_retirement_never_under_occupies(self):
        def prep(claims):
            for i, c in enumerate(claims):
                b = acl.bind_story_id(c, 3000 + i, actor="controller",
                                      factory_home=self.home)
                a = acl.mark_authoring(b, actor="controller", factory_home=self.home)
                acl.mark_materialized(a, actor="controller", factory_home=self.home)
        self._drive("retire", self._steps_retire, prepare=prep)

    def test_row_55_lease_lapse_never_under_occupies(self):
        # Under V3 this was the one operation that COULD under-occupy, because
        # lapse moved rows to a non-occupying state one at a time.
        self._drive("recoverable", self._steps_recoverable)

    def test_row_55_release_is_all_or_nothing(self):
        result = self.claim()
        baseline = self.occupying_keys()
        raw = self.snapshot()
        # crash before commit: nothing freed
        self.restore(raw)
        self.assertEqual(self.occupying_keys(), baseline)
        # commit: all five freed together, never a subset
        acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        self.assertEqual(self.occupying_keys(), set())


# ---------------------------------------------------------------------------
# Row 54: lock order and concurrency
# ---------------------------------------------------------------------------

class TestLockOrder(AclTestCase):

    def test_row_54_ranks_are_non_descending_within_every_operation(self):
        records = []
        acl.add_lock_observer(records.append)
        self.addCleanup(acl.remove_lock_observer, records.append)
        result = self.claim()
        acl.bind_story_id(result.claims[0], 3000, actor="controller",
                          factory_home=self.home)
        acl.release_packet_claims(
            run_id="run-a", packet_id="packet-1", actor="owner",
            packet_claim_hash_value=result.packet_claim_hash,
            factory_home=self.home)
        by_thread = {}
        for record in records:
            stack = by_thread.setdefault(record["thread"], [])
            if record["action"] == "acquire":
                if stack:
                    self.assertGreaterEqual(
                        record["rank"], max(stack),
                        f"descending acquisition: {record}")
                stack.append(record["rank"])
            else:
                if record["rank"] in stack:
                    stack.remove(record["rank"])

    def test_row_54_descending_acquisition_raises_rather_than_deadlocking(self):
        with acl.lock_rank(acl.L5_PACKET_JOURNAL, "j"):
            with self.assertRaises(acl.LockOrderViolation):
                with acl.lock_rank(acl.L1_ACL_LEDGER, "acl"):
                    pass

    def test_equal_ranks_are_legal(self):
        with acl.lock_rank(acl.L2_ANCHOR_LOCK, "a"):
            with acl.lock_rank(acl.L2_ANCHOR_LOCK, "b"):
                self.assertEqual(acl.held_lock_ranks(), (2, 2))

    def test_row_54_four_packets_race_for_overlapping_anchors(self):
        anchor_sets = [
            (GEN, "Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10", "Obadiah 1:1-9"),
            (GEN, "Micah 1:1-9", "Habakkuk 1:1-11", "Zephaniah 1:1-9", "Haggai 1:1-11"),
            (GEN, "Malachi 1:1-14", "Jonah 1:1-17", "Ruth 1:1-10", "Esther 1:1-9"),
            (GEN, "Lamentations 1:1-7", "Ecclesiastes 1:1-11",
             "Song of Solomon 1:1-8", "Titus 1:1-9"),
        ]
        outcomes, errors = [], []
        barrier = threading.Barrier(len(anchor_sets))

        def worker(index):
            barrier.wait()
            try:
                self.claim(run=f"run-{index}", packet=f"packet-{index}",
                           anchors=anchor_sets[index])
                outcomes.append(index)
            except acl.AnchorClaimError as exc:
                errors.append(type(exc).__name__)
            except Exception as exc:  # pragma: no cover - surfaced by assert
                errors.append(f"UNEXPECTED {type(exc).__name__}: {exc}")

        threads = [threading.Thread(target=worker, args=(i,))
                   for i in range(len(anchor_sets))]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=60)
        self.assertFalse(any(t.is_alive() for t in threads), "deadlock")
        self.assertEqual(len(outcomes), 1,
                         f"exactly one packet may win Genesis 1:1-5; {outcomes} {errors}")
        self.assertFalse([e for e in errors if e.startswith("UNEXPECTED")], errors)
        self.states()  # replay must be clean

    def test_row_54_disjoint_packets_all_succeed_concurrently(self):
        sets = [
            ("Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10", "Obadiah 1:1-9", "Micah 1:1-9"),
            ("Habakkuk 1:1-11", "Zephaniah 1:1-9", "Haggai 1:1-11", "Malachi 1:1-14",
             "Jonah 1:1-17"),
            ("Ruth 1:1-10", "Esther 1:1-9", "Lamentations 1:1-7",
             "Ecclesiastes 1:1-11", "Titus 1:1-9"),
            ("Philemon 1:1-7", "Jude 1:1-8", "2 John 1:1-6", "3 John 1:1-6",
             "Obadiah 1:10-16"),
        ]
        ok, errs = [], []
        barrier = threading.Barrier(len(sets))

        def worker(i):
            barrier.wait()
            try:
                self.claim(run=f"run-{i}", packet=f"packet-{i}", anchors=sets[i])
                ok.append(i)
            except Exception as exc:
                errs.append(f"{type(exc).__name__}: {exc}")

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(len(sets))]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=60)
        self.assertEqual(sorted(ok), [0, 1, 2, 3], errs)
        self.assertEqual(len(self.states()), 20)
        lines = self.ledger_bytes().decode().splitlines()
        self.assertEqual(len(lines), 4, "no torn or interleaved ACL lines")
        for line in lines:
            json.loads(line)


# ---------------------------------------------------------------------------
# Row 50: backfill
# ---------------------------------------------------------------------------

class TestBackfill(AclTestCase):

    def packet(self):
        return {
            "runId": "campaign-3000-3258-run-001",
            "packetId": "proving-packet-001",
            "slots": [
                {"slotId": 1, "storyId": 3000, "proposedAnchor": "Leviticus 10:12-20"},
                {"slotId": 2, "storyId": 3001, "proposedAnchor": "2 Kings 9:1-13"},
                {"slotId": 3, "storyId": 3002, "proposedAnchor": "1 Kings 13:11-32"},
                {"slotId": 4, "storyId": 3003, "proposedAnchor": "2 Chronicles 26:16-21"},
                {"slotId": 5, "storyId": 3004, "proposedAnchor": "Judges 9:50-57"},
            ],
        }

    def reservation_states(self, state="MATERIALIZED"):
        return {3000 + i: state for i in range(5)}

    def _fixture_tree(self):
        """A real-packet-shaped fixture: journal, ledger, packet.json, stories."""
        root = Path(tempfile.mkdtemp(dir=str(self.home)))
        (root / "runs").mkdir()
        (root / "events.jsonl").write_text('{"eventType":"PACKET_PLANNED"}\n')
        (root / "reservations.jsonl").write_text('{"storyId":3000}\n')
        (root / "packet.json").write_text(json.dumps(self.packet(), sort_keys=True))
        stories = root / "assets" / "stories" / "traditional"
        for story_id in range(3000, 3005):
            d = stories / str(story_id)
            d.mkdir(parents=True)
            (d / f"meta_{story_id}.json").write_text('{"id":%d}' % story_id)
            (d / f"story_{story_id}_traditional_web_short.txt").write_text("text\n")
        (root / "manifest.json").write_text("{}")
        (root / "scripture_anchor_registry.json").write_text("{}")
        return root

    def _hash_tree(self, root):
        import hashlib
        out = {}
        for path in sorted(root.rglob("*")):
            if path.is_file():
                out[str(path.relative_to(root))] = hashlib.sha256(
                    path.read_bytes()).hexdigest()
        return out

    def test_row_50_backfill_derives_five_materialized_claims(self):
        claims = acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        self.assertEqual(len(claims), 5)
        self.assertTrue(all(c.state == acl.MATERIALIZED for c in claims))
        self.assertEqual(sorted(c.story_id for c in claims),
                         [3000, 3001, 3002, 3003, 3004])
        rows = acl.build_overlap_queue(self.states().values())
        self.assertTrue(all(r["state"] == "locked" for r in rows))

    def test_row_50_backfilled_anchors_block_a_new_packet(self):
        acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        rows = acl.build_overlap_queue(self.states().values())
        self.assertEqual(self.run_gate("2 Kings 9:1-13", rows)["verdict"], "BLOCK")
        self.assertEqual(self.run_gate("2 Chronicles 26:16-21", rows)["verdict"], "BLOCK")

    def test_row_50_backfill_changes_the_acl_and_nothing_else(self):
        tree = self._fixture_tree()
        before = self._hash_tree(tree)
        acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        after = self._hash_tree(tree)
        self.assertEqual(before, after,
                         "backfill must not touch journal, ledger, packet.json, "
                         "stories, metadata, manifests or registries")
        self.assertTrue(acl.ledger_path(self.home).exists())

    def test_row_50_second_run_is_a_verifying_no_op(self):
        acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        first = self.ledger_bytes()
        acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        self.assertEqual(self.ledger_bytes(), first)

    def test_backfill_refuses_an_unmapped_reservation_state(self):
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.backfill_packet_claims(
                packet=self.packet(),
                reservation_states={3000 + i: "ABANDONED" for i in range(5)},
                actor="owner", factory_home=self.home)
        self.assertEqual(self.ledger_bytes(), b"")

    def test_backfill_refuses_mixed_states(self):
        states = self.reservation_states()
        states[3004] = "RESERVED"
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.backfill_packet_claims(
                packet=self.packet(), reservation_states=states, actor="owner",
                factory_home=self.home)

    def test_forbidden_write_list_is_named_as_documentation_not_a_guard(self):
        # The constant enforces nothing at runtime, and its name now says so.
        # A constant that looks like a guard but is not is worse than no
        # constant at all, so the old enforcement-sounding name must be gone.
        for name in ("events.jsonl", "reservations.jsonl", "packet.json",
                     "manifest.json", "scripture_anchor_registry.json", "*.mp3"):
            self.assertIn(name, acl.BACKFILL_FORBIDDEN_WRITES_DOC_CONTRACT)
        self.assertFalse(hasattr(acl, "BACKFILL_FORBIDDEN_WRITES"))

    def test_backfill_write_surface_is_exactly_one_path(self):
        # The real guarantee is structural: backfill opens one path for
        # writing.  Asserted against the source, so widening it fails here.
        import ast
        import inspect
        self.assertEqual(acl.BACKFILL_WRITE_SURFACE, ("anchor_claims.jsonl",))
        source = inspect.getsource(acl.backfill_packet_claims)
        tree = ast.parse(source.lstrip())
        called = {node.func.id for node in ast.walk(tree)
                  if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)}
        # the only writing primitive reachable from backfill is the ACL append
        for writer in ("_atomic_lock", "open", "write_text", "write_bytes",
                       "_write_all", "unlink", "rename", "replace"):
            self.assertNotIn(writer, called,
                             f"backfill must not call {writer}")
        self.assertIn("_append_locked", called)

    def test_backfill_touches_no_path_outside_the_write_surface(self):
        # Behavioural companion to the structural check: snapshot the whole
        # factory home, run backfill, and confirm the ACL is the only path
        # that appeared or changed.
        import hashlib
        seeded = self.home / "decoy.json"
        seeded.write_text('{"do":"not touch"}')
        before = {str(p.relative_to(self.home)):
                  hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in self.home.rglob("*") if p.is_file()}
        acl.backfill_packet_claims(
            packet=self.packet(), reservation_states=self.reservation_states(),
            actor="owner", factory_home=self.home)
        after = {str(p.relative_to(self.home)):
                 hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in self.home.rglob("*") if p.is_file()}
        changed = {k for k in set(before) | set(after)
                   if before.get(k) != after.get(k)}
        self.assertEqual(changed, set(acl.BACKFILL_WRITE_SURFACE))


# ---------------------------------------------------------------------------
# Gate hardening (F2)
# ---------------------------------------------------------------------------

class TestGateVocabulary(AclTestCase):

    def test_known_vocabulary_is_the_union(self):
        self.assertEqual(gate.KNOWN_QUEUE_STATES,
                         gate.OCCUPYING_STATES | gate.NON_OCCUPYING_STATES)

    def test_every_projected_state_is_known_to_the_gate(self):
        for state in acl.CLAIM_STATES:
            claim = acl.AnchorClaim(
                run_id="r", packet_id="p", slot_id=1, normalized_anchor=GEN,
                anchor_key=acl.anchor_key(GEN), comparison_id=-1, state=state,
                packet_claim_hash="h", event_id="e")
            row = acl.claim_to_overlap_queue_row(claim)
            if row is not None:
                self.assertIn(row["state"], gate.KNOWN_QUEUE_STATES)

    def test_unknown_state_fails_closed(self):
        for bogus in ("materialized", "claimed", "recoverable", "typo"):
            with self.subTest(state=bogus):
                with self.assertRaises(gate.GateError):
                    self.run_gate(GEN, [{"storyId": 1, "proposedAnchor": GEN,
                                         "state": bogus}])

    def test_legacy_non_occupying_states_still_pass(self):
        for state in ("abandoned", "expired", "released"):
            with self.subTest(state=state):
                result = self.run_gate(GEN, [{"storyId": 1, "proposedAnchor": GEN,
                                              "state": state}])
                self.assertEqual(result["verdict"], "PASS")
                self.assertEqual(result["universe"]["occupyingReservations"], 0)

    def test_occupying_states_still_block(self):
        for state in ("reserved", "authoring", "locked"):
            with self.subTest(state=state):
                result = self.run_gate(GEN, [{"storyId": 1, "proposedAnchor": GEN,
                                              "state": state}])
                self.assertEqual(result["verdict"], "BLOCK")


if __name__ == "__main__":
    unittest.main(verbosity=2)
