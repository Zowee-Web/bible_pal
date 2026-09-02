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
import unicodedata
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

import anchor_claims  # noqa: E402
import preflight_anchor_overlap as overlap_gate  # noqa: E402
import story_id_reservations as reservation_service  # noqa: E402
from claude_validator import (  # noqa: E402
    check_meta_text,
    check_reflection_banned,
    validate_lane_identity,
    validate_traditional,
)
from lib import reconstruction_check  # noqa: E402
from reflection_contract import (  # noqa: E402
    REFLECTION_FORMS,
    ReflectionContractError,
    STANDARD_FORM,
    assert_assignment_matches_metadata,
    describe_contract,
    normalize_reflection_form,
    validate_reflection_word_count,
)
from story_prompts import TRADITIONAL_RANGES  # noqa: E402
from story_voice_registry import VoiceValidationError, validate_story_voice  # noqa: E402
from tts_voice_gate import (  # noqa: E402
    TtsVoiceGateError,
    resolve_new_story_tts_voice,
)


LEGACY_CONTROLLER_SCHEMA_VERSION = 1
CONTROLLER_SCHEMA_VERSION = 2
SUPPORTED_CONTROLLER_SCHEMA_VERSIONS = (
    LEGACY_CONTROLLER_SCHEMA_VERSION,
    CONTROLLER_SCHEMA_VERSION,
)
CONTROLLER_MILESTONE = "M1_TEXT_ONLY"
PACKET_SIZE = 5
MAX_CORRECTION_ROUNDS = 3
PRODUCTION_LEASE_SECONDS = 24 * 60 * 60

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

RENEWABLE_PACKET_STATES = frozenset({
    ID_RESERVED,
    ANCHOR_PREFLIGHT_PASSED,
    ASSIGNMENT_READY,
    WRITER_OUTPUT_RECEIVED,
    VALIDATION_PASSED,
    REVIEW_READY,
    REVIEW_CHANGES_REQUESTED,
    CORRECTION_READY,
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
    "PACKET_LEASE_RENEWED",
    "VALIDATION_REFUSED",
    "MATERIALIZATION_RECORDED",
    "STORY_LENGTHS_RECLASSIFIED",
})

#: Same-state events that are legal in only some states.  Constraining only the
#: new type leaves v1/v2 replay of the four pre-existing same-state events
#: bit-for-bit unaffected, which is why this is a narrow map rather than a rule
#: applied to every same-state event.
SAME_STATE_EVENT_STATES = {
    "STORY_LENGTHS_RECLASSIFIED": frozenset({REVIEW_CHANGES_REQUESTED}),
}

#: ADR-030 length reclassification.
#:
#: The owner may remove a Full or Long bucket the anchor does not honestly
#: support.  The alternative -- keeping the bucket and letting a writer reach
#: its floor -- is what ADR-030 section 4 forbids: padding, repeated
#: propositions, invented physical detail, unstated thoughts or motives, or
#: theological commentary added to reach a minimum.  Removing the bucket is how
#: the system says "this passage does not support that length" without asking
#: anyone to write words the passage does not carry.
STORY_LENGTHS_RECLASSIFIED = "STORY_LENGTHS_RECLASSIFIED"

#: The attestation is an OWNER STATEMENT, not a machine proof.  The factory has
#: no authentication substrate: one uid, no signing key, no separate
#: credential, and every event already carries actor="owner".  A schema field
#: naming the reviewer would be exactly as caller-supplied as this token while
#: *looking* like proof, which is strictly worse.  The literal is required in
#: both the evidence record and the event reason so that no later reader of the
#: journal can mistake it for an identity guarantee.
REVIEWER_SEPARATION_STATUS = "REVIEWER_SEPARATION_OWNER_ATTESTED_NOT_MACHINE_PROVEN"

#: Exact key set of the required reviewer-separation attestation.
REVIEWER_ATTESTATION_FIELDS = frozenset({
    "reviewerRole",
    "writerOrRepairerRole",
    "differentActorsAttestedByOwner",
    "ownerActor",
    "reviewEvidenceSha256",
    "writerEvidenceSha256",
})

#: The pinned reviewer sentence that authorizes removing one bucket.
#:
#: This is deliberately exact rather than a keyword search.  A reviewer who
#: writes anything else -- a paraphrase, a longer sentence, a different
#: wording -- does not authorize a removal, and the request fails closed.  The
#: reviewer-facing instruction must therefore quote this sentence verbatim.
LENGTH_SUPPORT_FINDING_RE = re.compile(
    r"^length band (short|full|long) is not supported by the passage$"
)

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
    try:
        parent_info = path.parent.lstat()
    except OSError as exc:
        raise SafetyViolation(f"atomic-write parent is unavailable: {path.parent}: {exc}") from exc
    if stat.S_ISLNK(parent_info.st_mode) or not stat.S_ISDIR(parent_info.st_mode):
        raise SafetyViolation(f"atomic-write parent is not an ordinary directory: {path.parent}")
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


_CURRENT_SLOT_FIELDS = frozenset({
    "slotId", "storyId", "reservation", "proposedAnchor", "narrator",
    "mode", "kidFriendly", "lanes", "targetLengths", "mood",
    "reflectionForm", "authoringBrief", "state", "writerAttempts",
    "correctionHistory",
    "overlapEvidence", "assignment", "workspace", "validationEvidence",
    "reviewerVerdict", "unresolvedFindings", "materialization",
    "finalReadiness",
})
# Historical M1 slots predate Option B and carry no reflectionForm. The legacy
# field set is frozen: it must never gain fields, or a malformed new packet
# could masquerade as history.
_LEGACY_SLOT_FIELDS = frozenset(_CURRENT_SLOT_FIELDS - {"reflectionForm"})

_SLOT_FIELDS_BY_VERSION = {
    LEGACY_CONTROLLER_SCHEMA_VERSION: _LEGACY_SLOT_FIELDS,
    CONTROLLER_SCHEMA_VERSION: _CURRENT_SLOT_FIELDS,
}


def _slot_fields_for_version(version: int) -> frozenset:
    try:
        return _SLOT_FIELDS_BY_VERSION[version]
    except KeyError:
        raise JournalCorrupt("unsupported controller schema version") from None


def _declared_schema_version(packet: object) -> int:
    """Return the packet's declared version, rejecting anything unsupported."""

    if not isinstance(packet, dict):
        raise JournalCorrupt("packet snapshot is not an object")
    version = packet.get("schemaVersion")
    if version not in SUPPORTED_CONTROLLER_SCHEMA_VERSIONS:
        raise JournalCorrupt("unsupported controller schema version")
    return version


def normalize_packet_model(packet: Mapping[str, object]) -> dict:
    """Normalize a validated legacy packet to current semantics, in memory only.

    Historical bytes are never rewritten. A legacy packet omits reflectionForm
    because the concept did not exist; every historical slot is semantically
    the standard reflection form.
    """

    version = _declared_schema_version(packet)
    if version == CONTROLLER_SCHEMA_VERSION:
        return copy.deepcopy(dict(packet))
    normalized = copy.deepcopy(dict(packet))
    normalized["schemaVersion"] = CONTROLLER_SCHEMA_VERSION
    slots = []
    for slot in normalized["slots"]:
        promoted = dict(slot)
        promoted["reflectionForm"] = STANDARD_FORM
        slots.append(promoted)
    normalized["slots"] = slots
    return normalized


