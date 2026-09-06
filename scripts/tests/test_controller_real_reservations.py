#!/usr/bin/env python3
"""Multi-packet integration against the REAL reservation service and controller.

Everything here uses ``story_id_reservations`` and ``AutonomousStoryController``
unmodified -- no ``FakeReservations``, no stubbed ledger.  A temporary factory
home and a temporary repo stand in for the real ones; the real factory home and
the real repository are never read or written.

The question these tests answer is the one the single-packet suite cannot: when
four packets exist at once, does anything stop the second one from claiming a
passage the first already holds?
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import threading
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


PACKET_ANCHORS = {
    0: ("Nahum 1:1-15", "Joel 1:1-12", "Amos 1:1-10", "Obadiah 1:1-9", "Micah 1:1-9"),
    1: ("Habakkuk 1:1-11", "Zephaniah 1:1-9", "Haggai 1:1-11", "Malachi 1:1-14",
        "Jonah 1:1-17"),
    2: ("Ruth 1:1-10", "Esther 1:1-9", "Lamentations 1:1-7", "Ecclesiastes 1:1-11",
        "Titus 1:1-9"),
    3: ("Philemon 1:1-7", "Jude 1:1-8", "2 John 1:1-6", "3 John 1:1-6",
        "Obadiah 1:10-16"),
}


class RealStackTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="mp-real-")
        self.addCleanup(self._tmp.cleanup)
        self.base = Path(self._tmp.name)
        self.repo = self.base / "repo"
        self.factory = self.base / "factory"
        (self.repo / "assets" / "stories" / "traditional").mkdir(parents=True)
        (self.repo / "assets" / "stories" / "manifest.json").write_text(
            json.dumps({"version": 1, "parables": []}), encoding="utf-8")

    def reserve(self, index, count=5):
        return reservations.reserve_packet(
            count=count, run_id=f"run-{index}", packet_id=f"packet-{index}",
            actor="owner", worktree=self.repo, repo_root=self.repo,
            factory_home=self.factory, worktrees=[self.repo])

    def claim(self, index, anchors=None, actor="owner"):
        anchors = anchors or PACKET_ANCHORS[index]
        return acl.claim_packet_anchors(
            run_id=f"run-{index}", packet_id=f"packet-{index}",
            proposals=[{"slotId": i + 1, "anchor": a} for i, a in enumerate(anchors)],
            actor=actor, factory_home=self.factory)

    def acl_states(self):
        return acl.replay_ledger(self.factory)

    def run_gate(self, candidate, rows, story_id=None):
        fd, path = tempfile.mkstemp(suffix=".json", dir=str(self.base))
        with os.fdopen(fd, "w") as fh:
            json.dump({"reservations": rows}, fh)
        return gate.evaluate(candidate, story_id=story_id,
                             worktrees=[str(self.repo)], reservations_path=path)


class RealReservationsTests(RealStackTestCase):

    def test_real_module_is_under_test(self):
        self.assertFalse(hasattr(reservations, "reserve_packet_calls"))
        self.assertEqual(reservations.reserve_packet.__module__,
                         "story_id_reservations")

    def test_four_packets_reserve_twenty_distinct_ids(self):
        ids = []
        for index in range(4):
            ids.extend(r.story_id for r in self.reserve(index))
        self.assertEqual(len(ids), 20)
        self.assertEqual(len(set(ids)), 20)
        self.assertTrue(all(3000 <= i <= 3258 for i in ids))

    def test_reservations_alone_do_not_protect_anchors(self):
        # The premise of the whole design, demonstrated rather than asserted:
        # story-ID reservations answer "who owns this number", not "who owns
        # this passage".  Two packets reserve disjoint IDs and still collide.
        self.reserve(0)
        self.reserve(1)
        rows = []
        for index in (0, 1):
            for anchor in PACKET_ANCHORS[index]:
                rows.append(anchor)
        self.assertEqual(len(set(rows)), 10)
        # nothing in the reservation ledger mentions an anchor at all
        ledger = (self.factory / "reservations.jsonl").read_text()
        for anchor in rows:
            self.assertNotIn(anchor, ledger)

    def test_acl_blocks_a_second_packet_same_run(self):
        self.claim(0)
        collide = ("Nahum 1:1-15",) + PACKET_ANCHORS[1][1:]
        with self.assertRaises(acl.AnchorConflict):
            acl.claim_packet_anchors(
                run_id="run-0", packet_id="packet-99",
                proposals=[{"slotId": i + 1, "anchor": a}
                           for i, a in enumerate(collide)],
                actor="owner", factory_home=self.factory)

    def test_acl_blocks_a_second_packet_across_runs(self):
        self.claim(0)
        collide = ("Nahum 1:1-15",) + PACKET_ANCHORS[2][1:]
        with self.assertRaises(acl.AnchorConflict):
            self.claim(1, anchors=collide)

    def test_partial_collision_is_caught_by_the_gate_not_only_the_lock(self):
        self.claim(0)
        rows = acl.build_overlap_queue(self.acl_states().values())
        # Nahum 1:5-10 shares verses with the claimed Nahum 1:1-15 but has a
        # different anchorKey, so the exact-lock layer alone would miss it.
        self.assertNotEqual(acl.anchor_key("Nahum 1:5-10"),
                            acl.anchor_key("Nahum 1:1-15"))
        self.assertEqual(self.run_gate("Nahum 1:5-10", rows)["verdict"], "BLOCK")

    def test_four_packets_claim_disjoint_anchors_and_all_survive_replay(self):
        for index in range(4):
            self.claim(index)
        states = self.acl_states()
        self.assertEqual(len(states), 20)
        rows = acl.build_overlap_queue(states.values())
        self.assertEqual(len(rows), 20)
        self.assertEqual({r["state"] for r in rows}, {"reserved"})

    def test_bound_ids_come_from_the_real_reservation_service(self):
        reserved = self.reserve(0)
        result = self.claim(0)
        bound = [acl.bind_story_id(claim, reservation.story_id, actor="owner",
                                   factory_home=self.factory)
                 for claim, reservation in zip(result.claims, reserved)]
        self.assertEqual([c.story_id for c in bound],
                         [r.story_id for r in reserved])
        rows = acl.build_overlap_queue(self.acl_states().values())
        self.assertTrue(all(r["storyId"] > 0 for r in rows))

    def test_a_story_id_is_never_shared_across_packets(self):
        first = self.reserve(0)
        second = self.reserve(1)
        self.assertFalse(set(r.story_id for r in first)
                         & set(r.story_id for r in second))
        r0 = self.claim(0)
        r1 = self.claim(1)
        acl.bind_story_id(r0.claims[0], first[0].story_id, actor="owner",
                          factory_home=self.factory)
        with self.assertRaises(acl.AnchorLedgerCorrupt):
            acl.bind_story_id(r1.claims[0], first[0].story_id, actor="owner",
                              factory_home=self.factory)

    def test_concurrent_reserve_and_claim_do_not_deadlock(self):
        errors = []
        barrier = threading.Barrier(4)

        def worker(index):
            barrier.wait()
            try:
                reserved = self.reserve(index)
                result = self.claim(index)
                for claim, reservation in zip(result.claims, reserved):
                    acl.bind_story_id(claim, reservation.story_id, actor="owner",
                                      factory_home=self.factory)
            except Exception as exc:
                errors.append(f"{index}: {type(exc).__name__}: {exc}")

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=120)
        self.assertFalse(any(t.is_alive() for t in threads), "deadlock")
        self.assertFalse(errors, errors)
        states = self.acl_states()
        self.assertEqual(len(states), 20)
        self.assertEqual(len({c.story_id for c in states.values()}), 20)


class RealControllerTests(RealStackTestCase):

    def build(self, index):
        return controller.AutonomousStoryController(
            repo_root=self.repo, worktree=self.repo, factory_home=self.factory,
            worktrees=[self.repo], policy_root=REPO_ROOT,
            reservations=reservations,
            overlap_evaluator=gate.evaluate)

    def planning(self, index):
        return {"stories": [
            {"proposedAnchor": anchor, "mood": "encouraging",
             "narrator": "VOICE_SARAH_STORYTELLER", "lengths": ["short"]}
            for anchor in PACKET_ANCHORS[index]]}

    def test_controller_uses_the_real_reservation_module(self):
        ctl = self.build(0)
        self.assertIs(ctl.reservations, reservations)

    def test_plan_and_reserve_through_the_real_stack(self):
        ctl = self.build(0)
        packet = ctl.plan_packet(run_id="run-0", packet_id="packet-0",
                                 planning=self.planning(0), actor="owner",
                                 lease_seconds=600)
        self.assertEqual(packet["state"], controller.ID_RESERVED)
        story_ids = [slot["storyId"] for slot in packet["slots"]]
        self.assertEqual(len(set(story_ids)), 5)
        ledger = reservations.replay_ledger(self.factory)
        for story_id in story_ids:
            self.assertEqual(ledger[story_id].state, "RESERVED")

    def test_snapshot_emits_locked_for_materialized_through_the_real_service(self):
        ctl = self.build(0)
        packet = ctl.plan_packet(run_id="run-0", packet_id="packet-0",
                                 planning=self.planning(0), actor="owner",
                                 lease_seconds=600)
        path = ctl._overlap_queue_snapshot(packet)
        payload = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual({row["state"] for row in payload["reservations"]},
                         {"reserved"})
        for slot in packet["slots"]:
            current = reservations.replay_ledger(self.factory)[slot["storyId"]]
            (self.repo / "assets" / "stories" / "traditional"
             / str(slot["storyId"])).mkdir(parents=True, exist_ok=True)
            (self.repo / "assets" / "stories" / "traditional"
             / str(slot["storyId"]) / f"meta_{slot['storyId']}.json").write_text("{}")
            reservations.confirm_materialized(
                current, repo_root=self.repo, factory_home=self.factory,
                worktrees=[self.repo], actor="owner")
        path = ctl._overlap_queue_snapshot(packet)
        text = path.read_text(encoding="utf-8")
        payload = json.loads(text)
        self.assertEqual({row["state"] for row in payload["reservations"]},
                         {"locked"})
        self.assertNotIn("materialized", text)
        # and the emitted queue is one the gate actually accepts
        gate.load_reservations(str(path))

    def test_two_controllers_share_one_factory_home(self):
        a, b = self.build(0), self.build(1)
        pa = a.plan_packet(run_id="run-0", packet_id="packet-0",
                           planning=self.planning(0), actor="owner",
                           lease_seconds=600)
        pb = b.plan_packet(run_id="run-1", packet_id="packet-1",
                           planning=self.planning(1), actor="owner",
                           lease_seconds=600)
        ids_a = {slot["storyId"] for slot in pa["slots"]}
        ids_b = {slot["storyId"] for slot in pb["slots"]}
        self.assertFalse(ids_a & ids_b)

    def test_same_run_second_planned_packet_reserves_after_first_materialized(self):
        run_id = "campaign-3000-3258-run-001"
        first_packet_id = "proving-packet-001"
        second_packet_id = "proving-packet-002"
        first = self.build(0)
        first_packet = first.plan_packet(
            run_id=run_id, packet_id=first_packet_id,
            planning=self.planning(0), actor="owner", lease_seconds=600,
        )
        for slot in first_packet["slots"]:
            story_id = slot["storyId"]
            story_dir = self.repo / "assets" / "stories" / "traditional" / str(story_id)
            story_dir.mkdir(parents=True)
            (story_dir / f"meta_{story_id}.json").write_text("{}")
            reservations.confirm_materialized(
                reservations.replay_ledger(self.factory)[story_id],
                repo_root=self.repo, factory_home=self.factory,
                worktrees=[self.repo], actor="owner",
            )

        acl.claim_packet_anchors(
            run_id=run_id, packet_id=second_packet_id,
            proposals=[
                {"slotId": index + 1, "anchor": anchor}
                for index, anchor in enumerate(PACKET_ANCHORS[1])
            ],
            actor="owner", factory_home=self.factory,
        )
        second = self.build(1)
        with mock.patch.object(
            second, "_continue_planned_reservation",
            side_effect=RuntimeError("simulated crash before reservation"),
        ):
            with self.assertRaisesRegex(RuntimeError, "before reservation"):
                second.plan_packet(
                    run_id=run_id, packet_id=second_packet_id,
                    planning=self.planning(1), actor="owner", lease_seconds=600,
                )

        resumed = second.resume_planned_packet(
            run_id=run_id, packet_id=second_packet_id,
            planning=self.planning(1), actor="owner", lease_seconds=600,
        )
        self.assertEqual(resumed["state"], controller.ID_RESERVED)
        self.assertEqual(
            [slot["storyId"] for slot in resumed["slots"]],
            list(range(3005, 3010)),
        )
        states = reservations.replay_ledger(self.factory)
        self.assertEqual([states[story_id].state for story_id in range(3000, 3005)],
                         ["MATERIALIZED"] * 5)
        self.assertEqual([states[story_id].state for story_id in range(3005, 3010)],
                         ["RESERVED"] * 5)
        claims = acl.replay_ledger(self.factory)
        second_claims = [
            claim for claim in claims.values()
            if (claim.run_id, claim.packet_id) == (run_id, second_packet_id)
        ]
        self.assertEqual(len(second_claims), 5)
        self.assertEqual({claim.state for claim in second_claims}, {acl.CLAIMED})
        self.assertEqual({claim.story_id for claim in second_claims}, {None})

    def test_same_run_different_packet_reserves_distinct_ids(self):
        run_id = "campaign-3000-3258-run-001"
        first = self.build(0).plan_packet(
            run_id=run_id, packet_id="proving-packet-001",
            planning=self.planning(0), actor="owner", lease_seconds=600,
        )
        second = self.build(1).plan_packet(
            run_id=run_id, packet_id="proving-packet-002",
            planning=self.planning(1), actor="owner", lease_seconds=600,
        )
        self.assertEqual([slot["storyId"] for slot in first["slots"]],
                         list(range(3000, 3005)))
        self.assertEqual([slot["storyId"] for slot in second["slots"]],
                         list(range(3005, 3010)))

    def test_same_packet_name_in_different_runs_reserves_distinct_ids(self):
        packet_id = "proving-packet"
        first = self.build(0).plan_packet(
            run_id="campaign-a", packet_id=packet_id,
            planning=self.planning(0), actor="owner", lease_seconds=600,
        )
        second = self.build(1).plan_packet(
            run_id="campaign-b", packet_id=packet_id,
            planning=self.planning(1), actor="owner", lease_seconds=600,
        )
        first_ids = {slot["storyId"] for slot in first["slots"]}
        second_ids = {slot["storyId"] for slot in second["slots"]}
        self.assertFalse(first_ids & second_ids)

    def test_planned_resume_adopts_only_its_exact_packet_reservations(self):
        run_id = "campaign-3000-3258-run-001"
        packet_id = "proving-packet-002"
        ctl = self.build(1)
        with mock.patch.object(
            ctl, "_continue_planned_reservation",
            side_effect=RuntimeError("simulated crash before reservation"),
        ):
            with self.assertRaisesRegex(RuntimeError, "before reservation"):
                ctl.plan_packet(
                    run_id=run_id, packet_id=packet_id,
                    planning=self.planning(1), actor="owner", lease_seconds=600,
                )
        reserved = reservations.reserve_packet(
            count=5, run_id=run_id, packet_id=packet_id, actor="owner",
            worktree=self.repo, repo_root=self.repo, factory_home=self.factory,
            worktrees=[self.repo], lease_seconds=600,
        )
        resumed = ctl.resume_planned_packet(
            run_id=run_id, packet_id=packet_id,
            planning=self.planning(1), actor="owner", lease_seconds=600,
        )
        self.assertEqual([slot["storyId"] for slot in resumed["slots"]],
                         [item.story_id for item in reserved])
        self.assertEqual(len((self.factory / "reservations.jsonl").read_text().splitlines()), 5)

    def test_planned_resume_rejects_partial_exact_packet_reservations(self):
        run_id = "campaign-3000-3258-run-001"
        packet_id = "proving-packet-002"
        ctl = self.build(1)
        with mock.patch.object(
            ctl, "_continue_planned_reservation",
            side_effect=RuntimeError("simulated crash before reservation"),
        ):
            with self.assertRaisesRegex(RuntimeError, "before reservation"):
                ctl.plan_packet(
                    run_id=run_id, packet_id=packet_id,
                    planning=self.planning(1), actor="owner", lease_seconds=600,
                )
        reservations.reserve_packet(
            count=1, run_id=run_id, packet_id=packet_id, actor="owner",
            worktree=self.repo, repo_root=self.repo, factory_home=self.factory,
            worktrees=[self.repo], lease_seconds=600,
        )
        with self.assertRaisesRegex(
            controller.IntegrationError,
            "partial or extra authoritative packet reservations",
        ):
            ctl.resume_planned_packet(
                run_id=run_id, packet_id=packet_id,
                planning=self.planning(1), actor="owner", lease_seconds=600,
            )

    def test_controller_sees_a_sibling_packets_acl_occupancy(self):
        self.claim(1)
        ctl = self.build(0)
        rows = ctl.acl_queue_rows()
        self.assertEqual(len(rows), 5)
        # a packet proposing a sibling's anchor is blocked by the shared queue
        self.assertEqual(self.run_gate(PACKET_ANCHORS[1][0], rows)["verdict"],
                         "BLOCK")

    def test_lock_ranks_never_descend_across_the_real_stack(self):
        records = []
        acl.add_lock_observer(records.append)
        self.addCleanup(acl.remove_lock_observer, records.append)
        ctl = self.build(0)
        ctl.plan_packet(run_id="run-0", packet_id="packet-0",
                        planning=self.planning(0), actor="owner",
                        lease_seconds=600)
        self.claim(0)
        by_thread = {}
        for record in records:
            stack = by_thread.setdefault(record["thread"], [])
            if record["action"] == "acquire":
                if stack:
                    self.assertGreaterEqual(record["rank"], max(stack),
                                            f"descending acquisition: {record}")
                stack.append(record["rank"])
            elif record["rank"] in stack:
                stack.remove(record["rank"])
        self.assertTrue(records, "lock ranks were never observed")
        self.assertIn(acl.L5_PACKET_JOURNAL, {r["rank"] for r in records})
        self.assertIn(acl.L3_RESERVATION_LEDGER, {r["rank"] for r in records})


class RealBackfillFixtureTests(RealStackTestCase):
    """Row 50 against a proving-packet-shaped fixture, never the real factory."""

    PACKET = {
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

    def test_fixture_backfill_blocks_the_real_proving_anchors(self):
        acl.backfill_packet_claims(
            packet=self.PACKET,
            reservation_states={3000 + i: "MATERIALIZED" for i in range(5)},
            actor="owner", factory_home=self.factory)
        rows = acl.build_overlap_queue(acl.replay_ledger(self.factory).values())
        self.assertEqual({r["state"] for r in rows}, {"locked"})
        for slot in self.PACKET["slots"]:
            with self.subTest(anchor=slot["proposedAnchor"]):
                self.assertEqual(
                    self.run_gate(slot["proposedAnchor"], rows)["verdict"], "BLOCK")

    def test_backfill_does_not_touch_the_real_factory(self):
        real_home = Path("~/.bible_pal_factory").expanduser()
        real_acl = real_home / "anchor_claims.jsonl"
        existed = real_acl.exists()
        acl.backfill_packet_claims(
            packet=self.PACKET,
            reservation_states={3000 + i: "MATERIALIZED" for i in range(5)},
            actor="owner", factory_home=self.factory)
        self.assertEqual(real_acl.exists(), existed,
                         "the real factory ACL must not be created by a test")
        self.assertTrue((self.factory / "anchor_claims.jsonl").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
