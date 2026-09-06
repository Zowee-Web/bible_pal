#!/usr/bin/env python3
"""Global anchor claim ledger (ACL) for concurrent five-story packets.

The controller's story-ID reservations answer "who owns this number".  They do
not answer "who owns this passage", so two packets running at once could each
pass anchor preflight against a queue that only ever described their own five
slots.  This module is the missing authority: one append-only ledger of anchor
claims spanning every run and packet, projected into the overlap gate's queue
vocabulary through a single total function.

Design authority: ``MULTI_PACKET_REMEDIATION_DESIGN_V4.md``.

Two rules govern everything here:

*   **Only an explicit, committed, packet-atomic decision frees an anchor.**
    Expiry is not such a decision.  A lease lapse moves a claim to
    ``RECOVERABLE``, which still occupies.
*   **No crash window may ever produce under-occupancy.**  Over-occupancy -- an
    anchor held longer or more strongly than strictly necessary -- is safe.  A
    transition may be applied per row if and only if every intermediate state
    is occupying; otherwise it must be packet-atomic.
"""

from __future__ import annotations

import dataclasses
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import stat
import threading
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Callable, Iterable, Iterator, Mapping, Sequence


SCHEMA_VERSION = 1
FACTORY_HOME_ENV = "BIBLE_PAL_FACTORY_HOME"

_LEDGER_NAME = "anchor_claims.jsonl"
_LOCKS_NAME = "anchor_locks"

PACKET_SIZE = 5

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

CLAIMED = "CLAIMED"
AUTHORING = "AUTHORING"
MATERIALIZED = "MATERIALIZED"
RETIRED = "RETIRED"
RECOVERABLE = "RECOVERABLE"
RELEASED = "RELEASED"
ABORTED = "ABORTED"

CLAIM_STATES = (
    CLAIMED, AUTHORING, MATERIALIZED, RETIRED, RECOVERABLE, RELEASED, ABORTED,
)

#: States that free the anchor.  Exhaustive, and deliberately tiny.
FREEING_STATES = frozenset({RELEASED, ABORTED})

#: Everything that is not freeing occupies.  Derived, never written twice:
#: V4 section 0 records that a lifecycle table and a projection map written
#: independently is precisely how ``RECOVERABLE`` became a fail-open.
OCCUPYING_STATES = frozenset(set(CLAIM_STATES) - FREEING_STATES)

#: The single source of truth for the projection.  ``None`` means "omit".
#: Entries are exhaustive over ``CLAIM_STATES``; there is no default branch.
_QUEUE_PROJECTION: dict[str, str | None] = {
    CLAIMED: "reserved",
    AUTHORING: "authoring",
    MATERIALIZED: "locked",
    RETIRED: "locked",
    RECOVERABLE: "reserved",
    RELEASED: None,
    ABORTED: None,
}

# Packet-atomic events carry exactly PACKET_SIZE rows; per-row events carry one.
PACKET_ATOMIC_EVENTS = frozenset({
    "PACKET_ANCHORS_CLAIMED",
    "PACKET_ANCHORS_RELEASED",
    "PACKET_ANCHORS_ABORTED",
})
PER_ROW_EVENTS = frozenset({
    "ANCHOR_BOUND",
    "ANCHOR_AUTHORING",
    "ANCHOR_MATERIALIZED",
    "ANCHOR_RETIRED",
    "ANCHOR_RECOVERABLE",
})
EVENT_TYPES = PACKET_ATOMIC_EVENTS | PER_ROW_EVENTS

#: Per-row events may only move occupancy to occupancy.  A per-row transition
#: into a freeing state is unrepresentable by construction and rejected on
#: replay if it somehow exists (V4 section 5.3, defence in depth).
_PER_ROW_TARGET_STATE = {
    "ANCHOR_BOUND": CLAIMED,
    "ANCHOR_AUTHORING": AUTHORING,
    "ANCHOR_MATERIALIZED": MATERIALIZED,
    "ANCHOR_RETIRED": RETIRED,
    "ANCHOR_RECOVERABLE": RECOVERABLE,
}
_PACKET_EVENT_TARGET_STATE = {
    "PACKET_ANCHORS_CLAIMED": CLAIMED,
    "PACKET_ANCHORS_RELEASED": RELEASED,
    "PACKET_ANCHORS_ABORTED": ABORTED,
}

_LEGAL_TRANSITIONS: dict[str, frozenset[str]] = {
    CLAIMED: frozenset({CLAIMED, AUTHORING, MATERIALIZED, RECOVERABLE, RELEASED, ABORTED}),
    AUTHORING: frozenset({AUTHORING, MATERIALIZED, RECOVERABLE, RELEASED, ABORTED}),
    MATERIALIZED: frozenset({MATERIALIZED, RETIRED}),
    RETIRED: frozenset({RETIRED}),
    RECOVERABLE: frozenset({CLAIMED, AUTHORING, RECOVERABLE, RELEASED, ABORTED}),
    RELEASED: frozenset(),
    ABORTED: frozenset(),
}

_ANCHOR_KEY_RE = re.compile(r"^[0-9a-f]{64}$")
_SAFE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


# ---------------------------------------------------------------------------
# Typed failures
# ---------------------------------------------------------------------------

class AnchorClaimError(Exception):
    """Base class for typed anchor-claim failures."""


class AnchorLedgerCorrupt(AnchorClaimError):
    """The append-only claim history cannot be trusted.  Halt, mutate nothing."""


class AnchorConflict(AnchorClaimError):
    """Another legitimate owner holds this anchor."""


class AnchorClaimRecoveryRequired(AnchorClaimError):
    """A self-owned lock exists with no committed event; owner must adjudicate."""


class AnchorOverlapRejected(AnchorClaimError):
    """A proposed anchor collides with the global occupying set."""


class LockOrderViolation(AnchorClaimError):
    """A lock was requested below the rank of a lock already held."""


class OwnerAuthorizationRequired(AnchorClaimError):
    """A freeing transition was attempted without owner authorization."""


# ---------------------------------------------------------------------------
# Lock ranks (L1-L6) with real enforcement, not just observation
# ---------------------------------------------------------------------------

L1_ACL_LEDGER = 1
L2_ANCHOR_LOCK = 2
L3_RESERVATION_LEDGER = 3
L4_STORY_LOCK = 4
L5_PACKET_JOURNAL = 5
L6_MATERIALIZATION = 6

LOCK_RANK_NAMES = {
    L1_ACL_LEDGER: "L1_ACL_LEDGER",
    L2_ANCHOR_LOCK: "L2_ANCHOR_LOCK",
    L3_RESERVATION_LEDGER: "L3_RESERVATION_LEDGER",
    L4_STORY_LOCK: "L4_STORY_LOCK",
    L5_PACKET_JOURNAL: "L5_PACKET_JOURNAL",
    L6_MATERIALIZATION: "L6_MATERIALIZATION",
}

_local = threading.local()
_observer_lock = threading.Lock()
_observers: list[Callable[[Mapping[str, object]], None]] = []


def add_lock_observer(callback: Callable[[Mapping[str, object]], None]) -> None:
    """Register a test hook receiving every lock acquire/release record."""
    with _observer_lock:
        _observers.append(callback)


def remove_lock_observer(callback: Callable[[Mapping[str, object]], None]) -> None:
    with _observer_lock:
        if callback in _observers:
            _observers.remove(callback)


def _emit(record: Mapping[str, object]) -> None:
    with _observer_lock:
        listeners = tuple(_observers)
    for callback in listeners:
        callback(dict(record))


def _held() -> list[tuple[int, str]]:
    stack = getattr(_local, "held", None)
    if stack is None:
        stack = []
        _local.held = stack
    return stack


