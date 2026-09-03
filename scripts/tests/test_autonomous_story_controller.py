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
import claude_validator  # noqa: E402
import reflection_contract  # noqa: E402
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
        self.reserve_lease_seconds = []
        self.renew_calls = []
        self.renew_updates = {}
        self.confirm_calls = 0
        self.fail_confirm_before_once = False
        self.fail_confirm_after_once = False
        self.fail_reserve_before_once = False
        self.fail_reserve_partial_once = False
        self.fail_renew_story_id_once = None

    def replay_ledger(self, _factory_home):
        return dict(self.states)

    def reserve_packet(self, *, count, run_id, packet_id, actor, worktree,
                       repo_root, factory_home, lease_seconds, worktrees):
        del repo_root, factory_home, worktrees
        self.reserve_packet_calls += 1
        self.reserve_lease_seconds.append(lease_seconds)
        if self.fail_reserve_before_once:
            self.fail_reserve_before_once = False
            raise RuntimeError("simulated reservation failure before any claim")
        if self.fail_reserve_partial_once:
            self.fail_reserve_partial_once = False
            released = self.Reservation(
                story_id=3000,
                run_id=run_id,
                packet_id=packet_id,
                actor=actor,
                lease_token="lease-3000",
                worktree=str(pathlib.Path(worktree).resolve()),
                reserved_at="2026-01-01T00:00:00Z",
                lease_expires_at="2026-01-01T01:00:00Z",
                state="RELEASED",
            )
            self.states[released.story_id] = released
            raise RuntimeError("simulated partial packet failure after API rollback")
        reservations = []
        reserved_at = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        expires_at = reserved_at + dt.timedelta(seconds=lease_seconds)
        for story_id in range(3000, 3000 + count):
            item = self.Reservation(
                story_id=story_id,
                run_id=run_id,
                packet_id=packet_id,
                actor=actor,
                lease_token=f"lease-{story_id}",
                worktree=str(pathlib.Path(worktree).resolve()),
                reserved_at=reserved_at.isoformat().replace("+00:00", "Z"),
                lease_expires_at=expires_at.isoformat().replace("+00:00", "Z"),
                state="RESERVED",
            )
            self.states[story_id] = item
            reservations.append(item)
        return tuple(reservations)

    def _renew(
        self,
        reservation,
        *,
        actor,
        lease_seconds,
        now,
        owner_authorized=None,
        repo_root=None,
        factory_home=None,
        worktrees=None,
    ):
        del repo_root, factory_home, worktrees
        self.renew_calls.append((reservation.story_id, owner_authorized))
        current = self.states[reservation.story_id]
        if self.fail_renew_story_id_once == reservation.story_id:
            self.fail_renew_story_id_once = None
            raise RuntimeError(f"simulated renewal failure for {reservation.story_id}")
        for field in (
            "story_id", "run_id", "packet_id", "actor", "lease_token",
            "worktree", "reserved_at",
        ):
            if getattr(current, field) != getattr(reservation, field):
                raise RuntimeError(f"renewal ownership mismatch: {field}")
        if actor != current.actor or current.state != "RESERVED":
            raise RuntimeError("renewal owner/state mismatch")
        if current.lease_expires_at != reservation.lease_expires_at:
            return current
        current_expiry = dt.datetime.fromisoformat(
            current.lease_expires_at.replace("Z", "+00:00")
        )
        renewed_expiry = max(current_expiry, now) + dt.timedelta(seconds=lease_seconds)
        renewed = dataclasses.replace(
            current,
            lease_expires_at=renewed_expiry.isoformat().replace("+00:00", "Z"),
        )
        self.states[reservation.story_id] = renewed
        self.renew_updates[reservation.story_id] = (
            self.renew_updates.get(reservation.story_id, 0) + 1
        )
        return renewed

    def renew_reservation(self, reservation, **kwargs):
        return self._renew(reservation, **kwargs)

    def renew_expired_reservation(self, reservation, *, owner_authorized, **kwargs):
        if owner_authorized is not True:
            raise RuntimeError("owner authorization required")
        return self._renew(
            reservation,
            owner_authorized=owner_authorized,
            **kwargs,
        )

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


class MetaTextContextTests(unittest.TestCase):
    def test_scriptural_first_person_i_have_is_not_model_meta_text(self):
        for text in (
            '"I have anointed you king over Israel."',
            '"I have anointed thee king over Israel."',
            "I have kept the faith.",
            "I have kept the ways of the LORD.",
            "I have made a covenant with mine eyes.",
            "I have prepared the house.",
            "I have provided me a king.",
            "I have created him for my glory.",
            "I have written unto you.",
            "I have followed him fully.",
            "I have heard your prayer.",
            "I have seen your tears.",
        ):
            with self.subTest(text=text):
                self.assertIsNone(controller.check_meta_text(text))

    def test_model_work_announcements_remain_blocked(self):
        for text in (
            "I have written the requested story.",
            "I have generated the following output.",
            "I have prepared the corrected version.",
            "I have included the files below.",
            "I have included both language lanes.",
            "I have expanded the passage carefully.",
            "I have retold the account faithfully.",
            "I have provided both lanes as requested.",
            "I have created the reflection you asked for.",
            "I have rewritten the opening.",
            "I have followed the style guide.",
            "I have made the requested changes.",
            "I have kept the corrected files in the folder.",
        ):
            with self.subTest(text=text):
                self.assertIsNotNone(claude_validator._I_HAVE_MODEL_WORK_RE.search(text))
                self.assertIsNotNone(controller.check_meta_text(text))

    def test_nearby_biblical_objects_do_not_become_work_products(self):
        for text in (
            "I have written the law upon their hearts.",
            "I have prepared a place for you.",
            "I have made the earth.",
            "I have kept your precepts.",
            "I have provided for the widow.",
        ):
            with self.subTest(text=text):
                self.assertIsNone(controller.check_meta_text(text))

    def test_i_have_model_work_rule_has_zero_project_bible_collisions(self):
        for translation in ("kjv", "web"):
            corpus = json.loads(
                (REPO_ROOT / "server" / "data" / f"bible_{translation}.json").read_text()
            )
            collisions = []
            for book, chapters in corpus["books"].items():
                for chapter, verses in chapters.items():
                    for verse, text in verses.items():
                        if claude_validator._I_HAVE_MODEL_WORK_RE.search(text):
                            collisions.append(f"{book} {chapter}:{verse}")
            self.assertEqual(collisions, [], translation)


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
            "reflectionForm": slot["reflectionForm"],
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
                    words(reflection_contract.STANDARD_TARGET_RANGE[0], kjv=lane == "kjv"),
                    encoding="utf-8",
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


