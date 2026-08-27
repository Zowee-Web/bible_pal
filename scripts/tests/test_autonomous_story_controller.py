#!/usr/bin/env python3
"""Adversarial tests for the Milestone-1 text-only story controller.

Every controller runtime, reservation, and production path is temporary.  The
real reservation ledger, default factory home, production stories, manifest,
audio services, R2, and Git mutation are never used.
"""

from __future__ import annotations

import copy
import dataclasses
import datetime as dt
import json
import os
import pathlib
import shutil
import tempfile
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
STORY_FACTORY = REPO_ROOT / "scripts" / "story_factory"
import sys

sys.path.insert(0, str(STORY_FACTORY))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import autonomous_story_controller as controller  # noqa: E402
from lib import reconstruction_check  # noqa: E402


ANCHORS = (
    "Genesis 1:1-3",
    "Exodus 3:1-3",
    "Joshua 1:1-3",
    "Ruth 1:1-3",
    "Matthew 5:1-3",
)


class FakeReservations:
    Reservation = controller.reservation_service.Reservation

    def __init__(self):
        self.states = {}
        self.reserve_packet_calls = 0
        self.confirm_calls = 0
        self.fail_confirm_before_once = False
        self.fail_confirm_after_once = False

    def replay_ledger(self, _factory_home):
        return dict(self.states)

    def reserve_packet(self, *, count, run_id, packet_id, actor, worktree,
                       repo_root, factory_home, lease_seconds, worktrees):
        del repo_root, factory_home, lease_seconds, worktrees
        self.reserve_packet_calls += 1
        reservations = []
        for story_id in range(3000, 3000 + count):
            item = self.Reservation(
                story_id=story_id,
                run_id=run_id,
                packet_id=packet_id,
                actor=actor,
                lease_token=f"lease-{story_id}",
                worktree=str(pathlib.Path(worktree).resolve()),
                reserved_at="2026-01-01T00:00:00Z",
                lease_expires_at="2026-01-01T01:00:00Z",
                state="RESERVED",
            )
            self.states[story_id] = item
            reservations.append(item)
        return tuple(reservations)

    def confirm_materialized(self, reservation, **_kwargs):
        self.confirm_calls += 1
        current = self.states[reservation.story_id]
        if self.fail_confirm_before_once:
            self.fail_confirm_before_once = False
            raise RuntimeError("simulated crash before confirmation append")
        materialized = dataclasses.replace(current, state="MATERIALIZED")
        self.states[reservation.story_id] = materialized
        if self.fail_confirm_after_once:
            self.fail_confirm_after_once = False
            raise RuntimeError("simulated crash after confirmation append")
        return materialized


class FakeOverlap:
    def __init__(self):
        self.outcomes = {}
        self.calls = []

    def __call__(self, anchor, **kwargs):
        self.calls.append((anchor, kwargs))
        outcome = self.outcomes.get(anchor, "PASS")
        if isinstance(outcome, BaseException):
            raise outcome
        return {
            "gateVersion": "test",
            "candidate": {"rawReference": anchor, "proposedStoryId": kwargs.get("story_id")},
            "verdict": outcome,
            "blockingStoryIds": [] if outcome != "BLOCK" else [99],
            "warnings": [],
        }


def words(count: int, *, kjv: bool = False) -> str:
    base = (
        "The people walked beside the open field while morning light rested over the road "
        "and every traveler watched the work before them with quiet care"
    )
    if kjv:
        base = (
            "The people walked beside the open field and thou couldst see the road while "
            "morning light rested there and they went unto the place with quiet care"
        )
    tokens = base.split()
    return " ".join(tokens[index % len(tokens)] for index in range(count))


class ControllerTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="bible-pal-controller-")
        self.base = pathlib.Path(self._tmp.name)
        self.repo = self.base / "repo"
        self.factory = self.base / "factory"
        (self.repo / "assets" / "stories" / "traditional").mkdir(parents=True)
        (self.repo / "assets" / "stories" / "manifest.json").write_text(
            json.dumps({"version": 1, "parables": []}), encoding="utf-8",
        )
        self.reservations = FakeReservations()
        self.overlap = FakeOverlap()
        self.fixed_now = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        self.controller = controller.AutonomousStoryController(
            repo_root=self.repo,
            worktree=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            policy_root=REPO_ROOT,
            reservations=self.reservations,
            overlap_evaluator=self.overlap,
            clock=lambda: self.fixed_now,
        )
        self.run_id = "run-1"
        self.packet_id = "packet-1"
        self.actor = "owner"

    def tearDown(self):
        self._tmp.cleanup()

    def planning(self, *, count=5, narrator="VOICE_SARAH_STORYTELLER"):
        return {
            "stories": [
                {
                    "proposedAnchor": ANCHORS[index],
                    "mood": "encouraging",
                    "narrator": narrator,
                    "lengths": ["short"],
                }
                for index in range(count)
            ]
        }

    def plan(self):
        return self.controller.plan_packet(
            run_id=self.run_id,
            packet_id=self.packet_id,
            actor=self.actor,
            planning=self.planning(),
            lease_seconds=60,
        )

    def assignments(self):
        self.plan()
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        return self.controller.emit_writer_assignments(
            self.run_id, self.packet_id, actor=self.actor,
        )

    def _metadata(self, slot):
        story_id = slot["storyId"]
        return {
            "schemaVersion": 2,
            "storyId": story_id,
            "mode": "traditional",
            "kidFriendly": False,
            "languageStyle": "WEB",
            "lanes": ["web", "kjv"],
            "mood": slot["mood"],
            "lengths": slot["targetLengths"],
            "createdByModel": "manual-claude-handoff",
            "generationBatch": "AUTONOMOUS_M1_TEST",
            "title": f"Proving Story {story_id}",
            "scriptureAnchor": slot["proposedAnchor"],
            "bibleStoryKey": f"proving_story_{story_id}",
            "storyVoiceKey": slot["narrator"],
            "timelineEra": "patriarchs",
            "primaryCharacterId": "test_character",
            "primaryCharacterDisplayName": "Test Character",
            "files": self.controller._expected_files_map(slot),
        }

    def write_outputs(self, packet=None, *, root=None, only_ids=None, mutate=None):
        packet = packet or self.controller.load(self.run_id, self.packet_id)
        root = pathlib.Path(root or (self.base / f"writer-{packet['correctionRound']}-{packet['reviewRound']}"))
        root.mkdir(parents=True, exist_ok=True)
        for slot in packet["slots"]:
            story_id = slot["storyId"]
            if only_ids is not None and story_id not in only_ids:
                continue
            directory = root / str(story_id)
            directory.mkdir()
            for length in slot["targetLengths"]:
                floor, _ = controller.TRADITIONAL_RANGES[length]
                for lane in controller.LANES:
                    name = f"story_{story_id}_traditional_{lane}_{length}.txt"
                    (directory / name).write_text(words(floor, kjv=lane == "kjv"), encoding="utf-8")
            for lane in controller.LANES:
                (directory / f"reflection_{story_id}_traditional_{lane}.txt").write_text(
                    words(controller.REFLECTION_WORD_RANGE[0], kjv=lane == "kjv"), encoding="utf-8",
                )
                scripture_tokens = reconstruction_check.resolve_source_tokens(
                    slot["proposedAnchor"], lane, repo_root=REPO_ROOT,
                )
                (directory / f"scripture_{story_id}_{lane}.txt").write_text(
                    " ".join(scripture_tokens), encoding="utf-8",
                )
            (directory / f"meta_{story_id}.json").write_text(
                json.dumps(self._metadata(slot)), encoding="utf-8",
            )
        if mutate is not None:
            mutate(root, packet)
        return root

    def ingested(self):
        packet = self.assignments()
        source = self.write_outputs(packet)
        return self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )

    def validated(self):
        self.ingested()
        return self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)

    def materialized(self):
        self.validated()
        return self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor,
        )

    def review_ready(self):
        self.materialized()
        return self.controller.emit_review_packet(
            self.run_id, self.packet_id, actor=self.actor,
        )

    def review(self, verdict="APPROVED", findings=None):
        packet = self.controller.load(self.run_id, self.packet_id)
        findings = [] if findings is None and verdict == "APPROVED" else (findings or ["Revise bounded detail."])
        return {
            "stories": [
                {"storyId": slot["storyId"], "verdict": verdict, "findings": list(findings)}
                for slot in packet["slots"]
            ]
        }