@contextmanager
def lock_rank(rank: int, detail: str = "") -> Iterator[None]:
    """Enforce non-descending lock acquisition across L1-L6.

    Equal ranks are legal -- a packet holds five L2 locks at once.  Acquiring a
    strictly lower rank while holding a higher one is the cycle precondition and
    raises rather than deadlocking later under load.
    """
    stack = _held()
    if stack:
        highest = max(item[0] for item in stack)
        if rank < highest:
            raise LockOrderViolation(
                f"cannot acquire {LOCK_RANK_NAMES.get(rank, rank)} while holding "
                f"{LOCK_RANK_NAMES.get(highest, highest)}"
            )
    stack.append((rank, detail))
    _emit({"action": "acquire", "rank": rank,
           "name": LOCK_RANK_NAMES.get(rank, str(rank)), "detail": detail,
           "thread": threading.get_ident(),
           "held": [item[0] for item in stack]})
    try:
        yield
    finally:
        for index in range(len(stack) - 1, -1, -1):
            if stack[index] == (rank, detail):
                stack.pop(index)
                break
        _emit({"action": "release", "rank": rank,
               "name": LOCK_RANK_NAMES.get(rank, str(rank)), "detail": detail,
               "thread": threading.get_ident(),
               "held": [item[0] for item in stack]})


def held_lock_ranks() -> tuple[int, ...]:
    return tuple(item[0] for item in _held())


# ---------------------------------------------------------------------------
# Small helpers (mirroring story_id_reservations house style)
# ---------------------------------------------------------------------------

def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
    ).encode("utf-8")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hash_value(value: object) -> str:
    return _sha256(_canonical_bytes(value))


def _utc_now(now: dt.datetime | None = None) -> dt.datetime:
    value = now or dt.datetime.now(dt.timezone.utc)
    if value.tzinfo is None:
        raise AnchorClaimError("anchor claim timestamps must be timezone-aware")
    return value.astimezone(dt.timezone.utc)


