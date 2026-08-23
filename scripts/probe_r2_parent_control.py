#!/usr/bin/env python3
"""Bible PAL — R2 PARENT-CREDENTIAL CONTROL (single diagnostic request).

ONE QUESTION, ONE REQUEST. Gate D1 and Gate D2 both died on their first
PutObject with HTTP 400 InvalidArgument, having transmitted a locally
signed temporary credential. This harness answers exactly one thing:

    does the SAME disposable PutObject succeed when it is authenticated
    directly with the long-lived bucket-scoped parent S3 credential —
    no temporary credential, no JWT, no session token, and no
    x-amz-security-token?

DELIBERATELY SEPARATE FROM THE GATE D PROBE. `probe_r2_cas.py` refuses a
live send that is not backed by exactly a `TemporaryCredential`, and its
evidence schema refuses a key that is not allocator-shaped. Both refusals
are correct and are NOT weakened here: this file never imports the Gate D
transport, allocator, matrix or EvidenceWriter. It imports only PURE,
side-effect-free helpers (the SigV4 signer, the endpoint builder, the
error sanitizer, the private-file helpers) so the signing algorithm under
test is byte-for-byte the reviewed one.

THIS HARNESS DOES NOT TEST THE GATE D MATRIX. It cannot produce a CAS
PASS/FAIL and deliberately has no vocabulary for one.

Default mode is PLAN: it opens no socket, resolves no name, reads no
credential file and writes no evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import stat
import sys
import threading
import time
import urllib.parse
from typing import NamedTuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# PURE helpers only. Nothing imported here opens a socket, reads a file or
# mutates process state; the Gate D live path is not reachable from any of
# them. `sign_request` is the reviewed SigV4 implementation and is reused
# rather than reimplemented, so the control differs from Gate D in its
# AUTHENTICATION only — never in its signing algorithm.
from probe_r2_cas import (          # noqa: E402
    MIN_PROJECTED_SECRET_CHARS,
    EndpointRefused,
    EvidenceValidationError,
    MissingAuthorization,
    ProductionNameDetected,
    SafetyBarrierTripped,
    _iter_persisted_strings,
    _sha256_hex,
    assert_no_known_secret,
    build_endpoint_host,
    canonical_secret_projection,
    new_request_target,
    parse_s3_error,
    safe_error_argument,
    safe_error_message,
    sign_request,
    synthetic_payload,
)

EXIT_SUCCESS = 0
EXIT_R2_REJECTED = 20
EXIT_TRANSPORT_FAILURE = 21
EXIT_INCOMPLETE = 22
EXIT_REFUSED = 2


class ParentControlRefused(Exception):
    """This harness refused to proceed."""


class ConfidentialityWithheld(Exception):
    """The response could not be shown free of credential material.

    Carries a FIXED generic message: the whole point is that nothing
    derived from the rejected response reaches a log, a console or an
    exception string.
    """


def _capture_policy():
    """The immutable control policy, captured once at import.

    Returned through a closure so no module-level name can be rebound to
    widen the target: rebinding `PROBE_BUCKET` below changes a display
    alias and nothing else.
    """
    policy = {
        "bucket": "bible-pal-cas-probe",
        "denied_tokens": ("bible-pal-audio",),
        "key_prefix": "catalog/probe/control/",
        "key_leaf": "parent-put.json",
        "body_bytes": 256,
        "if_none_match": "*",
        "confirmation": "PARENT-CREDENTIAL-DISPOSABLE-PUT-ONLY",
        "credential_keys": ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"),
        "max_credential_file_bytes": 4096,
        "max_response_bytes": 65536,
        "connect_timeout_seconds": 30.0,
        "evidence_dirname": "parent-control-evidence",
        "anchor_dirname": "parent-control-anchors",
        "manifest_filename": "evidence-manifest.json",
        "record_filename": "parent_control_record.json",
    }

    def get(name):
        value = policy[name]
        return value

    return get


_policy = _capture_policy()

#: Display aliases ONLY. Enforcement always reads `_policy(...)`.
PROBE_BUCKET = _policy("bucket")
DENIED_NAMES = _policy("denied_tokens")
EXECUTE_CONFIRMATION = _policy("confirmation")

_ACCOUNT_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_CONTROL_RUN_ID_RE = re.compile(r"^ctl-[0-9]{1,10}-[0-9a-f]{1,16}$")
_CREDENTIAL_VALUE_RE = re.compile(r"^[!-~]{8,128}$")
_ENV_LINE_RE = re.compile(r"^([A-Z0-9_]{1,64})=(.*)$")


# ─────────────────────────────────────────────────────────────────────────
# Production-name denial
# ─────────────────────────────────────────────────────────────────────────

def assert_no_production_name(*values) -> None:
    """Refuse if a denied production name appears anywhere in `values`.

    CASEFOLDED, unlike the Gate D scan: this harness is new, so there is
    no reason to inherit a case-sensitive check. Subclasses of str/bytes
    are refused outright rather than scanned, because a polymorphic
    `__contains__` could lie to it.
    """
    denied = _policy("denied_tokens")
    for index, value in enumerate(values):
        if value is None:
            continue
        if type(value) is not str and type(value) is not bytes:
            if isinstance(value, (str, bytes)):
                raise SafetyBarrierTripped(
                    f"polymorphic {type(value).__name__} refused in the "
                    f"production-name scan (argument {index})")
            continue
        text = (value.decode("utf-8", "replace")
                if type(value) is bytes else value)
        folded = text.casefold()
        for token in denied:
            if token.casefold() in folded:
                raise ProductionNameDetected(
                    f"denied production name {token!r} found in argument "
                    f"{index}")


# ─────────────────────────────────────────────────────────────────────────
# Confidentiality boundary
# ─────────────────────────────────────────────────────────────────────────
#
# Gate E's proven model is reused verbatim (`assert_no_known_secret`,
# which does an exact scan plus a separator-insensitive canonical
# projection over every persisted string). That model catches a secret
# broken up by spaces, hyphens, underscores, dots or quotes.
#
# It is NOT sufficient on its own here. Its projection DROPS `&#NN;` and
# `%HH` as noise rather than DECODING them, so a response that substitutes
# one character of a secret — `Alpha&#66;eta...` for `AlphaBeta...` — has a
# projection that no longer contains the secret's projection, while a human
# reading the evidence recovers the secret trivially. R2 error bodies are
# XML, so entity encoding is exactly the shape to expect.
#
# The fix is to decode first, deterministically and boundedly, and then run
# the same proven check on the decoded text as well.

#: Five passes reduces the demonstrated four-layer percent/entity
#: nesting. DELIBERATELY FINITE: unbounded decoding would turn an
#: attacker-chosen response into unbounded work.
_MAX_DECODE_ROUNDS = 5

#: Response-controlled identifiers are additionally held to a bounded
#: grammar. This is defence in depth, not the security control: the
#: universal known-secret boundary below still applies to them. The charset
#: deliberately admits a real Cloudflare ray id (`a2ee5ec95eaea942-DTW`)
#: while excluding the whitespace, quotes, `%` and `&` that a transformed
#: secret needs.
_RESPONSE_IDENTIFIER_RE = re.compile(r"^[0-9A-Za-z._:-]{1,128}$")


def deterministic_decode(text) -> str:
    """Bounded, deterministic decoding of the transport encodings an R2
    response can legitimately carry.

    Repeated to a fixed point at most `_MAX_DECODE_ROUNDS` times so that
    double-encoded material (`&amp;#66;`) is also reduced. Deliberately
    NOT fuzzy: every step is a standard-library, reversible decoding.
    """
    if type(text) is not str:
        raise SafetyBarrierTripped("decode input must be exactly str")
    current = text
    for _ in range(_MAX_DECODE_ROUNDS):
        decoded = html.unescape(urllib.parse.unquote(current))
        if decoded == current:
            break
        current = decoded
    return current


def assert_no_transformed_secret(payload, secrets, where) -> None:
    """THE confidentiality boundary for anything persisted or rendered.

    Two layers, both fail-closed:

      1. Gate E's reviewed `assert_no_known_secret` — exact match plus the
         separator-insensitive projection — over every string in the
         payload, recursively.
      2. The same check again over the DECODED form of each string, which
         is what closes the entity/percent substitution hole.

    No exception raised here echoes the offending value.
    """
    materials = tuple(s for s in secrets
                      if type(s) is str and s)
    if not materials:
        raise SafetyBarrierTripped(
            "the confidentiality boundary requires the known secrets")
    assert_no_known_secret(payload, materials, where)
    for text in _iter_persisted_strings(payload):
        decoded = deterministic_decode(text)
        if decoded == text:
            continue                      # layer 1 already covered it
        # Re-run the PROVEN check on the decoded text rather than
        # reimplementing matching here.
        assert_no_known_secret({"decoded": decoded}, materials, where)


def assert_response_identifier_is_safe(value, field) -> None:
    """Bounded grammar for a response-controlled identifier. `None` is
    always acceptable; the value is never echoed."""
    if value is None:
        return
    if type(value) is not str or not _RESPONSE_IDENTIFIER_RE.fullmatch(value):
        raise EvidenceValidationError(
            f"{field} is not a bounded response identifier")


# ─────────────────────────────────────────────────────────────────────────
# Parent credential
# ─────────────────────────────────────────────────────────────────────────

class ParentCredential(NamedTuple):
    """The long-lived disposable PARENT S3 credential.

    There is deliberately no `session_token` field: this harness exists to
    prove what happens with NO session token, so the type cannot express
    one.
    """

    access_key_id: str
    secret_access_key: str


def parse_parent_credentials(text) -> ParentCredential:
    """Parse the disposable parent credential file's TEXT.

    NOTHING IS NORMALIZED. The parser never strips, unquotes or otherwise
    transforms credential bytes: a value is returned byte-for-byte as it
    appeared after `KEY=`, or the file is refused. Silent normalization was
    the defect here — trailing whitespace and shell-style quotes were being
    accepted and quietly reshaped, so a file that did not actually contain
    the credential could still yield one.

    Line splitting is done on `"\\n"` explicitly, with at most ONE trailing
    `"\\r"` removed, so a CRLF file parses identically to an LF file while
    the credential bytes themselves are untouched. `str.splitlines()` is
    deliberately NOT used: it also splits on \\v, \\f, \\x1c-\\x1e and
    \\u2028, which would silently cut a value in two.

    Secret VALUES never appear in any exception raised here.
    """
    if type(text) is not str:
        raise ParentControlRefused("credential text must be exactly str")
    expected = set(_policy("credential_keys"))
    seen: dict = {}
    for number, raw in enumerate(text.split("\n"), start=1):
        # Remove ONLY the CRLF terminator, never any credential byte.
        line = raw[:-1] if raw.endswith("\r") else raw
        if line == "":
            continue                       # blank lines are intentional
        if line.startswith("#"):
            continue                       # comments are intentional
        match = _ENV_LINE_RE.fullmatch(line)
        if match is None:
            # Anchored and whitespace-free by construction, so this also
            # covers leading space before KEY, space around '=', and
            # leading/trailing space inside VALUE.
            raise ParentControlRefused(
                f"credential file line {number} is not exactly KEY=VALUE "
                "with no surrounding whitespace")
        key, value = match.group(1), match.group(2)
        if key not in expected:
            raise ParentControlRefused(
                f"credential file line {number} has unexpected key {key!r}")
        if key in seen:
            raise ParentControlRefused(
                f"credential file defines {key!r} more than once")
        if not _CREDENTIAL_VALUE_RE.fullmatch(value):
            # Never echo `value`.
            raise ParentControlRefused(
                f"the value for {key!r} is not 8-128 printable ASCII "
                "characters without spaces or control characters")
        if value[0] in "\"'" or value[-1] in "\"'":
            raise ParentControlRefused(
                f"the value for {key!r} looks shell-quoted; this file is "
                "plain KEY=VALUE and quotes are never interpreted")
        seen[key] = value
    missing = sorted(expected - set(seen))
    if missing:
        raise ParentControlRefused(
            f"credential file is missing required keys {missing}")
    return ParentCredential(access_key_id=seen["R2_ACCESS_KEY_ID"],
                            secret_access_key=seen["R2_SECRET_ACCESS_KEY"])


def _assert_credential_stat(st, *, source) -> None:
    """The shared mode/owner/type/size contract, applied to either an
    `lstat` result or an `fstat` of the OPEN descriptor.

    The mode requirement is EXACT 0600. Accepting any owner-only mode
    (0400, 0200, 0700) was too loose: the execution contract names 0600,
    and an unexpected mode means the file is not the one that contract
    describes.
    """
    if stat.S_ISLNK(st.st_mode):
        raise ParentControlRefused(
            f"the credential file is a symlink ({source})")
    if not stat.S_ISREG(st.st_mode):
        raise ParentControlRefused(
            f"the credential file is not a regular file ({source})")
    if hasattr(os, "getuid") and st.st_uid != os.getuid():
        raise ParentControlRefused(
            f"the credential file is not owned by the current user ({source})")
    if stat.S_IMODE(st.st_mode) != 0o600:
        raise ParentControlRefused(
            f"the credential file mode is not exactly 0600 ({source})")
    if st.st_size > _policy("max_credential_file_bytes"):
        raise ParentControlRefused(
            f"the credential file is implausibly large ({source})")


def assert_credential_file_metadata(path):
    """Filesystem-only preconditions. Reads NO bytes. Returns the stat so
    the reader can prove the descriptor it opened is the same file."""
    if type(path) is not str or not path:
        raise MissingAuthorization("--credentials-file is required")
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        raise MissingAuthorization(
            "the disposable credential file does not exist")
    _assert_credential_stat(st, source="path")
    return st


def read_parent_credentials(path) -> ParentCredential:
    """Metadata gate, then the ONE authorized read of the file.

    The contract is re-verified against the OPEN DESCRIPTOR (`fstat`), and
    device/inode are compared with the pre-open `lstat`, so a file swapped
    between the check and the open cannot be read under the earlier file's
    approval.
    """
    before = assert_credential_file_metadata(path)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        _assert_credential_stat(opened, source="open descriptor")
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ParentControlRefused(
                "the credential file changed identity between the metadata "
                "check and the open")
        raw = os.read(fd, _policy("max_credential_file_bytes") + 1)
    finally:
        os.close(fd)
    if len(raw) > _policy("max_credential_file_bytes"):
        raise ParentControlRefused("the credential file grew while reading")
    return parse_parent_credentials(raw.decode("utf-8", "strict"))


# ─────────────────────────────────────────────────────────────────────────
# Execution gates
# ─────────────────────────────────────────────────────────────────────────

#: The path components BELOW the user's home that make up the one live
#: evidence root. Kept as components, not a joined string, because the
#: live path is walked one directory descriptor at a time.
EVIDENCE_ROOT_COMPONENTS = (".local", "state", "bible-pal-parent-control")


def canonical_evidence_root() -> str:
    """The ONE root a live parent control may ever write to.

    A safety invariant, not caller policy. This is the SPELLING; the
    physical identity is established separately by
    `open_live_evidence_root`, because a lexical comparison alone can be
    redirected by a symlinked path component.
    """
    return os.path.join(os.path.expanduser("~"), *EVIDENCE_ROOT_COMPONENTS)


def assert_evidence_root_is_canonical(value) -> str:
    """Lexical gate on the SPELLING of `--evidence-root`.

    Deliberately NOT the security control — `abspath`/`normpath` resolve
    no symlinks, so a symlinked component could still redirect the
    physical target. This rejects obviously wrong spellings early; the
    real invariant is enforced by descriptor-anchored traversal at write
    time.
    """
    if type(value) is not str or not value:
        raise MissingAuthorization("--evidence-root is required")
    resolved = os.path.normpath(
        os.path.abspath(os.path.expanduser(value)))
    if resolved != os.path.normpath(canonical_evidence_root()):
        raise ParentControlRefused(
            "--evidence-root must be exactly the parent-control root "
            f"{canonical_evidence_root()!r}")
    return resolved


def _verify_directory_fd(fd, *, what, exact_mode=None) -> os.stat_result:
    """The shared contract for an OPEN directory descriptor."""
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        raise ParentControlRefused(f"{what} is not a directory")
    if hasattr(os, "getuid") and st.st_uid != os.getuid():
        raise ParentControlRefused(
            f"{what} is not owned by the current user")
    if exact_mode is not None and stat.S_IMODE(st.st_mode) != exact_mode:
        raise ParentControlRefused(
            f"{what} mode is not exactly {exact_mode:04o}")
    return st


def _open_dir_nofollow(name, *, dir_fd, what):
    """Open ONE path component as a directory, refusing symlinks.

    O_NOFOLLOW makes a symlinked component an error rather than a
    redirection, and `dir_fd` anchors the lookup to the parent descriptor
    we already verified — so no part of the path is re-resolved from a
    string that could have changed underneath us.
    """
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    flags |= getattr(os, "O_CLOEXEC", 0)
    try:
        return os.open(name, flags, dir_fd=dir_fd)
    except OSError as exc:
        # ELOOP/ENOTDIR here means the component is a symlink or not a
        # directory. Never echo the resolved target.
        raise ParentControlRefused(
            f"{what} is not a real directory (errno {exc.errno})")


def open_or_create_verified_directory(parent_fd, name, *, what,
                                      exact_mode=None, must_be_new=False):
    """Open — or create, then open and verify — ONE directory component.

    DIRECTORY-ENTRY DURABILITY (Codex round-3 MEDIUM 3). `fsync` on a file
    makes that file's DATA durable; it does NOT make the directory entry
    that NAMES the file durable. So after creating a component we fsync
    the PARENT — and only after the child has been reopened and verified,
    so a name is never persisted before it has been validated.

    A component that merely already existed does not get its parent
    fsynced: this invocation created nothing there, so there is nothing
    new to persist.

    SCOPE, stated plainly: on macOS `fsync()` orders writes to the device
    but is not `F_FULLFSYNC`. This buys process- and kernel-crash
    durability, NOT power-loss media durability. That is the deliberate
    contract for a diagnostic.

    Returns `(fd, created)`.
    """
    if type(parent_fd) is not int:
        raise SafetyBarrierTripped("a parent directory descriptor is required")
    created = False
    try:
        os.mkdir(name, 0o700, dir_fd=parent_fd)
        created = True
    except FileExistsError:
        if must_be_new:
            raise
    fd = _open_dir_nofollow(name, dir_fd=parent_fd, what=what)
    try:
        _verify_directory_fd(fd, what=what, exact_mode=exact_mode)
        if created:
            # The entry exists AND has been verified; now persist the name.
            # A failure propagates — the caller must not proceed as though
            # the path were durable.
            os.fsync(parent_fd)
    except BaseException:
        os.close(fd)
        raise
    return fd, created


def open_live_evidence_root():
    """Return a verified directory FD for the one live evidence root.

    Walks `~/.local/state/bible-pal-parent-control` one component at a
    time from an anchor on the home directory, creating missing
    components 0700, and refusing any component that is a symlink. The
    caller then performs every subsequent mkdir/open anchored to this
    descriptor, so the validated directory cannot be swapped out from
    under the writes.

    The home directory ITSELF is resolved rather than required to be
    symlink-free: on macOS a home path legitimately sits behind
    firmlinks, and refusing that would refuse every normal machine. The
    attack this defends against lives in the components BELOW home.
    """
    home = os.path.realpath(os.path.expanduser("~"))
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0)
    anchor = os.open(home, flags)
    fds = [anchor]
    try:
        _verify_directory_fd(anchor, what="the home directory")
        for index, component in enumerate(EVIDENCE_ROOT_COMPONENTS):
            final = index == len(EVIDENCE_ROOT_COMPONENTS) - 1
            # The dedicated root must be EXACTLY 0700; the shared
            # ancestors only have to be real, owned directories. Each
            # newly created component fsyncs its parent inside the helper.
            fd, _created = open_or_create_verified_directory(
                fds[-1], component,
                what=f"evidence path component {component!r}",
                exact_mode=0o700 if final else None)
            fds.append(fd)
        return fds.pop()
    finally:
        for fd in fds:
            os.close(fd)


class ExecutionGates(NamedTuple):
    execute: bool
    authorized_by_adam: bool
    confirmation: object
    bucket: object
    account_id: object
    credentials_file: object
    evidence_root: object

    def assert_may_execute(self) -> None:
        """EVERY gate, checked BEFORE the credential file is read and
        BEFORE any network machinery is constructed.

        Nothing here has a default: `--bucket` and `--evidence-root` are
        as explicit as `--execute`, because a live argument that can be
        omitted is not part of an explicit authorization.
        """
        if type(self.execute) is not bool or type(
                self.authorized_by_adam) is not bool:
            raise SafetyBarrierTripped("authorization flags must be bool")
        if not self.execute:
            raise MissingAuthorization("--execute was not supplied")
        if not self.authorized_by_adam:
            raise MissingAuthorization(
                "--authorized-by-adam was not supplied")
        if type(self.confirmation) is not str \
                or self.confirmation != _policy("confirmation"):
            raise MissingAuthorization(
                "the exact confirmation string was not supplied")
        if self.bucket is None:
            raise MissingAuthorization("--bucket must be supplied explicitly")
        if type(self.bucket) is not str or self.bucket != _policy("bucket"):
            raise ProductionNameDetected(
                f"--bucket {self.bucket!r} is not the disposable probe bucket")
        if type(self.account_id) is not str \
                or not _ACCOUNT_ID_RE.fullmatch(self.account_id):
            raise MissingAuthorization(
                "--account-id must be exactly 32 lowercase hex characters")
        # Proves the endpoint shape with the reviewed builder.
        build_endpoint_host(self.account_id)
        assert_evidence_root_is_canonical(self.evidence_root)
        assert_credential_file_metadata(self.credentials_file)


# ─────────────────────────────────────────────────────────────────────────
# The one control request
# ─────────────────────────────────────────────────────────────────────────

def new_control_run_id() -> str:
    """Unique per invocation. Create-only evidence directories make a
    collision a hard error rather than an overwrite."""
    run_id = f"ctl-{os.getpid()}-{int(time.time()) & 0xffffffff:x}"
    if not _CONTROL_RUN_ID_RE.fullmatch(run_id):   # pragma: no cover
        raise SafetyBarrierTripped("generated control run id is invalid")
    return run_id


def control_key_for(run_id) -> str:
    """The ONE canonical control key. Namespaced under its own
    `control/` segment, so it can never collide with a Gate D allocator
    key (`catalog/probe/{p,t}/<run-id>/...`)."""
    if type(run_id) is not str or not _CONTROL_RUN_ID_RE.fullmatch(run_id):
        raise SafetyBarrierTripped(f"control run id refused: {run_id!r}")
    return f"{_policy('key_prefix')}{run_id}/{_policy('key_leaf')}"


#: The EXACT body Gate D2's first request sent, pinned by digest. A
#: control that changes the payload bytes as well as the authentication is
#: not a single-variable experiment, so this is reused rather than
#: reinvented: `synthetic_payload` is a pure helper and produces the same
#: 256 bytes the frozen D2 request record attests to.
D2_BODY_SEED = "seed"
D2_BODY_SHA256 = \
    "e28ba69bdecae0003bc057249a6fbc975ed567488ada96e98f213f161dc646ba"


def control_body() -> bytes:
    """Byte-identical to Gate D2 request #1, verified by digest."""
    body = synthetic_payload(D2_BODY_SEED, _policy("body_bytes"))
    if len(body) != _policy("body_bytes"):        # pragma: no cover
        raise SafetyBarrierTripped("control body is not the policy size")
    if hashlib.sha256(body).hexdigest() != D2_BODY_SHA256:
        raise SafetyBarrierTripped(
            "control body does not match the frozen Gate D2 request body")
    return body