class FactoryHomeAndPlannedResumeTests(ControllerTestCase):
    def _strand(self):
        self.reservations.fail_reserve_before_once = True
        with self.assertRaisesRegex(RuntimeError, "before any claim"):
            self.plan()
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(packet["state"], controller.PLANNED)
        return packet

    def _resume(self, planning=None):
        return self.controller.resume_planned_packet(
            run_id=self.run_id,
            packet_id=self.packet_id,
            actor=self.actor,
            planning=planning or self.planning(),
            lease_seconds=60,
        )

    def _events(self):
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        return [json.loads(line) for line in journal.read_text(encoding="utf-8").splitlines()]

    def _seed_claims(self, count=5, *, state="RESERVED"):
        self.reservations.states = {}
        for story_id in range(3000, 3000 + count):
            item = self.reservations.Reservation(
                story_id=story_id,
                run_id=self.run_id,
                packet_id=self.packet_id,
                actor=self.actor,
                lease_token=f"lease-{story_id}",
                worktree=str(self.repo.resolve()),
                reserved_at="2026-01-01T00:00:00Z",
                lease_expires_at="2026-01-01T01:00:00Z",
                state=state,
            )
            self.reservations.states[story_id] = item

    def _assert_mode(self, path, expected):
        self.assertEqual(pathlib.Path(path).stat().st_mode & 0o7777, expected, path)

    def test_fresh_runtime_directories_are_0700_and_evidence_is_0600(self):
        self.plan()
        pdir = self.controller.packet_dir(self.run_id, self.packet_id)
        expected_dirs = [
            self.factory,
            self.factory / "runs",
            self.factory / "runs" / self.run_id,
            self.factory / "runs" / self.run_id / "packets",
            pdir,
        ]
        for path in expected_dirs:
            self._assert_mode(path, 0o700)
        self._assert_mode(pdir / "events.jsonl", 0o600)
        self._assert_mode(pdir / "packet.json", 0o600)

    def test_all_created_runtime_subdirectories_are_0700(self):
        self.review_ready()
        self.controller.ingest_review(
            self.run_id, self.packet_id,
            review=self.review("CHANGES_REQUESTED"), actor=self.actor,
        )
        packet = self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
        changed = {slot["storyId"] for slot in packet["slots"] if slot["unresolvedFindings"]}
        source = self.write_outputs(packet, root=self.base / "private-correction", only_ids=changed)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        self.controller.emit_review_packet(self.run_id, self.packet_id, actor=self.actor)
        self.controller.ingest_review(
            self.run_id, self.packet_id, review=self.review("APPROVED"), actor=self.actor,
        )
        self.controller.mark_ready_for_human_review(self.run_id, self.packet_id, actor=self.actor)
        for root, dirs, _files in os.walk(self.factory):
            self._assert_mode(root, 0o700)
            for name in dirs:
                self._assert_mode(pathlib.Path(root) / name, 0o700)

    def test_preexisting_unsafe_factory_home_is_refused_without_chmod(self):
        self.factory.mkdir(mode=0o755)
        os.chmod(self.factory, 0o755)
        with self.assertRaises(controller.SafetyViolation):
            self.plan()
        self._assert_mode(self.factory, 0o755)
        self.assertFalse((self.factory / "runs").exists())
        self.assertEqual(self.reservations.reserve_packet_calls, 0)

    def test_safe_preexisting_private_factory_home_is_allowed(self):
        self.factory.mkdir(mode=0o700)
        os.chmod(self.factory, 0o700)
        packet = self.plan()
        self.assertEqual(packet["state"], controller.ID_RESERVED)

    def test_symlink_factory_home_is_refused(self):
        target = self.base / "factory-target"
        target.mkdir(mode=0o700)
        link = self.base / "factory-link"
        link.symlink_to(target, target_is_directory=True)
        with self.assertRaises(controller.ControllerConfigError):
            controller.AutonomousStoryController(
                repo_root=self.repo, worktree=self.repo, factory_home=link,
                worktrees=[self.repo], policy_root=REPO_ROOT,
                reservations=self.reservations, overlap_evaluator=self.overlap,
            )

    def test_factory_home_inside_repository_is_refused(self):
        with self.assertRaises(controller.ControllerConfigError):
            controller.AutonomousStoryController(
                repo_root=self.repo, worktree=self.repo,
                factory_home=self.repo / ".factory",
                worktrees=[self.repo], policy_root=REPO_ROOT,
                reservations=self.reservations, overlap_evaluator=self.overlap,
            )

    def test_planned_zero_claim_resume_reserves_five(self):
        self._strand()
        packet = self._resume()
        self.assertEqual(packet["state"], controller.ID_RESERVED)
        self.assertEqual([slot["storyId"] for slot in packet["slots"]], list(range(3000, 3005)))

    def test_resume_appends_no_second_packet_planned_event(self):
        self._strand()
        self._resume()
        event_types = [event["eventType"] for event in self._events()]
        self.assertEqual(event_types.count("PACKET_PLANNED"), 1)
        self.assertEqual(event_types.count("IDS_RESERVED"), 1)

    def test_resume_changed_planning_input_is_refused(self):
        self._strand()
        changed = self.planning()
        changed["stories"][0]["mood"] = "joyful"
        with self.assertRaises(controller.ControllerConfigError):
            self._resume(changed)
        self.assertEqual(self.controller.load(self.run_id, self.packet_id)["state"], controller.PLANNED)

    def test_resume_state_other_than_planned_is_refused(self):
        self.plan()
        with self.assertRaises(controller.IllegalControllerTransition):
            self._resume()

    def test_resume_malformed_journal_is_refused(self):
        self._strand()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        with journal.open("ab") as handle:
            handle.write(b"{malformed}\n")
        with self.assertRaises(controller.JournalCorrupt):
            self._resume()

    def test_resume_manifest_baseline_change_is_refused(self):
        self._strand()
        (self.repo / "assets" / "stories" / "manifest.json").write_text(
            json.dumps({"version": 2, "parables": []}), encoding="utf-8",
        )
        with self.assertRaises(controller.SafetyViolation):
            self._resume()

    def test_resume_refuses_broadened_journal_before_reserving(self):
        self._strand()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        os.chmod(journal, 0o644)
        calls = self.reservations.reserve_packet_calls
        with self.assertRaises(controller.SafetyViolation):
            self._resume()
        self.assertEqual(self.reservations.reserve_packet_calls, calls)

    def test_resume_rejects_production_path_for_reconciled_id(self):
        self._strand()
        self._seed_claims()
        (self.repo / "assets" / "stories" / "traditional" / "3000").mkdir()
        with self.assertRaises(controller.IntegrationError):
            self._resume()

    def test_five_existing_claims_reconcile_without_new_reservation_call(self):
        self._strand()
        self._seed_claims()
        calls = self.reservations.reserve_packet_calls
        packet = self._resume()
        self.assertEqual(packet["state"], controller.ID_RESERVED)
        self.assertEqual(self.reservations.reserve_packet_calls, calls)

    def test_four_existing_claims_are_refused(self):
        self._strand()
        self._seed_claims(4)
        with self.assertRaises(controller.IntegrationError):
            self._resume()

    def test_six_existing_claims_are_refused(self):
        self._strand()
        self._seed_claims(6)
        with self.assertRaises(controller.IntegrationError):
            self._resume()

    def test_claim_with_conflicting_packet_is_refused(self):
        self._strand()
        self._seed_claims()
        current = self.reservations.states[3004]
        self.reservations.states[3004] = dataclasses.replace(current, packet_id="other-packet")
        with self.assertRaises(controller.IntegrationError):
            self._resume()

    def test_claim_token_or_ownership_inconsistency_is_refused(self):
        self._strand()
        self._seed_claims()
        current = self.reservations.states[3000]
        self.reservations.states[3000] = dataclasses.replace(current, lease_token="")
        with self.assertRaises(controller.ControllerError):
            self._resume()

    def test_materialized_claim_while_controller_planned_is_refused(self):
        self._strand()
        self._seed_claims()
        current = self.reservations.states[3000]
        self.reservations.states[3000] = dataclasses.replace(current, state="MATERIALIZED")
        with self.assertRaises(controller.IntegrationError):
            self._resume()

    def test_reservation_failure_before_claim_leaves_replayable_planned(self):
        self._strand()
        self.reservations.fail_reserve_before_once = True
        with self.assertRaises(RuntimeError):
            self._resume()
        self.assertEqual(self.controller.load(self.run_id, self.packet_id)["state"], controller.PLANNED)
        self.assertEqual(len(self._events()), 1)

    def test_retry_after_reservation_failure_succeeds(self):
        self._strand()
        self.reservations.fail_reserve_before_once = True
        with self.assertRaises(RuntimeError):
            self._resume()
        packet = self._resume()
        self.assertEqual(packet["state"], controller.ID_RESERVED)

    def test_partial_failure_relies_on_reservation_api_rollback_state(self):
        self._strand()
        self.reservations.fail_reserve_partial_once = True
        with self.assertRaisesRegex(RuntimeError, "after API rollback"):
            self._resume()
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(packet["state"], controller.PLANNED)
        self.assertEqual(self.reservations.states[3000].state, "RELEASED")
        self.assertEqual(len(self._events()), 1)

    def test_repeated_resume_after_id_reserved_is_typed_refusal(self):
        self._strand()
        self._resume()
        with self.assertRaises(controller.IllegalControllerTransition):
            self._resume()

    def test_exact_old_permission_defect_can_be_privatized_and_resumed(self):
        self._strand()
        runtime_dirs = []
        for root, dirs, _files in os.walk(self.factory):
            runtime_dirs.append(pathlib.Path(root))
            runtime_dirs.extend(pathlib.Path(root) / name for name in dirs)
        for path in runtime_dirs:
            os.chmod(path, 0o755)
        with self.assertRaises(controller.SafetyViolation):
            self._resume()
        proof = self.controller.privatize_planned_runtime(
            run_id=self.run_id, packet_id=self.packet_id, actor=self.actor,
            planning=self.planning(),
        )
        self.assertEqual(proof["status"], "PRIVATE_RUNTIME_READY")
        for path in runtime_dirs:
            self._assert_mode(path, 0o700)
        packet = self._resume()
        self.assertEqual(packet["state"], controller.ID_RESERVED)
        event_types = [event["eventType"] for event in self._events()]
        self.assertEqual(event_types.count("PACKET_PLANNED"), 1)
        self.assertEqual(event_types.count("IDS_RESERVED"), 1)

    def test_resume_cli_can_explicitly_privatize_before_resume(self):
        planning_path = self.base / "resume-planning.json"
        planning_path.write_text(json.dumps(self.planning()), encoding="utf-8")
        fake = mock.Mock()
        fake.resume_planned_packet.return_value = {"state": controller.ID_RESERVED}
        fake.preflight_anchors.return_value = {"state": controller.ANCHOR_PREFLIGHT_PASSED}
        argv = [
            "resume-planned", "--run-id", self.run_id, "--packet-id", self.packet_id,
            "--actor", self.actor, "--repo-root", str(self.repo), "--worktree", str(self.repo),
            "--factory-home", str(self.factory), "--planning", str(planning_path),
            "--privatize-runtime",
        ]
        with mock.patch.object(controller, "_cli_controller", return_value=fake), \
                mock.patch.object(controller, "_print_json") as print_json:
            self.assertEqual(controller.main(argv), 0)
        fake.privatize_planned_runtime.assert_called_once()
        fake.resume_planned_packet.assert_called_once()
        fake.preflight_anchors.assert_called_once_with(
            self.run_id, self.packet_id, actor=self.actor,
        )
        print_json.assert_called_once_with({
            "status": "OK", "packet": {"state": controller.ANCHOR_PREFLIGHT_PASSED},
        })


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


class LeaseRenewalTests(ControllerTestCase):
    def _events(self):
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        return [json.loads(line) for line in journal.read_text().splitlines()]

    def test_new_packet_default_requests_24_hour_production_lease(self):
        self.controller.plan_packet(
            run_id=self.run_id,
            packet_id=self.packet_id,
            actor=self.actor,
            planning=self.planning(),
        )
        self.assertEqual(
            self.reservations.reserve_lease_seconds,
            [controller.PRODUCTION_LEASE_SECONDS],
        )
        self.assertEqual(controller.PRODUCTION_LEASE_SECONDS, 24 * 60 * 60)

    def test_planned_resume_default_requests_24_hour_production_lease(self):
        self.reservations.fail_reserve_before_once = True
        with self.assertRaises(RuntimeError):
            self.controller.plan_packet(
                run_id=self.run_id,
                packet_id=self.packet_id,
                actor=self.actor,
                planning=self.planning(),
            )
        self.controller.resume_planned_packet(
            run_id=self.run_id,
            packet_id=self.packet_id,
            actor=self.actor,
            planning=self.planning(),
        )
        self.assertEqual(
            self.reservations.reserve_lease_seconds[-1],
            controller.PRODUCTION_LEASE_SECONDS,
        )

    def test_assignment_ready_renews_exactly_five_without_state_change(self):
        before = self.assignments()
        assignment_hash = before["evidenceHashes"]["assignments"]
        packet = self.controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
        )
        self.assertEqual(packet["state"], controller.ASSIGNMENT_READY)
        self.assertEqual(set(self.reservations.renew_updates), set(range(3000, 3005)))
        self.assertTrue(all(count == 1 for count in self.reservations.renew_updates.values()))
        self.assertEqual(packet["evidenceHashes"]["assignments"], assignment_hash)
        self.assertIn("leaseRenewalRound1", packet["evidenceHashes"])
        self.assertEqual(self._events()[-1]["eventType"], "PACKET_LEASE_RENEWED")
        self.assertEqual(self._events()[-1]["fromState"], controller.ASSIGNMENT_READY)
        self.assertEqual(self._events()[-1]["toState"], controller.ASSIGNMENT_READY)

    def test_expired_assignment_ready_requires_explicit_recovery_flag(self):
        before = self.assignments()
        tokens = [slot["reservation"]["leaseToken"] for slot in before["slots"]]
        self.fixed_now += dt.timedelta(minutes=2)
        with self.assertRaisesRegex(controller.IntegrationError, "recover-expired"):
            self.controller.renew_packet_lease(
                self.run_id,
                self.packet_id,
                actor=self.actor,
            )
        self.assertEqual(self.reservations.renew_calls, [])
        packet = self.controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
            recover_expired=True,
        )
        self.assertEqual(packet["state"], controller.ASSIGNMENT_READY)
        self.assertEqual(
            [slot["reservation"]["leaseToken"] for slot in packet["slots"]],
            tokens,
        )
        self.assertTrue(all(
            dt.datetime.fromisoformat(
                slot["reservation"]["leaseExpiresAt"].replace("Z", "+00:00")
            ) > self.fixed_now
            for slot in packet["slots"]
        ))

    def test_partial_packet_failure_reconciles_without_duplicate_renewal(self):
        self.assignments()
        self.fixed_now += dt.timedelta(minutes=2)
        self.reservations.fail_renew_story_id_once = 3002
        with self.assertRaisesRegex(controller.IntegrationError, "story 3002"):
            self.controller.renew_packet_lease(
                self.run_id,
                self.packet_id,
                actor=self.actor,
                recover_expired=True,
            )
        self.assertEqual(self.reservations.renew_updates, {3000: 1, 3001: 1})
        self.assertNotIn("PACKET_LEASE_RENEWED", [event["eventType"] for event in self._events()])
        packet = self.controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
            recover_expired=True,
        )
        self.assertEqual(packet["state"], controller.ASSIGNMENT_READY)
        self.assertEqual(
            self.reservations.renew_updates,
            {story_id: 1 for story_id in range(3000, 3005)},
        )
        self.assertEqual(
            [event["eventType"] for event in self._events()].count("PACKET_LEASE_RENEWED"),
            1,
        )

    def test_repeated_packet_renewal_is_replayable(self):
        self.assignments()
        first = self.controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
        )
        self.fixed_now += dt.timedelta(minutes=1)
        second = self.controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
        )
        self.assertEqual(second["state"], controller.ASSIGNMENT_READY)
        self.assertIn("leaseRenewalRound1", first["evidenceHashes"])
        self.assertIn("leaseRenewalRound2", second["evidenceHashes"])
        self.assertEqual(
            self.controller.load(self.run_id, self.packet_id),
            second,
        )

    def test_wrong_actor_and_materialized_claims_are_rejected(self):
        self.assignments()
        with self.assertRaises(controller.IntegrationError):
            self.controller.renew_packet_lease(
                self.run_id,
                self.packet_id,
                actor="other-owner",
            )

        self.controller.ingest_writer_output(
            self.run_id,
            self.packet_id,
            source_root=self.write_outputs(),
            actor=self.actor,
        )
        self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        with self.assertRaisesRegex(controller.IntegrationError, "not RESERVED"):
            self.controller.renew_packet_lease(
                self.run_id,
                self.packet_id,
                actor=self.actor,
            )

    def test_review_ready_is_policy_eligible_when_claims_remain_reserved(self):
        packet = copy.deepcopy(self.assignments())
        packet["state"] = controller.REVIEW_READY
        for slot in packet["slots"]:
            slot["state"] = controller.REVIEW_READY
        with mock.patch.object(self.controller, "load", return_value=packet), \
                mock.patch.object(
                    self.controller,
                    "_record",
                    side_effect=lambda _prior, updated, **_kwargs: updated,
                ):
            renewed = self.controller.renew_packet_lease(
                self.run_id,
                self.packet_id,
                actor=self.actor,
            )
        self.assertEqual(renewed["state"], controller.REVIEW_READY)

    def test_terminal_state_is_ineligible(self):
        packet = copy.deepcopy(self.assignments())
        packet["state"] = controller.READY_FOR_HUMAN_REVIEW
        for slot in packet["slots"]:
            slot["state"] = controller.READY_FOR_HUMAN_REVIEW
        with mock.patch.object(self.controller, "load", return_value=packet):
            with self.assertRaises(controller.IllegalControllerTransition):
                self.controller.renew_packet_lease(
                    self.run_id,
                    self.packet_id,
                    actor=self.actor,
                )

    def test_cli_requires_explicit_recover_expired_flag(self):
        fake = mock.Mock()
        fake.renew_packet_lease.return_value = {"state": controller.ASSIGNMENT_READY}
        argv = [
            "renew-packet-lease",
            "--run-id", self.run_id,
            "--packet-id", self.packet_id,
            "--actor", self.actor,
            "--repo-root", str(self.repo),
            "--worktree", str(self.repo),
            "--factory-home", str(self.factory),
            "--recover-expired",
        ]
        with mock.patch.object(controller, "_cli_controller", return_value=fake), \
                mock.patch.object(controller, "_print_json") as print_json:
            self.assertEqual(controller.main(argv), 0)
        fake.renew_packet_lease.assert_called_once_with(
            self.run_id,
            self.packet_id,
            actor=self.actor,
            recover_expired=True,
            lease_seconds=float(controller.PRODUCTION_LEASE_SECONDS),
        )
        print_json.assert_called_once_with({
            "status": "OK",
            "packet": {"state": controller.ASSIGNMENT_READY},
        })

    def test_real_packet_shaped_expired_fixture_renews_without_reallocation(self):
        mutable_now = [self.fixed_now]
        real_controller = controller.AutonomousStoryController(
            repo_root=self.repo,
            worktree=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            policy_root=REPO_ROOT,
            reservations=controller.reservation_service,
            overlap_evaluator=self.overlap,
            clock=lambda: mutable_now[0],
        )
        original_reserve_packet = controller.reservation_service.reserve_packet

        def reserve_expiring_packet(**kwargs):
            kwargs["lease_seconds"] = 1
            kwargs["now"] = self.fixed_now
            return original_reserve_packet(**kwargs)

        with mock.patch.object(
            controller.reservation_service,
            "reserve_packet",
            side_effect=reserve_expiring_packet,
        ):
            real_controller.plan_packet(
                run_id=self.run_id,
                packet_id=self.packet_id,
                actor=self.actor,
                planning=self.planning(),
            )
        real_controller.preflight_anchors(
            self.run_id,
            self.packet_id,
            actor=self.actor,
        )
        assignment_ready = real_controller.emit_writer_assignments(
            self.run_id,
            self.packet_id,
            actor=self.actor,
        )
        original_tokens = [
            slot["reservation"]["leaseToken"]
            for slot in assignment_ready["slots"]
        ]
        assignment_hash = assignment_ready["evidenceHashes"]["assignments"]
        mutable_now[0] = self.fixed_now + dt.timedelta(seconds=2)
        renewed = real_controller.renew_packet_lease(
            self.run_id,
            self.packet_id,
            actor=self.actor,
            recover_expired=True,
        )
        self.assertEqual(renewed["state"], controller.ASSIGNMENT_READY)
        self.assertEqual(
            [slot["storyId"] for slot in renewed["slots"]],
            list(range(3000, 3005)),
        )
        self.assertEqual(
            [slot["reservation"]["leaseToken"] for slot in renewed["slots"]],
            original_tokens,
        )
        self.assertEqual(renewed["evidenceHashes"]["assignments"], assignment_hash)
        ledger_events = [
            json.loads(line)
            for line in (self.factory / "reservations.jsonl").read_text().splitlines()
        ]
        self.assertEqual(
            [event["eventType"] for event in ledger_events].count("RESERVED"),
            5,
        )
        self.assertEqual(
            [event["eventType"] for event in ledger_events].count("RENEWED"),
            5,
        )
        source = self.write_outputs(
            renewed,
            root=self.base / "real-shaped-writer-output",
        )
        ingested = real_controller.ingest_writer_output(
            self.run_id,
            self.packet_id,
            source_root=source,
            actor=self.actor,
        )
        self.assertEqual(ingested["state"], controller.WRITER_OUTPUT_RECEIVED)


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