class StateMachineTests(ControllerTestCase):
    def test_legal_transitions_reach_assignment_ready(self):
        packet = self.assignments()
        self.assertEqual(packet["state"], controller.ASSIGNMENT_READY)

    def test_illegal_transition_is_typed(self):
        self.plan()
        with self.assertRaises(controller.IllegalControllerTransition):
            self.controller.emit_writer_assignments(self.run_id, self.packet_id, actor=self.actor)

    def test_malformed_journal_is_rejected(self):
        self.plan()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        with journal.open("ab") as handle:
            handle.write(b"{not-json\n")
        with self.assertRaises(controller.JournalCorrupt):
            controller.replay_packet(self.factory, self.run_id, self.packet_id)

    def _append_forged(self, *, duplicate=False, sequence=None):
        packet = self.plan()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        events = [json.loads(line) for line in journal.read_text().splitlines()]
        last = copy.deepcopy(events[-1])
        last["eventType"] = "ANCHOR_PREFLIGHT_REFUSED"
        last["fromState"] = packet["state"]
        last["toState"] = packet["state"]
        last["sequence"] = sequence if sequence is not None else len(events) + 1
        if not duplicate:
            last["eventId"] = "fresh-event-id"
        last.pop("evidenceHash")
        last["evidenceHash"] = controller._event_hash(last)
        with journal.open("a") as handle:
            handle.write(json.dumps(last, sort_keys=True, separators=(",", ":")) + "\n")

    def test_duplicate_event_id_is_rejected(self):
        self._append_forged(duplicate=True)
        with self.assertRaises(controller.JournalCorrupt):
            controller.replay_packet(self.factory, self.run_id, self.packet_id)

    def test_out_of_order_event_is_rejected(self):
        self._append_forged(sequence=99)
        with self.assertRaises(controller.JournalCorrupt):
            controller.replay_packet(self.factory, self.run_id, self.packet_id)


class PacketModelTests(ControllerTestCase):
    def test_packet_requires_exactly_five_plans(self):
        with self.assertRaises(controller.ControllerConfigError):
            self.controller.plan_packet(
                run_id=self.run_id, packet_id=self.packet_id, actor=self.actor,
                planning=self.planning(count=4),
            )

    def test_duplicate_story_id_is_rejected(self):
        packet = self.plan()
        packet["slots"][1]["storyId"] = packet["slots"][0]["storyId"]
        packet["slots"][1]["reservation"] = copy.deepcopy(packet["slots"][0]["reservation"])
        with self.assertRaises(controller.JournalCorrupt):
            controller.validate_packet_model(packet)

    def test_story_id_outside_campaign_is_rejected(self):
        packet = self.plan()
        packet["slots"][0]["storyId"] = 2999
        packet["slots"][0]["reservation"]["storyId"] = 2999
        with self.assertRaises(controller.JournalCorrupt):
            controller.validate_packet_model(packet)


class ReservationIntegrationTests(ControllerTestCase):
    def test_controller_uses_reserve_packet_api(self):
        packet = self.plan()
        self.assertEqual(self.reservations.reserve_packet_calls, 1)
        self.assertEqual([s["storyId"] for s in packet["slots"]], list(range(3000, 3005)))

    def test_lost_reservation_is_rejected(self):
        self.plan()
        del self.reservations.states[3000]
        with self.assertRaises(controller.IntegrationError):
            self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)

    def test_mismatched_reservation_is_rejected(self):
        self.plan()
        current = self.reservations.states[3000]
        self.reservations.states[3000] = dataclasses.replace(current, lease_token="foreign")
        with self.assertRaises(controller.IntegrationError):
            self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)

    def test_materialization_confirmation_occurs_exactly_once(self):
        self.validated()
        self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(self.reservations.confirm_calls, 5)


class OverlapIntegrationTests(ControllerTestCase):
    def test_pass_advances(self):
        self.plan()
        packet = self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(packet["state"], controller.ANCHOR_PREFLIGHT_PASSED)
        self.assertEqual(len(self.overlap.calls), 5)

    def _assert_stops(self, outcome):
        self.plan()
        self.overlap.outcomes[ANCHORS[0]] = outcome
        with self.assertRaises(controller.OverlapRejected):
            self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(packet["state"], controller.ID_RESERVED)

    def test_warn_stops_for_owner_review(self):
        self._assert_stops("WARN")

    def test_block_stops(self):
        self._assert_stops("BLOCK")

    def test_error_stops(self):
        self._assert_stops(RuntimeError("coverage unavailable"))

    def test_final_metadata_anchor_change_stops(self):
        packet = self.assignments()

        def mutate(root, _packet):
            path = root / "3000" / "meta_3000.json"
            meta = json.loads(path.read_text())
            meta["scriptureAnchor"] = "Genesis 1:1-5"
            path.write_text(json.dumps(meta))

        source = self.write_outputs(packet, mutate=mutate)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)