def build_control_request(*, credential, account_id, run_id, amz_date):
    """Sign the ONE control request with the PARENT credential.

    `session_token=None` and `unsigned_session_token=None` are passed
    explicitly: the whole point of this harness is that no session token
    and no `x-amz-security-token` header exist on the wire.
    """
    if type(credential) is not ParentCredential:
        raise SafetyBarrierTripped(
            "the control requires exactly a ParentCredential")
    if type(account_id) is not str \
            or not _ACCOUNT_ID_RE.fullmatch(account_id):
        raise EndpointRefused("account id must be 32 lowercase hex")
    host = build_endpoint_host(account_id)
    key = control_key_for(run_id)
    assert_no_production_name(_policy("bucket"), key)
    target = new_request_target(method="PUT", bucket=_policy("bucket"),
                                key=key, query=())
    signed = sign_request(
        target=target, host=host,
        access_key_id=credential.access_key_id,
        secret_access_key=credential.secret_access_key,
        session_token=None,
        body=control_body(), amz_date=amz_date,
        extra_headers={"if-none-match": _policy("if_none_match")})
    headers = signed.header_map()
    if "x-amz-security-token" in headers:         # pragma: no cover
        raise SafetyBarrierTripped(
            "a security token reached a parent-authenticated request")
    expected = ("host", "if-none-match", "x-amz-content-sha256", "x-amz-date")
    if tuple(signed.signed_header_names) != expected:
        raise SafetyBarrierTripped(
            f"unexpected SignedHeaders {list(signed.signed_header_names)}")
    return signed