class OverlapQueueProjectionTests(ControllerTestCase):
    """F1: pin the ``materialized`` -> ``locked`` repair to the emitted literal.

    Before this repair the controller emitted the string ``"materialized"``,
    which is outside the gate's vocabulary and was silently discarded -- so a
    materialized story occupied nothing in the queue.  Asserting only that the
    gate happens to BLOCK would not have caught it, because ``harvest()`` finds
    materialized stories on disk independently.  That masking is
    configuration-dependent: it disappears the moment a sibling packet runs in
    a worktree this controller was not given.  So these tests assert the
    emitted STRING, never merely the verdict.
    """

    def _snapshot(self):
        packet = self.plan()
        path = self.controller._overlap_queue_snapshot(packet)
        return json.loads(path.read_text(encoding="utf-8")), packet

    def test_reserved_projects_reserved(self):
        payload, _ = self._snapshot()
        self.assertEqual(len(payload["reservations"]), 5)
        for row in payload["reservations"]:
            self.assertEqual(row["state"], "reserved")

    def test_materialized_emits_the_literal_locked(self):
        payload, packet = self._snapshot()
        for slot in packet["slots"]:
            reservation = self.reservations.states[slot["storyId"]]
            self.reservations.states[slot["storyId"]] = dataclasses.replace(
                reservation, state="MATERIALIZED",
            )
        path = self.controller._overlap_queue_snapshot(packet)
        payload = json.loads(path.read_text(encoding="utf-8"))
        states = [row["state"] for row in payload["reservations"]]
        self.assertEqual(states, ["locked"] * 5)
        self.assertNotIn("materialized", states)
        self.assertNotIn("materialized", path.read_text(encoding="utf-8"))

    def test_retired_projects_the_literal_locked(self):
        # ``_authoritative_reservations`` refuses anything but RESERVED and
        # MATERIALIZED, so RETIRED cannot reach the snapshot today.  The
        # projection must still be total: if that guard ever widens, RETIRED
        # must already be a permanent occupancy rather than a silent omission.
        self.assertEqual(
            controller.AutonomousStoryController.reservation_to_queue_state("RETIRED"),
            "locked",
        )

    def test_every_emitted_state_is_in_the_gate_vocabulary(self):
        for state in ("RESERVED", "MATERIALIZED", "RETIRED"):
            with self.subTest(state=state):
                projected = controller.AutonomousStoryController.reservation_to_queue_state(state)
                self.assertIn(projected, controller.overlap_gate.KNOWN_QUEUE_STATES)
                self.assertIn(projected, controller.overlap_gate.OCCUPYING_STATES)

    def test_released_projects_to_omission_not_to_an_unknown_state(self):
        # Omission here is a decision, not a default: a RELEASED reservation is
        # genuinely free.  It is expressed as None so the snapshot drops the
        # row, never as a string the gate would have to interpret.
        self.assertIsNone(
            controller.AutonomousStoryController.reservation_to_queue_state("RELEASED")
        )

    def test_snapshot_only_ever_emits_occupying_states(self):
        payload, packet = self._snapshot()
        emitted = {row["state"] for row in payload["reservations"]}
        for slot in packet["slots"]:
            reservation = self.reservations.states[slot["storyId"]]
            self.reservations.states[slot["storyId"]] = dataclasses.replace(
                reservation, state="MATERIALIZED",
            )
        path = self.controller._overlap_queue_snapshot(packet)
        emitted |= {row["state"] for row
                    in json.loads(path.read_text(encoding="utf-8"))["reservations"]}
        self.assertEqual(emitted, {"reserved", "locked"})
        self.assertTrue(emitted <= controller.overlap_gate.OCCUPYING_STATES)

    def test_projection_has_no_default_branch(self):
        with self.assertRaises(controller.IntegrationError):
            controller.AutonomousStoryController.reservation_to_queue_state("ABANDONED")
        with self.assertRaises(controller.IntegrationError):
            controller.AutonomousStoryController.reservation_to_queue_state("materialized")

    def test_projection_is_total_over_the_reservation_services_states(self):
        # If the reservation service ever adds a state, this fails rather than
        # letting the new state vanish from the queue.
        service_states = set(controller.reservation_service._STATES)
        mapped = set(controller.AutonomousStoryController.RESERVATION_QUEUE_PROJECTION)
        self.assertEqual(service_states, mapped)


class AclQueueProjectionTests(ControllerTestCase):
    """The controller reads global occupancy, not just its own five slots."""

    def test_acl_queue_is_empty_without_a_ledger(self):
        self.assertEqual(self.controller.acl_queue_rows(), [])

    def test_acl_rows_reach_the_gate_vocabulary(self):
        import anchor_claims
        result = anchor_claims.claim_packet_anchors(
            run_id="other-run", packet_id="other-packet",
            proposals=[{"slotId": i + 1, "anchor": a}
                       for i, a in enumerate(
                           ("Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10",
                            "Obadiah 1:1-9", "Micah 1:1-9"))],
            actor="owner", factory_home=self.factory,
        )
        rows = self.controller.acl_queue_rows()
        self.assertEqual(len(rows), 5)
        for row in rows:
            self.assertEqual(row["state"], "reserved")
            self.assertLess(row["storyId"], 0)
            self.assertIn(row["state"], controller.overlap_gate.KNOWN_QUEUE_STATES)
        self.assertEqual(
            self.controller.acl_queue_rows(
                exclude_packet=("other-run", "other-packet")),
            [],
        )


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
            self.assertEqual(
                slot["materialization"]["nonAuthoritativePreservedFileHashes"], {},
            )

    def test_manifest_is_unchanged_across_materialization(self):
        before = controller._hash_file(self.repo / "assets" / "stories" / "manifest.json")
        self.materialized()
        after = controller._hash_file(self.repo / "assets" / "stories" / "manifest.json")
        self.assertEqual(before, after)

    def test_audio_is_absent_after_materialization(self):
        self.materialized()
        self.assertEqual(list(self.repo.rglob("*.mp3")), [])

    def test_validation_preserves_initial_overlap_snapshot_and_binds_fresh_snapshot(self):
        self.ingested()
        initial = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "overlap_queue_snapshot.json"
        )
        historical = b'{"historical":"initial-preflight-evidence"}\n'
        initial.write_bytes(historical)
        packet = self.controller.validate_outputs(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertEqual(initial.read_bytes(), historical)
        fresh = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "overlap" / "validation" / "round-0" / "queue_snapshot.json"
        )
        self.assertTrue(fresh.is_file())
        reference = packet["slots"][0]["validationEvidence"]["overlapQueueSnapshot"]
        self.assertEqual(reference["path"], "overlap/validation/round-0/queue_snapshot.json")
        self.assertEqual(reference["hash"], controller._hash_value(json.loads(fresh.read_text())))

    def test_final_readiness_preserves_initial_overlap_snapshot(self):
        self.review_ready()
        self.controller.ingest_review(
            self.run_id, self.packet_id, review=self.review("APPROVED"), actor=self.actor,
        )
        initial = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "overlap_queue_snapshot.json"
        )
        historical = b'{"historical":"initial-preflight-evidence"}\n'
        initial.write_bytes(historical)
        packet = self.controller.mark_ready_for_human_review(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertEqual(initial.read_bytes(), historical)
        fresh = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "overlap" / "final-readiness" / "round-0" / "queue_snapshot.json"
        )
        self.assertTrue(fresh.is_file())
        self.assertEqual(
            packet["slots"][0]["finalReadiness"]["overlapQueueSnapshot"]["hash"],
            controller._hash_value(json.loads(fresh.read_text())),
        )


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


FULL_FINDING = "length band full is not supported by the passage"
LONG_FINDING = "length band long is not supported by the passage"
SHORT_FINDING = "length band short is not supported by the passage"