def _timestamp(value: dt.datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _require_text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise AnchorClaimError(f"{field} must be a non-empty string")
    return value.strip()


def _require_safe_id(value: object, field: str) -> str:
    text = _require_text(value, field)
    if not _SAFE_ID_RE.match(text):
        raise AnchorClaimError(f"{field} is not a safe identifier: {text!r}")
    return text


def _require_slot(value: object) -> int:
    if type(value) is not int or not 1 <= value <= PACKET_SIZE:
        raise AnchorClaimError(f"slotId must be an int in 1..{PACKET_SIZE}")
    return value


def _write_all(fd: int, data: bytes) -> None:
    offset = 0
    while offset < len(data):
        written = os.write(fd, data[offset:])
        if written <= 0:
            raise OSError("short write while persisting anchor claim evidence")
        offset += written


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    fd = os.open(path, flags)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def resolve_factory_home(factory_home: os.PathLike[str] | str | None) -> Path:
    if factory_home is not None:
        return Path(factory_home).expanduser().resolve()
    env = os.environ.get(FACTORY_HOME_ENV)
    if env:
        return Path(env).expanduser().resolve()
    raise AnchorClaimError(
        f"factory home is required; pass factory_home or set {FACTORY_HOME_ENV}"
    )


def ledger_path(factory_home: os.PathLike[str] | str | None) -> Path:
    return resolve_factory_home(factory_home) / _LEDGER_NAME


def locks_dir(factory_home: os.PathLike[str] | str | None) -> Path:
    return resolve_factory_home(factory_home) / _LOCKS_NAME


def _ensure_private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise AnchorClaimError(f"factory path is not an ordinary directory: {path}")


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

def anchor_key(normalized_anchor: str) -> str:
    """Filesystem-safe, canonically orderable key for one normalized anchor."""
    return _sha256(_require_text(normalized_anchor, "normalizedAnchor").encode("utf-8"))


def comparison_id(run_id: str, packet_id: str, slot_id: int) -> int:
    """Deterministic negative placeholder ID used before a story ID exists.

    Negative by construction so it can never be mistaken for a real story ID
    (the campaign namespace is 3000-3258, and all real IDs are positive).
    Uniqueness across the live queue is *asserted*, never assumed: see
    ``build_overlap_queue``.
    """
    digest = _sha256(_canonical_bytes([
        _require_safe_id(run_id, "runId"),
        _require_safe_id(packet_id, "packetId"),
        _require_slot(slot_id),
    ]))
    return -(1 + int(digest[:12], 16))


def pending_event_id(run_id: str, packet_id: str, claim_hash: str,
                     event_type: str = "PACKET_ANCHORS_CLAIMED") -> str:
    """Deterministic transaction ID for a packet claim.

    This MUST be a pure function of the transaction, not a fresh UUID.  It is
    one of the seven identity fields written into every L2 lock, so a random
    value would make an honest retry look divergent: the crashed attempt's
    locks would carry one ID and the retry would compute another, and the
    ``AnchorClaimRecoveryRequired`` branch could never be reached -- every
    orphan would be misreported as ledger corruption.  Determinism is what
    makes "same transaction, tried twice" recognisable as such.
    """
    digest = _sha256(_canonical_bytes([
        _require_safe_id(run_id, "runId"),
        _require_safe_id(packet_id, "packetId"),
        _require_text(claim_hash, "packetClaimHash"),
        _require_text(event_type, "eventType"),
    ]))
    return str(uuid.UUID(hex=digest[:32]))


def packet_claim_hash(run_id: str, packet_id: str,
                      rows: Sequence[Mapping[str, object]]) -> str:
    """All-five transaction identity: order-independent, content-exact."""
    ordered = sorted(
        (
            {
                "slotId": _require_slot(row["slotId"]),
                "normalizedAnchor": _require_text(row["normalizedAnchor"], "normalizedAnchor"),
                "anchorKey": _require_text(row["anchorKey"], "anchorKey"),
            }
            for row in rows
        ),
        key=lambda item: item["slotId"],
    )
    if len(ordered) != PACKET_SIZE:
        raise AnchorClaimError(f"a packet claim carries exactly {PACKET_SIZE} rows")
    if {item["slotId"] for item in ordered} != set(range(1, PACKET_SIZE + 1)):
        raise AnchorClaimError("packet claim slots must be exactly 1..5")
    return _hash_value({
        "runId": _require_safe_id(run_id, "runId"),
        "packetId": _require_safe_id(packet_id, "packetId"),
        "rows": ordered,
    })


# ---------------------------------------------------------------------------
# Claim record
# ---------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class AnchorClaim:
    """Authoritative claim state reconstructed from the ledger."""

    run_id: str
    packet_id: str
    slot_id: int
    normalized_anchor: str
    anchor_key: str
    comparison_id: int
    state: str
    packet_claim_hash: str
    event_id: str
    story_id: int | None = None

    @property
    def key(self) -> tuple[str, str, int]:
        return (self.run_id, self.packet_id, self.slot_id)

    @property
    def identity(self) -> int:
        """The identity the gate sees: a real story ID once bound, else the
        negative comparison ID.  Exactly one is active at any time."""
        return self.story_id if self.story_id is not None else self.comparison_id

    @property
    def occupying(self) -> bool:
        return self.state in OCCUPYING_STATES


# ---------------------------------------------------------------------------
# The single total projection
# ---------------------------------------------------------------------------

def claim_to_overlap_queue_row(claim: AnchorClaim) -> dict | None:
    """Project one claim into the overlap gate's queue vocabulary.

    Returns None **only** for states that are free by an explicit, committed,
    packet-atomic decision.  Expiry is not such a decision.

    This is the single translation point between the ACL lifecycle and the
    gate.  No caller may build a queue row by hand, and there is no default
    branch: an unrecognised state raises rather than vanishing from the queue,
    because a silently dropped row is an invisible occupancy.
    """
    state = getattr(claim, "state", None)
    if state not in _QUEUE_PROJECTION:
        raise AnchorLedgerCorrupt(
            f"unmapped anchor claim lifecycle state {state!r} for "
            f"{getattr(claim, 'run_id', '?')}/{getattr(claim, 'packet_id', '?')}"
            f"#{getattr(claim, 'slot_id', '?')}"
        )
    projected = _QUEUE_PROJECTION[state]
    if projected is None:
        return None
    return {
        "storyId": claim.identity,
        "proposedAnchor": claim.normalized_anchor,
        "state": projected,
    }


def build_overlap_queue(
    claims: Iterable[AnchorClaim],
    *,
    exclude_packet: tuple[str, str] | None = None,
) -> list[dict]:
    """Project every claim into gate queue rows.

    ``exclude_packet`` omits one packet's own rows.  It exists for release and
    abort reconciliation, never for the initial claim: at initial claim the
    packet has no committed rows, so nothing needs excluding, and an idempotent
    retry returns before the evaluator is reached (V3 section 6).
    """
    rows: list[dict] = []
    seen: dict[int, tuple[str, str, int]] = {}
    for claim in claims:
        if exclude_packet is not None and (claim.run_id, claim.packet_id) == exclude_packet:
            continue
        row = claim_to_overlap_queue_row(claim)
        if row is None:
            continue
        identity = row["storyId"]
        if identity in seen and seen[identity] != claim.key:
            raise AnchorLedgerCorrupt(
                f"queue identity {identity} is claimed by both {seen[identity]} "
                f"and {claim.key}"
            )
        seen[identity] = claim.key
        rows.append(row)
    rows.sort(key=lambda item: (item["state"], item["storyId"]))
    return rows


# ---------------------------------------------------------------------------
# Ledger replay
# ---------------------------------------------------------------------------

def _validate_event(event: object, line_number: int) -> dict:
    if not isinstance(event, dict):
        raise AnchorLedgerCorrupt(f"line {line_number}: event must be an object")
    event_type = event.get("eventType")
    if event_type not in EVENT_TYPES:
        raise AnchorLedgerCorrupt(
            f"line {line_number}: unknown eventType {event_type!r}"
        )
    for field in ("schemaVersion", "eventId", "timestamp", "runId", "packetId",
                  "actor", "rows"):
        if field not in event:
            raise AnchorLedgerCorrupt(f"line {line_number}: missing {field}")
    if event["schemaVersion"] != SCHEMA_VERSION:
        raise AnchorLedgerCorrupt(
            f"line {line_number}: unsupported schemaVersion {event['schemaVersion']!r}"
        )
    rows = event["rows"]
    if not isinstance(rows, list) or not rows:
        raise AnchorLedgerCorrupt(f"line {line_number}: rows must be a non-empty list")
    expected = PACKET_SIZE if event_type in PACKET_ATOMIC_EVENTS else 1
    if len(rows) != expected:
        raise AnchorLedgerCorrupt(
            f"line {line_number}: {event_type} carries {len(rows)} rows, "
            f"expected exactly {expected}"
        )
    slots = []
    for row in rows:
        if not isinstance(row, dict):
            raise AnchorLedgerCorrupt(f"line {line_number}: row must be an object")
        for field in ("slotId", "normalizedAnchor", "anchorKey", "comparisonId"):
            if field not in row:
                raise AnchorLedgerCorrupt(f"line {line_number}: row missing {field}")
        slots.append(_require_slot(row["slotId"]))
        if not _ANCHOR_KEY_RE.match(str(row["anchorKey"])):
            raise AnchorLedgerCorrupt(f"line {line_number}: malformed anchorKey")
        if not isinstance(row["comparisonId"], int) or row["comparisonId"] >= 0:
            raise AnchorLedgerCorrupt(
                f"line {line_number}: comparisonId must be a negative int"
            )
        story_id = row.get("storyId")
        if story_id is not None and (type(story_id) is not int or story_id <= 0):
            raise AnchorLedgerCorrupt(f"line {line_number}: storyId must be a positive int")
    if event_type in PACKET_ATOMIC_EVENTS and set(slots) != set(range(1, PACKET_SIZE + 1)):
        raise AnchorLedgerCorrupt(
            f"line {line_number}: {event_type} must name slots 1..{PACKET_SIZE}"
        )
    if len(set(slots)) != len(slots):
        raise AnchorLedgerCorrupt(f"line {line_number}: duplicate slotId in one event")
    return event


def _apply_event(states: dict[tuple[str, str, int], AnchorClaim],
                 event: Mapping[str, object], line_number: int) -> None:
    event_type = str(event["eventType"])
    run_id = str(event["runId"])
    packet_id = str(event["packetId"])
    if event_type in PACKET_ATOMIC_EVENTS:
        target = _PACKET_EVENT_TARGET_STATE[event_type]
    else:
        target = _PER_ROW_TARGET_STATE[event_type]

    # Defence in depth (V4 section 5.3): a per-row event may never reach a
    # freeing state.  The event vocabulary makes this unrepresentable, so if it
    # is ever seen the ledger is corrupt and the row stays occupying.
    if event_type in PER_ROW_EVENTS and target in FREEING_STATES:
        raise AnchorLedgerCorrupt(
            f"line {line_number}: per-row {event_type} would free an anchor; "
            "only packet-atomic release or abort may free"
        )

    for row in event["rows"]:
        slot_id = int(row["slotId"])
        key = (run_id, packet_id, slot_id)
        current = states.get(key)
        if event_type == "PACKET_ANCHORS_CLAIMED":
            if current is not None and current.state not in (CLAIMED, RECOVERABLE):
                raise AnchorLedgerCorrupt(
                    f"line {line_number}: re-claim of {key} in state {current.state}"
                )
        elif current is None:
            raise AnchorLedgerCorrupt(
                f"line {line_number}: {event_type} for unknown claim {key}"
            )
        if current is not None and target not in _LEGAL_TRANSITIONS[current.state]:
            raise AnchorLedgerCorrupt(
                f"line {line_number}: illegal transition "
                f"{current.state} -> {target} for {key}"
            )
        story_id = row.get("storyId")
        if story_id is None and current is not None:
            story_id = current.story_id
        if (current is not None and current.story_id is not None
                and story_id != current.story_id):
            raise AnchorLedgerCorrupt(
                f"line {line_number}: {key} would be rebound from "
                f"{current.story_id} to {story_id}"
            )
        states[key] = AnchorClaim(
            run_id=run_id,
            packet_id=packet_id,
            slot_id=slot_id,
            normalized_anchor=str(row["normalizedAnchor"]),
            anchor_key=str(row["anchorKey"]),
            comparison_id=int(row["comparisonId"]),
            state=target,
            packet_claim_hash=str(event.get("packetClaimHash") or
                                  (current.packet_claim_hash if current else "")),
            event_id=str(event["eventId"]),
            story_id=story_id,
        )


def _replay_bytes(raw: bytes, source: str) -> dict[tuple[str, str, int], AnchorClaim]:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AnchorLedgerCorrupt(f"{source} is not valid UTF-8: {exc}") from exc
    if text and not text.endswith("\n"):
        raise AnchorLedgerCorrupt(f"{source} ends with a torn line")
    states: dict[tuple[str, str, int], AnchorClaim] = {}
    seen_event_ids: set[str] = set()
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            raise AnchorLedgerCorrupt(f"{source} line {number} is blank")
        try:
            decoded = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AnchorLedgerCorrupt(f"{source} line {number}: {exc}") from exc
        event = _validate_event(decoded, number)
        event_id = str(event["eventId"])
        if event_id in seen_event_ids:
            raise AnchorLedgerCorrupt(f"{source} line {number}: duplicate eventId")
        seen_event_ids.add(event_id)
        _apply_event(states, event, number)

    # A packet whose rows are freed must be freed wholly.  The packet-atomic
    # event vocabulary guarantees this; the check restates it independently so
    # a hand-edited or partially merged ledger fails closed rather than opening
    # a hole (V4 section 5.3, secondary rule).
    by_packet: dict[tuple[str, str], list[AnchorClaim]] = {}
    for claim in states.values():
        by_packet.setdefault((claim.run_id, claim.packet_id), []).append(claim)
    for packet, claims in by_packet.items():
        freed = [c for c in claims if c.state in FREEING_STATES]
        if freed and len(freed) != len(claims):
            raise AnchorLedgerCorrupt(
                f"packet {packet[0]}/{packet[1]} is partially freed: "
                f"{len(freed)} of {len(claims)} rows; a per-row free is not "
                "a valid free and the remaining rows are treated as occupying"
            )
    return states


def replay_ledger(
    factory_home: os.PathLike[str] | str | None = None,
) -> dict[tuple[str, str, int], AnchorClaim]:
    """Reconstruct authoritative claim state under a shared L1 lock."""
    path = ledger_path(factory_home)
    if not path.exists():
        return {}
    with lock_rank(L1_ACL_LEDGER, "replay"):
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(path, flags)
        try:
            fcntl.flock(fd, fcntl.LOCK_SH)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode):
                raise AnchorLedgerCorrupt(f"ACL is not a regular file: {path}")
            chunks = []
            while True:
                chunk = os.read(fd, 1 << 20)
                if not chunk:
                    break
                chunks.append(chunk)
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)
    return _replay_bytes(b"".join(chunks), str(path))