class TransportOutcome(NamedTuple):
    status: object                 # int, or None on a transport failure
    headers: tuple                 # ((lowercase-name, value), ...)
    body: bytes
    body_truncated: bool
    failure_category: object       # str, or None
    t_request_attempt_mono_ns: int


class OneShotTransport:
    """Sends AT MOST ONE request, ever.

    The latch is set BEFORE any I/O is attempted, so even a crash inside
    `conn.request` leaves this object permanently spent. There is no
    retry, no redirect following, no fallback and no verification request:
    `send_once` is the only method that can reach a socket, and it can
    succeed at most once per instance.
    """

    def __init__(self, *, endpoint_host, connection_factory,
                 monotonic=time.monotonic_ns):
        if type(endpoint_host) is not str:
            raise EndpointRefused("endpoint host must be exactly str")
        if not callable(connection_factory):
            raise SafetyBarrierTripped("connection factory must be callable")
        self.endpoint_host = endpoint_host
        self._factory = connection_factory
        self._monotonic = monotonic
        self._lock = threading.Lock()
        self._spent = False

    @property
    def spent(self) -> bool:
        return self._spent

    def send_once(self, signed, *, on_attempt_boundary=None
                  ) -> TransportOutcome:
        """Send the one request.

        `on_attempt_boundary` is invoked AFTER the latch is consumed and
        the connection has been obtained, but BEFORE `conn.request`. If it
        raises, `conn.request` is never called — so a durable attempt
        marker is a precondition of the request, not a best-effort
        companion to it. A factory failure happens first and therefore
        never produces a marker claiming a request may have occurred.
        """
        with self._lock:
            if self._spent:
                raise SafetyBarrierTripped(
                    "this harness may attempt exactly one request")
            self._spent = True          # latched BEFORE any I/O
        url = "/" + signed.target.bucket + "/" + signed.target.key
        headers = dict(signed.headers)
        attempt_ns = self._monotonic()
        conn = None
        try:
            conn = self._factory(self.endpoint_host)
        except Exception as exc:        # noqa: BLE001 - category only
            return TransportOutcome(
                status=None, headers=(), body=b"", body_truncated=False,
                failure_category=type(exc).__name__,
                t_request_attempt_mono_ns=attempt_ns)
        try:
            if on_attempt_boundary is not None:
                # Deliberately OUTSIDE the try/except below: a failure to
                # journal must propagate, not be classified as a
                # transport failure that implies a request happened.
                on_attempt_boundary()
        except BaseException:
            try:
                conn.close()
            except Exception:           # pragma: no cover - best effort
                pass
            raise
        try:
            conn.request(signed.target.method, url, body=signed.body,
                         headers=headers)
            response = conn.getresponse()
            limit = _policy("max_response_bytes")
            body = response.read(limit + 1)
            truncated = len(body) > limit
            if truncated:
                body = body[:limit]
            pairs = tuple((str(name).lower(), str(value))
                          for name, value in response.getheaders())
            return TransportOutcome(
                status=int(response.status), headers=pairs, body=body,
                body_truncated=truncated, failure_category=None,
                t_request_attempt_mono_ns=attempt_ns)
        except Exception as exc:        # noqa: BLE001 - category only
            return TransportOutcome(
                status=None, headers=(), body=b"", body_truncated=False,
                failure_category=type(exc).__name__,
                t_request_attempt_mono_ns=attempt_ns)
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:       # pragma: no cover - best effort
                    pass