class LengthReclassificationTestCase(ControllerTestCase):
    """Harness for ADR-030 owner-authorized length reclassification.

    Plans a three-bucket packet, drives it to REVIEW_CHANGES_REQUESTED with
    real length-support findings, and builds a valid owner attestation bound to
    the evidence the controller actually recorded.
    """

    THREE = ["short", "full", "long"]

    def planning(self, *, count=5, narrator="VOICE_SARAH_STORYTELLER"):
        return {
            "stories": [
                {
                    "proposedAnchor": ANCHORS[index],
                    "mood": "encouraging",
                    "narrator": narrator,
                    "lengths": list(self.THREE),
                }
                for index in range(count)
            ]
        }

    def changes_requested(self, findings_by_id=None):
        self.review_ready()
        packet = self.controller.load(self.run_id, self.packet_id)
        default = ["Revise bounded detail."]
        review = {"stories": [
            {"storyId": slot["storyId"], "verdict": "CHANGES_REQUESTED",
             "findings": list((findings_by_id or {}).get(slot["storyId"], default))}
            for slot in packet["slots"]
        ]}
        return self.controller.ingest_review(
            self.run_id, self.packet_id, review=review, actor=self.actor,
        )

    def attestation(self, packet=None, **over):
        packet = packet or self.controller.load(self.run_id, self.packet_id)
        attempts = max(slot["writerAttempts"] for slot in packet["slots"])
        value = {
            "reviewerRole": "Claude Window 3 (reviewer)",
            "writerOrRepairerRole": "Codex Window 1 (writer)",
            "differentActorsAttestedByOwner": True,
            "ownerActor": packet["actor"],
            "reviewEvidenceSha256":
                packet["evidenceHashes"][f"reviewVerdictsRound{packet['reviewRound']}"],
            "writerEvidenceSha256":
                packet["evidenceHashes"][f"writerOutputAttempt{attempts}"],
        }
        value.update(over)
        return value

    def request(self, story_id, to_lengths, findings, *, from_lengths=None,
                rationale="anchor does not support the removed band"):
        packet = self.controller.load(self.run_id, self.packet_id)
        slot = next(s for s in packet["slots"] if s["storyId"] == story_id)
        return {
            "storyId": story_id,
            "fromLengths": list(from_lengths if from_lengths is not None
                                else slot["targetLengths"]),
            "toLengths": list(to_lengths),
            "removedBucketFindings": findings,
            "rationale": rationale,
        }

    def finding_map(self, story_id, buckets):
        packet = self.controller.load(self.run_id, self.packet_id)
        slot = next(s for s in packet["slots"] if s["storyId"] == story_id)
        out = {}
        for bucket in buckets:
            text = f"length band {bucket} is not supported by the passage"
            out[bucket] = {"findingIndex": slot["unresolvedFindings"].index(text),
                           "findingText": text}
        return out

    _DEFAULT = object()

    def reclassify(self, reclassifications, *, attestation=_DEFAULT, actor=None,
                   owner_authorized=True):
        # A sentinel, not None: several tests must pass None as the attestation
        # and see it refused, which a None-means-default helper cannot express.
        if attestation is self._DEFAULT:
            attestation = self.attestation()
        return self.controller.reclassify_story_lengths(
            self.run_id, self.packet_id,
            actor=actor if actor is not None else self.actor,
            reclassifications=reclassifications,
            reviewer_attestation=attestation,
            owner_authorized=owner_authorized,
        )

    def journal_bytes(self):
        return (self.controller.packet_dir(self.run_id, self.packet_id)
                / "events.jsonl").read_bytes()

    def drop_long(self, story_id):
        """The story-3001 shape: short/full/long -> short/full."""
        self.changes_requested({story_id: [LONG_FINDING]})
        return self.request(story_id, ["short", "full"],
                            self.finding_map(story_id, ["long"]))

    def drop_full_and_long(self, story_id):
        """The story-3003 shape: short/full/long -> short, two findings."""
        self.changes_requested({story_id: [FULL_FINDING, LONG_FINDING]})
        return self.request(story_id, ["short"],
                            self.finding_map(story_id, ["full", "long"]))


class LengthReclassificationHappyPathTests(LengthReclassificationTestCase):

    def test_row_43_long_only_removal_passes(self):
        request = self.drop_long(3001)
        packet = self.reclassify([request])
        slot = next(s for s in packet["slots"] if s["storyId"] == 3001)
        self.assertEqual(slot["targetLengths"], ["short", "full"])
        self.assertEqual(
            len(controller.expected_artifact_names(3001, slot["targetLengths"])), 9)

    def test_row_44_full_and_long_removal_with_both_findings_passes(self):
        request = self.drop_full_and_long(3003)
        packet = self.reclassify([request])
        slot = next(s for s in packet["slots"] if s["storyId"] == 3003)
        self.assertEqual(slot["targetLengths"], ["short"])
        self.assertEqual(
            len(controller.expected_artifact_names(3003, slot["targetLengths"])), 7)

    def test_row_42_status_literal_in_evidence_and_event_reason(self):
        request = self.drop_long(3001)
        self.reclassify([request])
        evidence = json.loads((
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "reclassifications" / "round-1" / "story_3001.json"
        ).read_text())
        self.assertEqual(evidence["separationStatus"],
                         "REVIEWER_SEPARATION_OWNER_ATTESTED_NOT_MACHINE_PROVEN")
        journal = self.journal_bytes().decode().splitlines()
        event = json.loads(journal[-1])
        self.assertEqual(event["eventType"], "STORY_LENGTHS_RECLASSIFIED")
        self.assertIn("REVIEWER_SEPARATION_OWNER_ATTESTED_NOT_MACHINE_PROVEN",
                      event["reason"])
        self.assertEqual(event["fromState"], event["toState"])

    def test_evidence_records_raw_roles_and_omission_semantics(self):
        request = self.drop_full_and_long(3003)
        self.reclassify([request])
        evidence = json.loads((
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "reclassifications" / "round-1" / "story_3003.json"
        ).read_text())
        self.assertEqual(evidence["reviewerAttestation"]["reviewerRole"],
                         "Claude Window 3 (reviewer)")
        self.assertEqual(evidence["reviewerAttestation"]["writerOrRepairerRole"],
                         "Codex Window 1 (writer)")
        self.assertTrue(evidence["omissionIsNotDeletion"])
        self.assertEqual(evidence["removedLengths"], ["full", "long"])
        self.assertEqual(evidence["retainedArtifactCount"], 7)
        self.assertEqual(len(evidence["removedArtifacts"]), 4)
        self.assertEqual(evidence["adr"], "ADR-030")

    def test_correction_round_is_not_consumed(self):
        packet_before = self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        packet = self.reclassify([request])
        self.assertEqual(packet["correctionRound"], packet_before["correctionRound"])
        self.assertEqual(packet["reviewRound"], packet_before["reviewRound"])
        self.assertEqual(packet["state"], controller.REVIEW_CHANGES_REQUESTED)

    def test_subsequent_emit_corrections_uses_the_reduced_set(self):
        request = self.drop_full_and_long(3003)
        self.reclassify([request])
        packet = self.controller.emit_corrections(
            self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(packet["correctionRound"], 1)
        assignment = json.loads((
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "corrections" / "round-1" / "story_3003.json").read_text())
        expected = set(controller.expected_artifact_names(3003, ["short"]))
        names = {value for value in assignment.values() if isinstance(value, str)}
        listed = {name for value in assignment.values() if isinstance(value, list)
                  for name in value if isinstance(name, str)}
        self.assertTrue(expected <= (names | listed),
                        f"correction assignment does not carry the reduced set: {assignment}")
        self.assertNotIn(f"story_3003_traditional_web_long.txt", names | listed)

    def test_multiple_stories_in_one_event(self):
        self.changes_requested({3001: [LONG_FINDING],
                                3003: [FULL_FINDING, LONG_FINDING]})
        packet = self.reclassify([
            self.request(3001, ["short", "full"], self.finding_map(3001, ["long"])),
            self.request(3003, ["short"], self.finding_map(3003, ["full", "long"])),
        ])
        by_id = {s["storyId"]: s for s in packet["slots"]}
        self.assertEqual(by_id[3001]["targetLengths"], ["short", "full"])
        self.assertEqual(by_id[3003]["targetLengths"], ["short"])
        # non-target stories unchanged
        for story_id in (3000, 3002, 3004):
            self.assertEqual(by_id[story_id]["targetLengths"], self.THREE)

    def test_snapshot_equals_replay(self):
        request = self.drop_long(3001)
        packet = self.reclassify([request])
        replayed = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(replayed, packet)


class LengthReclassificationAuthorizationTests(LengthReclassificationTestCase):

    def test_no_owner_authorization_is_refused(self):
        request = self.drop_long(3001)
        before = self.journal_bytes()
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], owner_authorized=False)
        self.assertEqual(self.journal_bytes(), before)

    def test_owner_authorized_must_be_literal_true(self):
        request = self.drop_long(3001)
        for truthy in (1, "true", "yes", [1], {"a": 1}):
            with self.subTest(value=truthy):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], owner_authorized=truthy)

    def test_actor_mismatch_is_refused(self):
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], actor="claude")

    def test_row_39_missing_or_malformed_attestation_is_refused(self):
        request = self.drop_long(3001)
        before = self.journal_bytes()
        for bad in (None, "attested", 42, [], {},
                    {"reviewerRole": "a"},
                    dict(self.attestation(), extra="x")):
            with self.subTest(attestation=repr(bad)[:40]):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=bad)
        missing = self.attestation()
        del missing["ownerActor"]
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], attestation=missing)
        self.assertEqual(self.journal_bytes(), before)

    def test_different_actors_flag_must_be_literal_true(self):
        request = self.drop_long(3001)
        for value in (False, 1, "true", None):
            with self.subTest(value=value):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=self.attestation(
                        differentActorsAttestedByOwner=value))

    def test_owner_actor_must_equal_packet_owner(self):
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request],
                            attestation=self.attestation(ownerActor="claude"))

    def test_row_40_identical_roles_are_refused(self):
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], attestation=self.attestation(
                reviewerRole="Claude Window 2",
                writerOrRepairerRole="Claude Window 2"))

    def test_row_40_roles_differing_only_by_case_or_whitespace_are_refused(self):
        request = self.drop_long(3001)
        for reviewer, writer in (
            ("Claude Window 2", "claude  window 2"),
            ("Claude Window 2", "  CLAUDE WINDOW 2  "),
            ("codex", "CODEX"),
            ("a  b", "a b"),
        ):
            with self.subTest(reviewer=reviewer, writer=writer):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=self.attestation(
                        reviewerRole=reviewer, writerOrRepairerRole=writer))

    def test_row_40_roles_differing_only_by_unicode_normalization_are_refused(self):
        # NFD "Cafe\u0301" and NFC "Café" are the same name; refusing them is
        # the safe direction, because two roles that differ only in Unicode
        # form are far more likely to be one person than two.
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], attestation=self.attestation(
                reviewerRole="Caf\u00e9 Reviewer",
                writerOrRepairerRole="Cafe\u0301 Reviewer"))

    def test_row_40_empty_or_whitespace_roles_are_refused(self):
        request = self.drop_long(3001)
        for role in ("", "   ", "\t\n", "\u00a0"):
            with self.subTest(role=repr(role)):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=self.attestation(
                        reviewerRole=role))

    def test_non_string_roles_are_refused(self):
        request = self.drop_long(3001)
        for role in (None, 7, ["a"], {"a": 1}):
            with self.subTest(role=repr(role)):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=self.attestation(
                        reviewerRole=role))

    def test_distinct_roles_are_accepted(self):
        request = self.drop_long(3001)
        packet = self.reclassify([request], attestation=self.attestation(
            reviewerRole="Claude Window 3", writerOrRepairerRole="Codex Window 1"))
        self.assertEqual(
            next(s for s in packet["slots"] if s["storyId"] == 3001)["targetLengths"],
            ["short", "full"])