class NarratorContractTests(ControllerTestCase):
    def test_invalid_narrator_is_rejected_at_plan(self):
        with self.assertRaises(controller.ControllerConfigError):
            self.controller.plan_packet(
                run_id=self.run_id, packet_id=self.packet_id, actor=self.actor,
                planning=self.planning(narrator="VOICE_GRACE"),
            )

    def test_writer_changed_narrator_is_rejected(self):
        packet = self.assignments()

        def mutate(root, _packet):
            path = root / "3000" / "meta_3000.json"
            meta = json.loads(path.read_text())
            meta["storyVoiceKey"] = "VOICE_JAMES_HUSKY"
            path.write_text(json.dumps(meta))

        source = self.write_outputs(packet, mutate=mutate)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)


class WorkspaceIsolationTests(ControllerTestCase):
    def test_path_traversal_identifier_is_rejected(self):
        escaped = self.factory.parent / "escape"
        with self.assertRaises(controller.ControllerConfigError):
            self.controller.plan_packet(
                run_id="../escape",
                packet_id=self.packet_id,
                actor=self.actor,
                planning=self.planning(),
            )
        self.assertFalse(escaped.exists())

    def test_writer_output_cannot_be_ingested_from_production(self):
        packet = self.assignments()
        production = self.repo / "assets" / "stories" / "traditional" / "incoming"
        self.write_outputs(packet, root=production)
        with self.assertRaises(controller.WorkspaceRejected):
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=production, actor=self.actor,
            )

    def test_symlink_artifact_is_rejected(self):
        packet = self.assignments()
        source = self.write_outputs(packet)
        target = source / "3000" / "story_3000_traditional_web_short.txt"
        target.unlink()
        target.symlink_to(source / "3000" / "story_3000_traditional_kjv_short.txt")
        with self.assertRaises(controller.WorkspaceRejected):
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=source, actor=self.actor,
            )

    def test_missing_required_artifact_is_rejected_at_ingest(self):
        packet = self.assignments()
        source = self.write_outputs(packet)
        (source / "3000" / "reflection_3000_traditional_web.txt").unlink()
        with self.assertRaises(controller.WorkspaceRejected):
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=source, actor=self.actor,
            )

    def test_unexpected_audio_artifact_is_rejected(self):
        packet = self.assignments()
        source = self.write_outputs(packet)
        (source / "3000" / "audio_3000.mp3").write_bytes(b"not audio")
        with self.assertRaises(controller.WorkspaceRejected):
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=source, actor=self.actor,
            )


class ValidationPipelineTests(ControllerTestCase):
    def _ingest_mutated(self, mutate):
        packet = self.assignments()
        source = self.write_outputs(packet, mutate=mutate)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )

    def test_schema_failure_stops(self):
        def mutate(root, _packet):
            path = root / "3000" / "meta_3000.json"
            meta = json.loads(path.read_text())
            del meta["title"]
            path.write_text(json.dumps(meta))

        self._ingest_mutated(mutate)
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)

    def test_missing_file_after_ingest_stops(self):
        self.ingested()
        packet = self.controller.load(self.run_id, self.packet_id)
        workspace = self.controller.packet_dir(self.run_id, self.packet_id) / packet["slots"][0]["workspace"]["path"]
        (workspace / "scripture_3000_web.txt").unlink()
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)

    def test_bucket_failure_stops(self):
        def mutate(root, _packet):
            (root / "3000" / "story_3000_traditional_web_short.txt").write_text(words(20))

        self._ingest_mutated(mutate)
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)

    def test_mechanical_quality_failure_stops(self):
        def mutate(root, _packet):
            path = root / "3000" / "story_3000_traditional_web_short.txt"
            path.write_text("Here is " + words(298))

        self._ingest_mutated(mutate)
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)

    def test_failed_validation_can_emit_bounded_correction_and_revalidate(self):
        def mutate(root, _packet):
            (root / "3000" / "story_3000_traditional_web_short.txt").write_text(words(20))

        self._ingest_mutated(mutate)
        with self.assertRaises(controller.ValidationFailed):
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(packet["state"], controller.CORRECTION_READY)
        changed = {slot["storyId"] for slot in packet["slots"] if slot["unresolvedFindings"]}
        source = self.write_outputs(packet, root=self.base / "validation-correction", only_ids=changed)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        packet = self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(packet["state"], controller.VALIDATION_PASSED)