def live_connection_factory(host):     # pragma: no cover - live only
    """Built ONLY after every gate has passed. `http.client` is imported
    here so plan mode never even loads it, and it neither follows
    redirects nor retries."""
    import http.client
    import ssl
    context = ssl.create_default_context()
    return http.client.HTTPSConnection(
        host, timeout=_policy("connect_timeout_seconds"), context=context)


# ─────────────────────────────────────────────────────────────────────────
# Evidence
# ─────────────────────────────────────────────────────────────────────────

#: Every field this harness may persist. Nothing outside this set reaches
#: disk, which is what keeps credential material out of the evidence by
#: construction rather than by review.
PARENT_CONTROL_FIELDS = frozenset({
    "record_kind", "run_id", "verdict", "bucket", "key", "method", "query",
    "body_len", "body_sha256", "if_none_match", "signed_header_names",
    "session_token_present", "x_amz_security_token_present",
    "t_request_attempt_mono_ns", "http_status", "error_code",
    "error_message", "error_argument", "message_omitted", "cf_ray",
    "request_id", "response_body_len", "response_body_sha256",
    "response_body_truncated", "transport_failure_category",
    "production_contacted",
})

#: Substrings that must never appear as a persisted field name. The record
#: builder is closed, so this is a belt-and-braces assertion.
_FORBIDDEN_FIELD_TOKENS = ("authorization", "secret", "signature",
                           "canonical", "string_to_sign", "session_token_value",
                           "access_key_id", "jwt", "credential_file")


