#!/usr/bin/env python3
"""Adversarial tests for race-safe autonomous story ID reservations.

All authoritative state is directed to temporary factory homes.  Concurrency
tests use real spawned processes, a real temporary Git repository, and the
module's production ``git worktree list --porcelain`` discovery path.

Run:
    PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
        scripts.tests.test_story_id_reservations -v
"""

from __future__ import annotations

import datetime as dt
import json
import multiprocessing
import os
import pathlib
import queue
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
STORY_FACTORY = REPO_ROOT / "scripts" / "story_factory"
sys.path.insert(0, str(STORY_FACTORY))

import story_id_reservations as reservations  # noqa: E402


def _git_init(repo: pathlib.Path) -> None:
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.name=Reservation Test",
            "-c",
            "user.email=reservation@example.invalid",
            "commit",
            "--allow-empty",
            "-q",
            "-m",
            "initial",
        ],
        check=True,
    )


def _write_manifest(repo: pathlib.Path, story_ids=(), *, kid=False) -> None:
    entries = []
    lane = "kids" if kid else "traditional"
    for story_id in story_ids:
        story_identity = (
            f"kidstory_fixture_{story_id}" if kid else f"story_{story_id}_fixture_short"
        )
        entries.append(
            {
                "storyId": story_identity,
                "audioFilePath": f"{lane}/{story_id}/audio_{story_id}_short.mp3",
                "textFilePath": f"{lane}/{story_id}/story_{story_id}_short.txt",
            }
        )
    path = repo / "assets" / "stories" / "manifest.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"version": 6, "parables": entries}), encoding="utf-8")


def _prepare_repo(repo: pathlib.Path) -> None:
    repo.mkdir(parents=True, exist_ok=True)
    _git_init(repo)
    (repo / "assets" / "stories" / "traditional").mkdir(parents=True)
    (repo / "assets" / "stories" / "kids").mkdir(parents=True)
    _write_manifest(repo)


def _process_reserve_worker(
    repo: str,
    factory_home: str,
    start_event,
    result_queue,
    packet_count: int,
    worker_number: int,
) -> None:
    try:
        if not start_event.wait(20):
            raise RuntimeError("start barrier timed out")
        common = {
            "run_id": f"run-{worker_number}",
            "packet_id": f"packet-{worker_number}",
            "actor": f"worker-{worker_number}",
            "worktree": repo,
            "repo_root": repo,
            "factory_home": factory_home,
            "lease_seconds": 300,
        }
        if packet_count == 1:
            claimed = [reservations.reserve_id(**common)]
        else:
            claimed = list(reservations.reserve_packet(count=packet_count, **common))
        result_queue.put(("ok", [item.story_id for item in claimed]))
    except BaseException as exc:  # Propagate child evidence to the parent test.
        result_queue.put(("error", f"{type(exc).__name__}: {exc}"))


class ReservationTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="bible-pal-reservations-")
        self.base = pathlib.Path(self._tmp.name)
        self.repo = self.base / "repo"
        self.factory = self.base / "factory-home"
        _prepare_repo(self.repo)
        self.start = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)

    def tearDown(self):
        self._tmp.cleanup()

    def reserve(self, **overrides):
        args = {
            "run_id": "run-1",
            "packet_id": "packet-1",
            "actor": "codex-test",
            "worktree": self.repo,
            "repo_root": self.repo,
            "factory_home": self.factory,
            "worktrees": [self.repo],
            "lease_seconds": 60,
        }
        args.update(overrides)
        return reservations.reserve_id(**args)

    def packet(self, count=5, **overrides):
        args = {
            "count": count,
            "run_id": "run-1",
            "packet_id": "packet-1",
            "actor": "codex-test",
            "worktree": self.repo,
            "repo_root": self.repo,
            "factory_home": self.factory,
            "worktrees": [self.repo],
            "lease_seconds": 60,
        }
        args.update(overrides)
        return reservations.reserve_packet(**args)

    def story_dir(self, story_id, lane="traditional", *, with_file=False):
        path = self.repo / "assets" / "stories" / lane / str(story_id)
        path.mkdir(parents=True, exist_ok=True)
        if with_file:
            (path / f"story_{story_id}.txt").write_text("material story", encoding="utf-8")
        return path

    def materialize(self, reservation, *, actor=None):
        self.story_dir(reservation.story_id, with_file=True)
        return reservations.confirm_materialized(
            reservation,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            actor=actor,
        )

    def ledger_lines(self):
        ledger = self.factory / "reservations.jsonl"
        return ledger.read_text(encoding="utf-8").splitlines()

    def append_raw_event(self, event):
        ledger = self.factory / "reservations.jsonl"
        with ledger.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n")
            handle.flush()
            os.fsync(handle.fileno())