class LengthReclassificationEvidenceBindingTests(LengthReclassificationTestCase):

    def test_row_41_malformed_evidence_hashes_are_refused(self):
        request = self.drop_long(3001)
        for field in ("reviewEvidenceSha256", "writerEvidenceSha256"):
            for bad in ("", "xyz", "A" * 64, "0" * 63, "0" * 65, None, 42,
                        "0" * 64):
                with self.subTest(field=field, value=repr(bad)[:24]):
                    with self.assertRaises(controller.ReviewRejected):
                        self.reclassify([request],
                                        attestation=self.attestation(**{field: bad}))

    def test_row_41_stale_review_verdicts_hash_is_refused(self):
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], attestation=self.attestation(
                reviewEvidenceSha256="b" * 64))

    def test_row_41_stale_writer_output_hash_is_refused(self):
        request = self.drop_long(3001)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request], attestation=self.attestation(
                writerEvidenceSha256="c" * 64))

    def test_arbitrary_caller_selected_evidence_is_refused(self):
        # Any other recorded hash from the same packet -- real, well-formed,
        # and hash-chained -- is still refused, because the binding is to a
        # specific key, not to "some hash the controller has seen".
        request = self.drop_long(3001)
        packet = self.controller.load(self.run_id, self.packet_id)
        for key, value in packet["evidenceHashes"].items():
            if key.startswith("reviewVerdictsRound"):
                continue
            with self.subTest(key=key):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request], attestation=self.attestation(
                        reviewEvidenceSha256=value))

    def test_evidence_hashes_bind_to_the_current_review_round(self):
        request = self.drop_long(3001)
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(packet["reviewRound"], 1)
        attestation = self.attestation()
        self.assertEqual(attestation["reviewEvidenceSha256"],
                         packet["evidenceHashes"]["reviewVerdictsRound1"])
        self.reclassify([request], attestation=attestation)

    def test_writer_hash_binds_to_the_max_attempt(self):
        request = self.drop_long(3001)
        packet = self.controller.load(self.run_id, self.packet_id)
        attempts = max(slot["writerAttempts"] for slot in packet["slots"])
        self.assertEqual(
            self.attestation()["writerEvidenceSha256"],
            packet["evidenceHashes"][f"writerOutputAttempt{attempts}"])


class LengthReclassificationFindingTests(LengthReclassificationTestCase):

    def test_row_45_full_and_long_removal_with_long_finding_only_is_refused(self):
        # The V1 defect, pinned: story 3003 must not lose Full on a Long-only
        # finding.  This is the single most important test in the suite.
        self.changes_requested({3003: [LONG_FINDING]})
        request = self.request(3003, ["short"],
                               self.finding_map(3003, ["long"]))
        before = self.journal_bytes()
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])
        self.assertEqual(self.journal_bytes(), before)
        slot = next(s for s in self.controller.load(self.run_id, self.packet_id)["slots"]
                    if s["storyId"] == 3003)
        self.assertEqual(slot["targetLengths"], self.THREE)

    def test_missing_finding_for_a_removed_bucket_is_refused(self):
        self.changes_requested({3003: [FULL_FINDING, LONG_FINDING]})
        partial = self.finding_map(3003, ["long"])
        request = self.request(3003, ["short"], partial)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_row_47_extra_qualifying_finding_with_no_removed_bucket_is_refused(self):
        # Reviewer said Full is unsupported; the request removes only Long.
        # Silently ignoring the Full finding is exactly what rule 5 forbids.
        self.changes_requested({3001: [FULL_FINDING, LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_row_47_duplicate_finding_index_is_refused(self):
        self.changes_requested({3003: [FULL_FINDING, LONG_FINDING]})
        mapping = self.finding_map(3003, ["full", "long"])
        mapping["long"]["findingIndex"] = mapping["full"]["findingIndex"]
        mapping["long"]["findingText"] = mapping["full"]["findingText"]
        request = self.request(3003, ["short"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_row_51_paraphrased_finding_text_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        mapping = self.finding_map(3001, ["long"])
        mapping["long"]["findingText"] = "The long band is not supported by the passage"
        request = self.request(3001, ["short", "full"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_finding_text_must_be_byte_equal_even_when_predicate_matches(self):
        # A findingText that matches the predicate but is not the persisted
        # string is still refused: the reviewer's actual sentence is the
        # authority, not a well-formed sentence the caller composed.
        self.changes_requested({3001: [LONG_FINDING]})
        mapping = {"long": {"findingIndex": 0, "findingText": FULL_FINDING}}
        request = self.request(3001, ["short", "full"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_finding_naming_a_different_band_than_its_key_is_refused(self):
        self.changes_requested({3001: [FULL_FINDING]})
        mapping = {"long": {"findingIndex": 0, "findingText": FULL_FINDING}}
        request = self.request(3001, ["short", "full"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_row_46_map_naming_retained_short_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        mapping = self.finding_map(3001, ["long"])
        mapping["short"] = {"findingIndex": 0, "findingText": LONG_FINDING}
        request = self.request(3001, ["short", "full"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_row_46_short_finding_can_never_be_consumed(self):
        # short is not removable, so a "short is not supported" finding can
        # never correspond to a removed bucket.  The request must fail and the
        # contradiction reach the owner rather than being dropped.
        self.changes_requested({3001: [SHORT_FINDING, LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_finding_index_out_of_range_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        for index in (-1, 1, 99, True, 1.0, "0"):
            with self.subTest(index=repr(index)):
                mapping = {"long": {"findingIndex": index, "findingText": LONG_FINDING}}
                request = self.request(3001, ["short", "full"], mapping)
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request])

    def test_finding_entry_shape_is_exact(self):
        self.changes_requested({3001: [LONG_FINDING]})
        for entry in ({"findingIndex": 0}, {"findingText": LONG_FINDING},
                      {"findingIndex": 0, "findingText": LONG_FINDING, "x": 1},
                      "text", None, 0):
            with self.subTest(entry=repr(entry)[:40]):
                request = self.request(3001, ["short", "full"], {"long": entry})
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request])

    def test_finding_from_the_wrong_review_round_is_refused(self):
        # Round 1 recorded a Long finding; round 2 records only a generic one.
        # The stale round-1 text is no longer in unresolvedFindings, so citing
        # it fails on the byte-equality check.
        self.changes_requested({3001: [LONG_FINDING]})
        self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
        source = self.write_outputs()
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor)
        self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor)
        self.controller.emit_review_packet(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.load(self.run_id, self.packet_id)
        review = {"stories": [
            {"storyId": slot["storyId"], "verdict": "CHANGES_REQUESTED",
             "findings": ["Unrelated round two finding."]}
            for slot in packet["slots"]]}
        self.controller.ingest_review(
            self.run_id, self.packet_id, review=review, actor=self.actor)
        mapping = {"long": {"findingIndex": 0, "findingText": LONG_FINDING}}
        request = self.request(3001, ["short", "full"], mapping)
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])


class LengthReclassificationMoveTests(LengthReclassificationTestCase):

    def test_target_set_that_adds_a_bucket_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["short", "full", "long", "long"],
                               self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_non_subset_target_sets_are_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        for target in (["short", "long"], ["full", "long"], ["long"], [],
                       ["short", "full", "long"], ["full"], ["short", "medium"]):
            with self.subTest(target=target):
                request = self.request(3001, target,
                                       self.finding_map(3001, ["long"]))
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request])

    def test_short_is_never_removable(self):
        self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["full"], self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_stale_from_lengths_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]),
                               from_lengths=["short", "full"])
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_non_tail_target_is_refused_by_the_truncation_rule_alone(self):
        # Isolating test.  With a `full` finding recorded and `["short","long"]`
        # requested, removed == ["full"] and the finding map is complete and
        # consistent -- so the ONLY rule that can refuse this is the tail
        # truncation predicate.  Without it, a non-tail set would install.
        self.changes_requested({3001: [FULL_FINDING]})
        request = self.request(3001, ["short", "long"],
                               self.finding_map(3001, ["full"]))
        before = self.journal_bytes()
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])
        self.assertEqual(self.journal_bytes(), before)
        slot = next(s for s in self.controller.load(self.run_id, self.packet_id)["slots"]
                    if s["storyId"] == 3001)
        self.assertEqual(slot["targetLengths"], self.THREE)

    def test_removing_only_a_middle_band_is_refused(self):
        # short/full/long -> short/long removes Full but keeps Long, which the
        # bucket experience does not support: a story cannot offer a Long
        # without the Full beneath it.
        self.changes_requested({3001: [FULL_FINDING]})
        request = self.request(3001, ["short", "long"],
                               self.finding_map(3001, ["full"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_is_legal_downward_move_predicate(self):
        legal = [(["short", "full", "long"], ["short", "full"]),
                 (["short", "full", "long"], ["short"]),
                 (["short", "full"], ["short"])]
        illegal = [(["short", "full"], ["short", "full", "long"]),
                   (["short"], ["short", "full"]),
                   (["short", "full", "long"], []),
                   (["short", "full"], ["full"]),
                   (["short", "full", "long"], ["short", "long"]),
                   (["short"], ["short"]),
                   (["short", "full"], "short"),
                   ("short", ["short"])]
        for old, new in legal:
            self.assertTrue(controller.is_legal_downward_move(old, new), (old, new))
        for old, new in illegal:
            self.assertFalse(controller.is_legal_downward_move(old, new), (old, new))

    def test_wrong_packet_state_is_refused(self):
        self.review_ready()
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertEqual(packet["state"], controller.REVIEW_READY)
        slot = next(s for s in packet["slots"] if s["storyId"] == 3001)
        request = {"storyId": 3001, "fromLengths": list(slot["targetLengths"]),
                   "toLengths": ["short", "full"],
                   "removedBucketFindings": {
                       "long": {"findingIndex": 0, "findingText": LONG_FINDING}},
                   "rationale": "r"}
        with self.assertRaises(controller.IllegalControllerTransition):
            self.controller.reclassify_story_lengths(
                self.run_id, self.packet_id, actor=self.actor,
                reclassifications=[request],
                reviewer_attestation={
                    "reviewerRole": "r", "writerOrRepairerRole": "w",
                    "differentActorsAttestedByOwner": True,
                    "ownerActor": packet["actor"],
                    "reviewEvidenceSha256": "a" * 64,
                    "writerEvidenceSha256": "b" * 64,
                },
                owner_authorized=True)

    def test_unknown_story_id_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        request["storyId"] = 9999
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request])

    def test_request_shape_is_exact(self):
        self.changes_requested({3001: [LONG_FINDING]})
        base = self.request(3001, ["short", "full"], self.finding_map(3001, ["long"]))
        for mutate in (lambda r: r.pop("rationale"),
                       lambda r: r.update(extra=1),
                       lambda r: r.pop("removedBucketFindings")):
            with self.subTest():
                request = copy.deepcopy(base)
                mutate(request)
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request])
        for bad in ([], "x", None, {}):
            with self.subTest(payload=repr(bad)):
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify(bad)

    def test_empty_rationale_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        for rationale in ("", "   ", None, 7):
            with self.subTest(rationale=repr(rationale)):
                request = self.request(3001, ["short", "full"],
                                       self.finding_map(3001, ["long"]),
                                       rationale=rationale)
                with self.assertRaises(controller.ReviewRejected):
                    self.reclassify([request])

    def test_same_story_named_twice_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING]})
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([request, copy.deepcopy(request)])