def build_parent_control_record(*, run_id, signed, outcome, verdict,
                                secrets) -> dict:
    """The ONE evidence record. Derived entirely from the signed request
    and the response — never from the caller's credential.

    The live path holds the real access key and secret at this point, so
    they are passed INTO the parser and the sanitizer: a response that
    echoes credential material must be redacted at the point the text is
    first interpreted, not merely caught at the write boundary.
    """
    materials = tuple(s for s in secrets if type(s) is str and s)
    if not materials:
        raise SafetyBarrierTripped(
            "record construction requires the known secrets for redaction")
    headers = signed.header_map()
    parsed = None
    if outcome.body:
        parsed = parse_s3_error(outcome.body,
                                truncated=outcome.body_truncated,
                                secrets=materials)
    header_map = dict(outcome.headers)
    message, omitted = (safe_error_message(parsed.message, materials)
                        if parsed is not None and parsed.message is not None
                        else (None, False))
    # Response-controlled identifiers are bounded before they are recorded.
    cf_ray = header_map.get("cf-ray")
    request_id = parsed.request_id if parsed is not None else None
    assert_response_identifier_is_safe(cf_ray, "cf_ray")
    assert_response_identifier_is_safe(request_id, "request_id")
    record = {
        "record_kind": "PARENT_CONTROL_RECORD",
        "run_id": run_id,
        "verdict": verdict,
        "bucket": signed.target.bucket,
        "key": signed.target.key,
        "method": signed.target.method,
        "query": [[name, value] for name, value in signed.target.query],
        "body_len": len(signed.body),
        "body_sha256": _sha256_hex(signed.body),
        "if_none_match": headers.get("if-none-match"),
        "signed_header_names": list(signed.signed_header_names),
        # The two facts this whole harness exists to record.
        "session_token_present": False,
        "x_amz_security_token_present": "x-amz-security-token" in headers,
        "t_request_attempt_mono_ns": outcome.t_request_attempt_mono_ns,
        "http_status": outcome.status,
        "error_code": parsed.code if parsed is not None else None,
        "error_message": message,
        "error_argument": (safe_error_argument(parsed.message)
                           if parsed is not None
                           and parsed.message is not None else None),
        "message_omitted": omitted,
        "cf_ray": cf_ray,
        "request_id": request_id,
        "response_body_len": len(outcome.body),
        "response_body_sha256": (_sha256_hex(outcome.body)
                                 if outcome.body else None),
        "response_body_truncated": outcome.body_truncated,
        "transport_failure_category": outcome.failure_category,
        # Proven, not asserted: the only bucket this harness can name.
        "production_contacted": False,
    }
    assert_record_is_safe(record)
    # THE confidentiality boundary, applied before this record can be
    # persisted OR rendered.
    assert_no_transformed_secret(record, materials, "PARENT_CONTROL_RECORD")
    return record


def assert_record_is_safe(record) -> None:
    """Fail closed if the record gained an unexpected or unsafe field."""
    if type(record) is not dict:
        raise SafetyBarrierTripped("record must be exactly dict")
    extra = set(record) - PARENT_CONTROL_FIELDS
    if extra:
        raise SafetyBarrierTripped(
            f"record fields not allowed: {sorted(extra)}")
    missing = PARENT_CONTROL_FIELDS - set(record)
    if missing:
        raise SafetyBarrierTripped(
            f"record is missing required fields: {sorted(missing)}")
    for name in record:
        folded = name.casefold()
        for token in _FORBIDDEN_FIELD_TOKENS:
            if token in folded:
                raise SafetyBarrierTripped(
                    f"record field {name!r} names credential material")
    if record["x_amz_security_token_present"] is not False:
        raise SafetyBarrierTripped(
            "a parent-control record may not report a security token")
    if record["session_token_present"] is not False:
        raise SafetyBarrierTripped(
            "a parent-control record may not report a session token")
    assert_no_production_name(record["bucket"], record["key"])