def _replay_locked(path: Path) -> dict[tuple[str, str, int], AnchorClaim]:
    """Replay while L1 is already held by the caller."""
    if not path.exists():
        return {}
    raw = path.read_bytes()
    return _replay_bytes(raw, str(path))


# ---------------------------------------------------------------------------
# L1 / L2 primitives
# ---------------------------------------------------------------------------

@contextmanager
def _acl_ledger_lock(home: Path) -> Iterator[Path]:
    """L1: the single global mutex for every claim mutation."""
    _ensure_private_directory(home)
    path = home / _LEDGER_NAME
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        with lock_rank(L1_ACL_LEDGER, str(path)):
            fcntl.flock(fd, fcntl.LOCK_EX)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode):
                raise AnchorLedgerCorrupt(f"ACL is not a regular file: {path}")
            try:
                yield path
            finally:
                fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def _append_locked(path: Path, event: Mapping[str, object]) -> None:
    """Append one event and fsync it.  The caller already holds L1."""
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        encoded = (
            json.dumps(dict(event), sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False) + "\n"
        ).encode("utf-8")
        _write_all(fd, encoded)
        os.fsync(fd)
    finally:
        os.close(fd)
    _fsync_directory(path.parent)


def _lock_record(*, run_id: str, packet_id: str, slot_id: int,
                 normalized_anchor: str, key: str, claim_hash: str,
                 pending_event_id_value: str, actor: str, created_at: str) -> dict:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "runId": run_id,
        "packetId": packet_id,
        "slotId": slot_id,
        "normalizedAnchor": normalized_anchor,
        "anchorKey": key,
        "packetClaimHash": claim_hash,
        "pendingEventId": pending_event_id_value,
        "actor": actor,
        "createdAt": created_at,
    }


#: The seven fields that constitute self-owned lock identity (V3 section 4).
_IDENTITY_FIELDS = (
    "runId", "packetId", "slotId", "normalizedAnchor", "anchorKey",
    "packetClaimHash", "pendingEventId",
)


def _read_lock_fd(fd: int, path: Path) -> dict:
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise AnchorLedgerCorrupt(f"anchor lock is not a regular file: {path}")
        os.lseek(fd, 0, os.SEEK_SET)
        raw = b""
        while True:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            raw += chunk
    except OSError as exc:
        raise AnchorLedgerCorrupt(f"cannot read anchor lock {path}: {exc}") from exc
    try:
        record = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AnchorLedgerCorrupt(f"anchor lock {path} is unreadable: {exc}") from exc
    if not isinstance(record, dict):
        raise AnchorLedgerCorrupt(f"anchor lock {path} is not an object")
    return record


def _read_lock(path: Path) -> dict:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise AnchorLedgerCorrupt(f"cannot read anchor lock {path}: {exc}") from exc
    try:
        return _read_lock_fd(fd, path)
    finally:
        os.close(fd)


def _classify_existing_lock(record: Mapping[str, object], desired: Mapping[str, object],
                            *, committed: bool, path: Path) -> str:
    """Return one of: adopt | recovery | conflict | corrupt.

    A same-owner record whose transaction content diverges is **corrupt**, not
    merely conflicting: ``(runId, packetId)`` is a unique packet identity and
    every lock for that pair is written once, under L1, from one in-memory
    transaction.  No correct execution can produce it (V4 section 3).
    """
    same_owner = (
        record.get("runId") == desired["runId"]
        and record.get("packetId") == desired["packetId"]
    )
    if not same_owner:
        return "conflict"
    divergent = [f for f in _IDENTITY_FIELDS if record.get(f) != desired[f]]
    if divergent:
        return "corrupt"
    return "adopt" if committed else "recovery"


# ---------------------------------------------------------------------------
# Claim transaction
# ---------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class ClaimResult:
    """Outcome of a packet claim transaction."""

    claims: tuple[AnchorClaim, ...]
    event_id: str
    packet_claim_hash: str
    idempotent: bool