def validate_packet_model(packet: object) -> None:
    """Validate the persisted packet model independently of filesystem state."""

    version = _declared_schema_version(packet)
    required = {
        "schemaVersion", "controllerMilestone", "runId", "packetId",
        "createdAt", "updatedAt", "state", "actor", "repoRoot", "worktree",
        "manifestHashAtPlan", "correctionRound", "reviewRound", "slots",
        "evidenceHashes",
    }
    if set(packet) != required:
        raise JournalCorrupt("packet snapshot fields differ from the M1 contract")
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

    slot_required = _slot_fields_for_version(version)
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
        if "reflectionForm" in slot_required and slot["reflectionForm"] not in REFLECTION_FORMS:
            raise JournalCorrupt("slot reflectionForm is not a known reflection form")
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


def normalize_role(value: object) -> str:
    """NFC -> strip -> collapse internal whitespace -> casefold.

    Used ONLY for the non-empty and inequality tests; the raw strings supplied
    by the owner are what get recorded.  The normalization deliberately refuses
    cosmetic near-identity: "Claude Window 2" and "claude  window 2" normalize
    equal and are refused, which is the safe direction -- two roles that differ
    only in spacing are far more likely to be one person than two.
    """
    if not isinstance(value, str):
        raise ReviewRejected("attestation role must be a string")
    folded = unicodedata.normalize("NFC", value).strip()
    return re.sub(r"\s+", " ", folded).casefold()


def is_legal_downward_move(old: object, new: object) -> bool:
    """A reclassification may only truncate the tail of the length list.

    ``0 < len(new) < len(old) and new == old[:len(new)]`` gives, in one
    predicate: non-empty, strictly smaller, order preserving, no bucket that
    was not already present, and -- because every list begins with ``short`` --
    ``short`` is never removable.

    This is applied in the operation *and* in replay, because
    ``validate_packet_model`` accepts ``["short", "long"]``: it checks only
    uniqueness and canonical ordering, and that list is canonically ordered.
    Without the predicate in replay a hand-edited journal could install a
    non-tail set.
    """
    if not isinstance(old, list) or not isinstance(new, list):
        return False
    if not all(isinstance(item, str) for item in old + new):
        return False
    return 0 < len(new) < len(old) and new == old[:len(new)]


def length_support_finding_bucket(text: object) -> str | None:
    """Return the bucket a length-support finding names, or None.

    The finding is normalized (NFC + whitespace collapse) before matching, but
    the bucket token is matched case-sensitively: an uppercase ``FULL`` is not
    the bucket ``full``.
    """
    if not isinstance(text, str):
        return None
    candidate = re.sub(r"\s+", " ", unicodedata.normalize("NFC", text).strip())
    match = LENGTH_SUPPORT_FINDING_RE.match(candidate)
    return match.group(1) if match else None


def _validate_event(event: object, expected_sequence: int) -> dict:
    if not isinstance(event, dict) or set(event) != EVENT_FIELDS:
        raise JournalCorrupt(f"event {expected_sequence} has invalid fields")
    if event["schemaVersion"] not in SUPPORTED_CONTROLLER_SCHEMA_VERSIONS:
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
    if event["packet"]["schemaVersion"] != event["schemaVersion"]:
        raise JournalCorrupt("event schema version disagrees with its packet")
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
                allowed_states = SAME_STATE_EVENT_STATES.get(event["eventType"])
                if allowed_states is not None and current["state"] not in allowed_states:
                    raise IllegalControllerTransition(
                        f"same-state event {event['eventType']!r} is not legal in "
                        f"{current['state']}"
                    )
            elif event["toState"] not in LEGAL_TRANSITIONS[current["state"]]:
                raise IllegalControllerTransition(
                    f"illegal controller transition {current['state']} -> {event['toState']}"
                )
        # Raw identity and evidence hash are already verified above; only now
        # is the historical snapshot normalized to current semantics.
        following = normalize_packet_model(event["packet"])
        if current is not None:
            _assert_target_lengths_invariants(current, following, event, sequence)
        current = following
    return current