class ProductionSafetyTests(ControllerTestCase):
    def test_no_production_copy_before_validation(self):
        self.ingested()
        for story_id in range(3000, 3005):
            self.assertFalse((self.repo / "assets" / "stories" / "traditional" / str(story_id)).exists())

    def test_materialization_creates_only_authorized_story_directories(self):
        packet = self.materialized()
        for slot in packet["slots"]:
            destination = self.repo / "assets" / "stories" / "traditional" / str(slot["storyId"])
            self.assertEqual(
                {path.name for path in destination.iterdir()},
                set(controller.expected_artifact_names(slot["storyId"], slot["targetLengths"])),
            )

    def test_manifest_is_unchanged_across_materialization(self):
        before = controller._hash_file(self.repo / "assets" / "stories" / "manifest.json")
        self.materialized()
        after = controller._hash_file(self.repo / "assets" / "stories" / "manifest.json")
        self.assertEqual(before, after)

    def test_audio_is_absent_after_materialization(self):
        self.materialized()
        self.assertEqual(list(self.repo.rglob("*.mp3")), [])


class ReviewAndCorrectionTests(ControllerTestCase):
    def test_approved_review_advances(self):
        self.review_ready()
        packet = self.controller.ingest_review(
            self.run_id, self.packet_id, review=self.review("APPROVED"), actor=self.actor,
        )
        self.assertEqual(packet["state"], controller.REVIEW_APPROVED)

    def test_changes_requested_cannot_advance_to_human_review(self):
        self.review_ready()
        packet = self.controller.ingest_review(
            self.run_id, self.packet_id, review=self.review("CHANGES_REQUESTED"), actor=self.actor,
        )
        self.assertEqual(packet["state"], controller.REVIEW_CHANGES_REQUESTED)
        with self.assertRaises(controller.IllegalControllerTransition):
            self.controller.mark_ready_for_human_review(self.run_id, self.packet_id, actor=self.actor)

    def test_malformed_reviewer_verdict_is_rejected(self):
        self.review_ready()
        review = self.review("APPROVED")
        review["stories"][0]["verdict"] = "MAYBE"
        with self.assertRaises(controller.ReviewRejected):
            self.controller.ingest_review(
                self.run_id, self.packet_id, review=review, actor=self.actor,
            )

    def test_tampered_review_bundle_is_rejected(self):
        packet = self.review_ready()
        review_path = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "reviews" / f"round-{packet['reviewRound']}" / "story_3000.json"
        )
        payload = json.loads(review_path.read_text())
        payload["anchor"] = "tampered"
        review_path.write_text(json.dumps(payload))
        with self.assertRaises(controller.ReviewRejected):
            self.controller.ingest_review(
                self.run_id, self.packet_id, review=self.review("APPROVED"), actor=self.actor,
            )

    def test_correction_attempt_cap_quarantines(self):
        self.review_ready()
        for round_number in range(1, controller.MAX_CORRECTION_ROUNDS + 1):
            packet = self.controller.ingest_review(
                self.run_id, self.packet_id,
                review=self.review("CHANGES_REQUESTED", [f"Round {round_number} finding"]),
                actor=self.actor,
            )
            self.assertEqual(packet["state"], controller.REVIEW_CHANGES_REQUESTED)
            packet = self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
            changed = {slot["storyId"] for slot in packet["slots"] if slot["unresolvedFindings"]}
            source = self.write_outputs(packet, root=self.base / f"correction-{round_number}", only_ids=changed)
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=source, actor=self.actor,
            )
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
            self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
            self.controller.emit_review_packet(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.ingest_review(
            self.run_id, self.packet_id,
            review=self.review("CHANGES_REQUESTED", ["One more finding"]),
            actor=self.actor,
        )
        self.assertEqual(packet["state"], controller.QUARANTINED)

    def test_approved_packet_reaches_human_review_and_report(self):
        self.review_ready()
        self.controller.ingest_review(
            self.run_id, self.packet_id, review=self.review("APPROVED"), actor=self.actor,
        )
        packet = self.controller.mark_ready_for_human_review(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertEqual(packet["state"], controller.READY_FOR_HUMAN_REVIEW)
        report = self.controller.packet_dir(self.run_id, self.packet_id) / "reports" / "ready_for_human_review.md"
        self.assertIn("READY_FOR_HUMAN_REVIEW", report.read_text())


class RecoveryTests(ControllerTestCase):
    def test_restart_replay_reconstructs_identical_packet(self):
        expected = self.assignments()
        restarted = controller.AutonomousStoryController(
            repo_root=self.repo,
            worktree=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            policy_root=REPO_ROOT,
            reservations=self.reservations,
            overlap_evaluator=self.overlap,
            clock=lambda: self.fixed_now,
        )
        self.assertEqual(restarted.load(self.run_id, self.packet_id), expected)

    def test_crash_after_copy_before_confirm_is_recoverable(self):
        self.validated()
        self.reservations.fail_confirm_before_once = True
        with self.assertRaises(RuntimeError):
            self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertTrue(all(slot["reservation"]["state"] == "MATERIALIZED" for slot in packet["slots"]))
        self.assertEqual(self.reservations.confirm_calls, 6)

    def test_crash_after_confirm_does_not_double_confirm(self):
        self.validated()
        self.reservations.fail_confirm_after_once = True
        with self.assertRaises(RuntimeError):
            self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertTrue(all(slot["reservation"]["state"] == "MATERIALIZED" for slot in packet["slots"]))
        self.assertEqual(self.reservations.confirm_calls, 5)


class IsolationProofTests(ControllerTestCase):
    def test_plan_cli_runs_anchor_preflight_before_writer_handoff(self):
        planning_path = self.base / "planning.json"
        planning_path.write_text(json.dumps(self.planning()), encoding="utf-8")
        fake = mock.Mock()
        fake.preflight_anchors.return_value = {"state": controller.ANCHOR_PREFLIGHT_PASSED}
        argv = [
            "plan-packet",
            "--run-id", self.run_id,
            "--packet-id", self.packet_id,
            "--actor", self.actor,
            "--repo-root", str(self.repo),
            "--worktree", str(self.repo),
            "--factory-home", str(self.factory),
            "--planning", str(planning_path),
        ]
        with mock.patch.object(controller, "_cli_controller", return_value=fake), \
                mock.patch.object(controller, "_print_json") as print_json:
            self.assertEqual(controller.main(argv), 0)
        fake.plan_packet.assert_called_once()
        fake.preflight_anchors.assert_called_once_with(
            self.run_id, self.packet_id, actor=self.actor,
        )
        print_json.assert_called_once_with({
            "status": "OK",
            "packet": {"state": controller.ANCHOR_PREFLIGHT_PASSED},
        })

    def test_default_factory_home_is_not_touched_by_explicit_test_home(self):
        sentinel = self.base / "default-home" / ".bible_pal_factory"
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(
            pathlib.Path, "home", return_value=sentinel.parent,
        ):
            controller.AutonomousStoryController(
                repo_root=self.repo,
                worktree=self.repo,
                factory_home=self.factory,
                policy_root=REPO_ROOT,
                reservations=self.reservations,
                overlap_evaluator=self.overlap,
            )
        self.assertFalse(sentinel.exists())

    def test_controller_has_no_audio_command_or_tts_invocation_path(self):
        commands = controller.build_parser()._subparsers._group_actions[0].choices
        self.assertNotIn("audio", commands)
        self.assertNotIn("generate-audio", commands)
        source = pathlib.Path(controller.__file__).read_text()
        self.assertNotIn("generate_opus_audio", source)
        self.assertNotIn("elevenlabs.com", source.lower())

    def test_controller_has_no_r2_or_publication_command(self):
        commands = controller.build_parser()._subparsers._group_actions[0].choices
        self.assertFalse({"publish", "upload", "r2"} & set(commands))
        source = pathlib.Path(controller.__file__).read_text().lower()
        self.assertNotIn("wrangler", source)

    def test_controller_has_no_git_write_implementation(self):
        source = pathlib.Path(controller.__file__).read_text()
        self.assertNotIn("import subprocess", source)
        for command in ("git add", "git commit", "git push", "git reset", "git clean", "git stash"):
            self.assertNotIn(command, source.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