class LengthReclassificationRetryTests(LengthReclassificationTestCase):

    def test_row_48_identical_retry_is_a_verifying_no_op(self):
        request = self.drop_long(3001)
        first = self.reclassify([request])
        journal = self.journal_bytes()
        second = self.reclassify([copy.deepcopy(request)])
        self.assertEqual(self.journal_bytes(), journal, "no duplicate append")
        self.assertEqual(second, first)

    def test_row_49_divergent_attestation_on_retry_is_refused(self):
        request = self.drop_long(3001)
        self.reclassify([request])
        journal = self.journal_bytes()
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([copy.deepcopy(request)],
                            attestation=self.attestation(
                                reviewerRole="Claude Window 9"))
        self.assertEqual(self.journal_bytes(), journal)

    def test_divergent_rationale_on_retry_is_refused(self):
        request = self.drop_long(3001)
        self.reclassify([request])
        journal = self.journal_bytes()
        diverged = copy.deepcopy(request)
        diverged["rationale"] = "a different reason"
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([diverged])
        self.assertEqual(self.journal_bytes(), journal)

    def test_matching_lengths_alone_never_conclude_a_no_op(self):
        # The whole point of hashing the payload rather than comparing lengths.
        request = self.drop_long(3001)
        self.reclassify([request])
        diverged = copy.deepcopy(request)
        diverged["fromLengths"] = ["short", "full"]
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([diverged])

    def test_repeated_bucket_removal_is_refused(self):
        request = self.drop_full_and_long(3003)
        self.reclassify([request])
        journal = self.journal_bytes()
        second = self.request(3003, ["short"], {}, from_lengths=["short"])
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([second])
        self.assertEqual(self.journal_bytes(), journal)

    def test_a_different_target_set_under_the_same_authority_is_refused(self):
        self.changes_requested({3001: [LONG_FINDING],
                                3003: [FULL_FINDING, LONG_FINDING]})
        self.reclassify([self.request(3003, ["short"],
                                      self.finding_map(3003, ["full", "long"]))])
        journal = self.journal_bytes()
        with self.assertRaises(controller.ReviewRejected):
            self.reclassify([self.request(3001, ["short", "full"],
                                          self.finding_map(3001, ["long"]))])
        self.assertEqual(self.journal_bytes(), journal)


class LengthReclassificationPreservationTests(LengthReclassificationTestCase):

    def _materialize_after_reclassification(self, request, *, mutate=None):
        self.reclassify([request])
        packet = self.controller.emit_corrections(
            self.run_id, self.packet_id, actor=self.actor,
        )
        changed = {slot["storyId"] for slot in packet["slots"] if slot["unresolvedFindings"]}
        source = self.write_outputs(
            packet, root=self.base / "reclassified-writer", only_ids=changed,
            mutate=mutate,
        )
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        return self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor,
        )

    def _production(self, story_id):
        return self.repo / "assets" / "stories" / "traditional" / str(story_id)

    def test_omission_does_not_delete_artifacts(self):
        request = self.drop_full_and_long(3003)
        packet_before = self.controller.load(self.run_id, self.packet_id)
        slot_before = next(s for s in packet_before["slots"] if s["storyId"] == 3003)
        production = self.controller.repo_root / slot_before["materialization"]["path"]
        before = sorted(p.name for p in production.iterdir())
        self.assertEqual(len(before), 11)
        self.reclassify([request])
        after = sorted(p.name for p in production.iterdir())
        self.assertEqual(before, after,
                         "reclassification must not delete any production file")
        workspace = self.controller._workspace_dir(packet_before, slot_before)
        self.assertEqual(len(sorted(workspace.iterdir())), 11)

    def test_materialization_evidence_is_retained(self):
        request = self.drop_full_and_long(3003)
        before = next(s for s in self.controller.load(self.run_id, self.packet_id)["slots"]
                      if s["storyId"] == 3003)["materialization"]
        packet = self.reclassify([request])
        after = next(s for s in packet["slots"] if s["storyId"] == 3003)["materialization"]
        self.assertEqual(before, after)
        self.assertEqual(len(after["fileHashes"]), 11)

    def test_short_full_materialization_preserves_historical_long_bytes(self):
        request = self.drop_long(3001)
        production = self._production(3001)
        authoritative_name = "story_3001_traditional_web_short.txt"
        authoritative_before = (production / authoritative_name).read_bytes()
        omitted = {
            name: (production / name).read_bytes()
            for name in (
                "story_3001_traditional_web_long.txt",
                "story_3001_traditional_kjv_long.txt",
            )
        }
        def update_authoritative(root, _packet):
            path = root / "3001" / authoritative_name
            path.write_text("At dawn " + path.read_text(), encoding="utf-8")

        self._materialize_after_reclassification(
            request, mutate=update_authoritative,
        )
        self.assertEqual(
            {name: (production / name).read_bytes() for name in omitted}, omitted,
        )
        self.assertNotEqual((production / authoritative_name).read_bytes(), authoritative_before)

    def test_short_materialization_preserves_historical_full_and_long_bytes(self):
        request = self.drop_full_and_long(3003)
        production = self._production(3003)
        omitted_names = {
            f"story_3003_traditional_{lane}_{length}.txt"
            for lane in controller.LANES for length in ("full", "long")
        }
        omitted = {name: (production / name).read_bytes() for name in omitted_names}
        self._materialize_after_reclassification(request)
        self.assertEqual(
            {name: (production / name).read_bytes() for name in omitted_names}, omitted,
        )

    def test_authoritative_materialization_evidence_excludes_preserved_files(self):
        request = self.drop_full_and_long(3003)
        packet = self._materialize_after_reclassification(request)
        slot = next(item for item in packet["slots"] if item["storyId"] == 3003)
        materialization = slot["materialization"]
        authoritative = set(controller.expected_artifact_names(3003, ["short"]))
        self.assertEqual(set(materialization["fileHashes"]), authoritative)
        self.assertEqual(
            set(materialization["nonAuthoritativePreservedFileHashes"]),
            {
                f"story_3003_traditional_{lane}_{length}.txt"
                for lane in controller.LANES for length in ("full", "long")
            },
        )
        self.assertTrue(authoritative.isdisjoint(
            materialization["nonAuthoritativePreservedFileHashes"],
        ))

    def test_repeat_materialization_preserves_historical_files_idempotently(self):
        request = self.drop_long(3001)
        first = self._materialize_after_reclassification(request)
        production = self._production(3001)
        omitted_names = {
            "story_3001_traditional_web_long.txt",
            "story_3001_traditional_kjv_long.txt",
        }
        before = {name: (production / name).read_bytes() for name in omitted_names}
        second = self.controller.materialize_for_review(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertEqual(
            {name: (production / name).read_bytes() for name in omitted_names}, before,
        )
        first_slot = next(item for item in first["slots"] if item["storyId"] == 3001)
        second_slot = next(item for item in second["slots"] if item["storyId"] == 3001)
        self.assertEqual(first_slot["materialization"], second_slot["materialization"])

    def test_identity_fields_are_immutable(self):
        request = self.drop_full_and_long(3003)
        before = next(s for s in self.controller.load(self.run_id, self.packet_id)["slots"]
                      if s["storyId"] == 3003)
        packet = self.reclassify([request])
        after = next(s for s in packet["slots"] if s["storyId"] == 3003)
        for field in ("proposedAnchor", "narrator", "mood", "lanes", "mode",
                      "kidFriendly", "reflectionForm", "storyId", "reservation",
                      "unresolvedFindings", "reviewerVerdict", "writerAttempts"):
            self.assertEqual(before[field], after[field], field)

    def test_non_target_stories_are_untouched(self):
        request = self.drop_long(3001)
        before = {s["storyId"]: copy.deepcopy(s)
                  for s in self.controller.load(self.run_id, self.packet_id)["slots"]}
        packet = self.reclassify([request])
        for slot in packet["slots"]:
            if slot["storyId"] == 3001:
                continue
            self.assertEqual(slot, before[slot["storyId"]])

    def test_prior_evidence_hashes_are_immutable(self):
        request = self.drop_long(3001)
        before = dict(self.controller.load(self.run_id, self.packet_id)["evidenceHashes"])
        packet = self.reclassify([request])
        for key, value in before.items():
            self.assertEqual(packet["evidenceHashes"][key], value, key)
        self.assertIn("lengthReclassificationReview1", packet["evidenceHashes"])

    def test_journal_prefix_is_preserved(self):
        request = self.drop_long(3001)
        before = self.journal_bytes()
        self.reclassify([request])
        after = self.journal_bytes()
        self.assertTrue(after.startswith(before))
        self.assertEqual(len(after.splitlines()), len(before.splitlines()) + 1)

    def test_round_1_verdicts_are_not_rewritten(self):
        request = self.drop_long(3001)
        verdicts = (self.controller.packet_dir(self.run_id, self.packet_id)
                    / "reviews" / "round-1" / "verdicts.json")
        before = verdicts.read_bytes()
        self.reclassify([request])
        self.assertEqual(verdicts.read_bytes(), before)

    def test_row_50_review_schema_is_untouched(self):
        # Asserted at REVIEW_READY, the only state where ingest_review is
        # reachable.  Nothing in this feature added a reviewer field, and the
        # exact-set checks still refuse one.
        self.review_ready()
        for bad in ({"stories": [], "reviewer": "claude"},
                    {"reviewer": "claude"},
                    {"stories": [{"storyId": 3000, "verdict": "APPROVED",
                                  "findings": [], "reviewer": "claude"}]}):
            with self.subTest(review=repr(bad)[:40]):
                with self.assertRaises(controller.ReviewRejected):
                    self.controller.ingest_review(
                        self.run_id, self.packet_id, review=bad, actor=self.actor)
        # And the reclassification feature added no reviewer field anywhere in
        # the review path -- the attestation lives in its own request argument.
        import inspect
        source = inspect.getsource(controller.AutonomousStoryController.ingest_review)
        self.assertNotIn("reviewerRole", source)
        self.assertNotIn("reviewerAttestation", source)

    def test_audio_present_blocks_reclassification(self):
        self.changes_requested({3001: [LONG_FINDING]})
        packet = self.controller.load(self.run_id, self.packet_id)
        slot = next(s for s in packet["slots"] if s["storyId"] == 3001)
        production = self.controller.repo_root / slot["materialization"]["path"]
        (production / "audio_3001_story.mp3").write_bytes(b"\x00")
        request = self.request(3001, ["short", "full"],
                               self.finding_map(3001, ["long"]))
        with self.assertRaises(controller.SafetyViolation):
            self.reclassify([request])


class LengthReclassificationReplayTests(LengthReclassificationTestCase):

    def _forge(self, mutate):
        """Append a forged STORY_LENGTHS_RECLASSIFIED-shaped event."""
        journal = (self.controller.packet_dir(self.run_id, self.packet_id)
                   / "events.jsonl")
        lines = journal.read_bytes().decode().splitlines()
        last = json.loads(lines[-1])
        packet = copy.deepcopy(last["packet"])
        event = {
            "schemaVersion": controller.CONTROLLER_SCHEMA_VERSION,
            "eventId": "00000000-0000-4000-8000-000000000abc",
            "sequence": len(lines) + 1,
            "timestamp": "2099-01-01T00:00:00Z",
            "eventType": "STORY_LENGTHS_RECLASSIFIED",
            "runId": self.run_id, "packetId": self.packet_id, "storyId": None,
            "fromState": last["toState"], "toState": last["toState"],
            "actor": self.actor, "reason": "forged", "packet": packet,
        }
        mutate(event)
        event["evidenceHash"] = controller._event_hash(event)
        journal.write_bytes(journal.read_bytes()
                            + controller._canonical_bytes(event) + b"\n")

    def test_non_prefix_target_lengths_change_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "long"]
            event["packet"]["evidenceHashes"]["lengthReclassificationReview1"] = "a" * 64
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_upward_target_lengths_change_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "full", "long", "long"]
            event["packet"]["evidenceHashes"]["lengthReclassificationReview1"] = "a" * 64
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_missing_evidence_hash_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "full"]
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_reclassification_changing_nothing_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            event["packet"]["evidenceHashes"]["lengthReclassificationReview1"] = "a" * 64
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_reclassification_moving_a_round_counter_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "full"]
            event["packet"]["correctionRound"] = 2
            event["packet"]["evidenceHashes"]["lengthReclassificationReview1"] = "a" * 64
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_another_event_type_changing_target_lengths_is_journal_corrupt(self):
        self.changes_requested({3001: [LONG_FINDING]})

        def mutate(event):
            event["eventType"] = "PACKET_LEASE_RENEWED"
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "full"]
        self._forge(mutate)
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)

    def test_reclassification_in_the_wrong_state_is_illegal_on_replay(self):
        self.review_ready()

        def mutate(event):
            for slot in event["packet"]["slots"]:
                if slot["storyId"] == 3001:
                    slot["targetLengths"] = ["short", "full"]
            event["packet"]["evidenceHashes"]["lengthReclassificationReview1"] = "a" * 64
        self._forge(mutate)
        with self.assertRaises(controller.IllegalControllerTransition):
            self.controller.load(self.run_id, self.packet_id)


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


