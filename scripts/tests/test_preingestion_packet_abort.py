#!/usr/bin/env python3
"""Focused, temporary-only tests for owner-gated pre-ingestion packet abort."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "story_factory"))

import anchor_claims as acl  # noqa: E402
import autonomous_story_controller as controller  # noqa: E402
import preflight_anchor_overlap as gate  # noqa: E402
import story_id_reservations as reservations  # noqa: E402


RUN_ID = "campaign-3000-3258-run-001"
ID_RESERVED_ACTOR = "codex-gpt-5-6-sol"
PACKET_003_ANCHORS = (
    "Jude 1:1-19",
    "Hosea 1:1-3:5",
    "Ephesians 2:1-22",
    "1 Thessalonians 4:13-5:11",
    "Song of Solomon 1:1-2:17",
)
OTHER_ANCHORS_A = (
    "Nahum 1:1-15",
    "Habakkuk 1:1-11",
    "Zephaniah 1:1-9",
    "Haggai 1:1-11",
    "Malachi 1:1-14",
)
OTHER_ANCHORS_B = (
    "Ruth 1:1-10",
    "Esther 1:1-9",
    "Lamentations 1:1-7",
    "Ecclesiastes 1:1-11",
    "Titus 1:1-9",
)


def _tree_hash(path: Path) -> str:
    rows = []
    for item in sorted(path.rglob("*")):
        if item.is_file():
            rows.append((str(item.relative_to(path)), hashlib.sha256(item.read_bytes()).hexdigest()))
    return hashlib.sha256(
        json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


class PreIngestionAbortTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="bible-pal-preingest-abort-")
        self.addCleanup(self._tmp.cleanup)
        self.base = Path(self._tmp.name)
        self.repo = self.base / "repo"
        self.factory = self.base / "factory"
        (self.repo / "assets" / "stories" / "traditional").mkdir(parents=True)
        (self.repo / "assets" / "stories" / "kids").mkdir(parents=True)
        (self.repo / "assets" / "stories" / "manifest.json").write_text(
            json.dumps({"version": 1, "parables": []}),
            encoding="utf-8",
        )
        # Model the already-consumed 3000-3009 range without creating mutable
        # reservations.  The target packet therefore receives 3010-3014.
        for story_id in range(3000, 3010):
            (self.repo / "assets" / "stories" / "traditional" / str(story_id)).mkdir()

    def build(self):
        return controller.AutonomousStoryController(
            repo_root=self.repo,
            worktree=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            policy_root=REPO_ROOT,
            reservations=reservations,
            overlap_evaluator=gate.evaluate,
        )

    @staticmethod
    def planning(anchors=PACKET_003_ANCHORS, *, corrected_3012=False):
        rows = []
        for index, anchor in enumerate(anchors):
            lengths = ["short", "full", "long"]
            if index in {0, 3, 4} or (corrected_3012 and index == 2):
                lengths = ["short", "full"]
            rows.append({
                "proposedAnchor": anchor,
                "mood": "encouraging",
                "narrator": "VOICE_SARAH_STORYTELLER",
                "lengths": lengths,
            })
        return {"stories": rows}

    def make_ready(self, packet_id="proving-packet-003", *, anchors=PACKET_003_ANCHORS,
                   corrected_3012=False):
        ctl = self.build()
        claimed = acl.claim_packet_anchors(
            run_id=RUN_ID,
            packet_id=packet_id,
            proposals=[
                {"slotId": index + 1, "anchor": anchor}
                for index, anchor in enumerate(anchors)
            ],
            actor="owner",
            factory_home=self.factory,
        )
        packet = ctl.plan_packet(
            run_id=RUN_ID,
            packet_id=packet_id,
            actor="owner",
            planning=self.planning(anchors, corrected_3012=corrected_3012),
            lease_seconds=3600,
        )
        bound = [
            acl.bind_story_id(
                claim,
                slot["storyId"],
                actor="owner",
                factory_home=self.factory,
            )
            for claim, slot in zip(claimed.claims, packet["slots"])
        ]
        packet = ctl.preflight_anchors(RUN_ID, packet_id, actor="owner")
        for claim in bound:
            acl.mark_authoring(claim, actor="owner", factory_home=self.factory)
        packet = ctl.emit_writer_assignments(RUN_ID, packet_id, actor="owner")
        self.assertEqual(packet["state"], controller.ASSIGNMENT_READY)
        return ctl, packet, claimed.packet_claim_hash

    def abort(self, ctl, packet_id="proving-packet-003"):
        return ctl.abort_unstarted_packet(
            RUN_ID,
            packet_id,
            actor="owner",
            owner_authorized=True,
        )

    def make_id_reserved_refusal(self, packet_id="proving-packet-015"):
        ctl = self.build()

        def refuse_one(anchor, **kwargs):
            verdict = "BLOCK" if anchor == PACKET_003_ANCHORS[0] else "PASS"
            return {
                "gateVersion": "id-reserved-recovery-test",
                "candidate": {
                    "rawReference": anchor,
                    "proposedStoryId": kwargs.get("story_id"),
                },
                "verdict": verdict,
                "blockingStoryIds": [42] if verdict == "BLOCK" else [],
                "warnings": [],
            }

        ctl.overlap_evaluator = refuse_one
        packet = ctl.plan_packet(
            run_id=RUN_ID,
            packet_id=packet_id,
            actor=ID_RESERVED_ACTOR,
            planning=self.planning(),
            lease_seconds=3600,
        )
        with self.assertRaises(controller.OverlapRejected):
            ctl.preflight_anchors(RUN_ID, packet_id, actor=ID_RESERVED_ACTOR)
        packet = ctl.load(RUN_ID, packet_id)
        self.assertEqual(packet["state"], controller.ID_RESERVED)
        return ctl, packet

    def abort_id_reserved(self, ctl, packet_id="proving-packet-015"):
        return ctl.abort_unstarted_packet(
            RUN_ID,
            packet_id,
            actor=ID_RESERVED_ACTOR,
            owner_authorized=True,
            reason="authoritative anchor-preflight refusal before assignments",
        )

    def packet_claims(self, packet_id):
        return [
            claim
            for claim in acl.replay_ledger(self.factory).values()
            if (claim.run_id, claim.packet_id) == (RUN_ID, packet_id)
        ]

    def test_happy_path_terminalizes_packet_and_exact_resources(self):
        ctl, packet, _ = self.make_ready()
        result = self.abort(ctl)
        self.assertEqual(result["state"], controller.ABORTED)
        self.assertEqual({slot["reservation"]["state"] for slot in result["slots"]}, {"RELEASED"})
        self.assertEqual({claim.state for claim in self.packet_claims("proving-packet-003")}, {acl.ABORTED})
        for slot in packet["slots"]:
            self.assertFalse((self.factory / "locks" / f"{slot['storyId']}.lock").exists())
        for claim in self.packet_claims("proving-packet-003"):
            self.assertFalse((acl.locks_dir(self.factory) / f"{claim.anchor_key}.lock").exists())
        evidence = self.factory / "runs" / RUN_ID / "packets" / "proving-packet-003" / "abort" / "pre_ingestion.json"
        self.assertTrue(evidence.is_file())
        self.assertEqual(json.loads(evidence.read_text())["ownerAuthorized"], True)
        event_types = [json.loads(line)["eventType"] for line in (
            self.factory / "runs" / RUN_ID / "packets" / "proving-packet-003" / "events.jsonl"
        ).read_text().splitlines()]
        self.assertEqual(event_types[-1], "PREINGEST_PACKET_ABORTED")
        self.assertIn("RELEASED", [json.loads(line)["eventType"] for line in (
            self.factory / "reservations.jsonl"
        ).read_text().splitlines()])
        self.assertIn("PACKET_ANCHORS_ABORTED", [json.loads(line)["eventType"] for line in (
            self.factory / "anchor_claims.jsonl"
        ).read_text().splitlines()])

    def test_owner_authorization_is_mandatory(self):
        ctl, packet, _ = self.make_ready()
        with self.assertRaisesRegex(controller.SafetyViolation, "owner authorization"):
            ctl.abort_unstarted_packet(RUN_ID, packet["packetId"], actor="owner")
        self.assertEqual(ctl.load(RUN_ID, packet["packetId"])["state"], controller.ASSIGNMENT_READY)

    def test_writer_attempt_or_downstream_artifact_rejects_before_mutation(self):
        ctl, packet, _ = self.make_ready()
        forged = copy.deepcopy(packet)
        forged["slots"][0]["writerAttempts"] = 1
        with mock.patch.object(ctl, "load", return_value=forged):
            with self.assertRaisesRegex(controller.SafetyViolation, "writer attempt"):
                self.abort(ctl)
        writer_dir = ctl.packet_dir(RUN_ID, packet["packetId"]) / "writer_output"
        writer_dir.mkdir(mode=0o700)
        (writer_dir / "unexpected.txt").write_text("not ingested", encoding="utf-8")
        os.chmod(writer_dir / "unexpected.txt", 0o600)
        with self.assertRaisesRegex(controller.SafetyViolation, "unexpected artifacts"):
            self.abort(ctl)
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.AUTHORING})

    def test_audio_in_packet_runtime_rejects_before_mutation(self):
        ctl, packet, _ = self.make_ready()
        audio = ctl.packet_dir(RUN_ID, packet["packetId"]) / "forbidden.mp3"
        audio.write_bytes(b"")
        os.chmod(audio, 0o600)
        with self.assertRaisesRegex(controller.SafetyViolation, "audio exists"):
            self.abort(ctl)
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.AUTHORING})

    def test_materialized_or_manifest_occupied_id_is_never_released(self):
        ctl, packet, _ = self.make_ready()
        story_id = packet["slots"][0]["storyId"]
        production = self.repo / "assets" / "stories" / "traditional" / str(story_id)
        production.mkdir()
        (production / f"meta_{story_id}.json").write_text("{}", encoding="utf-8")
        current = reservations.replay_ledger(self.factory)[story_id]
        reservations.confirm_materialized(
            current,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            actor="owner",
        )
        with self.assertRaisesRegex(controller.IntegrationError, "not safely releasable"):
            self.abort(ctl)
        self.assertEqual(reservations.replay_ledger(self.factory)[story_id].state, "MATERIALIZED")
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.AUTHORING})

    def test_manifest_registration_rejects_before_resource_mutation(self):
        ctl, packet, _ = self.make_ready()
        story_id = packet["slots"][0]["storyId"]
        manifest = self.repo / "assets" / "stories" / "manifest.json"
        manifest.write_text(json.dumps({
            "version": 2,
            "parables": [{
                "storyId": f"story_{story_id}_forbidden",
                "textFilePath": f"traditional/{story_id}/story_{story_id}_traditional_web_short.txt",
            }],
        }), encoding="utf-8")
        with self.assertRaisesRegex(controller.SafetyViolation, "manifest.json changed"):
            self.abort(ctl)
        self.assertEqual(reservations.replay_ledger(self.factory)[story_id].state, "RESERVED")
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.AUTHORING})

    def test_later_controller_states_are_not_supported_abort_sources(self):
        ctl, packet, _ = self.make_ready()
        for state in (
            controller.REVIEW_READY,
            controller.REVIEW_APPROVED,
            controller.READY_FOR_HUMAN_REVIEW,
        ):
            forged = copy.deepcopy(packet)
            forged["state"] = state
            for slot in forged["slots"]:
                slot["state"] = state
            with self.subTest(state=state), mock.patch.object(ctl, "load", return_value=forged):
                with self.assertRaisesRegex(
                    controller.IllegalControllerTransition,
                    "requires ID_RESERVED.*ASSIGNMENT_READY",
                ):
                    self.abort(ctl)

    def test_id_reserved_refusal_abort_releases_ids_and_records_immutable_evidence(self):
        ctl, packet = self.make_id_reserved_refusal()
        repo_before = _tree_hash(self.repo)
        manifest_before = (self.repo / "assets" / "stories" / "manifest.json").read_bytes()

        result = self.abort_id_reserved(ctl)

        self.assertEqual(result["state"], controller.ABORTED)
        self.assertEqual(
            {slot["reservation"]["state"] for slot in result["slots"]},
            {"RELEASED"},
        )
        story_ids = sorted(slot["storyId"] for slot in packet["slots"])
        ledger = reservations.replay_ledger(self.factory)
        self.assertEqual([ledger[story_id].state for story_id in story_ids], ["RELEASED"] * 5)
        for story_id in story_ids:
            self.assertFalse((self.factory / "locks" / f"{story_id}.lock").exists())

        evidence_path = (
            ctl.packet_dir(RUN_ID, packet["packetId"])
            / "abort" / "id_reserved_anchor_preflight.json"
        )
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        self.assertEqual(evidence["packetId"], packet["packetId"])
        self.assertEqual(evidence["sourceState"], controller.ID_RESERVED)
        self.assertEqual(evidence["releasedStoryIds"], story_ids)
        self.assertEqual(
            {row["state"] for row in evidence["reservationLedgerReleaseResult"]},
            {"RELEASED"},
        )
        self.assertEqual(evidence["actor"], ID_RESERVED_ACTOR)
        self.assertEqual(
            evidence["recoveryReason"],
            "authoritative anchor-preflight refusal before assignments",
        )
        self.assertRegex(
            evidence["authoritativeAnchorPreflightRefusal"]["eventHash"],
            r"^[0-9a-f]{64}$",
        )
        self.assertFalse(evidence["checks"]["productionFilesTouchedByRecovery"])
        self.assertFalse(evidence["checks"]["manifestTouchedByRecovery"])
        self.assertEqual(_tree_hash(self.repo), repo_before)
        self.assertEqual(
            (self.repo / "assets" / "stories" / "manifest.json").read_bytes(),
            manifest_before,
        )

    def test_id_reserved_refusal_abort_refuses_assignment_evidence(self):
        ctl, packet = self.make_id_reserved_refusal()
        forged = copy.deepcopy(packet)
        forged["slots"][0]["assignment"] = {"path": "assignments/forbidden.json", "hash": "0" * 64}
        before = (self.factory / "reservations.jsonl").read_bytes()
        with mock.patch.object(ctl, "load", return_value=forged):
            with self.assertRaisesRegex(controller.SafetyViolation, "assignment evidence"):
                self.abort_id_reserved(ctl)
        self.assertEqual((self.factory / "reservations.jsonl").read_bytes(), before)

    def test_id_reserved_refusal_abort_refuses_live_story_directory(self):
        ctl, packet = self.make_id_reserved_refusal()
        story_id = packet["slots"][0]["storyId"]
        (self.repo / "assets" / "stories" / "traditional" / str(story_id)).mkdir()
        before = (self.factory / "reservations.jsonl").read_bytes()
        with self.assertRaisesRegex(controller.SafetyViolation, "live story directories"):
            self.abort_id_reserved(ctl)
        self.assertEqual((self.factory / "reservations.jsonl").read_bytes(), before)

    def test_id_reserved_refusal_abort_refuses_materialization_evidence(self):
        ctl, packet = self.make_id_reserved_refusal()
        forged = copy.deepcopy(packet)
        forged["slots"][0]["materialization"] = {
            "treeHash": "0" * 64,
            "files": {},
        }
        before = (self.factory / "reservations.jsonl").read_bytes()
        with mock.patch.object(ctl, "load", return_value=forged):
            with self.assertRaisesRegex(controller.SafetyViolation, "downstream lifecycle"):
                self.abort_id_reserved(ctl)
        self.assertEqual((self.factory / "reservations.jsonl").read_bytes(), before)

    def test_id_reserved_refusal_abort_refuses_manifest_entry(self):
        ctl, packet = self.make_id_reserved_refusal()
        story_id = packet["slots"][0]["storyId"]
        manifest = self.repo / "assets" / "stories" / "manifest.json"
        manifest.write_text(json.dumps({
            "version": 2,
            "parables": [{
                "storyId": f"story_{story_id}_forbidden",
                "textFilePath": (
                    f"traditional/{story_id}/story_{story_id}_traditional_web_short.txt"
                ),
            }],
        }), encoding="utf-8")
        before = (self.factory / "reservations.jsonl").read_bytes()
        with self.assertRaisesRegex(controller.SafetyViolation, "manifest entries"):
            self.abort_id_reserved(ctl)
        self.assertEqual((self.factory / "reservations.jsonl").read_bytes(), before)

    def test_id_reserved_refusal_abort_requires_explicit_reason(self):
        ctl, packet = self.make_id_reserved_refusal()
        with self.assertRaisesRegex(controller.SafetyViolation, "explicit reason"):
            ctl.abort_unstarted_packet(
                RUN_ID,
                packet["packetId"],
                actor=ID_RESERVED_ACTOR,
                owner_authorized=True,
            )
        self.assertEqual(
            {item.state for item in reservations.replay_ledger(self.factory).values()},
            {"RESERVED"},
        )

    def test_id_reserved_refusal_abort_requires_exact_persisted_actor(self):
        ctl, packet = self.make_id_reserved_refusal()
        with self.assertRaisesRegex(controller.SafetyViolation, "persisted packet actor"):
            ctl.abort_unstarted_packet(
                RUN_ID,
                packet["packetId"],
                actor="owner",
                owner_authorized=True,
                reason="authoritative anchor-preflight refusal before assignments",
            )
        self.assertEqual(
            {item.state for item in reservations.replay_ledger(self.factory).values()},
            {"RESERVED"},
        )

    def test_id_reserved_incoherent_reservation_refuses_before_any_release(self):
        ctl, packet = self.make_id_reserved_refusal()
        story_id = packet["slots"][-1]["storyId"]
        lock_path = self.factory / "locks" / f"{story_id}.lock"
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        lock["packetId"] = "foreign-packet"
        lock_path.write_text(
            json.dumps(lock, sort_keys=True, separators=(",", ":")),
            encoding="utf-8",
        )
        before = (self.factory / "reservations.jsonl").read_bytes()
        with self.assertRaisesRegex(controller.IntegrationError, "not safely releasable"):
            self.abort_id_reserved(ctl)
        self.assertEqual((self.factory / "reservations.jsonl").read_bytes(), before)

    def test_id_reserved_partial_release_retries_through_supported_api(self):
        ctl, packet = self.make_id_reserved_refusal()
        story_ids = [slot["storyId"] for slot in packet["slots"]]
        real_release = reservations.release_reservation
        calls = 0

        def fail_third(item, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise reservations.ReservationConflict("injected third-release failure")
            return real_release(item, **kwargs)

        with mock.patch.object(reservations, "release_reservation", side_effect=fail_third):
            with self.assertRaisesRegex(controller.IntegrationError, "release failed"):
                self.abort_id_reserved(ctl)
        states = reservations.replay_ledger(self.factory)
        self.assertEqual(
            [states[story_id].state for story_id in story_ids],
            ["RELEASED", "RELEASED", "RESERVED", "RESERVED", "RESERVED"],
        )
        self.assertEqual(self.abort_id_reserved(ctl)["state"], controller.ABORTED)

    def test_id_reserved_abort_replay_and_event_hash_remain_coherent(self):
        ctl, packet = self.make_id_reserved_refusal()
        result = self.abort_id_reserved(ctl)
        replayed = ctl.load(RUN_ID, packet["packetId"])
        self.assertEqual(replayed, result)
        journal = ctl.packet_dir(RUN_ID, packet["packetId"]) / "events.jsonl"
        events = [json.loads(line) for line in journal.read_text().splitlines()]
        self.assertEqual(events[-1]["eventType"], "ID_RESERVED_ANCHOR_PREFLIGHT_ABORTED")
        event = copy.deepcopy(events[-1])
        digest = event.pop("evidenceHash")
        self.assertEqual(digest, controller._event_hash(event))
        before = journal.read_bytes()
        self.assertEqual(self.abort_id_reserved(ctl), result)
        self.assertEqual(journal.read_bytes(), before)

    def test_foreign_reservation_lock_is_rejected_without_acl_abort(self):
        ctl, packet, _ = self.make_ready()
        story_id = packet["slots"][0]["storyId"]
        lock_path = self.factory / "locks" / f"{story_id}.lock"
        record = json.loads(lock_path.read_text())
        record["packetId"] = "foreign-packet"
        lock_path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")))
        with self.assertRaisesRegex(controller.IntegrationError, "not safely releasable"):
            self.abort(ctl)
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.AUTHORING})

    def test_foreign_acl_lock_is_rejected_and_never_unlinked(self):
        ctl, packet, _ = self.make_ready()
        claim = self.packet_claims(packet["packetId"])[0]
        lock_path = acl.locks_dir(self.factory) / f"{claim.anchor_key}.lock"
        record = json.loads(lock_path.read_text())
        record["runId"] = "foreign-run"
        record["packetId"] = "foreign-packet"
        lock_path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")))
        before = lock_path.read_bytes()
        with self.assertRaisesRegex(controller.IntegrationError, "packet ACL abort failed|ACL ownership"):
            self.abort(ctl)
        self.assertEqual(lock_path.read_bytes(), before)
        self.assertEqual({slot["reservation"]["state"] for slot in packet["slots"]}, {"RESERVED"})

    def test_partial_reservation_release_retries_without_manual_repair(self):
        ctl, packet, _ = self.make_ready()
        real_release = reservations.release_reservation
        calls = 0

        def fail_third(item, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise reservations.ReservationConflict("injected third-release failure")
            return real_release(item, **kwargs)

        with mock.patch.object(reservations, "release_reservation", side_effect=fail_third):
            with self.assertRaisesRegex(controller.IntegrationError, "after ACL terminalization"):
                self.abort(ctl)
        self.assertEqual(ctl.load(RUN_ID, packet["packetId"])["state"], controller.ASSIGNMENT_READY)
        states = reservations.replay_ledger(self.factory)
        self.assertEqual([states[story_id].state for story_id in range(3010, 3015)],
                         ["RELEASED", "RELEASED", "RESERVED", "RESERVED", "RESERVED"])
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.ABORTED})
        self.assertEqual(self.abort(ctl)["state"], controller.ABORTED)

    def test_acl_already_terminal_and_reservations_live_retry_completes(self):
        ctl, packet, claim_hash = self.make_ready()
        acl.abort_packet_claims(
            run_id=RUN_ID,
            packet_id=packet["packetId"],
            actor="owner",
            packet_claim_hash_value=claim_hash,
            factory_home=self.factory,
        )
        self.assertEqual(self.abort(ctl)["state"], controller.ABORTED)
        self.assertEqual({reservations.replay_ledger(self.factory)[sid].state for sid in range(3010, 3015)},
                         {"RELEASED"})

    def test_released_id_reused_by_other_packet_survives_old_retry(self):
        ctl, packet, _ = self.make_ready()
        real_release = reservations.release_reservation
        calls = 0

        def fail_second(item, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise reservations.ReservationConflict("injected second-release failure")
            return real_release(item, **kwargs)

        with mock.patch.object(reservations, "release_reservation", side_effect=fail_second):
            with self.assertRaises(controller.IntegrationError):
                self.abort(ctl)
        replacement = reservations.reserve_id(
            run_id=RUN_ID,
            packet_id="competing-packet",
            actor="owner",
            worktree=self.repo,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            lease_seconds=3600,
        )
        self.assertEqual(replacement.story_id, 3010)
        result = self.abort(ctl)
        current = reservations.replay_ledger(self.factory)[3010]
        self.assertEqual(current, replacement)
        old = result["slots"][0]["reservation"]
        self.assertEqual(old["state"], "RELEASED")
        self.assertNotEqual(old["leaseToken"], current.lease_token)
        lock = json.loads((self.factory / "locks" / "3010.lock").read_text())
        self.assertEqual(lock["packetId"], "competing-packet")

    def test_successful_abort_makes_anchors_normally_reusable(self):
        ctl, packet, _ = self.make_ready()
        self.abort(ctl)
        replacement = acl.claim_packet_anchors(
            run_id=RUN_ID,
            packet_id="proving-packet-004",
            proposals=[{"slotId": i + 1, "anchor": a} for i, a in enumerate(PACKET_003_ANCHORS)],
            actor="owner",
            factory_home=self.factory,
        )
        self.assertEqual(len(replacement.claims), 5)
        self.assertEqual({claim.state for claim in replacement.claims}, {acl.CLAIMED})

    def test_successful_abort_makes_ids_normally_reusable(self):
        ctl, packet, _ = self.make_ready()
        self.abort(ctl)
        replacement = reservations.reserve_packet(
            count=5,
            run_id=RUN_ID,
            packet_id="proving-packet-004",
            actor="owner",
            worktree=self.repo,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            lease_seconds=3600,
        )
        self.assertEqual([item.story_id for item in replacement], list(range(3010, 3015)))

    def test_aborted_rows_leave_overlap_queue_and_packet_id_stays_historical(self):
        ctl, packet, _ = self.make_ready()
        self.abort(ctl)
        rows = acl.build_overlap_queue(acl.replay_ledger(self.factory).values())
        self.assertFalse(any(row["proposedAnchor"] in PACKET_003_ANCHORS for row in rows))
        with self.assertRaisesRegex(controller.ControllerConfigError, "packet already exists"):
            ctl.plan_packet(
                run_id=RUN_ID,
                packet_id=packet["packetId"],
                actor="owner",
                planning=self.planning(),
            )

    def test_exact_retry_after_controller_event_is_a_verifying_noop(self):
        ctl, packet, _ = self.make_ready()
        first = self.abort(ctl)
        journal = ctl.packet_dir(RUN_ID, packet["packetId"]) / "events.jsonl"
        reservation_ledger = self.factory / "reservations.jsonl"
        acl_ledger = self.factory / "anchor_claims.jsonl"
        before = (journal.read_bytes(), reservation_ledger.read_bytes(), acl_ledger.read_bytes())
        second = self.abort(ctl)
        self.assertEqual(second, first)
        self.assertEqual(before, (journal.read_bytes(), reservation_ledger.read_bytes(), acl_ledger.read_bytes()))

    def test_crash_before_controller_event_retries_from_terminal_resources(self):
        ctl, packet, _ = self.make_ready()
        real_record = ctl._record

        def fail_abort_record(prior, updated, **kwargs):
            if kwargs.get("event_type") == "PREINGEST_PACKET_ABORTED":
                raise RuntimeError("injected controller-record crash")
            return real_record(prior, updated, **kwargs)

        with mock.patch.object(ctl, "_record", side_effect=fail_abort_record):
            with self.assertRaisesRegex(RuntimeError, "controller-record crash"):
                self.abort(ctl)
        self.assertEqual(ctl.load(RUN_ID, packet["packetId"])["state"], controller.ASSIGNMENT_READY)
        self.assertEqual({claim.state for claim in self.packet_claims(packet["packetId"])}, {acl.ABORTED})
        self.assertEqual(
            {reservations.replay_ledger(self.factory)[story_id].state for story_id in range(3010, 3015)},
            {"RELEASED"},
        )
        self.assertEqual(self.abort(ctl)["state"], controller.ABORTED)

    def test_cli_route_requires_explicit_owner_authorize_flag(self):
        common = [
            "--run-id", RUN_ID,
            "--packet-id", "proving-packet-003",
            "--actor", "owner",
            "--repo-root", str(self.repo),
            "--worktree", str(self.repo),
            "--factory-home", str(self.factory),
        ]
        parsed = controller.build_parser().parse_args(["abort-unstarted-packet", *common])
        self.assertFalse(parsed.owner_authorize)
        parsed = controller.build_parser().parse_args(
            [
                "abort-unstarted-packet",
                *common,
                "--owner-authorize",
                "--reason",
                "authoritative anchor-preflight refusal",
            ]
        )
        self.assertTrue(parsed.owner_authorize)
        self.assertEqual(parsed.reason, "authoritative anchor-preflight refusal")

    def test_reservation_release_crash_orphan_is_reconciled_by_exact_retry(self):
        item = reservations.reserve_id(
            run_id=RUN_ID,
            packet_id="reservation-crash",
            actor="owner",
            worktree=self.repo,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
            lease_seconds=3600,
        )
        with mock.patch.object(
            reservations,
            "_remove_locked_claim",
            side_effect=reservations.ReservationConflict("injected post-append crash"),
        ):
            with self.assertRaises(reservations.ReservationConflict):
                reservations.release_reservation(
                    item,
                    repo_root=self.repo,
                    factory_home=self.factory,
                    worktrees=[self.repo],
                )
        self.assertEqual(reservations.replay_ledger(self.factory)[item.story_id].state, "RELEASED")
        self.assertTrue((self.factory / "locks" / f"{item.story_id}.lock").exists())
        retried = reservations.release_reservation(
            item,
            repo_root=self.repo,
            factory_home=self.factory,
            worktrees=[self.repo],
        )
        self.assertEqual(retried.state, "RELEASED")
        self.assertFalse((self.factory / "locks" / f"{item.story_id}.lock").exists())

    def test_acl_abort_crash_orphan_is_reconciled_without_touching_successor(self):
        claimed = acl.claim_packet_anchors(
            run_id=RUN_ID,
            packet_id="acl-crash",
            proposals=[{"slotId": i + 1, "anchor": a} for i, a in enumerate(PACKET_003_ANCHORS)],
            actor="owner",
            factory_home=self.factory,
        )
        with mock.patch.object(acl.os, "unlink", side_effect=OSError("injected post-append crash")):
            with self.assertRaises(OSError):
                acl.abort_packet_claims(
                    run_id=RUN_ID,
                    packet_id="acl-crash",
                    actor="owner",
                    packet_claim_hash_value=claimed.packet_claim_hash,
                    factory_home=self.factory,
                )
        self.assertEqual({claim.state for claim in self.packet_claims("acl-crash")}, {acl.ABORTED})
        acl.abort_packet_claims(
            run_id=RUN_ID,
            packet_id="acl-crash",
            actor="owner",
            packet_claim_hash_value=claimed.packet_claim_hash,
            factory_home=self.factory,
        )
        successor = acl.claim_packet_anchors(
            run_id=RUN_ID,
            packet_id="acl-successor",
            proposals=[{"slotId": i + 1, "anchor": a} for i, a in enumerate(PACKET_003_ANCHORS)],
            actor="owner",
            factory_home=self.factory,
        )
        before = {
            path.name: path.read_bytes()
            for path in acl.locks_dir(self.factory).iterdir()
        }
        acl.abort_packet_claims(
            run_id=RUN_ID,
            packet_id="acl-crash",
            actor="owner",
            packet_claim_hash_value=claimed.packet_claim_hash,
            factory_home=self.factory,
        )
        self.assertEqual(before, {path.name: path.read_bytes() for path in acl.locks_dir(self.factory).iterdir()})
        self.assertEqual({claim.state for claim in successor.claims}, {acl.CLAIMED})

    def test_packet_003_replan_reclaims_3010_3014_with_corrected_3012(self):
        ctl, packet, _ = self.make_ready()
        self.abort(ctl)
        replacement_id = "proving-packet-004"
        claimed = acl.claim_packet_anchors(
            run_id=RUN_ID,
            packet_id=replacement_id,
            proposals=[{"slotId": i + 1, "anchor": a} for i, a in enumerate(PACKET_003_ANCHORS)],
            actor="owner",
            factory_home=self.factory,
        )
        replacement = ctl.plan_packet(
            run_id=RUN_ID,
            packet_id=replacement_id,
            actor="owner",
            planning=self.planning(corrected_3012=True),
            lease_seconds=3600,
        )
        self.assertEqual([slot["storyId"] for slot in replacement["slots"]], list(range(3010, 3015)))
        bound = [
            acl.bind_story_id(claim, slot["storyId"], actor="owner", factory_home=self.factory)
            for claim, slot in zip(claimed.claims, replacement["slots"])
        ]
        replacement = ctl.preflight_anchors(RUN_ID, replacement_id, actor="owner")
        for claim in bound:
            acl.mark_authoring(claim, actor="owner", factory_home=self.factory)
        replacement = ctl.emit_writer_assignments(RUN_ID, replacement_id, actor="owner")
        slot_3012 = next(slot for slot in replacement["slots"] if slot["storyId"] == 3012)
        assignment_path = ctl.packet_dir(RUN_ID, replacement_id) / slot_3012["assignment"]["path"]
        assignment = json.loads(assignment_path.read_text())
        self.assertEqual(assignment["targetLengths"], ["short", "full"])
        self.assertEqual(set(assignment["wordRanges"]), {"short", "full"})
        self.assertEqual(len(assignment["requiredArtifacts"]), 9)

    def test_unrelated_packet_001_and_002_fixtures_remain_byte_identical(self):
        ctl_1, packet_1, _ = self.make_ready("proving-packet-001", anchors=OTHER_ANCHORS_A)
        ctl_2, packet_2, _ = self.make_ready("proving-packet-002", anchors=OTHER_ANCHORS_B)
        ctl_3, packet_3, _ = self.make_ready("proving-packet-003", anchors=PACKET_003_ANCHORS)
        roots = [ctl_1.packet_dir(RUN_ID, packet_1["packetId"]), ctl_2.packet_dir(RUN_ID, packet_2["packetId"])]
        before = [_tree_hash(root) for root in roots]
        ids = {slot["storyId"] for packet in (packet_1, packet_2) for slot in packet["slots"]}
        reservation_before = {story_id: reservations.replay_ledger(self.factory)[story_id] for story_id in ids}
        claims_before = {
            key: value
            for key, value in acl.replay_ledger(self.factory).items()
            if value.packet_id in {packet_1["packetId"], packet_2["packetId"]}
        }
        self.abort(ctl_3, packet_3["packetId"])
        self.assertEqual(before, [_tree_hash(root) for root in roots])
        self.assertEqual(reservation_before,
                         {story_id: reservations.replay_ledger(self.factory)[story_id] for story_id in ids})
        self.assertEqual(claims_before, {
            key: value
            for key, value in acl.replay_ledger(self.factory).items()
            if value.packet_id in {packet_1["packetId"], packet_2["packetId"]}
        })


if __name__ == "__main__":
    unittest.main(verbosity=2)