def claim_packet_anchors(
    *,
    run_id: str,
    packet_id: str,
    proposals: Sequence[Mapping[str, object]],
    actor: str,
    factory_home: os.PathLike[str] | str | None = None,
    overlap_evaluator: Callable[..., Mapping[str, object]] | None = None,
    verse_set_fn: Callable[[str], frozenset] | None = None,
    normalize_fn: Callable[[str], str] | None = None,
    now: dt.datetime | None = None,
) -> ClaimResult:
    """Claim all five anchors for one packet, atomically.

    ``proposals`` is a sequence of ``{"slotId": int, "anchor": str}``.  The
    whole packet is claimed or nothing is: the five rows are committed by one
    fsynced append under L1, so no replay can observe a partial claim.
    """
    home = resolve_factory_home(factory_home)
    actor = _require_text(actor, "actor")
    run_id = _require_safe_id(run_id, "runId")
    packet_id = _require_safe_id(packet_id, "packetId")
    if len(proposals) != PACKET_SIZE:
        raise AnchorClaimError(f"a packet claims exactly {PACKET_SIZE} anchors")

    normalize = normalize_fn or _default_normalize
    rows = []
    for proposal in proposals:
        slot_id = _require_slot(proposal["slotId"])
        normalized = normalize(_require_text(proposal["anchor"], "anchor"))
        rows.append({
            "slotId": slot_id,
            "normalizedAnchor": normalized,
            "anchorKey": anchor_key(normalized),
            "comparisonId": comparison_id(run_id, packet_id, slot_id),
            "storyId": None,
        })
    rows.sort(key=lambda row: row["slotId"])
    claim_hash = packet_claim_hash(run_id, packet_id, rows)

    with _acl_ledger_lock(home) as path:
        states = _replay_locked(path)

        # Idempotent retry returns BEFORE the evaluator runs.  A packet must
        # never be compared against its own committed rows (V3 section 6).
        existing = [c for c in states.values()
                    if (c.run_id, c.packet_id) == (run_id, packet_id)]
        if existing:
            if len(existing) != PACKET_SIZE:
                raise AnchorLedgerCorrupt(
                    f"{run_id}/{packet_id} has {len(existing)} claims, expected {PACKET_SIZE}"
                )
            divergent = [c for c in existing if c.packet_claim_hash != claim_hash]
            if divergent:
                raise AnchorConflict(
                    f"{run_id}/{packet_id} already claimed a different anchor set"
                )
            ordered = tuple(sorted(existing, key=lambda c: c.slot_id))
            # A matching ledger is not sufficient.  Reconcile all five exact
            # anchor locks against this same transaction before handing back
            # idempotent success; four matching locks never adopt a packet.
            reconcile_committed_locks(
                ordered, run_id=run_id, packet_id=packet_id,
                claim_hash=claim_hash, lock_dir=home / _LOCKS_NAME,
            )
            return ClaimResult(claims=ordered, event_id=ordered[0].event_id,
                               packet_claim_hash=claim_hash, idempotent=True)

        # 1. every proposal against the global occupying set
        queue = build_overlap_queue(states.values())
        if overlap_evaluator is not None:
            _assert_no_global_overlap(rows, queue, overlap_evaluator, home)

        # 2. every proposal against every other proposal in this packet
        _assert_no_internal_overlap(rows, verse_set_fn)

        pending_event_id_value = pending_event_id(run_id, packet_id, claim_hash)
        created_at = _timestamp(_utc_now(now))
        lock_dir = home / _LOCKS_NAME
        _ensure_private_directory(lock_dir)

        created: list[Path] = []
        canonical = sorted(rows, key=lambda row: row["anchorKey"])
        try:
            for row in canonical:
                desired = _lock_record(
                    run_id=run_id, packet_id=packet_id, slot_id=row["slotId"],
                    normalized_anchor=row["normalizedAnchor"], key=row["anchorKey"],
                    claim_hash=claim_hash,
                    pending_event_id_value=pending_event_id_value,
                    actor=actor, created_at=created_at,
                )
                lock_path = lock_dir / f"{row['anchorKey']}.lock"
                with lock_rank(L2_ANCHOR_LOCK, row["anchorKey"]):
                    fd = _atomic_lock(lock_path, desired)
                    if fd is None:
                        _handle_existing_lock(lock_path, desired, states)
                        raise AnchorConflict(
                            f"anchor {row['normalizedAnchor']} is already locked"
                        )
                    os.close(fd)
                    created.append(lock_path)

            event = {
                "schemaVersion": SCHEMA_VERSION,
                "eventId": pending_event_id_value,
                "timestamp": created_at,
                "eventType": "PACKET_ANCHORS_CLAIMED",
                "runId": run_id,
                "packetId": packet_id,
                "actor": actor,
                "packetClaimHash": claim_hash,
                "reason": "packet-atomic anchor claim",
                "rows": rows,
            }
            _append_locked(path, event)  # COMMIT
        except Exception:
            _rollback_locks(created)
            raise

        claims = tuple(
            AnchorClaim(
                run_id=run_id, packet_id=packet_id, slot_id=row["slotId"],
                normalized_anchor=row["normalizedAnchor"], anchor_key=row["anchorKey"],
                comparison_id=row["comparisonId"], state=CLAIMED,
                packet_claim_hash=claim_hash, event_id=pending_event_id_value,
                story_id=None,
            )
            for row in rows
        )
        return ClaimResult(claims=claims, event_id=pending_event_id_value,
                           packet_claim_hash=claim_hash, idempotent=False)


def _default_normalize(anchor: str) -> str:
    return " ".join(anchor.split())


def _atomic_lock(lock_path: Path, record: Mapping[str, object]) -> int | None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags, 0o600)
    except FileExistsError:
        return None
    except OSError as exc:
        raise AnchorConflict(f"cannot atomically lock {lock_path}: {exc}") from exc
    try:
        payload = json.dumps(dict(record), sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False).encode("utf-8")
        _write_all(fd, payload)
        os.fsync(fd)
        _fsync_directory(lock_path.parent)
        return fd
    except Exception:
        os.close(fd)
        raise


def _handle_existing_lock(lock_path: Path, desired: Mapping[str, object],
                          states: Mapping[tuple[str, str, int], AnchorClaim]) -> None:
    """Raise the correct typed error for an EEXIST.  Never deletes, never steals."""
    record = _read_lock(lock_path)
    key = (str(desired["runId"]), str(desired["packetId"]), int(desired["slotId"]))
    committed = key in states
    verdict = _classify_existing_lock(record, desired, committed=committed,
                                      path=lock_path)
    if verdict == "corrupt":
        raise AnchorLedgerCorrupt(
            f"anchor lock {lock_path} bears our packet identity but divergent "
            "transaction content; no correct execution can produce this. "
            "Halting without mutation for owner inspection."
        )
    if verdict == "recovery":
        raise AnchorClaimRecoveryRequired(
            f"anchor lock {lock_path} is ours with no committed claim event; "
            "owner-authorized reclaim-orphan-locks is required. Nothing was "
            "deleted or adopted."
        )
    if verdict == "adopt":
        return
    raise AnchorConflict(f"anchor lock {lock_path} is held by another packet")


def reconcile_committed_locks(
    claims: Sequence[AnchorClaim],
    *,
    run_id: str,
    packet_id: str,
    claim_hash: str,
    lock_dir: Path,
) -> None:
    """Verify every exact-anchor lock backing an already-committed packet claim.

    A committed ACL transaction proves the *claim* exists.  It does not prove
    the advisory exclusivity locks that make the claim enforceable are still in
    place, and those are separate files that can be deleted, replaced or
    corrupted out of band.  Returning idempotent success on the ledger alone
    would hand back a claim whose exclusivity nobody has checked -- which is
    how a retry could quietly adopt a packet whose locks a sibling now holds.

    All five must reconcile to the SAME committed transaction.  Four matching
    locks are never sufficient, so every row is inspected before anything is
    raised and the findings are then reported in a fixed severity order:

    1. ``AnchorLedgerCorrupt`` -- a lock bears our packet identity with
       divergent content.  No correct execution produces it, so the store
       cannot be trusted and nothing else matters.
    2. ``AnchorConflict`` -- a lock is held by a foreign owner.  A real
       ownership dispute outranks our own bookkeeping being incomplete.
    3. ``AnchorClaimRecoveryRequired`` -- a lock we should hold is absent.

    This function only ever reads.  It never creates, rewrites or deletes a
    lock file, and it never appends to the ledger.
    """
    missing: list[str] = []
    foreign: list[str] = []
    corrupt: list[str] = []
    expected_pending = pending_event_id(run_id, packet_id, claim_hash)
    for claim in sorted(claims, key=lambda item: item.anchor_key):
        desired = {
            "runId": run_id,
            "packetId": packet_id,
            "slotId": claim.slot_id,
            "normalizedAnchor": claim.normalized_anchor,
            "anchorKey": claim.anchor_key,
            "packetClaimHash": claim_hash,
            "pendingEventId": expected_pending,
        }
        lock_path = lock_dir / f"{claim.anchor_key}.lock"
        if not lock_path.exists():
            missing.append(f"slot {claim.slot_id} ({claim.normalized_anchor})")
            continue
        record = _read_lock(lock_path)
        verdict = _classify_existing_lock(record, desired, committed=True,
                                          path=lock_path)
        if verdict == "corrupt":
            corrupt.append(f"slot {claim.slot_id} ({lock_path.name})")
        elif verdict == "conflict":
            foreign.append(f"slot {claim.slot_id} ({lock_path.name})")

    if corrupt:
        raise AnchorLedgerCorrupt(
            f"{run_id}/{packet_id}: anchor lock(s) bear our packet identity with "
            f"divergent transaction content: {', '.join(corrupt)}. No correct "
            "execution can produce this. Halting without mutation."
        )
    if foreign:
        raise AnchorConflict(
            f"{run_id}/{packet_id}: anchor lock(s) are held by another packet: "
            f"{', '.join(foreign)}. The committed claim cannot be adopted."
        )
    if missing:
        # The ledger transaction is internally valid -- five rows, one matching
        # packetClaimHash -- but its exclusivity-lock set is incomplete.  That
        # is neither corruption (the ledger is coherent) nor a conflict (no
        # foreign owner holds it), so it is the owner-adjudicated case.  The
        # lock is deliberately NOT recreated: re-asserting exclusivity we
        # cannot prove was continuously held would paper over an out-of-band
        # deletion or a half-finished release, and both need a human.
        raise AnchorClaimRecoveryRequired(
            f"{run_id}/{packet_id}: committed claim is missing {len(missing)} of "
            f"{PACKET_SIZE} anchor lock(s): {', '.join(missing)}. The ledger "
            "transaction is valid but its exclusivity locks are incomplete; "
            "owner-authorized recovery is required. Nothing was recreated."
        )