class ValidationInfrastructureRecoveryTests(ControllerTestCase):
    def _quarantine_with_legacy_i_have_hit(self, *, genuine_model_meta=False):
        packet = self.assignments()
        real_detector = controller.check_meta_text
        for attempt in range(1, controller.MAX_CORRECTION_ROUNDS + 2):
            def mutate(root, current, attempt=attempt):
                if attempt <= controller.MAX_CORRECTION_ROUNDS:
                    for slot in current["slots"]:
                        for lane in controller.LANES:
                            (root / str(slot["storyId"])
                             / f"reflection_{slot['storyId']}_traditional_{lane}.txt").write_text(
                                "too short", encoding="utf-8",
                            )
                else:
                    phrase = (
                        "I have generated the requested reflection below."
                        if genuine_model_meta
                        else "I have anointed {pronoun} king over Israel."
                    )
                    slot = next(item for item in current["slots"] if item["storyId"] == 3001)
                    for lane in controller.LANES:
                        pronoun = "thee" if lane == "kjv" else "you"
                        (root / "3001"
                         / f"reflection_3001_traditional_{lane}.txt").write_text(
                            phrase.format(pronoun=pronoun) + " "
                            + words(30, kjv=lane == "kjv"),
                            encoding="utf-8",
                        )

            source = self.write_outputs(
                packet, root=self.base / f"recovery-attempt-{attempt}", mutate=mutate,
            )
            self.controller.ingest_writer_output(
                self.run_id, self.packet_id, source_root=source, actor=self.actor,
            )
            if attempt == controller.MAX_CORRECTION_ROUNDS + 1:
                def legacy_detector(text):
                    if "i have" in text.lstrip()[:200].lower():
                        return "i have"
                    return real_detector(text)

                context = mock.patch.object(
                    controller, "check_meta_text", side_effect=legacy_detector,
                )
            else:
                context = mock.patch.object(
                    controller, "check_meta_text", side_effect=real_detector,
                )
            with context, self.assertRaises(controller.ValidationFailed):
                self.controller.validate_outputs(
                    self.run_id, self.packet_id, actor=self.actor,
                )
            packet = self.controller.load(self.run_id, self.packet_id)
            if attempt <= controller.MAX_CORRECTION_ROUNDS:
                packet = self.controller.emit_corrections(
                    self.run_id, self.packet_id, actor=self.actor,
                )
        self.assertEqual(packet["state"], controller.QUARANTINED)
        return packet

    def _request(self, packet, **overrides):
        attempt = max(slot["writerAttempts"] for slot in packet["slots"])
        value = {
            "failureClass": controller.VALIDATION_I_HAVE_FALSE_POSITIVE,
            "writerOutputEvidenceSha256":
                packet["evidenceHashes"][f"writerOutputAttempt{attempt}"],
            "validationFailureSha256": packet["evidenceHashes"]["validationFailure"],
            "adjudication": (
                "The complete recorded failure set is the retired context-free "
                "I-have validator rule, not an editorial waiver."
            ),
        }
        value.update(overrides)
        return value

    def _recover(self, packet, **kwargs):
        return self.controller.recover_validation_i_have_false_positive(
            self.run_id,
            self.packet_id,
            actor=kwargs.pop("actor", self.actor),
            request=kwargs.pop("request", self._request(packet)),
            owner_authorized=kwargs.pop("owner_authorized", True),
            **kwargs,
        )

    def test_owner_recovery_revalidates_same_attempt_without_new_round(self):
        quarantined = self._quarantine_with_legacy_i_have_hit()
        before_attempts = [slot["writerAttempts"] for slot in quarantined["slots"]]
        before_histories = [copy.deepcopy(slot["correctionHistory"])
                            for slot in quarantined["slots"]]
        journal = (self.controller.packet_dir(self.run_id, self.packet_id)
                   / "events.jsonl")
        failed_event_count = len(journal.read_bytes().splitlines())
        recovered = self._recover(quarantined)
        self.assertEqual(recovered["state"], controller.WRITER_OUTPUT_RECEIVED)
        self.assertEqual(recovered["correctionRound"], controller.MAX_CORRECTION_ROUNDS)
        self.assertEqual([slot["writerAttempts"] for slot in recovered["slots"]], before_attempts)
        self.assertEqual([slot["correctionHistory"] for slot in recovered["slots"]], before_histories)
        events = [json.loads(line) for line in journal.read_text().splitlines()]
        self.assertEqual(len(events), failed_event_count + 1)
        self.assertEqual(events[-2]["eventType"], "VALIDATION_CORRECTION_CAP_EXCEEDED")
        self.assertEqual(events[-1]["eventType"], controller.VALIDATION_INFRASTRUCTURE_RECOVERY)
        evidence_path = (
            self.controller.packet_dir(self.run_id, self.packet_id)
            / "recoveries" / "validation" / "round-3"
            / "i_have_context_false_positive.json"
        )
        self.assertTrue(evidence_path.is_file())
        self.assertEqual(oct(evidence_path.stat().st_mode & 0o777), "0o600")
        passed = self.controller.validate_outputs(
            self.run_id, self.packet_id, actor=self.actor,
        )
        self.assertEqual(passed["state"], controller.VALIDATION_PASSED)
        self.assertEqual([slot["writerAttempts"] for slot in passed["slots"]], before_attempts)

    def test_changed_quarantined_attempt_is_refused_without_event(self):
        packet = self._quarantine_with_legacy_i_have_hit()
        journal = (self.controller.packet_dir(self.run_id, self.packet_id)
                   / "events.jsonl")
        before = journal.read_bytes()
        slot = next(item for item in packet["slots"] if item["storyId"] == 3001)
        workspace = self.controller._workspace_dir(packet, slot)
        target = workspace / "reflection_3001_traditional_web.txt"
        target.write_bytes(target.read_bytes() + b" changed")
        with self.assertRaises(controller.SafetyViolation):
            self._recover(packet)
        self.assertEqual(journal.read_bytes(), before)

    def test_genuine_model_meta_text_cannot_be_adjudicated_away(self):
        packet = self._quarantine_with_legacy_i_have_hit(genuine_model_meta=True)
        journal = (self.controller.packet_dir(self.run_id, self.packet_id)
                   / "events.jsonl")
        before = journal.read_bytes()
        with self.assertRaisesRegex(controller.ReviewRejected, "genuine blocking finding"):
            self._recover(packet)
        self.assertEqual(journal.read_bytes(), before)

    def test_recovery_requires_exact_owner_authorization_and_hashes(self):
        packet = self._quarantine_with_legacy_i_have_hit()
        with self.assertRaises(controller.ReviewRejected):
            self._recover(packet, owner_authorized=False)
        bad = self._request(packet, writerOutputEvidenceSha256="0" * 64)
        with self.assertRaises(controller.ReviewRejected):
            self._recover(packet, request=bad)

    def test_replay_refuses_a_different_event_using_quarantined_exit(self):
        packet = self._quarantine_with_legacy_i_have_hit()
        journal = (self.controller.packet_dir(self.run_id, self.packet_id)
                   / "events.jsonl")
        lines = journal.read_bytes().splitlines()
        forged_packet = copy.deepcopy(packet)
        forged_packet["state"] = controller.WRITER_OUTPUT_RECEIVED
        for slot in forged_packet["slots"]:
            slot["state"] = controller.WRITER_OUTPUT_RECEIVED
        event = {
            "schemaVersion": controller.CONTROLLER_SCHEMA_VERSION,
            "eventId": "00000000-0000-4000-8000-000000000999",
            "sequence": len(lines) + 1,
            "timestamp": "2099-01-01T00:00:00Z",
            "eventType": "WRITER_OUTPUT_INGESTED",
            "runId": self.run_id,
            "packetId": self.packet_id,
            "storyId": None,
            "fromState": controller.QUARANTINED,
            "toState": controller.WRITER_OUTPUT_RECEIVED,
            "actor": self.actor,
            "reason": "forged generic exit",
            "packet": forged_packet,
        }
        event["evidenceHash"] = controller._event_hash(event)
        journal.write_bytes(journal.read_bytes() + controller._canonical_bytes(event) + b"\n")
        with self.assertRaises(controller.JournalCorrupt):
            self.controller.load(self.run_id, self.packet_id)


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


