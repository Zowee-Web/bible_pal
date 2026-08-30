#!/usr/bin/env python3
"""Race-safe story ID reservations for the autonomous 3000-3258 campaign.

The exclusive per-ID lock is the admission primitive.  The append-only JSONL
ledger is the durable audit history.  ``state.json`` is deliberately absent:
current state is always reconstructed from the ledger, then checked against
the locks and against physical/manifest occupancy in every live Git worktree.
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
import subprocess
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Iterable, Iterator, Mapping


MIN_AUTOMATION_STORY_ID = 3000
MAX_AUTOMATION_STORY_ID = 3258
AUTOMATION_STORY_ID_COUNT = (
    MAX_AUTOMATION_STORY_ID - MIN_AUTOMATION_STORY_ID + 1
)

SCHEMA_VERSION = 1
FACTORY_HOME_ENV = "BIBLE_PAL_FACTORY_HOME"
DEFAULT_LEASE_SECONDS = 60 * 60

_LEDGER_NAME = "reservations.jsonl"
_LOCKS_NAME = "locks"
_STATES = frozenset({"RESERVED", "MATERIALIZED", "RELEASED", "RETIRED"})
_OCCUPYING_STATES = frozenset({"RESERVED", "MATERIALIZED", "RETIRED"})
_EVENT_TYPES = frozenset(
    {
        "RESERVED", "RENEWED", "MATERIALIZED", "RELEASED", "RETIRED",
        "RECOVERED", "ADOPTED",
    }
)
_EVENT_FIELDS = frozenset(
    {
        "schemaVersion",
        "eventId",
        "timestamp",
        "eventType",
        "runId",
        "packetId",
        "storyId",
        "actor",
        "leaseToken",
        "worktree",
        "priorState",
        "newState",
        "reason",
        "occupancySnapshotHash",
        "reservedAt",
        "leaseExpiresAt",
    }
)
_LOCK_FIELDS = frozenset(
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
    }
)
_STORY_ID_RE = re.compile(r"^story_(\d+)(?:_|$)")
_PATH_ID_RE = re.compile(
    r"^(?:assets/stories/)?(?:traditional|kids)/(\d+)(?:/|$)"
)
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class StoryIdReservationError(Exception):
    """Base class for typed reservation failures."""


class NamespaceExhausted(StoryIdReservationError):
    """The fixed 3000-3258 campaign namespace has no available ID."""


class ReservationConflict(StoryIdReservationError):
    """Authoritative reservation evidence conflicts or ownership is wrong."""


class LedgerCorrupt(StoryIdReservationError):
    """The append-only reservation history cannot be trusted."""


class IllegalTransition(LedgerCorrupt):
    """A ledger event or API request attempts an illegal state transition."""


class OccupancyScanError(StoryIdReservationError):
    """Worktree, story-directory, or manifest occupancy is ambiguous."""


class StaleRecoveryDenied(StoryIdReservationError):
    """A stale claim cannot be proven safe to reclaim."""


@dataclasses.dataclass(frozen=True)
class Reservation:
    """Authoritative owner/state reconstructed from the event ledger."""

    story_id: int
    run_id: str
    packet_id: str
    actor: str
    lease_token: str
    worktree: str
    reserved_at: str
    lease_expires_at: str
    state: str


@dataclasses.dataclass(frozen=True)
class OccupancySnapshot:
    """Deterministic evidence collected from worktrees, manifests, and ledger."""

    occupied_ids: frozenset[int]
    physical_ids: frozenset[int]
    manifest_ids: frozenset[int]
    ledger_ids: frozenset[int]
    worktrees: tuple[str, ...]
    evidence_hash: str


def _require_story_id(story_id: object) -> int:
    if type(story_id) is not int:  # bool is intentionally rejected.
        raise ReservationConflict("story ID must be an integer, not bool or another type")
    if not MIN_AUTOMATION_STORY_ID <= story_id <= MAX_AUTOMATION_STORY_ID:
        raise ReservationConflict(
            f"story ID {story_id} is outside the fixed automation range "
            f"{MIN_AUTOMATION_STORY_ID}-{MAX_AUTOMATION_STORY_ID}"
        )
    return story_id


def _require_text(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReservationConflict(f"{field} must be a non-empty string")
    return value


def _utc_now(now: dt.datetime | None = None) -> dt.datetime:
    value = now if now is not None else dt.datetime.now(dt.timezone.utc)
    if not isinstance(value, dt.datetime) or value.tzinfo is None:
        raise ReservationConflict("now must be a timezone-aware datetime")
    return value.astimezone(dt.timezone.utc)


def _require_lease_seconds(value: object) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        raise ReservationConflict("lease_seconds must be a positive number")
    return value


def _timestamp(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_timestamp(value: object, field: str, error_type=LedgerCorrupt) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise error_type(f"{field} must be a non-empty timestamp string")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise error_type(f"{field} is not an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise error_type(f"{field} must include an explicit timezone")
    return parsed.astimezone(dt.timezone.utc)


def _resolve_factory_home(factory_home: os.PathLike[str] | str | None) -> Path:
    if factory_home is not None:
        raw = os.fspath(factory_home)
    else:
        raw = os.environ.get(FACTORY_HOME_ENV) or str(Path.home() / ".bible_pal_factory")
    if not raw:
        raise ReservationConflict("factory home must not be empty")
    return Path(raw).expanduser().resolve(strict=False)


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _assert_factory_home_is_shared(home: Path, worktrees: Iterable[Path]) -> None:
    for worktree in worktrees:
        if _is_relative_to(home, worktree):
            raise ReservationConflict(
                f"factory home must be outside every Git worktree: {home} is under {worktree}"
            )


def _ensure_private_directory(path: Path) -> None:
    try:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = os.lstat(path)
    except OSError as exc:
        raise ReservationConflict(f"cannot create or inspect private directory {path}: {exc}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise ReservationConflict(f"private state path is not a real directory: {path}")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ReservationConflict(f"private state directory has unsafe permissions: {path}")


def _prepare_factory_home(home: Path) -> tuple[Path, Path]:
    _ensure_private_directory(home)
    locks = home / _LOCKS_NAME
    _ensure_private_directory(locks)
    return locks, home / _LEDGER_NAME


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant {value}")


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def _decode_json(text: str, source: str, error_type=LedgerCorrupt) -> object:
    try:
        return json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_json_constant,
        )
    except (json.JSONDecodeError, ValueError) as exc:
        raise error_type(f"invalid JSON in {source}: {exc}") from exc


def _read_regular_file(path: Path, error_type, purpose: str) -> bytes:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise error_type(f"cannot open {purpose} {path}: {exc}") from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise error_type(f"{purpose} is not a regular file: {path}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    except OSError as exc:
        raise error_type(f"cannot read {purpose} {path}: {exc}") from exc
    finally:
        os.close(fd)


def _normalize_worktrees(paths: Iterable[os.PathLike[str] | str]) -> tuple[Path, ...]:
    normalized: list[Path] = []
    seen: set[Path] = set()
    for raw in paths:
        try:
            path = Path(raw).expanduser().resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise OccupancyScanError(f"worktree is inaccessible: {raw}: {exc}") from exc
        if not path.is_dir():
            raise OccupancyScanError(f"worktree is not a directory: {path}")
        if path in seen:
            raise OccupancyScanError(f"duplicate worktree enumeration: {path}")
        seen.add(path)
        normalized.append(path)
    if not normalized:
        raise OccupancyScanError("Git reported no live worktrees")
    return tuple(normalized)


def _enumerate_worktrees(repo_root: os.PathLike[str] | str) -> tuple[Path, ...]:
    try:
        proc = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            cwd=Path(repo_root),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        raise OccupancyScanError(f"cannot enumerate Git worktrees: {exc}") from exc
    if proc.returncode != 0:
        raise OccupancyScanError(
            f"git worktree enumeration failed ({proc.returncode}): {proc.stderr.strip()}"
        )
    paths = [line[9:] for line in proc.stdout.splitlines() if line.startswith("worktree ")]
    return _normalize_worktrees(paths)


def _get_worktrees(
    repo_root: os.PathLike[str] | str,
    worktrees: Iterable[os.PathLike[str] | str] | None,
) -> tuple[Path, ...]:
    return _normalize_worktrees(worktrees) if worktrees is not None else _enumerate_worktrees(repo_root)


def _manifest_story_ids(path: Path) -> tuple[set[int], list[tuple[int, str]]]:
    try:
        raw = _read_regular_file(path, OccupancyScanError, "authoritative manifest")
        text = raw.decode("utf-8")
    except UnicodeError as exc:
        raise OccupancyScanError(f"manifest is not UTF-8: {path}: {exc}") from exc
    manifest = _decode_json(text, str(path), OccupancyScanError)
    if not isinstance(manifest, dict) or not isinstance(manifest.get("parables"), list):
        raise OccupancyScanError(f"manifest has an ambiguous root schema: {path}")

    story_ids: set[int] = set()
    evidence: list[tuple[int, str]] = []
    for index, entry in enumerate(manifest["parables"]):
        if not isinstance(entry, dict):
            raise OccupancyScanError(f"{path}: parables[{index}] is not an object")
        raw_story_id = entry.get("storyId")
        if not isinstance(raw_story_id, str) or not raw_story_id:
            raise OccupancyScanError(f"{path}: parables[{index}].storyId is invalid")
        identity_ids: set[int] = set()
        match = _STORY_ID_RE.match(raw_story_id)
        if match:
            identity_ids.add(int(match.group(1)))
        for key, value in entry.items():
            if not key.lower().endswith("filepath") or value in (None, ""):
                continue
            if not isinstance(value, str):
                raise OccupancyScanError(f"{path}: parables[{index}].{key} is invalid")
            match = _PATH_ID_RE.match(value)
            if match:
                identity_ids.add(int(match.group(1)))
        if len(identity_ids) != 1:
            raise OccupancyScanError(
                f"{path}: parables[{index}] has ambiguous story identity {sorted(identity_ids)}"
            )
        story_id = next(iter(identity_ids))
        story_ids.add(story_id)
        evidence.append((story_id, f"{path}:parables[{index}]:{raw_story_id}"))
    return story_ids, evidence


def _scan_external_occupancy(
    repo_root: os.PathLike[str] | str,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
) -> OccupancySnapshot:
    roots = _get_worktrees(repo_root, worktrees)
    physical: set[int] = set()
    manifest: set[int] = set()
    evidence: list[tuple[str, int, str]] = []

    for root in roots:
        try:
            root_info = os.lstat(root)
        except OSError as exc:
            raise OccupancyScanError(f"worktree became inaccessible: {root}: {exc}") from exc
        if not stat.S_ISDIR(root_info.st_mode):
            raise OccupancyScanError(f"worktree is not a real directory: {root}")

        for lane in ("traditional", "kids"):
            lane_path = root / "assets" / "stories" / lane
            try:
                lane_info = os.lstat(lane_path)
            except FileNotFoundError:
                continue
            except OSError as exc:
                raise OccupancyScanError(f"cannot inspect story lane {lane_path}: {exc}") from exc
            if not stat.S_ISDIR(lane_info.st_mode) or stat.S_ISLNK(lane_info.st_mode):
                raise OccupancyScanError(f"story lane is not a real directory: {lane_path}")
            try:
                with os.scandir(lane_path) as entries:
                    for entry in entries:
                        if not entry.name.isdecimal():
                            continue
                        story_id = int(entry.name)
                        if MIN_AUTOMATION_STORY_ID <= story_id <= MAX_AUTOMATION_STORY_ID:
                            try:
                                is_directory = entry.is_dir(follow_symlinks=False)
                            except OSError as exc:
                                raise OccupancyScanError(
                                    f"cannot classify story path {entry.path}: {exc}"
                                ) from exc
                            if not is_directory:
                                raise OccupancyScanError(
                                    f"campaign story path exists but is not a directory: {entry.path}"
                                )
                            physical.add(story_id)
                            evidence.append(("physical", story_id, str(Path(entry.path))))
            except OSError as exc:
                if isinstance(exc, OccupancyScanError):
                    raise
                raise OccupancyScanError(f"cannot scan story lane {lane_path}: {exc}") from exc

        manifest_path = root / "assets" / "stories" / "manifest.json"
        ids, manifest_evidence = _manifest_story_ids(manifest_path)
        for story_id, source in manifest_evidence:
            if MIN_AUTOMATION_STORY_ID <= story_id <= MAX_AUTOMATION_STORY_ID:
                manifest.add(story_id)
                evidence.append(("manifest", story_id, source))

    worktree_strings = tuple(str(path) for path in roots)
    payload = {
        "worktrees": worktree_strings,
        "evidence": sorted(evidence),
    }
    evidence_hash = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    occupied = physical | manifest
    return OccupancySnapshot(
        occupied_ids=frozenset(occupied),
        physical_ids=frozenset(physical),
        manifest_ids=frozenset(manifest),
        ledger_ids=frozenset(),
        worktrees=worktree_strings,
        evidence_hash=evidence_hash,
    )


def _validate_uuid(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise LedgerCorrupt(f"{field} must be a non-empty UUID")
    try:
        uuid.UUID(value)
    except (ValueError, AttributeError) as exc:
        raise LedgerCorrupt(f"{field} is not a UUID") from exc
    return value


def _validate_event(event: object, line_number: int) -> dict[str, object]:
    if not isinstance(event, dict):
        raise LedgerCorrupt(f"ledger line {line_number} is not an object")
    if frozenset(event) != _EVENT_FIELDS:
        missing = sorted(_EVENT_FIELDS - frozenset(event))
        extra = sorted(frozenset(event) - _EVENT_FIELDS)
        raise LedgerCorrupt(
            f"ledger line {line_number} has wrong fields; missing={missing}, extra={extra}"
        )
    if type(event["schemaVersion"]) is not int or event["schemaVersion"] != SCHEMA_VERSION:
        raise LedgerCorrupt(f"ledger line {line_number} has unsupported schemaVersion")
    if event["eventType"] not in _EVENT_TYPES:
        raise LedgerCorrupt(f"ledger line {line_number} has unknown eventType")
    if type(event["storyId"]) is not int:
        raise LedgerCorrupt(f"ledger line {line_number} storyId must be an integer, not bool")
    try:
        _require_story_id(event["storyId"])
    except ReservationConflict as exc:
        raise LedgerCorrupt(f"ledger line {line_number}: {exc}") from exc
    _validate_uuid(event["eventId"], "eventId")
    _validate_uuid(event["leaseToken"], "leaseToken")
    for field in ("runId", "packetId", "actor", "worktree", "reason"):
        if not isinstance(event[field], str) or not event[field]:
            raise LedgerCorrupt(f"ledger line {line_number} {field} must be non-empty")
    if not Path(event["worktree"]).is_absolute():
        raise LedgerCorrupt(f"ledger line {line_number} worktree must be absolute")
    if event["priorState"] is not None and event["priorState"] not in _STATES:
        raise LedgerCorrupt(f"ledger line {line_number} has invalid priorState")
    if event["newState"] not in _STATES:
        raise LedgerCorrupt(f"ledger line {line_number} has invalid newState")
    if not isinstance(event["occupancySnapshotHash"], str) or not _SHA256_RE.fullmatch(
        event["occupancySnapshotHash"]
    ):
        raise LedgerCorrupt(f"ledger line {line_number} has invalid occupancySnapshotHash")
    timestamp = _parse_timestamp(event["timestamp"], "timestamp")
    reserved_at = _parse_timestamp(event["reservedAt"], "reservedAt")
    expires_at = _parse_timestamp(event["leaseExpiresAt"], "leaseExpiresAt")
    if expires_at <= reserved_at:
        raise LedgerCorrupt(f"ledger line {line_number} lease does not expire after reservation")
    if timestamp < reserved_at:
        raise LedgerCorrupt(f"ledger line {line_number} predates its reservation")
    return event


def _event_transition(event: Mapping[str, object], current: Reservation | None) -> str:
    event_type = event["eventType"]
    prior = current.state if current is not None else None
    if event["priorState"] != prior:
        raise IllegalTransition(
            f"story {event['storyId']} declares priorState {event['priorState']!r}, "
            f"but replay derived {prior!r}"
        )
    allowed: dict[str, tuple[set[str | None], str]] = {
        "RESERVED": ({None, "RELEASED"}, "RESERVED"),
        "RENEWED": ({"RESERVED"}, "RESERVED"),
        "ADOPTED": ({None, "RELEASED"}, "MATERIALIZED"),
        "MATERIALIZED": ({"RESERVED"}, "MATERIALIZED"),
        "RELEASED": ({"RESERVED"}, "RELEASED"),
        "RECOVERED": ({"RESERVED"}, "RELEASED"),
        "RETIRED": ({"MATERIALIZED"}, "RETIRED"),
    }
    priors, expected_new = allowed[event_type]
    if prior not in priors or event["newState"] != expected_new:
        raise IllegalTransition(
            f"illegal {event_type} transition for story {event['storyId']}: "
            f"{prior!r} -> {event['newState']!r}"
        )
    return expected_new


def _replay_bytes(raw: bytes, source: str) -> dict[int, Reservation]:
    if not raw:
        return {}
    if not raw.endswith(b"\n"):
        raise LedgerCorrupt(f"truncated ledger (missing final newline): {source}")
    try:
        text = raw.decode("utf-8")
    except UnicodeError as exc:
        raise LedgerCorrupt(f"ledger is not UTF-8: {source}: {exc}") from exc

    states: dict[int, Reservation] = {}
    event_ids: set[str] = set()
    lease_tokens: set[str] = set()
    last_timestamps: dict[int, dt.datetime] = {}
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line:
            raise LedgerCorrupt(f"blank ledger line {line_number}: {source}")
        event = _validate_event(_decode_json(line, f"{source}:{line_number}"), line_number)
        event_id = event["eventId"]
        if event_id in event_ids:
            raise LedgerCorrupt(f"duplicate eventId at ledger line {line_number}: {event_id}")
        event_ids.add(event_id)
        story_id = event["storyId"]
        event_time = _parse_timestamp(event["timestamp"], "timestamp")
        if story_id in last_timestamps and event_time < last_timestamps[story_id]:
            raise LedgerCorrupt(f"story {story_id} ledger timestamps move backward")
        last_timestamps[story_id] = event_time
        current = states.get(story_id)
        new_state = _event_transition(event, current)

        if event["eventType"] in {"RESERVED", "ADOPTED"}:
            if event["leaseToken"] in lease_tokens:
                raise LedgerCorrupt(f"lease token reused at ledger line {line_number}")
            lease_tokens.add(event["leaseToken"])
            states[story_id] = Reservation(
                story_id=story_id,
                run_id=event["runId"],
                packet_id=event["packetId"],
                actor=event["actor"],
                lease_token=event["leaseToken"],
                worktree=event["worktree"],
                reserved_at=event["reservedAt"],
                lease_expires_at=event["leaseExpiresAt"],
                state=new_state,
            )
            continue

        assert current is not None
        if event["eventType"] == "RENEWED":
            for field, current_value in (
                ("runId", current.run_id),
                ("packetId", current.packet_id),
                ("actor", current.actor),
                ("leaseToken", current.lease_token),
                ("worktree", current.worktree),
                ("reservedAt", current.reserved_at),
            ):
                if event[field] != current_value:
                    raise LedgerCorrupt(
                        f"story {story_id} renewal changes authoritative {field}"
                    )
            prior_expiry = _parse_timestamp(current.lease_expires_at, "leaseExpiresAt")
            renewed_expiry = _parse_timestamp(event["leaseExpiresAt"], "leaseExpiresAt")
            if renewed_expiry <= prior_expiry or renewed_expiry <= event_time:
                raise LedgerCorrupt(
                    f"story {story_id} renewal does not extend beyond the prior lease and event time"
                )
            states[story_id] = dataclasses.replace(
                current,
                lease_expires_at=event["leaseExpiresAt"],
                state=new_state,
            )
            continue

        for field, current_value in (
            ("runId", current.run_id),
            ("packetId", current.packet_id),
            ("leaseToken", current.lease_token),
            ("worktree", current.worktree),
            ("reservedAt", current.reserved_at),
            ("leaseExpiresAt", current.lease_expires_at),
        ):
            if event[field] != current_value:
                raise LedgerCorrupt(
                    f"story {story_id} transition changes authoritative {field}"
                )
        states[story_id] = dataclasses.replace(current, state=new_state)
    return states


def replay_ledger(
    factory_home: os.PathLike[str] | str | None = None,
) -> dict[int, Reservation]:
    """Strictly replay the append-only ledger; never consult ``state.json``."""

    home = _resolve_factory_home(factory_home)
    ledger = home / _LEDGER_NAME
    try:
        os.lstat(ledger)
    except FileNotFoundError:
        return {}
    except OSError as exc:
        raise LedgerCorrupt(f"cannot inspect ledger {ledger}: {exc}") from exc

    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(ledger, flags)
    except OSError as exc:
        raise LedgerCorrupt(f"cannot open ledger {ledger}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_SH)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise LedgerCorrupt(f"ledger is not a regular file: {ledger}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        return _replay_bytes(b"".join(chunks), str(ledger))
    except OSError as exc:
        raise LedgerCorrupt(f"cannot read ledger {ledger}: {exc}") from exc
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def scan_occupied_ids(
    repo_root: os.PathLike[str] | str,
    *,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
) -> OccupancySnapshot:
    """Return fail-closed occupancy across live worktrees, manifests, and ledger."""

    external = _scan_external_occupancy(repo_root, worktrees)
    home = _resolve_factory_home(factory_home)
    roots = tuple(Path(path) for path in external.worktrees)
    _assert_factory_home_is_shared(home, roots)
    states = replay_ledger(home)
    ledger_ids = {story_id for story_id, state in states.items() if state.state in _OCCUPYING_STATES}
    occupied = set(external.occupied_ids) | ledger_ids
    payload = {
        "external": external.evidence_hash,
        "ledger": sorted((story_id, states[story_id].state) for story_id in ledger_ids),
    }
    evidence_hash = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return dataclasses.replace(
        external,
        occupied_ids=frozenset(occupied),
        ledger_ids=frozenset(ledger_ids),
        evidence_hash=evidence_hash,
    )


def _write_all(fd: int, data: bytes) -> None:
    offset = 0
    while offset < len(data):
        written = os.write(fd, data[offset:])
        if written <= 0:
            raise OSError("short write while persisting reservation evidence")
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


def _lock_record(reservation: Reservation) -> dict[str, object]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "runId": reservation.run_id,
        "packetId": reservation.packet_id,
        "storyId": reservation.story_id,
        "actor": reservation.actor,
        "leaseToken": reservation.lease_token,
        "worktree": reservation.worktree,
        "reservedAt": reservation.reserved_at,
        "leaseExpiresAt": reservation.lease_expires_at,
    }


def _atomic_claim(lock_path: Path, reservation: Reservation) -> int | None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags, 0o600)
    except FileExistsError:
        return None
    except OSError as exc:
        raise ReservationConflict(f"cannot atomically claim {lock_path}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        payload = json.dumps(
            _lock_record(reservation), sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        _write_all(fd, payload)
        os.fsync(fd)
        _fsync_directory(lock_path.parent)
        return fd
    except Exception:
        # Deliberately leave an uncertain claim in place.  Removing it could
        # make a partially persisted reservation available to another worker.
        os.close(fd)
        raise


def _append_event(home: Path, event: Mapping[str, object]) -> None:
    ledger = home / _LEDGER_NAME
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(ledger, flags, 0o600)
    except OSError as exc:
        raise LedgerCorrupt(f"cannot open append-only ledger {ledger}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise LedgerCorrupt(f"ledger is not a regular file: {ledger}")
        encoded = (
            json.dumps(dict(event), sort_keys=True, separators=(",", ":")) + "\n"
        ).encode("utf-8")
        _write_all(fd, encoded)
        os.fsync(fd)
        _fsync_directory(home)
    except OSError as exc:
        raise LedgerCorrupt(f"cannot append durable ledger event: {exc}") from exc
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _new_event(
    event_type: str,
    reservation: Reservation,
    *,
    actor: str,
    prior_state: str | None,
    new_state: str,
    reason: str,
    occupancy_hash: str,
    now: dt.datetime,
) -> dict[str, object]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "eventId": str(uuid.uuid4()),
        "timestamp": _timestamp(now),
        "eventType": event_type,
        "runId": reservation.run_id,
        "packetId": reservation.packet_id,
        "storyId": reservation.story_id,
        "actor": _require_text(actor, "actor"),
        "leaseToken": reservation.lease_token,
        "worktree": reservation.worktree,
        "priorState": prior_state,
        "newState": new_state,
        "reason": _require_text(reason, "reason"),
        "occupancySnapshotHash": occupancy_hash,
        "reservedAt": reservation.reserved_at,
        "leaseExpiresAt": reservation.lease_expires_at,
    }


def _read_lock_fd(fd: int, lock_path: Path) -> dict[str, object]:
    try:
        os.lseek(fd, 0, os.SEEK_SET)
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 64 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        text = b"".join(chunks).decode("utf-8")
    except (OSError, UnicodeError) as exc:
        raise ReservationConflict(f"cannot read lock {lock_path}: {exc}") from exc
    record = _decode_json(text, str(lock_path), ReservationConflict)
    if not isinstance(record, dict) or frozenset(record) != _LOCK_FIELDS:
        raise ReservationConflict(f"lock record has an ambiguous schema: {lock_path}")
    if type(record["schemaVersion"]) is not int or record["schemaVersion"] != SCHEMA_VERSION:
        raise ReservationConflict(f"lock record has unsupported schemaVersion: {lock_path}")
    if type(record["storyId"]) is not int:
        raise ReservationConflict(f"lock storyId must be an integer, not bool: {lock_path}")
    for field in ("runId", "packetId", "actor", "leaseToken", "worktree", "reservedAt", "leaseExpiresAt"):
        if not isinstance(record[field], str) or not record[field]:
            raise ReservationConflict(f"lock field {field} is invalid: {lock_path}")
    _parse_timestamp(record["reservedAt"], "reservedAt", ReservationConflict)
    _parse_timestamp(record["leaseExpiresAt"], "leaseExpiresAt", ReservationConflict)
    return record


def _validate_lock_matches(record: Mapping[str, object], reservation: Reservation) -> None:
    expected = _lock_record(reservation)
    if dict(record) != expected:
        raise ReservationConflict(
            f"lock/ledger disagreement for story {reservation.story_id}"
        )


def _lock_identity_matches(record: Mapping[str, object], reservation: Reservation) -> bool:
    expected = _lock_record(reservation)
    return all(
        record.get(field) == value
        for field, value in expected.items()
        if field != "leaseExpiresAt"
    )


def _rewrite_locked_claim(fd: int, lock_path: Path, reservation: Reservation) -> None:
    payload = json.dumps(
        _lock_record(reservation), sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    try:
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        _write_all(fd, payload)
        os.fsync(fd)
        _fsync_directory(lock_path.parent)
    except OSError as exc:
        raise ReservationConflict(
            f"cannot persist renewed reservation lock {lock_path}: {exc}"
        ) from exc


@contextmanager
def _locked_claim(lock_path: Path) -> Iterator[int]:
    flags = os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags)
    except OSError as exc:
        raise ReservationConflict(f"reservation lock is missing or unreadable: {lock_path}: {exc}") from exc
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        opened = os.fstat(fd)
        try:
            current = os.stat(lock_path, follow_symlinks=False)
        except OSError as exc:
            raise ReservationConflict(f"reservation lock changed while waiting: {lock_path}") from exc
        if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            raise ReservationConflict(f"reservation lock inode changed: {lock_path}")
        yield fd
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _remove_locked_claim(lock_path: Path, fd: int) -> None:
    opened = os.fstat(fd)
    try:
        current = os.stat(lock_path, follow_symlinks=False)
    except OSError as exc:
        raise ReservationConflict(f"reservation lock disappeared: {lock_path}") from exc
    if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
        raise ReservationConflict(f"refusing to unlink replaced lock: {lock_path}")
    try:
        os.unlink(lock_path)
        _fsync_directory(lock_path.parent)
    except OSError as exc:
        raise ReservationConflict(f"cannot relinquish reservation lock {lock_path}: {exc}") from exc


def _assert_api_reservation(current: Reservation | None, supplied: Reservation) -> Reservation:
    if not isinstance(supplied, Reservation):
        raise ReservationConflict("reservation argument must be a Reservation")
    if current != supplied:
        raise ReservationConflict(
            f"supplied reservation is stale, forged, or not current for story {supplied.story_id}"
        )
    return supplied


def _assert_renewal_identity(
    current: Reservation | None,
    supplied: Reservation,
    *,
    actor: str,
) -> Reservation:
    if not isinstance(supplied, Reservation):
        raise ReservationConflict("reservation argument must be a Reservation")
    if current is None:
        raise ReservationConflict(
            f"story {supplied.story_id} has no authoritative reservation"
        )
    if current.state != "RESERVED":
        raise IllegalTransition(f"only RESERVED claims may renew, not {current.state}")
    if supplied.state != "RESERVED":
        raise ReservationConflict("supplied renewal claim must be RESERVED")
    for field in (
        "story_id", "run_id", "packet_id", "actor", "lease_token",
        "worktree", "reserved_at",
    ):
        if getattr(current, field) != getattr(supplied, field):
            raise ReservationConflict(
                f"story {supplied.story_id} renewal ownership mismatch: {field}"
            )
    if actor != current.actor:
        raise ReservationConflict(
            f"story {supplied.story_id} renewal actor is not the reservation owner"
        )
    current_expiry = _parse_timestamp(
        current.lease_expires_at, "leaseExpiresAt", ReservationConflict
    )
    supplied_expiry = _parse_timestamp(
        supplied.lease_expires_at, "leaseExpiresAt", ReservationConflict
    )
    if current_expiry < supplied_expiry:
        raise ReservationConflict(
            f"story {supplied.story_id} supplied lease is newer than authoritative replay"
        )
    return current


def _renew_reservation(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None,
    worktrees: Iterable[os.PathLike[str] | str] | None,
    actor: str,
    lease_seconds: int | float,
    now: dt.datetime | None,
    allow_expired: bool,
    owner_authorized: bool,
) -> Reservation:
    actor = _require_text(actor, "actor")
    lease_seconds = _require_lease_seconds(lease_seconds)
    event_time = _utc_now(now)
    home, lock_path, _ = _transition_context(
        reservation,
        repo_root=repo_root,
        factory_home=factory_home,
        worktrees=worktrees,
    )
    initial = replay_ledger(home).get(reservation.story_id)
    if initial is None:
        raise ReservationConflict(
            f"story {reservation.story_id} has no authoritative reservation"
        )
    if initial.state != "RESERVED":
        raise IllegalTransition(f"only RESERVED claims may renew, not {initial.state}")
    with _locked_claim(lock_path) as fd:
        current = _assert_renewal_identity(
            replay_ledger(home).get(reservation.story_id),
            reservation,
            actor=actor,
        )
        lock_record = _read_lock_fd(fd, lock_path)
        current_expiry = _parse_timestamp(
            current.lease_expires_at, "leaseExpiresAt", ReservationConflict
        )
        supplied_expiry = _parse_timestamp(
            reservation.lease_expires_at, "leaseExpiresAt", ReservationConflict
        )
        if dict(lock_record) != _lock_record(current):
            lock_expiry = _parse_timestamp(
                lock_record.get("leaseExpiresAt"),
                "leaseExpiresAt",
                ReservationConflict,
            )
            if not _lock_identity_matches(lock_record, current) or lock_expiry >= current_expiry:
                raise ReservationConflict(
                    f"lock/ledger disagreement for story {reservation.story_id}"
                )
            snapshot = _scan_external_occupancy(repo_root, worktrees)
            if reservation.story_id in snapshot.occupied_ids:
                raise ReservationConflict(
                    f"story {reservation.story_id} has physical or manifest occupancy and cannot renew"
                )
            _rewrite_locked_claim(fd, lock_path, current)
            if current_expiry > event_time:
                return current

        snapshot = _scan_external_occupancy(repo_root, worktrees)
        if reservation.story_id in snapshot.occupied_ids:
            raise ReservationConflict(
                f"story {reservation.story_id} has physical or manifest occupancy and cannot renew"
            )
        if current_expiry > supplied_expiry and current_expiry > event_time:
            return current

        expired = current_expiry <= event_time
        if expired and not allow_expired:
            raise StaleRecoveryDenied(
                f"story {reservation.story_id} lease is expired; explicit owner recovery is required"
            )
        if expired and owner_authorized is not True:
            raise StaleRecoveryDenied(
                f"story {reservation.story_id} expired renewal lacks explicit owner authorization"
            )

        renewed_expiry = max(current_expiry, event_time) + dt.timedelta(
            seconds=lease_seconds
        )
        renewed = dataclasses.replace(
            current,
            lease_expires_at=_timestamp(renewed_expiry),
        )
        _append_event(
            home,
            _new_event(
                "RENEWED",
                renewed,
                actor=actor,
                prior_state="RESERVED",
                new_state="RESERVED",
                reason=(
                    "owner-authorized expired reservation renewal"
                    if expired
                    else "active reservation lease renewal"
                ),
                occupancy_hash=snapshot.evidence_hash,
                now=event_time,
            ),
        )
        _rewrite_locked_claim(fd, lock_path, renewed)
        return renewed


def renew_reservation(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str,
    lease_seconds: int | float = DEFAULT_LEASE_SECONDS,
    now: dt.datetime | None = None,
) -> Reservation:
    """Append an owner-matched renewal for a still-active RESERVED lease."""

    return _renew_reservation(
        reservation,
        repo_root=repo_root,
        factory_home=factory_home,
        worktrees=worktrees,
        actor=actor,
        lease_seconds=lease_seconds,
        now=now,
        allow_expired=False,
        owner_authorized=False,
    )


def renew_expired_reservation(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str,
    owner_authorized: bool = False,
    lease_seconds: int | float = DEFAULT_LEASE_SECONDS,
    now: dt.datetime | None = None,
) -> Reservation:
    """Explicitly renew an expired, still-owned RESERVED claim without replacing it."""

    if owner_authorized is not True:
        raise StaleRecoveryDenied(
            "expired reservation renewal requires owner_authorized=True"
        )
    return _renew_reservation(
        reservation,
        repo_root=repo_root,
        factory_home=factory_home,
        worktrees=worktrees,
        actor=actor,
        lease_seconds=lease_seconds,
        now=now,
        allow_expired=True,
        owner_authorized=True,
    )


def _material_file_exists(story_id: int, worktrees: Iterable[Path]) -> bool:
    def contains_file(directory: Path) -> bool:
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    try:
                        if entry.is_symlink():
                            raise OccupancyScanError(f"material story path is a symlink: {entry.path}")
                        if entry.is_file(follow_symlinks=False):
                            return True
                        if entry.is_dir(follow_symlinks=False) and contains_file(Path(entry.path)):
                            return True
                    except OSError as exc:
                        raise OccupancyScanError(f"cannot inspect material path {entry.path}: {exc}") from exc
        except FileNotFoundError:
            return False
        except OSError as exc:
            if isinstance(exc, OccupancyScanError):
                raise
            raise OccupancyScanError(f"cannot scan material directory {directory}: {exc}") from exc
        return False

    for root in worktrees:
        for lane in ("traditional", "kids"):
            if contains_file(root / "assets" / "stories" / lane / str(story_id)):
                return True
    return False


def reserve_id(
    *,
    run_id: str,
    packet_id: str,
    actor: str,
    worktree: os.PathLike[str] | str,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    lease_seconds: int | float = DEFAULT_LEASE_SECONDS,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    now: dt.datetime | None = None,
) -> Reservation:
    """Atomically reserve the lowest safe ID in the fixed campaign range."""

    run_id = _require_text(run_id, "run_id")
    packet_id = _require_text(packet_id, "packet_id")
    actor = _require_text(actor, "actor")
    lease_seconds = _require_lease_seconds(lease_seconds)
    current_time = _utc_now(now)
    roots = _get_worktrees(repo_root, worktrees)
    owner_worktree = Path(worktree).expanduser().resolve(strict=True)
    if owner_worktree not in roots:
        raise ReservationConflict(f"owner worktree is not in the live Git worktree set: {owner_worktree}")
    home = _resolve_factory_home(factory_home)
    _assert_factory_home_is_shared(home, roots)
    locks, _ = _prepare_factory_home(home)

    states = replay_ledger(home)
    initial = _scan_external_occupancy(repo_root, worktrees)
    conflicting_locks: list[int] = []
    for story_id in range(MIN_AUTOMATION_STORY_ID, MAX_AUTOMATION_STORY_ID + 1):
        current = states.get(story_id)
        if story_id in initial.occupied_ids or (
            current is not None and current.state in _OCCUPYING_STATES
        ):
            continue

        reserved_at = _timestamp(current_time)
        lease_expires_at = _timestamp(current_time + dt.timedelta(seconds=lease_seconds))
        reservation = Reservation(
            story_id=story_id,
            run_id=run_id,
            packet_id=packet_id,
            actor=actor,
            lease_token=str(uuid.uuid4()),
            worktree=str(owner_worktree),
            reserved_at=reserved_at,
            lease_expires_at=lease_expires_at,
            state="RESERVED",
        )
        lock_path = locks / f"{story_id}.lock"
        fd = _atomic_claim(lock_path, reservation)
        if fd is None:
            conflicting_locks.append(story_id)
            continue
        try:
            refreshed = replay_ledger(home).get(story_id)
            if refreshed is not None and refreshed.state != "RELEASED":
                raise ReservationConflict(
                    f"lock/ledger disagreement after claiming story {story_id}"
                )
            prior_state = refreshed.state if refreshed is not None else None
            _append_event(
                home,
                _new_event(
                    "RESERVED",
                    reservation,
                    actor=actor,
                    prior_state=prior_state,
                    new_state="RESERVED",
                    reason="atomic campaign reservation",
                    occupancy_hash=initial.evidence_hash,
                    now=current_time,
                ),
            )
            post_claim = _scan_external_occupancy(repo_root, worktrees)
            if story_id in post_claim.occupied_ids:
                _append_event(
                    home,
                    _new_event(
                        "MATERIALIZED",
                        reservation,
                        actor=actor,
                        prior_state="RESERVED",
                        new_state="MATERIALIZED",
                        reason="occupancy appeared during post-claim race recheck",
                        occupancy_hash=post_claim.evidence_hash,
                        now=current_time,
                    ),
                )
                states[story_id] = dataclasses.replace(reservation, state="MATERIALIZED")
                continue
            return reservation
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)

    if conflicting_locks:
        raise ReservationConflict(
            "campaign candidates were blocked by lock/ledger disagreement or concurrent claims: "
            + ", ".join(str(value) for value in conflicting_locks)
        )
    raise NamespaceExhausted(
        f"automation story ID namespace {MIN_AUTOMATION_STORY_ID}-{MAX_AUTOMATION_STORY_ID} is exhausted"
    )


def _transition_context(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None,
    worktrees: Iterable[os.PathLike[str] | str] | None,
) -> tuple[Path, Path, tuple[Path, ...]]:
    _require_story_id(reservation.story_id)
    roots = _get_worktrees(repo_root, worktrees)
    home = _resolve_factory_home(factory_home)
    _assert_factory_home_is_shared(home, roots)
    locks = home / _LOCKS_NAME
    try:
        info = os.lstat(locks)
    except OSError as exc:
        raise ReservationConflict(f"reservation lock directory is unavailable: {locks}: {exc}") from exc
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ReservationConflict(f"reservation lock directory is invalid: {locks}")
    return home, locks / f"{reservation.story_id}.lock", roots


def confirm_materialized(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str | None = None,
    now: dt.datetime | None = None,
) -> Reservation:
    """Burn a RESERVED ID after proving material story files exist."""

    home, lock_path, _ = _transition_context(
        reservation, repo_root=repo_root, factory_home=factory_home, worktrees=worktrees
    )
    with _locked_claim(lock_path) as fd:
        current = _assert_api_reservation(replay_ledger(home).get(reservation.story_id), reservation)
        if current.state != "RESERVED":
            raise IllegalTransition(f"only RESERVED claims may materialize, not {current.state}")
        _validate_lock_matches(_read_lock_fd(fd, lock_path), current)
        snapshot = _scan_external_occupancy(repo_root, worktrees)
        roots = tuple(Path(path) for path in snapshot.worktrees)
        if not _material_file_exists(reservation.story_id, roots):
            raise ReservationConflict(
                f"story {reservation.story_id} has no material file in any live worktree"
            )
        event_time = _utc_now(now)
        _append_event(
            home,
            _new_event(
                "MATERIALIZED",
                reservation,
                actor=actor or reservation.actor,
                prior_state="RESERVED",
                new_state="MATERIALIZED",
                reason="material story files confirmed",
                occupancy_hash=snapshot.evidence_hash,
                now=event_time,
            ),
        )
    return dataclasses.replace(reservation, state="MATERIALIZED")


def release_reservation(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str | None = None,
    reason: str = "unmaterialized reservation released",
    now: dt.datetime | None = None,
) -> Reservation:
    """Release only a still-RESERVED claim with no external occupancy."""

    home, lock_path, _ = _transition_context(
        reservation, repo_root=repo_root, factory_home=factory_home, worktrees=worktrees
    )
    with _locked_claim(lock_path) as fd:
        current = _assert_api_reservation(replay_ledger(home).get(reservation.story_id), reservation)
        if current.state != "RESERVED":
            raise IllegalTransition(f"only RESERVED claims may release, not {current.state}")
        _validate_lock_matches(_read_lock_fd(fd, lock_path), current)
        snapshot = _scan_external_occupancy(repo_root, worktrees)
        if reservation.story_id in snapshot.occupied_ids:
            raise IllegalTransition(
                f"story {reservation.story_id} has physical or manifest occupancy and cannot release"
            )
        _append_event(
            home,
            _new_event(
                "RELEASED",
                reservation,
                actor=actor or reservation.actor,
                prior_state="RESERVED",
                new_state="RELEASED",
                reason=reason,
                occupancy_hash=snapshot.evidence_hash,
                now=_utc_now(now),
            ),
        )
        _remove_locked_claim(lock_path, fd)
    return dataclasses.replace(reservation, state="RELEASED")


def retire_reservation(
    reservation: Reservation,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str | None = None,
    reason: str = "materialized story retired",
    now: dt.datetime | None = None,
) -> Reservation:
    """Move MATERIALIZED content to the permanent RETIRED state."""

    home, lock_path, _ = _transition_context(
        reservation, repo_root=repo_root, factory_home=factory_home, worktrees=worktrees
    )
    with _locked_claim(lock_path) as fd:
        current = _assert_api_reservation(replay_ledger(home).get(reservation.story_id), reservation)
        if current.state != "MATERIALIZED":
            raise IllegalTransition(f"only MATERIALIZED claims may retire, not {current.state}")
        _validate_lock_matches(_read_lock_fd(fd, lock_path), current)
        snapshot = _scan_external_occupancy(repo_root, worktrees)
        _append_event(
            home,
            _new_event(
                "RETIRED",
                reservation,
                actor=actor or reservation.actor,
                prior_state="MATERIALIZED",
                new_state="RETIRED",
                reason=reason,
                occupancy_hash=snapshot.evidence_hash,
                now=_utc_now(now),
            ),
        )
    return dataclasses.replace(reservation, state="RETIRED")


def recover_stale(
    story_id: int,
    *,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    actor: str = "stale-recovery",
    reason: str = "expired unmaterialized reservation recovered",
    now: dt.datetime | None = None,
) -> Reservation:
    """Recover an expired RESERVED claim only after every safety source is clear."""

    story_id = _require_story_id(story_id)
    roots = _get_worktrees(repo_root, worktrees)
    home = _resolve_factory_home(factory_home)
    _assert_factory_home_is_shared(home, roots)
    lock_path = home / _LOCKS_NAME / f"{story_id}.lock"
    current = replay_ledger(home).get(story_id)
    if current is None:
        if os.path.lexists(lock_path):
            raise ReservationConflict(f"lock/ledger disagreement for story {story_id}")
        raise StaleRecoveryDenied(f"story {story_id} has no recoverable RESERVED claim")
    if current.state != "RESERVED":
        if current.state == "RELEASED" and os.path.lexists(lock_path):
            raise ReservationConflict(f"lock/ledger disagreement for story {story_id}")
        raise StaleRecoveryDenied(
            f"story {story_id} has permanent {current.state} history and cannot recover"
        )
    with _locked_claim(lock_path) as fd:
        current = replay_ledger(home).get(story_id)
        if current is None or current.state != "RESERVED":
            raise ReservationConflict(f"story {story_id} changed while recovery waited")
        _validate_lock_matches(_read_lock_fd(fd, lock_path), current)
        if _utc_now(now) < _parse_timestamp(
            current.lease_expires_at, "leaseExpiresAt", ReservationConflict
        ):
            raise StaleRecoveryDenied(f"story {story_id} lease has not expired")
        snapshot = _scan_external_occupancy(repo_root, worktrees)
        if story_id in snapshot.occupied_ids:
            raise StaleRecoveryDenied(
                f"story {story_id} has physical or manifest occupancy and cannot recover"
            )
        _append_event(
            home,
            _new_event(
                "RECOVERED",
                current,
                actor=actor,
                prior_state="RESERVED",
                new_state="RELEASED",
                reason=reason,
                occupancy_hash=snapshot.evidence_hash,
                now=_utc_now(now),
            ),
        )
        _remove_locked_claim(lock_path, fd)
    return dataclasses.replace(current, state="RELEASED")


def adopt_preexisting(
    story_id: int,
    *,
    run_id: str,
    packet_id: str,
    actor: str,
    worktree: os.PathLike[str] | str,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    lease_seconds: int | float = DEFAULT_LEASE_SECONDS,
    reason: str = "preexisting occupied story adopted",
    now: dt.datetime | None = None,
) -> Reservation:
    """Record unreserved physical/manifest occupancy as permanently materialized."""

    story_id = _require_story_id(story_id)
    if isinstance(lease_seconds, bool) or not isinstance(lease_seconds, (int, float)) or lease_seconds <= 0:
        raise ReservationConflict("lease_seconds must be a positive number")
    roots = _get_worktrees(repo_root, worktrees)
    owner_worktree = Path(worktree).expanduser().resolve(strict=True)
    if owner_worktree not in roots:
        raise ReservationConflict("adoption owner worktree is not live")
    home = _resolve_factory_home(factory_home)
    _assert_factory_home_is_shared(home, roots)
    locks, _ = _prepare_factory_home(home)
    states = replay_ledger(home)
    current = states.get(story_id)
    if current is not None and current.state != "RELEASED":
        raise ReservationConflict(f"story {story_id} already has reservation state {current.state}")
    snapshot = _scan_external_occupancy(repo_root, worktrees)
    if story_id not in snapshot.occupied_ids:
        raise ReservationConflict(f"story {story_id} has no preexisting occupancy to adopt")
    event_time = _utc_now(now)
    reservation = Reservation(
        story_id=story_id,
        run_id=_require_text(run_id, "run_id"),
        packet_id=_require_text(packet_id, "packet_id"),
        actor=_require_text(actor, "actor"),
        lease_token=str(uuid.uuid4()),
        worktree=str(owner_worktree),
        reserved_at=_timestamp(event_time),
        lease_expires_at=_timestamp(event_time + dt.timedelta(seconds=lease_seconds)),
        state="MATERIALIZED",
    )
    lock_path = locks / f"{story_id}.lock"
    fd = _atomic_claim(lock_path, reservation)
    if fd is None:
        raise ReservationConflict(f"story {story_id} has a lock without adoptable ledger state")
    try:
        refreshed = replay_ledger(home).get(story_id)
        if refreshed is not None and refreshed.state != "RELEASED":
            raise ReservationConflict(f"story {story_id} changed during adoption")
        _append_event(
            home,
            _new_event(
                "ADOPTED",
                reservation,
                actor=actor,
                prior_state=refreshed.state if refreshed else None,
                new_state="MATERIALIZED",
                reason=reason,
                occupancy_hash=snapshot.evidence_hash,
                now=event_time,
            ),
        )
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
    return reservation


def reserve_packet(
    *,
    count: int = 5,
    run_id: str,
    packet_id: str,
    actor: str,
    worktree: os.PathLike[str] | str,
    repo_root: os.PathLike[str] | str,
    factory_home: os.PathLike[str] | str | None = None,
    lease_seconds: int | float = DEFAULT_LEASE_SECONDS,
    worktrees: Iterable[os.PathLike[str] | str] | None = None,
    now: dt.datetime | None = None,
) -> tuple[Reservation, ...]:
    """Reserve a packet sequentially; safely unwind only unmaterialized claims."""

    if type(count) is not int or count <= 0:
        raise ReservationConflict("packet count must be a positive integer, not bool")
    reservations: list[Reservation] = []
    try:
        for _ in range(count):
            reservations.append(
                reserve_id(
                    run_id=run_id,
                    packet_id=packet_id,
                    actor=actor,
                    worktree=worktree,
                    repo_root=repo_root,
                    factory_home=factory_home,
                    lease_seconds=lease_seconds,
                    worktrees=worktrees,
                    now=now,
                )
            )
    except Exception as original:
        cleanup_errors: list[str] = []
        states = replay_ledger(factory_home)
        for reservation in reversed(reservations):
            current = states.get(reservation.story_id)
            if current is None or current.state != "RESERVED" or current.lease_token != reservation.lease_token:
                continue
            try:
                release_reservation(
                    current,
                    repo_root=repo_root,
                    factory_home=factory_home,
                    worktrees=worktrees,
                    actor=actor,
                    reason="partial packet reservation rollback",
                    now=now,
                )
            except StoryIdReservationError as exc:
                cleanup_errors.append(f"{reservation.story_id}: {exc}")
        if cleanup_errors:
            raise ReservationConflict(
                f"packet failed ({original}); cleanup also failed: {'; '.join(cleanup_errors)}"
            ) from original
        raise
    return tuple(reservations)


__all__ = [
    "AUTOMATION_STORY_ID_COUNT",
    "MAX_AUTOMATION_STORY_ID",
    "MIN_AUTOMATION_STORY_ID",
    "IllegalTransition",
    "LedgerCorrupt",
    "NamespaceExhausted",
    "OccupancyScanError",
    "OccupancySnapshot",
    "Reservation",
    "ReservationConflict",
    "StaleRecoveryDenied",
    "adopt_preexisting",
    "confirm_materialized",
    "recover_stale",
    "renew_expired_reservation",
    "renew_reservation",
    "release_reservation",
    "replay_ledger",
    "reserve_id",
    "reserve_packet",
    "retire_reservation",
    "scan_occupied_ids",
]