def _assert_target_lengths_invariants(prior: dict, following: dict,
                                      event: Mapping[str, object],
                                      sequence: int) -> None:
    """targetLengths may change ONLY through a valid reclassification event.

    Four invariants, checked on every event so a hand-edited or forged journal
    cannot install a length set the operation would have refused:

    1. only ``STORY_LENGTHS_RECLASSIFIED`` may change any slot's targetLengths;
    2. every change must satisfy the downward tail-truncation predicate;
    3. a reclassification event must change at least one slot;
    4. it must carry its evidence hash, and must not move the rounds.
    """
    prior_by_id = {slot["storyId"]: slot for slot in prior["slots"]}
    changed = []
    for slot in following["slots"]:
        before = prior_by_id.get(slot["storyId"])
        if before is None:
            continue
        if before["targetLengths"] != slot["targetLengths"]:
            changed.append((slot["storyId"], before["targetLengths"],
                            slot["targetLengths"]))
    if event["eventType"] != STORY_LENGTHS_RECLASSIFIED:
        if changed:
            raise JournalCorrupt(
                f"event {event['eventType']!r} at line {sequence} changes "
                f"targetLengths for {[c[0] for c in changed]}; only "
                f"{STORY_LENGTHS_RECLASSIFIED} may"
            )
        return
    if not changed:
        raise JournalCorrupt(
            f"{STORY_LENGTHS_RECLASSIFIED} at line {sequence} changes no "
            "targetLengths"
        )
    for story_id, before, after in changed:
        if not is_legal_downward_move(before, after):
            raise JournalCorrupt(
                f"{STORY_LENGTHS_RECLASSIFIED} at line {sequence} moves story "
                f"{story_id} from {before} to {after}, which is not a downward "
                "tail truncation"
            )
    if (prior["reviewRound"] != following["reviewRound"]
            or prior["correctionRound"] != following["correctionRound"]):
        raise JournalCorrupt(
            f"{STORY_LENGTHS_RECLASSIFIED} at line {sequence} moved a round "
            "counter; reclassification consumes no correction round"
        )
    key = f"lengthReclassificationReview{following['reviewRound']}"
    if key not in following["evidenceHashes"]:
        raise JournalCorrupt(
            f"{STORY_LENGTHS_RECLASSIFIED} at line {sequence} is missing "
            f"evidenceHashes[{key!r}]"
        )


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
        self.factory_home = Path(os.path.abspath(os.fspath(Path(raw_home).expanduser())))
        try:
            home_info = self.factory_home.lstat()
        except FileNotFoundError:
            home_info = None
        except OSError as exc:
            raise ControllerConfigError(f"cannot inspect factory home {self.factory_home}: {exc}") from exc
        if home_info is not None and stat.S_ISLNK(home_info.st_mode):
            raise ControllerConfigError("factory home may not be a symlink")
        resolved_home = self.factory_home.resolve(strict=False)
        if _is_within(resolved_home, self.repo_root) or _is_within(resolved_home, self.worktree):
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

    def _verify_private_runtime_directory(self, path: Path) -> None:
        try:
            info = path.lstat()
        except OSError as exc:
            raise SafetyViolation(f"private runtime directory is unavailable: {path}: {exc}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise SafetyViolation(f"private runtime path is not an ordinary directory: {path}")
        if info.st_uid != os.geteuid():
            raise SafetyViolation(f"private runtime directory is not owned by this user: {path}")
        actual_mode = stat.S_IMODE(info.st_mode)
        if actual_mode != 0o700:
            raise SafetyViolation(
                f"private runtime directory must have mode 0700, found {actual_mode:04o}: {path}"
            )

    def _verify_private_runtime_file(self, path: Path) -> None:
        try:
            info = path.lstat()
        except OSError as exc:
            raise SafetyViolation(f"private runtime evidence file is unavailable: {path}: {exc}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise SafetyViolation(f"private runtime evidence is not an ordinary file: {path}")
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise SafetyViolation(f"private runtime evidence file must be owner-owned mode 0600: {path}")

    def _ensure_runtime_directory(self, path: Path) -> Path:
        path = Path(os.path.abspath(os.fspath(path)))
        try:
            relative = path.relative_to(self.factory_home)
        except ValueError as exc:
            raise SafetyViolation(f"runtime directory escapes factory home: {path}") from exc
        cursor = self.factory_home
        for part in (None, *relative.parts):
            if part is not None:
                cursor = cursor / part
            try:
                os.mkdir(cursor, 0o700)
            except FileExistsError:
                pass
            except OSError as exc:
                raise SafetyViolation(f"cannot create private runtime directory {cursor}: {exc}") from exc
            self._verify_private_runtime_directory(cursor)
        return path

    def _prepare_packet_runtime(self, run_id: str, packet_id: str) -> Path:
        return self._ensure_runtime_directory(self.packet_dir(run_id, packet_id))

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
        pdir = self._prepare_packet_runtime(packet["runId"], packet["packetId"])
        journal = pdir / "events.jsonl"
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(journal, flags, 0o600)
        try:
            # L5 in the L1-L6 hierarchy.  The rank guard raises rather than
            # deadlocking if a future caller ever holds the packet journal
            # while reaching back down for the ACL or reservation ledger.
            with anchor_claims.lock_rank(anchor_claims.L5_PACKET_JOURNAL, str(journal)):
                fcntl.flock(fd, fcntl.LOCK_EX)
                journal_info = os.fstat(fd)
                if (
                    not stat.S_ISREG(journal_info.st_mode)
                    or journal_info.st_uid != os.geteuid()
                    or stat.S_IMODE(journal_info.st_mode) != 0o600
                ):
                    raise SafetyViolation("controller journal must be an owner-owned regular file with mode 0600")
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
            allowed = {"proposedAnchor", "mood", "narrator", "mode", "kidFriendly", "lengths", "reflectionForm"}
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
            try:
                reflection_form = normalize_reflection_form(raw.get("reflectionForm"))
            except ReflectionContractError as exc:
                raise ControllerConfigError(
                    f"planning story {index} has an invalid reflectionForm: {exc}"
                ) from exc
            normalized.append({
                "anchor": anchor,
                "mood": mood,
                "narrator": self._validate_narrator(raw.get("narrator")),
                "lengths": lengths,
                "reflectionForm": reflection_form,
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
        lease_seconds: int | float = PRODUCTION_LEASE_SECONDS,
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
                "reflectionForm": plan["reflectionForm"],
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

        return self._continue_planned_reservation(
            packet, actor=actor, lease_seconds=lease_seconds,
        )

    def _assert_planning_snapshot(self, packet: dict, planning: dict) -> None:
        plans = self._validate_plan(planning)
        expected = [
            {
                "proposedAnchor": plan["anchor"],
                "mood": plan["mood"],
                "narrator": plan["narrator"],
                "mode": "traditional",
                "kidFriendly": False,
                "lanes": ["web", "kjv"],
                "targetLengths": plan["lengths"],
            }
            for plan in plans
        ]
        actual = [
            {
                "proposedAnchor": slot["proposedAnchor"],
                "mood": slot["mood"],
                "narrator": slot["narrator"],
                "mode": slot["mode"],
                "kidFriendly": slot["kidFriendly"],
                "lanes": slot["lanes"],
                "targetLengths": slot["targetLengths"],
            }
            for slot in packet["slots"]
        ]
        if actual != expected:
            raise ControllerConfigError("resume planning input differs from the persisted PLANNED snapshot")

    def _validate_reservations_for_adoption(self, packet: dict, reservations: Iterable[object]) -> tuple:
        ordered = tuple(sorted(reservations, key=lambda item: item.story_id))
        if len(ordered) != PACKET_SIZE:
            raise IntegrationError("PLANNED recovery requires exactly five authoritative reservations")
        seen = set()
        now = self.clock().astimezone(dt.timezone.utc)
        for reservation in ordered:
            story_id = reservation.story_id
            if type(story_id) is not int or not 3000 <= story_id <= 3258 or story_id in seen:
                raise IntegrationError("recovery reservation IDs are duplicate or outside 3000-3258")
            seen.add(story_id)
            if reservation.state != "RESERVED":
                raise IntegrationError(
                    f"story {story_id} is {reservation.state}; PLANNED recovery adopts RESERVED only"
                )
            if reservation.run_id != packet["runId"] or reservation.packet_id != packet["packetId"]:
                raise IntegrationError(f"story {story_id} reservation identity does not match packet")
            if reservation.actor != packet["actor"] or reservation.worktree != packet["worktree"]:
                raise IntegrationError(f"story {story_id} reservation ownership does not match packet")
            ref = _reservation_to_dict(reservation)
            _validate_reservation_ref(ref, story_id)
            try:
                expiry = dt.datetime.fromisoformat(
                    reservation.lease_expires_at.replace("Z", "+00:00")
                ).astimezone(dt.timezone.utc)
            except (AttributeError, TypeError, ValueError) as exc:
                raise IntegrationError(f"story {story_id} lease expiry is invalid") from exc
            if expiry <= now:
                raise IntegrationError(f"story {story_id} reservation lease is expired")
            production = self.repo_root / "assets" / "stories" / "traditional" / str(story_id)
            try:
                production.lstat()
            except FileNotFoundError:
                pass
            except OSError as exc:
                raise IntegrationError(f"cannot inspect production path for story {story_id}: {exc}") from exc
            else:
                raise IntegrationError(f"story {story_id} already has a production path")
        return ordered

    def _continue_planned_reservation(
        self,
        packet: dict,
        *,
        actor: str,
        lease_seconds: int | float,
    ) -> dict:
        if packet["state"] != PLANNED:
            raise IllegalControllerTransition("reservation continuation requires PLANNED")
        states = self.reservations.replay_ledger(self.factory_home)
        active = [value for value in states.values() if value.state in {"RESERVED", "MATERIALIZED"}]
        ambiguous = [
            value for value in active
            if (value.run_id == packet["runId"]) != (value.packet_id == packet["packetId"])
        ]
        if ambiguous:
            raise IntegrationError("reservation ledger has conflicting run/packet ownership")
        existing = [
            value for value in active
            if value.run_id == packet["runId"] and value.packet_id == packet["packetId"]
        ]
        if existing:
            if len(existing) != PACKET_SIZE:
                raise IntegrationError("partial or extra authoritative packet reservations require owner review")
            reserved = self._validate_reservations_for_adoption(packet, existing)
            reason = "reconciled five authoritative reservations after missing controller transition"
        else:
            # L3 (reservation ledger) and L4 (per-story locks) live inside the
            # reservation service.  They are observed here, at the call
            # boundary, because that module is outside this change's scope; the
            # ranks are still enforced relative to any ACL lock held above.
            with anchor_claims.lock_rank(
                anchor_claims.L3_RESERVATION_LEDGER, "reserve_packet"
            ), anchor_claims.lock_rank(anchor_claims.L4_STORY_LOCK, "reserve_packet"):
                reserved = self.reservations.reserve_packet(
                    count=PACKET_SIZE,
                    run_id=packet["runId"],
                    packet_id=packet["packetId"],
                    actor=actor,
                    worktree=self.worktree,
                    repo_root=self.repo_root,
                    factory_home=self.factory_home,
                    lease_seconds=lease_seconds,
                    worktrees=self.worktrees,
                )
            reserved = self._validate_reservations_for_adoption(packet, reserved)
            reason = "reservation service returned five authoritative claims"
        self._assert_manifest_unchanged(packet)
        updated = self._transition(packet, ID_RESERVED)
        for slot, reservation in zip(updated["slots"], reserved):
            slot["storyId"] = reservation.story_id
            slot["reservation"] = _reservation_to_dict(reservation)
            slot["authoringBrief"] = self._authoring_brief(slot)
        updated["evidenceHashes"]["reservations"] = _hash_value(
            [slot["reservation"] for slot in updated["slots"]]
        )
        return self._record(packet, updated, event_type="IDS_RESERVED", actor=actor, reason=reason)

    def resume_planned_packet(
        self,
        *,
        run_id: str,
        packet_id: str,
        actor: str,
        planning: dict,
        lease_seconds: int | float = PRODUCTION_LEASE_SECONDS,
    ) -> dict:
        run_id = _safe_identifier(run_id, "runId")
        packet_id = _safe_identifier(packet_id, "packetId")
        actor = _safe_identifier(actor, "actor")
        packet = self.load(run_id, packet_id)
        if packet["state"] != PLANNED:
            raise IllegalControllerTransition("resume-planned requires PLANNED")
        if packet["actor"] != actor:
            raise ControllerConfigError("resume actor differs from the persisted packet owner")
        if packet["repoRoot"] != str(self.repo_root) or packet["worktree"] != str(self.worktree):
            raise ControllerConfigError("resume repository identity differs from persisted packet")
        if any(slot["storyId"] is not None or slot["reservation"] is not None for slot in packet["slots"]):
            raise JournalCorrupt("PLANNED packet contains reservation references")
        self._assert_planning_snapshot(packet, planning)
        self._assert_manifest_unchanged(packet)
        pdir = self._prepare_packet_runtime(run_id, packet_id)
        self._verify_private_runtime_file(pdir / "events.jsonl")
        self._verify_private_runtime_file(pdir / "packet.json")
        return self._continue_planned_reservation(
            packet, actor=actor, lease_seconds=lease_seconds,
        )

    def privatize_planned_runtime(
        self,
        *,
        run_id: str,
        packet_id: str,
        actor: str,
        planning: dict,
    ) -> dict:
        """Privatize only the exact, controller-created stranded M1 tree.

        This is deliberately narrower than a general chmod utility: any extra
        directory, file, reservation state, symlink, owner mismatch, or mode
        other than the known old 0755/new 0700 directory modes fails closed.
        """

        run_id = _safe_identifier(run_id, "runId")
        packet_id = _safe_identifier(packet_id, "packetId")
        actor = _safe_identifier(actor, "actor")
        packet = self.load(run_id, packet_id)
        if packet["state"] != PLANNED:
            raise IllegalControllerTransition("runtime privatization requires PLANNED")
        if packet["actor"] != actor:
            raise ControllerConfigError("privatization actor differs from persisted packet owner")
        if packet["repoRoot"] != str(self.repo_root) or packet["worktree"] != str(self.worktree):
            raise ControllerConfigError("privatization repository identity differs from persisted packet")
        if any(slot["storyId"] is not None or slot["reservation"] is not None for slot in packet["slots"]):
            raise JournalCorrupt("PLANNED packet contains reservation references")
        self._assert_planning_snapshot(packet, planning)
        self._assert_manifest_unchanged(packet)
        if self.reservations.replay_ledger(self.factory_home):
            raise IntegrationError("stranded-runtime privatization requires an empty reservation ledger")

        pdir = self.packet_dir(run_id, packet_id)
        expected_dirs = {
            self.factory_home,
            self.factory_home / "runs",
            self.factory_home / "runs" / run_id,
            self.factory_home / "runs" / run_id / "packets",
            pdir,
        }
        expected_files = {pdir / "events.jsonl", pdir / "packet.json"}
        actual_dirs = set()
        actual_files = set()
        for raw_root, dir_names, file_names in os.walk(self.factory_home, followlinks=False):
            root = Path(raw_root)
            actual_dirs.add(root)
            for name in dir_names:
                path = root / name
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                    raise SafetyViolation(f"stranded runtime contains an unsafe directory entry: {path}")
                actual_dirs.add(path)
            for name in file_names:
                path = root / name
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                    raise SafetyViolation(f"stranded runtime contains an unsafe file entry: {path}")
                actual_files.add(path)
        if actual_dirs != expected_dirs or actual_files != expected_files:
            raise SafetyViolation("stranded runtime tree differs from the exact controller-created layout")

        prior_modes = {}
        for path in expected_dirs:
            info = path.lstat()
            mode = stat.S_IMODE(info.st_mode)
            if info.st_uid != os.geteuid() or mode not in {0o700, 0o755}:
                raise SafetyViolation(f"stranded runtime directory is not safely attributable: {path}")
            prior_modes[str(path)] = f"{mode:04o}"
        for path in expected_files:
            info = path.lstat()
            if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600:
                raise SafetyViolation(f"stranded runtime evidence file is not owner-private: {path}")
        snapshot = _load_json(pdir / "packet.json", error_type=SafetyViolation)
        # A legacy convenience snapshot legitimately omits reflectionForm. It is
        # fully validated against its own declared version before normalization,
        # so a tampered or malformed snapshot still fails.
        try:
            validate_packet_model(snapshot)
            normalized_snapshot = normalize_packet_model(snapshot)
        except JournalCorrupt as exc:
            raise SafetyViolation(f"packet snapshot is not a valid packet model: {exc}") from exc
        if normalized_snapshot != packet:
            raise SafetyViolation("packet snapshot differs from authoritative journal replay")

        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
        for path in sorted(expected_dirs, key=lambda item: len(item.parts), reverse=True):
            try:
                fd = os.open(path, flags)
            except OSError as exc:
                raise SafetyViolation(f"cannot securely open stranded runtime directory {path}: {exc}") from exc
            try:
                info = os.fstat(fd)
                if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
                    raise SafetyViolation(f"stranded runtime ownership changed during repair: {path}")
                os.fchmod(fd, 0o700)
                os.fsync(fd)
            finally:
                os.close(fd)
        for path in expected_dirs:
            self._verify_private_runtime_directory(path)
        return {
            "status": "PRIVATE_RUNTIME_READY",
            "runId": run_id,
            "packetId": packet_id,
            "priorModes": prior_modes,
            "effectiveMode": "0700",
            "directoryCount": len(expected_dirs),
        }

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

    def renew_packet_lease(
        self,
        run_id: str,
        packet_id: str,
        *,
        actor: str,
        recover_expired: bool = False,
        lease_seconds: int | float = PRODUCTION_LEASE_SECONDS,
    ) -> dict:
        """Renew five owner-matched RESERVED claims without advancing workflow state.

        Reservation events are appended one ID at a time.  The controller journal is
        updated only after all five succeed.  If an interruption occurs partway through,
        replay exposes the already-renewed expirations while the packet still carries the
        prior references; a retry recognizes those matching-token renewals and continues
        with only the remaining claims.
        """

        packet = self.load(run_id, packet_id)
        if packet["state"] not in RENEWABLE_PACKET_STATES:
            raise IllegalControllerTransition(
                f"packet lease renewal is not allowed from {packet['state']}"
            )
        if actor != packet["actor"]:
            raise IntegrationError("packet lease renewal actor is not the packet owner")
        if type(recover_expired) is not bool:
            raise ControllerConfigError("recover_expired must be a boolean")
        if (
            isinstance(lease_seconds, bool)
            or not isinstance(lease_seconds, (int, float))
            or lease_seconds <= 0
        ):
            raise ControllerConfigError("lease_seconds must be a positive number")
        self._assert_manifest_unchanged(packet)

        states = self.reservations.replay_ledger(self.factory_home)
        now = self.clock().astimezone(dt.timezone.utc)
        candidates = []
        for slot in packet["slots"]:
            story_id = slot["storyId"]
            current = states.get(story_id)
            if current is None:
                raise IntegrationError(f"story {story_id} has no authoritative reservation")
            if current.state != "RESERVED" or slot["reservation"]["state"] != "RESERVED":
                raise IntegrationError(f"story {story_id} reservation is not RESERVED")
            supplied = _reservation_from_dict(self.reservations, slot["reservation"])
            for field in (
                "story_id", "run_id", "packet_id", "actor", "lease_token",
                "worktree", "reserved_at",
            ):
                if getattr(current, field) != getattr(supplied, field):
                    raise IntegrationError(
                        f"story {story_id} reservation ownership changed: {field}"
                    )
            try:
                current_expiry = dt.datetime.fromisoformat(
                    current.lease_expires_at.replace("Z", "+00:00")
                ).astimezone(dt.timezone.utc)
                supplied_expiry = dt.datetime.fromisoformat(
                    supplied.lease_expires_at.replace("Z", "+00:00")
                ).astimezone(dt.timezone.utc)
            except (AttributeError, TypeError, ValueError) as exc:
                raise IntegrationError(f"story {story_id} lease expiry is invalid") from exc
            if current_expiry < supplied_expiry:
                raise IntegrationError(
                    f"story {story_id} authoritative lease moved backward"
                )
            if current_expiry <= now and not recover_expired:
                raise IntegrationError(
                    f"story {story_id} lease is expired; --recover-expired is required"
                )
            candidates.append((slot, supplied, current, current_expiry))

        renewed_rows = []
        renewed_by_id = {}
        reservation_error = getattr(
            self.reservations, "StoryIdReservationError", Exception
        )
        for slot, supplied, current, current_expiry in candidates:
            try:
                if current_expiry <= now:
                    renewed = self.reservations.renew_expired_reservation(
                        supplied,
                        repo_root=self.repo_root,
                        factory_home=self.factory_home,
                        worktrees=self.worktrees,
                        actor=actor,
                        owner_authorized=True,
                        lease_seconds=lease_seconds,
                        now=now,
                    )
                else:
                    renewed = self.reservations.renew_reservation(
                        supplied,
                        repo_root=self.repo_root,
                        factory_home=self.factory_home,
                        worktrees=self.worktrees,
                        actor=actor,
                        lease_seconds=lease_seconds,
                        now=now,
                    )
            except reservation_error as exc:
                raise IntegrationError(
                    f"story {slot['storyId']} lease renewal failed: {exc}"
                ) from exc
            if renewed.state != "RESERVED" or renewed.lease_token != supplied.lease_token:
                raise IntegrationError(
                    f"story {slot['storyId']} renewal returned ambiguous ownership"
                )
            try:
                renewed_expiry = dt.datetime.fromisoformat(
                    renewed.lease_expires_at.replace("Z", "+00:00")
                ).astimezone(dt.timezone.utc)
            except (AttributeError, TypeError, ValueError) as exc:
                raise IntegrationError(
                    f"story {slot['storyId']} renewed lease expiry is invalid"
                ) from exc
            if renewed_expiry <= now:
                raise IntegrationError(
                    f"story {slot['storyId']} renewed lease is not active"
                )
            renewed_by_id[slot["storyId"]] = renewed
            renewed_rows.append({
                "storyId": slot["storyId"],
                "leaseToken": renewed.lease_token,
                "priorLeaseExpiresAt": supplied.lease_expires_at,
                "leaseExpiresAt": renewed.lease_expires_at,
                "recoveredExpired": current_expiry <= now,
            })

        updated = copy.deepcopy(packet)
        for slot in updated["slots"]:
            slot["reservation"] = _reservation_to_dict(renewed_by_id[slot["storyId"]])
        updated["updatedAt"] = self._now()
        renewal_round = 1 + sum(
            key.startswith("leaseRenewalRound")
            for key in packet["evidenceHashes"]
        )
        updated["evidenceHashes"][f"leaseRenewalRound{renewal_round}"] = _hash_value(
            renewed_rows
        )
        return self._record(
            packet,
            updated,
            event_type="PACKET_LEASE_RENEWED",
            actor=actor,
            reason=(
                "owner-authorized expired packet lease recovery"
                if any(row["recoveredExpired"] for row in renewed_rows)
                else "active packet lease checkpoint"
            ),
        )

    #: Reservation lifecycle -> overlap-gate queue vocabulary.  Total over the
    #: reservation service's own ``_STATES``; there is deliberately no default
    #: branch.  ``MATERIALIZED`` and ``RETIRED`` project to ``locked`` because
    #: the passage has been consumed and can never be re-drawn -- the earlier
    #: ``materialized`` string was outside the gate's vocabulary and was
    #: silently discarded, so a materialized story occupied nothing.
    RESERVATION_QUEUE_PROJECTION = {
        "RESERVED": "reserved",
        "MATERIALIZED": "locked",
        "RETIRED": "locked",
        "RELEASED": None,
    }

    @classmethod
    def reservation_to_queue_state(cls, state: str) -> str | None:
        """Project one reservation state, or raise.  Never guesses."""
        if state not in cls.RESERVATION_QUEUE_PROJECTION:
            raise IntegrationError(
                f"unmapped reservation state {state!r}; the overlap queue "
                "cannot omit a state it does not recognise"
            )
        return cls.RESERVATION_QUEUE_PROJECTION[state]

    def _overlap_queue_snapshot(self, packet: dict) -> Path:
        states = self._authoritative_reservations(packet)
        payload = {"reservations": []}
        for slot in packet["slots"]:
            current = states[slot["storyId"]]
            projected = self.reservation_to_queue_state(current.state)
            if projected is None:
                continue
            payload["reservations"].append({
                "storyId": slot["storyId"],
                "proposedAnchor": slot["proposedAnchor"],
                "state": projected,
            })
        path = self.packet_dir(packet["runId"], packet["packetId"]) / "overlap_queue_snapshot.json"
        _write_json(path, payload)
        return path

    def acl_queue_rows(self, *, exclude_packet=None) -> list[dict]:
        """Project every global anchor claim into gate queue rows.

        This is what makes a second concurrent packet safe: the queue stops
        describing only our own five slots and starts describing every packet's
        occupancy, through ``anchor_claims``' single total projection.
        """
        claims = anchor_claims.replay_ledger(self.factory_home)
        return anchor_claims.build_overlap_queue(
            claims.values(), exclude_packet=exclude_packet
        )

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
        self._ensure_runtime_directory(evidence_dir)
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
            "reflectionContract": describe_contract(slot["reflectionForm"]),
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
        self._ensure_runtime_directory(pdir / "assignments")
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
        self._ensure_runtime_directory(destination)
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

        # Resolve the reflection form BEFORE any range check.  The assignment is the
        # immutable planning authority; metadata may omit the field (normalizing to
        # standard) but may never disagree with it.  A mismatch is the writer
        # self-elevation path and fails closed for both lanes.
        assigned_form = slot.get("reflectionForm", STANDARD_FORM)
        form_ok = True
        try:
            reflection_form = assert_assignment_matches_metadata(
                assigned_form, meta.get("reflectionForm")
            )
        except ReflectionContractError as exc:
            form_ok = False
            reflection_form = normalize_reflection_form(assigned_form)
            errors.append(f"story {story_id}: reflection form: {exc}")
        valid_range = describe_contract(reflection_form)["validWordRange"]

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
            try:
                applied_range = validate_reflection_word_count(words, reflection_form)
            except ReflectionContractError as exc:
                applied_range = list(valid_range)
                item_errors.append(str(exc))
            meta_hit = check_meta_text(text)
            if meta_hit is not None:
                item_errors.append(f"meta-text {meta_hit!r}")
            banned = check_reflection_banned(text)
            if banned is not None:
                item_errors.append(f"banned reflection phrase {banned!r}")
            for problem in item_errors:
                errors.append(f"story {story_id}: {name}: {problem}")
            reflection_details.append({"file": name, "words": words,
                                       "reflectionForm": reflection_form,
                                       "appliedRange": list(applied_range),
                                       "passed": not item_errors, "errors": item_errors})
        checks.append({"name": "reflection_quality",
                       "passed": form_ok and all(v["passed"] for v in reflection_details),
                       "reflectionForm": reflection_form,
                       "assignedForm": assigned_form,
                       "validWordRange": list(valid_range),
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
        self._ensure_runtime_directory(validation_dir)
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
        self._ensure_runtime_directory(review_dir)
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

    # ------------------------------------------------------------------
    # ADR-030 owner-authorized length reclassification
    # ------------------------------------------------------------------

    def _validate_reviewer_attestation(self, packet: dict, attestation: object,
                                       *, actor: str) -> dict:
        """Validate the owner's reviewer-separation attestation.

        This is an owner statement, hash-bound to the exact review verdicts and
        the exact writer artifacts under adjudication.  It is NOT a proof that
        the named roles were the actual actors, and nothing here should be read
        as claiming otherwise.
        """
        if not isinstance(attestation, dict):
            raise ReviewRejected("reviewerAttestation must be an object")
        if set(attestation) != REVIEWER_ATTESTATION_FIELDS:
            raise ReviewRejected(
                "reviewerAttestation fields must be exactly "
                f"{sorted(REVIEWER_ATTESTATION_FIELDS)}"
            )
        if attestation["differentActorsAttestedByOwner"] is not True:
            raise ReviewRejected(
                "differentActorsAttestedByOwner must be literal true; truthy "
                "values are refused"
            )
        if attestation["ownerActor"] != packet["actor"] or actor != packet["actor"]:
            raise ReviewRejected(
                "reclassification actor and ownerActor must both equal the "
                "packet owner"
            )
        reviewer = normalize_role(attestation["reviewerRole"])
        writer = normalize_role(attestation["writerOrRepairerRole"])
        if not reviewer or not writer:
            raise ReviewRejected("attestation roles must be non-empty after normalization")
        if reviewer == writer:
            raise ReviewRejected(
                "attested reviewer and writer roles are the same after "
                "normalization; owner attestation cannot assert separation"
            )

        for field in ("reviewEvidenceSha256", "writerEvidenceSha256"):
            value = attestation[field]
            if not isinstance(value, str) or not HEX64_RE.fullmatch(value):
                raise ReviewRejected(f"{field} must be a 64-character hex digest")

        # Bind to already-recorded, hash-chained controller evidence.  Neither
        # hash is caller-selected and neither floats to "latest": the review
        # key is pinned to THIS review round, and the writer key to the highest
        # attempt actually recorded on the packet.
        review_key = f"reviewVerdictsRound{packet['reviewRound']}"
        recorded_review = packet["evidenceHashes"].get(review_key)
        if recorded_review is None:
            raise ReviewRejected(f"packet has no recorded {review_key}")
        if attestation["reviewEvidenceSha256"] != recorded_review:
            raise ReviewRejected(
                f"reviewEvidenceSha256 does not match recorded {review_key}"
            )
        attempts = [slot["writerAttempts"] for slot in packet["slots"]]
        writer_key = f"writerOutputAttempt{max(attempts)}"
        recorded_writer = packet["evidenceHashes"].get(writer_key)
        if recorded_writer is None:
            raise ReviewRejected(f"packet has no recorded {writer_key}")
        if attestation["writerEvidenceSha256"] != recorded_writer:
            raise ReviewRejected(
                f"writerEvidenceSha256 does not match recorded {writer_key}"
            )
        return dict(attestation)

    def _validate_removed_bucket_findings(self, slot: dict, removed: list[str],
                                          mapping: object) -> dict:
        """One distinct persisted reviewer finding per removed bucket.

        Bidirectional by design.  Key-set equality alone would let a reviewer
        finding about Full be silently ignored while only Long is removed, so
        the reverse direction is checked too: every length-support finding the
        reviewer recorded must correspond to a removed bucket.

        That reverse rule also disposes of the retained-``short`` case.  A
        ``length band short is not supported`` finding can never be consumed,
        because ``short`` is not removable, so the request always fails and the
        contradiction reaches the owner instead of being dropped.
        """
        story_id = slot["storyId"]
        if not isinstance(mapping, dict):
            raise ReviewRejected(f"story {story_id}: removedBucketFindings must be an object")
        if set(mapping) != set(removed):
            raise ReviewRejected(
                f"story {story_id}: removedBucketFindings keys {sorted(mapping)} "
                f"do not exactly match removed buckets {sorted(removed)}"
            )
        findings = slot["unresolvedFindings"]
        seen_indexes: list[int] = []
        resolved = {}
        for bucket in sorted(mapping):
            entry = mapping[bucket]
            if not isinstance(entry, dict) or set(entry) != {"findingIndex", "findingText"}:
                raise ReviewRejected(
                    f"story {story_id}: finding entry for {bucket!r} must be "
                    "exactly {findingIndex, findingText}"
                )
            index = entry["findingIndex"]
            if type(index) is not int or not 0 <= index < len(findings):
                raise ReviewRejected(
                    f"story {story_id}: findingIndex for {bucket!r} is out of range"
                )
            if index in seen_indexes:
                raise ReviewRejected(
                    f"story {story_id}: findingIndex {index} cited for more than "
                    "one bucket; no single finding may authorize two removals"
                )
            seen_indexes.append(index)
            if findings[index] != entry["findingText"]:
                raise ReviewRejected(
                    f"story {story_id}: findingText for {bucket!r} is not byte-equal "
                    "to the persisted unresolved finding; paraphrase is refused"
                )
            named = length_support_finding_bucket(entry["findingText"])
            if named is None:
                raise ReviewRejected(
                    f"story {story_id}: finding for {bucket!r} does not match the "
                    "pinned length-support sentence"
                )
            if named != bucket:
                raise ReviewRejected(
                    f"story {story_id}: finding names band {named!r} but is mapped "
                    f"to {bucket!r}"
                )
            resolved[bucket] = {"findingIndex": index, "findingText": entry["findingText"]}

        recorded = {b for b in (length_support_finding_bucket(f) for f in findings)
                    if b is not None}
        if recorded != set(removed):
            raise ReviewRejected(
                f"story {story_id}: reviewer recorded length-support findings for "
                f"{sorted(recorded)} but the request removes {sorted(removed)}; "
                "every such finding must be consumed"
            )
        return resolved

    def _assert_reclassification_custody(self, packet: dict, slot: dict) -> None:
        """Production custody: no audio, not cataloged, reservation untouched."""
        story_id = slot["storyId"]
        materialization = slot.get("materialization")
        if not isinstance(materialization, dict):
            raise SafetyViolation(f"story {story_id}: no controller materialization evidence")
        if materialization.get("audioPresent") is not False:
            raise SafetyViolation(f"story {story_id}: audioPresent is not False")
        if materialization.get("manifestRegistered") is not False:
            raise SafetyViolation(f"story {story_id}: story is registered in the catalog")
        destination = self.repo_root / materialization["path"]
        if destination.exists() and any(
            path.suffix.lower() in {".mp3", ".wav", ".m4a"} for path in destination.iterdir()
        ):
            raise SafetyViolation(f"story {story_id}: audio exists in production")

    def reclassify_story_lengths(
        self,
        run_id: str,
        packet_id: str,
        *,
        actor: str,
        reclassifications: list,
        reviewer_attestation: object,
        owner_authorized: bool = False,
    ) -> dict:
        """Remove Full/Long buckets the anchor does not honestly support.

        ADR-030 makes Short the default and Full and Long conditional on what
        the approved anchor supports.  When a reviewer records that a band is
        unsupported, the honest response is to omit the band -- not to have a
        writer pad, repeat propositions, invent physical detail, add unstated
        thoughts or motives, or add theological commentary to reach a floor.

        **Omission is not deletion.**  This operation changes the authoritative
        target-length set and records why.  It removes no story, reflection,
        scripture, metadata, audio or historical artifact from the record, and
        it never touches an omitted variant's bytes in any prior evidence.

        Every check runs for every named slot before any mutation, so a
        partially applied reclassification is unrepresentable.
        """
        packet = self.load(run_id, packet_id)
        if packet["state"] != REVIEW_CHANGES_REQUESTED:
            raise IllegalControllerTransition(
                "length reclassification requires REVIEW_CHANGES_REQUESTED"
            )
        if owner_authorized is not True:
            raise ReviewRejected(
                "length reclassification requires literal owner_authorized=True"
            )
        if actor != packet["actor"]:
            raise ReviewRejected("length reclassification actor must be the packet owner")
        attestation = self._validate_reviewer_attestation(
            packet, reviewer_attestation, actor=actor,
        )
        self._assert_manifest_unchanged(packet)

        if not isinstance(reclassifications, list) or not reclassifications:
            raise ReviewRejected("reclassifications must be a non-empty list")
        by_id = {slot["storyId"]: slot for slot in packet["slots"]}
        planned = []
        seen_ids = set()
        for request in reclassifications:
            if not isinstance(request, dict) or set(request) != {
                "storyId", "fromLengths", "toLengths", "removedBucketFindings", "rationale",
            }:
                raise ReviewRejected(
                    "each reclassification must be exactly {storyId, fromLengths, "
                    "toLengths, removedBucketFindings, rationale}"
                )
            story_id = request["storyId"]
            if story_id not in by_id:
                raise ReviewRejected(f"story {story_id} is not in this packet")
            if story_id in seen_ids:
                raise ReviewRejected(f"story {story_id} named twice")
            seen_ids.add(story_id)
            slot = by_id[story_id]
            self._assert_reclassification_custody(packet, slot)
            old_lengths = request["fromLengths"]
            new_lengths = request["toLengths"]
            if not is_legal_downward_move(old_lengths, new_lengths):
                raise ReviewRejected(
                    f"story {story_id}: {old_lengths} -> {new_lengths} is "
                    "not a downward tail truncation; short is never removable and "
                    "no bucket may be added"
                )
            removed = [band for band in old_lengths if band not in new_lengths]
            resolved = self._validate_removed_bucket_findings(
                slot, removed, request["removedBucketFindings"],
            )
            rationale = request["rationale"]
            if not isinstance(rationale, str) or not rationale.strip():
                raise ReviewRejected(f"story {story_id}: rationale is required")
            planned.append({
                "slot": slot, "storyId": story_id, "removed": removed,
                "fromLengths": list(old_lengths), "toLengths": list(new_lengths),
                "findings": resolved, "rationale": rationale,
            })

        payloads = {}
        for entry in planned:
            slot = entry["slot"]
            materialization = slot["materialization"]
            retained_names = expected_artifact_names(entry["storyId"], entry["toLengths"])
            removed_names = [
                name for name in expected_artifact_names(
                    entry["storyId"], entry["fromLengths"])
                if name not in set(retained_names)
            ]
            payloads[str(entry["storyId"])] = {
                "reclassificationVersion": 2,
                "runId": run_id,
                "packetId": packet_id,
                "reviewRound": packet["reviewRound"],
                "storyId": entry["storyId"],
                "fromLengths": entry["fromLengths"],
                "toLengths": entry["toLengths"],
                "removedLengths": entry["removed"],
                "removedBucketFindings": entry["findings"],
                "removedArtifacts": sorted(removed_names),
                "retainedArtifactCount": len(retained_names),
                "reviewerAttestation": attestation,
                "separationStatus": REVIEWER_SEPARATION_STATUS,
                "workspaceTreeHash": (slot.get("workspace") or {}).get("treeHash"),
                "materializationTreeHash": materialization.get("treeHash"),
                "ownerActor": packet["actor"],
                "rationale": entry["rationale"],
                "adr": "ADR-030",
                "omissionIsNotDeletion": True,
            }
        evidence_key = f"lengthReclassificationReview{packet['reviewRound']}"
        evidence_hash = _hash_value(payloads)

        # Retry.  Matching lengths alone NEVER conclude a no-op: the recomputed
        # payload hash must match, which means byte-identical attestation and
        # byte-identical finding maps too.  This runs BEFORE the fromLengths
        # equality check below, because on a genuine retry the slot already
        # holds the reduced set and that check would reject the no-op.
        recorded = packet["evidenceHashes"].get(evidence_key)
        if recorded is not None:
            if recorded == evidence_hash:
                return packet
            raise ReviewRejected(
                "a length reclassification is already recorded for this review "
                "round and this request diverges from it; nothing was changed"
            )
        if any(entry["slot"]["targetLengths"] == entry["toLengths"]
               for entry in planned):
            raise ReviewRejected(
                "target lengths are already reduced with no recorded "
                "reclassification evidence; owner review is required"
            )

        # Mutation path only: the request must describe the CURRENT state.
        for entry in planned:
            if entry["fromLengths"] != entry["slot"]["targetLengths"]:
                raise ReviewRejected(
                    f"story {entry['storyId']}: fromLengths does not match the "
                    "persisted target length set"
                )

        updated = copy.deepcopy(packet)
        updated_by_id = {slot["storyId"]: slot for slot in updated["slots"]}
        for entry in planned:
            updated_by_id[entry["storyId"]]["targetLengths"] = entry["toLengths"]
        updated["evidenceHashes"][evidence_key] = evidence_hash
        updated["updatedAt"] = self._now()

        # Identity immutability, asserted rather than assumed.
        for before, after in zip(packet["slots"], updated["slots"]):
            for field in ("proposedAnchor", "narrator", "mood", "lanes", "mode",
                          "kidFriendly", "reflectionForm", "storyId", "reservation",
                          "materialization", "unresolvedFindings", "reviewerVerdict"):
                if before.get(field) != after.get(field):
                    raise SafetyViolation(
                        f"story {before['storyId']}: reclassification would change "
                        f"immutable field {field!r}"
                    )

        evidence_dir = (self.packet_dir(run_id, packet_id) / "reclassifications"
                        / f"round-{packet['reviewRound']}")
        self._ensure_runtime_directory(evidence_dir)
        for story_id, payload in payloads.items():
            _write_json(evidence_dir / f"story_{story_id}.json", payload)

        summary = ", ".join(
            f"{entry['storyId']}:{'+'.join(entry['removed'])}" for entry in planned
        )
        return self._record(
            packet, updated, event_type=STORY_LENGTHS_RECLASSIFIED, actor=actor,
            reason=(
                f"owner-authorized ADR-030 length reclassification ({summary}); "
                f"{REVIEWER_SEPARATION_STATUS}"
            ),
        )

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
        self._ensure_runtime_directory(correction_dir)
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
                # The assigned reflection form is immutable through correction:
                # a correction writer must never reconstruct or re-choose it.
                "immutableReflectionForm": slot["reflectionForm"],
                "reflectionContract": describe_contract(slot["reflectionForm"]),
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
        self._ensure_runtime_directory(report_path.parent)
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
    resume = subs.add_parser("resume-planned", parents=[common])
    resume.add_argument("--planning", required=True)
    resume.add_argument(
        "--privatize-runtime",
        action="store_true",
        help="explicitly validate and privatize the exact stranded controller tree before resume",
    )
    subs.add_parser("status", parents=[common])
    renew = subs.add_parser("renew-packet-lease", parents=[common])
    renew.add_argument(
        "--recover-expired",
        action="store_true",
        help="explicitly owner-authorize renewal of matching expired RESERVED claims",
    )
    renew.add_argument(
        "--lease-seconds",
        type=float,
        default=PRODUCTION_LEASE_SECONDS,
        help="new campaign lease extension in seconds (default: 24 hours)",
    )
    subs.add_parser("emit-writer-assignments", parents=[common])
    ingest = subs.add_parser("ingest-writer-output", parents=[common])
    ingest.add_argument("--source-root", required=True)
    subs.add_parser("validate", parents=[common])
    subs.add_parser("materialize", parents=[common])
    subs.add_parser("emit-review-packet", parents=[common])
    review = subs.add_parser("ingest-review", parents=[common])
    review.add_argument("--review-file", required=True)
    reclassify = subs.add_parser("reclassify-lengths", parents=[common])
    reclassify.add_argument("--reclassification-file", required=True)
    reclassify.add_argument("--owner-authorize", action="store_true")
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
        elif args.command == "resume-planned":
            planning = _load_json(Path(args.planning))
            if args.privatize_runtime:
                controller.privatize_planned_runtime(
                    run_id=args.run_id,
                    packet_id=args.packet_id,
                    actor=args.actor,
                    planning=planning,
                )
            controller.resume_planned_packet(
                run_id=args.run_id,
                packet_id=args.packet_id,
                actor=args.actor,
                planning=planning,
            )
            result = controller.preflight_anchors(
                args.run_id, args.packet_id, actor=args.actor,
            )
        elif args.command == "status":
            result = controller.load(args.run_id, args.packet_id)
        elif args.command == "renew-packet-lease":
            result = controller.renew_packet_lease(
                args.run_id,
                args.packet_id,
                actor=args.actor,
                recover_expired=args.recover_expired,
                lease_seconds=args.lease_seconds,
            )
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
        elif args.command == "reclassify-lengths":
            payload = _load_json(Path(args.reclassification_file))
            if not isinstance(payload, dict) or set(payload) != {
                "reclassifications", "reviewerAttestation",
            }:
                raise ReviewRejected(
                    "reclassification file must be exactly "
                    "{reclassifications, reviewerAttestation}"
                )
            result = controller.reclassify_story_lengths(
                args.run_id, args.packet_id, actor=args.actor,
                reclassifications=payload["reclassifications"],
                reviewer_attestation=payload["reviewerAttestation"],
                owner_authorized=args.owner_authorize,
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
    "MAX_CORRECTION_ROUNDS", "PACKET_SIZE", "PLANNED", "PRODUCTION_LEASE_SECONDS",
    "QUARANTINED", "RENEWABLE_PACKET_STATES",
    "READY_FOR_HUMAN_REVIEW", "REVIEW_APPROVED", "REVIEW_CHANGES_REQUESTED",
    "REVIEW_READY", "ReviewRejected", "SafetyViolation", "ValidationFailed",
    "VALIDATION_PASSED", "WorkspaceRejected", "WRITER_OUTPUT_RECEIVED",
    "build_parser", "expected_artifact_names", "main", "replay_packet",
    "validate_packet_model",
]


if __name__ == "__main__":
    raise SystemExit(main())
