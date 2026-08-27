#!/usr/bin/env python3
"""Text-only Milestone-1 controller for one five-story proving packet.

The controller deliberately stops at ``READY_FOR_HUMAN_REVIEW``.  It emits
writer/reviewer artifacts but never invokes a model, TTS, R2, publication, or
Git mutation.  Mutable runtime state lives under the shared factory home; the
append-only event journal is authoritative and ``packet.json`` is only a
convenience snapshot.
"""

from __future__ import annotations

import argparse
import copy
import dataclasses
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import uuid
from pathlib import Path, PurePosixPath
from typing import Iterable, Mapping

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError


MODULE_PATH = Path(__file__).resolve()
POLICY_REPO_ROOT = MODULE_PATH.parent.parent.parent
SCRIPTS_DIR = POLICY_REPO_ROOT / "scripts"
for _path in (str(SCRIPTS_DIR), str(MODULE_PATH.parent)):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import preflight_anchor_overlap as overlap_gate  # noqa: E402
import story_id_reservations as reservation_service  # noqa: E402
from claude_validator import (  # noqa: E402
    check_meta_text,
    check_reflection_banned,
    validate_lane_identity,
    validate_traditional,
)
from lib import reconstruction_check  # noqa: E402
from story_prompts import REFLECTION_WORD_RANGE, TRADITIONAL_RANGES  # noqa: E402
from story_voice_registry import VoiceValidationError, validate_story_voice  # noqa: E402
from tts_voice_gate import (  # noqa: E402
    TtsVoiceGateError,
    resolve_new_story_tts_voice,
)


CONTROLLER_SCHEMA_VERSION = 1
CONTROLLER_MILESTONE = "M1_TEXT_ONLY"
PACKET_SIZE = 5
MAX_CORRECTION_ROUNDS = 3

PLANNED = "PLANNED"
ID_RESERVED = "ID_RESERVED"
ANCHOR_PREFLIGHT_PASSED = "ANCHOR_PREFLIGHT_PASSED"
ASSIGNMENT_READY = "ASSIGNMENT_READY"
WRITER_OUTPUT_RECEIVED = "WRITER_OUTPUT_RECEIVED"
VALIDATION_PASSED = "VALIDATION_PASSED"
REVIEW_READY = "REVIEW_READY"
REVIEW_CHANGES_REQUESTED = "REVIEW_CHANGES_REQUESTED"
CORRECTION_READY = "CORRECTION_READY"
REVIEW_APPROVED = "REVIEW_APPROVED"
READY_FOR_HUMAN_REVIEW = "READY_FOR_HUMAN_REVIEW"
QUARANTINED = "QUARANTINED"
ABORTED = "ABORTED"

STATES = frozenset({
    PLANNED,
    ID_RESERVED,
    ANCHOR_PREFLIGHT_PASSED,
    ASSIGNMENT_READY,
    WRITER_OUTPUT_RECEIVED,
    VALIDATION_PASSED,
    REVIEW_READY,
    REVIEW_CHANGES_REQUESTED,
    CORRECTION_READY,
    REVIEW_APPROVED,
    READY_FOR_HUMAN_REVIEW,
    QUARANTINED,
    ABORTED,
})

LEGAL_TRANSITIONS = {
    PLANNED: frozenset({ID_RESERVED, ABORTED, QUARANTINED}),
    ID_RESERVED: frozenset({ANCHOR_PREFLIGHT_PASSED, ABORTED, QUARANTINED}),
    ANCHOR_PREFLIGHT_PASSED: frozenset({ASSIGNMENT_READY, ABORTED, QUARANTINED}),
    ASSIGNMENT_READY: frozenset({WRITER_OUTPUT_RECEIVED, ABORTED, QUARANTINED}),
    WRITER_OUTPUT_RECEIVED: frozenset({
        VALIDATION_PASSED, CORRECTION_READY, ABORTED, QUARANTINED,
    }),
    VALIDATION_PASSED: frozenset({REVIEW_READY, ABORTED, QUARANTINED}),
    REVIEW_READY: frozenset({
        REVIEW_APPROVED, REVIEW_CHANGES_REQUESTED, QUARANTINED, ABORTED,
    }),
    REVIEW_CHANGES_REQUESTED: frozenset({CORRECTION_READY, QUARANTINED, ABORTED}),
    CORRECTION_READY: frozenset({WRITER_OUTPUT_RECEIVED, QUARANTINED, ABORTED}),
    REVIEW_APPROVED: frozenset({READY_FOR_HUMAN_REVIEW, QUARANTINED}),
    READY_FOR_HUMAN_REVIEW: frozenset(),
    QUARANTINED: frozenset(),
    ABORTED: frozenset(),
}

SAME_STATE_EVENTS = frozenset({
    "ANCHOR_PREFLIGHT_REFUSED",
    "VALIDATION_REFUSED",
    "MATERIALIZATION_RECORDED",
})

REVIEW_VERDICTS = frozenset({"APPROVED", "CHANGES_REQUESTED", "REJECTED"})
MOODS = frozenset({
    "encouraging", "calm_peaceful", "grateful", "brave_courage",
    "hurting", "anxious", "joyful", "weary",
})
LENGTHS = ("short", "full", "long")
LANES = ("web", "kjv")
SAFE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
EVENT_FIELDS = frozenset({
    "schemaVersion", "eventId", "sequence", "timestamp", "eventType",
    "runId", "packetId", "storyId", "fromState", "toState", "actor",
    "reason", "evidenceHash", "packet",
})


class ControllerError(Exception):
    """Base class for typed controller failures."""


class ControllerConfigError(ControllerError):
    """Planning/configuration input is unsafe or incomplete."""


class JournalCorrupt(ControllerError):
    """The controller event history cannot be trusted."""


class IllegalControllerTransition(JournalCorrupt):
    """An event or API call attempts an illegal state transition."""


class IntegrationError(ControllerError):
    """A prerequisite authority disagrees with controller state."""


class OverlapRejected(ControllerError):
    """An overlap verdict other than PASS stopped autonomous authoring."""


class WorkspaceRejected(ControllerError):
    """Writer output violated the isolated workspace contract."""


class ValidationFailed(ControllerError):
    """Ordered text/schema/campaign validation did not pass."""

    def __init__(self, errors: Iterable[str]):
        self.errors = tuple(errors)
        super().__init__("; ".join(self.errors))


class ReviewRejected(ControllerError):
    """Reviewer input is malformed or cannot advance the packet."""


class SafetyViolation(ControllerError):
    """A production/runtime safety invariant would be violated."""


def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
    ).encode("utf-8")


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hash_value(value: object) -> str:
    return _sha256_bytes(_canonical_bytes(value))


def _hash_file(path: Path) -> str:
    try:
        return _sha256_bytes(path.read_bytes())
    except OSError as exc:
        raise SafetyViolation(f"cannot hash required file {path}: {exc}") from exc


def _utc_timestamp(now: dt.datetime | None = None) -> str:
    value = now or dt.datetime.now(dt.timezone.utc)
    if value.tzinfo is None:
        raise ControllerConfigError("controller timestamps must be timezone-aware")
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _strict_json_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ControllerConfigError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def _load_json(path: Path, *, error_type=ControllerConfigError):
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=_strict_json_pairs)
    except ControllerConfigError:
        raise
    except (OSError, json.JSONDecodeError) as exc:
        raise error_type(f"cannot read JSON {path}: {exc}") from exc


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _safe_identifier(value: object, field: str) -> str:
    if not isinstance(value, str) or not SAFE_ID_RE.fullmatch(value):
        raise ControllerConfigError(
            f"{field} must match {SAFE_ID_RE.pattern!r}; traversal is forbidden"
        )
    return value


def _write_all(fd: int, data: bytes) -> None:
    offset = 0
    while offset < len(data):
        written = os.write(fd, data[offset:])
        if written <= 0:
            raise OSError("short write while persisting controller evidence")
        offset += written