def assert_no_secret_material(record, secrets) -> None:
    """Refuse to persist a record containing any known secret value, in
    exact OR transformed form. Thin alias kept so the write path reads as
    one obvious boundary call."""
    assert_no_transformed_secret(record, secrets, "PARENT_CONTROL_RECORD")


#: The pre-request attempt journal. Written and fsync'd BEFORE
#: `conn.request` is ever called, so a confidentiality rejection of the
#: RESPONSE can never erase the fact that a request may have been made.
ATTEMPT_RECORD_FILENAME = "parent_control_attempt.json"
ATTEMPT_ANCHOR_FILENAME = "parent_control_attempt.sha256"
TERMINAL_RECORD_FILENAME = "parent_control_terminal.json"

#: The attempt record carries NO response-controlled text, by
#: construction: it is written before any response exists.
ATTEMPT_RECORD_FIELDS = frozenset({
    "record_kind", "run_id", "bucket", "key", "method", "query", "body_len",
    "body_sha256", "if_none_match", "signed_header_names",
    "session_token_present", "x_amz_security_token_present",
    "request_attempt_boundary_timestamp", "request_may_have_been_attempted",
})

#: The terminal record written when a response is REFUSED for
#: confidentiality. Deliberately excludes cf_ray, request_id, error
#: message and error argument — every response-controlled string.
TERMINAL_RECORD_FIELDS = frozenset({
    "record_kind", "run_id", "terminal_category", "http_status",
    "response_body_len", "response_body_sha256", "response_body_truncated",
    "transport_failure_category",
})


class ParentControlEvidence:
    """Create-only private evidence, anchored to a verified directory FD.

    Every mkdir/open below the root uses `dir_fd`, so once the root
    descriptor has been validated the writes cannot be redirected by
    swapping a path component — the pathname strings are never re-resolved
    from the filesystem root. 0700 directories, 0600 files, O_EXCL,
    O_NOFOLLOW, and no delete/move/replace anywhere in this module.
    """

    def __init__(self, root_fd, run_id, *, owns_fd=True):
        if type(root_fd) is not int:
            raise SafetyBarrierTripped(
                "evidence requires a verified root directory descriptor")
        if type(run_id) is not str \
                or not _CONTROL_RUN_ID_RE.fullmatch(run_id):
            raise SafetyBarrierTripped("control run id refused")
        self.run_id = run_id
        self._root_fd = root_fd
        self._owns_root_fd = owns_fd
        # DISPLAY ONLY. Every write is anchored to a directory descriptor;
        # these strings are never reopened, so they cannot redirect a write.
        self.root_path = canonical_evidence_root()
        self.run_dir = os.path.join(self.root_path,
                                    _policy("evidence_dirname"), run_id)
        self.anchor_dir = os.path.join(self.root_path,
                                       _policy("anchor_dirname"))
        _verify_directory_fd(root_fd, what="the evidence root",
                             exact_mode=0o700)
        self._evidence_fd = self._child_dir(root_fd,
                                            _policy("evidence_dirname"))
        self._anchor_fd = self._child_dir(root_fd, _policy("anchor_dirname"))
        # Create-only: an existing control run id is a hard error, so a
        # previous control can never be overwritten. The run directory is
        # ALWAYS fresh, so its parent entry is ALWAYS fsynced — and that
        # fsync must succeed before any request can be made.
        self._run_fd, created = open_or_create_verified_directory(
            self._evidence_fd, run_id, what="the control run directory",
            exact_mode=0o700, must_be_new=True)
        if not created:          # pragma: no cover - must_be_new raises
            raise SafetyBarrierTripped("the control run directory existed")

    @staticmethod
    def _child_dir(parent_fd, name):
        fd, _created = open_or_create_verified_directory(
            parent_fd, name, what=f"evidence subdirectory {name!r}",
            exact_mode=0o700)
        return fd

    @classmethod
    def at_live_root(cls, run_id):
        """The ONE constructor the live path uses."""
        return cls(open_live_evidence_root(), run_id, owns_fd=True)

    def close(self):
        for attr in ("_run_fd", "_anchor_fd", "_evidence_fd"):
            fd = getattr(self, attr, None)
            if fd is not None:
                os.close(fd)
                setattr(self, attr, None)
        if self._owns_root_fd and self._root_fd is not None:
            os.close(self._root_fd)
            self._root_fd = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def _write_private(self, name, payload, *, dir_fd):
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_NOFOLLOW", 0)
        previous = os.umask(0o077)
        try:
            fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
        finally:
            os.umask(previous)
        try:
            view = memoryview(payload)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise SafetyBarrierTripped("os.write made no progress")
                view = view[written:]
            os.fsync(fd)
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) \
                    or stat.S_IMODE(st.st_mode) & 0o077:
                raise SafetyBarrierTripped(
                    f"{name!r} did not end up a private regular file")
        finally:
            os.close(fd)
        os.fsync(dir_fd)
        return name

    def _serialize(self, obj) -> bytes:
        return json.dumps(obj, sort_keys=True, indent=2,
                          ensure_ascii=False).encode("utf-8")

    # ── stage 1: the pre-request attempt journal ─────────────────────────

    def write_attempt_record(self, record) -> str:
        """Persist and fsync the safe attempt marker, plus its OWN
        integrity artifact, so it is independently verifiable without the
        final manifest — which may never be written."""
        if type(record) is not dict:
            raise SafetyBarrierTripped("attempt record must be a dict")
        if set(record) != ATTEMPT_RECORD_FIELDS:
            raise SafetyBarrierTripped(
                "attempt record fields are not exactly the allowed set")
        if record["record_kind"] != "PARENT_CONTROL_ATTEMPT_RECORD" \
                or record["request_may_have_been_attempted"] is not True \
                or record["session_token_present"] is not False \
                or record["x_amz_security_token_present"] is not False:
            raise SafetyBarrierTripped("attempt record facts are wrong")
        assert_no_production_name(record["bucket"], record["key"])
        payload = self._serialize(record)
        self._write_private(ATTEMPT_RECORD_FILENAME, payload,
                            dir_fd=self._run_fd)
        digest = hashlib.sha256(payload).hexdigest()
        self._write_private(ATTEMPT_ANCHOR_FILENAME,
                            (digest + "\n").encode("ascii"),
                            dir_fd=self._run_fd)
        return digest

    # ── stage 2: terminal records ────────────────────────────────────────

    def write_terminal_record(self, record) -> str:
        """A generic terminal record for a response that was REFUSED.

        Carries only locally derived facts; every response-controlled
        string is excluded by the field set itself.
        """
        if type(record) is not dict or set(record) != TERMINAL_RECORD_FIELDS:
            raise SafetyBarrierTripped(
                "terminal record fields are not exactly the allowed set")
        payload = self._serialize(record)
        self._write_private(TERMINAL_RECORD_FILENAME, payload,
                            dir_fd=self._run_fd)
        return hashlib.sha256(payload).hexdigest()

    def write(self, record, *, secrets=()) -> dict:
        """Persist the result record, its manifest and its anchor."""
        assert_record_is_safe(record)
        assert_no_secret_material(record, secrets)
        payload = self._serialize(record)
        name = _policy("record_filename")
        self._write_private(name, payload, dir_fd=self._run_fd)
        manifest = {"run_id": self.run_id,
                    "files": {name: hashlib.sha256(payload).hexdigest()},
                    "verdict": record["verdict"]}
        manifest_bytes = self._serialize(manifest)
        self._write_private(_policy("manifest_filename"), manifest_bytes,
                            dir_fd=self._run_fd)
        manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
        anchor_name = f"{self.run_id}.sha256"
        self._write_private(anchor_name, (manifest_sha256 + "\n").encode(),
                            dir_fd=self._anchor_fd)
        return {"manifest_name": _policy("manifest_filename"),
                "manifest_sha256": manifest_sha256,
                "anchor_name": anchor_name,
                "record_name": name,
                # Display-only paths, for the console and for inspection.
                "run_dir": self.run_dir,
                "record_path": os.path.join(self.run_dir, name),
                "manifest_path": os.path.join(
                    self.run_dir, _policy("manifest_filename")),
                "anchor_path": os.path.join(self.anchor_dir, anchor_name)}