def _remove_terminal_lock_if_owned(
    lock_path: Path,
    *,
    claim: AnchorClaim,
    run_id: str,
    packet_id: str,
    claim_hash: str,
) -> bool:
    """Remove one exact post-commit freeing orphan, never a successor's lock."""

    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags)
    except FileNotFoundError:
        return False
    except OSError as exc:
        raise AnchorLedgerCorrupt(f"cannot inspect terminal anchor lock {lock_path}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        opened = os.fstat(fd)
        record = _read_lock_fd(fd, lock_path)
        desired = {
            "runId": run_id,
            "packetId": packet_id,
            "slotId": claim.slot_id,
            "normalizedAnchor": claim.normalized_anchor,
            "anchorKey": claim.anchor_key,
            "packetClaimHash": claim_hash,
            "pendingEventId": pending_event_id(run_id, packet_id, claim_hash),
        }
        verdict = _classify_existing_lock(
            record,
            desired,
            committed=True,
            path=lock_path,
        )
        if verdict == "conflict":
            # The old terminal claim no longer owns this exact-key lock.  A
            # later packet may have reused the anchor; never touch its lock.
            return False
        if verdict == "corrupt":
            raise AnchorLedgerCorrupt(
                f"terminal anchor lock {lock_path} bears {run_id}/{packet_id} "
                "ownership but divergent transaction identity"
            )
        try:
            current = os.stat(lock_path, follow_symlinks=False)
        except FileNotFoundError:
            return False
        except OSError as exc:
            raise AnchorLedgerCorrupt(
                f"terminal anchor lock changed while inspected: {lock_path}: {exc}"
            ) from exc
        if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            raise AnchorLedgerCorrupt(
                f"refusing to unlink replaced terminal anchor lock: {lock_path}"
            )
        os.unlink(lock_path)
        return True
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _reconcile_terminal_packet_locks(
    claims: Sequence[AnchorClaim],
    *,
    run_id: str,
    packet_id: str,
    claim_hash: str,
    lock_dir: Path,
) -> None:
    removed = False
    for claim in sorted(claims, key=lambda item: item.anchor_key):
        lock_path = lock_dir / f"{claim.anchor_key}.lock"
        with lock_rank(L2_ANCHOR_LOCK, claim.anchor_key):
            removed = _remove_terminal_lock_if_owned(
                lock_path,
                claim=claim,
                run_id=run_id,
                packet_id=packet_id,
                claim_hash=claim_hash,
            ) or removed
    if removed:
        _fsync_directory(lock_dir)


def _rollback_locks(created: Sequence[Path]) -> None:
    """Unlink only the locks this transaction created, in reverse canonical order."""
    for lock_path in reversed(list(created)):
        try:
            os.unlink(lock_path)
        except FileNotFoundError:
            continue
    if created:
        _fsync_directory(Path(created[0]).parent)


def _assert_no_global_overlap(rows, queue, overlap_evaluator, home: Path) -> None:
    import tempfile
    with tempfile.TemporaryDirectory(dir=str(home)) as tmp:
        queue_path = Path(tmp) / "acl_overlap_queue.json"
        queue_path.write_text(
            json.dumps({"reservations": queue}, sort_keys=True), encoding="utf-8"
        )
        for row in rows:
            result = overlap_evaluator(
                row["normalizedAnchor"],
                story_id=row["comparisonId"],
                reservations_path=str(queue_path),
            )
            verdict = result.get("verdict")
            if verdict != "PASS":
                raise AnchorOverlapRejected(
                    f"slot {row['slotId']} anchor {row['normalizedAnchor']}: {verdict}"
                )


def _assert_no_internal_overlap(rows, verse_set_fn) -> None:
    """Five proposals must not collide with each other."""
    keys = [row["anchorKey"] for row in rows]
    if len(set(keys)) != len(keys):
        raise AnchorOverlapRejected("two slots propose the identical anchor")
    if verse_set_fn is None:
        return
    sets = {row["slotId"]: frozenset(verse_set_fn(row["normalizedAnchor"]))
            for row in rows}
    ordered = sorted(sets)
    for index, left in enumerate(ordered):
        for right in ordered[index + 1:]:
            shared = sets[left] & sets[right]
            if shared:
                raise AnchorOverlapRejected(
                    f"slots {left} and {right} share {len(shared)} verses"
                )


# ---------------------------------------------------------------------------
# Per-row occupancy transitions (occupying -> occupying only)
# ---------------------------------------------------------------------------

def _per_row_transition(event_type: str, claim: AnchorClaim, *, actor: str,
                        factory_home, story_id: int | None = None,
                        reason: str = "", now=None) -> AnchorClaim:
    home = resolve_factory_home(factory_home)
    target = _PER_ROW_TARGET_STATE[event_type]
    with _acl_ledger_lock(home) as path:
        states = _replay_locked(path)
        current = states.get(claim.key)
        if current is None:
            raise AnchorLedgerCorrupt(f"no committed claim for {claim.key}")
        if current.state == target and event_type != "ANCHOR_BOUND":
            return current  # per-row idempotence
        if target not in _LEGAL_TRANSITIONS[current.state]:
            raise AnchorLedgerCorrupt(
                f"illegal transition {current.state} -> {target} for {claim.key}"
            )
        bound_story = current.story_id
        if event_type == "ANCHOR_BOUND":
            if story_id is None or type(story_id) is not int or story_id <= 0:
                raise AnchorClaimError("ANCHOR_BOUND requires a positive storyId")
            if current.story_id is not None:
                if current.story_id != story_id:
                    raise AnchorLedgerCorrupt(
                        f"{claim.key} is already bound to {current.story_id}; "
                        "rebinding is refused"
                    )
                return current  # idempotent re-bind of an already-bound row
            for other in states.values():
                if (
                    other.story_id == story_id
                    and other.key != current.key
                    and other.state in OCCUPYING_STATES
                ):
                    raise AnchorLedgerCorrupt(
                        f"story {story_id} is already bound to {other.key}"
                    )
            bound_story = story_id
        event = {
            "schemaVersion": SCHEMA_VERSION,
            "eventId": str(uuid.uuid4()),
            "timestamp": _timestamp(_utc_now(now)),
            "eventType": event_type,
            "runId": current.run_id,
            "packetId": current.packet_id,
            "actor": _require_text(actor, "actor"),
            "packetClaimHash": current.packet_claim_hash,
            "reason": reason or event_type,
            "rows": [{
                "slotId": current.slot_id,
                "normalizedAnchor": current.normalized_anchor,
                "anchorKey": current.anchor_key,
                "comparisonId": current.comparison_id,
                "storyId": bound_story,
            }],
        }
        _append_locked(path, event)
        return dataclasses.replace(current, state=target, story_id=bound_story,
                                   event_id=event["eventId"])


def bind_story_id(claim: AnchorClaim, story_id: int, *, actor: str,
                  factory_home=None, now=None) -> AnchorClaim:
    """Replace the negative comparison identity with the real story ID, once."""
    return _per_row_transition("ANCHOR_BOUND", claim, actor=actor,
                               factory_home=factory_home, story_id=story_id,
                               reason="anchor bound to reserved story id", now=now)


def mark_authoring(claim, *, actor, factory_home=None, now=None) -> AnchorClaim:
    return _per_row_transition("ANCHOR_AUTHORING", claim, actor=actor,
                               factory_home=factory_home, now=now)


def mark_materialized(claim, *, actor, factory_home=None, now=None) -> AnchorClaim:
    return _per_row_transition("ANCHOR_MATERIALIZED", claim, actor=actor,
                               factory_home=factory_home, now=now)


def mark_retired(claim, *, actor, factory_home=None, now=None) -> AnchorClaim:
    """Catalog registration.  Per-row: MATERIALIZED and RETIRED both project
    to ``locked``, so a partial retirement changes nothing the gate observes."""
    return _per_row_transition("ANCHOR_RETIRED", claim, actor=actor,
                               factory_home=factory_home, now=now)


def mark_recoverable(claim, *, actor, factory_home=None, reason="lease lapsed",
                     now=None) -> AnchorClaim:
    """A lease lapse never frees an anchor.  RECOVERABLE still occupies; it
    means eligible for owner adjudication, not available."""
    return _per_row_transition("ANCHOR_RECOVERABLE", claim, actor=actor,
                               factory_home=factory_home, reason=reason, now=now)


# ---------------------------------------------------------------------------
# Packet-atomic freeing transitions
# ---------------------------------------------------------------------------

AUTHORIZED_OWNER_ACTORS = frozenset({"owner"})


def _free_packet(event_type: str, *, run_id: str, packet_id: str, actor: str,
                 packet_claim_hash_value: str, factory_home=None,
                 reason: str = "", now=None) -> tuple[AnchorClaim, ...]:
    if actor not in AUTHORIZED_OWNER_ACTORS:
        raise OwnerAuthorizationRequired(
            f"{event_type} requires an authorized owner actor; got {actor!r}. "
            "Expiry, automation and agents may never free an anchor."
        )
    home = resolve_factory_home(factory_home)
    target = _PACKET_EVENT_TARGET_STATE[event_type]
    with _acl_ledger_lock(home) as path:
        states = _replay_locked(path)
        claims = sorted(
            (c for c in states.values() if (c.run_id, c.packet_id) == (run_id, packet_id)),
            key=lambda c: c.slot_id,
        )
        if not claims:
            raise AnchorLedgerCorrupt(f"no claims for {run_id}/{packet_id}")
        if len(claims) != PACKET_SIZE:
            raise AnchorLedgerCorrupt(
                f"{run_id}/{packet_id} has {len(claims)} claims; a free must "
                f"reconcile exactly {PACKET_SIZE}"
            )
        # All-five identity: four matching rows and one divergent row fails the
        # retry rather than freeing the four.
        rows_for_hash = [{"slotId": c.slot_id, "normalizedAnchor": c.normalized_anchor,
                          "anchorKey": c.anchor_key} for c in claims]
        actual = packet_claim_hash(run_id, packet_id, rows_for_hash)
        if actual != packet_claim_hash_value:
            raise AnchorLedgerCorrupt(
                f"{run_id}/{packet_id} transaction identity does not reconcile; "
                "no anchor was freed"
            )
        lock_dir = home / _LOCKS_NAME
        if all(c.state == target for c in claims):
            _reconcile_terminal_packet_locks(
                claims,
                run_id=run_id,
                packet_id=packet_id,
                claim_hash=actual,
                lock_dir=lock_dir,
            )
            return tuple(claims)  # idempotent retry
        for claim in claims:
            if target not in _LEGAL_TRANSITIONS[claim.state]:
                raise AnchorLedgerCorrupt(
                    f"illegal transition {claim.state} -> {target} for {claim.key}"
                )
        # Before freeing the authoritative rows, prove all five advisory locks
        # still belong to this exact transaction.  A foreign lock must never be
        # unlinked merely because its filename matches one of our anchor keys.
        reconcile_committed_locks(
            claims,
            run_id=run_id,
            packet_id=packet_id,
            claim_hash=actual,
            lock_dir=lock_dir,
        )

        event = {
            "schemaVersion": SCHEMA_VERSION,
            "eventId": str(uuid.uuid4()),
            "timestamp": _timestamp(_utc_now(now)),
            "eventType": event_type,
            "runId": run_id,
            "packetId": packet_id,
            "actor": actor,
            "packetClaimHash": actual,
            "reason": reason or event_type,
            "rows": [{
                "slotId": c.slot_id,
                "normalizedAnchor": c.normalized_anchor,
                "anchorKey": c.anchor_key,
                "comparisonId": c.comparison_id,
                "storyId": c.story_id,
            } for c in claims],
        }
        # Commit FIRST: the append is the authoritative free.  A crash between
        # commit and unlink leaves stale release orphans, which are never
        # treated as occupancy.  An exact owner-authorized retry removes only
        # its own orphan and leaves any successor packet's lock untouched.  The
        # reverse order would drop exclusivity for nothing.
        _append_locked(path, event)
        terminal = tuple(
            dataclasses.replace(c, state=target, event_id=event["eventId"])
            for c in claims
        )
        _reconcile_terminal_packet_locks(
            terminal,
            run_id=run_id,
            packet_id=packet_id,
            claim_hash=actual,
            lock_dir=lock_dir,
        )
        return terminal


def release_packet_claims(*, run_id, packet_id, actor, packet_claim_hash_value,
                          factory_home=None, reason="", now=None):
    return _free_packet("PACKET_ANCHORS_RELEASED", run_id=run_id,
                        packet_id=packet_id, actor=actor,
                        packet_claim_hash_value=packet_claim_hash_value,
                        factory_home=factory_home, reason=reason, now=now)


def abort_packet_claims(*, run_id, packet_id, actor, packet_claim_hash_value,
                        factory_home=None, reason="", now=None):
    return _free_packet("PACKET_ANCHORS_ABORTED", run_id=run_id,
                        packet_id=packet_id, actor=actor,
                        packet_claim_hash_value=packet_claim_hash_value,
                        factory_home=factory_home, reason=reason, now=now)


# ---------------------------------------------------------------------------
# Backfill: appends ACL evidence only
# ---------------------------------------------------------------------------

#: **Documentation and test contract -- NOT a runtime guard.**
#:
#: This tuple enumerates the paths V4 section 4 forbids backfill from writing.
#: Nothing consults it at runtime, and it must not be mistaken for a check: the
#: actual guarantee is structural, not defensive.  ``backfill_packet_claims``
#: opens exactly one path for writing -- the ACL -- so there is no code path
#: that could touch anything listed here, and a filesystem-scanning runtime
#: assertion would add machinery that guards against a branch which does not
#: exist.
#:
#: The enforcement lives in the tests instead, where it belongs:
#: ``test_row_50_backfill_changes_the_acl_and_nothing_else`` hashes a
#: proving-packet-shaped tree before and after and asserts byte-identity, and
#: ``test_backfill_write_surface_is_exactly_one_path`` asserts the structural
#: write surface directly.  Both fail if a future edit widens what backfill
#: opens for writing.
#:
#: Named for what it is so that a reader does not trust a constant that
#: enforces nothing.
BACKFILL_FORBIDDEN_WRITES_DOC_CONTRACT = (
    "events.jsonl", "reservations.jsonl", "packet.json",
    "story_*.txt", "reflection_*.txt", "scripture_*.txt", "meta_*.json",
    "manifest.json", "manifest_opus.json", "kids_manifest.json",
    "scripture_anchor_registry.json", "character_registry.json",
    "biblical_figure_registry.json", "used_scripture_anchors.json",
    "*.mp3", "*.wav", "*.m4a",
)

#: Every path ``backfill_packet_claims`` may open for writing.  Exactly one.
BACKFILL_WRITE_SURFACE = (_LEDGER_NAME,)

_RESERVATION_STATE_TO_CLAIM = {
    "RESERVED": CLAIMED,
    "MATERIALIZED": MATERIALIZED,
    "RETIRED": RETIRED,
}


def derive_backfill_claims(packet: Mapping[str, object],
                           reservation_states: Mapping[int, str]) -> list[dict]:
    """Derive ACL rows for one historical packet.  Pure; writes nothing."""
    slots = packet.get("slots")
    if not isinstance(slots, list) or len(slots) != PACKET_SIZE:
        raise AnchorClaimError("backfill requires a five-slot packet snapshot")
    rows = []
    derived_states = set()
    for slot in slots:
        slot_id = _require_slot(slot["slotId"])
        story_id = slot.get("storyId")
        if type(story_id) is not int or story_id <= 0:
            raise AnchorClaimError("backfill requires a materialized story id")
        anchor = _require_text(slot.get("proposedAnchor"), "proposedAnchor")
        reservation_state = reservation_states.get(story_id)
        claim_state = _RESERVATION_STATE_TO_CLAIM.get(str(reservation_state))
        if claim_state is None:
            raise AnchorLedgerCorrupt(
                f"story {story_id} reservation state {reservation_state!r} has no "
                "backfill projection"
            )
        derived_states.add(claim_state)
        rows.append({
            "slotId": slot_id,
            "normalizedAnchor": _default_normalize(anchor),
            "anchorKey": anchor_key(_default_normalize(anchor)),
            "comparisonId": comparison_id(str(packet["runId"]), str(packet["packetId"]), slot_id),
            "storyId": story_id,
        })
    if len(derived_states) != 1:
        raise AnchorLedgerCorrupt(
            f"backfill would derive mixed claim states {sorted(derived_states)}; "
            "a historical packet must backfill as one uniform state"
        )
    rows.sort(key=lambda row: row["slotId"])
    return rows


def backfill_packet_claims(*, packet: Mapping[str, object],
                           reservation_states: Mapping[int, str],
                           actor: str, factory_home=None,
                           now=None) -> tuple[AnchorClaim, ...]:
    """Append ACL evidence for one historical packet.  The ACL is the ONLY
    path written.  No journal, reservation, packet.json, story, metadata,
    manifest, registry or audio byte is read-modify-written."""
    home = resolve_factory_home(factory_home)
    run_id = _require_safe_id(packet["runId"], "runId")
    packet_id = _require_safe_id(packet["packetId"], "packetId")
    rows = derive_backfill_claims(packet, reservation_states)
    claim_hash = packet_claim_hash(run_id, packet_id, rows)
    state = _RESERVATION_STATE_TO_CLAIM[
        str(reservation_states[rows[0]["storyId"]])
    ]
    with _acl_ledger_lock(home) as path:
        states = _replay_locked(path)
        existing = [c for c in states.values()
                    if (c.run_id, c.packet_id) == (run_id, packet_id)]
        if existing:
            if len(existing) != PACKET_SIZE or any(
                c.packet_claim_hash != claim_hash for c in existing
            ):
                raise AnchorLedgerCorrupt(
                    f"{run_id}/{packet_id} already has divergent ACL evidence"
                )
            return tuple(sorted(existing, key=lambda c: c.slot_id))  # verifying no-op
        timestamp = _timestamp(_utc_now(now))
        base_event_id = pending_event_id(run_id, packet_id, claim_hash)
        _append_locked(path, {
            "schemaVersion": SCHEMA_VERSION,
            "eventId": base_event_id,
            "timestamp": timestamp,
            "eventType": "PACKET_ANCHORS_CLAIMED",
            "runId": run_id,
            "packetId": packet_id,
            "actor": _require_text(actor, "actor"),
            "packetClaimHash": claim_hash,
            "reason": "backfill of historical packet anchor occupancy",
            "rows": rows,
        })
        result = []
        for row in rows:
            claim = AnchorClaim(
                run_id=run_id, packet_id=packet_id, slot_id=row["slotId"],
                normalized_anchor=row["normalizedAnchor"], anchor_key=row["anchorKey"],
                comparison_id=row["comparisonId"], state=CLAIMED,
                packet_claim_hash=claim_hash, event_id=base_event_id,
                story_id=row["storyId"],
            )
            result.append(claim)
        for target_event, target_state in (
            ("ANCHOR_MATERIALIZED", MATERIALIZED), ("ANCHOR_RETIRED", RETIRED),
        ):
            if state not in (MATERIALIZED, RETIRED):
                break
            for index, claim in enumerate(result):
                event_id = str(uuid.uuid4())
                _append_locked(path, {
                    "schemaVersion": SCHEMA_VERSION,
                    "eventId": event_id,
                    "timestamp": timestamp,
                    "eventType": target_event,
                    "runId": run_id,
                    "packetId": packet_id,
                    "actor": actor,
                    "packetClaimHash": claim_hash,
                    "reason": "backfill of historical packet anchor occupancy",
                    "rows": [{
                        "slotId": claim.slot_id,
                        "normalizedAnchor": claim.normalized_anchor,
                        "anchorKey": claim.anchor_key,
                        "comparisonId": claim.comparison_id,
                        "storyId": claim.story_id,
                    }],
                })
                result[index] = dataclasses.replace(
                    claim, state=target_state, event_id=event_id
                )
            if target_state == state:
                break
    return tuple(result)


__all__ = [
    "ABORTED", "AUTHORING", "CLAIMED", "MATERIALIZED", "RECOVERABLE",
    "RELEASED", "RETIRED", "CLAIM_STATES", "FREEING_STATES", "OCCUPYING_STATES",
    "PACKET_ATOMIC_EVENTS", "PER_ROW_EVENTS", "EVENT_TYPES", "PACKET_SIZE",
    "AnchorClaim", "AnchorClaimError", "AnchorClaimRecoveryRequired",
    "AnchorConflict", "AnchorLedgerCorrupt", "AnchorOverlapRejected",
    "BACKFILL_FORBIDDEN_WRITES_DOC_CONTRACT", "BACKFILL_WRITE_SURFACE",
    "ClaimResult", "LockOrderViolation", "OwnerAuthorizationRequired",
    "L1_ACL_LEDGER", "L2_ANCHOR_LOCK", "L3_RESERVATION_LEDGER", "L4_STORY_LOCK",
    "L5_PACKET_JOURNAL", "L6_MATERIALIZATION", "LOCK_RANK_NAMES",
    "abort_packet_claims", "add_lock_observer", "anchor_key",
    "backfill_packet_claims", "bind_story_id", "build_overlap_queue",
    "claim_packet_anchors", "claim_to_overlap_queue_row", "comparison_id",
    "derive_backfill_claims", "held_lock_ranks", "ledger_path", "lock_rank",
    "pending_event_id",
    "locks_dir", "mark_authoring", "mark_materialized", "mark_recoverable",
    "mark_retired", "packet_claim_hash", "reconcile_committed_locks",
    "release_packet_claims",
    "remove_lock_observer", "replay_ledger", "resolve_factory_home",
]