def _fsync_dir(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    fd = os.open(path, flags)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _atomic_write(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw_tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(raw_tmp)
    try:
        os.fchmod(fd, mode)
        _write_all(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    try:
        os.replace(tmp, path)
        _fsync_dir(path.parent)
    except Exception:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise


def _write_json(path: Path, value: object) -> None:
    _atomic_write(path, _canonical_bytes(value) + b"\n")


def _event_hash(event_without_hash: Mapping[str, object]) -> str:
    return _hash_value(event_without_hash)


def _validate_reservation_ref(ref: object, story_id: int) -> None:
    if not isinstance(ref, dict):
        raise JournalCorrupt(f"story {story_id} has no reservation reference")
    required = {
        "storyId", "runId", "packetId", "actor", "leaseToken", "worktree",
        "reservedAt", "leaseExpiresAt", "state",
    }
    if set(ref) != required:
        raise JournalCorrupt(f"story {story_id} reservation reference fields differ")
    if ref["storyId"] != story_id or ref["state"] not in {
        "RESERVED", "MATERIALIZED", "RELEASED", "RETIRED",
    }:
        raise JournalCorrupt(f"story {story_id} reservation reference is invalid")
    for field in required - {"storyId"}:
        if not isinstance(ref[field], str) or not ref[field]:
            raise JournalCorrupt(f"story {story_id} reservation {field} is invalid")


def validate_packet_model(packet: object) -> None:
    """Validate the persisted packet model independently of filesystem state."""

    if not isinstance(packet, dict):
        raise JournalCorrupt("packet snapshot is not an object")
    required = {
        "schemaVersion", "controllerMilestone", "runId", "packetId",
        "createdAt", "updatedAt", "state", "actor", "repoRoot", "worktree",
        "manifestHashAtPlan", "correctionRound", "reviewRound", "slots",
        "evidenceHashes",
    }
    if set(packet) != required:
        raise JournalCorrupt("packet snapshot fields differ from the M1 contract")
    if packet["schemaVersion"] != CONTROLLER_SCHEMA_VERSION:
        raise JournalCorrupt("unsupported controller schema version")
    if packet["controllerMilestone"] != CONTROLLER_MILESTONE:
        raise JournalCorrupt("packet is not a Milestone-1 text-only packet")
    try:
        _safe_identifier(packet["runId"], "runId")
        _safe_identifier(packet["packetId"], "packetId")
    except ControllerConfigError as exc:
        raise JournalCorrupt(f"packet identity is invalid: {exc}") from exc
    if packet["state"] not in STATES:
        raise JournalCorrupt(f"unknown packet state {packet['state']!r}")
    if not HEX64_RE.fullmatch(packet["manifestHashAtPlan"] or ""):
        raise JournalCorrupt("manifestHashAtPlan is not SHA-256")
    if type(packet["correctionRound"]) is not int or not 0 <= packet["correctionRound"] <= MAX_CORRECTION_ROUNDS:
        raise JournalCorrupt("correctionRound is outside the M1 cap")
    if type(packet["reviewRound"]) is not int or packet["reviewRound"] < 0:
        raise JournalCorrupt("reviewRound is invalid")
    if not isinstance(packet["evidenceHashes"], dict):
        raise JournalCorrupt("evidenceHashes is not an object")
    slots = packet["slots"]
    if not isinstance(slots, list) or len(slots) != PACKET_SIZE:
        raise JournalCorrupt(f"packet must contain exactly {PACKET_SIZE} slots")

    slot_required = {
        "slotId", "storyId", "reservation", "proposedAnchor", "narrator",
        "mode", "kidFriendly", "lanes", "targetLengths", "mood",
        "authoringBrief", "state", "writerAttempts", "correctionHistory",
        "overlapEvidence", "assignment", "workspace", "validationEvidence",
        "reviewerVerdict", "unresolvedFindings", "materialization",
        "finalReadiness",
    }
    story_ids = []
    for index, slot in enumerate(slots, 1):
        if not isinstance(slot, dict) or set(slot) != slot_required:
            raise JournalCorrupt(f"slot {index} fields differ from the M1 contract")
        if slot["slotId"] != index:
            raise JournalCorrupt("slot IDs must be ordered 1 through 5")
        if slot["state"] != packet["state"]:
            raise JournalCorrupt("slot state disagrees with packet state")
        if slot["mode"] != "traditional" or slot["kidFriendly"] is not False:
            raise JournalCorrupt("M1 supports adult Traditional stories only")
        if slot["lanes"] != ["web", "kjv"]:
            raise JournalCorrupt("M1 requires deterministic WEB and KJV lanes")
        lengths = slot["targetLengths"]
        if not isinstance(lengths, list) or not lengths or any(v not in LENGTHS for v in lengths):
            raise JournalCorrupt("slot targetLengths are invalid")
        if len(set(lengths)) != len(lengths) or lengths != sorted(lengths, key=LENGTHS.index):
            raise JournalCorrupt("slot targetLengths must be unique and canonical")
        if type(slot["writerAttempts"]) is not int or slot["writerAttempts"] < 0:
            raise JournalCorrupt("writerAttempts is invalid")
        if not isinstance(slot["correctionHistory"], list):
            raise JournalCorrupt("correctionHistory is not a list")
        story_id = slot["storyId"]
        if packet["state"] == PLANNED:
            if story_id is not None or slot["reservation"] is not None:
                raise JournalCorrupt("PLANNED slots may not claim story IDs")
        else:
            if type(story_id) is not int or not 3000 <= story_id <= 3258:
                raise JournalCorrupt("story ID is outside campaign range 3000-3258")
            _validate_reservation_ref(slot["reservation"], story_id)
            story_ids.append(story_id)
    if len(story_ids) != len(set(story_ids)):
        raise JournalCorrupt("duplicate story ID in packet")


def _validate_event(event: object, expected_sequence: int) -> dict:
    if not isinstance(event, dict) or set(event) != EVENT_FIELDS:
        raise JournalCorrupt(f"event {expected_sequence} has invalid fields")
    if event["schemaVersion"] != CONTROLLER_SCHEMA_VERSION:
        raise JournalCorrupt("event schema version is unsupported")
    if event["sequence"] != expected_sequence:
        raise JournalCorrupt(
            f"event sequence is out of order: expected {expected_sequence}, got {event['sequence']}"
        )
    if not isinstance(event["eventId"], str) or not event["eventId"]:
        raise JournalCorrupt("eventId is missing")
    if event["fromState"] is not None and event["fromState"] not in STATES:
        raise JournalCorrupt("event fromState is unknown")
    if event["toState"] not in STATES:
        raise JournalCorrupt("event toState is unknown")
    if event["storyId"] is not None and type(event["storyId"]) is not int:
        raise JournalCorrupt("event storyId is invalid")
    supplied_hash = event["evidenceHash"]
    core = dict(event)
    del core["evidenceHash"]
    if not isinstance(supplied_hash, str) or supplied_hash != _event_hash(core):
        raise JournalCorrupt("event evidence hash mismatch")
    validate_packet_model(event["packet"])
    if event["packet"]["state"] != event["toState"]:
        raise JournalCorrupt("event packet state disagrees with toState")
    if event["runId"] != event["packet"]["runId"] or event["packetId"] != event["packet"]["packetId"]:
        raise JournalCorrupt("event identity disagrees with packet")
    return event


def _replay_bytes(raw: bytes, source: str) -> dict | None:
    if not raw:
        return None
    if not raw.endswith(b"\n"):
        raise JournalCorrupt(f"truncated controller journal: {source}")
    try:
        text = raw.decode("utf-8")
    except UnicodeError as exc:
        raise JournalCorrupt(f"controller journal is not UTF-8: {source}") from exc
    current = None
    event_ids = set()
    last_timestamp = None
    for sequence, line in enumerate(text.splitlines(), 1):
        if not line:
            raise JournalCorrupt(f"blank controller event at line {sequence}")
        try:
            event = json.loads(line, object_pairs_hook=_strict_json_pairs)
        except (json.JSONDecodeError, ControllerConfigError) as exc:
            raise JournalCorrupt(f"malformed controller event at line {sequence}: {exc}") from exc
        event = _validate_event(event, sequence)
        if event["eventId"] in event_ids:
            raise JournalCorrupt(f"duplicate eventId at line {sequence}")
        event_ids.add(event["eventId"])
        if last_timestamp is not None and event["timestamp"] < last_timestamp:
            raise JournalCorrupt("controller event timestamps move backward")
        last_timestamp = event["timestamp"]

        if current is None:
            if event["eventType"] != "PACKET_PLANNED" or event["fromState"] is not None or event["toState"] != PLANNED:
                raise IllegalControllerTransition("journal must begin with PACKET_PLANNED")
        else:
            if event["runId"] != current["runId"] or event["packetId"] != current["packetId"]:
                raise JournalCorrupt("controller identity changes during replay")
            if event["fromState"] != current["state"]:
                raise IllegalControllerTransition(
                    f"event declares {event['fromState']!r}, replay derived {current['state']!r}"
                )
            if event["toState"] == current["state"]:
                if event["eventType"] not in SAME_STATE_EVENTS:
                    raise IllegalControllerTransition(
                        f"same-state event {event['eventType']!r} is not authorized"
                    )
            elif event["toState"] not in LEGAL_TRANSITIONS[current["state"]]:
                raise IllegalControllerTransition(
                    f"illegal controller transition {current['state']} -> {event['toState']}"
                )
        current = event["packet"]
    return current


def _packet_dir(factory_home: Path, run_id: str, packet_id: str) -> Path:
    return factory_home / "runs" / run_id / "packets" / packet_id


def replay_packet(
    factory_home: os.PathLike[str] | str,
    run_id: str,
    packet_id: str,
) -> dict:
    """Strictly reconstruct a packet from its append-only journal."""

    run_id = _safe_identifier(run_id, "runId")
    packet_id = _safe_identifier(packet_id, "packetId")
    journal = _packet_dir(Path(factory_home).expanduser().resolve(), run_id, packet_id) / "events.jsonl"
    try:
        fd = os.open(journal, os.O_RDONLY | (getattr(os, "O_NOFOLLOW", 0)))
    except OSError as exc:
        raise JournalCorrupt(f"cannot open controller journal {journal}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_SH)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise JournalCorrupt("controller journal is not a regular file")
        chunks = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        packet = _replay_bytes(b"".join(chunks), str(journal))
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
    if packet is None:
        raise JournalCorrupt("controller journal contains no events")
    return packet


def _reservation_to_dict(reservation) -> dict:
    return {
        "storyId": reservation.story_id,
        "runId": reservation.run_id,
        "packetId": reservation.packet_id,
        "actor": reservation.actor,
        "leaseToken": reservation.lease_token,
        "worktree": reservation.worktree,
        "reservedAt": reservation.reserved_at,
        "leaseExpiresAt": reservation.lease_expires_at,
        "state": reservation.state,
    }


def _reservation_from_dict(module, value: dict):
    return module.Reservation(
        story_id=value["storyId"],
        run_id=value["runId"],
        packet_id=value["packetId"],
        actor=value["actor"],
        lease_token=value["leaseToken"],
        worktree=value["worktree"],
        reserved_at=value["reservedAt"],
        lease_expires_at=value["leaseExpiresAt"],
        state=value["state"],
    )


def expected_artifact_names(story_id: int, lengths: Iterable[str]) -> tuple[str, ...]:
    names = []
    for length in lengths:
        for lane in LANES:
            names.append(f"story_{story_id}_traditional_{lane}_{length}.txt")
    names.extend((
        f"reflection_{story_id}_traditional_web.txt",
        f"reflection_{story_id}_traditional_kjv.txt",
        f"scripture_{story_id}_web.txt",
        f"scripture_{story_id}_kjv.txt",
        f"meta_{story_id}.json",
    ))
    return tuple(names)


def _tree_hash(directory: Path, names: Iterable[str]) -> tuple[str, dict[str, str]]:
    hashes = {}
    for name in sorted(names):
        path = directory / name
        try:
            info = path.lstat()
        except OSError as exc:
            raise SafetyViolation(f"required artifact unavailable: {path}: {exc}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise SafetyViolation(f"artifact is not an ordinary file: {path}")
        hashes[name] = _hash_file(path)
    return _hash_value(hashes), hashes


class _AttemptSource:
    """Minimal reconstruction-check content source backed by one attempt dir."""

    name = "controller-runtime-workspace"

    def __init__(self, directory: Path):
        self.directory = directory

    def _path(self, rel: str) -> Path:
        name = PurePosixPath(rel).name
        path = self.directory / name
        if not _is_within(path.resolve(strict=False), self.directory.resolve()):
            raise reconstruction_check.ContentUnavailable("runtime path escapes attempt directory")
        return path

    def exists(self, rel: str) -> bool:
        return self._path(rel).is_file()

    def mode(self, rel: str) -> int:
        path = self._path(rel)
        try:
            info = path.lstat()
        except OSError as exc:
            raise reconstruction_check.ContentUnavailable(str(exc)) from exc
        if stat.S_ISLNK(info.st_mode):
            return reconstruction_check.SYMLINK_MODE
        return reconstruction_check.NORMAL_FILE_MODE

    def read_text(self, rel: str) -> str:
        try:
            return self._path(rel).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise reconstruction_check.ContentUnavailable(str(exc)) from exc


class AutonomousStoryController:
    """Manual, event-sourced controller for exactly one five-story packet."""

    def __init__(
        self,
        *,
        repo_root: os.PathLike[str] | str,
        worktree: os.PathLike[str] | str,
        factory_home: os.PathLike[str] | str | None = None,
        worktrees: Iterable[os.PathLike[str] | str] | None = None,
        policy_root: os.PathLike[str] | str = POLICY_REPO_ROOT,
        reservations=reservation_service,
        overlap_evaluator=None,
        clock=None,
    ):
        self.repo_root = Path(repo_root).expanduser().resolve(strict=True)
        self.worktree = Path(worktree).expanduser().resolve(strict=True)
        raw_home = factory_home or os.environ.get("BIBLE_PAL_FACTORY_HOME") or (Path.home() / ".bible_pal_factory")
        self.factory_home = Path(raw_home).expanduser().resolve(strict=False)
        if _is_within(self.factory_home, self.repo_root) or _is_within(self.factory_home, self.worktree):
            raise ControllerConfigError("factory home must remain outside every repository worktree")
        self.worktrees = tuple(Path(p).expanduser().resolve(strict=True) for p in worktrees) if worktrees is not None else None
        self.policy_root = Path(policy_root).expanduser().resolve(strict=True)
        self.reservations = reservations
        self.overlap_evaluator = overlap_evaluator or overlap_gate.evaluate
        self.clock = clock or (lambda: dt.datetime.now(dt.timezone.utc))

    def _now(self) -> str:
        return _utc_timestamp(self.clock())

    def packet_dir(self, run_id: str, packet_id: str) -> Path:
        return _packet_dir(
            self.factory_home,
            _safe_identifier(run_id, "runId"),
            _safe_identifier(packet_id, "packetId"),
        )

    def load(self, run_id: str, packet_id: str) -> dict:
        return replay_packet(self.factory_home, run_id, packet_id)

    def _record(
        self,
        prior: dict | None,
        packet: dict,
        *,
        event_type: str,
        actor: str,
        reason: str,
        story_id: int | None = None,
    ) -> dict:
        validate_packet_model(packet)
        pdir = self.packet_dir(packet["runId"], packet["packetId"])
        pdir.mkdir(parents=True, exist_ok=True)
        journal = pdir / "events.jsonl"
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(journal, flags, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            os.lseek(fd, 0, os.SEEK_SET)
            chunks = []
            while True:
                chunk = os.read(fd, 1024 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
            current = _replay_bytes(b"".join(chunks), str(journal))
            if current != prior:
                raise IntegrationError("packet changed while controller operation was in flight")
            sequence = len(b"".join(chunks).splitlines()) + 1
            event = {
                "schemaVersion": CONTROLLER_SCHEMA_VERSION,
                "eventId": str(uuid.uuid4()),
                "sequence": sequence,
                "timestamp": self._now(),
                "eventType": event_type,
                "runId": packet["runId"],
                "packetId": packet["packetId"],
                "storyId": story_id,
                "fromState": prior["state"] if prior is not None else None,
                "toState": packet["state"],
                "actor": actor,
                "reason": reason,
                "packet": packet,
            }
            event["evidenceHash"] = _event_hash(event)
            _validate_event(event, sequence)
            os.lseek(fd, 0, os.SEEK_END)
            _write_all(fd, _canonical_bytes(event) + b"\n")
            os.fsync(fd)
            _fsync_dir(pdir)
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)
        _write_json(pdir / "packet.json", packet)
        return packet

    def _transition(self, packet: dict, state: str) -> dict:
        if state != packet["state"] and state not in LEGAL_TRANSITIONS[packet["state"]]:
            raise IllegalControllerTransition(f"illegal API transition {packet['state']} -> {state}")
        updated = copy.deepcopy(packet)
        updated["state"] = state
        updated["updatedAt"] = self._now()
        for slot in updated["slots"]:
            slot["state"] = state
        return updated

    def _manifest_hash(self) -> str:
        return _hash_file(self.repo_root / "assets" / "stories" / "manifest.json")

    def _assert_manifest_unchanged(self, packet: dict) -> None:
        actual = self._manifest_hash()
        if actual != packet["manifestHashAtPlan"]:
            raise SafetyViolation("manifest.json changed since packet planning; controller stopped")

    def _validate_narrator(self, narrator: object) -> str:
        if not isinstance(narrator, str) or not narrator.strip():
            raise ControllerConfigError("every slot requires an explicit narrator")
        narrator = narrator.strip()
        try:
            validate_story_voice(narrator)
            placeholder_env = {"VOICE_CHARLOTTE_V3": "A" * 20}
            resolve_new_story_tts_voice(
                {"storyVoiceKey": narrator, "kidFriendly": False},
                expected_story_voice_key=narrator,
                voices_path=str(self.policy_root / "server" / "voices.json"),
                schema_path=str(self.policy_root / "assets" / "stories" / "meta.schema.json"),
                env=placeholder_env,
            )
        except (VoiceValidationError, TtsVoiceGateError) as exc:
            raise ControllerConfigError(f"narrator {narrator!r} is not new-authoring-safe: {exc}") from exc
        return narrator

    def _validate_plan(self, planning: object) -> list[dict]:
        if not isinstance(planning, dict) or set(planning) != {"stories"}:
            raise ControllerConfigError("planning input must be exactly {'stories': [...]}")
        stories = planning["stories"]
        if not isinstance(stories, list) or len(stories) != PACKET_SIZE:
            raise ControllerConfigError(f"planning input must contain exactly {PACKET_SIZE} stories")
        normalized = []
        anchors = set()
        for index, raw in enumerate(stories, 1):
            if not isinstance(raw, dict):
                raise ControllerConfigError(f"planning story {index} is not an object")
            allowed = {"proposedAnchor", "mood", "narrator", "mode", "kidFriendly", "lengths"}
            if not set(raw) <= allowed:
                raise ControllerConfigError(f"planning story {index} has unsupported fields")
            anchor = raw.get("proposedAnchor")
            if not isinstance(anchor, str) or not anchor.strip():
                raise ControllerConfigError(f"planning story {index} has no scripture anchor")
            anchor = anchor.strip()
            anchor_key = re.sub(r"\s+", " ", anchor).lower()
            if anchor_key in anchors:
                raise ControllerConfigError("packet contains duplicate proposed anchors")
            anchors.add(anchor_key)
            mood = raw.get("mood")
            if mood not in MOODS:
                raise ControllerConfigError(f"planning story {index} has invalid mood {mood!r}")
            if raw.get("mode", "traditional") != "traditional" or raw.get("kidFriendly", False) is not False:
                raise ControllerConfigError("Milestone 1 supports adult Traditional stories only")
            lengths = raw.get("lengths", list(LENGTHS))
            if not isinstance(lengths, list) or not lengths or any(v not in LENGTHS for v in lengths):
                raise ControllerConfigError(f"planning story {index} has invalid lengths")
            lengths = sorted(set(lengths), key=LENGTHS.index)
            normalized.append({
                "anchor": anchor,
                "mood": mood,
                "narrator": self._validate_narrator(raw.get("narrator")),
                "lengths": lengths,
            })
        return normalized

    def _authoring_brief(self, slot: dict) -> str:
        lengths = ", ".join(slot["targetLengths"])
        return (
            f"Write adult Traditional WEB and KJV Bible PAL artifacts for story {slot['storyId']} "
            f"only within {slot['proposedAnchor']}. Target mood: {slot['mood']}; lengths: {lengths}; "
            f"assigned narrator: {slot['narrator']}. Observable passage-grounded narration only. "
            "Do not broaden the scripture anchor, change the narrator, create audio, edit a manifest, "
            "or write into production assets. Return exactly the named text and metadata artifacts."
        )

    def plan_packet(
        self,
        *,
        run_id: str,
        packet_id: str,
        actor: str,
        planning: dict,
        lease_seconds: int | float = reservation_service.DEFAULT_LEASE_SECONDS,
    ) -> dict:
        run_id = _safe_identifier(run_id, "runId")
        packet_id = _safe_identifier(packet_id, "packetId")
        actor = _safe_identifier(actor, "actor")
        pdir = self.packet_dir(run_id, packet_id)
        if (pdir / "events.jsonl").exists():
            raise ControllerConfigError(f"packet already exists: {run_id}/{packet_id}")
        plans = self._validate_plan(planning)
        created = self._now()
        packet = {
            "schemaVersion": CONTROLLER_SCHEMA_VERSION,
            "controllerMilestone": CONTROLLER_MILESTONE,
            "runId": run_id,
            "packetId": packet_id,
            "createdAt": created,
            "updatedAt": created,
            "state": PLANNED,
            "actor": actor,
            "repoRoot": str(self.repo_root),
            "worktree": str(self.worktree),
            "manifestHashAtPlan": self._manifest_hash(),
            "correctionRound": 0,
            "reviewRound": 0,
            "slots": [],
            "evidenceHashes": {},
        }
        for index, plan in enumerate(plans, 1):
            packet["slots"].append({
                "slotId": index,
                "storyId": None,
                "reservation": None,
                "proposedAnchor": plan["anchor"],
                "narrator": plan["narrator"],
                "mode": "traditional",
                "kidFriendly": False,
                "lanes": ["web", "kjv"],
                "targetLengths": plan["lengths"],
                "mood": plan["mood"],
                "authoringBrief": "",
                "state": PLANNED,
                "writerAttempts": 0,
                "correctionHistory": [],
                "overlapEvidence": {},
                "assignment": None,
                "workspace": None,
                "validationEvidence": None,
                "reviewerVerdict": None,
                "unresolvedFindings": [],
                "materialization": None,
                "finalReadiness": None,
            })
        self._record(None, packet, event_type="PACKET_PLANNED", actor=actor,
                     reason="validated five-story planning input")

        existing = [
            value for value in self.reservations.replay_ledger(self.factory_home).values()
            if value.run_id == run_id and value.packet_id == packet_id
            and value.state in {"RESERVED", "MATERIALIZED"}
        ]
        if existing and len(existing) != PACKET_SIZE:
            raise IntegrationError("partial authoritative packet reservation requires owner review")
        if existing:
            reserved = tuple(sorted(existing, key=lambda item: item.story_id))
        else:
            reserved = self.reservations.reserve_packet(
                count=PACKET_SIZE,
                run_id=run_id,
                packet_id=packet_id,
                actor=actor,
                worktree=self.worktree,
                repo_root=self.repo_root,
                factory_home=self.factory_home,
                lease_seconds=lease_seconds,
                worktrees=self.worktrees,
            )
        if len(reserved) != PACKET_SIZE:
            raise IntegrationError("reservation authority did not return exactly five claims")
        updated = self._transition(packet, ID_RESERVED)
        for slot, reservation in zip(updated["slots"], reserved):
            if reservation.run_id != run_id or reservation.packet_id != packet_id:
                raise IntegrationError("reservation identity does not match packet")
            slot["storyId"] = reservation.story_id
            slot["reservation"] = _reservation_to_dict(reservation)
            slot["authoringBrief"] = self._authoring_brief(slot)
        updated["evidenceHashes"]["reservations"] = _hash_value(
            [slot["reservation"] for slot in updated["slots"]]
        )
        return self._record(packet, updated, event_type="IDS_RESERVED", actor=actor,
                            reason="reservation service returned five authoritative claims")

    def _authoritative_reservations(self, packet: dict) -> dict[int, object]:
        states = self.reservations.replay_ledger(self.factory_home)
        out = {}
        for slot in packet["slots"]:
            story_id = slot["storyId"]
            current = states.get(story_id)
            if current is None:
                raise IntegrationError(f"story {story_id} has no authoritative reservation")
            ref = slot["reservation"]
            for attr, key in (
                ("story_id", "storyId"), ("run_id", "runId"),
                ("packet_id", "packetId"), ("lease_token", "leaseToken"),
                ("worktree", "worktree"),
            ):
                if getattr(current, attr) != ref[key]:
                    raise IntegrationError(f"story {story_id} reservation ownership changed")
            if current.state not in {"RESERVED", "MATERIALIZED"}:
                raise IntegrationError(f"story {story_id} reservation is {current.state}")
            out[story_id] = current
        return out

    def _overlap_queue_snapshot(self, packet: dict) -> Path:
        states = self._authoritative_reservations(packet)
        payload = {"reservations": []}
        for slot in packet["slots"]:
            current = states[slot["storyId"]]
            payload["reservations"].append({
                "storyId": slot["storyId"],
                "proposedAnchor": slot["proposedAnchor"],
                "state": "reserved" if current.state == "RESERVED" else "materialized",
            })
        path = self.packet_dir(packet["runId"], packet["packetId"]) / "overlap_queue_snapshot.json"
        _write_json(path, payload)
        return path

    def _evaluate_overlap(self, packet: dict, slot: dict, queue_path: Path) -> dict:
        kwargs = {
            "story_id": slot["storyId"],
            "repo_root": str(self.repo_root),
            "reservations_path": str(queue_path),
        }
        if self.worktrees is not None:
            kwargs["worktrees"] = [str(path) for path in self.worktrees]
        return self.overlap_evaluator(slot["proposedAnchor"], **kwargs)

    def preflight_anchors(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != ID_RESERVED:
            raise IllegalControllerTransition("anchor preflight requires ID_RESERVED")
        self._assert_manifest_unchanged(packet)
        queue_path = self._overlap_queue_snapshot(packet)
        updated = copy.deepcopy(packet)
        refusals = []
        evidence_dir = self.packet_dir(run_id, packet_id) / "overlap" / "initial"
        for slot in updated["slots"]:
            try:
                result = self._evaluate_overlap(packet, slot, queue_path)
            except Exception as exc:
                result = {"verdict": "ERROR", "errorType": type(exc).__name__, "error": str(exc)}
            result_hash = _hash_value(result)
            _write_json(evidence_dir / f"{slot['storyId']}.json", result)
            slot["overlapEvidence"]["initial"] = {
                "verdict": result.get("verdict"),
                "hash": result_hash,
                "path": str(PurePosixPath("overlap") / "initial" / f"{slot['storyId']}.json"),
            }
            if result.get("verdict") != "PASS":
                refusals.append(f"{slot['storyId']}:{result.get('verdict', 'ERROR')}")
        if refusals:
            updated["updatedAt"] = self._now()
            self._record(packet, updated, event_type="ANCHOR_PREFLIGHT_REFUSED",
                         actor=actor, reason=", ".join(refusals))
            raise OverlapRejected("autonomous preflight requires PASS: " + ", ".join(refusals))
        updated = self._transition(updated, ANCHOR_PREFLIGHT_PASSED)
        updated["evidenceHashes"]["initialOverlap"] = _hash_value(
            [slot["overlapEvidence"]["initial"] for slot in updated["slots"]]
        )
        return self._record(packet, updated, event_type="ANCHORS_PREFLIGHT_PASSED",
                            actor=actor, reason="all five overlap verdicts were PASS")

    def _assignment_payload(self, packet: dict, slot: dict) -> dict:
        names = expected_artifact_names(slot["storyId"], slot["targetLengths"])
        return {
            "assignmentVersion": 1,
            "runId": packet["runId"],
            "packetId": packet["packetId"],
            "storyId": slot["storyId"],
            "scriptureAnchor": slot["proposedAnchor"],
            "mode": slot["mode"],
            "mood": slot["mood"],
            "kidFriendly": slot["kidFriendly"],
            "lanes": slot["lanes"],
            "targetLengths": slot["targetLengths"],
            "wordRanges": {length: list(TRADITIONAL_RANGES[length]) for length in slot["targetLengths"]},
            "reflectionWordRange": list(REFLECTION_WORD_RANGE),
            "assignedNarrator": slot["narrator"],
            "authoringBrief": slot["authoringBrief"],
            "requiredArtifacts": list(names),
            "outputPathContract": f"writer_output/{slot['storyId']}/attempt-<n>/",
            "requirements": [
                "Retell only observable events within the exact planned anchor.",
                "Preserve adult Traditional mode in both WEB and KJV lanes.",
                "Metadata storyVoiceKey must equal the assigned narrator.",
                "Metadata must omit voiceKey, voiceKeys, and reflectionVoiceKey.",
                "The anchor may not be broadened without controller re-preflight.",
                "Manifest and production asset writes are forbidden.",
                "Audio generation and audio files are forbidden.",
            ],
            "overlapEvidenceHash": slot["overlapEvidence"]["initial"]["hash"],
            "requestedHandoff": "Return only the exact required artifacts; no model invocation is performed by the controller.",
        }

    def emit_writer_assignments(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != ANCHOR_PREFLIGHT_PASSED:
            raise IllegalControllerTransition("writer assignments require ANCHOR_PREFLIGHT_PASSED")
        pdir = self.packet_dir(run_id, packet_id)
        updated = self._transition(packet, ASSIGNMENT_READY)
        hashes = {}
        for slot in updated["slots"]:
            payload = self._assignment_payload(packet, slot)
            path = pdir / "assignments" / f"story_{slot['storyId']}.json"
            _write_json(path, payload)
            digest = _hash_value(payload)
            hashes[str(slot["storyId"])] = digest
            slot["assignment"] = {
                "path": str(PurePosixPath("assignments") / path.name),
                "hash": digest,
            }
        updated["evidenceHashes"]["assignments"] = _hash_value(hashes)
        return self._record(packet, updated, event_type="WRITER_ASSIGNMENTS_EMITTED",
                            actor=actor, reason="deterministic manual writer handoffs emitted")

    def _copy_writer_attempt(self, source: Path, destination: Path, expected: tuple[str, ...]) -> None:
        source = source.expanduser().resolve(strict=True)
        production_root = (self.repo_root / "assets" / "stories").resolve(strict=False)
        if _is_within(source, production_root):
            raise WorkspaceRejected("writer output may not be ingested from production assets")
        try:
            source_info = source.lstat()
        except OSError as exc:
            raise WorkspaceRejected(f"writer source unavailable: {source}: {exc}") from exc
        if stat.S_ISLNK(source_info.st_mode) or not stat.S_ISDIR(source_info.st_mode):
            raise WorkspaceRejected("writer source must be an ordinary directory")
        actual = set()
        with os.scandir(source) as entries:
            for entry in entries:
                if entry.is_symlink() or not entry.is_file(follow_symlinks=False):
                    raise WorkspaceRejected(f"writer artifact is not an ordinary file: {entry.name}")
                actual.add(entry.name)
        required = set(expected)
        missing = sorted(required - actual)
        unexpected = sorted(actual - required)
        if missing:
            raise WorkspaceRejected("missing required artifacts: " + ", ".join(missing))
        if unexpected:
            raise WorkspaceRejected("unexpected writer artifacts: " + ", ".join(unexpected))
        if any(name.lower().endswith((".mp3", ".wav", ".m4a")) for name in actual):
            raise WorkspaceRejected("audio artifacts are forbidden in Milestone 1")
        payloads = {}
        for name in expected:
            try:
                data = (source / name).read_bytes()
            except OSError as exc:
                raise WorkspaceRejected(f"writer artifact cannot be read: {name}: {exc}") from exc
            if not data:
                raise WorkspaceRejected(f"writer artifact is empty: {name}")
            payloads[name] = data
        if destination.exists():
            raise WorkspaceRejected(f"writer attempt destination already exists: {destination}")
        destination.mkdir(parents=True, mode=0o700)
        for name, data in payloads.items():
            _atomic_write(destination / name, data)

    def ingest_writer_output(
        self,
        run_id: str,
        packet_id: str,
        *,
        source_root: os.PathLike[str] | str,
        actor: str,
    ) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] not in {ASSIGNMENT_READY, CORRECTION_READY}:
            raise IllegalControllerTransition("writer ingestion requires ASSIGNMENT_READY or CORRECTION_READY")
        source_root = Path(source_root).expanduser().resolve(strict=True)
        updated = self._transition(packet, WRITER_OUTPUT_RECEIVED)
        correction = packet["state"] == CORRECTION_READY
        active = [slot for slot in updated["slots"] if not correction or slot["unresolvedFindings"]]
        if correction and not active:
            raise WorkspaceRejected("correction round has no changed stories")
        pdir = self.packet_dir(run_id, packet_id)
        for slot in active:
            attempt = slot["writerAttempts"] + 1
            source = source_root / str(slot["storyId"])
            destination = pdir / "writer_output" / str(slot["storyId"]) / f"attempt-{attempt}"
            expected = expected_artifact_names(slot["storyId"], slot["targetLengths"])
            self._copy_writer_attempt(source, destination, expected)
            tree_hash, hashes = _tree_hash(destination, expected)
            slot["writerAttempts"] = attempt
            slot["workspace"] = {
                "path": str(destination.relative_to(pdir)),
                "treeHash": tree_hash,
                "fileHashes": hashes,
            }
            slot["validationEvidence"] = None
            slot["materialization"] = None if not correction else slot["materialization"]
        updated["evidenceHashes"][f"writerOutputAttempt{max(s['writerAttempts'] for s in active)}"] = _hash_value(
            {str(slot["storyId"]): slot["workspace"]["treeHash"] for slot in active}
        )
        return self._record(packet, updated, event_type="WRITER_OUTPUT_INGESTED",
                            actor=actor, reason="writer artifacts copied into isolated runtime workspace")

    def _workspace_dir(self, packet: dict, slot: dict) -> Path:
        workspace = slot.get("workspace")
        if not isinstance(workspace, dict) or not isinstance(workspace.get("path"), str):
            raise ValidationFailed([f"story {slot['storyId']}: no ingested writer workspace"])
        pdir = self.packet_dir(packet["runId"], packet["packetId"])
        path = (pdir / workspace["path"]).resolve(strict=True)
        if not _is_within(path, (pdir / "writer_output").resolve(strict=False)):
            raise ValidationFailed([f"story {slot['storyId']}: workspace path escapes packet runtime"])
        return path

    def _expected_files_map(self, slot: dict) -> dict:
        story_id = slot["storyId"]
        files = {}
        for length in slot["targetLengths"]:
            files[length] = {
                "storyText": f"story_{story_id}_traditional_web_{length}.txt",
            }
            files[f"{length}_kjv"] = {
                "storyText": f"story_{story_id}_traditional_kjv_{length}.txt",
            }
        files["reflection"] = {
            "reflectionText": f"reflection_{story_id}_traditional_web.txt",
        }
        files["reflection_kjv"] = {
            "reflectionText": f"reflection_{story_id}_traditional_kjv.txt",
        }
        return files

    def _validate_scripture_excerpt(
        self,
        path: Path,
        *,
        anchor: str,
        lane: str,
    ) -> tuple[bool, str]:
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        if lines and re.fullmatch(rf"{re.escape(anchor)}\s+\({lane.upper()}\)", lines[0].strip()):
            lines = lines[1:]
        body = "\n".join(re.sub(r"^\s*\d+\s+", "", line) for line in lines)
        actual = reconstruction_check.normalize_tokens(body)
        try:
            expected = reconstruction_check.resolve_source_tokens(
                anchor, lane, repo_root=self.policy_root,
            )
        except reconstruction_check.ContentUnavailable as exc:
            return False, f"canonical scripture resolution failed: {exc}"
        if actual != expected:
            return False, "scripture excerpt does not exactly match canonical passage tokens"
        return True, f"{len(actual)} canonical tokens"

    def _validate_story_workspace(self, packet: dict, slot: dict) -> tuple[dict, list[str]]:
        story_id = slot["storyId"]
        errors = []
        checks = []
        directory = self._workspace_dir(packet, slot)
        expected = expected_artifact_names(story_id, slot["targetLengths"])
        try:
            actual_names = sorted(entry.name for entry in os.scandir(directory))
        except OSError as exc:
            return {}, [f"story {story_id}: workspace cannot be enumerated: {exc}"]
        if set(actual_names) != set(expected):
            errors.append(f"story {story_id}: workspace artifact set changed after ingestion")
        for name in actual_names:
            path = directory / name
            try:
                info = path.lstat()
            except OSError as exc:
                errors.append(f"story {story_id}: cannot inspect {name}: {exc}")
                continue
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                errors.append(f"story {story_id}: {name} is not an ordinary file")
            if name.lower().endswith((".mp3", ".wav", ".m4a")):
                errors.append(f"story {story_id}: audio artifact is forbidden: {name}")
        try:
            tree_hash, file_hashes = _tree_hash(directory, expected)
        except SafetyViolation as exc:
            errors.append(f"story {story_id}: {exc}")
            tree_hash, file_hashes = "", {}
        if tree_hash and tree_hash != slot["workspace"]["treeHash"]:
            errors.append(f"story {story_id}: workspace changed after ingestion")
        checks.append({"name": "workspace_integrity", "passed": not any("workspace" in e for e in errors),
                       "treeHash": tree_hash})

        meta_path = directory / f"meta_{story_id}.json"
        try:
            meta = _load_json(meta_path, error_type=ControllerConfigError)
        except ControllerError as exc:
            return {"checks": checks, "fileHashes": file_hashes}, [f"story {story_id}: metadata JSON: {exc}"]
        if not isinstance(meta, dict):
            return {"checks": checks, "fileHashes": file_hashes}, [f"story {story_id}: metadata root is not an object"]

        schema_path = self.policy_root / "assets" / "stories" / "meta.schema.json"
        try:
            schema = _load_json(schema_path, error_type=ValidationFailed)
            Draft202012Validator.check_schema(schema)
            schema_errors = sorted(
                Draft202012Validator(schema).iter_errors(meta),
                key=lambda err: tuple(str(v) for v in err.absolute_path),
            )
        except (SchemaError, ControllerError) as exc:
            errors.append(f"story {story_id}: metadata schema infrastructure: {exc}")
            schema_errors = []
        for err in schema_errors:
            location = ".".join(str(v) for v in err.absolute_path) or "<root>"
            errors.append(f"story {story_id}: schema {location}: {err.message}")
        checks.append({"name": "metadata_schema", "passed": not schema_errors,
                       "errors": len(schema_errors)})

        expected_values = {
            "schemaVersion": 2,
            "storyId": story_id,
            "mode": "traditional",
            "kidFriendly": False,
            "languageStyle": "WEB",
            "lanes": ["web", "kjv"],
            "mood": slot["mood"],
            "lengths": slot["targetLengths"],
            "scriptureAnchor": slot["proposedAnchor"],
            "storyVoiceKey": slot["narrator"],
            "files": self._expected_files_map(slot),
        }
        contract_errors = []
        for field, expected_value in expected_values.items():
            if meta.get(field) != expected_value:
                contract_errors.append(f"{field} differs from controller assignment")
        for legacy in ("voiceKey", "voiceKeys", "reflectionVoiceKey"):
            if legacy in meta:
                contract_errors.append(f"legacy narrator field {legacy} is forbidden")
        for field in ("ttsModel", "ttsVoiceSettings", "renderedAt", "generatorVersion"):
            if field in meta:
                contract_errors.append(f"audio-render field {field} is forbidden before audio")
        errors.extend(f"story {story_id}: metadata contract: {item}" for item in contract_errors)
        checks.append({"name": "metadata_controller_contract", "passed": not contract_errors,
                       "errors": contract_errors})

        try:
            resolve_new_story_tts_voice(
                meta,
                expected_story_voice_key=slot["narrator"],
                voices_path=str(self.policy_root / "server" / "voices.json"),
                schema_path=str(schema_path),
                env={"VOICE_CHARLOTTE_V3": "A" * 20},
            )
            narrator_error = None
        except TtsVoiceGateError as exc:
            narrator_error = str(exc)
            errors.append(f"story {story_id}: narrator gate: {exc}")
        checks.append({"name": "narrator_gate", "passed": narrator_error is None,
                       "error": narrator_error})

        source = _AttemptSource(directory)
        reconstruction = []
        quality_details = []
        for length in slot["targetLengths"]:
            floor, ceiling = TRADITIONAL_RANGES[length]
            for lane in LANES:
                name = f"story_{story_id}_traditional_{lane}_{length}.txt"
                path = directory / name
                try:
                    text = path.read_text(encoding="utf-8")
                except (OSError, UnicodeError) as exc:
                    errors.append(f"story {story_id}: cannot read {name}: {exc}")
                    continue
                words = len(text.split())
                item_errors = []
                if not floor <= words <= ceiling:
                    item_errors.append(f"{words} words outside {floor}-{ceiling}")
                meta_hit = check_meta_text(text)
                if meta_hit is not None:
                    item_errors.append(f"meta-text {meta_hit!r}")
                traditional = validate_traditional(text)
                if traditional:
                    item_errors.append(f"{len(traditional)} Traditional violation(s)")
                lane_warnings = validate_lane_identity(text, lane)
                for problem in item_errors:
                    errors.append(f"story {story_id}: {name}: {problem}")
                quality_details.append({
                    "file": name,
                    "words": words,
                    "range": [floor, ceiling],
                    "passed": not item_errors,
                    "errors": item_errors,
                    "laneWarnings": [list(value) for value in lane_warnings],
                })
                canonical_rel = f"assets/stories/traditional/{story_id}/{name}"
                finding = reconstruction_check.analyze_story_rel(
                    canonical_rel,
                    str(story_id),
                    lane,
                    length,
                    slot["proposedAnchor"],
                    source,
                    repo_root=self.policy_root,
                )
                reconstruction.append({
                    "file": name,
                    "reconstructible": finding.reconstructible,
                    "unresolved": finding.unresolved,
                    "storyWords": finding.story_words,
                    "sourceWords": finding.source_words,
                    "longestRun": finding.metrics.longest_run,
                    "matchedWords": finding.metrics.matched_words,
                    "policy": "ADR-031 advisory; not an acceptance threshold",
                })
        checks.append({"name": "strict_buckets_and_mechanical_quality",
                       "passed": all(item["passed"] for item in quality_details),
                       "files": quality_details})
        checks.append({"name": "reconstruction_diagnostic", "passed": True,
                       "advisory": reconstruction})

        reflection_details = []
        for lane in LANES:
            name = f"reflection_{story_id}_traditional_{lane}.txt"
            try:
                text = (directory / name).read_text(encoding="utf-8")
            except (OSError, UnicodeError) as exc:
                errors.append(f"story {story_id}: cannot read {name}: {exc}")
                continue
            words = len(text.split())
            item_errors = []
            if not REFLECTION_WORD_RANGE[0] <= words <= REFLECTION_WORD_RANGE[1]:
                item_errors.append(
                    f"{words} words outside {REFLECTION_WORD_RANGE[0]}-{REFLECTION_WORD_RANGE[1]}"
                )
            meta_hit = check_meta_text(text)
            if meta_hit is not None:
                item_errors.append(f"meta-text {meta_hit!r}")
            banned = check_reflection_banned(text)
            if banned is not None:
                item_errors.append(f"banned reflection phrase {banned!r}")
            for problem in item_errors:
                errors.append(f"story {story_id}: {name}: {problem}")
            reflection_details.append({"file": name, "words": words,
                                       "passed": not item_errors, "errors": item_errors})
        checks.append({"name": "reflection_quality", "passed": all(v["passed"] for v in reflection_details),
                       "files": reflection_details})

        scripture_details = []
        for lane in LANES:
            name = f"scripture_{story_id}_{lane}.txt"
            try:
                passed, detail = self._validate_scripture_excerpt(
                    directory / name, anchor=slot["proposedAnchor"], lane=lane,
                )
            except (OSError, UnicodeError) as exc:
                passed, detail = False, str(exc)
            if not passed:
                errors.append(f"story {story_id}: {name}: {detail}")
            scripture_details.append({"file": name, "passed": passed, "detail": detail})
        checks.append({"name": "canonical_scripture_excerpts",
                       "passed": all(v["passed"] for v in scripture_details),
                       "files": scripture_details})

        evidence = {
            "storyId": story_id,
            "status": "PASS" if not errors else "FAIL",
            "orderedChecks": checks,
            "fileHashes": file_hashes,
            "workspaceTreeHash": tree_hash,
            "metadataHash": file_hashes.get(f"meta_{story_id}.json"),
        }
        return evidence, errors

    def validate_outputs(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != WRITER_OUTPUT_RECEIVED:
            raise IllegalControllerTransition("validation requires WRITER_OUTPUT_RECEIVED")
        self._assert_manifest_unchanged(packet)
        self._authoritative_reservations(packet)
        queue_path = self._overlap_queue_snapshot(packet)
        updated = copy.deepcopy(packet)
        all_errors = []
        validation_dir = self.packet_dir(run_id, packet_id) / "validation"
        for slot in updated["slots"]:
            evidence, errors = self._validate_story_workspace(packet, slot)
            try:
                final_overlap = self._evaluate_overlap(packet, slot, queue_path)
            except Exception as exc:
                final_overlap = {"verdict": "ERROR", "errorType": type(exc).__name__, "error": str(exc)}
            evidence["finalOverlap"] = final_overlap
            evidence["finalOverlapHash"] = _hash_value(final_overlap)
            if final_overlap.get("verdict") != "PASS":
                errors.append(f"story {slot['storyId']}: final overlap verdict {final_overlap.get('verdict', 'ERROR')}")
            if errors:
                evidence["status"] = "FAIL"
            _write_json(validation_dir / f"story_{slot['storyId']}.json", evidence)
            slot["validationEvidence"] = {
                "status": evidence["status"],
                "hash": _hash_value(evidence),
                "path": str(PurePosixPath("validation") / f"story_{slot['storyId']}.json"),
                "workspaceTreeHash": evidence.get("workspaceTreeHash"),
                "finalOverlapHash": evidence["finalOverlapHash"],
                "finalOverlapVerdict": final_overlap.get("verdict"),
            }
            slot["overlapEvidence"]["final"] = {
                "verdict": final_overlap.get("verdict"),
                "hash": evidence["finalOverlapHash"],
            }
            slot["unresolvedFindings"] = list(errors)
            all_errors.extend(errors)
        if all_errors:
            if packet["correctionRound"] >= MAX_CORRECTION_ROUNDS:
                updated = self._transition(updated, QUARANTINED)
                event_type = "VALIDATION_CORRECTION_CAP_EXCEEDED"
                reason = f"validation still failed after {MAX_CORRECTION_ROUNDS} correction rounds"
            else:
                updated["updatedAt"] = self._now()
                event_type = "VALIDATION_REFUSED"
                reason = f"{len(all_errors)} blocking validation finding(s)"
            updated["evidenceHashes"]["validationFailure"] = _hash_value(all_errors)
            self._record(packet, updated, event_type=event_type, actor=actor, reason=reason)
            raise ValidationFailed(all_errors)
        for slot in updated["slots"]:
            slot["unresolvedFindings"] = []
        updated = self._transition(updated, VALIDATION_PASSED)
        updated["evidenceHashes"][f"validationRound{packet['correctionRound']}"] = _hash_value(
            [slot["validationEvidence"] for slot in updated["slots"]]
        )
        return self._record(packet, updated, event_type="VALIDATION_PASSED",
                            actor=actor, reason="all ordered text/schema/campaign checks passed")

    def _directory_matches(self, directory: Path, expected_hashes: Mapping[str, str]) -> bool:
        if not directory.is_dir():
            return False
        try:
            actual = {entry.name for entry in os.scandir(directory)}
        except OSError:
            return False
        if actual != set(expected_hashes):
            return False
        try:
            return all(_hash_file(directory / name) == digest for name, digest in expected_hashes.items())
        except ControllerError:
            return False

    def _copy_to_staging(self, source: Path, staging: Path, expected: tuple[str, ...]) -> None:
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir(parents=False, mode=0o700)
        for name in expected:
            _atomic_write(staging / name, (source / name).read_bytes(), mode=0o644)
        _fsync_dir(staging)

    def _install_story_directory(self, packet: dict, slot: dict, source: Path) -> tuple[str, dict[str, str]]:
        story_id = slot["storyId"]
        expected = expected_artifact_names(story_id, slot["targetLengths"])
        tree_hash, source_hashes = _tree_hash(source, expected)
        parent = self.repo_root / "assets" / "stories" / "traditional"
        parent.mkdir(parents=True, exist_ok=True)
        destination = parent / str(story_id)
        staging = parent / f".{story_id}.controller-staging"
        backup = parent / f".{story_id}.controller-backup"

        if backup.exists():
            if destination.exists() and self._directory_matches(destination, source_hashes):
                shutil.rmtree(backup)
            elif not destination.exists() and staging.exists() and self._directory_matches(staging, source_hashes):
                os.replace(staging, destination)
                _fsync_dir(parent)
                shutil.rmtree(backup)
            else:
                raise SafetyViolation(f"story {story_id}: unresolved controller directory-swap recovery state")
        if destination.exists() and self._directory_matches(destination, source_hashes):
            if staging.exists():
                shutil.rmtree(staging)
            return tree_hash, source_hashes

        previous = slot.get("materialization")
        if destination.exists():
            prior_hashes = previous.get("fileHashes") if isinstance(previous, dict) else None
            if not isinstance(prior_hashes, dict) or not self._directory_matches(destination, prior_hashes):
                raise SafetyViolation(
                    f"story {story_id}: production directory exists without controller-owned hash evidence"
                )
        self._copy_to_staging(source, staging, expected)
        if destination.exists():
            if backup.exists():
                raise SafetyViolation(f"story {story_id}: controller backup unexpectedly exists")
            os.replace(destination, backup)
            _fsync_dir(parent)
        os.replace(staging, destination)
        _fsync_dir(parent)
        if not self._directory_matches(destination, source_hashes):
            raise SafetyViolation(f"story {story_id}: production copy hash verification failed")
        if backup.exists():
            shutil.rmtree(backup)
            _fsync_dir(parent)
        return tree_hash, source_hashes

    def materialize_for_review(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != VALIDATION_PASSED:
            raise IllegalControllerTransition("materialization requires VALIDATION_PASSED")
        self._assert_manifest_unchanged(packet)
        authoritative = self._authoritative_reservations(packet)
        updated = copy.deepcopy(packet)
        for slot in updated["slots"]:
            evidence = slot.get("validationEvidence")
            if not isinstance(evidence, dict) or evidence.get("status") != "PASS":
                raise ValidationFailed([f"story {slot['storyId']}: no passing validation evidence"])
            source = self._workspace_dir(packet, slot)
            tree_hash, file_hashes = _tree_hash(
                source, expected_artifact_names(slot["storyId"], slot["targetLengths"]),
            )
            if tree_hash != evidence.get("workspaceTreeHash"):
                raise SafetyViolation(f"story {slot['storyId']}: workspace changed after validation")
            installed_hash, installed_files = self._install_story_directory(packet, slot, source)
            current = authoritative[slot["storyId"]]
            if current.state == "RESERVED":
                current = self.reservations.confirm_materialized(
                    current,
                    repo_root=self.repo_root,
                    factory_home=self.factory_home,
                    worktrees=self.worktrees,
                    actor=actor,
                )
            elif current.state != "MATERIALIZED":
                raise IntegrationError(f"story {slot['storyId']} cannot materialize from {current.state}")
            slot["reservation"] = _reservation_to_dict(current)
            slot["materialization"] = {
                "path": f"assets/stories/traditional/{slot['storyId']}",
                "treeHash": installed_hash,
                "fileHashes": installed_files,
                "reservationState": current.state,
                "audioPresent": False,
                "manifestRegistered": False,
            }
        updated["updatedAt"] = self._now()
        updated["evidenceHashes"][f"materializationRound{packet['correctionRound']}"] = _hash_value(
            [slot["materialization"] for slot in updated["slots"]]
        )
        self._assert_manifest_unchanged(updated)
        return self._record(packet, updated, event_type="MATERIALIZATION_RECORDED",
                            actor=actor, reason="validated text copied and reservations confirmed exactly once")

    def _assert_materialized(self, packet: dict) -> None:
        authoritative = self._authoritative_reservations(packet)
        for slot in packet["slots"]:
            story_id = slot["storyId"]
            materialization = slot.get("materialization")
            if not isinstance(materialization, dict):
                raise SafetyViolation(f"story {story_id}: no controller materialization evidence")
            if authoritative[story_id].state != "MATERIALIZED":
                raise IntegrationError(f"story {story_id}: reservation is not MATERIALIZED")
            destination = self.repo_root / materialization["path"]
            if not self._directory_matches(destination, materialization["fileHashes"]):
                raise SafetyViolation(f"story {story_id}: production files differ from recorded hashes")
            if any(path.suffix.lower() in {".mp3", ".wav", ".m4a"} for path in destination.iterdir()):
                raise SafetyViolation(f"story {story_id}: audio exists before human review")

    def emit_review_packet(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != VALIDATION_PASSED:
            raise IllegalControllerTransition("review packet emission requires VALIDATION_PASSED")
        self._assert_manifest_unchanged(packet)
        self._assert_materialized(packet)
        round_number = packet["reviewRound"] + 1
        updated = self._transition(packet, REVIEW_READY)
        updated["reviewRound"] = round_number
        review_dir = self.packet_dir(run_id, packet_id) / "reviews" / f"round-{round_number}"
        review_hashes = {}
        for slot in updated["slots"]:
            source = self._workspace_dir(packet, slot)
            contents = {
                name: (source / name).read_text(encoding="utf-8")
                for name in expected_artifact_names(slot["storyId"], slot["targetLengths"])
            }
            payload = {
                "reviewPacketVersion": 1,
                "runId": run_id,
                "packetId": packet_id,
                "reviewRound": round_number,
                "storyId": slot["storyId"],
                "anchor": slot["proposedAnchor"],
                "narrator": slot["narrator"],
                "mood": slot["mood"],
                "validationEvidence": slot["validationEvidence"],
                "materialization": slot["materialization"],
                "artifacts": contents,
                "requirements": self._assignment_payload(packet, slot)["requirements"],
                "requiredVerdict": {
                    "storyId": slot["storyId"],
                    "verdict": "APPROVED | CHANGES_REQUESTED | REJECTED",
                    "findings": ["bounded actionable finding"],
                },
            }
            path = review_dir / f"story_{slot['storyId']}.json"
            _write_json(path, payload)
            review_hashes[str(slot["storyId"])] = _hash_value(payload)
        updated["evidenceHashes"][f"reviewBundleRound{round_number}"] = _hash_value(review_hashes)
        return self._record(packet, updated, event_type="REVIEW_PACKET_EMITTED",
                            actor=actor, reason="deterministic manual Codex review bundle emitted")

    def ingest_review(
        self,
        run_id: str,
        packet_id: str,
        *,
        review: dict,
        actor: str,
    ) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != REVIEW_READY:
            raise IllegalControllerTransition("review ingestion requires REVIEW_READY")
        review_dir = self.packet_dir(run_id, packet_id) / "reviews" / f"round-{packet['reviewRound']}"
        review_hashes = {}
        for slot in packet["slots"]:
            path = review_dir / f"story_{slot['storyId']}.json"
            payload = _load_json(path, error_type=ReviewRejected)
            review_hashes[str(slot["storyId"])] = _hash_value(payload)
        expected_bundle_hash = packet["evidenceHashes"].get(
            f"reviewBundleRound{packet['reviewRound']}"
        )
        if _hash_value(review_hashes) != expected_bundle_hash:
            raise ReviewRejected("review bundle changed after emission; verdict cannot be trusted")
        if not isinstance(review, dict) or set(review) != {"stories"} or not isinstance(review["stories"], list):
            raise ReviewRejected("review input must be exactly {'stories': [...]}")
        rows = review["stories"]
        if len(rows) != PACKET_SIZE:
            raise ReviewRejected("review input must contain exactly five story verdicts")
        by_id = {}
        for row in rows:
            if not isinstance(row, dict) or set(row) != {"storyId", "verdict", "findings"}:
                raise ReviewRejected("review verdict fields must be storyId/verdict/findings")
            if row["storyId"] in by_id or row["verdict"] not in REVIEW_VERDICTS:
                raise ReviewRejected("review contains duplicate ID or malformed verdict")
            if not isinstance(row["findings"], list) or any(not isinstance(v, str) or not v.strip() for v in row["findings"]):
                raise ReviewRejected("review findings must be non-empty strings")
            if row["verdict"] == "APPROVED" and row["findings"]:
                raise ReviewRejected("APPROVED verdict may not carry unresolved findings")
            if row["verdict"] == "CHANGES_REQUESTED" and not row["findings"]:
                raise ReviewRejected("CHANGES_REQUESTED requires bounded findings")
            by_id[row["storyId"]] = row
        expected_ids = {slot["storyId"] for slot in packet["slots"]}
        if set(by_id) != expected_ids:
            raise ReviewRejected("review story IDs do not exactly match packet")
        _write_json(review_dir / "verdicts.json", review)

        updated = copy.deepcopy(packet)
        verdicts = set()
        for slot in updated["slots"]:
            row = by_id[slot["storyId"]]
            slot["reviewerVerdict"] = row["verdict"]
            slot["unresolvedFindings"] = list(row["findings"])
            verdicts.add(row["verdict"])
        if "REJECTED" in verdicts:
            target = QUARANTINED
            event_type = "REVIEW_REJECTED"
            reason = "reviewer rejected at least one story"
        elif "CHANGES_REQUESTED" in verdicts:
            if packet["correctionRound"] >= MAX_CORRECTION_ROUNDS:
                target = QUARANTINED
                event_type = "CORRECTION_CAP_EXCEEDED"
                reason = f"review requested changes after {MAX_CORRECTION_ROUNDS} correction rounds"
            else:
                target = REVIEW_CHANGES_REQUESTED
                event_type = "REVIEW_CHANGES_REQUESTED"
                reason = "bounded reviewer findings require correction"
        else:
            target = REVIEW_APPROVED
            event_type = "REVIEW_APPROVED"
            reason = "all five reviewer verdicts are APPROVED"
        updated = self._transition(updated, target)
        updated["evidenceHashes"][f"reviewVerdictsRound{packet['reviewRound']}"] = _hash_value(review)
        return self._record(packet, updated, event_type=event_type, actor=actor, reason=reason)

    def emit_corrections(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] not in {REVIEW_CHANGES_REQUESTED, WRITER_OUTPUT_RECEIVED}:
            raise IllegalControllerTransition(
                "correction emission requires reviewer changes or failed validation"
            )
        if not any(slot["unresolvedFindings"] for slot in packet["slots"]):
            raise ReviewRejected("correction emission requires bounded unresolved findings")
        if packet["correctionRound"] >= MAX_CORRECTION_ROUNDS:
            raise ReviewRejected("correction attempt cap reached")
        round_number = packet["correctionRound"] + 1
        updated = self._transition(packet, CORRECTION_READY)
        updated["correctionRound"] = round_number
        correction_dir = self.packet_dir(run_id, packet_id) / "corrections" / f"round-{round_number}"
        hashes = {}
        for slot in updated["slots"]:
            if not slot["unresolvedFindings"]:
                continue
            payload = {
                "correctionVersion": 1,
                "runId": run_id,
                "packetId": packet_id,
                "correctionRound": round_number,
                "storyId": slot["storyId"],
                "immutableAnchor": slot["proposedAnchor"],
                "immutableNarrator": slot["narrator"],
                "findings": slot["unresolvedFindings"],
                "requiredArtifacts": list(expected_artifact_names(slot["storyId"], slot["targetLengths"])),
                "instruction": "Correct only the bounded findings and return the complete artifact set; no manifest or audio.",
            }
            path = correction_dir / f"story_{slot['storyId']}.json"
            _write_json(path, payload)
            digest = _hash_value(payload)
            hashes[str(slot["storyId"])] = digest
            slot["correctionHistory"].append({
                "round": round_number,
                "assignmentPath": str(path.relative_to(self.packet_dir(run_id, packet_id))),
                "assignmentHash": digest,
                "findings": list(slot["unresolvedFindings"]),
            })
        updated["evidenceHashes"][f"correctionsRound{round_number}"] = _hash_value(hashes)
        return self._record(packet, updated, event_type="CORRECTION_ASSIGNMENTS_EMITTED",
                            actor=actor, reason=f"bounded correction round {round_number} emitted")

    def _final_overlap_pass(self, packet: dict) -> dict[str, dict]:
        queue_path = self._overlap_queue_snapshot(packet)
        results = {}
        for slot in packet["slots"]:
            try:
                result = self._evaluate_overlap(packet, slot, queue_path)
            except Exception as exc:
                result = {"verdict": "ERROR", "errorType": type(exc).__name__, "error": str(exc)}
            if result.get("verdict") != "PASS":
                raise OverlapRejected(
                    f"story {slot['storyId']} final human-gate overlap is {result.get('verdict', 'ERROR')}"
                )
            results[str(slot["storyId"])] = result
        return results

    def _human_report(self, packet: dict) -> str:
        lines = [
            f"# Bible PAL proving packet {packet['packetId']}",
            "",
            f"Run: `{packet['runId']}`",
            f"State: `{READY_FOR_HUMAN_REVIEW}`",
            f"Correction rounds: {packet['correctionRound']}",
            "",
            "| Story | Anchor | Narrator | Validation | Review |",
            "|---:|---|---|---|---|",
        ]
        for slot in packet["slots"]:
            lines.append(
                f"| {slot['storyId']} | {slot['proposedAnchor']} | {slot['narrator']} | "
                f"{slot['validationEvidence']['status']} | {slot['reviewerVerdict']} |"
            )
        lines.extend((
            "",
            "Safety gate: text only; no audio; no manifest registration; no publication.",
            "Next action: independent human review. Promotion remains forbidden.",
            "",
        ))
        return "\n".join(lines)

    def mark_ready_for_human_review(self, run_id: str, packet_id: str, *, actor: str) -> dict:
        packet = self.load(run_id, packet_id)
        if packet["state"] != REVIEW_APPROVED:
            raise IllegalControllerTransition("human-review readiness requires REVIEW_APPROVED")
        self._assert_manifest_unchanged(packet)
        self._assert_materialized(packet)
        final_overlap = self._final_overlap_pass(packet)
        updated = self._transition(packet, READY_FOR_HUMAN_REVIEW)
        for slot in updated["slots"]:
            if slot["reviewerVerdict"] != "APPROVED" or slot["unresolvedFindings"]:
                raise ReviewRejected(f"story {slot['storyId']} is not cleanly approved")
            destination = self.repo_root / slot["materialization"]["path"]
            tree_hash, file_hashes = _tree_hash(
                destination,
                expected_artifact_names(slot["storyId"], slot["targetLengths"]),
            )
            if tree_hash != slot["materialization"]["treeHash"]:
                raise SafetyViolation(f"story {slot['storyId']} changed after review")
            slot["finalReadiness"] = {
                "status": "PASS",
                "storyTreeHash": tree_hash,
                "fileHashes": file_hashes,
                "overlapHash": _hash_value(final_overlap[str(slot["storyId"])]),
                "reservationState": "MATERIALIZED",
                "audioPresent": False,
                "manifestRegistered": False,
            }
        updated["evidenceHashes"]["finalReadiness"] = _hash_value(
            [slot["finalReadiness"] for slot in updated["slots"]]
        )
        report = self._human_report(updated)
        report_path = self.packet_dir(run_id, packet_id) / "reports" / "ready_for_human_review.md"
        _atomic_write(report_path, report.encode("utf-8"), mode=0o600)
        updated["evidenceHashes"]["humanReport"] = _sha256_bytes(report.encode("utf-8"))
        return self._record(packet, updated, event_type="READY_FOR_HUMAN_REVIEW",
                            actor=actor, reason="all five text stories passed autonomous and reviewer gates")


def _cli_controller(args) -> AutonomousStoryController:
    return AutonomousStoryController(
        repo_root=args.repo_root,
        worktree=args.worktree,
        factory_home=args.factory_home,
    )


def _print_json(value: object) -> None:
    print(json.dumps(value, sort_keys=True, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Bible PAL Milestone-1 text-only autonomous story controller",
    )
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--run-id", required=True)
    common.add_argument("--packet-id", required=True)
    common.add_argument("--actor", default="controller-owner")
    common.add_argument("--repo-root", required=True)
    common.add_argument("--worktree", required=True)
    common.add_argument("--factory-home")
    subs = parser.add_subparsers(dest="command", required=True)

    plan = subs.add_parser("plan-packet", parents=[common])
    plan.add_argument("--planning", required=True)
    subs.add_parser("status", parents=[common])
    subs.add_parser("emit-writer-assignments", parents=[common])
    ingest = subs.add_parser("ingest-writer-output", parents=[common])
    ingest.add_argument("--source-root", required=True)
    subs.add_parser("validate", parents=[common])
    subs.add_parser("materialize", parents=[common])
    subs.add_parser("emit-review-packet", parents=[common])
    review = subs.add_parser("ingest-review", parents=[common])
    review.add_argument("--review-file", required=True)
    subs.add_parser("emit-corrections", parents=[common])
    subs.add_parser("report", parents=[common])
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    controller = _cli_controller(args)
    try:
        if args.command == "plan-packet":
            controller.plan_packet(
                run_id=args.run_id,
                packet_id=args.packet_id,
                actor=args.actor,
                planning=_load_json(Path(args.planning)),
            )
            result = controller.preflight_anchors(
                args.run_id, args.packet_id, actor=args.actor,
            )
        elif args.command == "status":
            result = controller.load(args.run_id, args.packet_id)
        elif args.command == "emit-writer-assignments":
            result = controller.emit_writer_assignments(args.run_id, args.packet_id, actor=args.actor)
        elif args.command == "ingest-writer-output":
            result = controller.ingest_writer_output(
                args.run_id, args.packet_id, source_root=args.source_root, actor=args.actor,
            )
        elif args.command == "validate":
            result = controller.validate_outputs(args.run_id, args.packet_id, actor=args.actor)
        elif args.command == "materialize":
            result = controller.materialize_for_review(args.run_id, args.packet_id, actor=args.actor)
        elif args.command == "emit-review-packet":
            result = controller.emit_review_packet(args.run_id, args.packet_id, actor=args.actor)
        elif args.command == "ingest-review":
            result = controller.ingest_review(
                args.run_id, args.packet_id, review=_load_json(Path(args.review_file)), actor=args.actor,
            )
        elif args.command == "emit-corrections":
            result = controller.emit_corrections(args.run_id, args.packet_id, actor=args.actor)
        elif args.command == "report":
            result = controller.mark_ready_for_human_review(args.run_id, args.packet_id, actor=args.actor)
        else:  # pragma: no cover - argparse enforces commands.
            raise ControllerConfigError(f"unknown command {args.command}")
    except ControllerError as exc:
        _print_json({"status": "ERROR", "errorType": type(exc).__name__, "error": str(exc)})
        return 2
    _print_json({"status": "OK", "packet": result})
    return 0


__all__ = [
    "ABORTED", "ANCHOR_PREFLIGHT_PASSED", "ASSIGNMENT_READY",
    "AutonomousStoryController", "CONTROLLER_MILESTONE", "CORRECTION_READY",
    "ControllerConfigError", "ControllerError", "ID_RESERVED",
    "IllegalControllerTransition", "IntegrationError", "JournalCorrupt",
    "MAX_CORRECTION_ROUNDS", "PACKET_SIZE", "PLANNED", "QUARANTINED",
    "READY_FOR_HUMAN_REVIEW", "REVIEW_APPROVED", "REVIEW_CHANGES_REQUESTED",
    "REVIEW_READY", "ReviewRejected", "SafetyViolation", "ValidationFailed",
    "VALIDATION_PASSED", "WorkspaceRejected", "WRITER_OUTPUT_RECEIVED",
    "build_parser", "expected_artifact_names", "main", "replay_packet",
    "validate_packet_model",
]


if __name__ == "__main__":
    raise SystemExit(main())