class ReflectionContractIntegration(ControllerTestCase):
    """Option B: assignment is authoritative; the writer cannot self-elevate."""

    def _plan_with_form(self, form):
        planning = self.planning()
        if form is not None:
            for story in planning["stories"]:
                story["reflectionForm"] = form
        return self.controller.plan_packet(
            run_id=self.run_id, packet_id=self.packet_id, actor=self.actor,
            planning=planning, lease_seconds=60,
        )

    def test_absent_planning_form_normalizes_to_standard(self):
        packet = self._plan_with_form(None)
        for slot in packet["slots"]:
            self.assertEqual(slot["reflectionForm"], "standard")

    def test_assignment_carries_form_and_both_ranges(self):
        self._plan_with_form("observation")
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        self.controller.emit_writer_assignments(self.run_id, self.packet_id, actor=self.actor)
        payload = json.loads(
            (self.controller.packet_dir(self.run_id, self.packet_id)
             / "assignments" / "story_3000.json").read_text(encoding="utf-8")
        )
        self.assertEqual(payload["reflectionContract"], {
            "reflectionForm": "observation",
            "validWordRange": [25, 120],
            "targetWordRange": [60, 100],
            "explicitlyAssignedException": True,
        })

    def test_unknown_planning_form_is_rejected(self):
        with self.assertRaises(controller.ControllerConfigError):
            self._plan_with_form("sonnet")

    def test_standard_assignment_rejects_exception_metadata(self):
        packet = self._plan_with_form(None)
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.emit_writer_assignments(
            self.run_id, self.packet_id, actor=self.actor)

        def elevate(root, pkt):
            for slot in pkt["slots"]:
                path = root / str(slot["storyId"]) / f"meta_{slot['storyId']}.json"
                meta = json.loads(path.read_text(encoding="utf-8"))
                meta["reflectionForm"] = "image_cascade"
                path.write_text(json.dumps(meta), encoding="utf-8")

        source = self.write_outputs(packet, mutate=elevate)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor)
        with self.assertRaises(controller.ValidationFailed) as caught:
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.assertIn("reflection form", str(caught.exception))

    def test_exception_assignment_with_matching_metadata_validates(self):
        packet = self._plan_with_form("observation")
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.emit_writer_assignments(
            self.run_id, self.packet_id, actor=self.actor)

        def declare(root, pkt):
            for slot in pkt["slots"]:
                path = root / str(slot["storyId"]) / f"meta_{slot['storyId']}.json"
                meta = json.loads(path.read_text(encoding="utf-8"))
                meta["reflectionForm"] = "observation"
                path.write_text(json.dumps(meta), encoding="utf-8")
                # 100 words is legal for the exception band and illegal for standard.
                for lane in controller.LANES:
                    (root / str(slot["storyId"])
                     / f"reflection_{slot['storyId']}_traditional_{lane}.txt").write_text(
                        words(100, kjv=lane == "kjv"), encoding="utf-8")

        source = self.write_outputs(packet, mutate=declare)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor)
        result = self.controller.validate_outputs(
            self.run_id, self.packet_id, actor=self.actor)
        self.assertEqual(result["state"], controller.VALIDATION_PASSED)
        evidence = json.loads(
            (self.controller.packet_dir(self.run_id, self.packet_id)
             / "validation" / "story_3000.json").read_text(encoding="utf-8")
        )
        check = next(
            c for c in evidence["orderedChecks"] if c["name"] == "reflection_quality"
        )
        self.assertEqual(check["reflectionForm"], "observation")
        self.assertEqual(check["validWordRange"], [25, 120])

    def test_standard_reflection_above_eighty_fails(self):
        packet = self._plan_with_form(None)
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.emit_writer_assignments(
            self.run_id, self.packet_id, actor=self.actor)

        def overlong(root, pkt):
            for slot in pkt["slots"]:
                for lane in controller.LANES:
                    (root / str(slot["storyId"])
                     / f"reflection_{slot['storyId']}_traditional_{lane}.txt").write_text(
                        words(81, kjv=lane == "kjv"), encoding="utf-8")

        source = self.write_outputs(packet, mutate=overlong)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor)
        with self.assertRaises(controller.ValidationFailed) as caught:
            self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.assertIn("outside 25-80", str(caught.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)


def _downgrade_event(event):
    """Rewrite a current-version event into an authentic legacy v1 event."""
    legacy = copy.deepcopy(event)
    legacy["schemaVersion"] = controller.LEGACY_CONTROLLER_SCHEMA_VERSION
    legacy["packet"]["schemaVersion"] = controller.LEGACY_CONTROLLER_SCHEMA_VERSION
    for slot in legacy["packet"]["slots"]:
        slot.pop("reflectionForm", None)
    core = {k: v for k, v in legacy.items() if k != "evidenceHash"}
    legacy["evidenceHash"] = controller._event_hash(core)
    return legacy


def _downgrade_journal(path):
    """Convert a journal (and its snapshot) to the pre-Option-B v1 shape."""
    events = [json.loads(line) for line in path.read_text().splitlines()]
    legacy = [_downgrade_event(event) for event in events]
    path.write_bytes(b"".join(controller._canonical_bytes(e) + b"\n" for e in legacy))
    snapshot = path.parent / "packet.json"
    if snapshot.exists():
        snapshot.write_text(json.dumps(legacy[-1]["packet"]), encoding="utf-8")
    return path.read_bytes()


class LegacyJournalCompatibilityTests(ControllerTestCase):
    """Journals written before reflectionForm existed must still replay."""

    def _legacy_at(self, builder):
        builder()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        raw = _downgrade_journal(journal)
        return journal, raw

    def _replay(self):
        return controller.replay_packet(self.factory, self.run_id, self.packet_id)

    def test_legacy_planned_packet_replays(self):
        self._legacy_at(self.plan)
        self.assertEqual(self._replay()["state"], controller.ID_RESERVED)

    def test_legacy_assignment_ready_packet_replays(self):
        self._legacy_at(self.assignments)
        self.assertEqual(self._replay()["state"], controller.ASSIGNMENT_READY)

    def test_legacy_review_ready_packet_replays(self):
        self._legacy_at(self.review_ready)
        self.assertEqual(self._replay()["state"], controller.REVIEW_READY)

    def test_legacy_correction_ready_packet_replays(self):
        def build():
            self.review_ready()
            self.controller.ingest_review(
                self.run_id, self.packet_id,
                review=self.review(verdict="CHANGES_REQUESTED"), actor=self.actor,
            )
            self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
        self._legacy_at(build)
        self.assertEqual(self._replay()["state"], controller.CORRECTION_READY)

    def test_legacy_slots_normalize_to_standard(self):
        self._legacy_at(self.review_ready)
        packet = self._replay()
        self.assertEqual(packet["schemaVersion"], controller.CONTROLLER_SCHEMA_VERSION)
        self.assertEqual(
            [slot["reflectionForm"] for slot in packet["slots"]],
            [reflection_contract.STANDARD_FORM] * controller.PACKET_SIZE,
        )

    def test_legacy_evidence_hashes_remain_valid(self):
        journal, raw = self._legacy_at(self.review_ready)
        for line in raw.splitlines():
            event = json.loads(line)
            core = {k: v for k, v in event.items() if k != "evidenceHash"}
            self.assertEqual(event["evidenceHash"], controller._event_hash(core))

    def test_replay_never_rewrites_journal_bytes(self):
        journal, raw = self._legacy_at(self.review_ready)
        self._replay()
        self.assertEqual(journal.read_bytes(), raw)

    def test_legacy_snapshot_is_accepted_after_normalization(self):
        self._legacy_at(self.review_ready)
        pdir = self.controller.packet_dir(self.run_id, self.packet_id)
        snapshot = json.loads((pdir / "packet.json").read_text())
        self.assertEqual(snapshot["schemaVersion"], controller.LEGACY_CONTROLLER_SCHEMA_VERSION)
        controller.validate_packet_model(snapshot)
        self.assertEqual(controller.normalize_packet_model(snapshot), self._replay())

    def test_malformed_snapshot_is_still_rejected(self):
        self._legacy_at(self.review_ready)
        pdir = self.controller.packet_dir(self.run_id, self.packet_id)
        snapshot = json.loads((pdir / "packet.json").read_text())
        snapshot["slots"][0].pop("mood")
        with self.assertRaises(controller.JournalCorrupt):
            controller.validate_packet_model(snapshot)


class MixedVersionJournalTests(ControllerTestCase):
    def test_v1_history_continues_into_v2_without_touching_old_bytes(self):
        self.review_ready()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        legacy_bytes = _downgrade_journal(journal)

        self.controller.ingest_review(
            self.run_id, self.packet_id,
            review=self.review(verdict="CHANGES_REQUESTED"), actor=self.actor,
        )
        self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)

        after = journal.read_bytes()
        self.assertTrue(after.startswith(legacy_bytes), "legacy prefix was rewritten")
        events = [json.loads(line) for line in after.splitlines()]
        old_count = len(legacy_bytes.splitlines())
        self.assertTrue(all(
            e["schemaVersion"] == controller.LEGACY_CONTROLLER_SCHEMA_VERSION
            for e in events[:old_count]
        ))
        self.assertTrue(all(
            e["schemaVersion"] == controller.CONTROLLER_SCHEMA_VERSION
            for e in events[old_count:]
        ))
        packet = controller.replay_packet(self.factory, self.run_id, self.packet_id)
        self.assertEqual(packet["state"], controller.CORRECTION_READY)
        self.assertTrue(all(s["state"] == packet["state"] for s in packet["slots"]))

    def test_new_snapshot_uses_current_version(self):
        self.review_ready()
        pdir = self.controller.packet_dir(self.run_id, self.packet_id)
        _downgrade_journal(pdir / "events.jsonl")
        self.controller.ingest_review(
            self.run_id, self.packet_id,
            review=self.review(verdict="CHANGES_REQUESTED"), actor=self.actor,
        )
        snapshot = json.loads((pdir / "packet.json").read_text())
        self.assertEqual(snapshot["schemaVersion"], controller.CONTROLLER_SCHEMA_VERSION)
        self.assertIn("reflectionForm", snapshot["slots"][0])


class SchemaVersionTamperTests(ControllerTestCase):
    def _first_event(self):
        self.plan()
        journal = self.controller.packet_dir(self.run_id, self.packet_id) / "events.jsonl"
        return json.loads(journal.read_text().splitlines()[0])

    def _reseal(self, event):
        core = {k: v for k, v in event.items() if k != "evidenceHash"}
        event["evidenceHash"] = controller._event_hash(core)
        return event

    def test_current_version_event_missing_reflection_form_fails(self):
        event = self._first_event()
        for slot in event["packet"]["slots"]:
            slot.pop("reflectionForm")
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(self._reseal(event), 1)

    def test_current_version_event_with_unknown_form_fails(self):
        event = self._first_event()
        for slot in event["packet"]["slots"]:
            slot["reflectionForm"] = "freeform_epic"
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(self._reseal(event), 1)

    def test_legacy_event_with_extra_reflection_form_fails(self):
        event = _downgrade_event(self._first_event())
        for slot in event["packet"]["slots"]:
            slot["reflectionForm"] = reflection_contract.STANDARD_FORM
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(self._reseal(event), 1)

    def test_modified_legacy_event_with_stale_hash_fails(self):
        event = _downgrade_event(self._first_event())
        event["packet"]["slots"][0]["proposedAnchor"] = "Genesis 9:1-3"
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(event, 1)

    def test_event_version_must_match_its_packet_version(self):
        event = self._first_event()
        event["packet"]["schemaVersion"] = controller.LEGACY_CONTROLLER_SCHEMA_VERSION
        for slot in event["packet"]["slots"]:
            slot.pop("reflectionForm")
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(self._reseal(event), 1)

    def test_unsupported_future_version_fails(self):
        event = self._first_event()
        event["schemaVersion"] = 3
        event["packet"]["schemaVersion"] = 3
        with self.assertRaises(controller.JournalCorrupt):
            controller._validate_event(self._reseal(event), 1)


class CorrectionAssignmentContractTests(ControllerTestCase):
    def _corrections_for(self, form):
        narrator = "VOICE_SARAH_STORYTELLER"
        planning = {
            "stories": [
                {
                    "proposedAnchor": ANCHORS[index], "mood": "encouraging",
                    "narrator": narrator, "lengths": ["short"], "reflectionForm": form,
                }
                for index in range(controller.PACKET_SIZE)
            ]
        }
        self.controller.plan_packet(
            run_id=self.run_id, packet_id=self.packet_id, actor=self.actor,
            planning=planning, lease_seconds=60,
        )
        self.controller.preflight_anchors(self.run_id, self.packet_id, actor=self.actor)
        packet = self.controller.emit_writer_assignments(
            self.run_id, self.packet_id, actor=self.actor,
        )
        source = self.write_outputs(packet)
        self.controller.ingest_writer_output(
            self.run_id, self.packet_id, source_root=source, actor=self.actor,
        )
        self.controller.validate_outputs(self.run_id, self.packet_id, actor=self.actor)
        self.controller.materialize_for_review(self.run_id, self.packet_id, actor=self.actor)
        self.controller.emit_review_packet(self.run_id, self.packet_id, actor=self.actor)
        self.controller.ingest_review(
            self.run_id, self.packet_id,
            review=self.review(verdict="CHANGES_REQUESTED"), actor=self.actor,
        )
        self.controller.emit_corrections(self.run_id, self.packet_id, actor=self.actor)
        cdir = self.controller.packet_dir(self.run_id, self.packet_id) / "corrections" / "round-1"
        return [json.loads(p.read_text()) for p in sorted(cdir.glob("story_*.json"))]

    def test_standard_form_survives_correction_with_contract(self):
        payloads = self._corrections_for(reflection_contract.STANDARD_FORM)
        self.assertEqual(len(payloads), controller.PACKET_SIZE)
        for payload in payloads:
            self.assertEqual(payload["immutableReflectionForm"], reflection_contract.STANDARD_FORM)
            contract = payload["reflectionContract"]
            self.assertEqual(contract["reflectionForm"], reflection_contract.STANDARD_FORM)
            self.assertEqual(tuple(contract["validWordRange"]), reflection_contract.STANDARD_VALID_RANGE)
            self.assertEqual(tuple(contract["targetWordRange"]), reflection_contract.STANDARD_TARGET_RANGE)
            self.assertFalse(contract["explicitlyAssignedException"])

    def test_observation_form_survives_correction(self):
        for payload in self._corrections_for("observation"):
            self.assertEqual(payload["immutableReflectionForm"], "observation")
            contract = payload["reflectionContract"]
            self.assertEqual(contract["reflectionForm"], "observation")
            self.assertEqual(tuple(contract["validWordRange"]), reflection_contract.EXCEPTION_VALID_RANGE)
            self.assertTrue(contract["explicitlyAssignedException"])

    def test_image_cascade_form_survives_correction(self):
        for payload in self._corrections_for("image_cascade"):
            self.assertEqual(payload["immutableReflectionForm"], "image_cascade")
            self.assertEqual(payload["reflectionContract"]["reflectionForm"], "image_cascade")
            self.assertTrue(payload["reflectionContract"]["explicitlyAssignedException"])

    def test_correction_cannot_switch_reflection_form(self):
        self._corrections_for("observation")
        packet = self.controller.load(self.run_id, self.packet_id)
        self.assertTrue(all(s["reflectionForm"] == "observation" for s in packet["slots"]))