# ─────────────────────────────────────────────────────────────────────────
# Verdict
# ─────────────────────────────────────────────────────────────────────────

def derive_verdict(outcome) -> str:
    """SUCCESS / R2_REJECTED / TRANSPORT_FAILURE / INCOMPLETE.

    Deliberately NOT a CAS verdict: this harness tests one request's
    authentication, never conditional-write semantics.
    """
    if type(outcome) is not TransportOutcome:
        raise SafetyBarrierTripped("verdict requires a TransportOutcome")
    if outcome.failure_category is not None:
        return "TRANSPORT_FAILURE"
    if outcome.status is None:
        return "INCOMPLETE"
    if 200 <= outcome.status < 300:
        return "SUCCESS"
    return "R2_REJECTED"


_VERDICT_EXIT = {"SUCCESS": EXIT_SUCCESS,
                 "R2_REJECTED": EXIT_R2_REJECTED,
                 "TRANSPORT_FAILURE": EXIT_TRANSPORT_FAILURE,
                 "INCOMPLETE": EXIT_INCOMPLETE}

INTERPRETATION = """\
INTERPRETATION (fixed in advance, so a result cannot be read to taste):

  SUCCESS (2xx)
    A parent-authenticated PutObject works against the disposable bucket.
    Endpoint, SigV4 construction, PutObject, the 256-byte body path and
    If-None-Match: * are substantially validated. The temporary-credential
    / session-token layer becomes the leading fault domain. This does NOT
    identify a local JWT root cause.

  R2_REJECTED with 400 InvalidArgument
    The failure survives removal of the entire temporary-credential layer.
    The common request/signing/conditional-header path becomes the leading
    fault domain. A 400 here does NOT authorize a follow-up plain PUT: any
    second live comparison requires NEW explicit authorization.

  R2_REJECTED with 401/403
    Parent permission/authentication assumptions need review. This is NOT
    a CAS result.

  Anything else
    Freeze and review before acting.

This harness does not test the Gate D matrix and cannot produce a CAS
PASS/FAIL."""


def render_plan(*, bucket, account_id, evidence_root) -> str:
    lines = [
        "Bible PAL — R2 PARENT-CREDENTIAL CONTROL (PLAN MODE)",
        "=" * 62,
        "NO SOCKETS ARE OPENED IN THIS MODE.",
        "NO CREDENTIAL FILE IS READ IN THIS MODE.",
        "NO EVIDENCE IS CREATED IN THIS MODE.",
        "LIVE PARENT CONTROL NOT PERFORMED IN PLAN MODE.",
        "",
        f"  control bucket   : {_policy('bucket')} (immutable policy constant)",
        f"  denied names     : {list(_policy('denied_tokens'))}",
        f"  requested bucket : {bucket!r}",
        f"  account id given : {'yes' if account_id else 'no'}"
        " (value not echoed)",
        f"  evidence root    : {evidence_root!r}",
        f"  key shape        : {_policy('key_prefix')}<control-run-id>/"
        f"{_policy('key_leaf')}",
        "",
        "The ONE request this harness can ever make:",
        "  method                : PUT",
        f"  body                  : exactly {_policy('body_bytes')} bytes",
        "  query                 : none",
        f"  conditional header    : If-None-Match: {_policy('if_none_match')}",
        "  SigV4                 : AWS4-HMAC-SHA256, region auto, service s3",
        "  SignedHeaders         : host, if-none-match, x-amz-content-sha256,"
        " x-amz-date",
        "  x-amz-security-token  : ABSENT (parent credential, not temporary)",
        "  session token         : ABSENT",
        "  JWT                   : ABSENT",
        "",
        "At most ONE HTTP request per invocation. No retry, no redirect",
        "following, no fallback, no verification request, no cleanup.",
        "",
        "Execution requires ALL of: --execute --authorized-by-adam"
        " --confirm <exact string>",
        f"  --bucket {_policy('bucket')} --account-id <32 lowercase hex>",
        "  --credentials-file <path> --evidence-root <path>",
        "",
        INTERPRETATION,
        "",
        "It NEVER touches production; production R2 publication remains"
        " BLOCKED.",
    ]
    return "\n".join(lines)