class RangeAndOccupancyTests(ReservationTestCase):
    def test_campaign_constants_define_exactly_259_ids(self):
        self.assertEqual(reservations.MIN_AUTOMATION_STORY_ID, 3000)
        self.assertEqual(reservations.MAX_AUTOMATION_STORY_ID, 3258)
        self.assertEqual(reservations.AUTOMATION_STORY_ID_COUNT, 259)
        self.assertEqual(len(range(3000, 3259)), 259)

    def test_first_legal_allocation_is_3000(self):
        self.assertEqual(self.reserve().story_id, 3000)

    def test_last_legal_allocation_is_3258(self):
        for story_id in range(3000, 3258):
            self.story_dir(story_id)
        self.assertEqual(self.reserve().story_id, 3258)

    def test_3259_is_never_returned_and_exhaustion_is_typed(self):
        for story_id in range(3000, 3259):
            self.story_dir(story_id)
        with self.assertRaises(reservations.NamespaceExhausted):
            self.reserve()

    def test_repository_ids_below_3000_do_not_shift_campaign_range(self):
        self.story_dir(2999, with_file=True)
        self.assertEqual(self.reserve().story_id, 3000)

    def test_bool_story_id_is_not_an_integer_for_api_validation(self):
        with self.assertRaises(reservations.ReservationConflict):
            reservations.recover_stale(
                True,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )

    def test_existing_tracked_traditional_directory_is_occupied(self):
        story = self.story_dir(3000, with_file=True)
        subprocess.run(["git", "-C", str(self.repo), "add", str(story)], check=True)
        self.assertEqual(self.reserve().story_id, 3001)

    def test_existing_untracked_traditional_directory_is_occupied(self):
        self.story_dir(3000)
        status = subprocess.run(
            ["git", "-C", str(self.repo), "status", "--short"],
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        self.assertIn("?? assets/", status)
        self.assertEqual(self.reserve().story_id, 3001)

    def test_existing_kids_directory_is_occupied(self):
        self.story_dir(3000, lane="kids")
        self.assertEqual(self.reserve().story_id, 3001)

    def test_manifest_only_identity_is_occupied(self):
        _write_manifest(self.repo, [3000])
        self.assertEqual(self.reserve().story_id, 3001)

    def test_historical_manifest_opus_is_not_authoritative(self):
        historical = self.repo / "assets" / "stories" / "manifest_opus.json"
        historical.write_text(
            json.dumps(
                {
                    "parables": [
                        {
                            "storyId": "story_3000_historical",
                            "textFilePath": "traditional/3000/story_3000.txt",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        self.assertEqual(self.reserve().story_id, 3000)

    def test_manifest_parse_failure_fails_closed(self):
        (self.repo / "assets" / "stories" / "manifest.json").write_text("{broken", encoding="utf-8")
        with self.assertRaises(reservations.OccupancyScanError):
            self.reserve()

    def test_ambiguous_manifest_identity_fails_closed(self):
        path = self.repo / "assets" / "stories" / "manifest.json"
        path.write_text(
            json.dumps(
                {
                    "version": 6,
                    "parables": [
                        {
                            "storyId": "story_3000_conflict",
                            "textFilePath": "traditional/3001/story_3001.txt",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaises(reservations.OccupancyScanError):
            self.reserve()

    def test_scan_combines_physical_manifest_and_ledger_sources(self):
        self.story_dir(3000)
        _write_manifest(self.repo, [3001])
        reservation = self.reserve()
        self.assertEqual(reservation.story_id, 3002)
        snapshot = reservations.scan_occupied_ids(
            self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        self.assertEqual(snapshot.physical_ids, frozenset({3000}))
        self.assertEqual(snapshot.manifest_ids, frozenset({3001}))
        self.assertEqual(snapshot.ledger_ids, frozenset({3002}))
        self.assertEqual(snapshot.occupied_ids, frozenset({3000, 3001, 3002}))
        self.assertRegex(snapshot.evidence_hash, r"^[0-9a-f]{64}$")


class AtomicAndPacketTests(ReservationTestCase):
    def _run_processes(self, contenders, packet_count):
        ctx = multiprocessing.get_context("spawn")
        start_event = ctx.Event()
        result_queue = ctx.Queue()
        processes = [
            ctx.Process(
                target=_process_reserve_worker,
                args=(
                    str(self.repo),
                    str(self.factory),
                    start_event,
                    result_queue,
                    packet_count,
                    number,
                ),
            )
            for number in range(contenders)
        ]
        for process in processes:
            process.start()
        start_event.set()
        results = []
        for _ in processes:
            try:
                results.append(result_queue.get(timeout=60))
            except queue.Empty as exc:
                self.fail(f"concurrency worker produced no result: {exc}")
        for process in processes:
            process.join(60)
            self.assertFalse(process.is_alive(), "concurrency worker hung")
            self.assertEqual(process.exitcode, 0)
        errors = [payload for status, payload in results if status != "ok"]
        self.assertEqual(errors, [])
        return [story_id for _, ids in results for story_id in ids]

    def test_two_processes_race_for_same_next_id_without_duplicates(self):
        ids = self._run_processes(2, 1)
        self.assertEqual(set(ids), {3000, 3001})
        self.assertEqual(ids.count(3000), 1)

    def test_ten_process_contenders_all_receive_unique_ids(self):
        ids = self._run_processes(10, 1)
        self.assertEqual(len(ids), 10)
        self.assertEqual(len(set(ids)), 10)
        self.assertEqual(set(ids), set(range(3000, 3010)))
        self.assertEqual(len(reservations.replay_ledger(self.factory)), 10)

    def test_two_concurrent_five_story_packets_have_ten_distinct_ids(self):
        ids = self._run_processes(2, 5)
        self.assertEqual(len(ids), 10)
        self.assertEqual(len(set(ids)), 10)
        self.assertEqual(set(ids), set(range(3000, 3010)))

    def test_sequential_packet_reserves_requested_count(self):
        packet = self.packet(count=5)
        self.assertEqual([item.story_id for item in packet], list(range(3000, 3005)))

    def test_packet_count_rejects_bool(self):
        with self.assertRaises(reservations.ReservationConflict):
            self.packet(count=True)

    def test_partial_packet_failure_releases_only_still_reserved_claims(self):
        first = self.reserve(packet_id="partial")
        second = self.reserve(packet_id="partial")
        materialized = self.materialize(first)
        with mock.patch.object(
            reservations,
            "reserve_id",
            side_effect=[first, second, reservations.NamespaceExhausted("forced failure")],
        ):
            with self.assertRaises(reservations.NamespaceExhausted):
                self.packet(count=3, packet_id="partial")
        states = reservations.replay_ledger(self.factory)
        self.assertEqual(states[first.story_id], materialized)
        self.assertEqual(states[second.story_id].state, "RELEASED")
        self.assertTrue((self.factory / "locks" / "3000.lock").exists())
        self.assertFalse((self.factory / "locks" / "3001.lock").exists())


class LifecycleAndPermanenceTests(ReservationTestCase):
    def test_reserved_claim_may_release_and_be_reused(self):
        reservation = self.reserve()
        released = reservations.release_reservation(
            reservation,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        self.assertEqual(released.state, "RELEASED")
        replacement = self.reserve(run_id="run-2", packet_id="packet-2")
        self.assertEqual(replacement.story_id, 3000)
        self.assertNotEqual(replacement.lease_token, reservation.lease_token)

    def test_confirm_materialized_requires_actual_story_file(self):
        reservation = self.reserve()
        self.story_dir(3000)
        with self.assertRaises(reservations.ReservationConflict):
            reservations.confirm_materialized(
                reservation,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )

    def test_confirm_materialized_crash_retry_is_rejected_without_append(self):
        """A retry after the first event fsync must leave the ledger replayable."""
        reservation = self.reserve()
        self.assertEqual(reservation.story_id, 3000)
        materialized = self.materialize(reservation)
        ledger_after_first_confirm = self.ledger_lines()

        with self.assertRaises(reservations.IllegalTransition):
            reservations.confirm_materialized(
                materialized,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )

        self.assertEqual(self.ledger_lines(), ledger_after_first_confirm)
        states = reservations.replay_ledger(self.factory)
        self.assertEqual(states[3000], materialized)
        replacement = self.reserve(run_id="run-2", packet_id="packet-2")
        self.assertEqual(replacement.story_id, 3001)

    def test_materialized_claim_cannot_release_or_be_reused(self):
        reservation = self.reserve()
        materialized = self.materialize(reservation)
        shutil.rmtree(self.story_dir(3000))
        with self.assertRaises(reservations.IllegalTransition):
            reservations.release_reservation(
                materialized,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )
        self.assertEqual(self.reserve(run_id="run-2", packet_id="packet-2").story_id, 3001)

    def test_retired_claim_is_permanently_burned(self):
        materialized = self.materialize(self.reserve())
        retired = reservations.retire_reservation(
            materialized,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        shutil.rmtree(self.story_dir(3000))
        self.assertEqual(retired.state, "RETIRED")
        self.assertEqual(self.reserve(run_id="run-2", packet_id="packet-2").story_id, 3001)

    def test_quarantined_materialized_id_stays_burned(self):
        materialized = self.materialize(self.reserve())
        retired = reservations.retire_reservation(
            materialized,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            reason="quarantined after review failure",
        )
        shutil.rmtree(self.story_dir(3000))
        self.assertEqual(reservations.replay_ledger(self.factory)[3000], retired)
        self.assertEqual(self.reserve(run_id="replacement", packet_id="replacement").story_id, 3001)

    def test_release_is_denied_when_physical_occupancy_appears(self):
        reservation = self.reserve()
        self.story_dir(3000)
        with self.assertRaises(reservations.IllegalTransition):
            reservations.release_reservation(
                reservation,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )

    def test_adopt_preexisting_records_permanent_materialized_state(self):
        self.story_dir(3000, with_file=True)
        adopted = reservations.adopt_preexisting(
            3000,
            run_id="adoption-run",
            packet_id="adoption-packet",
            actor="controller",
            worktree=self.repo,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        self.assertEqual(adopted.state, "MATERIALIZED")
        shutil.rmtree(self.story_dir(3000))
        self.assertEqual(self.reserve().story_id, 3001)

    def test_adopt_without_preexisting_occupancy_is_denied(self):
        with self.assertRaises(reservations.ReservationConflict):
            reservations.adopt_preexisting(
                3000,
                run_id="adoption-run",
                packet_id="adoption-packet",
                actor="controller",
                worktree=self.repo,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )


class StaleRecoveryTests(ReservationTestCase):
    def stale_reservation(self):
        return self.reserve(now=self.start, lease_seconds=1)

    def recover(self, story_id=3000, **overrides):
        args = {
            "repo_root": self.repo,
            "factory_home": self.factory,
            "worktrees": [self.repo],
            "now": self.start + dt.timedelta(seconds=2),
        }
        args.update(overrides)
        return reservations.recover_stale(story_id, **args)

    def test_expired_reserved_claim_without_content_is_recoverable(self):
        self.stale_reservation()
        recovered = self.recover()
        self.assertEqual(recovered.state, "RELEASED")
        replacement = self.reserve(
            run_id="replacement",
            packet_id="replacement",
            now=self.start + dt.timedelta(seconds=3),
        )
        self.assertEqual(replacement.story_id, 3000)

    def test_unexpired_lease_is_not_recoverable(self):
        self.stale_reservation()
        with self.assertRaises(reservations.StaleRecoveryDenied):
            self.recover(now=self.start)

    def test_expired_claim_with_story_directory_is_not_recoverable(self):
        self.stale_reservation()
        self.story_dir(3000)
        with self.assertRaises(reservations.StaleRecoveryDenied):
            self.recover()

    def test_expired_claim_with_manifest_registration_is_not_recoverable(self):
        self.stale_reservation()
        _write_manifest(self.repo, [3000])
        with self.assertRaises(reservations.StaleRecoveryDenied):
            self.recover()

    def test_materialized_history_is_never_stale_recoverable(self):
        materialized = self.materialize(self.stale_reservation())
        shutil.rmtree(self.story_dir(3000))
        with self.assertRaises(reservations.StaleRecoveryDenied):
            self.recover(now=self.start + dt.timedelta(days=1))
        self.assertEqual(reservations.replay_ledger(self.factory)[3000], materialized)

    def test_missing_lock_with_reserved_ledger_fails_closed(self):
        self.stale_reservation()
        (self.factory / "locks" / "3000.lock").unlink()
        with self.assertRaises(reservations.ReservationConflict):
            self.recover()

    def test_orphan_lock_with_no_ledger_fails_closed_for_recovery(self):
        locks = self.factory / "locks"
        locks.mkdir(parents=True, mode=0o700)
        (locks / "3000.lock").write_text("{}", encoding="utf-8")
        with self.assertRaises(reservations.ReservationConflict):
            self.recover()


class LedgerReplayTests(ReservationTestCase):
    def test_lock_and_ledger_are_private_and_carry_required_audit_fields(self):
        self.reserve()
        ledger = self.factory / "reservations.jsonl"
        lock = self.factory / "locks" / "3000.lock"
        self.assertEqual(ledger.stat().st_mode & 0o777, 0o600)
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)
        event = json.loads(self.ledger_lines()[0])
        lock_record = json.loads(lock.read_text(encoding="utf-8"))
        self.assertTrue(
            {
                "schemaVersion",
                "eventId",
                "timestamp",
                "runId",
                "packetId",
                "storyId",
                "actor",
                "leaseToken",
                "worktree",
                "reservedAt",
                "leaseExpiresAt",
                "occupancySnapshotHash",
            }.issubset(event)
        )
        self.assertTrue(
            {
                "schemaVersion",
                "runId",
                "packetId",
                "storyId",
                "actor",
                "leaseToken",
                "worktree",
                "reservedAt",
                "leaseExpiresAt",
            }.issubset(lock_record)
        )

    def test_replay_reconstructs_identical_state_after_restart(self):
        first = self.reserve()
        second = self.reserve(run_id="run-2", packet_id="packet-2")
        second_materialized = self.materialize(second)
        before = reservations.replay_ledger(self.factory)
        self.assertEqual(before, {3000: first, 3001: second_materialized})
        after = reservations.replay_ledger(pathlib.Path(str(self.factory)))
        self.assertEqual(after, before)

    def test_truncated_jsonl_fails_closed(self):
        self.reserve()
        ledger = self.factory / "reservations.jsonl"
        raw = ledger.read_bytes()
        ledger.write_bytes(raw[:-1])
        with self.assertRaises(reservations.LedgerCorrupt):
            reservations.replay_ledger(self.factory)

    def test_invalid_json_event_fails_closed(self):
        self.reserve()
        with (self.factory / "reservations.jsonl").open("ab") as handle:
            handle.write(b"{not-json}\n")
            handle.flush()
            os.fsync(handle.fileno())
        with self.assertRaises(reservations.LedgerCorrupt):
            reservations.replay_ledger(self.factory)

    def test_illegal_transition_fails_closed(self):
        self.reserve()
        event = json.loads(self.ledger_lines()[0])
        event.update(
            {
                "eventId": str(uuid.uuid4()),
                "eventType": "RETIRED",
                "priorState": "RESERVED",
                "newState": "RETIRED",
                "reason": "illegal direct retirement",
            }
        )
        self.append_raw_event(event)
        with self.assertRaises(reservations.IllegalTransition):
            reservations.replay_ledger(self.factory)

    def test_duplicate_event_id_fails_closed(self):
        self.reserve()
        self.append_raw_event(json.loads(self.ledger_lines()[0]))
        with self.assertRaises(reservations.LedgerCorrupt):
            reservations.replay_ledger(self.factory)

    def test_conflicting_reused_lease_token_fails_closed(self):
        self.reserve()
        event = json.loads(self.ledger_lines()[0])
        event.update(
            {
                "eventId": str(uuid.uuid4()),
                "storyId": 3001,
                "priorState": None,
                "runId": "conflict-run",
                "packetId": "conflict-packet",
                "reason": "conflicting duplicate lease",
            }
        )
        self.append_raw_event(event)
        with self.assertRaises(reservations.LedgerCorrupt):
            reservations.replay_ledger(self.factory)

    def test_boolean_story_id_in_ledger_fails_closed(self):
        self.reserve()
        event = json.loads(self.ledger_lines()[0])
        event.update({"eventId": str(uuid.uuid4()), "storyId": True})
        self.append_raw_event(event)
        with self.assertRaises(reservations.LedgerCorrupt):
            reservations.replay_ledger(self.factory)

    def test_corrupt_state_json_is_ignored_and_ledger_remains_authoritative(self):
        reservation = self.reserve()
        (self.factory / "state.json").write_text("corrupt derived cache", encoding="utf-8")
        self.assertEqual(reservations.replay_ledger(self.factory), {3000: reservation})

    def test_corrupt_lock_record_fails_closed(self):
        reservation = self.reserve()
        (self.factory / "locks" / "3000.lock").write_text("{broken", encoding="utf-8")
        with self.assertRaises(reservations.ReservationConflict):
            reservations.release_reservation(
                reservation,
                repo_root=self.repo,
                factory_home=self.factory,
                worktrees=[self.repo],
            )


class FilesystemRaceAndIsolationTests(ReservationTestCase):
    def test_content_appearing_during_post_claim_recheck_is_burned_and_skipped(self):
        original_append = reservations._append_event
        appeared = False

        def append_then_appear(home, event):
            nonlocal appeared
            original_append(home, event)
            if event["eventType"] == "RESERVED" and event["storyId"] == 3000 and not appeared:
                appeared = True
                self.story_dir(3000, with_file=True)

        with mock.patch.object(reservations, "_append_event", side_effect=append_then_appear):
            claimed = self.reserve()
        self.assertEqual(claimed.story_id, 3001)
        self.assertEqual(reservations.replay_ledger(self.factory)[3000].state, "MATERIALIZED")

    def test_worktree_appearing_between_scans_is_detected_post_claim(self):
        new_worktree = self.base / "appearing-worktree"
        _prepare_repo(new_worktree)
        path = new_worktree / "assets" / "stories" / "traditional" / "3000"
        path.mkdir()
        current_root = self.repo.resolve()
        appearing_root = new_worktree.resolve()
        enumerations = [
            (current_root,),
            (current_root,),
            (current_root, appearing_root),
            (current_root, appearing_root),
        ]
        with mock.patch.object(reservations, "_enumerate_worktrees", side_effect=enumerations):
            claimed = reservations.reserve_id(
                run_id="worktree-race",
                packet_id="worktree-race",
                actor="codex-test",
                worktree=self.repo,
                repo_root=self.repo,
                factory_home=self.factory,
            )
        self.assertEqual(claimed.story_id, 3001)
        self.assertEqual(reservations.replay_ledger(self.factory)[3000].state, "MATERIALIZED")

    def test_unreadable_story_directory_fails_closed(self):
        target = (self.repo / "assets" / "stories" / "traditional").resolve()
        real_scandir = reservations.os.scandir

        def guarded_scandir(path):
            if pathlib.Path(path) == target:
                raise PermissionError("simulated unreadable lane")
            return real_scandir(path)

        with mock.patch.object(reservations.os, "scandir", side_effect=guarded_scandir):
            with self.assertRaises(reservations.OccupancyScanError):
                self.reserve()

    def test_unreadable_parent_directory_fails_closed(self):
        target = (self.repo / "assets" / "stories" / "kids").resolve()
        real_lstat = reservations.os.lstat

        def guarded_lstat(path):
            if pathlib.Path(path) == target:
                raise PermissionError("simulated unreadable parent")
            return real_lstat(path)

        with mock.patch.object(reservations.os, "lstat", side_effect=guarded_lstat):
            with self.assertRaises(reservations.OccupancyScanError):
                self.reserve()

    def test_git_worktree_enumeration_failure_fails_before_state_creation(self):
        failed = subprocess.CompletedProcess([], 2, stdout="", stderr="fatal")
        with mock.patch.object(reservations.subprocess, "run", return_value=failed):
            with self.assertRaises(reservations.OccupancyScanError):
                reservations.reserve_id(
                    run_id="run",
                    packet_id="packet",
                    actor="actor",
                    worktree=self.repo,
                    repo_root=self.repo,
                    factory_home=self.factory,
                )
        self.assertFalse(self.factory.exists())

    def test_environment_factory_home_is_used_when_explicit_home_is_absent(self):
        env_home = self.base / "environment-factory"
        with mock.patch.dict(os.environ, {reservations.FACTORY_HOME_ENV: str(env_home)}):
            claimed = reservations.reserve_id(
                run_id="run",
                packet_id="packet",
                actor="actor",
                worktree=self.repo,
                repo_root=self.repo,
                worktrees=[self.repo],
            )
        self.assertEqual(claimed.story_id, 3000)
        self.assertTrue((env_home / "reservations.jsonl").is_file())

    def test_explicit_factory_home_does_not_touch_environment_home(self):
        trap_home = self.base / "must-remain-absent"
        with mock.patch.dict(os.environ, {reservations.FACTORY_HOME_ENV: str(trap_home)}):
            self.reserve()
        self.assertFalse(trap_home.exists())

    def test_factory_home_inside_worktree_is_rejected_without_writes(self):
        bad_home = self.repo / ".factory-state"
        with self.assertRaises(reservations.ReservationConflict):
            reservations.reserve_id(
                run_id="run",
                packet_id="packet",
                actor="actor",
                worktree=self.repo,
                repo_root=self.repo,
                factory_home=bad_home,
                worktrees=[self.repo],
            )
        self.assertFalse(bad_home.exists())

    def test_read_only_occupancy_scan_does_not_create_factory_state(self):
        snapshot = reservations.scan_occupied_ids(
            self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        self.assertEqual(snapshot.occupied_ids, frozenset())
        self.assertFalse(self.factory.exists())

    def test_repository_receives_no_reservation_state_files(self):
        self.reserve()
        self.assertFalse((self.repo / "reservations.jsonl").exists())
        self.assertFalse((self.repo / "state.json").exists())
        self.assertEqual(list(self.repo.rglob("*.lock")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