def render_result(*, run_id, paths, record) -> str:
    return "\n".join([
        "Bible PAL — R2 PARENT-CREDENTIAL CONTROL (LIVE RESULT)",
        "=" * 62,
        f"  run id          : {run_id}",
        f"  evidence dir    : {paths['run_dir']}",
        f"  manifest sha256 : {paths['manifest_sha256']}",
        f"  bucket / key    : {record['bucket']} / {record['key']}",
        f"  http status     : {record['http_status']}",
        f"  error code      : {record['error_code']}",
        f"  error message   : {record['error_message']!r}",
        f"  error argument  : {record['error_argument']!r}",
        f"  cf-ray          : {record['cf_ray']}",
        f"  body len/sha256 : {record['response_body_len']} /"
        f" {record['response_body_sha256']}",
        f"  transport failure: {record['transport_failure_category']}",
        f"  security token  : {record['x_amz_security_token_present']}"
        " (must be False)",
        "",
        f"  VERDICT         : {record['verdict']}",
        "  This is NOT a CAS result. Production R2 publication remains"
        " BLOCKED.",
    ])


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="R2 parent-credential control. Plan/offline by default.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--plan", action="store_true",
                      help="default: describe the control, open zero sockets")
    mode.add_argument("--execute", action="store_true",
                      help="send the ONE parent-authenticated PutObject "
                           "(requires every authorization gate)")
    # NO DEFAULTS for --bucket or --evidence-root: a live argument that can
    # be omitted is not part of an explicit authorization. Plan mode
    # displays the immutable policy values instead.
    parser.add_argument("--bucket")
    parser.add_argument("--account-id")
    parser.add_argument("--confirm")
    parser.add_argument("--authorized-by-adam", action="store_true")
    parser.add_argument("--credentials-file")
    parser.add_argument("--evidence-root")
    return parser


def build_attempt_record(*, run_id, signed) -> dict:
    """The safe pre-request marker. Contains no response-controlled text
    because it is built before any response exists."""
    headers = signed.header_map()
    return {
        "record_kind": "PARENT_CONTROL_ATTEMPT_RECORD",
        "run_id": run_id,
        "bucket": signed.target.bucket,
        "key": signed.target.key,
        "method": signed.target.method,
        "query": [[name, value] for name, value in signed.target.query],
        "body_len": len(signed.body),
        "body_sha256": _sha256_hex(signed.body),
        "if_none_match": headers.get("if-none-match"),
        "signed_header_names": list(signed.signed_header_names),
        "session_token_present": False,
        "x_amz_security_token_present": "x-amz-security-token" in headers,
        "request_attempt_boundary_timestamp": time.time_ns(),
        # Deliberately conservative: reaching this boundary does not prove
        # the bytes left the machine, only that they may have.
        "request_may_have_been_attempted": True,
    }


def build_terminal_record(*, run_id, outcome, category) -> dict:
    """Locally derived facts only — no cf_ray, request_id, error message
    or error argument from a response we refused to trust."""
    return {
        "record_kind": "PARENT_CONTROL_TERMINAL_RECORD",
        "run_id": run_id,
        "terminal_category": category,
        "http_status": (outcome.status if type(outcome.status) is int
                        else None),
        "response_body_len": len(outcome.body),
        "response_body_sha256": (_sha256_hex(outcome.body)
                                 if outcome.body else None),
        "response_body_truncated": outcome.body_truncated,
        "transport_failure_category": outcome.failure_category,
    }


def run_control(*, gates, connection_factory, now=None,
                run_id=None) -> tuple:
    """THE one complete live orchestration path.

    There is deliberately no second function that assembles credential +
    evidence root + connection factory into a request (Codex round-2
    MEDIUM 2): such a helper is a live-capable API without authorization,
    however it is named. Tests drive THIS function, redirecting HOME so
    the canonical root resolves inside a sandbox — which exercises the
    real order rather than a parallel imitation of it.

    Order:
      authorization gates
      → canonical physical evidence-root acquisition
      → credential metadata + read
      → exact request construction
      → durable pre-request attempt journal
      → the one-shot request
      → confidentiality-validated response handling
      → final evidence
    """
    gates.assert_may_execute()
    assert_evidence_root_is_canonical(gates.evidence_root)
    credential = read_parent_credentials(gates.credentials_file)
    secrets = (credential.access_key_id, credential.secret_access_key)
    run_id = new_control_run_id() if run_id is None else run_id
    epoch = int(time.time()) if now is None else int(now)
    amz_date = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(epoch))
    signed = build_control_request(credential=credential,
                                   account_id=gates.account_id,
                                   run_id=run_id, amz_date=amz_date)
    with ParentControlEvidence.at_live_root(run_id) as evidence:
        transport = OneShotTransport(
            endpoint_host=build_endpoint_host(gates.account_id),
            connection_factory=connection_factory)
        outcome = transport.send_once(
            signed,
            on_attempt_boundary=lambda: evidence.write_attempt_record(
                build_attempt_record(run_id=run_id, signed=signed)))
        verdict = derive_verdict(outcome)
        try:
            record = build_parent_control_record(
                run_id=run_id, signed=signed, outcome=outcome,
                verdict=verdict, secrets=secrets)
        except (EvidenceValidationError, SafetyBarrierTripped):
            # The response could not be shown to be free of credential
            # material. Keep the durable attempt marker, add a generic
            # terminal record, and surface NOTHING from the response.
            evidence.write_terminal_record(build_terminal_record(
                run_id=run_id, outcome=outcome,
                category="RESULT_WITHHELD_FOR_CONFIDENTIALITY"))
            raise ConfidentialityWithheld(
                "response diagnostics withheld by confidentiality boundary")
        paths = evidence.write(record, secrets=secrets)
    return record, paths


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        assert_no_production_name(args.bucket, args.account_id,
                                  args.credentials_file, args.evidence_root)
        if not args.execute:
            # Plan mode displays the immutable policy values when the
            # caller supplied none; it never needs a live argument.
            print(render_plan(
                bucket=args.bucket or _policy("bucket"),
                account_id=args.account_id,
                evidence_root=args.evidence_root
                or canonical_evidence_root()))
            return EXIT_SUCCESS
        gates = ExecutionGates(
            execute=True, authorized_by_adam=bool(args.authorized_by_adam),
            confirmation=args.confirm, bucket=args.bucket,
            account_id=args.account_id,
            credentials_file=args.credentials_file,
            evidence_root=args.evidence_root)
        record, paths = run_control(
            gates=gates, connection_factory=live_connection_factory)
        print(render_result(run_id=record["run_id"], paths=paths,
                            record=record))
        return _VERDICT_EXIT[record["verdict"]]
    except ConfidentialityWithheld:
        # GENERIC by construction. `str(exc)` is a fixed string and no
        # response-controlled content is interpolated, so this cannot leak
        # what was rejected. An expected safety refusal, not a crash: no
        # traceback.
        print("REFUSED: response diagnostics withheld by confidentiality "
              "boundary")
        return EXIT_REFUSED
    except EvidenceValidationError:
        # Same class of refusal reached outside run_control; still generic.
        print("REFUSED: evidence withheld by confidentiality boundary")
        return EXIT_REFUSED
    except (ProductionNameDetected, MissingAuthorization, EndpointRefused,
            SafetyBarrierTripped, ParentControlRefused) as exc:
        print(f"REFUSED [{type(exc).__name__}]: {exc}")
        return EXIT_REFUSED


if __name__ == "__main__":   # pragma: no cover
    raise SystemExit(main())
