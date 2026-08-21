#!/usr/bin/env python3
"""Disposable R2 compare-and-swap probe — OFFLINE-CAPABLE IMPLEMENTATION.

Implements the accepted REVISED DISPOSABLE CAS PROBE PLAN, corrected per
two rounds of Codex implementation audit. This module is NOT the
production catalog publisher and must never become one: it exists solely
to establish, against a DISPOSABLE bucket, whether R2's S3-compatible
`PutObject` honours `If-Match` / `If-None-Match` preconditions atomically,
and whether our own signer, credential derivation and reconciliation
logic are correct.

STATUS: production R2 publication remains BLOCKED. Nothing here publishes
anything, and nothing here may be pointed at production. `--execute` is
disabled unconditionally — see `main()`.

╔══════════════════════════════════════════════════════════════════════╗
║ THREAT MODEL — READ THIS BEFORE REVIEWING THE BARRIERS               ║
╠══════════════════════════════════════════════════════════════════════╣
║ IN SCOPE. Accidental or ordinary rebinding of exported, public-       ║
║ looking configuration/policy NAMES on this module — e.g. a caller     ║
║ (or a careless future edit) doing                                     ║
║     probe.PROBE_BUCKET = "bible-pal-audio"                            ║
║ must have NO effect on live target enforcement, credential claims,    ║
║ evidence safety, key allocation, endpoint checks or resource caps.    ║
║                                                                       ║
║ HOW THAT IS ACHIEVED. Every policy value is captured ONCE, at import, ║
║ inside a closure (`_policy()`), in an immutable `typing.NamedTuple`.  ║
║ Enforcement reads policy ONLY through that closure — never through a  ║
║ module global. The exported constants below are DISPLAY/TEST ALIASES; ║
║ rebinding them changes nothing that matters. Additionally, every      ║
║ security-relevant record type is a NamedTuple rather than a frozen    ║
║ dataclass, so `object.__setattr__` cannot mutate a validated object   ║
║ after construction (tuples have no writable slots).                   ║
║                                                                       ║
║ OUT OF SCOPE. An adversary who can monkeypatch functions, rewrite     ║
║ `__code__`, replace builtins, or inject bytecode inside this process. ║
║ That is arbitrary code execution and no in-process guard can survive  ║
║ it. The eventual live probe MUST run in a clean, dedicated process    ║
║ from the reviewed module, so arbitrary in-process code injection is   ║
║ not an accepted threat.                                               ║
╚══════════════════════════════════════════════════════════════════════╝

DEFAULT MODE IS `--plan`: it opens ZERO sockets. The default connection
factory REFUSES to construct a connection, so "plan mode does not touch
the network" is a property of construction rather than a promise.

SIGN-TO-SEND BINDING. The future live primitive is
`R2Transport.sign_and_send(...)`: it validates its inputs, signs
internally, and transmits the exact bytes it just signed, with no
caller-visible mutable request object in between. `send_signed_offline`
exists ONLY for offline tests of the lower-level signer and is never the
live path.

WHAT THIS MODULE DELIBERATELY DOES NOT CONTAIN
  - multipart upload of any kind
  - CopyObject
  - DeleteObject as a normal operation (modelled as a denied probe only)
  - any production key name, bucket name or endpoint default
  - any retry of an ambiguous PutObject
  - any general-purpose credential minting
  - any live execution path
"""

from __future__ import annotations

import argparse
import base64
import binascii
import enum
import hashlib
import hmac
import json
import math
import os
import re
import ssl
import stat
import sys
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET
from typing import Callable, Iterable, Mapping, NamedTuple, Sequence

# ─────────────────────────────────────────────────────────────────────────
# Exit codes
# ─────────────────────────────────────────────────────────────────────────

EXIT_OK = 0
EXIT_TEST_FAILURE = 10
EXIT_ABANDON = 20
EXIT_PRODUCTION_NAME_DETECTED = 90
EXIT_ENDPOINT_REFUSED = 91
EXIT_MISSING_AUTHORIZATION = 92
EXIT_CAP_EXCEEDED = 93
EXIT_SAFETY_BARRIER = 94


class ProbeError(Exception):
    """Base class. Every subclass carries a fixed exit code."""

    exit_code = EXIT_SAFETY_BARRIER


class ProductionNameDetected(ProbeError):
    exit_code = EXIT_PRODUCTION_NAME_DETECTED


class EndpointRefused(ProbeError):
    exit_code = EXIT_ENDPOINT_REFUSED


class MissingAuthorization(ProbeError):
    exit_code = EXIT_MISSING_AUTHORIZATION


class CapExceeded(ProbeError):
    exit_code = EXIT_CAP_EXCEEDED


class SafetyBarrierTripped(ProbeError):
    exit_code = EXIT_SAFETY_BARRIER


class EvidenceValidationError(ProbeError):
    exit_code = EXIT_SAFETY_BARRIER


# ─────────────────────────────────────────────────────────────────────────
# Exact-type helpers
#
# Security-sensitive values must be EXACT built-in types. isinstance() is
# not enough: a str subclass can compare equal to the probe bucket while
# formatting as the production bucket. `type(x) is str` refuses that class
# of confusion outright.
# ─────────────────────────────────────────────────────────────────────────

def _exact(value, expected_type, name: str):
    if type(value) is not expected_type:
        raise SafetyBarrierTripped(
            f"{name} must be exactly {expected_type.__name__}, "
            f"got {type(value).__name__}")
    return value


def _exact_str(value, name: str, *, max_len: int = 4096,
               allow_empty: bool = False) -> str:
    _exact(value, str, name)
    if not allow_empty and value == "":
        raise SafetyBarrierTripped(f"{name} must not be empty")
    if len(value) > max_len:
        raise SafetyBarrierTripped(f"{name} exceeds {max_len} characters")
    return value


def _exact_int(value, name: str, *, minimum=None, maximum=None) -> int:
    _exact(value, int, name)  # bool is excluded: type(True) is bool
    if minimum is not None and value < minimum:
        raise SafetyBarrierTripped(f"{name} must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise SafetyBarrierTripped(f"{name} must be <= {maximum}")
    return value


def _exact_opt_int(value, name: str, *, minimum=None, maximum=None):
    if value is None:
        return None
    return _exact_int(value, name, minimum=minimum, maximum=maximum)


def _exact_bool(value, name: str) -> bool:
    _exact(value, bool, name)
    return value


def _exact_bytes(value, name: str, *, max_len: int) -> bytes:
    _exact(value, bytes, name)
    if len(value) > max_len:
        raise SafetyBarrierTripped(f"{name} exceeds {max_len} bytes")
    return value


def _no_ctl(value: str, name: str, *, allow_tab: bool = False) -> str:
    banned = "\x00\r\n" if allow_tab else "\x00\r\n\t"
    if any(ch in value for ch in banned):
        raise SafetyBarrierTripped(f"{name} contains a control character")
    return value


# ─────────────────────────────────────────────────────────────────────────
# THE IMMUTABLE POLICY (Codex BLOCKER 1)
#
# Captured once, at import, inside a closure. Enforcement reads it ONLY
# via `_policy()`. Rebinding any exported constant below cannot reach it,
# and every field is a str/int/tuple inside a NamedTuple, so nothing here
# can be mutated in place either.
# ─────────────────────────────────────────────────────────────────────────

class TestSpec(NamedTuple):
    """One row of the single source of truth (Codex MEDIUM 2)."""

    id: str
    group: str
    category: str            # semantic | race | scope | signing | absence
                             # | shape | archive | audit | integrity
    cost_seconds: float
    required_repetitions: int
    max_attempts: int
    production_size_repetitions: int
    description: str
    #: The setup state a race repetition must prove before its writers are
    #: released. Non-None for EXACTLY the category=="race" rows (Codex
    #: MEDIUM 2); the old parallel race_setup_by_test mapping is deleted.
    race_setup_state: str | None = None


class _Caps(NamedTuple):
    max_production_size_puts: int
    max_put_attempts: int
    max_get_head: int
    max_object_keys: int
    max_uploaded_bytes: int
    max_peak_storage_bytes: int


class _Policy(NamedTuple):
    bucket: str
    denied_tokens: tuple
    key_prefix: str
    sacrificial_key: str
    denied_out_of_prefix_key: str
    production_body_bytes: int
    credential_scope: str
    credential_actions: tuple
    credential_prefixes: tuple
    credential_object_paths: tuple
    group_ttl_seconds: int
    expiry_group_ttl_seconds: int
    expiry_group: str
    execute_confirmation: str
    allowed_extra_headers: frozenset
    transport_owned_headers: frozenset
    # The COMPLETE set of header names permitted on the wire at the live
    # transmit boundary. Anything outside it — x-amz-copy-source, x-amz-acl,
    # x-amz-website-redirect-location, multipart headers, any unknown
    # x-amz-* mutation header — is refused BEFORE a socket, so a caller
    # cannot smuggle a dangerous header through even a hand-built request.
    wire_header_allowlist: frozenset
    caps: _Caps
    matrix: tuple            # tuple[TestSpec, ...]
    # Load-bearing transport/parse constants live here too (BLOCKER 2), so
    # enforcement never reads a rebindable module global for any of them.
    sigv4_service: str
    r2_region: str
    multipart_query_markers: tuple
    max_error_body_bytes: int
    max_response_body_bytes: int
    max_evidence_file_bytes: int
    scrub_exact: tuple
    scrub_prefixes: tuple
    # Timing / freshness limits (LOW + HIGH 2 + MEDIUM 1), captured here so
    # they are not mutable class-level policy.
    same_key_min_gap_seconds: float
    credential_safety_factor: float
    credential_required_margin_seconds: float
    expiry_max_age_seconds: float
    max_race_send_skew_ns: int
    max_amz_date_skew_seconds: int


def _capture_policy():
    """Build the policy instance ONCE and return an accessor bound to that
    exact instance (BLOCKER 1).

    The whole `_Policy(...)` is constructed here, at import, and bound to a
    local. The returned accessor closes over THAT object via a default
    argument, so `_policy()` returns the same instance on every call and
    rebinding `probe._Policy`, `probe.TestSpec`, `probe._Caps` or any
    exported alias after import has no effect on enforcement. (Replacing
    `_policy` itself, or a function's `__code__`, is arbitrary code
    injection and remains out of scope — see the module header.)
    """
    production_body_bytes = 2_589_207
    matrix = (
        # id      group      category    cost req att prod  description
        TestSpec("A", "T-CAS-1", "semantic-support", 60.0, 10, 20, 0,
                 "correct ETag + If-Match -> 2xx + exact raw-byte read-back"),
        TestSpec("B", "T-CAS-1", "semantic", 90.0, 10, 20, 3,
                 "stale ETag + If-Match -> 412 on EVERY valid repetition"),
        TestSpec("C", "T-CAS-1", "semantic-support", 30.0, 10, 20, 0,
                 "absent key + If-None-Match:* -> 2xx + exact raw-byte read-back"),
        TestSpec("D", "T-CAS-2", "semantic", 70.0, 10, 20, 3,
                 "existing key + If-None-Match:* -> 412 on EVERY valid rep"),
        TestSpec("E1", "T-CAS-2", "semantic", 100.0, 10, 20, 3,
                 "delayed stale writer -> 412 on EVERY valid repetition"),
        TestSpec("G", "T-CAS-2", "integrity", 30.0, 5, 10, 0,
                 "PUT ETag reappears byte-exactly on read-back"),
        TestSpec("E2", "T-RACE", "race", 120.0, 30, 45, 3,
                 "simultaneous writers -> exactly one mutation",
                 race_setup_state="SEEDED_ETAG_CAPTURED"),
        TestSpec("F", "T-RACE", "race", 120.0, 30, 45, 0,
                 "simultaneous If-None-Match:* creators -> one creation",
                 race_setup_state="PROVEN_ABSENT"),
        TestSpec("H1", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential HeadObject on its own key -> 2xx"),
        TestSpec("H2", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential GetObject on its own key -> 2xx"),
        TestSpec("H3", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential PutObject on its own key -> 2xx"),
        TestSpec("H4", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential DeleteObject on the sacrificial key -> 401/403"),
        TestSpec("H5", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential GET ?list-type=2 on the bucket -> 401/403"),
        TestSpec("H6", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential GET on the out-of-prefix key -> 401/403"),
        TestSpec("H7", "T-SCOPE", "scope", 10.0, 3, 6, 0,
                 "child-credential PUT on the out-of-prefix key -> 401/403"),
        TestSpec("I1", "T-SCOPE", "signing", 5.0, 1, 2, 0,
                 "child token transmitted AND inside SignedHeaders -> 2xx"),
        TestSpec("I2", "T-SCOPE", "signing", 5.0, 1, 1, 0,
                 "DIAGNOSTIC ONLY: token on the wire, absent from SignedHeaders"),
        TestSpec("I3", "T-SCOPE", "signing", 5.0, 1, 2, 0,
                 "no session token on the wire -> 401/403"),
        TestSpec("K1", "T-SCOPE", "absence", 10.0, 5, 10, 0,
                 "child-credential GET 404 NoSuchKey = ABSENT"),
        TestSpec("K2", "T-SCOPE", "absence", 0.0, 1, 1, 0,
                 "child-credential out-of-prefix access -> coded 401/403 denial"),
        TestSpec("K3", "T-SCOPE", "absence", 10.0, 1, 3, 0,
                 "two same-key PUTs within 1s -> 429 on the second"),
        TestSpec("J", "T-SHAPE", "shape", 60.0, 3, 6, 3,
                 "single-part PUT of exactly production_body_bytes -> 2xx"),
        TestSpec("L", "T-SHAPE", "integrity", 0.0, 1, 1, 0,
                 "read-back sha256 and length equal what was PUT"),
        TestSpec("X1", "T-SHAPE", "archive", 30.0, 3, 6, 0,
                 "archive create-only If-None-Match:* + exact raw-byte idempotency"),
        TestSpec("X2", "T-SHAPE", "audit", 30.0, 3, 6, 0,
                 "audit create-only If-None-Match:* + exact raw-byte idempotency"),
        TestSpec("I4", "T-EXPIRY", "signing", 95.0, 1, 2, 0,
                 "request signed after expires_at with that credential -> coded 401/403"),
    )
    policy = _Policy(
        bucket="bible-pal-cas-probe",
        denied_tokens=("bible-pal-audio",),
        key_prefix="catalog/probe/",
        sacrificial_key="catalog/probe/h-sacrificial.json",
        denied_out_of_prefix_key="outside/probe-denied.json",
        production_body_bytes=production_body_bytes,
        credential_scope="object-read-write",
        credential_actions=("HeadObject", "GetObject", "PutObject"),
        credential_prefixes=("catalog/",),
        credential_object_paths=(),
        group_ttl_seconds=900,
        expiry_group_ttl_seconds=60,
        expiry_group="T-EXPIRY",
        execute_confirmation="PUBLISH-NOTHING-PROBE-DISPOSABLE-BUCKET-ONLY",
        allowed_extra_headers=frozenset({
            "content-type", "content-md5", "if-match", "if-none-match"}),
        transport_owned_headers=frozenset({"host", "content-length"}),
        # SigV4-owned + the four allowlisted conditional/content extras. This
        # is the exhaustive wire allowlist enforced by _attempt(); host and
        # content-length remain transport-owned and are refused if supplied.
        wire_header_allowlist=frozenset({
            "authorization", "x-amz-date", "x-amz-content-sha256",
            "x-amz-security-token", "content-type", "content-md5",
            "if-match", "if-none-match"}),
        caps=_Caps(
            max_production_size_puts=60,
            max_put_attempts=650,
            max_get_head=1000,
            max_object_keys=300,
            max_uploaded_bytes=170 * 1000 * 1000,   # decimal MB, accepted
            max_peak_storage_bytes=120 * 1000 * 1000),
        matrix=matrix,
        sigv4_service="s3",
        r2_region="auto",
        multipart_query_markers=("uploads", "uploadId", "partNumber"),
        max_error_body_bytes=64 * 1024,
        max_response_body_bytes=production_body_bytes + 64 * 1024,
        # An evidence record is small; anything larger is refused outright.
        max_evidence_file_bytes=256 * 1024,
        scrub_exact=(
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE",
            "SSL_CERT_FILE", "SSL_CERT_DIR",
            "SSLKEYLOGFILE",
            "AUDIO_BASE_URL"),
        scrub_prefixes=("CLOUDFLARE_", "CF_", "AWS_", "WRANGLER_", "R2_"),
        same_key_min_gap_seconds=3.0,
        credential_safety_factor=1.5,
        credential_required_margin_seconds=120.0,
        expiry_max_age_seconds=10.0,
        # Both writers must begin their sends within this window of the
        # barrier release. Conservative for a local same-process barrier —
        # proves shared-barrier release, not perfect CPU simultaneity.
        max_race_send_skew_ns=50_000_000,   # 50 ms
        # The request timestamp must be within this window of the wall
        # clock, so a stale amz_date cannot masquerade as "now".
        max_amz_date_skew_seconds=300,      # 5 minutes
    )
    # Bind the exact instance via a default argument. Rebinding _Policy /
    # TestSpec / _Caps after this line cannot reach `policy`.
    return lambda policy=policy: policy


_policy = _capture_policy()

# ─────────────────────────────────────────────────────────────────────────
# CAPTURED VALIDATION GRAMMAR (Codex BLOCKER 3)
#
# Every compiled regex and immutable choice set that ENFORCEMENT reads
# lives in one closure-captured object. Validators dereference
# `_grammar()`, never a module name, so rebinding any of the display
# aliases below is inert. This replaces capturing one constant at a time.
# ─────────────────────────────────────────────────────────────────────────

class _ValidationGrammar(NamedTuple):
    endpoint_host: object
    run_id_file: object
    evidence_relative: object
    account_id: object
    bucket: object
    query_name: object
    header_name: object
    cred: object
    live_key: object
    sha256: object
    run_id: object
    allocated_key: object
    amz_date: object
    safe_message: object
    opaque_token: object
    error_code: object
    request_id: object
    writer_id: object
    barrier_gen: object
    ident: object
    etag: object
    issuance_nonce: object
    hexblob: object
    cf_ray: object
    correlation: object
    jwt_anywhere: object
    r2_host_any: object
    account_id_anywhere: object
    session_token_anywhere: object
    http_methods: frozenset
    phases: frozenset
    empty_sha256: str
    security_token_header: str


def _capture_validation_grammar():
    grammar = _ValidationGrammar(
        endpoint_host=re.compile(
            r"^[0-9a-f]{32}\.r2\.cloudflarestorage\.com$"),
        run_id_file=re.compile(r"^[0-9A-Za-z._-]{1,64}$"),
        evidence_relative=re.compile(r"^[0-9A-Za-z._/-]{1,160}$"),
        account_id=re.compile(r"^[0-9a-f]{32}$"),
        bucket=re.compile(r"^[a-z0-9-]{3,63}$"),
        query_name=re.compile(r"^[A-Za-z0-9-]{1,128}$"),
        header_name=re.compile(r"^[a-z0-9-]{1,64}$"),
        cred=re.compile(r"^[!-~]{8,128}$"),
        live_key=re.compile(r"^[A-Za-z0-9/._-]{1,200}$"),
        sha256=re.compile(r"^[0-9a-f]{64}$"),
        run_id=re.compile(r"^[a-z0-9][a-z0-9-]{3,39}$"),
        # Structural form produced by ProbeKeyAllocator.
        allocated_key=re.compile(
            r"^catalog/probe/(?P<phase>[pt])/(?P<run>[a-z0-9][a-z0-9-]{3,39})/"
            r"(?P<test>[a-z0-9-]{1,16})/(?P<rep>[0-9]{4})/obj\.json$"),
        amz_date=re.compile(r"^[0-9]{8}T[0-9]{6}Z$"),
        safe_message=re.compile(r"^[ -~]{1,200}$"),
        opaque_token=re.compile(r"[A-Za-z0-9_-]{20,}"),
        error_code=re.compile(r"^[A-Za-z]{1,64}$"),
        request_id=re.compile(r"^[A-Za-z0-9._:-]{1,128}$"),
        writer_id=re.compile(r"^[A-Za-z0-9_-]{1,32}$"),
        barrier_gen=re.compile(r"^[A-Za-z0-9._-]{1,64}$"),
        ident=re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$"),
        etag=re.compile(r'^(W/)?"[!-~]{1,128}"$|^\*$'),
        # An allocator nonce is "<run id>:<six digits>" and nothing else.
        issuance_nonce=re.compile(r"^[a-z0-9][a-z0-9-]{3,39}:[0-9]{6}$"),
        hexblob=re.compile(r"^[0-9a-f]+$"),
        cf_ray=re.compile(r"^[A-Za-z0-9-]{1,64}$"),
        # "<phase>/<run_id>/<test>/<rep>/<seq>" (MEDIUM 2).
        correlation=re.compile(
            r"^[PT]/[a-z0-9][a-z0-9-]{3,39}/[A-Za-z0-9-]{1,16}"
            r"/[0-9]{1,4}/[0-9]{1,6}$"),
        # Credential shapes that must never appear inside a stored string.
        jwt_anywhere=re.compile(r"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
                                r"\.[A-Za-z0-9_-]{8,}"),
        r2_host_any=re.compile(r"[0-9a-f]{32}\.r2\.cloudflarestorage\.com"),
        # A 32-hex run not part of a longer hex string (so a 64-hex sha256
        # in an appropriate field is not mistaken for an account id).
        account_id_anywhere=re.compile(r"(?<![0-9a-fA-F])[0-9a-f]{32}"
                                       r"(?![0-9a-fA-F])"),
        # Standard base64 of "jwt/" begins with "and0L".
        session_token_anywhere=re.compile(r"and0L[A-Za-z0-9+/]{16,}={0,2}"),
        http_methods=frozenset({"GET", "HEAD", "PUT", "DELETE"}),
        phases=frozenset({"P", "T"}),
        empty_sha256=hashlib.sha256(b"").hexdigest(),
        security_token_header="x-amz-security-token",
    )
    return lambda grammar=grammar: grammar


_grammar = _capture_validation_grammar()


# DISPLAY ONLY. Rebinding any of these changes nothing that is enforced.
_ENDPOINT_HOST_RE = _grammar().endpoint_host
_ACCOUNT_ID_RE = _grammar().account_id
_ALLOWED_METHODS = _grammar().http_methods
_ALLOWED_HTTP_METHODS = _grammar().http_methods
_ALLOWED_PHASES = _grammar().phases
_BUCKET_RE = _grammar().bucket
_QUERY_NAME_RE = _grammar().query_name
_HEADER_NAME_RE = _grammar().header_name
_CRED_RE = _grammar().cred
_LIVE_KEY_RE = _grammar().live_key
_SHA256_RE = _grammar().sha256
_RUN_ID_RE = _grammar().run_id
_ALLOCATED_KEY_RE = _grammar().allocated_key
_SAFE_MESSAGE_RE = _grammar().safe_message
_OPAQUE_TOKEN_RE = _grammar().opaque_token
_ERROR_CODE_RE = _grammar().error_code
_REQUEST_ID_RE = _grammar().request_id
_WRITER_ID_RE = _grammar().writer_id
_BARRIER_GEN_RE = _grammar().barrier_gen
_IDENT_RE = _grammar().ident
_ETAG_RE = _grammar().etag
_ISSUANCE_NONCE_RE = _grammar().issuance_nonce
_HEX_RE = _grammar().hexblob
_CF_RAY_RE = _grammar().cf_ray
_CORRELATION_RE = _grammar().correlation
_JWT_ANYWHERE_RE = _grammar().jwt_anywhere
_R2_HOST_ANY_RE = _grammar().r2_host_any
_ACCOUNT_ID_ANYWHERE_RE = _grammar().account_id_anywhere
_SESSION_TOKEN_ANYWHERE_RE = _grammar().session_token_anywhere
_EMPTY_SHA256 = _grammar().empty_sha256



def _capture_evidence_layout():
    """The manifest filename and the kind->directory map, captured once.

    Rebinding `MANIFEST_FILENAME` would otherwise let exactly one stray
    top-level file be skipped during enumeration, and rebinding the
    directory map could redirect canonical paths.
    """
    layout = (
        "evidence-manifest.json",
        (("ISSUANCE_RECORD", "issuance_record"),
         ("SEMANTIC_RECORD", "semantic_record"),
         ("RACE_RECORD", "race_record"),
         ("TEST_RESULT_RECORD", "test_result_record"),
         ("REQUEST_RECORD", "request"),
         ("RESPONSE_RECORD", "response")),
        # Every (raw, hex) evidence pair. The hex is a lossless
        # transcription of the raw header, never an independent blob
        # (Codex MEDIUM 1).
        (("etag_raw", "etag_raw_hex"),
         ("if_match_raw", "if_match_raw_hex"),
         ("if_none_match_raw", "if_none_match_raw_hex")),
    )
    return lambda layout=layout: layout


_evidence_layout = _capture_evidence_layout()


def _manifest_filename() -> str:
    return _evidence_layout()[0]


def _record_kind_dir(kind) -> str:
    for known, directory in _evidence_layout()[1]:
        if known == kind:
            return directory
    raise SafetyBarrierTripped(f"{kind!r} has no evidence directory")


def _record_kind_dirs() -> frozenset:
    return frozenset(d for _, d in _evidence_layout()[1])


# ── Derived views of the ONE matrix (Codex MEDIUM 2) ─────────────────────

def _matrix_groups(policy) -> dict:
    groups: dict = {}
    for spec in policy.matrix:
        groups.setdefault(spec.group, []).append(spec.id)
    return {group: tuple(ids) for group, ids in groups.items()}


def credential_groups() -> dict:
    """group -> tuple(test ids). Derived; never separately maintained."""
    return _matrix_groups(_policy())


def known_test_ids() -> frozenset:
    return frozenset(spec.id for spec in _policy().matrix)


def semantic_test_ids() -> tuple:
    return tuple(spec.id for spec in _policy().matrix
                 if spec.category == "semantic")


def race_test_ids() -> tuple:
    return tuple(spec.id for spec in _policy().matrix
                 if spec.category == "race")


def test_spec(test_id) -> TestSpec:
    _exact_str(test_id, "test_id", max_len=16)
    for spec in _policy().matrix:
        if spec.id == test_id:
            return spec
    raise SafetyBarrierTripped(f"unknown test id {test_id!r}")


# ── Exported DISPLAY constants ───────────────────────────────────────────
# Rebinding any of these changes NOTHING that is enforced. They exist for
# readable test assertions and plan output only.

PROBE_BUCKET = _policy().bucket
DENIED_NAME_TOKENS = _policy().denied_tokens
PROBE_KEY_PREFIX = _policy().key_prefix
SACRIFICIAL_KEY = _policy().sacrificial_key
DENIED_OUT_OF_PREFIX_KEY = _policy().denied_out_of_prefix_key
PRODUCTION_BODY_BYTES = _policy().production_body_bytes
PROBE_ACTIONS = _policy().credential_actions
PROBE_CREDENTIAL_SCOPE = _policy().credential_scope
PROBE_CREDENTIAL_PREFIXES = _policy().credential_prefixes
GROUP_TTL_SECONDS = _policy().group_ttl_seconds
EXPIRY_GROUP_TTL_SECONDS = _policy().expiry_group_ttl_seconds
EXPIRY_GROUP = _policy().expiry_group
EXECUTE_CONFIRMATION = _policy().execute_confirmation
ALLOWED_EXTRA_HEADERS = _policy().allowed_extra_headers
TRANSPORT_OWNED_HEADERS = _policy().transport_owned_headers
TEST_MATRIX = _policy().matrix
SEMANTIC_TESTS = semantic_test_ids()
RACE_TESTS = race_test_ids()

#: DISPLAY aliases of load-bearing values. Enforcement reads the closure
#: policy (`_policy().*`), never these names — rebinding them is inert.
MAX_ERROR_BODY_BYTES = _policy().max_error_body_bytes
MAX_RESPONSE_BODY_BYTES = _policy().max_response_body_bytes
SIGV4_SERVICE = _policy().sigv4_service
R2_REGION = _policy().r2_region
MULTIPART_QUERY_MARKERS = _policy().multipart_query_markers



# ─────────────────────────────────────────────────────────────────────────
# Environment scrubbing — MUST run before any TLS context exists
# ─────────────────────────────────────────────────────────────────────────

#: DISPLAY aliases. forbidden_environment_keys() reads the closure policy.
SCRUB_EXACT = (
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
    "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE",
    "SSL_CERT_FILE", "SSL_CERT_DIR",
    "SSLKEYLOGFILE",
    "AUDIO_BASE_URL",
)

#: DISPLAY alias. forbidden_environment_keys() reads the closure policy.
SCRUB_PREFIXES = ("CLOUDFLARE_", "CF_", "AWS_", "WRANGLER_", "R2_")


def forbidden_environment_keys(env: Mapping[str, str]) -> list:
    policy = _policy()
    exact = policy.scrub_exact
    prefixes = policy.scrub_prefixes
    bad = []
    for key in env:
        if key in exact:
            bad.append(key)
            continue
        upper = key.upper()
        if any(upper.startswith(prefix) for prefix in prefixes):
            bad.append(key)
    return sorted(bad)


def scrubbed_environment(home: str, path: str = "/usr/bin:/bin") -> dict:
    return {"HOME": home, "PATH": path, "TZ": "UTC", "LANG": "C.UTF-8"}


def scrub_process_environment(home: str, path: str = "/usr/bin:/bin") -> None:
    os.environ.clear()
    os.environ.update(scrubbed_environment(home, path))
    leftovers = forbidden_environment_keys(os.environ)
    if leftovers:
        raise SafetyBarrierTripped(
            f"environment scrub failed; still present: {leftovers}")


def assert_environment_clean(env: Mapping[str, str] | None = None) -> None:
    env = os.environ if env is None else env
    leftovers = forbidden_environment_keys(env)
    if leftovers:
        raise SafetyBarrierTripped(
            "forbidden environment variables present: " + ", ".join(leftovers))


# ─────────────────────────────────────────────────────────────────────────
# Production-name denylist (policy read via the closure)
# ─────────────────────────────────────────────────────────────────────────

def assert_no_denied_names(*values, env: Mapping[str, str] | None = None
                           ) -> None:
    """Refuse if any denied production name appears anywhere.

    Fail-closed: exact built-in str/bytes are scanned; SUBCLASSES of
    str/bytes are refused outright (a polymorphic __contains__ could lie
    to this scan), and unsupported types are refused rather than coerced
    through a potentially malicious __str__.
    """
    denied = _policy().denied_tokens

    def scan(obj, where: str) -> None:
        if obj is None or type(obj) in (int, float, bool):
            return
        if type(obj) is str or type(obj) is bytes:
            text = (obj.decode("utf-8", "replace") if type(obj) is bytes
                    else obj)
            for token in denied:
                if token in text:
                    raise ProductionNameDetected(
                        f"denied production name {token!r} found in {where}")
            return
        if isinstance(obj, (str, bytes)):
            raise SafetyBarrierTripped(
                f"polymorphic {type(obj).__name__} refused in safety scan "
                f"({where})")
        if type(obj) is dict:
            for key, value in obj.items():
                scan(key, where)
                scan(value, where)
            return
        if type(obj) in (list, tuple, set, frozenset):
            for item in obj:
                scan(item, where)
            return
        raise SafetyBarrierTripped(
            f"unsupported type {type(obj).__name__} in safety scan ({where})")

    for index, value in enumerate(values):
        scan(value, f"argument {index}")
    if env is not None:
        scan(dict(env), "environment")


# ─────────────────────────────────────────────────────────────────────────
# Endpoint allowlist
# ─────────────────────────────────────────────────────────────────────────

def build_endpoint_host(account_id) -> str:
    if type(account_id) is not str or not _grammar().account_id.fullmatch(account_id):
        raise EndpointRefused(
            "account id must be exactly str: 32 lowercase hex characters")
    return f"{account_id}.r2.cloudflarestorage.com"


def assert_endpoint_allowed(endpoint) -> str:
    _exact(endpoint, str, "endpoint")
    assert_no_denied_names(endpoint)
    parsed = urllib.parse.urlsplit(endpoint)
    if parsed.scheme != "https":
        raise EndpointRefused(f"scheme must be https, got {parsed.scheme!r}")
    if parsed.username or parsed.password:
        raise EndpointRefused("credentials must never appear in the endpoint")
    if parsed.port is not None:
        raise EndpointRefused("explicit ports are refused")
    if parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise EndpointRefused("endpoint must be scheme + host only")
    host = str(parsed.hostname or "")
    if not _grammar().endpoint_host.fullmatch(host):
        raise EndpointRefused(
            f"host {host!r} is not the permitted R2 S3 endpoint shape "
            "(jurisdictional endpoints, r2.dev and custom domains are "
            "refused)")
    return host


# ─────────────────────────────────────────────────────────────────────────
# Request target — NamedTuple, so object.__setattr__ cannot mutate it
# ─────────────────────────────────────────────────────────────────────────

class RequestTarget(NamedTuple):
    method: str
    bucket: str
    key: str
    query: tuple = ()


def new_request_target(*, method, bucket, key, query=()) -> RequestTarget:
    """Validating builder. Raw NamedTuple construction is still possible,
    which is why every boundary re-validates."""
    target = RequestTarget(method=method, bucket=bucket, key=key,
                           query=tuple(query) if type(query) in (tuple, list)
                           else query)
    validate_target(target)
    return target


def validate_target(target) -> tuple:
    """Exact-type validation of every field. Returns validated builtins."""
    if type(target) is not RequestTarget:
        raise SafetyBarrierTripped(
            f"target must be exactly RequestTarget, got "
            f"{type(target).__name__}")
    method = target.method
    if type(method) is not str or method not in _grammar().http_methods:
        raise SafetyBarrierTripped(f"method {method!r} is not permitted")
    bucket = target.bucket
    if type(bucket) is not str or not _grammar().bucket.fullmatch(bucket):
        raise SafetyBarrierTripped("bucket must be exactly str, [a-z0-9-]{3,63}")
    key = target.key
    if type(key) is not str:
        raise SafetyBarrierTripped("key must be exactly str")
    if len(key) > 512:
        raise SafetyBarrierTripped("key exceeds 512 characters")
    if any(ch in key for ch in "\x00\r\n"):
        raise SafetyBarrierTripped("key contains a control character")
    if ".." in key.split("/"):
        raise SafetyBarrierTripped("key must not contain '..' segments")
    query = target.query
    if type(query) is not tuple:
        raise SafetyBarrierTripped("query must be exactly tuple")
    pairs = []
    for item in query:
        if type(item) is not tuple or len(item) != 2:
            raise SafetyBarrierTripped("query items must be exactly 2-tuples")
        name, value = item
        if type(name) is not str or not _grammar().query_name.fullmatch(name):
            raise SafetyBarrierTripped(f"query name {name!r} refused")
        if type(value) is not str or len(value) > 512:
            raise SafetyBarrierTripped("query value must be exactly str <=512")
        if any(ch in value for ch in "\x00\r\n"):
            raise SafetyBarrierTripped("query value contains a control char")
        pairs.append((name, value))
    return method, bucket, key, tuple(pairs)


def _canonical_uri(bucket: str, key: str) -> str:
    # AWS single-encode for S3 path-style: URI-encode every byte except
    # unreserved (A-Z a-z 0-9 - . _ ~); '/' is the path separator and is
    # not encoded inside the object key. Uppercase hex, %20 for space.
    raw = f"/{bucket}/{key}" if key else f"/{bucket}"
    return urllib.parse.quote(raw, safe="/-._~")


def _canonical_query(query_pairs) -> str:
    # AWS: "URI-encode each name and value individually. You must also
    # sort the parameters in the canonical query string alphabetically by
    # key name. The sorting occurs AFTER encoding."
    encoded = [(urllib.parse.quote(name, safe="-._~"),
                urllib.parse.quote(value, safe="-._~"))
               for name, value in query_pairs]
    encoded.sort()
    return "&".join(f"{name}={value}" for name, value in encoded)


def target_canonical_path(target) -> str:
    _, bucket, key, _ = validate_target(target)
    return _canonical_uri(bucket, key)


def target_canonical_query(target) -> str:
    _, _, _, query = validate_target(target)
    return _canonical_query(query)


def assert_target_allowed(target, allow_denied_prefix_probe=False) -> tuple:
    """Bucket / key / multipart enforcement, from the closure policy."""
    _exact_bool(allow_denied_prefix_probe, "allow_denied_prefix_probe")
    policy = _policy()
    method, bucket, key, query = validate_target(target)
    assert_no_denied_names(bucket, key)
    if bucket != policy.bucket:
        raise ProductionNameDetected(
            f"bucket {bucket!r} is not the fixed probe bucket "
            f"{policy.bucket!r}")
    for name, _value in query:
        if name in policy.multipart_query_markers:
            raise SafetyBarrierTripped(
                f"multipart query marker {name!r} must never be emitted")
    # EXACT OPERATION RULE (Codex round-3 BLOCKER 2). The probe performs a
    # closed set of operations, so anything outside it is refused before a
    # socket rather than being left to credential scope:
    #   - DELETE exists ONLY as the H4 denial probe against the sacrificial
    #     key. A DELETE on an allocated object key — with or without a
    #     caller-chosen `versionId` — has no legitimate purpose here.
    #   - The ONLY query the probe ever emits is `list-type=2` on the
    #     bucket-level H5 listing (validated below). Every other request
    #     carries an EMPTY query, so `versionId`, `uploads`, `acl`,
    #     `tagging` and friends cannot ride along.
    if method == "DELETE" and key != policy.sacrificial_key:
        raise SafetyBarrierTripped(
            "DELETE is permitted ONLY against the sacrificial denial-probe "
            f"key, never {key!r}")
    if query and not (key == "" and method == "GET"):
        raise SafetyBarrierTripped(
            "only the bucket-level ListObjectsV2 diagnostic may carry a "
            f"query; {[name for name, _ in query]} refused")
    if key:
        if not _grammar().live_key.fullmatch(key):
            raise SafetyBarrierTripped(
                f"live probe keys are fixed ASCII; {key!r} refused")
        if not key.startswith(policy.key_prefix):
            if not (allow_denied_prefix_probe
                    and key == policy.denied_out_of_prefix_key):
                raise SafetyBarrierTripped(
                    f"key {key!r} is outside {policy.key_prefix!r}")
    else:
        # BUCKET-LEVEL OPERATION RULE (Codex round 2). An empty key
        # addresses the bucket itself; the ONLY legitimate bucket-level
        # request in this probe is the H5 ListObjectsV2 diagnostic — a GET
        # carrying exactly `list-type=2`. A bucket-level DELETE/PUT/HEAD, a
        # copy, or any other bucket-level query is refused outright.
        if method != "GET" or tuple(query) != (("list-type", "2"),):
            raise SafetyBarrierTripped(
                "a bucket-level (empty-key) request is permitted ONLY as "
                "GET ?list-type=2 (the H5 ListObjectsV2 diagnostic)")
    return method, bucket, key, query


# ─────────────────────────────────────────────────────────────────────────
# SigV4
# ─────────────────────────────────────────────────────────────────────────



def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hmac(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def derive_signing_key(secret_access_key: str, datestamp: str,
                       region: str, service: str) -> bytes:
    k_date = _hmac(("AWS4" + secret_access_key).encode("utf-8"), datestamp)
    k_region = _hmac(k_date, region)
    k_service = _hmac(k_region, service)
    return _hmac(k_service, "aws4_request")


def normalise_header_value(value: str) -> str:
    """AWS: trim, collapse sequential whitespace (spaces and tabs) to one."""
    return " ".join(value.split())


def content_md5_base64(body: bytes) -> str:
    """Base64 of the 16 RAW MD5 bytes — not the hex digest."""
    return base64.b64encode(hashlib.md5(body).digest()).decode("ascii")


class SignedRequest(NamedTuple):
    """OFFLINE-TEST ARTEFACT ONLY.

    The live boundary is `R2Transport.sign_and_send`, which never accepts
    one of these: it signs internally and transmits immediately, so no
    caller-visible object exists between signing and transmission.
    """

    target: RequestTarget
    host: str
    headers: tuple
    canonical_headers: tuple
    body: bytes
    signed_header_names: tuple
    canonical_request: str
    string_to_sign: str
    signature: str

    def header_map(self) -> dict:
        return {name: value for name, value in self.headers}


def _build_signed_headers(*, host, payload_hash, amz_date, session_token,
                          body, include_content_md5, extra_headers):
    """The canonical header map. Header ownership is enforced here."""
    policy = _policy()
    canonical = {
        "host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }
    if session_token is not None:
        canonical["x-amz-security-token"] = session_token
    if include_content_md5 and body:
        canonical["content-md5"] = content_md5_base64(body)

    if extra_headers is not None:
        if type(extra_headers) is not dict:
            raise SafetyBarrierTripped(
                "extra_headers must be exactly dict (mapping subclasses "
                "are refused)")
        for name, value in extra_headers.items():
            _exact_str(name, "extra header name", max_len=64)
            lowered = name.lower()
            if lowered not in policy.allowed_extra_headers:
                raise SafetyBarrierTripped(
                    f"extra header {name!r} is not allowlisted "
                    f"(allowed: {sorted(policy.allowed_extra_headers)})")
            if lowered in canonical:
                raise SafetyBarrierTripped(
                    f"extra header {name!r} collides with an existing header "
                    "(duplicates and case-variants are refused)")
            _exact_str(value, f"extra header {lowered} value", max_len=1024,
                       allow_empty=True)
            _no_ctl(value, f"extra header {lowered} value", allow_tab=True)
            canonical[lowered] = value
    return canonical


def sign_request(*, target, host, access_key_id, secret_access_key,
                 session_token, body, amz_date, extra_headers=None,
                 include_content_md5: bool = False,
                 unsigned_session_token=None) -> SignedRequest:
    """Pure signer. Retained for OFFLINE parity testing of the algorithm.

    Production/live use must go through `R2Transport.sign_and_send`, which
    binds signing and transmission together.
    """
    method, bucket, key, query = validate_target(target)
    if type(host) is not str or not _grammar().endpoint_host.fullmatch(host):
        raise EndpointRefused(
            "sign_request host must be the exact R2 S3 endpoint host shape")
    if not _grammar().cred.fullmatch(access_key_id if type(access_key_id) is str
                              else ""):
        raise SafetyBarrierTripped("access_key_id refused")
    if not _grammar().cred.fullmatch(secret_access_key
                              if type(secret_access_key) is str else ""):
        raise SafetyBarrierTripped("secret_access_key refused")
    if session_token is not None:
        _exact_str(session_token, "session_token", max_len=8192)
        _no_ctl(session_token, "session_token")
    if unsigned_session_token is not None:
        # The I2 diagnostic shape ONLY: the token really goes on the wire
        # but is deliberately excluded from SignedHeaders. Persisting that
        # shape is what makes I2 provable instead of caller-asserted.
        if session_token is not None:
            raise SafetyBarrierTripped(
                "a session token cannot be both signed and unsigned")
        _exact_str(unsigned_session_token, "unsigned_session_token",
                   max_len=8192)
        _no_ctl(unsigned_session_token, "unsigned_session_token")
    body = _exact_bytes(body, "body", max_len=_policy().production_body_bytes)
    _exact_str(amz_date, "amz_date", max_len=17)
    if not _grammar().amz_date.fullmatch(amz_date):
        raise SafetyBarrierTripped(f"malformed x-amz-date {amz_date!r}")
    _exact_bool(include_content_md5, "include_content_md5")
    datestamp = amz_date[:8]

    payload_hash = _sha256_hex(body) if body else _grammar().empty_sha256
    canonical = _build_signed_headers(
        host=host, payload_hash=payload_hash, amz_date=amz_date,
        session_token=session_token, body=body,
        include_content_md5=include_content_md5,
        extra_headers=extra_headers)

    signed_names = tuple(sorted(canonical))
    canonical_headers_text = "".join(
        f"{name}:{normalise_header_value(canonical[name])}\n"
        for name in signed_names)
    signed_headers = ";".join(signed_names)

    canonical_request = "\n".join((
        method, _canonical_uri(bucket, key), _canonical_query(query),
        canonical_headers_text, signed_headers, payload_hash))

    region = _policy().r2_region
    service = _policy().sigv4_service
    scope = f"{datestamp}/{region}/{service}/aws4_request"
    string_to_sign = "\n".join((
        "AWS4-HMAC-SHA256", amz_date, scope,
        _sha256_hex(canonical_request.encode("utf-8"))))

    signing_key = derive_signing_key(
        secret_access_key, datestamp, region, service)
    signature = hmac.new(signing_key, string_to_sign.encode("utf-8"),
                         hashlib.sha256).hexdigest()
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access_key_id}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}")

    # Wire headers: everything signed EXCEPT host (bound by the transport
    # to the validated connection host), plus authorization. Never
    # content-length (http.client computes it from the exact body bytes).
    wire = {name: value for name, value in canonical.items() if name != "host"}
    wire["authorization"] = authorization
    if unsigned_session_token is not None:
        wire[_grammar().security_token_header] = unsigned_session_token

    return SignedRequest(
        target=target, host=host, headers=tuple(sorted(wire.items())),
        canonical_headers=tuple((n, canonical[n]) for n in signed_names),
        body=body, signed_header_names=signed_names,
        canonical_request=canonical_request, string_to_sign=string_to_sign,
        signature=signature)


# ─────────────────────────────────────────────────────────────────────────
# Temporary credentials — FIXED probe contract
# ─────────────────────────────────────────────────────────────────────────

class TemporaryCredential(NamedTuple):
    group: str
    access_key_id: str
    secret_access_key: str
    session_token: str
    issued_at: int
    expires_at: int
    bucket: str
    scope: str
    actions: tuple
    prefix_paths: tuple

    def seconds_remaining(self, now: float) -> float:
        return self.expires_at - now

    def redacted_summary(self) -> dict:
        return {
            "group": self.group, "bucket": self.bucket, "scope": self.scope,
            "actions": list(self.actions),
            "prefix_paths": list(self.prefix_paths),
            "issued_at": self.issued_at, "expires_at": self.expires_at,
            "session_token_sha256": hashlib.sha256(
                self.session_token.encode("utf-8")).hexdigest(),
        }


def _amz_date_to_epoch(amz_date: str) -> int:
    """UTC epoch seconds for a `YYYYMMDDThhmmssZ` timestamp.

    Uses a fixed-offset UTC datetime (no local timezone, no wall clock),
    so it is deterministic and side-effect free.
    """
    from datetime import datetime, timezone
    dt = datetime(int(amz_date[0:4]), int(amz_date[4:6]), int(amz_date[6:8]),
                  int(amz_date[9:11]), int(amz_date[11:13]),
                  int(amz_date[13:15]), tzinfo=timezone.utc)
    return int(dt.timestamp())


def _b64url_nopad(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def mint_probe_credential(*, group, account_id, parent_access_key_id,
                          parent_secret_access_key, now
                          ) -> TemporaryCredential:
    """Derive the ONE credential shape this probe is allowed to hold.

    Deliberately NOT a general-purpose Cloudflare credential mint. Bucket,
    scope, actions, prefixes, objectPaths and audience are read from the
    closure-captured policy; the TTL derives from the fixed group. No
    public argument can widen any claim, and rebinding the exported
    PROBE_ACTIONS / PROBE_CREDENTIAL_SCOPE aliases has no effect here.

    Cloudflare's documented client-side signing recipe. The Temporary
    Credentials REST API path is deliberately NOT implemented: it would
    require a second Cloudflare bearer token, which the accepted
    architecture forbids.
    """
    policy = _policy()
    _exact_str(group, "group", max_len=16)
    groups = _matrix_groups(policy)
    if group not in groups:
        raise SafetyBarrierTripped(f"unknown credential group {group!r}")
    endpoint_host = build_endpoint_host(account_id)
    if type(parent_access_key_id) is not str \
            or not _grammar().cred.fullmatch(parent_access_key_id):
        raise SafetyBarrierTripped("parent access key id refused")
    if type(parent_secret_access_key) is not str \
            or not _grammar().cred.fullmatch(parent_secret_access_key):
        raise SafetyBarrierTripped("parent secret access key refused")
    _exact_int(now, "now", minimum=1)

    ttl = (policy.expiry_group_ttl_seconds if group == policy.expiry_group
           else policy.group_ttl_seconds)

    header = {"alg": "HS256", "typ": "JWT"}
    claims = {
        "actions": list(policy.credential_actions),
        "aud": endpoint_host,
        "bucket": policy.bucket,
        "exp": now + ttl,
        # The credential GROUP is part of the signed claims (Codex
        # BLOCKER 2-A). Without it, two groups sharing a TTL mint
        # byte-identical tokens, and "the child credential minted for this
        # group" would not be a fact any fingerprint could identify.
        "group": group,
        "iat": now,
        "iss": parent_access_key_id,
        "paths": {"objectPaths": list(policy.credential_object_paths),
                  "prefixPaths": list(policy.credential_prefixes)},
        "scope": policy.credential_scope,
        "sub": account_id,
    }

    def encode(obj: dict) -> str:
        return _b64url_nopad(json.dumps(
            obj, sort_keys=True, separators=(",", ":"),
            ensure_ascii=False, allow_nan=False).encode("utf-8"))

    signing_input = f"{encode(header)}.{encode(claims)}"
    signature = hmac.new(parent_secret_access_key.encode("utf-8"),
                         signing_input.encode("utf-8"),
                         hashlib.sha256).digest()
    jwt = f"{signing_input}.{_b64url_nopad(signature)}"

    return TemporaryCredential(
        group=group,
        access_key_id=parent_access_key_id,
        secret_access_key=hashlib.sha256(jwt.encode("utf-8")).hexdigest(),
        session_token=base64.b64encode(
            b"jwt/" + jwt.encode("utf-8")).decode("ascii"),
        issued_at=now, expires_at=now + ttl,
        bucket=policy.bucket, scope=policy.credential_scope,
        actions=policy.credential_actions,
        prefix_paths=policy.credential_prefixes)


def _decode_probe_session_token(session_token) -> tuple:
    """Return (header, claims, jwt) from a probe session token, or raise.

    Proves the token is standard base64 of exactly "jwt/" + a 3-segment
    JWT whose header/claims decode as JSON. The HS256 signature is NOT
    checked here — the parent secret is not available at transport time —
    which is exactly why the caller must ALSO cross-check the derived
    secret against sha256(jwt).
    """
    if type(session_token) is not str:
        raise SafetyBarrierTripped("session_token must be exactly str")
    try:
        raw = base64.b64decode(session_token.encode("ascii"), validate=True)
    except (binascii.Error, ValueError):
        raise SafetyBarrierTripped(
            "session_token is not valid standard base64")
    if not raw.startswith(b"jwt/"):
        raise SafetyBarrierTripped("session_token lacks the 'jwt/' prefix")
    jwt = raw[4:].decode("utf-8", "strict")
    parts = jwt.split(".")
    if len(parts) != 3:
        raise SafetyBarrierTripped("session_token JWT is not 3 segments")

    def _decode_segment(segment: str) -> dict:
        padding = "=" * (-len(segment) % 4)
        obj = json.loads(base64.urlsafe_b64decode(segment + padding))
        if type(obj) is not dict:
            raise SafetyBarrierTripped("JWT segment is not a JSON object")
        return obj

    return _decode_segment(parts[0]), _decode_segment(parts[1]), jwt


class TransmittedCredentialClaims(NamedTuple):
    """The credential facts carried by the token that was ACTUALLY sent."""

    group: str
    scope: str
    actions: tuple
    prefix_paths: tuple
    issued_at: int
    expires_at: int
    access_key_id: str
    account_id: str
    bucket: str


def validate_transmitted_token_claims(wire_token, *, endpoint_host,
                                      access_key_id
                                      ) -> TransmittedCredentialClaims:
    """STRUCTURAL validation of the session token that went on the wire.

    This is the authority for a request's credential facts (Codex
    BLOCKER 2): every value returned is decoded from the signed JWT, never
    copied from a caller-owned `TemporaryCredential`, whose NamedTuple
    `_replace` would otherwise let evidence claim a group or an expiry the
    token does not carry.

    It proves shape and policy conformance — header, bucket, scope,
    actions, prefixes, objectPaths, group membership, TTL matching the
    group, `iss` equal to the signing access key, `aud`/`sub` equal to this
    endpoint — but DELIBERATELY does NOT check the wall clock. I4 records
    retrospective evidence about an ALREADY-EXPIRED credential, so a
    validity-window check here would make the honest expired case
    unrecordable. Pre-transmission enforcement is unchanged and still lives
    in `validate_probe_credential_for_transport`, which continues to reject
    an expired credential before it can be sent.
    """
    policy = _policy()
    if type(endpoint_host) is not str \
            or not _grammar().endpoint_host.fullmatch(endpoint_host):
        raise EndpointRefused("endpoint_host refused")
    if type(access_key_id) is not str \
            or not _grammar().cred.fullmatch(access_key_id):
        raise SafetyBarrierTripped("signing access_key_id refused")

    header, claims, jwt = _decode_probe_session_token(wire_token)
    if header != {"alg": "HS256", "typ": "JWT"}:
        raise SafetyBarrierTripped("JWT protected header is not HS256/JWT")

    group = claims.get("group")
    groups = _matrix_groups(policy)
    if type(group) is not str or group not in groups:
        raise SafetyBarrierTripped(
            f"JWT group claim {group!r} is not a matrix group")
    if claims.get("bucket") != policy.bucket:
        raise ProductionNameDetected("JWT bucket claim is not the probe bucket")
    if claims.get("scope") != policy.credential_scope:
        raise SafetyBarrierTripped("JWT scope claim is not the probe scope")
    actions = tuple(claims.get("actions") or ())
    if actions != policy.credential_actions:
        raise SafetyBarrierTripped("JWT actions claim is not the probe set")
    paths = claims.get("paths")
    prefixes = tuple((paths or {}).get("prefixPaths") or ())
    if type(paths) is not dict or prefixes != policy.credential_prefixes \
            or tuple(paths.get("objectPaths") or ()) \
            != policy.credential_object_paths:
        raise SafetyBarrierTripped("JWT paths claim is not the probe set")
    if claims.get("iss") != access_key_id:
        raise SafetyBarrierTripped(
            "JWT iss does not equal the access key that signed the request")
    if claims.get("aud") != endpoint_host:
        raise SafetyBarrierTripped(
            "JWT audience is not the endpoint this request went to")
    account_id = str(claims.get("sub") or "")
    if not _grammar().account_id.fullmatch(account_id):
        raise SafetyBarrierTripped("JWT sub is not a 32-hex account id")
    if endpoint_host != f"{account_id}.r2.cloudflarestorage.com":
        raise SafetyBarrierTripped(
            "JWT sub account id does not match the endpoint host")

    issued_at = claims.get("iat")
    expires_at = claims.get("exp")
    if type(issued_at) is not int or type(expires_at) is not int:
        raise SafetyBarrierTripped("JWT iat/exp must be int")
    expected_ttl = (policy.expiry_group_ttl_seconds
                    if group == policy.expiry_group
                    else policy.group_ttl_seconds)
    if expires_at - issued_at != expected_ttl:
        raise SafetyBarrierTripped(
            f"JWT TTL does not match group {group!r}")
    del jwt
    return TransmittedCredentialClaims(
        group=group, scope=policy.credential_scope, actions=actions,
        prefix_paths=prefixes, issued_at=issued_at, expires_at=expires_at,
        access_key_id=access_key_id, account_id=account_id,
        bucket=policy.bucket)


def validate_probe_credential_for_transport(credential, *, endpoint_host,
                                            now) -> TemporaryCredential:
    """Prove a credential is internally consistent and bound to THIS
    endpoint, THIS policy, THIS group and THIS validity window (HIGH 2).

    Every field is validated: exact type, group membership, bucket/scope/
    actions/prefix equal to the captured policy, TTL matching the group,
    validity window containing `now`, access-key shape, and — decoding the
    session token — the protected header, every claim, aud==endpoint host,
    iss==access key id, and derived_secret==sha256(jwt). The parent-secret
    HS256 signature is verified at mint time, by the independent offline
    tests, and finally by R2 itself during the eventual probe.
    """
    policy = _policy()
    if type(credential) is not TemporaryCredential:
        raise SafetyBarrierTripped("credential must be exactly "
                                   "TemporaryCredential")
    if type(endpoint_host) is not str \
            or not _grammar().endpoint_host.fullmatch(endpoint_host):
        raise EndpointRefused("endpoint_host refused")
    if type(now) not in (int, float) or not math.isfinite(now):
        raise SafetyBarrierTripped("now must be a finite number")

    groups = _matrix_groups(policy)
    if type(credential.group) is not str or credential.group not in groups:
        raise SafetyBarrierTripped(
            f"credential group {credential.group!r} is not permitted")
    if credential.bucket != policy.bucket:
        raise ProductionNameDetected(
            "credential bucket is not the probe bucket")
    if credential.scope != policy.credential_scope:
        raise SafetyBarrierTripped("credential scope is not the probe scope")
    if tuple(credential.actions) != policy.credential_actions:
        raise SafetyBarrierTripped("credential actions are not the probe set")
    if tuple(credential.prefix_paths) != policy.credential_prefixes:
        raise SafetyBarrierTripped("credential prefixes are not the probe set")
    if type(credential.access_key_id) is not str \
            or not _grammar().cred.fullmatch(credential.access_key_id):
        raise SafetyBarrierTripped("credential access_key_id refused")
    if type(credential.secret_access_key) is not str \
            or not _grammar().sha256.fullmatch(credential.secret_access_key):
        raise SafetyBarrierTripped(
            "credential secret must be a sha256 hex digest")

    expected_ttl = (policy.expiry_group_ttl_seconds
                    if credential.group == policy.expiry_group
                    else policy.group_ttl_seconds)
    if type(credential.issued_at) is not int \
            or type(credential.expires_at) is not int:
        raise SafetyBarrierTripped("credential timestamps must be int")
    if credential.expires_at - credential.issued_at != expected_ttl:
        raise SafetyBarrierTripped(
            f"credential TTL does not match group {credential.group!r}")
    if not (credential.issued_at <= now < credential.expires_at):
        raise SafetyBarrierTripped(
            "current time is outside the credential validity window")

    header, claims, jwt = _decode_probe_session_token(
        credential.session_token)
    if header != {"alg": "HS256", "typ": "JWT"}:
        raise SafetyBarrierTripped("JWT protected header is not HS256/JWT")
    if hashlib.sha256(jwt.encode("utf-8")).hexdigest() \
            != credential.secret_access_key:
        raise SafetyBarrierTripped(
            "derived secret is not sha256(jwt) — token/secret disagree")

    if claims.get("aud") != endpoint_host:
        raise SafetyBarrierTripped(
            "credential audience is not THIS transport endpoint host")
    if claims.get("iss") != credential.access_key_id:
        raise SafetyBarrierTripped(
            "JWT iss does not equal the credential access key id")
    if claims.get("bucket") != policy.bucket:
        raise ProductionNameDetected("JWT bucket claim is not the probe bucket")
    if claims.get("scope") != policy.credential_scope:
        raise SafetyBarrierTripped("JWT scope claim is not the probe scope")
    if claims.get("group") != credential.group \
            or credential.group not in _matrix_groups(policy):
        raise SafetyBarrierTripped(
            "JWT group claim is not this credential's matrix group")
    if tuple(claims.get("actions") or ()) != policy.credential_actions:
        raise SafetyBarrierTripped("JWT actions claim is not the probe set")
    paths = claims.get("paths")
    if type(paths) is not dict \
            or tuple(paths.get("prefixPaths") or ()) != policy.credential_prefixes \
            or tuple(paths.get("objectPaths") or ()) \
            != policy.credential_object_paths:
        raise SafetyBarrierTripped("JWT paths claim is not the probe set")
    if claims.get("iat") != credential.issued_at \
            or claims.get("exp") != credential.expires_at:
        raise SafetyBarrierTripped(
            "JWT iat/exp disagree with the credential metadata")
    if not _grammar().account_id.fullmatch(str(claims.get("sub") or "")):
        raise SafetyBarrierTripped("JWT sub is not a 32-hex account id")
    if endpoint_host != f"{claims['sub']}.r2.cloudflarestorage.com":
        raise SafetyBarrierTripped(
            "JWT sub account id does not match the endpoint host")
    return credential


# ─────────────────────────────────────────────────────────────────────────
# Credential grouping
# ─────────────────────────────────────────────────────────────────────────

class CredentialGroupPlanner:
    """Refuses to start a group that cannot finish inside its credential.

    Costs are INTERNAL, derived from the one immutable matrix; the caller
    cannot supply negative/NaN/zero costs. T-EXPIRY has its own admission
    policy: its short TTL exists to be outlived, so the ordinary margin
    rule cannot apply — instead the credential must be freshly minted.
    """

    #: Display aliases; enforcement reads the captured policy (LOW item).
    SAFETY_FACTOR = _policy().credential_safety_factor
    REQUIRED_MARGIN_SECONDS = _policy().credential_required_margin_seconds
    EXPIRY_MAX_AGE_SECONDS = _policy().expiry_max_age_seconds

    def estimated_group_cost(self, group) -> float:
        _exact_str(group, "group", max_len=16)
        policy = _policy()
        groups = _matrix_groups(policy)
        if group not in groups:
            raise SafetyBarrierTripped(f"unknown credential group {group!r}")
        return float(sum(spec.cost_seconds for spec in policy.matrix
                         if spec.group == group))

    def can_start(self, *, credential, now) -> tuple:
        if type(credential) is not TemporaryCredential:
            raise SafetyBarrierTripped(
                "credential must be exactly TemporaryCredential")
        if type(now) not in (int, float) or not math.isfinite(now):
            raise SafetyBarrierTripped("now must be a finite number")
        policy = _policy()
        group = credential.group
        if group not in _matrix_groups(policy):
            raise SafetyBarrierTripped(f"unknown credential group {group!r}")

        max_age = policy.expiry_max_age_seconds
        if group == policy.expiry_group:
            age = now - credential.issued_at
            if age < 0 or age > max_age:
                return False, (
                    f"expiry-test credential must be freshly minted "
                    f"(age {age:.0f}s > {max_age:.0f}s)")
            if now >= credential.expires_at:
                return False, "expiry-test credential already expired"
            return True, "ok (expiry policy: fresh mint)"

        factor = policy.credential_safety_factor
        margin = policy.credential_required_margin_seconds
        cost = self.estimated_group_cost(group)
        remaining = credential.seconds_remaining(now)
        needed = cost * factor + margin
        if remaining < needed:
            return False, (
                f"group {group} needs {needed:.0f}s (internal cost "
                f"{cost:.0f}s x{factor} + {margin:.0f}s margin) but the "
                f"credential has {remaining:.0f}s left")
        return True, "ok"

    def assert_credential_matches_test(self, credential, test_id) -> None:
        if type(credential) is not TemporaryCredential:
            raise SafetyBarrierTripped(
                "credential must be exactly TemporaryCredential")
        _exact_str(test_id, "test_id", max_len=16)
        policy = _policy()
        groups = _matrix_groups(policy)
        allowed = groups.get(credential.group, ())
        if test_id not in allowed:
            raise SafetyBarrierTripped(
                f"test {test_id!r} may not run under credential group "
                f"{credential.group!r}")
        expiry_tests = groups.get(policy.expiry_group, ())
        if (credential.group == policy.expiry_group) != (
                test_id in expiry_tests):
            raise SafetyBarrierTripped(
                "the expiry credential is reserved for expiry testing only")


# ─────────────────────────────────────────────────────────────────────────
# Identities + fresh-key allocation (Codex BLOCKER 3 / HIGH 2)
# ─────────────────────────────────────────────────────────────────────────

class RepetitionIdentity(NamedTuple):
    """Structured identity shared between the allocator and the evidence.

    Free-form key strings are never trusted: evidence carries one of these,
    and the aggregator re-derives the expected key from its parts.
    """

    phase: str
    run_id: str
    test_id: str
    repetition: int
    key: str


class RaceIdentity(NamedTuple):
    phase: str
    run_id: str
    test_id: str          # exactly "E2" or "F"
    repetition: int
    key: str
    setup_state: str

    @property
    def repetition_id(self) -> str:
        return f"{self.test_id}/{self.repetition}"


def expected_key_for(*, phase, run_id, test_id, repetition) -> str:
    """The one canonical key formula. Used by the allocator AND by every
    validator, so a hand-written key cannot masquerade as allocated."""
    _exact_str(phase, "phase", max_len=1)
    if phase not in ("p", "t"):
        raise SafetyBarrierTripped("phase must be 'p' or 't'")
    if type(run_id) is not str or not _grammar().run_id.fullmatch(run_id):
        raise SafetyBarrierTripped("run id refused")
    _exact_str(test_id, "test_id", max_len=16)
    if test_id not in known_test_ids():
        raise SafetyBarrierTripped(f"unknown test id {test_id!r}")
    _exact_int(repetition, "repetition", minimum=1, maximum=9999)
    return (f"{_policy().key_prefix}{phase}/{run_id}/"
            f"{test_id.lower()}/{repetition:04d}/obj.json")


def validate_repetition_identity(identity) -> RepetitionIdentity:
    if type(identity) is not RepetitionIdentity:
        raise SafetyBarrierTripped(
            "identity must be exactly RepetitionIdentity")
    expected = expected_key_for(
        phase=identity.phase, run_id=identity.run_id,
        test_id=identity.test_id, repetition=identity.repetition)
    if type(identity.key) is not str or identity.key != expected:
        raise SafetyBarrierTripped(
            "identity key does not match its own phase/run/test/repetition "
            "— free-form keys are not accepted")
    if not _grammar().allocated_key.fullmatch(identity.key):
        raise SafetyBarrierTripped("identity key is not allocator-shaped")
    return identity


def race_setup_state_for(test_id) -> str:
    """Derived from TEST_MATRIX alone (Codex MEDIUM 2)."""
    spec = test_spec(test_id)
    if spec.category != "race" or spec.race_setup_state is None:
        raise SafetyBarrierTripped(
            f"{test_id!r} is not a race test (only "
            f"{list(race_test_ids())} are)")
    return spec.race_setup_state


def validate_race_identity(identity) -> RaceIdentity:
    if type(identity) is not RaceIdentity:
        raise SafetyBarrierTripped("identity must be exactly RaceIdentity")
    required_setup = race_setup_state_for(identity.test_id)
    if type(identity.setup_state) is not str \
            or identity.setup_state != required_setup:
        raise SafetyBarrierTripped(
            f"{identity.test_id} requires setup_state {required_setup!r}, "
            f"got {identity.setup_state!r}")
    expected = expected_key_for(
        phase=identity.phase, run_id=identity.run_id,
        test_id=identity.test_id, repetition=identity.repetition)
    if type(identity.key) is not str or identity.key != expected:
        raise SafetyBarrierTripped(
            "race identity key does not match its own test/repetition")
    return identity


class IssuedIdentity(NamedTuple):
    """An identity plus the run-owned capability that proves the allocator
    issued it (HIGH 3). A manually constructed RepetitionIdentity /
    RaceIdentity has no matching nonce in any allocator registry, so it
    cannot become accepted evidence."""

    identity: object              # RepetitionIdentity | RaceIdentity
    nonce: str


class ProbeKeyAllocator:
    """Unique fixed-format keys per repetition; reuse refused. Also the
    authoritative ISSUANCE REGISTRY (HIGH 3): each allocation mints an
    opaque run-scoped nonce and records `nonce -> identity`. Evidence is
    only accepted when presented with a nonce this allocator issued.

    Thread-safe: the future race runner shares one allocator across its
    writer threads.
    """

    def __init__(self, run_id):
        if type(run_id) is not str or not _grammar().run_id.fullmatch(run_id):
            raise SafetyBarrierTripped(
                "run id must be exactly str, ^[a-z0-9][a-z0-9-]{3,39}$")
        self.run_id = run_id
        self._issued = set()
        self._registry = {}          # nonce -> identity
        self._counter = 0
        self._lock = threading.Lock()

    def _claim(self, key: str, identity) -> str:
        with self._lock:
            if key in self._issued:
                raise SafetyBarrierTripped(
                    f"key reuse refused: {key!r} was already allocated")
            self._issued.add(key)
            self._counter += 1
            nonce = f"{self.run_id}:{self._counter:06d}"
            self._registry[nonce] = identity
        return nonce

    def allocate(self, *, phase, test_id, repetition) -> IssuedIdentity:
        key = expected_key_for(phase=phase, run_id=self.run_id,
                               test_id=test_id, repetition=repetition)
        identity = validate_repetition_identity(RepetitionIdentity(
            phase=phase, run_id=self.run_id, test_id=test_id,
            repetition=repetition, key=key))
        nonce = self._claim(key, identity)
        return IssuedIdentity(identity=identity, nonce=nonce)

    def allocate_race(self, *, phase, test_id, repetition) -> IssuedIdentity:
        """Setup state is DERIVED from the race type, never supplied."""
        setup = race_setup_state_for(test_id)
        key = expected_key_for(phase=phase, run_id=self.run_id,
                               test_id=test_id, repetition=repetition)
        identity = validate_race_identity(RaceIdentity(
            phase=phase, run_id=self.run_id, test_id=test_id,
            repetition=repetition, key=key, setup_state=setup))
        nonce = self._claim(key, identity)
        return IssuedIdentity(identity=identity, nonce=nonce)

    def issued_registry(self) -> dict:
        """A COPY of `nonce -> identity` for everything this allocator
        actually minted (Codex BLOCKER 1).

        Finalization cross-checks every physical ISSUANCE_RECORD against
        this, because a caller-written JSON file cannot prove "the
        allocator issued this" — only the issuer can.
        """
        with self._lock:
            return dict(self._registry)

    def resolve(self, issued) -> object:
        """Return the registered identity for an IssuedIdentity, proving
        the allocator issued it and the identity is byte-identical to what
        was registered. Raises otherwise."""
        if type(issued) is not IssuedIdentity:
            raise SafetyBarrierTripped("expected an IssuedIdentity capability")
        if type(issued.nonce) is not str:
            raise SafetyBarrierTripped("issuance nonce must be str")
        with self._lock:
            registered = self._registry.get(issued.nonce)
        if registered is None:
            raise SafetyBarrierTripped(
                "issuance nonce was never issued by this allocator")
        if issued.identity != registered:
            raise SafetyBarrierTripped(
                "identity does not match the registered issuance")
        return registered


# ─────────────────────────────────────────────────────────────────────────
# Same-key write guard
# ─────────────────────────────────────────────────────────────────────────

class SameKeyWriteGuard:
    """R2 documents 1 write/second/key; above that it returns 429.

    The gap is measured from the previous write's RESPONSE-END to the next
    write's REQUEST-START on that same key, on a monotonic clock.
    `wait_until_writable` LOOPS and re-checks after each sleep — a single
    sleep is never assumed to have advanced the clock — and raises if the
    clock demonstrably fails to advance. Thread-safe.
    """

    #: Display alias; enforcement reads the captured policy (LOW item).
    MIN_GAP_SECONDS = _policy().same_key_min_gap_seconds
    _MAX_WAIT_LOOPS = 64

    def __init__(self, monotonic: Callable[[], float] = time.monotonic,
                 sleep: Callable[[float], None] = time.sleep):
        self._monotonic = monotonic
        self._sleep = sleep
        self._min_gap = _policy().same_key_min_gap_seconds
        self._last_response_end = {}
        self._lock = threading.Lock()

    def note_write_response_end(self, key, mono_ts=None) -> None:
        _exact_str(key, "key", max_len=512)
        if mono_ts is not None and (type(mono_ts) not in (int, float)
                                    or not math.isfinite(mono_ts)):
            raise SafetyBarrierTripped("mono_ts must be a finite number")
        with self._lock:
            self._last_response_end[key] = (
                self._monotonic() if mono_ts is None else float(mono_ts))

    def seconds_until_writable(self, key, now=None) -> float:
        _exact_str(key, "key", max_len=512)
        with self._lock:
            last = self._last_response_end.get(key)
        if last is None:
            return 0.0
        now = self._monotonic() if now is None else now
        remaining = self._min_gap - (now - last)
        return remaining if remaining > 0.0 else 0.0

    def wait_until_writable(self, key) -> float:
        total = 0.0
        for _ in range(self._MAX_WAIT_LOOPS):
            remaining = self.seconds_until_writable(key)
            if remaining <= 0.0:
                return total
            self._sleep(remaining)
            total += remaining
        raise SafetyBarrierTripped(
            "monotonic clock did not advance across "
            f"{self._MAX_WAIT_LOOPS} sleep attempts — refusing to write")


# ─────────────────────────────────────────────────────────────────────────
# Hard resource caps (Codex MEDIUM 1 + MEDIUM 3 of round 1)
# ─────────────────────────────────────────────────────────────────────────

class ResourceCaps(NamedTuple):
    max_production_size_puts: int
    max_put_attempts: int
    max_get_head: int
    max_object_keys: int
    max_uploaded_bytes: int
    max_peak_storage_bytes: int


def fixed_resource_caps() -> ResourceCaps:
    """The authorized caps, read from the closure policy."""
    caps = _policy().caps
    return ResourceCaps(*caps)


class PutReservation(NamedTuple):
    key: str
    body_len: int
    prior_size: int | None
    had_prior: bool
    token: int


class RacePairWinner(enum.Enum):
    """Which same-key race writer committed. An exact enum, so `True`/`1`
    cannot be mistaken for writer 1 (HIGH B). The live runner must DERIVE
    this from the validated classify_race_repetition outcome."""

    WRITER_1 = "WRITER_1"
    WRITER_2 = "WRITER_2"
    NONE = "NONE"


class _RacePairState(NamedTuple):
    """LEDGER-INTERNAL authoritative same-key race-pair state. Callers only
    ever hold an opaque pair id, so key/lengths/prior cannot be forged."""

    key: str
    first: PutReservation
    second: PutReservation
    first_len: int
    second_len: int
    prior_size: int | None


class LedgerPoisoned(ProbeError):
    """Raised once a cap has been exceeded. The ledger is terminally
    unusable: counters may be inconsistent after a partial charge, so
    continuing would silently under-count. Fail closed, forever."""

    exit_code = EXIT_CAP_EXCEEDED


class ResourceLedger:
    """Absolute stop caps. There is no extension path, by design.

    CONCURRENCY MODEL (Codex MEDIUM 1). The race coordinator reserves BOTH
    writers' PUT attempts SEQUENTIALLY, before releasing the barrier;
    writer threads never touch the ledger. `reserve_race_pair` encodes
    that contract. A mutex additionally guards every mutation so a future
    refactor cannot silently undercount.

    POISONING. When a cap is exceeded the ledger records the breach and
    every subsequent operation raises `LedgerPoisoned`. Catching
    `CapExceeded` and continuing is therefore impossible: the probe stops.

    Accounting is conservative: `reserve_put` charges EVERYTHING (attempt,
    bytes, key, storage) BEFORE transmission; `resolve_put` releases the
    storage assumption only when a definite non-commit is proven. 412 and
    429 always remain counted as attempts and uploaded bytes.
    """

    def __init__(self):
        self._caps = fixed_resource_caps()
        self.production_size_puts = 0
        self.put_operation_count = 0
        self.get_head_count = 0
        self.uploaded_bytes = 0
        self._live_objects = {}
        self._all_keys = set()
        self.peak_storage_bytes = 0
        self._poisoned = None
        self._lock = threading.RLock()
        self._next_token = 1
        # token -> the AUTHORITATIVE reservation the ledger itself created.
        # resolve_put trusts THIS, never the caller's object (MEDIUM 1).
        self._open_reservations = {}
        # Tokens that belong to a same-key race pair — resolvable ONLY via
        # resolve_race_pair, never resolve_put.
        self._race_pair_tokens = set()
        # pair_id -> _RacePairState (ledger-internal authority).
        self._race_pairs = {}
        self._next_pair_id = 0

    @classmethod
    def for_testing(cls, caps) -> "ResourceLedger":
        """TESTS ONLY. The live probe never constructs a ledger this way."""
        if type(caps) is not ResourceCaps:
            raise SafetyBarrierTripped("caps must be exactly ResourceCaps")
        ledger = cls()
        ledger._caps = caps
        return ledger

    @property
    def poisoned(self) -> bool:
        return self._poisoned is not None

    @property
    def object_count(self) -> int:
        return len(self._all_keys)

    def _assert_usable(self) -> None:
        if self._poisoned is not None:
            raise LedgerPoisoned(
                f"ledger is poisoned after a cap breach ({self._poisoned}); "
                "no further probe operations may proceed")

    def _check(self, name: str, value: int, cap: int) -> None:
        if value > cap:
            self._poisoned = f"{name} {value} > {cap}"
            raise CapExceeded(f"hard cap exceeded: {name} {value} > {cap}")

    def _reserve_locked(self, key, body_len) -> PutReservation:
        _exact_str(key, "key", max_len=512)
        _exact_int(body_len, "body_len", minimum=0)
        policy = _policy()

        self.put_operation_count += 1
        self._check("put_attempts", self.put_operation_count,
                    self._caps.max_put_attempts)

        if body_len == policy.production_body_bytes:
            self.production_size_puts += 1
            self._check("production_size_puts", self.production_size_puts,
                        self._caps.max_production_size_puts)

        self.uploaded_bytes += body_len
        self._check("uploaded_bytes", self.uploaded_bytes,
                    self._caps.max_uploaded_bytes)

        self._all_keys.add(key)
        self._check("object_keys", self.object_count,
                    self._caps.max_object_keys)

        had_prior = key in self._live_objects
        prior = self._live_objects.get(key)
        self._live_objects[key] = body_len
        live = sum(self._live_objects.values())
        self.peak_storage_bytes = max(self.peak_storage_bytes, live)
        self._check("peak_storage_bytes", self.peak_storage_bytes,
                    self._caps.max_peak_storage_bytes)

        token = self._next_token
        self._next_token += 1
        reservation = PutReservation(key, body_len, prior, had_prior, token)
        self._open_reservations[token] = reservation
        return reservation

    def reserve_put(self, key, body_len) -> PutReservation:
        with self._lock:
            self._assert_usable()
            return self._reserve_locked(key, body_len)

    def reserve_race_pair(self, first_key, first_len,
                          second_key, second_len) -> tuple:
        """Reserve two DIFFERENT-key race writers before barrier release.

        Equal keys are REFUSED (HIGH A): a same-key race must go through
        `reserve_race_pair_same_key`, which returns a handle that can only
        be settled atomically. There is deliberately no other path.
        """
        _exact_str(first_key, "first_key", max_len=512)
        _exact_str(second_key, "second_key", max_len=512)
        if first_key == second_key:
            raise SafetyBarrierTripped(
                "reserve_race_pair is for two DIFFERENT keys; a same-key "
                "race must use reserve_race_pair_same_key so it can be "
                "settled atomically")
        with self._lock:
            self._assert_usable()
            first = self._reserve_locked(first_key, first_len)
            second = self._reserve_locked(second_key, second_len)
            return first, second

    def reserve_race_pair_same_key(self, key, first_len, second_len) -> str:
        """Reserve BOTH writers of a SAME-KEY race, returning an OPAQUE id.

        Same-key race writers must never be resolved independently: if
        writer 2 wins and writer 1 later resolves as a loser, an
        independent loser resolution could pop/restore the winner's
        storage. The returned value is a bare opaque pair id (HIGH B) — it
        carries no caller-visible key or lengths, so there is nothing to
        forge. All authoritative state lives in `_race_pairs`.
        """
        with self._lock:
            self._assert_usable()
            first = self._reserve_locked(key, first_len)
            second = self._reserve_locked(key, second_len)
            self._race_pair_tokens.add(first.token)
            self._race_pair_tokens.add(second.token)
            self._next_pair_id += 1
            pair_id = f"pair-{self._next_pair_id:06d}"
            self._race_pairs[pair_id] = _RacePairState(
                key=key, first=first, second=second,
                first_len=first_len, second_len=second_len,
                prior_size=(first.prior_size if first.had_prior else None))
            return pair_id

    def resolve_race_pair(self, pair_id, *, winner) -> None:
        """Settle a same-key race pair atomically under one lock.

        `pair_id` is only a lookup key: the ledger derives the object key,
        both body lengths and the prior size from its OWN stored state
        (HIGH B), never from caller input. `winner` must be an exact
        `RacePairWinner` — bools and raw ints are refused, so `winner=True`
        can no longer be mistaken for writer 1.

        Both PUT attempts and uploaded bytes were already counted at
        reservation. This installs the final live size from the actual
        winner exactly once; the loser never pops/restores over it. If
        neither committed, the prior object size is restored.

        NOTE for the eventual live runner: `winner` must be DERIVED from the
        validated `classify_race_repetition` outcome for the repetition, not
        chosen freely at the call site.
        """
        if type(pair_id) is not str:
            raise SafetyBarrierTripped("pair_id must be exactly str")
        if type(winner) is not RacePairWinner:
            raise SafetyBarrierTripped(
                "winner must be exactly a RacePairWinner enum member "
                "(bools and raw ints are refused)")
        with self._lock:
            self._assert_usable()
            state = self._race_pairs.get(pair_id)
            if state is None:
                raise SafetyBarrierTripped(
                    "unknown or already-settled race pair id")
            for res in (state.first, state.second):
                if self._open_reservations.get(res.token) != res:
                    self._poisoned = "race pair reservations no longer match"
                    raise SafetyBarrierTripped(
                        "race pair state does not match the ledger — "
                        "refusing (ledger poisoned)")
            # Final live size derives ONLY from stored authoritative state.
            if winner is RacePairWinner.NONE:
                final = state.prior_size
            elif winner is RacePairWinner.WRITER_1:
                final = state.first_len
            else:
                final = state.second_len
            del self._open_reservations[state.first.token]
            del self._open_reservations[state.second.token]
            self._race_pair_tokens.discard(state.first.token)
            self._race_pair_tokens.discard(state.second.token)
            del self._race_pairs[pair_id]
            if final is None:
                self._live_objects.pop(state.key, None)
            else:
                self._live_objects[state.key] = final
            live = sum(self._live_objects.values())
            self.peak_storage_bytes = max(self.peak_storage_bytes, live)
            self._check("peak_storage_bytes", self.peak_storage_bytes,
                        self._caps.max_peak_storage_bytes)

    def resolve_put(self, reservation, *, committed) -> None:
        """Resolve a reservation once the outcome is DEFINITE.

        The caller's `reservation` is used ONLY to look up its token; the
        ledger then resolves its OWN stored authoritative record and
        additionally requires the caller's object to be field-for-field
        identical to it. A forged PutReservation carrying a real open
        token but a different key/prior therefore cannot cause an
        undercount — the equality check fails closed and poisons the
        ledger (MEDIUM 1).

        committed=False (proven non-commit: 412/429/403/definite client
        rejection) restores the prior storage state. Attempts and uploaded
        bytes are never released. An ambiguous attempt is simply never
        resolved and stays conservatively charged.
        """
        if type(reservation) is not PutReservation:
            raise SafetyBarrierTripped(
                "reservation must be exactly PutReservation")
        _exact_bool(committed, "committed")
        with self._lock:
            self._assert_usable()
            if reservation.token in self._race_pair_tokens:
                raise SafetyBarrierTripped(
                    "this reservation belongs to a same-key race pair and "
                    "may only be settled via resolve_race_pair (HIGH 4)")
            authoritative = self._open_reservations.get(reservation.token)
            if authoritative is None:
                raise SafetyBarrierTripped(
                    "reservation token is unknown or already resolved")
            if reservation != authoritative:
                # A real token wrapped around forged fields. Fail closed.
                self._poisoned = "forged reservation presented to resolve_put"
                raise SafetyBarrierTripped(
                    "reservation does not match the ledger's authoritative "
                    "record for its token — refusing (ledger poisoned)")
            del self._open_reservations[authoritative.token]
            if committed:
                return
            if authoritative.had_prior:
                self._live_objects[authoritative.key] = \
                    authoritative.prior_size
            else:
                self._live_objects.pop(authoritative.key, None)
            # peak_storage_bytes deliberately keeps its high-water mark.

    def charge_get_head(self, count=1) -> None:
        with self._lock:
            self._assert_usable()
            _exact_int(count, "count", minimum=1)
            self.get_head_count += count
            self._check("get_head", self.get_head_count,
                        self._caps.max_get_head)

    def open_reservation_counts(self) -> tuple:
        """(open single-PUT reservations, open same-key race pairs).

        The final PASS gate requires BOTH to be zero: an unresolved PUT
        reservation means the runner never proved whether that body
        committed, and a probe that cannot account for every write it may
        have made must never report PASS."""
        with self._lock:
            open_puts = sum(1 for token in self._open_reservations
                            if token not in self._race_pair_tokens)
            return open_puts, len(self._race_pairs)

    def snapshot(self) -> dict:
        with self._lock:
            open_puts = sum(1 for token in self._open_reservations
                            if token not in self._race_pair_tokens)
            return {
                "object_count": self.object_count,
                "put_operation_count": self.put_operation_count,
                "production_size_puts": self.production_size_puts,
                "get_head_count": self.get_head_count,
                "uploaded_bytes": self.uploaded_bytes,
                "peak_storage_bytes": self.peak_storage_bytes,
                "poisoned": self.poisoned,
                "open_put_reservations": open_puts,
                "open_race_pairs": len(self._race_pairs),
            }


# ─────────────────────────────────────────────────────────────────────────
# Synthetic payloads
# ─────────────────────────────────────────────────────────────────────────

def synthetic_payload(seed, size) -> bytes:
    """Deterministic, valid JSON of EXACTLY `size` bytes.

    Never derived from the shipped catalog manifest — the probe does not
    open that file, so real catalog bytes cannot enter its address space
    and therefore cannot be uploaded anywhere.
    """
    _exact_str(seed, "seed", max_len=64)
    _exact_int(size, "size", minimum=1)
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", seed):
        raise SafetyBarrierTripped(f"unsafe payload seed {seed!r}")
    prefix = ('{"__probe__":true,"not_a_catalog":true,"seed":"'
              + seed + '","filler":"')
    suffix = '"}'
    overhead = len(prefix) + len(suffix)
    if size < overhead:
        raise SafetyBarrierTripped(
            f"size {size} is below the {overhead}-byte minimum for "
            f"seed {seed!r}")
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    start = hashlib.sha256(seed.encode("utf-8")).digest()[0] % len(alphabet)
    filler = "".join(alphabet[(start + i) % len(alphabet)]
                     for i in range(size - overhead))
    body = (prefix + filler + suffix).encode("utf-8")
    if len(body) != size:
        raise SafetyBarrierTripped(
            f"payload builder produced {len(body)} bytes, expected {size}")
    return body


def production_size_payload(seed) -> bytes:
    return synthetic_payload(seed, _policy().production_body_bytes)


def diagnostic_body(test_id) -> bytes:
    """The EXACT body each signing/expiry diagnostic transmits.

    Derived from the row id alone, so the transport builds the body itself
    and no caller can choose what a diagnostic writes (Codex round-3
    BLOCKER 2).
    """
    _exact_str(test_id, "test_id", max_len=16)
    if test_id not in ("I2", "I3", "I4"):
        raise SafetyBarrierTripped(
            f"{test_id!r} is not a signing/expiry diagnostic row")
    return synthetic_payload(test_id.lower(), 256)


# ─────────────────────────────────────────────────────────────────────────
# Transport
# ─────────────────────────────────────────────────────────────────────────

class ErrorCategory(enum.Enum):
    TRANSPORT_CONNECT_FAILED = "TRANSPORT_CONNECT_FAILED"
    TRANSPORT_TLS_FAILED = "TRANSPORT_TLS_FAILED"
    TRANSPORT_TIMEOUT_BEFORE_RESPONSE = "TRANSPORT_TIMEOUT_BEFORE_RESPONSE"
    TRANSPORT_TIMEOUT_AFTER_SEND = "TRANSPORT_TIMEOUT_AFTER_SEND"
    TRANSPORT_CONNECTION_RESET = "TRANSPORT_CONNECTION_RESET"
    RESPONSE_MALFORMED = "RESPONSE_MALFORMED"
    INTERNAL_ASSERTION = "INTERNAL_ASSERTION"
    SAFETY_BARRIER_TRIPPED = "SAFETY_BARRIER_TRIPPED"


class SendPhase(enum.Enum):
    """Where a transport failure happened — what decides whether a
    mutation was possible.

    BEFORE_REQUEST    — the failure preceded conn.request(); no request
                        bytes can have existed. Definite no-mutation.
    DURING_REQUEST    — conn.request() raised. http.client's request()
                        connects AND writes: it may fail after opening the
                        socket, after sending headers, after sending part
                        or all of a PUT body — or after the server
                        committed. ALWAYS ambiguous.
    AWAITING_RESPONSE — the request was fully written but no response
                        arrived. ALWAYS ambiguous.
    """

    BEFORE_REQUEST = "BEFORE_REQUEST"
    DURING_REQUEST = "DURING_REQUEST"
    AWAITING_RESPONSE = "AWAITING_RESPONSE"


class TransportFailure(Exception):
    def __init__(self, category: ErrorCategory, phase: SendPhase,
                 exception_type_name: str):
        super().__init__(category.value)
        self.category = category
        self.phase = phase
        self.exception_type_name = exception_type_name


def classify_exception(exc: BaseException, phase: SendPhase) -> ErrorCategory:
    if isinstance(exc, ProbeError):
        return ErrorCategory.SAFETY_BARRIER_TRIPPED
    if isinstance(exc, ssl.SSLError):
        return ErrorCategory.TRANSPORT_TLS_FAILED
    if isinstance(exc, TimeoutError):
        if phase is SendPhase.BEFORE_REQUEST:
            return ErrorCategory.TRANSPORT_CONNECT_FAILED
        if phase is SendPhase.DURING_REQUEST:
            return ErrorCategory.TRANSPORT_TIMEOUT_AFTER_SEND
        return ErrorCategory.TRANSPORT_TIMEOUT_BEFORE_RESPONSE
    if isinstance(exc, ConnectionResetError):
        return ErrorCategory.TRANSPORT_CONNECTION_RESET
    if isinstance(exc, ConnectionError):
        return ErrorCategory.TRANSPORT_CONNECT_FAILED
    if isinstance(exc, OSError):
        return (ErrorCategory.TRANSPORT_CONNECT_FAILED
                if phase is SendPhase.BEFORE_REQUEST
                else ErrorCategory.TRANSPORT_CONNECTION_RESET)
    if isinstance(exc, AssertionError):
        return ErrorCategory.INTERNAL_ASSERTION
    return ErrorCategory.RESPONSE_MALFORMED


class RawResponse(NamedTuple):
    status: int
    headers: tuple
    body: bytes
    body_truncated: bool
    t_request_start_mono_ns: int
    t_response_end_mono_ns: int

    def header(self, name: str) -> str | None:
        lowered = name.lower()
        for key, value in self.headers:
            if key.lower() == lowered:
                return value
        return None


class TransportAttempt(NamedTuple):
    """The ONE physical authority for a single transmit (Codex round 2).

    It carries exactly what was signed, what (if anything) came back, and —
    critically — the monotonic instant captured AT the `conn.request(...)`
    boundary (`t_request_attempt_mono_ns`), never before connection creation.
    Race skew, K3 throttle windows and every timestamp in evidence derive
    from THIS object, so a timestamp taken before the real transmission can
    never be mistaken for the transmission time.

    `t_request_attempt_mono_ns` is None ONLY when the failure preceded
    `conn.request` (SendPhase.BEFORE_REQUEST) — i.e. no request was ever
    attempted. It is populated even when `conn.request` itself raises.
    """

    signed_request: object          # SignedRequest actually transmitted
    response: object                # RawResponse | None
    failure: object                 # TransportFailure | None
    send_phase: object              # SendPhase
    t_request_attempt_mono_ns: object   # int | None (None iff BEFORE_REQUEST)
    t_response_end_mono_ns: object      # int | None

    @property
    def status(self):
        return self.response.status if self.response is not None else None

    def header(self, name):
        return self.response.header(name) if self.response is not None else None


class RefusingConnectionFactory:
    """The default. Constructing a connection raises, so `--plan` cannot
    reach the network even if a caller forgets to check the mode."""

    def __call__(self, host, timeout):  # pragma: no cover - guard
        raise SafetyBarrierTripped(
            "no connection factory installed: this probe is in plan/offline "
            "mode and must not open sockets")


def real_connection_factory(host, timeout):
    """The only place a real socket would ever be created.

    `http.client` is chosen deliberately over `urllib.request`: urllib
    honours HTTP_PROXY/HTTPS_PROXY from the environment and follows
    redirects, and http.client does neither.
    """
    import http.client  # imported here so plan mode never touches it

    if type(host) is not str or not _grammar().endpoint_host.fullmatch(host):
        raise EndpointRefused("connection host refused")
    assert_environment_clean()
    context = ssl.create_default_context()
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    if getattr(context, "keylog_filename", None):
        raise SafetyBarrierTripped("TLS key logging is enabled — refusing")
    return http.client.HTTPSConnection(host, timeout=timeout, context=context)


class R2Transport:
    """Live boundary: `sign_and_send`. Offline helper: `send_signed_offline`.

    `sign_and_send` is the ONLY method the future live runner may use. It
    accepts validated primitives plus a TemporaryCredential, signs
    internally, and transmits the exact bytes it just signed. No
    caller-owned request object exists between signing and transmission,
    so post-signing mutation of Authorization / x-amz-date /
    x-amz-content-sha256 / x-amz-security-token / body is structurally
    impossible.
    """

    def __init__(self, *, endpoint_host, connection_factory=None,
                 timeout=30.0, monotonic=time.monotonic_ns,
                 wall_clock=time.time):
        _exact(endpoint_host, str, "endpoint_host")
        self.endpoint_host = assert_endpoint_allowed(f"https://{endpoint_host}")
        self._factory = connection_factory or RefusingConnectionFactory()
        if type(timeout) not in (int, float) or not math.isfinite(timeout) \
                or not (1.0 <= float(timeout) <= 300.0):
            raise SafetyBarrierTripped("timeout must be 1..300 seconds")
        self._timeout = float(timeout)
        self._monotonic = monotonic
        # The ACTUAL wall clock decides credential freshness (MEDIUM 1) —
        # never the request signer's chosen amz_date. Injectable for tests.
        self._wall_clock = wall_clock
        self.ledger = []

    # ── The live primitive ───────────────────────────────────────────────

    def _assert_amz_date_fresh(self, credential, amz_date):
        """Shared credential/date pre-send validation for ORDINARY traffic.

        Returns the wall-clock `now` used, so callers need not read it twice.
        """
        if type(credential) is not TemporaryCredential:
            raise SafetyBarrierTripped(
                "a live send requires exactly a TemporaryCredential")
        _exact_str(amz_date, "amz_date", max_len=17)
        if not _grammar().amz_date.fullmatch(amz_date):
            raise SafetyBarrierTripped(f"malformed x-amz-date {amz_date!r}")
        actual_now = self._wall_clock()
        if type(actual_now) not in (int, float) or not math.isfinite(actual_now):
            raise SafetyBarrierTripped("wall clock returned a non-finite value")
        skew = _policy().max_amz_date_skew_seconds
        request_epoch = _amz_date_to_epoch(amz_date)
        if abs(request_epoch - actual_now) > skew:
            raise SafetyBarrierTripped(
                f"amz_date is {abs(request_epoch - actual_now):.0f}s from the "
                f"wall clock (max {skew}s) — refusing")
        validate_probe_credential_for_transport(
            credential, endpoint_host=self.endpoint_host, now=actual_now)
        return actual_now

    def sign_and_attempt(self, *, target, body, credential, amz_date,
                         extra_headers=None, include_content_md5=False,
                         allow_denied_prefix_probe=False,
                         max_response_bytes=None) -> TransportAttempt:
        """THE ordinary live path. Validate → sign → transmit as ONE step,
        returning the single authoritative TransportAttempt (the exact
        signed request, the response-or-failure, and the request-attempt
        timestamp). The credential and amz_date are validated against the
        ACTUAL wall clock before anything is signed or a socket considered.
        """
        self._assert_amz_date_fresh(credential, amz_date)
        signed = sign_request(
            target=target, host=self.endpoint_host,
            access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=credential.session_token,
            body=body, amz_date=amz_date, extra_headers=extra_headers,
            include_content_md5=include_content_md5)
        return self._attempt(
            signed, allow_denied_prefix_probe=allow_denied_prefix_probe,
            max_response_bytes=max_response_bytes)

    def sign_and_send(self, *, target, body, credential, amz_date,
                      extra_headers=None, include_content_md5=False,
                      allow_denied_prefix_probe=False,
                      max_response_bytes=None) -> RawResponse:
        """Back-compatible wrapper over `sign_and_attempt`: returns the
        RawResponse or re-raises the captured TransportFailure. New code
        should prefer `sign_and_attempt` so it also gets the signed request
        and the request-attempt timestamp."""
        attempt = self.sign_and_attempt(
            target=target, body=body, credential=credential, amz_date=amz_date,
            extra_headers=extra_headers, include_content_md5=include_content_md5,
            allow_denied_prefix_probe=allow_denied_prefix_probe,
            max_response_bytes=max_response_bytes)
        if attempt.failure is not None:
            raise attempt.failure
        return attempt.response

    # ── The three EXACT signing/expiry diagnostics ───────────────────────
    #
    # There is deliberately NO general diagnostic primitive (Codex round-3
    # BLOCKER 2). Each row is its own method: the caller supplies ONLY the
    # allocator-issued identity and that group's child credential, and the
    # method derives method/bucket/key/query/body/date ITSELF from captured
    # policy. A caller cannot choose the shape of a diagnostic request, so
    # an arbitrary DELETE (with or without a `versionId` query) has no path
    # to a live-configured connection factory.

    def _diagnostic_target(self, test_id, identity):
        """Validate the identity for `test_id` and build its EXACT target."""
        spec = test_spec(test_id)
        if type(identity) is not RepetitionIdentity:
            raise SafetyBarrierTripped(
                "a diagnostic requires exactly an allocator RepetitionIdentity")
        validate_repetition_identity(identity)
        if identity.test_id != test_id:
            raise SafetyBarrierTripped(
                f"identity is for {identity.test_id!r}, not {test_id!r}")
        # method/bucket/key/query are FIXED: PUT, the probe bucket, this
        # repetition's own canonical key, and an empty query.
        return spec, new_request_target(
            method="PUT", bucket=_policy().bucket, key=identity.key, query=())

    def _assert_diagnostic_credential(self, spec, credential):
        if type(credential) is not TemporaryCredential:
            raise SafetyBarrierTripped(
                "a diagnostic requires exactly a TemporaryCredential")
        if credential.group != spec.group:
            raise SafetyBarrierTripped(
                f"{spec.id} requires the {spec.group!r} child credential, "
                f"got {credential.group!r}")

    def _diagnostic_amz_date(self):
        """The request date is derived from the transport's OWN wall clock —
        never supplied by a caller."""
        now = self._wall_clock()
        if type(now) not in (int, float) or not math.isfinite(now):
            raise SafetyBarrierTripped("wall clock returned a non-finite value")
        return format_amz_date(int(now)), int(now)

    def attempt_i2(self, *, identity, credential) -> TransportAttempt:
        """I2 — token PHYSICALLY on the wire, excluded from SignedHeaders."""
        spec, target = self._diagnostic_target("I2", identity)
        self._assert_diagnostic_credential(spec, credential)
        amz_date, _now = self._diagnostic_amz_date()
        signed = sign_request(
            target=target, host=self.endpoint_host,
            access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=None,
            unsigned_session_token=credential.session_token,
            body=diagnostic_body("I2"), amz_date=amz_date, extra_headers=None)
        return self._attempt(signed, allow_denied_prefix_probe=False,
                             max_response_bytes=None)

    def attempt_i3(self, *, identity, credential) -> TransportAttempt:
        """I3 — signed with the child key, NO session token on the wire."""
        spec, target = self._diagnostic_target("I3", identity)
        self._assert_diagnostic_credential(spec, credential)
        amz_date, _now = self._diagnostic_amz_date()
        signed = sign_request(
            target=target, host=self.endpoint_host,
            access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=None, unsigned_session_token=None,
            body=diagnostic_body("I3"), amz_date=amz_date, extra_headers=None)
        return self._attempt(signed, allow_denied_prefix_probe=False,
                             max_response_bytes=None)

    def attempt_i4(self, *, identity, credential) -> TransportAttempt:
        """I4 — a normally-bound token whose credential has ALREADY expired.

        The expiry is PROVEN locally before anything is signed: the request
        time must be at or past `credential.expires_at`, and the transmitted
        token's own `exp` claim must agree with that value. Freshness is not
        skipped merely because a caller asked for "expired" mode — this
        method refuses to run while the credential is still valid.
        """
        spec, target = self._diagnostic_target("I4", identity)
        self._assert_diagnostic_credential(spec, credential)
        amz_date, now = self._diagnostic_amz_date()
        if now < credential.expires_at:
            raise SafetyBarrierTripped(
                "the I4 diagnostic requires an ALREADY-EXPIRED credential "
                f"(now {now} < expires_at {credential.expires_at})")
        # The token's own signed claims must carry that same expiry, so the
        # row cannot be satisfied by a credential object whose metadata was
        # edited to look expired.
        _header, claims, _jwt = _decode_probe_session_token(
            credential.session_token)
        if claims.get("exp") != credential.expires_at \
                or claims.get("group") != spec.group:
            raise SafetyBarrierTripped(
                "the I4 token claims disagree with the credential's expiry "
                "or group")
        signed = sign_request(
            target=target, host=self.endpoint_host,
            access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=credential.session_token,
            unsigned_session_token=None,
            body=diagnostic_body("I4"), amz_date=amz_date, extra_headers=None)
        return self._attempt(signed, allow_denied_prefix_probe=False,
                             max_response_bytes=None)

    # ── Shared wire validation + transmission ────────────────────────────

    def _attempt(self, signed, *, allow_denied_prefix_probe,
                 max_response_bytes) -> TransportAttempt:
        """THE single transmit. Fully validates the wire (allowlist,
        bucket/key barriers, host), then transmits, capturing the
        request-attempt timestamp AT the `conn.request(...)` boundary and
        returning a TransportAttempt. A transport error is CAPTURED in the
        result (never raised), so the caller always learns the send phase
        and the attempt timestamp; only a genuine safety/validation error
        (a ProbeError, including a refused redirect) still raises.
        """
        policy = _policy()
        if type(signed) is not SignedRequest:
            raise SafetyBarrierTripped(
                "signed must be exactly SignedRequest (subclasses refused)")
        method, bucket, key, query = assert_target_allowed(
            signed.target,
            allow_denied_prefix_probe=allow_denied_prefix_probe)

        host = signed.host
        if type(host) is not str or not _grammar().endpoint_host.fullmatch(host):
            raise EndpointRefused("signed host refused")
        if host != self.endpoint_host:
            raise EndpointRefused(
                "signed host does not match the transport endpoint")

        body = signed.body
        if type(body) is not bytes \
                or len(body) > policy.production_body_bytes:
            raise SafetyBarrierTripped("body must be exactly bytes, bounded")

        if type(signed.headers) is not tuple:
            raise SafetyBarrierTripped("headers must be exactly tuple")
        allowlist = policy.wire_header_allowlist
        wire = {}
        for item in signed.headers:
            if type(item) is not tuple or len(item) != 2:
                raise SafetyBarrierTripped("header items must be 2-tuples")
            name, value = item
            if type(name) is not str or not _grammar().header_name.fullmatch(name):
                raise SafetyBarrierTripped(
                    f"header name {name!r} refused (lowercase token names "
                    "only — case-variants cannot exist)")
            if type(value) is not str \
                    or any(ch in value for ch in "\x00\r\n"):
                raise SafetyBarrierTripped(f"header {name} value refused")
            if name in policy.transport_owned_headers:
                raise SafetyBarrierTripped(
                    f"header {name!r} is transport-owned and may never be "
                    "supplied: Host is bound to the validated connection "
                    "host and Content-Length to the exact body bytes")
            # COMPLETE wire allowlist (Codex BLOCKER 3). A header outside it
            # — x-amz-copy-source, x-amz-acl, x-amz-website-redirect-location,
            # any multipart or unknown x-amz-* mutation header — is refused
            # HERE, before a socket, even on a hand-built request. Credential
            # scope is never trusted to save an unsafe local request.
            if name not in allowlist:
                raise SafetyBarrierTripped(
                    f"header {name!r} is not on the wire allowlist "
                    f"({sorted(allowlist)}) — refusing before any socket")
            if name in wire:
                raise SafetyBarrierTripped(f"duplicate header {name!r}")
            wire[name] = value
        for required in ("authorization", "x-amz-date",
                         "x-amz-content-sha256"):
            if required not in wire:
                raise SafetyBarrierTripped(
                    f"required header {required!r} is missing")

        # Rebuild the request path from validated primitives — never from
        # an instance method or a caller-formatted string.
        path_only = _canonical_uri(bucket, key)
        query_text = _canonical_query(query)
        path = f"{path_only}?{query_text}" if query_text else path_only
        if not path.isascii() or " " in path \
                or any(ch in path for ch in "\x00\r\n\t"):
            raise SafetyBarrierTripped("request path refused")
        # The bucket-address check is on the PATH portion only: a bucket-
        # level ListObjectsV2 (empty key) legitimately carries `?list-type=2`,
        # and a query string can never change which bucket is addressed.
        if path_only != f"/{policy.bucket}" \
                and not path_only.startswith(f"/{policy.bucket}/"):
            raise ProductionNameDetected(
                "resolved request path does not address the probe bucket")

        cap = policy.max_response_body_bytes
        max_response = (cap if max_response_bytes is None
                        else _exact_int(max_response_bytes,
                                        "max_response_bytes", minimum=1,
                                        maximum=cap))

        self.ledger.append({
            "method": method, "bucket": bucket, "key": key, "path": path,
            "query": [name for name, _ in query], "body_len": len(body)})
        # ── END OF WIRE VALIDATION — locals only from here down ──────────

        conn = None
        phase = SendPhase.BEFORE_REQUEST
        t_attempt = None
        t_end = None
        response = None
        failure = None
        try:
            conn = self._factory(host, self._timeout)
            # Capture the attempt time AT the actual conn.request boundary —
            # after the connection exists, immediately before bytes go out
            # (Codex BLOCKER 2). From here on any exception means bytes MAY
            # have been sent and the server MAY have committed.
            phase = SendPhase.DURING_REQUEST
            t_attempt = self._monotonic()
            conn.request(method, path, body=body or None, headers=wire)
            phase = SendPhase.AWAITING_RESPONSE
            raw_response = conn.getresponse()
            status = raw_response.status
            headers_out = tuple((k, v) for k, v in raw_response.getheaders())
            raw = raw_response.read(max_response + 1)
            truncated = len(raw) > max_response
            body_out = raw[:max_response]
            t_end = self._monotonic()
            if 300 <= status < 400:
                raise SafetyBarrierTripped(
                    f"redirect status {status} received; redirects are never "
                    "followed")
            response = RawResponse(
                status=status, headers=headers_out, body=body_out,
                body_truncated=truncated, t_request_start_mono_ns=t_attempt,
                t_response_end_mono_ns=t_end)
        except ProbeError:
            raise
        except BaseException as exc:  # noqa: BLE001 — mapped to safe category
            failure = TransportFailure(classify_exception(exc, phase), phase,
                                       type(exc).__name__)
            t_end = self._monotonic()
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:  # noqa: BLE001 — close must never leak
                    pass

        return TransportAttempt(
            signed_request=signed, response=response, failure=failure,
            send_phase=phase, t_request_attempt_mono_ns=t_attempt,
            t_response_end_mono_ns=t_end)


class OfflineSignerHarness(R2Transport):
    """TEST-ONLY transport for exercising the pure signer against fakes.

    WHY IT IS SEPARATE (Codex round-3 BLOCKER 2). The live `R2Transport`
    exposes NO method that transmits a caller-owned `SignedRequest`: its
    only send paths sign internally (`sign_and_attempt`) or are the three
    exact diagnostics (`attempt_i2/3/4`). That closes the route by which a
    caller-shaped request — an arbitrary DELETE, a `versionId` query —
    could reach a live-configured connection factory.

    The offline tests still need to push a hand-built SignedRequest through
    the wire validator, so that capability lives HERE, on a class the
    runner and the CLI never construct, and which is STRUCTURALLY unable to
    be live: its constructor refuses `real_connection_factory` outright and
    accepts only a factory explicitly marked as an offline double via
    `offline_connection_double`. It is not enough for a method to be named
    "offline" while its safety depends on what the caller installed.
    """

    def __init__(self, *, endpoint_host, connection_factory=None, **kwargs):
        if connection_factory is not None:
            if connection_factory is real_connection_factory:
                raise SafetyBarrierTripped(
                    "the offline harness must never be given the real "
                    "connection factory")
            target = connection_factory
            if not is_offline_connection_double(target):
                raise SafetyBarrierTripped(
                    "the offline harness accepts only a connection factory "
                    "explicitly marked with offline_connection_double()")
        super().__init__(endpoint_host=endpoint_host,
                         connection_factory=connection_factory, **kwargs)

    def send_signed_offline(self, signed, *, allow_denied_prefix_probe=False,
                            max_response_bytes=None) -> RawResponse:
        """OFFLINE TESTS ONLY. Transmits a caller-owned SignedRequest through
        the identical `_attempt` wire validation (allowlist, bucket/key
        barriers, host binding), against a marked offline double."""
        attempt = self._attempt(
            signed, allow_denied_prefix_probe=allow_denied_prefix_probe,
            max_response_bytes=max_response_bytes)
        if attempt.failure is not None:
            raise attempt.failure
        return attempt.response


#: Attribute an object must carry to be accepted by OfflineSignerHarness.
OFFLINE_DOUBLE_ATTRIBUTE = "probe_offline_connection_double"


def offline_connection_double(factory):
    """Mark a connection factory as a TEST DOUBLE.

    `real_connection_factory` is never marked, and marking it would require
    editing this module, so the offline harness cannot be handed the live
    factory by any caller.
    """
    if factory is real_connection_factory:
        raise SafetyBarrierTripped(
            "the real connection factory can never be an offline double")
    try:
        setattr(factory, OFFLINE_DOUBLE_ATTRIBUTE, True)
    except (AttributeError, TypeError):
        raise SafetyBarrierTripped(
            "this object cannot be marked as an offline double")
    return factory


def is_offline_connection_double(factory) -> bool:
    """True when `factory` (or its class) carries the offline-double mark."""
    if factory is real_connection_factory:
        return False
    if type(factory) is RefusingConnectionFactory:
        return True          # the refusing default can never network
    return getattr(factory, OFFLINE_DOUBLE_ATTRIBUTE, False) is True


def assert_single_part(ledger: Sequence[Mapping]) -> None:
    """Prove single-part execution from the emitted request ledger.

    Deliberately NOT inferred from ETag shape: a 32-hex ETag with no `-N`
    suffix is informational, and R2 makes no documented promise tying it
    to the upload path.
    """
    markers = _policy().multipart_query_markers
    for entry in ledger:
        for marker in markers:
            if marker in entry.get("query", ()):
                raise SafetyBarrierTripped(
                    f"multipart marker {marker!r} present in the ledger")
    puts = [e for e in ledger if e["method"] == "PUT"]
    if len(puts) != 1:
        raise SafetyBarrierTripped(
            f"expected exactly one PutObject, ledger has {len(puts)}")


# ─────────────────────────────────────────────────────────────────────────
# S3 error parsing — bounded, structural
# ─────────────────────────────────────────────────────────────────────────



class ParsedError(NamedTuple):
    code: str | None
    message: str | None
    message_omitted: bool
    request_id: str | None
    host_id_sha256: str | None


def _capture_blank_parsed_error():
    """The all-empty parse result, captured (Codex BLOCKER 3): rebinding a
    module name to a ParsedError carrying, say, a NoSuchKey code would let
    an unparseable body masquerade as a specific S3 error."""
    blank = ParsedError(None, None, False, None, None)
    return lambda blank=blank: blank


_blank_parsed_error = _capture_blank_parsed_error()

#: DISPLAY ONLY — enforcement reads the closure above.
_BLANK_PARSED_ERROR = _blank_parsed_error()


def safe_error_message(raw) -> tuple:
    if raw is None:
        return None, False
    if type(raw) is not str:
        return None, True
    collapsed = " ".join(raw.split())
    if not _grammar().safe_message.fullmatch(collapsed):
        return None, True
    if _grammar().opaque_token.search(collapsed):
        return None, True
    return collapsed, False


def parse_s3_error(body, *, truncated=False) -> ParsedError:
    """Parse ONLY allowlisted fields from a BOUNDED S3 error body.

    Structural rules (no regex over arbitrary nested content): bounded and
    untruncated; no DTD/entity declarations; stdlib XML parser; root must
    be exactly <Error>; exactly ONE DIRECT text-only <Code> child, so
    duplicates, nested/spoofed <Code> and element-bearing <Code> are all
    rejected. Anything rejected yields code=None, which classifiers treat
    as UNKNOWN. HostId is reduced to a digest, never recorded raw.
    """
    _exact(body, bytes, "body")
    _exact_bool(truncated, "truncated")
    if truncated or len(body) > _policy().max_error_body_bytes:
        return _blank_parsed_error()
    upper = body.upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        return _blank_parsed_error()
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return _blank_parsed_error()
    if root.tag != "Error":
        return _blank_parsed_error()

    def direct_text_child(tag: str):
        elems = [child for child in root if child.tag == tag]
        if len(elems) != 1:
            return None            # absent or duplicated → rejected
        elem = elems[0]
        if len(elem) != 0:
            return None            # element children → spoofed structure
        return elem.text

    code = direct_text_child("Code")
    if code is not None and not _grammar().error_code.fullmatch(code):
        code = None
    message, omitted = safe_error_message(direct_text_child("Message"))
    request_id = direct_text_child("RequestId")
    if request_id is not None and not _grammar().request_id.fullmatch(request_id):
        request_id = None
    host_id = direct_text_child("HostId")
    return ParsedError(
        code=code, message=message, message_omitted=omitted,
        request_id=request_id,
        host_id_sha256=(hashlib.sha256(host_id.encode("utf-8")).hexdigest()
                        if host_id else None))


# ─────────────────────────────────────────────────────────────────────────
# Absence classification
# ─────────────────────────────────────────────────────────────────────────

class RemoteState(enum.Enum):
    CONFIRMED = "CONFIRMED"
    ABSENT = "ABSENT"
    CORRUPT = "CORRUPT"
    UNKNOWN = "UNKNOWN"


def classify_remote_state(*, method, status, error_code, body_valid=None,
                          transport_failed=False, body_truncated=False
                          ) -> RemoteState:
    """ABSENT requires an authenticated direct GET returning 404 NoSuchKey.

    HEAD is deliberately insufficient: a HEAD response carries no body, so
    no <Code> can be parsed, and a bare 404 is indistinguishable from
    other causes. Truncated bodies are UNKNOWN. Everything unresolved is
    UNKNOWN, and UNKNOWN blocks.
    """
    if transport_failed or status is None or body_truncated:
        return RemoteState.UNKNOWN
    if method == "GET" and status == 404 and error_code == "NoSuchKey":
        return RemoteState.ABSENT
    if method == "GET" and 200 <= status < 300:
        if body_valid is None:
            return RemoteState.UNKNOWN
        return RemoteState.CONFIRMED if body_valid else RemoteState.CORRUPT
    return RemoteState.UNKNOWN


# ─────────────────────────────────────────────────────────────────────────
# PUT outcome state machine + status/outcome matrix (Codex BLOCKER 2)
# ─────────────────────────────────────────────────────────────────────────

class PutOutcome(enum.Enum):
    BEFORE_REQUEST_FAILURE = "BEFORE_REQUEST_FAILURE"
    REQUEST_ATTEMPTED_COMMIT_UNKNOWN = "REQUEST_ATTEMPTED_COMMIT_UNKNOWN"
    RESPONSE_LOST_COMMIT_UNKNOWN = "RESPONSE_LOST_COMMIT_UNKNOWN"
    DEFINITE_CONDITIONAL_REJECTION = "DEFINITE_CONDITIONAL_REJECTION"  # 412
    DEFINITE_THROTTLE_REJECTION = "DEFINITE_THROTTLE_REJECTION"        # 429
    DEFINITE_AUTH_REJECTION = "DEFINITE_AUTH_REJECTION"                # 401/403
    DEFINITE_CLIENT_REJECTION = "DEFINITE_CLIENT_REJECTION"            # 4xx
    SERVER_ERROR_COMMIT_UNKNOWN = "SERVER_ERROR_COMMIT_UNKNOWN"        # 5xx
    PUT_CONFIRMED = "PUT_CONFIRMED"
    PUT_SUCCEEDED_VERIFY_UNKNOWN = "PUT_SUCCEEDED_VERIFY_UNKNOWN"
    SUPERSEDED_AFTER_PUBLISH = "SUPERSEDED_AFTER_PUBLISH"


class NextAction(enum.Enum):
    CONTINUE = "CONTINUE"
    RECONCILE_WITH_AUTHORITATIVE_GET = "RECONCILE_WITH_AUTHORITATIVE_GET"
    RESTART_FROM_FRESH_PLAN = "RESTART_FROM_FRESH_PLAN"
    HUMAN_INTERVENTION = "HUMAN_INTERVENTION"


class Reconciliation(enum.Enum):
    RECONCILED_SUCCESS = "RECONCILED_SUCCESS"
    NO_MUTATION_RESTART_FROM_FRESH_PLAN = "NO_MUTATION_RESTART_FROM_FRESH_PLAN"
    SUPERSEDED_CONFLICT = "SUPERSEDED_CONFLICT"
    UNKNOWN_HUMAN_INTERVENTION = "UNKNOWN_HUMAN_INTERVENTION"


#: DISPLAY ONLY (Codex HIGH). next_action() matches the enum exhaustively
#: and never reads this set, so rebinding it changes no control flow.
AMBIGUOUS_OUTCOMES = frozenset({
    PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN,
    PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN,
    PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN,
    PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN,
})

DEFINITE_NO_MUTATION_OUTCOMES = frozenset({
    PutOutcome.BEFORE_REQUEST_FAILURE,
    PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
    PutOutcome.DEFINITE_THROTTLE_REJECTION,
    PutOutcome.DEFINITE_AUTH_REJECTION,
    PutOutcome.DEFINITE_CLIENT_REJECTION,
})

#: Outcomes permitted when NO HTTP status exists (transport-derived only).
def _capture_status_outcome_sets():
    """The status->outcome matrix sets, captured (Codex BLOCKER 3).

    `allowed_outcomes_for_status` reads this closure, so rebinding the
    display aliases below cannot widen what a status is allowed to mean.
    """
    sets = (
        # Permitted when NO HTTP status exists (transport-derived only).
        frozenset({PutOutcome.BEFORE_REQUEST_FAILURE,
                   PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN,
                   PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN}),
        # Permitted for a 2xx, depending on verification facts.
        frozenset({PutOutcome.PUT_CONFIRMED,
                   PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN,
                   PutOutcome.SUPERSEDED_AFTER_PUBLISH}),
    )
    return lambda sets=sets: sets


_status_outcome_sets = _capture_status_outcome_sets()

#: DISPLAY ONLY — enforcement reads the closure above.
_TRANSPORT_ONLY_OUTCOMES = _status_outcome_sets()[0]
_SUCCESS_OUTCOMES = _status_outcome_sets()[1]


def allowed_outcomes_for_status(status) -> frozenset:
    """THE complete status→outcome matrix (Codex BLOCKER 2).

    A pair outside this matrix is logically impossible evidence and must
    fail closed rather than contribute to any verdict.
    """
    if status is None:
        return _status_outcome_sets()[0]
    _exact_int(status, "status", minimum=100, maximum=599)
    if 200 <= status < 300:
        return _status_outcome_sets()[1]
    if status == 412:
        return frozenset({PutOutcome.DEFINITE_CONDITIONAL_REJECTION})
    if status == 429:
        return frozenset({PutOutcome.DEFINITE_THROTTLE_REJECTION})
    if status in (401, 403):
        return frozenset({PutOutcome.DEFINITE_AUTH_REJECTION})
    if 400 <= status < 500:
        return frozenset({PutOutcome.DEFINITE_CLIENT_REJECTION})
    if 500 <= status < 600:
        return frozenset({PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN})
    # 1xx and 3xx have no legitimate place in this probe: the transport
    # refuses redirects outright and never surfaces an informational
    # response. Fail closed rather than inventing a mapping.
    raise SafetyBarrierTripped(
        f"HTTP status class {status} is not a permitted probe response")


def assert_status_outcome_consistent(status, outcome) -> None:
    if type(outcome) is not PutOutcome:
        raise SafetyBarrierTripped("outcome must be exactly PutOutcome")
    allowed = allowed_outcomes_for_status(status)
    if outcome not in allowed:
        raise SafetyBarrierTripped(
            f"contradictory evidence: HTTP {status} cannot pair with "
            f"{outcome.value} (allowed: "
            f"{sorted(o.value for o in allowed)})")


def classify_put_outcome(*, transport_failure, status, verify_succeeded=None,
                         verify_shows_other_state=False) -> PutOutcome:
    if transport_failure is not None:
        if type(transport_failure) is not TransportFailure:
            raise SafetyBarrierTripped(
                "transport_failure must be exactly TransportFailure")
        if transport_failure.phase is SendPhase.BEFORE_REQUEST:
            return PutOutcome.BEFORE_REQUEST_FAILURE
        if transport_failure.phase is SendPhase.DURING_REQUEST:
            return PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN
        return PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN
    if status is None:
        return PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN
    _exact_int(status, "status", minimum=100, maximum=599)
    _exact_bool(verify_shows_other_state, "verify_shows_other_state")
    if 200 <= status < 300:
        if verify_shows_other_state:
            return PutOutcome.SUPERSEDED_AFTER_PUBLISH
        if verify_succeeded is True:
            return PutOutcome.PUT_CONFIRMED
        return PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN
    if status == 412:
        return PutOutcome.DEFINITE_CONDITIONAL_REJECTION
    if status == 429:
        return PutOutcome.DEFINITE_THROTTLE_REJECTION
    if status in (401, 403):
        return PutOutcome.DEFINITE_AUTH_REJECTION
    if 400 <= status < 500:
        return PutOutcome.DEFINITE_CLIENT_REJECTION
    if 500 <= status < 600:
        return PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN
    # 1xx / 3xx: same fail-closed rule as the matrix above.
    raise SafetyBarrierTripped(
        f"HTTP status class {status} is not a permitted probe response")


def next_action(outcome: PutOutcome) -> NextAction:
    """There is NO branch that replays the PUT. By construction.

    Every ambiguous outcome routes to reconciliation — never straight to
    a fresh-plan restart: only a reconciliation GET may authorize one.

    This is an EXHAUSTIVE explicit match on the enum (Codex HIGH). It reads
    no module-level set, so rebinding `AMBIGUOUS_OUTCOMES` (or any other
    exported collection) cannot change safety control flow, and a newly
    added PutOutcome member fails closed instead of silently CONTINUEing.
    """
    if type(outcome) is not PutOutcome:
        raise SafetyBarrierTripped("outcome must be exactly PutOutcome")
    # Ambiguous — commit state unknown, so an authoritative GET decides.
    if outcome is PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN:
        return NextAction.RECONCILE_WITH_AUTHORITATIVE_GET
    if outcome is PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN:
        return NextAction.RECONCILE_WITH_AUTHORITATIVE_GET
    if outcome is PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN:
        return NextAction.RECONCILE_WITH_AUTHORITATIVE_GET
    if outcome is PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN:
        return NextAction.RECONCILE_WITH_AUTHORITATIVE_GET
    # Definitely no mutation, and nothing in flight.
    if outcome is PutOutcome.BEFORE_REQUEST_FAILURE:
        return NextAction.RESTART_FROM_FRESH_PLAN
    if outcome is PutOutcome.DEFINITE_CONDITIONAL_REJECTION:
        return NextAction.CONTINUE
    if outcome is PutOutcome.DEFINITE_THROTTLE_REJECTION:
        return NextAction.CONTINUE
    if outcome is PutOutcome.DEFINITE_AUTH_REJECTION:
        return NextAction.CONTINUE
    if outcome is PutOutcome.DEFINITE_CLIENT_REJECTION:
        return NextAction.CONTINUE
    # Definitely committed.
    if outcome is PutOutcome.PUT_CONFIRMED:
        return NextAction.CONTINUE
    if outcome is PutOutcome.SUPERSEDED_AFTER_PUBLISH:
        return NextAction.HUMAN_INTERVENTION
    raise SafetyBarrierTripped(
        f"no next action is defined for {outcome!r} — refusing")


def reconcile_after_ambiguous_put(*, get_state, observed_sha256,
                                  observed_length, intended_sha256,
                                  intended_length, prior_sha256,
                                  prior_length) -> Reconciliation:
    if type(get_state) is not RemoteState:
        raise SafetyBarrierTripped("get_state must be exactly RemoteState")
    if get_state is not RemoteState.CONFIRMED:
        if get_state is RemoteState.ABSENT and prior_sha256 is None:
            return Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN
        return Reconciliation.UNKNOWN_HUMAN_INTERVENTION
    if observed_sha256 is None or observed_length is None:
        return Reconciliation.UNKNOWN_HUMAN_INTERVENTION
    if observed_sha256 == intended_sha256 \
            and observed_length == intended_length:
        return Reconciliation.RECONCILED_SUCCESS
    if prior_sha256 is not None and observed_sha256 == prior_sha256 \
            and observed_length == prior_length:
        return Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN
    return Reconciliation.SUPERSEDED_CONFLICT


# ─────────────────────────────────────────────────────────────────────────
# Semantic CAS aggregation (Codex BLOCKER 2 + 3)
# ─────────────────────────────────────────────────────────────────────────

class RepetitionStatus(enum.Enum):
    """DERIVED repetition classification. Never caller-supplied."""

    VALID = "VALID"
    INVALID_THROTTLED = "INVALID_THROTTLED"
    INVALID_CREDENTIAL_EXPIRED = "INVALID_CREDENTIAL_EXPIRED"
    INVALID_AMBIGUOUS = "INVALID_AMBIGUOUS"


class Verdict(enum.Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    ABANDON = "ABANDON"


#: DISPLAY aliases, derived from the B matrix row (all semantic tests
#: share these values). The aggregator derives thresholds per test from
#: test_spec(); rebinding these names is inert.
SEMANTIC_REQUIRED_VALID = test_spec("B").required_repetitions
SEMANTIC_MAX_ATTEMPTS = test_spec("B").max_attempts


class SemanticEvidence(NamedTuple):
    """Structured evidence for ONE semantic repetition.

    A NamedTuple, so `object.__setattr__` cannot mutate it after creation
    — and the aggregator revalidates the COMPLETE object on record()
    anyway, so constructor-time validation is never the only check.
    """

    identity: RepetitionIdentity
    http_status: int | None
    outcome: PutOutcome
    mutation_observed: bool | None
    credential_expired: bool = False


def validate_semantic_evidence(evidence) -> SemanticEvidence:
    """Complete revalidation. Called by the aggregator on every record()."""
    if type(evidence) is not SemanticEvidence:
        raise SafetyBarrierTripped(
            "evidence must be exactly SemanticEvidence")
    identity = validate_repetition_identity(evidence.identity)
    if identity.test_id not in semantic_test_ids():
        raise SafetyBarrierTripped(
            f"{identity.test_id!r} is not a semantic test id")
    _exact_opt_int(evidence.http_status, "http_status",
                   minimum=100, maximum=599)
    assert_status_outcome_consistent(evidence.http_status, evidence.outcome)
    if evidence.mutation_observed is not None:
        _exact_bool(evidence.mutation_observed, "mutation_observed")
    _exact_bool(evidence.credential_expired, "credential_expired")
    # HIGH 1: credential_expired is coherent ONLY with an authentication
    # failure. Pairing it with 412 / 429 / 2xx / 5xx / transport-success
    # is impossible evidence and is refused, so ten expired 412s can never
    # be laundered into VALID repetitions.
    if evidence.credential_expired:
        if evidence.http_status not in (401, 403) \
                or evidence.outcome is not PutOutcome.DEFINITE_AUTH_REJECTION:
            raise SafetyBarrierTripped(
                "credential_expired=True is only consistent with a 401/403 "
                "DEFINITE_AUTH_REJECTION; it cannot accompany "
                f"http_status={evidence.http_status}, outcome="
                f"{evidence.outcome.value}")
    return evidence


def derive_semantic_status(evidence) -> tuple:
    """Derive (status, abandon_reason) from structured evidence.

    Rules:
      - Mutation is ALWAYS dominant: any observed mutation where the
        precondition should have blocked one → ABANDON, under every status
        and every label. 412+mutation is impossible evidence and abandons.
      - A 2xx acceptance of a blocked precondition → ABANDON: it can never
        be hidden as an "invalid" repetition.
      - VALID requires 412 AND a proven-unchanged final state.
      - 429 → INVALID_THROTTLED (documented throttle; never CAS evidence).
      - 401/403 with expiry evidence → INVALID_CREDENTIAL_EXPIRED.
      - Everything else → INVALID_AMBIGUOUS. Never PASS-contributing.
    """
    evidence = validate_semantic_evidence(evidence)
    ident = evidence.identity
    if evidence.mutation_observed is True:
        return None, (
            f"{ident.test_id} rep {ident.repetition}: the object was MUTATED "
            "despite a precondition that must block mutation "
            f"(http_status={evidence.http_status}) — CAS is not enforced")
    status = evidence.http_status
    if status is None:
        return RepetitionStatus.INVALID_AMBIGUOUS, None
    if 200 <= status < 300:
        return None, (
            f"{ident.test_id} rep {ident.repetition}: a blocked precondition "
            f"was ACCEPTED with HTTP {status} — a 2xx can never be "
            "classified away as an invalid repetition")
    if status == 412:
        if evidence.mutation_observed is False:
            return RepetitionStatus.VALID, None
        return RepetitionStatus.INVALID_AMBIGUOUS, None
    if status == 429:
        return RepetitionStatus.INVALID_THROTTLED, None
    if status in (401, 403) and evidence.credential_expired:
        return RepetitionStatus.INVALID_CREDENTIAL_EXPIRED, None
    return RepetitionStatus.INVALID_AMBIGUOUS, None


class SemanticAggregator:
    """Fixed-purpose acceptance object (Codex BLOCKER 3).

    Thresholds are internal constants — there is no constructor argument
    to lower them. `overall()` always evaluates exactly the semantic tests
    from the immutable matrix; it takes no test-id list. Evidence identity
    (test_id, repetition) and key are both deduplicated, so replaying one
    observation ten times cannot manufacture ten valid repetitions.
    """

    def __init__(self):
        self._records = {}
        self._seen_identities = set()
        self._seen_keys = {}

    def required_valid(self, test_id) -> int:
        """Per-test, from the matrix row (MEDIUM 2)."""
        return test_spec(test_id).required_repetitions

    def max_attempts(self, test_id) -> int:
        return test_spec(test_id).max_attempts

    def record(self, evidence):
        evidence = validate_semantic_evidence(evidence)
        ident = evidence.identity
        pair = (ident.test_id, ident.repetition)
        if pair in self._seen_identities:
            raise SafetyBarrierTripped(
                f"duplicate evidence for {ident.test_id} rep "
                f"{ident.repetition} — each repetition may be recorded once")
        owner = self._seen_keys.get(ident.key)
        if owner is not None and owner != pair:
            raise SafetyBarrierTripped(
                f"key {ident.key!r} is already bound to {owner} — two "
                "repetitions may not share a key")
        self._seen_identities.add(pair)
        self._seen_keys[ident.key] = pair
        derived, abandon_reason = derive_semantic_status(evidence)
        self._records.setdefault(ident.test_id, []).append(
            (evidence, derived, abandon_reason))
        return derived

    def attempts(self, test_id) -> int:
        return len(self._records.get(test_id, ()))

    def valid(self, test_id) -> list:
        return [ev for ev, derived, _ in self._records.get(test_id, ())
                if derived is RepetitionStatus.VALID]

    def verdict(self, test_id) -> tuple:
        _exact_str(test_id, "test_id", max_len=16)
        # Thresholds are DERIVED per test from the matrix row (MEDIUM 2),
        # not from a single shared constant.
        spec = test_spec(test_id)
        if spec.category != "semantic":
            raise SafetyBarrierTripped(
                f"{test_id!r} is not a semantic test")
        required = spec.required_repetitions
        max_attempts = spec.max_attempts
        records = self._records.get(test_id, [])
        for _, _, abandon_reason in records:
            if abandon_reason is not None:
                return Verdict.ABANDON, abandon_reason
        if not records:
            return Verdict.FAIL, f"{test_id}: no repetitions recorded"
        if len(records) > max_attempts:
            return Verdict.FAIL, (
                f"{test_id}: {len(records)} attempts exceeds the "
                f"{max_attempts} cap")
        valid_count = len(self.valid(test_id))
        if valid_count < required:
            return Verdict.FAIL, (
                f"{test_id}: only {valid_count} valid repetitions of "
                f"{required} required (invalid: "
                f"{len(records) - valid_count}) — INCONCLUSIVE, never PASS")
        return Verdict.PASS, (
            f"{test_id}: {valid_count}/{valid_count} valid repetitions "
            "returned 412 with a proven-unchanged final state")

    def overall(self) -> tuple:
        """Always exactly the semantic tests. No caller-supplied subset."""
        reasons = []
        worst = Verdict.PASS
        for test_id in semantic_test_ids():
            verdict, reason = self.verdict(test_id)
            reasons.append(reason)
            if verdict is Verdict.ABANDON:
                worst = Verdict.ABANDON
            elif verdict is Verdict.FAIL and worst is not Verdict.ABANDON:
                worst = Verdict.FAIL
        return worst, reasons


# ─────────────────────────────────────────────────────────────────────────
# Race model (Codex HIGH 1 of round 1, HIGH 2 of round 2)
# ─────────────────────────────────────────────────────────────────────────

class RaceAttribution(enum.Enum):
    CAS = "CAS"
    THROTTLE = "THROTTLE"


def attribute_loser(status):
    """412 is CAS evidence. 429 is a documented throttle and is NEVER CAS
    evidence. Anything else is unattributable."""
    if status == 412:
        return RaceAttribution.CAS
    if status == 429:
        return RaceAttribution.THROTTLE
    return None




class RaceBarrierEvidence(NamedTuple):
    """Coordinator-issued proof that both writers were released together
    (HIGH 2). The generation id ties a repetition's writers to ONE barrier
    release; the release timestamp bounds when the sends may have started.
    """

    generation_id: str
    release_mono_ns: int




class RaceWriter(NamedTuple):
    writer_id: str
    http_status: int | None
    payload_sha256: str
    payload_length: int
    returned_etag: str | None
    if_match: str | None          # the exact conditional this writer sent
    if_none_match: str | None
    barrier_generation: str       # which barrier release this writer used
    barrier_join_mono_ns: int     # when it joined (must precede release)
    send_mono_ns: int             # monotonic send time (must follow release)


class RaceRepetition(NamedTuple):
    """One race repetition's MANDATORY evidence (HIGH 1 + HIGH 2).

    `identity` comes from ProbeKeyAllocator.allocate_race, which derives
    the setup state from the race type, so E2/F cannot be mismatched and
    the key cannot be a free-form stale string.

    Structured, test-specific setup evidence:
      - E2: `shared_original_etag` is the seeded object's ETag; both
        writers must send exactly that as `if_match` (and no
        if_none_match). `absence_confirmed` is unused (None).
      - F: `absence_confirmed` must be True (GET-404-NoSuchKey proof);
        both writers must send `if_none_match == "*"` (and no if_match).

    `barrier` is coordinator-issued RaceBarrierEvidence. Both writers must
    reference its generation, have joined before release, sent after
    release, and sent within `max_race_send_skew_ns` of each other —
    proving a shared-barrier release, not perfect CPU simultaneity.
    """

    identity: RaceIdentity
    shared_original_etag: str | None
    absence_confirmed: bool | None
    barrier: RaceBarrierEvidence
    writers: tuple
    final_state: RemoteState
    final_sha256: str | None
    final_length: int | None
    final_etag: str | None


class RaceRepetitionStatus(enum.Enum):
    VALID_CAS = "VALID_CAS"                 # one winner, 412 loser, final==winner
    INVALID_THROTTLED = "INVALID_THROTTLED"  # one winner, 429 loser
    INCONCLUSIVE = "INCONCLUSIVE"           # missing/weak evidence, zero winners
    ABANDON = "ABANDON"                     # safety property violated


def validate_race_writer(writer) -> RaceWriter:
    if type(writer) is not RaceWriter:
        raise SafetyBarrierTripped("writers must be exactly RaceWriter")
    if type(writer.writer_id) is not str \
            or not _grammar().writer_id.fullmatch(writer.writer_id):
        raise SafetyBarrierTripped("writer_id refused")
    _exact_opt_int(writer.http_status, "http_status", minimum=100, maximum=599)
    if type(writer.payload_sha256) is not str \
            or not _grammar().sha256.fullmatch(writer.payload_sha256):
        raise SafetyBarrierTripped("payload_sha256 must be 64 lowercase hex")
    _exact_int(writer.payload_length, "payload_length", minimum=0)
    if writer.returned_etag is not None:
        _exact_str(writer.returned_etag, "returned_etag", max_len=256)
        _no_ctl(writer.returned_etag, "returned_etag")
    if writer.if_match is not None:
        _exact_str(writer.if_match, "if_match", max_len=256)
        _no_ctl(writer.if_match, "if_match")
    if writer.if_none_match is not None:
        _exact_str(writer.if_none_match, "if_none_match", max_len=8)
    if type(writer.barrier_generation) is not str \
            or not _grammar().barrier_gen.fullmatch(writer.barrier_generation):
        raise SafetyBarrierTripped("barrier_generation refused")
    _exact_int(writer.barrier_join_mono_ns, "barrier_join_mono_ns", minimum=0)
    _exact_int(writer.send_mono_ns, "send_mono_ns", minimum=0)
    return writer


def validate_race_repetition(repetition) -> RaceRepetition:
    if type(repetition) is not RaceRepetition:
        raise SafetyBarrierTripped(
            "repetition must be exactly RaceRepetition")
    identity = validate_race_identity(repetition.identity)
    if type(repetition.writers) is not tuple or len(repetition.writers) != 2:
        raise SafetyBarrierTripped(
            "a race repetition requires EXACTLY TWO writers")
    w1, w2 = (validate_race_writer(w) for w in repetition.writers)
    if w1.writer_id == w2.writer_id:
        raise SafetyBarrierTripped("writer ids must be unique")
    if w1.payload_sha256 == w2.payload_sha256:
        raise SafetyBarrierTripped(
            "writers must carry DISTINCT payloads — identical payloads "
            "cannot attribute the final object to one winner")

    # ── HIGH 2: structured barrier / intentional-simultaneity evidence ──
    barrier = repetition.barrier
    if type(barrier) is not RaceBarrierEvidence:
        raise SafetyBarrierTripped(
            "race repetition requires RaceBarrierEvidence")
    if type(barrier.generation_id) is not str \
            or not _grammar().barrier_gen.fullmatch(barrier.generation_id):
        raise SafetyBarrierTripped("barrier generation_id refused")
    _exact_int(barrier.release_mono_ns, "release_mono_ns", minimum=0)
    max_skew = _policy().max_race_send_skew_ns
    for w in (w1, w2):
        if w.barrier_generation != barrier.generation_id:
            raise SafetyBarrierTripped(
                "both writers must share the barrier generation")
        if w.barrier_join_mono_ns > barrier.release_mono_ns:
            raise SafetyBarrierTripped(
                "a writer joined the barrier AFTER release")
        if w.send_mono_ns < barrier.release_mono_ns:
            raise SafetyBarrierTripped(
                "a writer sent BEFORE the barrier release")
    if abs(w1.send_mono_ns - w2.send_mono_ns) > max_skew:
        raise SafetyBarrierTripped(
            f"race send skew {abs(w1.send_mono_ns - w2.send_mono_ns)}ns "
            f"exceeds the {max_skew}ns bound — not an intentional race")

    # Test-specific precondition evidence.
    if identity.test_id == "E2":
        etag = repetition.shared_original_etag
        if type(etag) is not str or not _grammar().etag.fullmatch(etag) or etag == "*":
            raise SafetyBarrierTripped(
                "E2 requires a concrete shared original ETag")
        if repetition.absence_confirmed is not None:
            raise SafetyBarrierTripped(
                "E2 must not carry absence_confirmed")
        for w in (w1, w2):
            if w.if_match != etag or w.if_none_match is not None:
                raise SafetyBarrierTripped(
                    "each E2 writer must send If-Match == the shared original "
                    "ETag and no If-None-Match")
    elif identity.test_id == "F":
        if repetition.absence_confirmed is not True:
            raise SafetyBarrierTripped(
                "F requires proven-absent setup (absence_confirmed=True)")
        if repetition.shared_original_etag is not None:
            raise SafetyBarrierTripped(
                "F must not carry a shared original ETag")
        for w in (w1, w2):
            if w.if_none_match != "*" or w.if_match is not None:
                raise SafetyBarrierTripped(
                    "each F writer must send If-None-Match: * and no If-Match")
    else:  # pragma: no cover - validate_race_identity already gates this
        raise SafetyBarrierTripped("only E2 and F are race tests")

    if type(repetition.final_state) is not RemoteState:
        raise SafetyBarrierTripped("final_state must be exactly RemoteState")
    if repetition.final_sha256 is not None and (
            type(repetition.final_sha256) is not str
            or not _grammar().sha256.fullmatch(repetition.final_sha256)):
        raise SafetyBarrierTripped("final_sha256 must be 64 hex or None")
    _exact_opt_int(repetition.final_length, "final_length", minimum=0)
    if repetition.final_etag is not None:
        _exact_str(repetition.final_etag, "final_etag", max_len=256)
        _no_ctl(repetition.final_etag, "final_etag")
    return repetition


def classify_race_repetition(repetition) -> tuple:
    """Return (RaceRepetitionStatus, reason, attributions).

    A 412 loser yields VALID_CAS (create/If-Match rejection is CAS
    evidence). A 429 loser yields INVALID_THROTTLED — the safety property
    held, but same-key rate limiting may be responsible, so it is NEVER a
    valid CAS repetition. Two winners, or a final matching the loser or
    neither writer, is ABANDON.
    """
    repetition = validate_race_repetition(repetition)
    writers = repetition.writers
    winners = [w for w in writers
               if w.http_status is not None and 200 <= w.http_status < 300]
    losers = [w for w in writers if w not in winners]
    attributions = [attribute_loser(w.http_status) for w in losers]

    if len(winners) == 2:
        return (RaceRepetitionStatus.ABANDON,
                "both writers mutated the same key — the safety property is "
                "violated", attributions)
    if not winners:
        return (RaceRepetitionStatus.INCONCLUSIVE,
                "no writer succeeded; repetition is inconclusive",
                attributions)
    winner, loser = winners[0], losers[0]
    if loser.http_status not in (412, 429):
        return (RaceRepetitionStatus.INCONCLUSIVE,
                f"loser status {loser.http_status} is neither 412 nor 429",
                attributions)
    if not winner.returned_etag:
        return (RaceRepetitionStatus.INCONCLUSIVE, "winner returned no ETag",
                attributions)
    if repetition.final_state is not RemoteState.CONFIRMED \
            or repetition.final_sha256 is None \
            or repetition.final_length is None:
        return (RaceRepetitionStatus.INCONCLUSIVE,
                "final state was not authoritatively read", attributions)
    if repetition.final_sha256 == loser.payload_sha256:
        return (RaceRepetitionStatus.ABANDON,
                "final object matches the LOSER's payload — the loser mutated "
                "despite its rejection", attributions)
    if repetition.final_sha256 != winner.payload_sha256:
        return (RaceRepetitionStatus.ABANDON,
                "final object matches neither writer's payload exactly",
                attributions)
    if repetition.final_length != winner.payload_length:
        return (RaceRepetitionStatus.INCONCLUSIVE,
                "final hash matches the winner but the length differs",
                attributions)
    if repetition.final_etag is None \
            or repetition.final_etag != winner.returned_etag:
        return (RaceRepetitionStatus.INCONCLUSIVE,
                "final authoritative ETag does not equal the winner's ETag",
                attributions)
    # Exactly one winner, final matches it. The LOSER's status decides
    # whether this is CAS evidence or merely a throttle.
    if loser.http_status == 429:
        return (RaceRepetitionStatus.INVALID_THROTTLED,
                f"one winner ({winner.writer_id}) but the loser was throttled "
                "(429) — safety held, CAS not proven", attributions)
    return (RaceRepetitionStatus.VALID_CAS,
            f"exactly one winner ({winner.writer_id}); loser 412; final "
            "bytes, length and ETag all match the winner", attributions)


def race_verdict(repetition) -> tuple:
    """Back-compatible single-repetition verdict wrapper: maps the
    repetition status onto (Verdict, reason, attributions)."""
    status, reason, attributions = classify_race_repetition(repetition)
    if status is RaceRepetitionStatus.ABANDON:
        return Verdict.ABANDON, reason, attributions
    if status is RaceRepetitionStatus.VALID_CAS:
        return Verdict.PASS, reason, attributions
    return Verdict.FAIL, reason, attributions


class RaceAggregator:
    """Fixed-purpose race acceptance object (HIGH 1), mirroring the
    semantic one. Thresholds are derived per test (E2/F) from the matrix;
    there is no constructor argument and `overall()` takes no test list.
    Identity (test_id, repetition) and key are deduplicated.
    """

    def __init__(self):
        self._records = {}
        self._seen_identities = set()
        self._seen_keys = {}

    def record(self, repetition):
        repetition = validate_race_repetition(repetition)
        ident = repetition.identity
        pair = (ident.test_id, ident.repetition)
        if pair in self._seen_identities:
            raise SafetyBarrierTripped(
                f"duplicate race evidence for {ident.test_id} rep "
                f"{ident.repetition}")
        owner = self._seen_keys.get(ident.key)
        if owner is not None and owner != pair:
            raise SafetyBarrierTripped(
                f"race key {ident.key!r} already bound to {owner}")
        self._seen_identities.add(pair)
        self._seen_keys[ident.key] = pair
        status, reason, attributions = classify_race_repetition(repetition)
        self._records.setdefault(ident.test_id, []).append(
            (status, reason, attributions))
        return status

    def valid(self, test_id) -> int:
        return sum(1 for status, _, _ in self._records.get(test_id, ())
                   if status is RaceRepetitionStatus.VALID_CAS)

    def verdict(self, test_id) -> tuple:
        _exact_str(test_id, "test_id", max_len=16)
        spec = test_spec(test_id)
        if spec.category != "race":
            raise SafetyBarrierTripped(f"{test_id!r} is not a race test")
        records = self._records.get(test_id, [])
        for status, reason, _ in records:
            if status is RaceRepetitionStatus.ABANDON:
                return Verdict.ABANDON, f"{test_id}: {reason}"
        if not records:
            return Verdict.FAIL, f"{test_id}: no race repetitions recorded"
        if len(records) > spec.max_attempts:
            return Verdict.FAIL, (
                f"{test_id}: {len(records)} attempts exceeds the "
                f"{spec.max_attempts} cap")
        valid_count = self.valid(test_id)
        if valid_count < spec.required_repetitions:
            return Verdict.FAIL, (
                f"{test_id}: only {valid_count} VALID_CAS repetitions of "
                f"{spec.required_repetitions} required "
                f"(invalid/throttled: {len(records) - valid_count}) — "
                "INCONCLUSIVE, never PASS")
        return Verdict.PASS, (
            f"{test_id}: {valid_count}/{valid_count} VALID_CAS race "
            "repetitions with exactly one winner and a 412 loser")

    def overall(self) -> tuple:
        reasons = []
        worst = Verdict.PASS
        for test_id in race_test_ids():
            verdict, reason = self.verdict(test_id)
            reasons.append(reason)
            if verdict is Verdict.ABANDON:
                worst = Verdict.ABANDON
            elif verdict is Verdict.FAIL and worst is not Verdict.ABANDON:
                worst = Verdict.FAIL
        return worst, reasons


# ─────────────────────────────────────────────────────────────────────────
# Archive model
# ─────────────────────────────────────────────────────────────────────────

class ArchiveOutcome(enum.Enum):
    CREATED = "CREATED"
    IDEMPOTENT_EXISTING_ARCHIVE = "IDEMPOTENT_EXISTING_ARCHIVE"
    VERSION_COLLISION = "VERSION_COLLISION"
    UNKNOWN_BLOCKED = "UNKNOWN_BLOCKED"


class ArchiveExpectation(NamedTuple):
    version: int
    semantic_sha256: str
    raw_sha256: str
    length: int


def new_archive_expectation(*, version, semantic_sha256, raw_sha256,
                            length) -> ArchiveExpectation:
    _exact_int(version, "version", minimum=1)
    for name, value in (("semantic_sha256", semantic_sha256),
                        ("raw_sha256", raw_sha256)):
        if type(value) is not str or not _grammar().sha256.fullmatch(value):
            raise SafetyBarrierTripped(f"{name} must be 64 lowercase hex")
    _exact_int(length, "length", minimum=1)
    return ArchiveExpectation(version, semantic_sha256, raw_sha256, length)


def classify_archive(*, create_status, get_state=RemoteState.UNKNOWN,
                     observed_version=None, observed_semantic_sha256=None,
                     observed_raw_sha256=None, observed_length=None,
                     expected) -> ArchiveOutcome:
    """Models catalog/archive/v<N>.json — one key per generation, created
    with If-None-Match: *. On 412 the existing object must read back and
    match EXACTLY (version, semantic hash, raw hash, length) to be
    idempotent; any mismatch is a version collision and BLOCKS."""
    if type(expected) is not ArchiveExpectation:
        raise SafetyBarrierTripped(
            "expected must be exactly ArchiveExpectation")
    if create_status is not None and type(create_status) is int \
            and 200 <= create_status < 300:
        return ArchiveOutcome.CREATED
    if create_status != 412:
        return ArchiveOutcome.UNKNOWN_BLOCKED
    if get_state is not RemoteState.CONFIRMED:
        return ArchiveOutcome.UNKNOWN_BLOCKED
    matches = (observed_version == expected.version
               and observed_semantic_sha256 == expected.semantic_sha256
               and observed_raw_sha256 == expected.raw_sha256
               and observed_length == expected.length)
    return (ArchiveOutcome.IDEMPOTENT_EXISTING_ARCHIVE if matches
            else ArchiveOutcome.VERSION_COLLISION)


def archive_allows_pointer_mutation(outcome: ArchiveOutcome) -> bool:
    """Archive failure prevents pointer mutation."""
    return outcome in (ArchiveOutcome.CREATED,
                       ArchiveOutcome.IDEMPOTENT_EXISTING_ARCHIVE)


# ─────────────────────────────────────────────────────────────────────────
# Audit model
# ─────────────────────────────────────────────────────────────────────────

class AuditOutcome(enum.Enum):
    CREATED = "CREATED"
    IDEMPOTENT_EXISTING_AUDIT = "IDEMPOTENT_EXISTING_AUDIT"
    COLLISION = "COLLISION"
    UNKNOWN = "UNKNOWN"


class PublicationClassification(enum.Enum):
    PUBLICATION_SUCCEEDED = "PUBLICATION_SUCCEEDED"
    PUBLICATION_SUCCEEDED_AUDIT_FAILED = "PUBLICATION_SUCCEEDED_AUDIT_FAILED"
    PUBLICATION_NOT_COMMITTED = "PUBLICATION_NOT_COMMITTED"


def classify_audit(*, create_status, get_state=RemoteState.UNKNOWN,
                   observed_sha256=None, expected_sha256=None) -> AuditOutcome:
    if create_status is not None and type(create_status) is int \
            and 200 <= create_status < 300:
        return AuditOutcome.CREATED
    if create_status != 412:
        return AuditOutcome.UNKNOWN
    if get_state is not RemoteState.CONFIRMED or observed_sha256 is None:
        return AuditOutcome.UNKNOWN
    return (AuditOutcome.IDEMPOTENT_EXISTING_AUDIT
            if observed_sha256 == expected_sha256 else AuditOutcome.COLLISION)


def classify_publication(*, pointer_committed_and_verified, audit_outcome
                         ) -> PublicationClassification:
    """A failed audit NEVER rolls the pointer back and NEVER triggers a
    blind republish."""
    _exact_bool(pointer_committed_and_verified,
                "pointer_committed_and_verified")
    if type(audit_outcome) is not AuditOutcome:
        raise SafetyBarrierTripped("audit_outcome must be exactly AuditOutcome")
    if not pointer_committed_and_verified:
        return PublicationClassification.PUBLICATION_NOT_COMMITTED
    if audit_outcome in (AuditOutcome.CREATED,
                         AuditOutcome.IDEMPOTENT_EXISTING_AUDIT):
        return PublicationClassification.PUBLICATION_SUCCEEDED
    return PublicationClassification.PUBLICATION_SUCCEEDED_AUDIT_FAILED


def audit_failure_permits_pointer_rollback() -> bool:
    """Always False. Present so the prohibition is testable."""
    return False


def audit_failure_permits_pointer_replay() -> bool:
    """Always False."""
    return False


# ─────────────────────────────────────────────────────────────────────────
# PER-TEST RESULT DERIVATION (Codex BLOCKER 1 + BLOCKER 2)
#
# There is NO global cross-category success list. Each support matrix row
# has its own explicit derivation from the persisted REQUEST_RECORD and
# RESPONSE_RECORD of that exact repetition. The caller supplies neither the
# outcome classification nor the validity nor the production-size flag: it
# supplies only the evidence reference, and everything else is computed
# here. Reconstruction recomputes the same function from the same physical
# bytes and requires equality, so a stored classification cannot lie.
#
# A fixed-purpose probe deserves an explicit table, not a clever
# abstraction. Anything the facts do not support derives INCONCLUSIVE.
# ─────────────────────────────────────────────────────────────────────────

class TestResultDerivation(NamedTuple):
    outcome: str
    valid: bool
    production_size: bool


class _DerivationConstants(NamedTuple):
    """Everything the derivation table reads besides captured policy."""

    inconclusive: TestResultDerivation
    denial_statuses: frozenset


def _capture_derivation_constants():
    """Capture the derivation constants ONCE (Codex HIGH sweep).

    `INCONCLUSIVE` in particular is load-bearing: if enforcement read a
    rebindable module name for it, rebinding that name to a valid-looking
    TestResultDerivation would turn EVERY failed derivation into a success.
    """
    constants = _DerivationConstants(
        inconclusive=TestResultDerivation("INCONCLUSIVE", False, False),
        denial_statuses=frozenset({401, 403}),
    )
    return lambda constants=constants: constants


_derivation_constants = _capture_derivation_constants()


def _inconclusive() -> TestResultDerivation:
    return _derivation_constants().inconclusive


#: DISPLAY ONLY — enforcement reads the closure above.
INCONCLUSIVE = _derivation_constants().inconclusive


def _is_2xx(status) -> bool:
    return type(status) is int and 200 <= status < 300


def _denied(status) -> bool:
    return (type(status) is int
            and status in _derivation_constants().denial_statuses)


def _signed_header_names(request) -> frozenset:
    names = request.get("signed_headers")
    if type(names) not in (list, tuple):
        return frozenset()
    return frozenset(n.lower() for n in names if type(n) is str)


def _query_pairs(request) -> frozenset:
    pairs = request.get("query_params")
    if type(pairs) not in (list, tuple):
        return frozenset()
    out = set()
    for pair in pairs:
        if type(pair) in (list, tuple) and len(pair) == 2 \
                and type(pair[0]) is str and type(pair[1]) is str:
            out.add((pair[0], pair[1]))
    return frozenset(out)


def _child_credential_bound(spec, request) -> bool:
    """Prove the request really used THIS group's validated child
    credential (Codex BLOCKER 2-A).

    Every fact here is derived from the wire by `build_request_record`: the
    token was physically transmitted, it was inside SignedHeaders, its
    fingerprint and the signing access key's fingerprint were recorded, and
    the credential's group/scope/actions/prefixes match the captured probe
    contract for this row's group. No token, or a credential minted for
    another group or a wider scope, fails.
    """
    policy = _policy()
    if request.get("session_token_present") is not True:
        return False
    if request.get("session_token_signed") is not True:
        return False
    if _grammar().security_token_header not in _signed_header_names(request):
        return False
    if type(request.get("session_token_sha256")) is not str:
        return False
    if type(request.get("access_key_id_sha256")) is not str:
        return False
    if request.get("credential_group") != spec.group:
        return False
    if request.get("credential_scope") != policy.credential_scope:
        return False
    actions = request.get("credential_actions")
    prefixes = request.get("credential_prefixes")
    if type(actions) not in (list, tuple) or type(prefixes) not in (list,
                                                                    tuple):
        return False
    if tuple(actions) != tuple(policy.credential_actions):
        return False
    if tuple(prefixes) != tuple(policy.credential_prefixes):
        return False
    return True


def _credential_window(request) -> tuple:
    issued = request.get("credential_issued_at")
    expires = request.get("credential_expires_at")
    at = request.get("request_time_epoch")
    if type(issued) is not int or type(expires) is not int \
            or type(at) is not int:
        return None
    return issued, expires, at


def _readback_matches(request, response) -> bool:
    """The final authenticated read returned EXACTLY what we sent."""
    sha = request.get("request_body_sha256")
    length = request.get("request_body_len")
    if sha is None or length is None:
        return False
    return (response.get("final_get_sha256") == sha
            and response.get("final_get_len") == length)


def _remote_state_of(response) -> RemoteState:
    value = response.get("remote_state")
    for state in RemoteState:
        if state.value == value:
            return state
    return RemoteState.UNKNOWN


def _derive_a(spec, request, response, siblings, sibling_responses=()):
    """A: correct ETag + If-Match must actually mutate and verify."""
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if type(request.get("if_match_raw")) is not str:
        return _inconclusive()
    if request.get("if_none_match_raw") is not None:
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    if not _readback_matches(request, response):
        return _inconclusive()
    return TestResultDerivation("CORRECT_ETAG_ACCEPTED", True, False)


def _derive_c(spec, request, response, siblings, sibling_responses=()):
    """C: If-None-Match:* create on an absent key must actually create."""
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if request.get("if_none_match_raw") != "*":
        return _inconclusive()
    if request.get("if_match_raw") is not None:
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    if not _readback_matches(request, response):
        return _inconclusive()
    return TestResultDerivation("CREATE_IF_ABSENT_OK", True, False)


def _derive_g(spec, request, response, siblings, sibling_responses=()):
    """G: the quoted ETag returned by the PUT must round trip byte-exactly
    through an authenticated read-back."""
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    etag = response.get("etag_raw")
    if type(etag) is not str or etag == "*" \
            or not _grammar().etag.fullmatch(etag):
        return _inconclusive()
    if response.get("final_etag") != etag:
        return _inconclusive()
    if not _readback_matches(request, response):
        return _inconclusive()
    return TestResultDerivation("ETAG_ROUNDTRIP_OK", True, False)


def _allowed_scope(method):
    """H1/H2/H3: an ALLOWED operation, under the intended child credential,
    on this repetition's own key, must actually succeed."""
    def derive(spec, request, response, siblings, sibling_responses=()):
        if request.get("http_method") != method:
            return _inconclusive()
        if not _key_matches_target(request.get("key"), "allocated"):
            return _inconclusive()
        if not _child_credential_bound(spec, request):
            return _inconclusive()
        if not _is_2xx(response.get("status")):
            return _inconclusive()
        return TestResultDerivation("SCOPE_ALLOWED_OK", True, False)
    return derive


def _denied_scope(method, *, target, require_list_query=False):
    """H4/H5/H6/H7: a DENIED operation must actually be DENIED, and must be
    the operation the row claims.

    A 2xx can NEVER satisfy one of these rows, and neither can a request
    that did not carry this group's validated child credential — a denial
    without a token proves nothing about the token's scope (Codex
    BLOCKER 2-A). `target` names the key the row is defined against;
    `require_list_query` additionally requires a real ListObjectsV2 query
    (Codex BLOCKER 2-B).
    """
    def derive(spec, request, response, siblings, sibling_responses=()):
        if request.get("http_method") != method:
            return _inconclusive()
        if not _key_matches_target(request.get("key"), target):
            return _inconclusive()
        if require_list_query and \
                ("list-type", "2") not in _query_pairs(request):
            return _inconclusive()
        if not _child_credential_bound(spec, request):
            return _inconclusive()
        if not _denied(response.get("status")):
            return _inconclusive()
        return TestResultDerivation("SCOPE_DENIED_OK", True, False)
    return derive


def _key_matches_target(key, target) -> bool:
    policy = _policy()
    if target == "sacrificial":
        return key == policy.sacrificial_key
    if target == "out_of_prefix":
        return key == policy.denied_out_of_prefix_key
    if target == "bucket":
        # A bucket-level listing addresses no object key.
        return key == ""
    # "allocated": this repetition's own key, never a fixed policy key.
    return (type(key) is str and key.startswith(policy.key_prefix)
            and key not in (policy.sacrificial_key,
                            policy.denied_out_of_prefix_key))


def _derive_i1(spec, request, response, siblings, sibling_responses=()):
    """I1: the security token must actually appear in SignedHeaders, on a
    request that really carried this group's child credential."""
    if not _child_credential_bound(spec, request):
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    return TestResultDerivation("SIGNING_CONTRACT_OK", True, False)


def _derive_i2(spec, request, response, siblings, sibling_responses=()):
    """I2 is DIAGNOSTIC ONLY: the token was PHYSICALLY TRANSMITTED but
    deliberately excluded from SignedHeaders (Codex BLOCKER 2-C).

    Both facts come from the wire: the header is present, and the header
    name is absent from SignedHeaders. A request that never carried a token
    cannot satisfy this row.
    """
    token_header = _grammar().security_token_header
    if request.get("session_token_present") is not True:
        return _inconclusive()
    if type(request.get("session_token_sha256")) is not str:
        return _inconclusive()
    if request.get("session_token_signed") is not False:
        return _inconclusive()
    if token_header in _signed_header_names(request):
        return _inconclusive()
    if request.get("credential_group") != spec.group:
        return _inconclusive()
    if response.get("status") is None:
        return _inconclusive()
    return TestResultDerivation("SIGNING_DIAGNOSTIC_RECORDED", True, False)


def _derive_i3(spec, request, response, siblings, sibling_responses=()):
    """I3: with the token omitted entirely, the request must be REJECTED.

    Success here would mean the token was not really required. The row
    claims no group binding: with nothing transmitted there is no signed
    claim to decode, and the parent access key is shared across groups.
    """
    token_header = _grammar().security_token_header
    if request.get("session_token_present") is not False:
        return _inconclusive()
    if request.get("session_token_sha256") is not None:
        return _inconclusive()
    if token_header in _signed_header_names(request):
        return _inconclusive()
    # With no token transmitted there is nothing to decode a group from,
    # so this row deliberately claims no group binding (see its matrix
    # description) rather than trusting a caller-supplied one.
    if request.get("credential_group") is not None:
        return _inconclusive()
    if type(request.get("access_key_id_sha256")) is not str:
        return _inconclusive()
    if not _denied(response.get("status")):
        return _inconclusive()
    return TestResultDerivation("SIGNING_CONTRACT_OK", True, False)


def _derive_i4(spec, request, response, siblings, sibling_responses=()):
    """I4: the TTL must be PROVEN to have elapsed (Codex BLOCKER 2-D).

    The persisted evidence carries the credential's issued/expires window
    and the request's own signing time, so the row can require that the
    request was made after expiry with THAT credential, and was rejected.
    A generic AccessDenied inside the validity window is INCONCLUSIVE.
    """
    if not _child_credential_bound(spec, request):
        return _inconclusive()
    window = _credential_window(request)
    if window is None:
        return _inconclusive()
    issued_at, expires_at, request_at = window
    if not issued_at < expires_at:
        return _inconclusive()
    if request_at < expires_at:
        return _inconclusive()          # still inside the validity window
    if not _denied(response.get("status")):
        return _inconclusive()
    if type(response.get("error_code")) is not str:
        return _inconclusive()
    return TestResultDerivation("CREDENTIAL_EXPIRY_ENFORCED", True, False)


def _derive_k1(spec, request, response, siblings, sibling_responses=()):
    """K1: ABSENT via the existing absence classifier — an AUTHENTICATED
    GET returning 404 NoSuchKey, nothing weaker."""
    if not _child_credential_bound(spec, request):
        return _inconclusive()
    state = classify_remote_state(
        method=request.get("http_method"), status=response.get("status"),
        error_code=response.get("error_code"),
        body_truncated=bool(response.get("body_truncated")))
    if state is not RemoteState.ABSENT:
        return _inconclusive()
    return TestResultDerivation("ABSENT_CONFIRMED", True, False)


def _derive_k2(spec, request, response, siblings, sibling_responses=()):
    """K2: the denial contrast — an out-of-prefix access under the same
    child credential must come back as a denial, proving 404 and 403 are
    distinguishable."""
    if not _key_matches_target(request.get("key"), "out_of_prefix"):
        return _inconclusive()
    if not _child_credential_bound(spec, request):
        return _inconclusive()
    if not _denied(response.get("status")):
        return _inconclusive()
    if type(response.get("error_code")) is not str:
        return _inconclusive()
    return TestResultDerivation("DENIAL_CONTRAST_OK", True, False)


#: R2 documents one write per second per object key. The throttle window is
#: measured in PHYSICAL nanoseconds between the two conn.request boundaries.
K3_THROTTLE_WINDOW_NS = 1_000_000_000


def _derive_k3(spec, request, response, siblings, sibling_responses=()):
    """K3: a throttle provoked by REPEATED SAME-KEY WRITES.

    THROTTLE_OBSERVED requires ALL of:
      - the throttled attempt is a PUT that returned a DEFINITE 429, with a
        PHYSICAL transport-attempt timestamp;
      - an EARLIER same-key PUT from this repetition whose RESPONSE was a
        DEFINITE 2xx — the server actually OBSERVED and accepted a first
        write (Codex HIGH 2) — and which also carries a physical
        transport-attempt timestamp;
      - `0 <= second_attempt_ns - first_attempt_ns <= 1s`.

    TIME SOURCE (Codex round-3 BLOCKER 3). Only
    `t_request_attempt_mono_ns` — captured at the actual `conn.request()`
    boundary — may satisfy the window. The signed `x-amz-date` /
    `request_time_epoch` is DELIBERATELY not consulted: two requests can
    carry the same signed date while their real transmissions are seconds
    apart, and that must never read as a throttle. A missing timestamp on
    either attempt is INCONCLUSIVE.
    """
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if response.get("status") != 429:
        return _inconclusive()
    key = request.get("key")
    if not _key_matches_target(key, "allocated"):
        return _inconclusive()
    sequence = request.get("sequence")
    second_ns = request.get("t_request_attempt_mono_ns")
    if type(sequence) is not int or type(second_ns) is not int:
        return _inconclusive()
    responses_by_corr = {
        r.get("correlation_id"): r for r in sibling_responses
        if type(r) is dict}
    for prior in siblings:
        if prior.get("http_method") != "PUT" or prior.get("key") != key:
            continue
        prior_sequence = prior.get("sequence")
        first_ns = prior.get("t_request_attempt_mono_ns")
        if type(prior_sequence) is not int or type(first_ns) is not int:
            continue
        if prior_sequence >= sequence:
            continue
        # The earlier same-key write must have been SERVER-OBSERVED (a
        # definite 2xx). Without its response, or with a non-2xx one, this
        # sibling proves nothing.
        prior_response = responses_by_corr.get(prior.get("correlation_id"))
        if prior_response is None or not _is_2xx(prior_response.get("status")):
            continue
        delta = second_ns - first_ns
        if 0 <= delta <= K3_THROTTLE_WINDOW_NS:
            return TestResultDerivation("THROTTLE_OBSERVED", True, False)
    return _inconclusive()


def _derive_j(spec, request, response, siblings, sibling_responses=()):
    """J: a production-size SINGLE-PART PUT.

    Production size is DERIVED here from the persisted request (BLOCKER 2):
    request_body_len must equal the captured policy production body size
    exactly. A one-byte J request can never increment the production-size
    count, because nothing the caller says is consulted.
    """
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if request.get("request_body_len") != _policy().production_body_bytes:
        return _inconclusive()
    if type(request.get("request_body_sha256")) is not str:
        return _inconclusive()
    if request.get("multipart_markers_present") is not False:
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    return TestResultDerivation("SINGLE_PART_PROVEN", True, True)


def _derive_l(spec, request, response, siblings, sibling_responses=()):
    """L: raw byte integrity — the read-back hash AND length must equal
    what was sent."""
    if request.get("http_method") != "PUT":
        return _inconclusive()
    if not _is_2xx(response.get("status")):
        return _inconclusive()
    if not _readback_matches(request, response):
        return _inconclusive()
    return TestResultDerivation("BYTE_INTEGRITY_OK", True, False)


def _create_only_conditional(created, idempotent):
    """X1/X2: a CREATE-ONLY conditional write (Codex BLOCKER 2-F/G).

    Both rows require a real `PUT` carrying `If-None-Match: *` — an
    unconditional GET can never satisfy either. A 2xx is a create. A 412
    counts as idempotent ONLY with an authenticated read-back confirming
    the existing object is byte-identical (exact sha256 AND length).

    The probe writes OPAQUE bytes, so it cannot observe a document's own
    version field or semantic hash; the rows therefore claim raw-byte
    idempotency only, and the matrix descriptions say exactly that. No
    placeholder stands in for a fact the live row does not establish.
    """
    def derive(spec, request, response, siblings, sibling_responses=()):
        if request.get("http_method") != "PUT":
            return _inconclusive()
        if request.get("if_none_match_raw") != "*":
            return _inconclusive()
        if request.get("if_match_raw") is not None:
            return _inconclusive()
        if not _key_matches_target(request.get("key"), "allocated"):
            return _inconclusive()
        if type(request.get("request_body_sha256")) is not str:
            return _inconclusive()
        status = response.get("status")
        if _is_2xx(status):
            return TestResultDerivation(created, True, False)
        if status != 412:
            return _inconclusive()
        if _remote_state_of(response) is not RemoteState.CONFIRMED:
            return _inconclusive()
        if not _readback_matches(request, response):
            return _inconclusive()
        return TestResultDerivation(idempotent, True, False)
    return derive


def _capture_derivations():
    """One derivation per support matrix row, bound to the exact functions
    at import. Closed over so rebinding any exported name is inert."""
    table = {
        "A": _derive_a,
        "C": _derive_c,
        "G": _derive_g,
        "H1": _allowed_scope("HEAD"),
        "H2": _allowed_scope("GET"),
        "H3": _allowed_scope("PUT"),
        "H4": _denied_scope("DELETE", target="sacrificial"),
        "H5": _denied_scope("GET", target="bucket",
                            require_list_query=True),
        "H6": _denied_scope("GET", target="out_of_prefix"),
        "H7": _denied_scope("PUT", target="out_of_prefix"),
        "I1": _derive_i1,
        "I2": _derive_i2,
        "I3": _derive_i3,
        "I4": _derive_i4,
        "K1": _derive_k1,
        "K2": _derive_k2,
        "K3": _derive_k3,
        "J": _derive_j,
        "L": _derive_l,
        "X1": _create_only_conditional("ARCHIVE_CREATED",
                                       "ARCHIVE_IDEMPOTENT"),
        "X2": _create_only_conditional("AUDIT_CREATED", "AUDIT_IDEMPOTENT"),
    }
    return lambda table=table: table


_derivations = _capture_derivations()


def derive_test_result(spec, request_record, response_record, *,
                       sibling_requests=(),
                       sibling_responses=()) -> TestResultDerivation:
    """DERIVE one support-row repetition's result from its own evidence.

    `spec` selects the row-specific derivation; there is no shared success
    list, so an H4 denial row cannot be satisfied by an archive outcome and
    an archive row cannot be satisfied by a scope outcome. Both records
    must belong to this exact test and repetition.

    `sibling_requests` are the OTHER persisted REQUEST_RECORDs of the same
    test and repetition; `sibling_responses` are their RESPONSE_RECORDs.
    Only K3 uses them — to prove the earlier same-key write was actually
    server-observed (a definite 2xx), not merely attempted (Codex HIGH 2).
    """
    # Anchored on a row of the CAPTURED matrix rather than the rebindable
    # `TestSpec` name, so rebinding that name cannot disable derivation.
    if type(spec) is not type(_policy().matrix[0]):
        raise SafetyBarrierTripped("spec must be exactly TestSpec")
    if spec.category in ("semantic", "race"):
        raise SafetyBarrierTripped(
            f"{spec.id} has its own typed record; it has no test result "
            "derivation")
    for name, record in (("request_record", request_record),
                         ("response_record", response_record)):
        if type(record) is not dict:
            raise SafetyBarrierTripped(f"{name} must be exactly dict")
    if request_record.get("record_kind") != "REQUEST_RECORD":
        raise SafetyBarrierTripped("expected a REQUEST_RECORD")
    if response_record.get("record_kind") != "RESPONSE_RECORD":
        raise SafetyBarrierTripped("expected a RESPONSE_RECORD")
    if request_record.get("correlation_id") \
            != response_record.get("correlation_id"):
        raise SafetyBarrierTripped(
            "request and response must share one correlation")
    if request_record.get("test_id") != spec.id:
        raise SafetyBarrierTripped(
            f"evidence belongs to {request_record.get('test_id')!r}, "
            f"not {spec.id!r}")
    derive = _derivations().get(spec.id)
    if derive is None:
        raise SafetyBarrierTripped(
            f"no result derivation is defined for {spec.id!r} — refusing")
    if type(sibling_requests) not in (tuple, list):
        raise SafetyBarrierTripped("sibling_requests must be tuple/list")
    siblings = []
    for sibling in sibling_requests:
        if type(sibling) is not dict \
                or sibling.get("record_kind") != "REQUEST_RECORD":
            raise SafetyBarrierTripped(
                "sibling_requests must all be REQUEST_RECORDs")
        if sibling.get("test_id") != spec.id \
                or sibling.get("repetition") != request_record["repetition"]:
            raise SafetyBarrierTripped(
                "sibling_requests must belong to this test and repetition")
        if sibling.get("correlation_id") != request_record["correlation_id"]:
            siblings.append(sibling)
    if type(sibling_responses) not in (tuple, list):
        raise SafetyBarrierTripped("sibling_responses must be tuple/list")
    sibling_resps = []
    for sibling in sibling_responses:
        if type(sibling) is not dict \
                or sibling.get("record_kind") != "RESPONSE_RECORD":
            raise SafetyBarrierTripped(
                "sibling_responses must all be RESPONSE_RECORDs")
        if sibling.get("test_id") != spec.id \
                or sibling.get("repetition") != request_record["repetition"]:
            raise SafetyBarrierTripped(
                "sibling_responses must belong to this test and repetition")
        if sibling.get("correlation_id") != request_record["correlation_id"]:
            sibling_resps.append(sibling)
    result = derive(spec, request_record, response_record, tuple(siblings),
                    tuple(sibling_resps))
    if type(result) is not TestResultDerivation:
        raise SafetyBarrierTripped("a derivation returned a foreign type")
    if result.outcome not in _test_result_outcomes():
        raise SafetyBarrierTripped(
            f"derived outcome {result.outcome!r} is not a known outcome")
    if result.production_size and spec.production_size_repetitions == 0:
        raise SafetyBarrierTripped(
            f"{spec.id} requires no production-size repetitions")
    if result.production_size and not result.valid:
        raise SafetyBarrierTripped(
            "a production-size repetition must also be valid")
    return result


# ─────────────────────────────────────────────────────────────────────────
# Evidence — per-field validation (Codex HIGH 3)
# ─────────────────────────────────────────────────────────────────────────


#: Every persisted evidence file declares exactly one of these kinds, and
#: is validated by that kind's cross-field rules (BLOCKER 3). RUN_SUMMARY
#: is NOT in this set — a summary is DERIVED, never caller-persisted.
class _RecordTaxonomy(NamedTuple):
    kinds: frozenset
    #: The record kinds that carry acceptance. Each one must reference
    #: exactly one physical ISSUANCE_RECORD (Codex BLOCKER 3).
    acceptance_kinds: frozenset
    #: acceptance kind -> the ISSUANCE_RECORD.identity_kind that may back it
    issuance_kind_for_record: tuple


def _capture_record_taxonomy():
    """Capture the record taxonomy ONCE (Codex HIGH).

    Enforcement reads this closure, never the exported names below, so
    emptying `ACCEPTANCE_RECORD_KINDS` — which would otherwise skip the
    issuance requirement entirely — changes nothing.
    """
    taxonomy = _RecordTaxonomy(
        kinds=frozenset({
            "REQUEST_RECORD", "RESPONSE_RECORD", "SEMANTIC_RECORD",
            "RACE_RECORD", "TEST_RESULT_RECORD", "ISSUANCE_RECORD"}),
        acceptance_kinds=frozenset({
            "SEMANTIC_RECORD", "RACE_RECORD", "TEST_RESULT_RECORD"}),
        issuance_kind_for_record=(("SEMANTIC_RECORD", "semantic"),
                                  ("RACE_RECORD", "race"),
                                  ("TEST_RESULT_RECORD", "support")))
    return lambda taxonomy=taxonomy: taxonomy


_taxonomy = _capture_record_taxonomy()


def issuance_kind_for_record_kind(kind) -> str:
    for known, identity_kind in _taxonomy().issuance_kind_for_record:
        if known == kind:
            return identity_kind
    raise SafetyBarrierTripped(f"{kind!r} is not an acceptance record kind")


#: DISPLAY ONLY — rebinding any of these three changes nothing enforced.
RECORD_KINDS = _taxonomy().kinds
ACCEPTANCE_RECORD_KINDS = _taxonomy().acceptance_kinds
ISSUANCE_KIND_FOR_RECORD = dict(_taxonomy().issuance_kind_for_record)


def issuance_kind_for_test(test_id) -> str:
    """DERIVED from TEST_MATRIX, never supplied."""
    category = test_spec(test_id).category
    if category == "semantic":
        return "semantic"
    if category == "race":
        return "race"
    return "support"

#: Outcome classifications a TEST_RESULT_RECORD may carry (BLOCKER 1). Each
#: is DERIVED from persisted request/response evidence or from an existing
#: validated model outcome — never chosen by the caller.
def _capture_test_result_outcomes():
    outcomes = frozenset({
        # scope: a denied op genuinely refused, or an allowed one worked
        "SCOPE_ALLOWED_OK", "SCOPE_DENIED_OK",
        # signing / diagnostics
        "SIGNING_CONTRACT_OK", "SIGNING_DIAGNOSTIC_RECORDED",
        # absence classification
        "ABSENT_CONFIRMED", "DENIAL_CONTRAST_OK", "THROTTLE_OBSERVED",
        # shape / integrity
        "SINGLE_PART_PROVEN", "BYTE_INTEGRITY_OK", "ETAG_ROUNDTRIP_OK",
        "CORRECT_ETAG_ACCEPTED", "CREATE_IF_ABSENT_OK",
        # archive / audit model outcomes
        "ARCHIVE_IDEMPOTENT", "ARCHIVE_CREATED", "AUDIT_CREATED",
        "AUDIT_IDEMPOTENT",
        # credential expiry
        "CREDENTIAL_EXPIRY_ENFORCED",
        # explicit non-valid outcome
        "INCONCLUSIVE",
    })
    return lambda outcomes=outcomes: outcomes


_test_result_outcomes = _capture_test_result_outcomes()

#: DISPLAY ONLY — enforcement reads the closure above.
TEST_RESULT_OUTCOMES = _test_result_outcomes()


def _reject_credential_shapes(text: str, field: str, *,
                              check_account_id: bool = True) -> None:
    """Reject credential-shaped content ANYWHERE within `text` (HIGH 3).

    Used on the inner content of a value after any field-specific
    normalisation (e.g. ETag unwrapping). Known-secret scanning remains
    defence in depth on top of this.

    `check_account_id` is False for ETag inner content: a normal single-
    part S3/R2 ETag is a 32-hex MD5, which is the same shape as an account
    id but is NOT a secret — rejecting it would reject every ordinary
    ETag. The endpoint-host, JWT, session-token and Authorization checks
    still apply, so a QUOTED credential inside an ETag is still refused.
    """
    if _grammar().r2_host_any.search(text):
        raise EvidenceValidationError(
            f"{field}: full R2 endpoint hostname refused")
    if check_account_id and _grammar().account_id_anywhere.search(text):
        raise EvidenceValidationError(
            f"{field}: 32-hex account-id-shaped run refused")
    if "AWS4-HMAC-SHA256" in text:
        raise EvidenceValidationError(
            f"{field}: Authorization-shaped value refused")
    if _grammar().jwt_anywhere.search(text):
        raise EvidenceValidationError(f"{field}: JWT-shaped value refused")
    if _grammar().session_token_anywhere.search(text):
        raise EvidenceValidationError(
            f"{field}: session-token-shaped value refused")


def _reject_dangerous_shapes(value: str, field: str) -> None:
    """Default rejection for identifier-like fields (keys, header names).

    These fields are exact tokens, so the whole value is inspected. The
    32-hex account-id check is a fullmatch here to avoid rejecting a
    legitimate 64-hex sha256 in a hash field (those use _v_sha256 and
    never route through here)."""
    if _grammar().account_id.fullmatch(value):
        raise EvidenceValidationError(
            f"{field}: bare 32-hex account id refused")
    _reject_credential_shapes(value, field)


def _unwrap_etag_inner(value: str) -> str:
    """Return the opaque inner content of an ETag, dropping an optional
    `W/` weak marker and the surrounding quotes. `*` unwraps to `*`."""
    inner = value
    if inner.startswith("W/"):
        inner = inner[2:]
    if len(inner) >= 2 and inner[0] == '"' and inner[-1] == '"':
        inner = inner[1:-1]
    return inner


def _v_etag(*, allow_none=True):
    """ETag-aware validator (HIGH 3 + MEDIUM 2).

    Unwraps `(W/)?"..."` and inspects the INNER content:
      - an inner value that is EXACTLY 32 lowercase hex is a legitimate
        single-part MD5 ETag and is allowed;
      - otherwise the full credential-shape check applies, INCLUDING the
        32-hex account-id-run check — so an account-id embedded inside a
        longer ETag (e.g. "opaque-<32hex>-tail") is rejected, while a
        quoted session token / JWT / Authorization / host value is too.
    """
    def check(value, field):
        if value is None:
            if allow_none:
                return
            raise EvidenceValidationError(f"{field}: must not be None")
        if type(value) is not str:
            raise EvidenceValidationError(f"{field}: must be exactly str")
        if len(value) > 256 or any(ch in value for ch in "\x00\r\n"):
            raise EvidenceValidationError(f"{field}: malformed etag")
        if not _grammar().etag.fullmatch(value):
            raise EvidenceValidationError(f"{field}: not an ETag shape")
        inner = _unwrap_etag_inner(value)
        if _grammar().account_id.fullmatch(inner):
            return   # exactly-32-hex opaque MD5 ETag — legitimate
        _reject_credential_shapes(inner, field, check_account_id=True)
    return check


def _v_str(*, max_len, pattern=None, choices=None, allow_none=False,
           allow_empty=False, free_text=False):
    def check(value, field):
        if value is None:
            if allow_none:
                return
            raise EvidenceValidationError(f"{field}: must not be None")
        if type(value) is not str:
            raise EvidenceValidationError(
                f"{field}: must be exactly str, got {type(value).__name__}")
        if not allow_empty and value == "":
            raise EvidenceValidationError(f"{field}: must not be empty")
        if len(value) > max_len:
            raise EvidenceValidationError(
                f"{field}: exceeds {max_len} characters")
        if any(ch in value for ch in "\x00\r\n"):
            raise EvidenceValidationError(f"{field}: control character")
        if choices is not None and value not in choices:
            raise EvidenceValidationError(f"{field}: {value!r} not permitted")
        if pattern is not None and not pattern.fullmatch(value):
            raise EvidenceValidationError(f"{field}: malformed value")
        if free_text:
            # Search credential shapes ANYWHERE in a free-text field.
            _reject_credential_shapes(value, field)
        else:
            _reject_dangerous_shapes(value, field)
    return check


def _v_int(*, minimum=0, maximum=None, allow_none=False):
    def check(value, field):
        if value is None:
            if allow_none:
                return
            raise EvidenceValidationError(f"{field}: must not be None")
        if type(value) is not int:
            raise EvidenceValidationError(
                f"{field}: must be exactly int, got {type(value).__name__}")
        if value < minimum:
            raise EvidenceValidationError(f"{field}: must be >= {minimum}")
        if maximum is not None and value > maximum:
            raise EvidenceValidationError(f"{field}: must be <= {maximum}")
    return check


def _v_bool(*, allow_none=False):
    def check(value, field):
        if value is None and allow_none:
            return
        if type(value) is not bool:
            raise EvidenceValidationError(f"{field}: must be exactly bool")
    return check


def _v_sha256(*, allow_none=True):
    def check(value, field):
        if value is None:
            if allow_none:
                return
            raise EvidenceValidationError(f"{field}: must not be None")
        if type(value) is not str or not _grammar().sha256.fullmatch(value):
            raise EvidenceValidationError(
                f"{field}: must be exactly 64 lowercase hex")
    return check


def _v_hexblob(*, max_len, allow_none=True):
    def check(value, field):
        if value is None:
            if allow_none:
                return
            raise EvidenceValidationError(f"{field}: must not be None")
        if type(value) is not str or not _grammar().hexblob.fullmatch(value) \
                or len(value) % 2 or len(value) > max_len:
            raise EvidenceValidationError(
                f"{field}: must be even-length lowercase hex <= {max_len}")
    return check


def _v_str_list(*, allowed_pattern, max_items):
    def check(value, field):
        if type(value) not in (list, tuple):
            raise EvidenceValidationError(
                f"{field}: must be exactly list or tuple")
        if len(value) > max_items:
            raise EvidenceValidationError(f"{field}: too many items")
        for item in value:
            if type(item) is not str or not allowed_pattern.fullmatch(item):
                raise EvidenceValidationError(f"{field}: bad list item")
            _reject_dangerous_shapes(item, field)
    return check


def _v_query_params():
    """The exact canonical query of the request, as [name, value] pairs.

    H5 has to prove it really issued ListObjectsV2, which is a query fact;
    without persisting the query there is nothing to derive it from.
    """
    def check(value, field):
        if type(value) not in (list, tuple):
            raise EvidenceValidationError(
                f"{field}: must be exactly list or tuple")
        if len(value) > 16:
            raise EvidenceValidationError(f"{field}: too many query pairs")
        grammar = _grammar()
        for pair in value:
            if type(pair) not in (list, tuple) or len(pair) != 2:
                raise EvidenceValidationError(
                    f"{field}: each item must be a [name, value] pair")
            name, item = pair
            if type(name) is not str or not grammar.query_name.fullmatch(name):
                raise EvidenceValidationError(f"{field}: bad query name")
            if type(item) is not str or len(item) > 256:
                raise EvidenceValidationError(f"{field}: bad query value")
            _reject_dangerous_shapes(name, field)
            _reject_dangerous_shapes(item, field)
    return check


def _v_choice_list(*, choices, max_items, max_len):
    def check(value, field):
        if value is None:
            return
        if type(value) not in (list, tuple):
            raise EvidenceValidationError(
                f"{field}: must be exactly list or tuple")
        if len(value) > max_items:
            raise EvidenceValidationError(f"{field}: too many items")
        for item in value:
            if type(item) is not str or len(item) > max_len \
                    or item not in choices:
                raise EvidenceValidationError(f"{field}: bad list item")
    return check


def _v_key():
    def check(value, field):
        if value is None:
            return
        if type(value) is not str:
            raise EvidenceValidationError(f"{field}: must be exactly str")
        policy = _policy()
        # The two fixed policy keys, plus the empty key of a bucket-level
        # ListObjectsV2 (H5), which addresses no object.
        allowed_exceptions = (policy.sacrificial_key,
                              policy.denied_out_of_prefix_key, "")
        if value in allowed_exceptions:
            return
        if not _grammar().live_key.fullmatch(value) \
                or not value.startswith(policy.key_prefix):
            raise EvidenceValidationError(
                f"{field}: not a probe key ({value!r})")
        _reject_dangerous_shapes(value, field)
    return check


def _v_bucket():
    def check(value, field):
        if value is None:
            return
        if type(value) is not str or value != _policy().bucket:
            raise EvidenceValidationError(
                f"{field}: must be exactly the disposable probe bucket")
    return check


def _make_evidence_field_validators():
    """Built inside a closure so the table cannot be rebound wholesale."""
    groups = tuple(_matrix_groups(_policy()))
    tests = tuple(sorted(known_test_ids()))
    return {
        "record_kind": _v_str(max_len=24, choices=_taxonomy().kinds),
        "run_id": _v_str(max_len=40, pattern=_grammar().run_id, allow_none=True),
        "outcome_classification": _v_str(
            max_len=48, choices=_test_result_outcomes(), allow_none=True),
        "derived_valid": _v_bool(allow_none=True),
        "derived_production_size": _v_bool(allow_none=True),
        "evidence_refs": _v_str_list(allowed_pattern=_grammar().correlation,
                                     max_items=8),
        "mutation_observed": _v_bool(allow_none=True),
        "race_repetition_status": _v_str(
            max_len=24,
            choices=frozenset(s.value for s in RaceRepetitionStatus),
            allow_none=True),
        "shared_original_etag": _v_etag(allow_none=True),
        "absence_confirmed": _v_bool(allow_none=True),
        "phase": _v_str(max_len=1, choices=_grammar().phases),
        "group": _v_str(max_len=16, choices=frozenset(groups)),
        "test_id": _v_str(max_len=16, choices=frozenset(tests)),
        "repetition": _v_int(minimum=1, maximum=9999),
        "sequence": _v_int(minimum=0, maximum=9999),
        "bucket": _v_bucket(),
        "key": _v_key(),
        "endpoint_host_sha256": _v_sha256(allow_none=False),
        "http_method": _v_str(max_len=8, choices=_grammar().http_methods),
        "status": _v_int(minimum=100, maximum=599, allow_none=True),
        "error_code": _v_str(max_len=64, pattern=_grammar().error_code,
                             allow_none=True),
        "error_message": _v_str(max_len=200, pattern=_grammar().safe_message,
                                allow_none=True, free_text=True),
        "message_omitted": _v_bool(),
        "request_id": _v_str(max_len=128, pattern=_grammar().request_id,
                             allow_none=True, free_text=True),
        "cf_ray": _v_str(max_len=64, pattern=_grammar().cf_ray, allow_none=True),
        "host_id_sha256": _v_sha256(),
        "etag_raw": _v_etag(allow_none=True),
        "etag_raw_hex": _v_hexblob(max_len=512),
        "if_match_raw": _v_etag(allow_none=True),
        "if_match_raw_hex": _v_hexblob(max_len=512),
        "if_none_match_raw": _v_etag(allow_none=True),
        "if_none_match_raw_hex": _v_hexblob(max_len=512),
        "signed_headers": _v_str_list(allowed_pattern=_grammar().header_name,
                                      max_items=16),
        "session_token_present": _v_bool(),
        "session_token_sha256": _v_sha256(),
        "request_body_len": _v_int(minimum=0, allow_none=True),
        "request_body_sha256": _v_sha256(),
        "response_body_len": _v_int(minimum=0, allow_none=True),
        "response_body_sha256": _v_sha256(),
        "body_truncated": _v_bool(allow_none=True),
        "final_get_len": _v_int(minimum=0, allow_none=True),
        "final_get_sha256": _v_sha256(),
        "final_etag": _v_etag(allow_none=True),
        "t_request_start_mono_ns": _v_int(minimum=0, allow_none=True),
        "t_response_end_mono_ns": _v_int(minimum=0, allow_none=True),
        # The PHYSICAL instant captured at the conn.request() boundary
        # (Codex round-3 BLOCKER 3). None only when no request was ever
        # attempted. K3's throttle window is measured from THIS and from
        # nothing else — never from a signed date or a response time.
        "t_request_attempt_mono_ns": _v_int(minimum=0, allow_none=True),
        "race_attribution": _v_str(
            max_len=16, choices=frozenset(a.value for a in RaceAttribution),
            allow_none=True),
        "repetition_status": _v_str(
            max_len=32,
            choices=frozenset(s.value for s in RepetitionStatus)
            | {"ABANDON"},
            allow_none=True),
        "multipart_markers_present": _v_bool(allow_none=True),
        "ambiguous_state": _v_str(
            max_len=48, choices=frozenset(o.value for o in PutOutcome),
            allow_none=True),
        "reconciliation": _v_str(
            max_len=48, choices=frozenset(r.value for r in Reconciliation),
            allow_none=True),
        "remote_state": _v_str(
            max_len=16, choices=frozenset(s.value for s in RemoteState),
            allow_none=True),
        "error_category": _v_str(
            max_len=48, choices=frozenset(c.value for c in ErrorCategory),
            allow_none=True),
        "exception_type_name": _v_str(max_len=64, pattern=_grammar().ident,
                                      allow_none=True),
        "writer_id": _v_str(max_len=32, pattern=_grammar().writer_id,
                            allow_none=True),
        "setup_state": _v_str(
            max_len=32,
            choices=frozenset(spec.race_setup_state
                              for spec in _policy().matrix
                              if spec.race_setup_state is not None),
            allow_none=True),
        "payload_length": _v_int(minimum=0, allow_none=True),
        # Round-4 additions.
        "credential_expired": _v_bool(allow_none=True),
        "correlation_id": _v_str(max_len=80, pattern=_grammar().correlation,
                                 allow_none=True),
        "issuance_nonce": _v_str(max_len=48, pattern=_grammar().issuance_nonce),
        "session_token_signed": _v_bool(allow_none=True),
        "access_key_id_sha256": _v_sha256(),
        "request_time_epoch": _v_int(minimum=0, allow_none=True),
        "query_params": _v_query_params(),
        "credential_group": _v_str(
            max_len=16, choices=frozenset(_matrix_groups(_policy())),
            allow_none=True),
        "credential_scope": _v_str(
            max_len=32, choices=frozenset({_policy().credential_scope}),
            allow_none=True),
        "credential_actions": _v_choice_list(
            choices=frozenset(_policy().credential_actions),
            max_items=8, max_len=32),
        "credential_prefixes": _v_choice_list(
            choices=frozenset(_policy().credential_prefixes),
            max_items=8, max_len=128),
        "credential_issued_at": _v_int(minimum=0, allow_none=True),
        "credential_expires_at": _v_int(minimum=0, allow_none=True),
        "identity_kind": _v_str(
            max_len=16,
            choices=frozenset(k for _, k
                              in _taxonomy().issuance_kind_for_record)),
        "barrier_generation_id": _v_str(max_len=64, pattern=_grammar().barrier_gen,
                                        allow_none=True),
        "barrier_release_mono_ns": _v_int(minimum=0, allow_none=True),
        "final_state": _v_str(
            max_len=16, choices=frozenset(s.value for s in RemoteState),
            allow_none=True),
        "final_sha256": _v_sha256(),
        "final_length": _v_int(minimum=0, allow_none=True),
        **_race_writer_field_validators("w1"),
        **_race_writer_field_validators("w2"),
    }


def _race_writer_field_validators(prefix):
    """Flat per-writer RACE_RECORD field validators (BLOCKER 2)."""
    return {
        f"{prefix}_writer_id": _v_str(max_len=32, pattern=_grammar().writer_id,
                                      allow_none=True),
        f"{prefix}_http_status": _v_int(minimum=100, maximum=599,
                                        allow_none=True),
        f"{prefix}_payload_sha256": _v_sha256(),
        f"{prefix}_payload_length": _v_int(minimum=0, allow_none=True),
        f"{prefix}_returned_etag": _v_etag(allow_none=True),
        f"{prefix}_if_match": _v_etag(allow_none=True),
        f"{prefix}_if_none_match": _v_str(
            max_len=1, choices=frozenset({"*"}), allow_none=True),
        f"{prefix}_barrier_generation": _v_str(
            max_len=64, pattern=_grammar().barrier_gen, allow_none=True),
        f"{prefix}_barrier_join_mono_ns": _v_int(minimum=0, allow_none=True),
        f"{prefix}_send_mono_ns": _v_int(minimum=0, allow_none=True),
    }


def _make_evidence_validator():
    validators = _make_evidence_field_validators()
    allowed = frozenset(validators)

    def validate(record, secrets: Iterable[str] = ()) -> None:
        if type(record) is not dict:
            raise EvidenceValidationError(
                "evidence record must be exactly dict")
        for key, value in record.items():
            if type(key) is not str:
                raise EvidenceValidationError(
                    "evidence keys must be exactly str")
            check = validators.get(key)
            if check is None:
                raise EvidenceValidationError(
                    f"evidence field {key!r} is not on the allowlist")
            check(value, key)
        # No default=str anywhere: every value is already a flat exact
        # primitive, so a plain dumps cannot stringify a rogue object.
        serialized = json.dumps(record, sort_keys=True)
        for secret in secrets:
            if secret and secret in serialized:
                raise EvidenceValidationError(
                    "evidence record contains secret material")
        assert_no_denied_names(serialized)

    return validate, allowed


validate_evidence_record, ALLOWED_EVIDENCE_FIELDS = _make_evidence_validator()


# ── Record kinds: exact required/allowed fields + cross-field rules ──────
#
# A generic field validator is not enough (BLOCKER 3): a REQUEST record
# must not masquerade as a SEMANTIC one, and a SEMANTIC record must prove
# its status/outcome/label are mutually consistent, not merely well-typed.

_REQUEST_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "group", "test_id", "repetition",
    "sequence", "correlation_id", "bucket", "key", "endpoint_host_sha256",
    "http_method", "query_params", "request_body_len", "request_body_sha256",
    "signed_headers",
    # All DERIVED from the wire (Codex BLOCKER 2) — none is caller-supplied.
    "session_token_present", "session_token_signed", "request_time_epoch"})
_REQUEST_ALLOWED = _REQUEST_REQUIRED | frozenset({
    "if_match_raw", "if_match_raw_hex", "if_none_match_raw",
    "if_none_match_raw_hex", "session_token_sha256", "access_key_id_sha256",
    "multipart_markers_present",
    # The physical conn.request() instant for this request (BLOCKER 3).
    "t_request_attempt_mono_ns",
    # Non-secret identity + validity window of the credential that signed.
    "credential_group", "credential_scope", "credential_actions",
    "credential_prefixes", "credential_issued_at", "credential_expires_at"})

_RESPONSE_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "group", "test_id", "repetition",
    "sequence", "correlation_id", "status"})
_RESPONSE_ALLOWED = _RESPONSE_REQUIRED | frozenset({
    "etag_raw", "etag_raw_hex", "error_code", "error_message",
    "message_omitted", "request_id", "cf_ray", "host_id_sha256",
    "response_body_len", "response_body_sha256", "body_truncated",
    "final_get_len", "final_get_sha256", "final_etag",
    "t_request_start_mono_ns", "t_response_end_mono_ns",
    "ambiguous_state", "remote_state", "reconciliation",
    "error_category", "exception_type_name",
    # Optional derived annotations on a raw response observation. They do
    # not, by themselves, confer acceptance — the SEMANTIC/RACE records do.
    "repetition_status", "race_attribution"})

_SEMANTIC_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "group", "test_id", "repetition",
    "key", "issuance_nonce", "status", "ambiguous_state",
    "mutation_observed", "credential_expired", "repetition_status"})
_SEMANTIC_ALLOWED = _SEMANTIC_REQUIRED | frozenset({"sequence"})

#: RACE_RECORD carries the COMPLETE facts (BLOCKER 2), so the result can be
#: re-derived from the record alone — never a caller-selected label.
_RACE_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "group", "test_id", "repetition",
    "key", "issuance_nonce", "setup_state", "shared_original_etag",
    "absence_confirmed",
    "barrier_generation_id", "barrier_release_mono_ns",
    "final_state", "final_sha256", "final_length", "final_etag",
    "race_repetition_status", "race_attribution"}) | frozenset(
        f"{p}_{f}" for p in ("w1", "w2") for f in (
            "writer_id", "http_status", "payload_sha256", "payload_length",
            "returned_etag", "if_match", "if_none_match", "barrier_generation",
            "barrier_join_mono_ns", "send_mono_ns"))
_RACE_ALLOWED = _RACE_REQUIRED | frozenset({"sequence"})

#: TEST_RESULT_RECORD — the smallest persisted result for the non-semantic,
#: non-race matrix rows (BLOCKER 1). `derived_valid` /
#: `derived_production_size` are recomputed from `outcome_classification`
#: and the referenced persisted evidence, so a caller cannot mark a row
#: complete by asserting valid=True.
#: ISSUANCE_RECORD — the physical proof that the allocator minted this
#: identity (Codex BLOCKER 3). Written when the identity is allocated, so
#: reconstruction can require issuance for every acceptance record without
#: trusting any in-memory registry.
_ISSUANCE_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "test_id", "repetition", "key",
    "issuance_nonce", "identity_kind"})
_ISSUANCE_ALLOWED = _ISSUANCE_REQUIRED

_TEST_RESULT_REQUIRED = frozenset({
    "record_kind", "phase", "run_id", "group", "test_id", "repetition",
    "key", "issuance_nonce", "outcome_classification", "derived_valid",
    "derived_production_size", "evidence_refs"})
#: No caller-supplied audit annotations: every field is derived, so there
#: is nothing left for a caller to add (Codex BLOCKER 1).
_TEST_RESULT_ALLOWED = _TEST_RESULT_REQUIRED


def _require_and_restrict(record, required, allowed, kind):
    missing = required - set(record)
    if missing:
        raise EvidenceValidationError(
            f"{kind}: missing required fields {sorted(missing)}")
    extra = set(record) - allowed
    if extra:
        raise EvidenceValidationError(
            f"{kind}: fields not allowed for this kind {sorted(extra)}")


def _cross_check_group_matches_test(record):
    test_id = record["test_id"]
    if record["group"] != test_spec(test_id).group:
        raise EvidenceValidationError(
            f"group {record['group']!r} does not match the matrix group for "
            f"test {test_id!r}")


def _cross_check_key_identity(record):
    """The key must be allocator-shaped and agree with phase/test/rep."""
    match = _grammar().allocated_key.fullmatch(record["key"])
    if not match:
        raise EvidenceValidationError("key is not allocator-shaped")
    if match.group("phase") != record["phase"].lower():
        raise EvidenceValidationError("key phase disagrees with the record")
    if match.group("test") != record["test_id"].lower():
        raise EvidenceValidationError("key test id disagrees with the record")
    if int(match.group("rep")) != record["repetition"]:
        raise EvidenceValidationError("key repetition disagrees with the record")
    run_id = record.get("run_id")
    if run_id is not None and match.group("run") != run_id:
        raise EvidenceValidationError("key run id disagrees with the record")


class Correlation(NamedTuple):
    """Complete request/response correlation identity (MEDIUM 2). EVERY
    component is compared — a matching test_id alone is not enough."""

    phase: str
    run_id: str
    test_id: str
    repetition: int
    sequence: int

    def serialize(self) -> str:
        return (f"{self.phase}/{self.run_id}/{self.test_id}/"
                f"{self.repetition}/{self.sequence}")


def build_correlation(*, phase, run_id, test_id, repetition,
                      sequence) -> Correlation:
    if type(phase) is not str or phase not in _grammar().phases:
        raise EvidenceValidationError("correlation phase must be 'P' or 'T'")
    if type(run_id) is not str or not _grammar().run_id.fullmatch(run_id):
        raise EvidenceValidationError("correlation run_id refused")
    if type(test_id) is not str or test_id not in known_test_ids():
        raise EvidenceValidationError("correlation test_id refused")
    if type(repetition) is not int or type(repetition) is bool \
            or not (1 <= repetition <= 9999):
        raise EvidenceValidationError("correlation repetition refused")
    if type(sequence) is not int or type(sequence) is bool \
            or not (0 <= sequence <= 999999):
        raise EvidenceValidationError("correlation sequence refused")
    return Correlation(phase=phase, run_id=run_id, test_id=test_id,
                       repetition=repetition, sequence=sequence)


def parse_correlation(value) -> Correlation:
    """Parse a serialized correlation id into its complete identity."""
    if type(value) is not str or not _grammar().correlation.fullmatch(value):
        raise EvidenceValidationError("correlation_id is malformed")
    phase, run_id, test_id, repetition, sequence = value.split("/")
    return build_correlation(phase=phase, run_id=run_id, test_id=test_id,
                             repetition=int(repetition),
                             sequence=int(sequence))


def _cross_check_correlation(record):
    """Every correlation component must equal the record's own fields
    (MEDIUM 2) — phase, run_id, test_id, repetition AND sequence."""
    corr = parse_correlation(record["correlation_id"])
    mismatches = []
    if corr.phase != record["phase"]:
        mismatches.append("phase")
    if corr.run_id != record["run_id"]:
        mismatches.append("run_id")
    if corr.test_id != record["test_id"]:
        mismatches.append("test_id")
    if corr.repetition != record["repetition"]:
        mismatches.append("repetition")
    if corr.sequence != record["sequence"]:
        mismatches.append("sequence")
    if mismatches:
        raise EvidenceValidationError(
            f"correlation_id disagrees with the record on {mismatches}")
    return corr


def _validate_test_result_record(record):
    """Structural checks only — the RESULT itself is re-derived elsewhere.

    There is deliberately no global "valid outcome" list here (Codex
    BLOCKER 1). Whether this repetition counts is decided by
    `derive_test_result` from the referenced physical request/response
    evidence, at write time AND again at reconstruction, which is the only
    place that has those facts. This function therefore checks identity and
    shape: the row is a support row, the key is canonical, the repetition
    is within the cap, and exactly one evidence reference correlates to
    this phase/run/test/repetition.
    """
    _cross_check_group_matches_test(record)
    test_id = record["test_id"]
    spec = test_spec(test_id)
    if spec.category in ("semantic", "race"):
        raise EvidenceValidationError(
            f"TEST_RESULT_RECORD may not cover {spec.category} test "
            f"{test_id!r} — those use their own typed records")
    _cross_check_key_identity(record)
    if record["repetition"] > spec.max_attempts:
        raise EvidenceValidationError(
            f"{test_id}: repetition {record['repetition']} exceeds "
            f"max_attempts {spec.max_attempts}")
    refs = record["evidence_refs"]
    if type(refs) not in (list, tuple) or len(refs) != 1:
        raise EvidenceValidationError(
            "TEST_RESULT_RECORD must reference EXACTLY ONE request/response "
            "correlation — the one whose facts derive the result")
    corr = parse_correlation(refs[0])
    if corr.phase != record["phase"] or corr.run_id != record["run_id"] \
            or corr.test_id != test_id \
            or corr.repetition != record["repetition"]:
        raise EvidenceValidationError(
            "evidence_refs must correlate to this phase/run/test/rep")
    if record["outcome_classification"] not in _test_result_outcomes():
        raise EvidenceValidationError(
            f"unknown outcome {record['outcome_classification']!r}")
    if record["derived_production_size"] and \
            spec.production_size_repetitions == 0:
        raise EvidenceValidationError(
            f"{test_id} requires no production-size repetitions")
    if record["derived_production_size"] and not record["derived_valid"]:
        raise EvidenceValidationError(
            "a production-size repetition must also be valid")


#: DISPLAY ONLY — enforcement reads _evidence_layout()[2].
_RAW_HEX_PAIRS = _evidence_layout()[2]


def _cross_check_raw_hex_pairs(record):
    """Both present or both absent, and the hex must be hex_of(raw).

    Without this, a record could carry a benign-looking raw header beside
    an arbitrary hex blob, and a reviewer reading only one of the two would
    be misled about what went on the wire.
    """
    for raw_name, hex_name in _evidence_layout()[2]:
        has_raw = raw_name in record
        has_hex = hex_name in record
        if has_raw != has_hex:
            present, missing = ((raw_name, hex_name) if has_raw
                                else (hex_name, raw_name))
            raise EvidenceValidationError(
                f"{present} is present without {missing} — raw/hex pairs "
                "must appear together")
        if not has_raw:
            continue
        raw_value = record[raw_name]
        hex_value = record[hex_name]
        if raw_value is None or hex_value is None:
            if raw_value is not None or hex_value is not None:
                raise EvidenceValidationError(
                    f"{raw_name}/{hex_name} must be null together")
            continue
        if type(raw_value) is not str or type(hex_value) is not str:
            raise EvidenceValidationError(
                f"{raw_name}/{hex_name} must both be exactly str")
        if hex_value != hex_of(raw_value):
            raise EvidenceValidationError(
                f"{hex_name} is not the hex transcription of {raw_name}")


def _validate_issuance_record(record):
    """The issuance must be self-consistent: its key must be the canonical
    allocator key for its own phase/run/test/repetition, its nonce must be
    scoped to its own run, and its identity kind must be the one TEST_MATRIX
    derives for that test."""
    _cross_check_key_identity(record)
    test_id = record["test_id"]
    spec = test_spec(test_id)
    if record["repetition"] > spec.max_attempts:
        raise EvidenceValidationError(
            f"{test_id}: repetition {record['repetition']} exceeds "
            f"max_attempts {spec.max_attempts}")
    if record["identity_kind"] != issuance_kind_for_test(test_id):
        raise EvidenceValidationError(
            f"{test_id}: identity_kind {record['identity_kind']!r} is not "
            "the kind TEST_MATRIX derives for that row")
    if record["issuance_nonce"].split(":")[0] != record["run_id"]:
        raise EvidenceValidationError(
            "issuance_nonce is not scoped to this run")


def _fixed_probe_keys() -> frozenset:
    """The only non-allocated keys the probe ever addresses: the two from
    captured policy (the sacrificial DeleteObject target and the
    out-of-prefix denial target), plus the empty key of a bucket-level
    ListObjectsV2 request."""
    policy = _policy()
    return frozenset({policy.sacrificial_key,
                      policy.denied_out_of_prefix_key, ""})


def _validate_request_record(record):
    _cross_check_group_matches_test(record)
    _cross_check_correlation(record)
    # A request either targets this repetition's allocator key, or one of
    # the fixed policy keys the denial rows are defined against. The empty
    # key is accepted ONLY for a request that really is a ListObjectsV2.
    if record["key"] == "":
        if ("list-type", "2") not in _query_pairs(record):
            raise EvidenceValidationError(
                "an empty key is only valid for a ListObjectsV2 request")
    elif record["key"] not in _fixed_probe_keys():
        _cross_check_key_identity(record)


def _validate_response_record(record):
    _cross_check_group_matches_test(record)
    _cross_check_correlation(record)


def _semantic_evidence_from_record(record):
    match = _grammar().allocated_key.fullmatch(record["key"])
    identity = RepetitionIdentity(
        phase=record["phase"].lower(), run_id=match.group("run"),
        test_id=record["test_id"], repetition=record["repetition"],
        key=record["key"])
    return SemanticEvidence(
        identity=identity, http_status=record["status"],
        outcome=PutOutcome(record["ambiguous_state"]),
        mutation_observed=record["mutation_observed"],
        credential_expired=record["credential_expired"])


def _derived_semantic_record_status(record) -> str:
    """The status a SEMANTIC_RECORD's facts DERIVE (VALID / INVALID_* /
    ABANDON). Raises if the facts are internally inconsistent."""
    _cross_check_group_matches_test(record)
    test_id = record["test_id"]
    if test_spec(test_id).category != "semantic":
        raise EvidenceValidationError(
            f"SEMANTIC_RECORD test {test_id!r} is not a semantic test")
    _cross_check_key_identity(record)
    try:
        evidence = _semantic_evidence_from_record(record)
        derived, abandon_reason = derive_semantic_status(evidence)
    except SafetyBarrierTripped as exc:
        raise EvidenceValidationError(f"SEMANTIC_RECORD: {exc}")
    return "ABANDON" if abandon_reason is not None else derived.value


def _validate_semantic_record(record):
    derived = _derived_semantic_record_status(record)
    if derived != record["repetition_status"]:
        raise EvidenceValidationError(
            "SEMANTIC_RECORD repetition_status does not equal the derived "
            f"status ({derived!r})")


def _race_repetition_from_record(record):
    """Reconstruct a RaceRepetition from a persisted RACE_RECORD's flat
    facts, so the result can be re-derived (BLOCKER 2)."""
    match = _grammar().allocated_key.fullmatch(record["key"])
    if not match:
        raise EvidenceValidationError("RACE_RECORD key is not allocator-shaped")
    identity = RaceIdentity(
        phase=record["phase"].lower(), run_id=match.group("run"),
        test_id=record["test_id"], repetition=record["repetition"],
        key=record["key"], setup_state=record["setup_state"])

    def writer(prefix):
        return RaceWriter(
            writer_id=record[f"{prefix}_writer_id"],
            http_status=record[f"{prefix}_http_status"],
            payload_sha256=record[f"{prefix}_payload_sha256"],
            payload_length=record[f"{prefix}_payload_length"],
            returned_etag=record[f"{prefix}_returned_etag"],
            if_match=record[f"{prefix}_if_match"],
            if_none_match=record[f"{prefix}_if_none_match"],
            barrier_generation=record[f"{prefix}_barrier_generation"],
            barrier_join_mono_ns=record[f"{prefix}_barrier_join_mono_ns"],
            send_mono_ns=record[f"{prefix}_send_mono_ns"])

    return RaceRepetition(
        identity=identity,
        shared_original_etag=record["shared_original_etag"],
        absence_confirmed=record["absence_confirmed"],
        barrier=RaceBarrierEvidence(
            generation_id=record["barrier_generation_id"],
            release_mono_ns=record["barrier_release_mono_ns"]),
        writers=(writer("w1"), writer("w2")),
        final_state=RemoteState(record["final_state"]),
        final_sha256=record["final_sha256"],
        final_length=record["final_length"],
        final_etag=record["final_etag"])


def _validate_race_record(record):
    if record["group"] != test_spec(record["test_id"]).group:
        raise EvidenceValidationError("RACE_RECORD group/test mismatch")
    try:
        repetition = _race_repetition_from_record(record)
        status, _reason, attributions = classify_race_repetition(repetition)
    except SafetyBarrierTripped as exc:
        raise EvidenceValidationError(f"RACE_RECORD: {exc}")
    # The stored derived label MUST equal what the facts derive.
    if record["race_repetition_status"] != status.value:
        raise EvidenceValidationError(
            "RACE_RECORD race_repetition_status does not equal the derived "
            f"status ({status.value!r})")
    losers = [a for a in attributions if a is not None]
    expected_attr = losers[0].value if losers else None
    if record["race_attribution"] != expected_attr:
        raise EvidenceValidationError(
            "RACE_RECORD race_attribution does not equal the derived "
            f"attribution ({expected_attr!r})")


def validate_record(record, secrets: Iterable[str]) -> str:
    """Validate one persisted evidence record by its declared kind.

    Returns the record_kind. `secrets` must be an explicit tuple — the
    persistence boundary never defaults it (HIGH 3).
    """
    if type(record) is not dict:
        raise EvidenceValidationError("record must be exactly dict")
    kinds = _taxonomy().kinds
    kind = record.get("record_kind")
    if kind not in kinds:
        raise EvidenceValidationError(
            f"record_kind {kind!r} is not one of {sorted(kinds)}")
    required, allowed, cross = {
        "REQUEST_RECORD": (_REQUEST_REQUIRED, _REQUEST_ALLOWED,
                           _validate_request_record),
        "RESPONSE_RECORD": (_RESPONSE_REQUIRED, _RESPONSE_ALLOWED,
                            _validate_response_record),
        "SEMANTIC_RECORD": (_SEMANTIC_REQUIRED, _SEMANTIC_ALLOWED,
                            _validate_semantic_record),
        "RACE_RECORD": (_RACE_REQUIRED, _RACE_ALLOWED, _validate_race_record),
        "TEST_RESULT_RECORD": (_TEST_RESULT_REQUIRED, _TEST_RESULT_ALLOWED,
                               _validate_test_result_record),
        "ISSUANCE_RECORD": (_ISSUANCE_REQUIRED, _ISSUANCE_ALLOWED,
                            _validate_issuance_record),
    }[kind]
    _require_and_restrict(record, required, allowed, kind)
    # Per-field validation (types, shapes, secret scan, denylist).
    validate_evidence_record(record, secrets)
    _cross_check_raw_hex_pairs(record)
    if cross is not None:
        cross(record)
    return kind


# ── Derived run summary (BLOCKER 3) ──────────────────────────────────────
#
# The RUN_SUMMARY verdict is DERIVED from the acceptance gates. There is
# no path to persist a caller-chosen verdict, and a PASS is impossible
# unless every required matrix test is complete and every gate says PASS.

SUMMARY_VERDICTS = frozenset({"PASS", "FAIL", "ABANDON", "INCOMPLETE"})


class MatrixCompletion:
    """Per-test completion counters DERIVED FROM PERSISTED RECORDS.

    There is deliberately NO public bare-counter API (BLOCKER 1). The only
    way to advance a counter is `count_persisted_test_result`, which takes a
    fully validated TEST_RESULT_RECORD — so every counted repetition is
    backed by a real evidence file. Semantic and race completion come from
    their own aggregators, never from here.

    A row is complete only when valid >= required, attempts <= max, and
    production-size repetitions >= the matrix requirement, with the
    invariant 0 <= production_size <= valid <= attempts <= max_attempts.
    """

    def __init__(self):
        # test_id -> {repetition: (valid, production_size)}
        self._by_test = {}

    def count_persisted_test_result(self, record) -> None:
        """Advance counters from ONE validated TEST_RESULT_RECORD."""
        if record.get("record_kind") != "TEST_RESULT_RECORD":
            raise EvidenceValidationError(
                "MatrixCompletion only counts TEST_RESULT_RECORDs")
        test_id = record["test_id"]
        spec = test_spec(test_id)
        repetition = record["repetition"]
        reps = self._by_test.setdefault(test_id, {})
        if repetition in reps:
            raise EvidenceValidationError(
                f"{test_id}: duplicate TEST_RESULT_RECORD for repetition "
                f"{repetition}")
        reps[repetition] = (bool(record["derived_valid"]),
                            bool(record["derived_production_size"]))
        if len(reps) > spec.max_attempts:
            raise EvidenceValidationError(
                f"{test_id}: {len(reps)} attempts exceeds max_attempts "
                f"{spec.max_attempts}")

    def counts(self, test_id) -> tuple:
        reps = self._by_test.get(test_id, {})
        attempts = len(reps)
        valid = sum(1 for v, _ in reps.values() if v)
        production = sum(1 for v, p in reps.values() if v and p)
        # The invariant holds by construction, but assert it so a future
        # refactor cannot quietly break it.
        spec = test_spec(test_id)
        if not (0 <= production <= valid <= attempts <= spec.max_attempts):
            raise EvidenceValidationError(
                f"{test_id}: derived counts violate the completion invariant")
        return valid, attempts, production

    def is_complete(self, test_id) -> bool:
        spec = test_spec(test_id)
        if test_id not in self._by_test:
            return False
        valid, attempts, production = self.counts(test_id)
        return (valid >= spec.required_repetitions
                and attempts <= spec.max_attempts
                and production >= spec.production_size_repetitions)


def derive_run_summary(*, phase, semantic, race, ledger,
                       completion=None) -> dict:
    """Build the RUN_SUMMARY dict with a DERIVED verdict.

    PASS requires ALL of: no ABANDON anywhere; the ledger not poisoned;
    EVERY ledger reservation resolved (no open normal PUT reservation and no
    open same-key race pair); every semantic and race test PASS via its
    aggregator; and every remaining required matrix row complete from
    record-derived counters.

    OPEN RESERVATIONS ARE AUTHORITATIVE HERE (Codex round-3 BLOCKER 1). An
    unresolved reservation means the probe never established whether a body
    it may have written committed, so it cannot account for its own writes
    and must never report PASS. This is enforced in THIS function — the
    authoritative, disk-derived summary layer — not by a caller patching the
    returned dict afterwards. The counts are read from the ledger itself and
    persisted in the summary, so a later reader can re-check them.

    NOTE: `EvidenceWriter.finalize` calls this with state RECONSTRUCTED FROM
    DISK (BLOCKER 2). The in-memory run state never authorizes PASS.
    """
    if type(phase) is not str or phase not in _grammar().phases:
        raise EvidenceValidationError("summary phase must be 'P' or 'T'")
    if type(semantic) is not SemanticAggregator:
        raise EvidenceValidationError("semantic must be a SemanticAggregator")
    if type(race) is not RaceAggregator:
        raise EvidenceValidationError("race must be a RaceAggregator")
    if type(ledger) is not ResourceLedger:
        raise EvidenceValidationError("ledger must be a ResourceLedger")
    completion = completion if completion is not None else MatrixCompletion()
    if type(completion) is not MatrixCompletion:
        raise EvidenceValidationError("completion must be a MatrixCompletion")

    matrix = _policy().matrix
    abandon = False
    all_complete = True
    valid_reps = 0
    tests_passed = 0

    sem_verdict, _ = semantic.overall()
    race_verdict_overall, _ = race.overall()
    if sem_verdict is Verdict.ABANDON or race_verdict_overall is Verdict.ABANDON:
        abandon = True

    for spec in matrix:
        if spec.category == "semantic":
            v, _ = semantic.verdict(spec.id)
            complete = v is Verdict.PASS
            valid_reps += len(semantic.valid(spec.id))
        elif spec.category == "race":
            v, _ = race.verdict(spec.id)
            complete = v is Verdict.PASS
            valid_reps += race.valid(spec.id)
        else:
            complete = completion.is_complete(spec.id)
            valid_reps += completion.counts(spec.id)[0]
        if complete:
            tests_passed += 1
        else:
            all_complete = False

    if ledger.poisoned:
        abandon = True

    snap = ledger.snapshot()
    # AUTHORITATIVE: any unresolved reservation is terminal, exactly like a
    # poisoned ledger. Read straight from the ledger — never from a caller.
    open_puts, open_pairs = ledger.open_reservation_counts()
    _exact_int(open_puts, "open_put_reservations", minimum=0)
    _exact_int(open_pairs, "open_race_pairs", minimum=0)
    if open_puts or open_pairs:
        abandon = True

    if abandon:
        verdict = "ABANDON"
    elif all_complete:
        verdict = "PASS"
    else:
        verdict = "INCOMPLETE"

    return {
        "verdict": verdict,
        "phase": phase,
        "tests_total": len(matrix),
        "tests_passed": tests_passed,
        "tests_failed": len(matrix) - tests_passed,
        "valid_repetitions": valid_reps,
        "abandon_triggered": abandon,
        "ledger_poisoned": ledger.poisoned,
        "put_operation_count": snap["put_operation_count"],
        "production_size_puts": snap["production_size_puts"],
        "get_head_count": snap["get_head_count"],
        "object_count": snap["object_count"],
        "uploaded_bytes": snap["uploaded_bytes"],
        "peak_storage_bytes": snap["peak_storage_bytes"],
        # Persisted so the authoritative summary carries its own proof.
        "open_put_reservations": open_puts,
        "open_race_pairs": open_pairs,
    }


_SUMMARY_FIELD_VALIDATORS = {
    "verdict": _v_str(max_len=16, choices=SUMMARY_VERDICTS),
    "phase": _v_str(max_len=1, choices=_grammar().phases),
    "tests_total": _v_int(),
    "tests_passed": _v_int(),
    "tests_failed": _v_int(),
    "valid_repetitions": _v_int(),
    "abandon_triggered": _v_bool(),
    "ledger_poisoned": _v_bool(),
    "put_operation_count": _v_int(),
    "production_size_puts": _v_int(),
    "get_head_count": _v_int(),
    "object_count": _v_int(),
    "uploaded_bytes": _v_int(),
    "peak_storage_bytes": _v_int(),
    # Exact nonnegative integers; REQUIRED (a missing count is a malformed
    # summary, not an implicit zero).
    "open_put_reservations": _v_int(minimum=0),
    "open_race_pairs": _v_int(minimum=0),
}
SUMMARY_FIELDS = frozenset(_SUMMARY_FIELD_VALIDATORS)


def validate_summary(summary, secrets: Iterable[str]) -> None:
    """Shape-validate a DERIVED summary. `secrets` is explicit (HIGH 3).

    Also enforces the internal consistency a PASS claims: a PASS summary may
    not be poisoned, may not be flagged abandon, and may not carry a nonzero
    open-reservation count (Codex round-3 BLOCKER 1). A hand-edited summary
    asserting PASS beside an open reservation is refused here.
    """
    if type(summary) is not dict:
        raise EvidenceValidationError("summary must be exactly dict")
    missing = SUMMARY_FIELDS - set(summary)
    if missing:
        raise EvidenceValidationError(
            f"summary missing derived fields {sorted(missing)}")
    for key, value in summary.items():
        if type(key) is not str or key not in _SUMMARY_FIELD_VALIDATORS:
            raise EvidenceValidationError(
                f"summary field {key!r} is not in the fixed schema")
        _SUMMARY_FIELD_VALIDATORS[key](value, key)
    if summary["verdict"] == "PASS":
        if summary["open_put_reservations"] or summary["open_race_pairs"]:
            raise EvidenceValidationError(
                "a PASS summary cannot carry unresolved reservations "
                f"({summary['open_put_reservations']} puts, "
                f"{summary['open_race_pairs']} race pairs)")
        if summary["ledger_poisoned"] or summary["abandon_triggered"]:
            raise EvidenceValidationError(
                "a PASS summary cannot be poisoned or abandon-triggered")
    serialized = json.dumps(summary, sort_keys=True)
    for secret in secrets:
        if secret and secret in serialized:
            raise EvidenceValidationError("summary contains secret material")
    assert_no_denied_names(serialized)


def hex_of(text):
    """Hex of the UTF-8 bytes, so quoting and whitespace survive every JSON
    round trip, editor and downstream tool."""
    if text is None:
        return None
    _exact(text, str, "text")
    return binascii.hexlify(text.encode("utf-8")).decode("ascii")


# ─────────────────────────────────────────────────────────────────────────
# Evidence writer
# ─────────────────────────────────────────────────────────────────────────

def default_evidence_root() -> str:
    return os.path.join(os.path.expanduser("~"), ".local", "state",
                        "bible-pal")


def _ensure_private_dir(path: str) -> None:
    """Create-or-validate one directory, conservatively.

    A pre-existing directory is NEVER chmodded: it must already be a real
    directory (not a symlink), owned by the current uid, with no group or
    other access — otherwise the writer refuses.
    """
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        os.mkdir(path, 0o700)
        st = os.lstat(path)
    if stat.S_ISLNK(st.st_mode):
        raise SafetyBarrierTripped(f"evidence path {path!r} is a symlink")
    if not stat.S_ISDIR(st.st_mode):
        raise SafetyBarrierTripped(f"evidence path {path!r} is not a directory")
    if hasattr(os, "getuid") and st.st_uid != os.getuid():
        raise SafetyBarrierTripped(
            f"evidence path {path!r} is not owned by the current user")
    if stat.S_IMODE(st.st_mode) & 0o077:
        raise SafetyBarrierTripped(
            f"evidence path {path!r} is group/other accessible — refusing to "
            "use it (and refusing to silently chmod it)")


def _fsync_directory(path: str) -> None:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


# ─────────────────────────────────────────────────────────────────────────
# Disk-authoritative acceptance reconstruction (BLOCKER 2)
#
# The persisted, validated evidence files are the FINAL SOURCE OF TRUTH at
# finalization. In-memory run state exists only for fail-fast checks,
# issuance control and transaction coordination — it never authorizes PASS.
# ─────────────────────────────────────────────────────────────────────────

#: DISPLAY ONLY — enforcement reads the closure above.
MANIFEST_FILENAME = _evidence_layout()[0]

#: DISPLAY ONLY. Enforcement reads _policy().max_evidence_file_bytes, so
#: rebinding this name changes nothing (Codex HIGH).
MAX_EVIDENCE_FILE_BYTES = _policy().max_evidence_file_bytes


class StrictJsonRejected(SafetyBarrierTripped):
    """Evidence JSON that a plain json.loads would silently accept."""


def _reject_constant(name):
    raise StrictJsonRejected(
        f"non-standard JSON constant {name!r} in evidence")


def _no_duplicate_keys(pairs):
    """object_pairs_hook that refuses duplicate object names (Codex LOW).

    Plain json.loads keeps the LAST duplicate, so `{"status":200,
    "status":412}` would parse as 412 while a reviewer reading the bytes
    sees 200. Refuse the ambiguity instead of picking a winner.
    """
    seen = set()
    for name, _value in pairs:
        if name in seen:
            raise StrictJsonRejected(f"duplicate JSON object key {name!r}")
        seen.add(name)
    return dict(pairs)


def strict_json_loads(text):
    """json.loads with duplicate keys, NaN and +/-Infinity refused."""
    return json.loads(text, object_pairs_hook=_no_duplicate_keys,
                      parse_constant=_reject_constant)

#: DISPLAY ONLY: kind -> the directory each kind's files must live in. A
#: record's path is DERIVED from its own identity, so an unexpected path, a
#: duplicate identity under a second name, or a stray directory is
#: detectable.
_RECORD_KIND_DIRS = dict(_evidence_layout()[1])


def expected_relative_for_record(record) -> str:
    """The ONE canonical relative path for a validated record.

    Because the path is a pure function of the record's identity, disk
    reconstruction can verify that each file sits exactly where its content
    says it should — so an extra copy under another name, or a file moved
    into the wrong directory, fails closed.
    """
    kind = record["record_kind"]
    directory = _record_kind_dir(kind)
    if kind in ("REQUEST_RECORD", "RESPONSE_RECORD"):
        corr = parse_correlation(record["correlation_id"])
        leaf = (f"{corr.phase}_{corr.run_id}_{corr.test_id}_"
                f"{corr.repetition:04d}_{corr.sequence:06d}.json")
        return f"{directory}/{leaf}"
    return (f"{directory}/{record['test_id'].lower()}/"
            f"{record['repetition']:04d}.json")


class ReconstructedRun(NamedTuple):
    """Acceptance state rebuilt purely from physical evidence files."""

    semantic: SemanticAggregator
    race: RaceAggregator
    completion: MatrixCompletion
    files: dict                # relative path -> sha256 of the exact bytes
    identities: frozenset      # (kind, test_id, repetition) tuples
    correlations: dict         # kind -> {correlation tuple}


def _iter_evidence_files(run_dir):
    """Enumerate the authoritative evidence files beneath `run_dir`.

    Refuses symlinks, non-regular files, unexpected top-level entries and
    unexpected directory structures; the manifest is skipped.
    """
    max_bytes = _policy().max_evidence_file_bytes
    found = []
    for entry in sorted(os.listdir(run_dir)):
        path = os.path.join(run_dir, entry)
        st = os.lstat(path)
        if entry == _manifest_filename():
            if not stat.S_ISREG(st.st_mode):
                raise SafetyBarrierTripped("manifest is not a regular file")
            continue
        if stat.S_ISLNK(st.st_mode):
            raise SafetyBarrierTripped(
                f"evidence entry {entry!r} is a symlink")
        if not stat.S_ISDIR(st.st_mode):
            raise SafetyBarrierTripped(
                f"unexpected non-directory evidence entry {entry!r}")
        if entry not in _record_kind_dirs():
            raise SafetyBarrierTripped(
                f"unexpected evidence directory {entry!r}")
        for dirpath, dirnames, filenames in os.walk(path):
            dirnames.sort()
            for name in sorted(dirnames):
                sub = os.path.join(dirpath, name)
                if os.path.islink(sub):
                    raise SafetyBarrierTripped(
                        f"evidence subdirectory {name!r} is a symlink")
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                sub_st = os.lstat(full)
                if stat.S_ISLNK(sub_st.st_mode):
                    raise SafetyBarrierTripped(
                        f"evidence file {name!r} is a symlink")
                if not stat.S_ISREG(sub_st.st_mode):
                    raise SafetyBarrierTripped(
                        f"evidence file {name!r} is not a regular file")
                if not name.endswith(".json"):
                    raise SafetyBarrierTripped(
                        f"unexpected non-JSON evidence file {name!r}")
                if sub_st.st_size > max_bytes:
                    raise SafetyBarrierTripped(
                        f"evidence file {name!r} exceeds the size bound")
                found.append(os.path.relpath(full, run_dir))
    return found


def reconstruct_run_from_disk(run_dir, *, phase, run_id, secrets,
                             issued_registry,
                             recorded_digests=None) -> ReconstructedRun:
    """Rebuild ALL acceptance state from the physical evidence files.

    Three passes, so nothing depends on directory iteration order:

      1. READ — every file is reopened, size-bounded, hashed, strictly
         parsed (duplicate keys / NaN / Infinity refused), fully
         re-validated by the current typed validator, required to sit at
         its own canonical path, and scoped to this phase and run.
      2. LINK — every acceptance record must be backed by exactly one
         physical ISSUANCE_RECORD whose nonce, key, test, repetition and
         identity kind all match, with no nonce used twice; every
         TEST_RESULT evidence reference must resolve to a physical
         RESPONSE_RECORD *and* its physical REQUEST_RECORD; every response
         must have a request.
      3. DERIVE — the support-row result is RECOMPUTED from those physical
         request/response bytes and must equal what the record stored, and
         only then is anything folded into fresh aggregators.

    When `recorded_digests` is supplied, each file's digest must match it
    and the two sets must be exactly equal — so a deleted, altered, extra
    or unmanifested file fails closed.

    ISSUANCE IS THE ONE EXCEPTION to "disk is the source of truth" (Codex
    BLOCKER 1). A caller-written JSON file cannot prove that the allocator
    minted an identity, so `issued_registry` — the allocator's own
    `nonce -> identity` map — is a MANDATORY keyword argument with NO
    default, and every physical ISSUANCE_RECORD must correspond EXACTLY to
    a registry entry and vice versa. There is no branch that skips that
    check: this function cannot be called at all without a registry, so
    registry authentication is not optional.

    Structural auditing without a registry lives in
    `inspect_evidence_bundle_structure`, which is deliberately incapable of
    returning any acceptance-capable object.
    """
    _exact_str(run_dir, "run_dir", max_len=1024)
    # Mandatory, and checked BEFORE anything is read. An acceptance-capable
    # reconstruction without an issuer authority is refused outright.
    if type(issued_registry) is not dict:
        raise SafetyBarrierTripped(
            "issued_registry must be exactly dict — acceptance "
            "reconstruction requires the allocator's issuance registry")
    if type(phase) is not str or phase not in _grammar().phases:
        raise SafetyBarrierTripped("phase must be 'P' or 'T'")
    if type(run_id) is not str or not _grammar().run_id.fullmatch(run_id):
        raise SafetyBarrierTripped("run_id refused")

    max_bytes = _policy().max_evidence_file_bytes
    files = {}
    by_kind = {kind: {} for kind in _taxonomy().kinds}  # relative -> record

    # ── pass 1: read, validate, scope ───────────────────────────────────
    for relative in _iter_evidence_files(run_dir):
        path = os.path.join(run_dir, relative)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                raise SafetyBarrierTripped(
                    f"{relative}: not a regular file at read time")
            if st.st_size > max_bytes:
                raise SafetyBarrierTripped(f"{relative}: exceeds size bound")
            raw = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw += chunk
                if len(raw) > max_bytes:
                    raise SafetyBarrierTripped(
                        f"{relative}: exceeds size bound while reading")
        finally:
            os.close(fd)

        digest = hashlib.sha256(raw).hexdigest()
        files[relative] = digest
        if recorded_digests is not None:
            expected = recorded_digests.get(relative)
            if expected is None:
                raise SafetyBarrierTripped(
                    f"{relative}: physical evidence file is not in the "
                    "manifest")
            if expected != digest:
                raise SafetyBarrierTripped(
                    f"{relative}: on-disk bytes do not match the recorded "
                    "digest")

        try:
            record = strict_json_loads(raw.decode("utf-8"))
        except StrictJsonRejected as exc:
            raise SafetyBarrierTripped(f"{relative}: {exc}") from None
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise SafetyBarrierTripped(f"{relative}: not strict JSON")
        if type(record) is not dict:
            raise SafetyBarrierTripped(f"{relative}: root is not an object")

        kind = validate_record(record, secrets)
        if expected_relative_for_record(record) != relative:
            raise SafetyBarrierTripped(
                f"{relative}: record identity does not match its path")
        if record["phase"] != phase:
            raise SafetyBarrierTripped(f"{relative}: phase is not this run's")
        record_run = record.get("run_id")
        if record_run is not None and record_run != run_id:
            raise SafetyBarrierTripped(f"{relative}: run_id is not this run's")
        key = record.get("key")
        # The two fixed policy keys (sacrificial / out-of-prefix denial)
        # are not allocator-shaped; every other key must be, and must
        # belong to this run.
        if key is not None and key not in _fixed_probe_keys():
            match = _grammar().allocated_key.fullmatch(key)
            if match is None:
                raise SafetyBarrierTripped(
                    f"{relative}: key is not an allocated probe key")
            if match.group("run") != run_id:
                raise SafetyBarrierTripped(
                    f"{relative}: key belongs to another run")
        by_kind[kind][relative] = record

    # ── pass 2: link issuance and evidence references ───────────────────
    issuance_by_identity = {}
    issuance_by_nonce = {}
    for relative, record in by_kind["ISSUANCE_RECORD"].items():
        identity = (record["test_id"], record["repetition"])
        if identity in issuance_by_identity:
            raise SafetyBarrierTripped(
                f"{relative}: duplicate ISSUANCE_RECORD for {identity}")
        nonce = record["issuance_nonce"]
        if nonce in issuance_by_nonce:
            raise SafetyBarrierTripped(
                f"{relative}: issuance nonce {nonce!r} was issued twice")
        issuance_by_identity[identity] = record
        issuance_by_nonce[nonce] = record

    # UNCONDITIONAL: exact registry <-> physical issuance equality.
    registry_nonces = set(issued_registry)
    physical_nonces = set(issuance_by_nonce)
    if physical_nonces != registry_nonces:
        raise SafetyBarrierTripped(
            "physical issuance disagrees with the allocator registry: "
            f"only-on-disk={sorted(physical_nonces - registry_nonces)} "
            f"only-in-registry={sorted(registry_nonces - physical_nonces)}")
    for nonce, record in issuance_by_nonce.items():
        identity = issued_registry[nonce]
        for field in ("test_id", "repetition", "key"):
            if getattr(identity, field) != record[field]:
                raise SafetyBarrierTripped(
                    f"issuance {nonce!r}: {field} does not match what "
                    "the allocator issued")
        if identity.run_id != run_id or identity.phase != phase.lower():
            raise SafetyBarrierTripped(
                f"issuance {nonce!r}: allocator identity is from another "
                "run or phase")

    requests = {}
    for relative, record in by_kind["REQUEST_RECORD"].items():
        corr = record["correlation_id"]
        if corr in requests:
            raise SafetyBarrierTripped(
                f"{relative}: duplicate REQUEST_RECORD correlation")
        requests[corr] = record
    responses = {}
    for relative, record in by_kind["RESPONSE_RECORD"].items():
        corr = record["correlation_id"]
        if corr in responses:
            raise SafetyBarrierTripped(
                f"{relative}: duplicate RESPONSE_RECORD correlation")
        if corr not in requests:
            raise SafetyBarrierTripped(
                f"{relative}: orphan RESPONSE_RECORD — no physical request")
        if requests[corr]["test_id"] != record["test_id"]:
            raise SafetyBarrierTripped(
                f"{relative}: response test does not match its request")
        responses[corr] = record

    consumed_nonces = set()
    identities = {("ISSUANCE_RECORD", r["test_id"], r["repetition"])
                  for r in by_kind["ISSUANCE_RECORD"].values()}
    for kind in sorted(_taxonomy().acceptance_kinds):
        for relative, record in by_kind[kind].items():
            nonce = record["issuance_nonce"]
            issuance = issuance_by_nonce.get(nonce)
            if issuance is None:
                raise SafetyBarrierTripped(
                    f"{relative}: no physical ISSUANCE_RECORD for nonce "
                    f"{nonce!r}")
            if nonce in consumed_nonces:
                raise SafetyBarrierTripped(
                    f"{relative}: issuance nonce {nonce!r} backs more than "
                    "one acceptance record")
            consumed_nonces.add(nonce)
            for field in ("phase", "run_id", "test_id", "repetition", "key"):
                if issuance[field] != record[field]:
                    raise SafetyBarrierTripped(
                        f"{relative}: issuance {field} does not match the "
                        "acceptance record")
            if issuance["identity_kind"] != issuance_kind_for_record_kind(
                    kind):
                raise SafetyBarrierTripped(
                    f"{relative}: issuance identity_kind "
                    f"{issuance['identity_kind']!r} cannot back a {kind}")
            identities.add((kind, record["test_id"], record["repetition"]))

    # ── pass 3: recompute every support result, then aggregate ──────────
    semantic = SemanticAggregator()
    race = RaceAggregator()
    completion = MatrixCompletion()

    for record in by_kind["SEMANTIC_RECORD"].values():
        semantic.record(_semantic_evidence_from_record(record))
    for record in by_kind["RACE_RECORD"].values():
        race.record(_race_repetition_from_record(record))
    for relative, record in by_kind["TEST_RESULT_RECORD"].items():
        ref = record["evidence_refs"][0]
        response = responses.get(ref)
        if response is None:
            raise SafetyBarrierTripped(
                f"{relative}: evidence ref {ref!r} has no physical "
                "RESPONSE_RECORD")
        request = requests[ref]      # pass 2 proved the request exists
        if request["test_id"] != record["test_id"]:
            raise SafetyBarrierTripped(
                f"{relative}: evidence belongs to another test")
        siblings = [other for correlation, other in sorted(requests.items())
                    if correlation != ref
                    and other["test_id"] == record["test_id"]
                    and other["repetition"] == record["repetition"]]
        sibling_resps = [other for correlation, other
                         in sorted(responses.items())
                         if correlation != ref
                         and other["test_id"] == record["test_id"]
                         and other["repetition"] == record["repetition"]]
        derived = derive_test_result(test_spec(record["test_id"]),
                                     request, response,
                                     sibling_requests=siblings,
                                     sibling_responses=sibling_resps)
        if (record["outcome_classification"] != derived.outcome
                or record["derived_valid"] is not derived.valid
                or record["derived_production_size"]
                is not derived.production_size):
            raise SafetyBarrierTripped(
                f"{relative}: stored result {record['outcome_classification']!r}"
                f"/{record['derived_valid']}/"
                f"{record['derived_production_size']} does not match the "
                f"result derived from its evidence ({derived.outcome}/"
                f"{derived.valid}/{derived.production_size})")
        completion.count_persisted_test_result(record)

    if recorded_digests is not None:
        missing = set(recorded_digests) - set(files)
        if missing:
            raise SafetyBarrierTripped(
                f"manifested evidence files missing from disk: "
                f"{sorted(missing)}")

    correlations = {
        "REQUEST_RECORD": {parse_correlation(c) for c in requests},
        "RESPONSE_RECORD": {parse_correlation(c) for c in responses},
    }
    return ReconstructedRun(
        semantic=semantic, race=race, completion=completion, files=files,
        identities=frozenset(identities), correlations=correlations)


def inspect_evidence_bundle_structure(run_dir) -> dict:
    """Registry-free STRUCTURAL audit of an evidence bundle.

    Deliberately incapable of acceptance (Codex BLOCKER 1): it builds no
    SemanticAggregator, no RaceAggregator and no MatrixCompletion, derives
    no verdict, and returns only counts and relative paths. Anything that
    could contribute to PASS must go through
    `reconstruct_run_from_disk`, which requires the allocator registry.
    """
    _exact_str(run_dir, "run_dir", max_len=1024)
    counts = {}
    relatives = _iter_evidence_files(run_dir)
    for relative in relatives:
        directory = relative.split("/", 1)[0]
        counts[directory] = counts.get(directory, 0) + 1
    return {"file_count": len(relatives),
            "files": tuple(relatives),
            "counts_by_directory": dict(sorted(counts.items()))}


class EvidenceWriter:
    """0700 directories, 0600 files, umask 077, O_EXCL|O_NOFOLLOW, full
    write loops, fsync.

    The integrity index is EXTERNALLY ANCHORED, not tamper-proof: the same
    user and process that wrote the bundle can rewrite both it and the
    anchor. Its value is detecting accidental corruption, truncation or a
    partial copy, and giving a reviewer a fixed hash to work against.
    """


    #: The allocator run id constrains what nonces this writer accepts, so
    #: it must be a valid allocator run id too.
    def __init__(self, root, run_id, secrets, *, phase="T"):
        """`secrets` is REQUIRED (HIGH 3): the persistence boundary never
        defaults it. Pass an exact tuple of known secret strings. Tests
        that legitimately have none use `EvidenceWriter.for_testing(...)`.

        In-memory writer state is deliberately NOT an acceptance authority
        (BLOCKER 2). It exists only for fail-fast checks during the run,
        issuance control and transaction coordination. At finalization the
        PHYSICAL VALIDATED PERSISTED RECORDS are the source of truth: every
        aggregator and completion counter is rebuilt from the files on disk
        and cross-checked for exact set equality against this index. There
        is no separate MatrixCompletion here — it would be a second,
        redundant authority.
        """
        _exact_str(root, "root", max_len=512)
        if type(run_id) is not str \
                or not _grammar().run_id_file.fullmatch(run_id):
            raise SafetyBarrierTripped(f"unsafe run id {run_id!r}")
        if type(secrets) not in (tuple, list):
            raise SafetyBarrierTripped(
                "secrets must be an explicit tuple/list of strings")
        for secret in secrets:
            if type(secret) is not str:
                raise SafetyBarrierTripped("each secret must be exactly str")
        if type(phase) is not str or phase not in _grammar().phases:
            raise SafetyBarrierTripped("phase must be 'P' or 'T'")
        assert_no_denied_names(root, run_id)
        self.root = os.path.abspath(root)
        self.run_id = run_id
        self._phase = phase
        self._secrets = tuple(secrets)
        self._files = {}
        self._lock = threading.Lock()

        # Issuance control (authoritative — it gates what may be written).
        self._allocator = ProbeKeyAllocator(run_id)
        self._used_nonces = set()
        # Resource caps and poisoning. Authoritative for ABANDON only: it
        # can force a worse verdict, never a better one.
        self.ledger = ResourceLedger()
        # FAIL-FAST ONLY. These reject invalid evidence at write time; they
        # are discarded at finalization in favour of the on-disk rebuild.
        self._semantic = SemanticAggregator()
        self._race = RaceAggregator()
        # Transaction coordination / duplicate refusal.
        # (kind, test_id, repetition) -> relative file path.
        self._persisted = {}
        self._requests = {}          # correlation_id -> test_id
        self._responses = {}         # correlation_id -> observed status

        previous_umask = os.umask(0o077)
        try:
            _ensure_private_dir(self.root)
            self.evidence_dir = os.path.join(self.root, "cas-probe-evidence")
            _ensure_private_dir(self.evidence_dir)
            self.anchor_dir = os.path.join(self.root, "cas-probe-anchors")
            _ensure_private_dir(self.anchor_dir)
            self.run_dir = os.path.join(self.evidence_dir, run_id)
            os.mkdir(self.run_dir, 0o700)   # existing run id is a hard error
            _ensure_private_dir(self.run_dir)
        finally:
            os.umask(previous_umask)

    def _write_new_private_file(self, path: str, payload: bytes) -> None:
        previous_umask = os.umask(0o077)
        try:
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            flags |= getattr(os, "O_NOFOLLOW", 0)
            fd = os.open(path, flags, 0o600)
            try:
                view = memoryview(payload)
                while view:
                    written = os.write(fd, view)
                    if written <= 0:
                        raise SafetyBarrierTripped("os.write made no progress")
                    view = view[written:]
                os.fsync(fd)
            finally:
                os.close(fd)
        finally:
            os.umask(previous_umask)
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode) or stat.S_IMODE(st.st_mode) & 0o077:
            raise SafetyBarrierTripped(
                f"evidence file {path!r} did not end up a private regular file")

    def _write_bytes(self, relative: str, payload: bytes) -> str:
        if type(relative) is not str \
                or not _grammar().evidence_relative.fullmatch(relative) \
                or ".." in relative.split("/") or relative.startswith("/"):
            raise SafetyBarrierTripped(f"unsafe evidence path {relative!r}")
        path = os.path.join(self.run_dir, relative)
        parent = os.path.dirname(path)
        components = []
        current = parent
        while current != self.run_dir:
            components.append(current)
            current = os.path.dirname(current)
        for component in reversed(components):
            _ensure_private_dir(component)
        self._write_new_private_file(path, payload)
        self._files[relative] = hashlib.sha256(payload).hexdigest()
        return path

    @classmethod
    def for_testing(cls, root, run_id, *, phase="T"):
        """TESTS ONLY: an EvidenceWriter with an explicitly empty secret
        set. Named so it is never mistaken for the live constructor."""
        return cls(root, run_id, secrets=(), phase=phase)

    # ── Identity issuance (HIGH 3) ───────────────────────────────────────

    def allocate_semantic(self, test_id, repetition) -> IssuedIdentity:
        """Allocate a repetition identity AND persist its ISSUANCE_RECORD.

        The physical issuance file is what makes the later acceptance
        record legitimate at reconstruction (Codex BLOCKER 3): no issuance
        file, no acceptance. It is written here, at allocation, so it
        cannot be back-filled to bless evidence that was never issued.
        """
        with self._lock:
            issued = self._allocator.allocate(
                phase=self._phase.lower(), test_id=test_id,
                repetition=repetition)
            self._persist_allocator_issuance(issued)
            return issued

    def allocate_race(self, test_id, repetition) -> IssuedIdentity:
        with self._lock:
            issued = self._allocator.allocate_race(
                phase=self._phase.lower(), test_id=test_id,
                repetition=repetition)
            self._persist_allocator_issuance(issued)
            return issued

    def _persist_allocator_issuance(self, issued) -> str:
        """The ONLY path that may write an ISSUANCE_RECORD (BLOCKER 1).

        It accepts no record dict, no nonce and no key from a caller: it
        takes an IssuedIdentity, resolves it against THIS writer's
        allocator registry, and builds the record itself from the resolved
        identity. A fabricated IssuedIdentity — one the registry does not
        contain — cannot get through, so there is no way to mint issuance
        without the allocator having really minted it.
        """
        if type(issued) is not IssuedIdentity:
            raise SafetyBarrierTripped(
                "issuance persistence requires an IssuedIdentity capability")
        # Raises unless the allocator registry holds this exact nonce ->
        # byte-identical identity.
        identity = self._allocator.resolve(issued)
        if identity is not issued.identity and identity != issued.identity:
            raise SafetyBarrierTripped("issuance identity was substituted")
        if identity.run_id != self.run_id \
                or identity.phase != self._phase.lower():
            raise SafetyBarrierTripped(
                "issuance identity does not belong to this writer's run")
        if identity.key != expected_key_for(
                phase=identity.phase, run_id=identity.run_id,
                test_id=identity.test_id, repetition=identity.repetition):
            raise SafetyBarrierTripped("issuance key is not canonical")
        record = {
            "record_kind": "ISSUANCE_RECORD", "phase": self._phase,
            "run_id": self.run_id, "test_id": identity.test_id,
            "repetition": identity.repetition, "key": identity.key,
            "issuance_nonce": issued.nonce,
            "identity_kind": issuance_kind_for_test(identity.test_id)}
        return self._write_typed_record(
            "ISSUANCE_RECORD", identity.test_id, identity.repetition, record)

    def _consume(self, issued):
        """Resolve an issuance capability and mark it used exactly once."""
        identity = self._allocator.resolve(issued)
        if issued.nonce in self._used_nonces:
            raise SafetyBarrierTripped(
                "issuance nonce was already used for a persisted record")
        if ("ISSUANCE_RECORD", identity.test_id, identity.repetition) \
                not in self._persisted:
            raise SafetyBarrierTripped(
                "no persisted ISSUANCE_RECORD backs this identity")
        return identity

    def _assert_this_run(self, record) -> None:
        """Evidence from another phase or run may never enter this bundle.

        Finalization enforces the same rule against the files on disk; this
        is the fail-fast copy so a mixed-run write is refused at the door.
        """
        if record["phase"] != self._phase:
            raise SafetyBarrierTripped(
                f"record phase {record['phase']!r} is not this run's phase")
        if record["run_id"] != self.run_id:
            raise SafetyBarrierTripped(
                f"record run_id {record['run_id']!r} is not this run")

    def _persist_typed(self, kind, test_id, repetition, record):
        """Serialise ONE validated NON-ISSUANCE typed record.

        ISSUANCE_RECORD is refused here unconditionally (Codex BLOCKER 1):
        issuance authenticity needs an issuer, and only
        `_persist_allocator_issuance` — which resolves a real capability
        against the allocator registry — may write one.
        """
        if kind == "ISSUANCE_RECORD":
            raise SafetyBarrierTripped(
                "ISSUANCE_RECORD may only be written by the allocator-backed "
                "issuance path")
        return self._write_typed_record(kind, test_id, repetition, record)

    def _write_typed_record(self, kind, test_id, repetition, record):
        """Byte-level serialisation of one validated typed record at its
        canonical path. Private to the two callers above."""
        pair = (kind, test_id, repetition)
        if pair in self._persisted:
            raise SafetyBarrierTripped(
                f"a {kind} for {test_id} rep {repetition} was already "
                "persisted")
        validate_record(record, self._secrets)
        self._assert_this_run(record)
        relative = expected_relative_for_record(record)
        payload = json.dumps(record, sort_keys=True, indent=2,
                             ensure_ascii=False).encode("utf-8")
        self._write_bytes(relative, payload)
        self._persisted[pair] = relative
        return relative

    def _load_persisted(self, relative):
        """Re-read one of our own persisted files from DISK and re-validate.

        Deriving from the bytes on disk (rather than from a cached dict)
        means the writer's derivation uses exactly what reconstruction will
        later use.
        """
        recorded = self._files.get(relative)
        if recorded is None:
            raise SafetyBarrierTripped(
                f"{relative} was never persisted by this writer")
        path = os.path.join(self.run_dir, relative)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                raise SafetyBarrierTripped(f"{relative} is not a regular file")
            max_bytes = _policy().max_evidence_file_bytes
            if st.st_size > max_bytes:
                raise SafetyBarrierTripped(f"{relative} exceeds size bound")
            raw = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw += chunk
                if len(raw) > max_bytes:
                    raise SafetyBarrierTripped(
                        f"{relative} exceeds size bound while reading")
        finally:
            os.close(fd)
        if hashlib.sha256(raw).hexdigest() != recorded:
            raise SafetyBarrierTripped(
                f"{relative} changed since it was written")
        record = strict_json_loads(raw.decode("utf-8"))
        if type(record) is not dict:
            raise SafetyBarrierTripped(f"{relative}: root is not an object")
        validate_record(record, self._secrets)
        return record

    # ── Authoritative typed write methods (BLOCKER 1/2) ──────────────────

    def write_semantic_record(self, issued, *, http_status, outcome,
                              mutation_observed, credential_expired=False,
                              group=None) -> str:
        with self._lock:
            identity = self._consume(issued)
            if type(identity) is not RepetitionIdentity:
                raise SafetyBarrierTripped(
                    "a semantic record needs a semantic identity")
            test_id = identity.test_id
            spec = test_spec(test_id)
            # Only the semantic matrix rows get a SEMANTIC_RECORD; a support
            # row must go through the derived TEST_RESULT path.
            if spec.category != "semantic":
                raise SafetyBarrierTripped(
                    f"{test_id} is a {spec.category} row — it has no "
                    "SEMANTIC_RECORD")
            group = group if group is not None else spec.group
            evidence = SemanticEvidence(
                identity=identity, http_status=http_status, outcome=outcome,
                mutation_observed=mutation_observed,
                credential_expired=credential_expired)
            # Validate + derive BEFORE persisting; only then advance state.
            validate_semantic_evidence(evidence)
            derived, abandon_reason = derive_semantic_status(evidence)
            status_value = "ABANDON" if abandon_reason is not None \
                else derived.value
            record = {
                "record_kind": "SEMANTIC_RECORD", "phase": self._phase,
                "run_id": self.run_id, "group": group, "test_id": test_id,
                "repetition": identity.repetition, "key": identity.key,
                "issuance_nonce": issued.nonce,
                "status": http_status, "ambiguous_state": outcome.value,
                "mutation_observed": mutation_observed,
                "credential_expired": credential_expired,
                "repetition_status": status_value}
            relative = self._persist_typed("SEMANTIC_RECORD", test_id,
                                           identity.repetition, record)
            # Persistence succeeded → advance owned state.
            self._semantic.record(evidence)
            self._used_nonces.add(issued.nonce)
            return relative

    def write_race_record(self, issued, repetition) -> str:
        with self._lock:
            identity = self._consume(issued)
            if type(identity) is not RaceIdentity:
                raise SafetyBarrierTripped(
                    "a race record needs a race identity")
            if type(repetition) is not RaceRepetition \
                    or repetition.identity != identity:
                raise SafetyBarrierTripped(
                    "race repetition identity does not match the issuance")
            validate_race_repetition(repetition)
            status, _reason, attributions = classify_race_repetition(
                repetition)
            losers = [a for a in attributions if a is not None]
            attribution = losers[0].value if losers else None
            record = _flatten_race_record(
                repetition, phase=self._phase, run_id=self.run_id,
                group=test_spec(identity.test_id).group,
                issuance_nonce=issued.nonce,
                status=status.value, attribution=attribution)
            relative = self._persist_typed("RACE_RECORD", identity.test_id,
                                           identity.repetition, record)
            self._race.record(repetition)
            self._used_nonces.add(issued.nonce)
            return relative

    def write_request_record(self, record) -> str:
        """Persist a REQUEST_RECORD, THEN register its correlation id so a
        later RESPONSE_RECORD can be tied back to it (MEDIUM 3).

        The registry advances only after the bytes are on disk (MEDIUM 1):
        if persistence fails, no request is remembered, so a subsequent
        response for that correlation is still an orphan and is refused.
        """
        with self._lock:
            if record.get("record_kind") != "REQUEST_RECORD":
                raise EvidenceValidationError("expected a REQUEST_RECORD")
            validate_record(record, self._secrets)
            self._assert_this_run(record)
            corr = record["correlation_id"]
            if corr in self._requests:
                raise SafetyBarrierTripped(
                    f"duplicate request correlation_id {corr!r}")
            relative = expected_relative_for_record(record)
            payload = json.dumps(record, sort_keys=True, indent=2,
                                 ensure_ascii=False).encode("utf-8")
            self._write_bytes(relative, payload)
            # Persisted → only now does the correlation exist.
            self._requests[corr] = record["test_id"]
            return relative

    def write_response_record(self, record) -> str:
        """Persist a RESPONSE_RECORD; it must correlate to a previously
        PERSISTED REQUEST_RECORD with the same correlation id and test
        (MEDIUM 3). No orphan or duplicate responses. As with requests, the
        registry advances only after the bytes are on disk (MEDIUM 1).
        """
        with self._lock:
            if record.get("record_kind") != "RESPONSE_RECORD":
                raise EvidenceValidationError("expected a RESPONSE_RECORD")
            validate_record(record, self._secrets)
            self._assert_this_run(record)
            corr = record["correlation_id"]
            if corr not in self._requests:
                raise SafetyBarrierTripped(
                    f"orphan RESPONSE_RECORD: no request for {corr!r}")
            if self._requests[corr] != record["test_id"]:
                raise SafetyBarrierTripped(
                    "RESPONSE_RECORD test does not match its request")
            if corr in self._responses:
                raise SafetyBarrierTripped(
                    f"duplicate RESPONSE_RECORD for {corr!r}")
            relative = expected_relative_for_record(record)
            payload = json.dumps(record, sort_keys=True, indent=2,
                                 ensure_ascii=False).encode("utf-8")
            self._write_bytes(relative, payload)
            self._responses[corr] = record["status"]
            return relative

    def write_test_result_record(self, issued, *, evidence_ref,
                                 group=None) -> str:
        """Persist the DERIVED per-repetition result of a support row.

        The caller supplies ONLY the correlation of the request/response
        pair that this repetition produced. The outcome classification, the
        validity and the production-size flag are all computed by
        `derive_test_result` from the persisted evidence, re-read from disk
        (Codex BLOCKER 1 + 2). There is no argument by which a caller can
        label an HTTP 200 on the DeleteObject-denial row as a success, or
        mark a one-byte PUT as a production-size repetition.
        """
        with self._lock:
            identity = self._consume(issued)
            if type(identity) is not RepetitionIdentity:
                raise SafetyBarrierTripped(
                    "a test result record needs a repetition identity")
            test_id = identity.test_id
            spec = test_spec(test_id)
            if spec.category in ("semantic", "race"):
                raise SafetyBarrierTripped(
                    f"{test_id} results are derived from its own typed "
                    "records, not from a TEST_RESULT_RECORD")
            if type(evidence_ref) is not str:
                raise SafetyBarrierTripped("evidence_ref must be exactly str")
            corr = parse_correlation(evidence_ref)
            if corr.phase != self._phase or corr.run_id != self.run_id \
                    or corr.test_id != test_id \
                    or corr.repetition != identity.repetition:
                raise SafetyBarrierTripped(
                    "evidence_ref does not correlate to this "
                    "phase/run/test/repetition")
            if evidence_ref not in self._responses:
                raise SafetyBarrierTripped(
                    f"evidence ref {evidence_ref!r} is not a persisted "
                    "response")
            # Re-read BOTH physical files and derive from their bytes.
            request = self._load_persisted(expected_relative_for_record(
                {"record_kind": "REQUEST_RECORD",
                 "correlation_id": evidence_ref}))
            response = self._load_persisted(expected_relative_for_record(
                {"record_kind": "RESPONSE_RECORD",
                 "correlation_id": evidence_ref}))
            siblings = []
            sibling_resps = []
            for correlation in sorted(self._requests):
                if correlation == evidence_ref:
                    continue
                other = parse_correlation(correlation)
                if other.test_id != test_id \
                        or other.repetition != identity.repetition:
                    continue
                siblings.append(self._load_persisted(
                    expected_relative_for_record(
                        {"record_kind": "REQUEST_RECORD",
                         "correlation_id": correlation})))
                # The sibling's RESPONSE is required so K3 can prove the
                # earlier same-key write was server-observed (Codex HIGH 2).
                if correlation in self._responses:
                    sibling_resps.append(self._load_persisted(
                        expected_relative_for_record(
                            {"record_kind": "RESPONSE_RECORD",
                             "correlation_id": correlation})))
            derived = derive_test_result(spec, request, response,
                                         sibling_requests=siblings,
                                         sibling_responses=sibling_resps)
            record = {
                "record_kind": "TEST_RESULT_RECORD", "phase": self._phase,
                "run_id": self.run_id,
                "group": group if group is not None else spec.group,
                "test_id": test_id, "repetition": identity.repetition,
                "key": identity.key, "issuance_nonce": issued.nonce,
                "outcome_classification": derived.outcome,
                "derived_valid": derived.valid,
                "derived_production_size": derived.production_size,
                "evidence_refs": [evidence_ref]}
            relative = self._persist_typed("TEST_RESULT_RECORD", test_id,
                                           identity.repetition, record)
            self._used_nonces.add(issued.nonce)
            return relative

    # ── Disk-authoritative finalize (BLOCKER 2) ──────────────────────────

    def finalize(self) -> dict:
        """DERIVE the run summary from the PHYSICAL PERSISTED RECORDS.

        Takes NO caller-owned aggregator/ledger/completion/verdict, and
        trusts NO in-memory acceptance state. Every evidence file under the
        run directory is reopened, size-bounded, hashed, strictly parsed,
        fully re-validated and folded into FRESH aggregators; the summary is
        derived from that rebuild alone. The writer's own index is then
        required to be EXACTLY equal to what is on disk — same file set,
        same digests, same typed identities, same correlations — so a
        deleted, altered, extra, unmanifested, untyped or unreadable file
        makes PASS impossible.
        """
        with self._lock:
            rebuilt = reconstruct_run_from_disk(
                self.run_dir, phase=self._phase, run_id=self.run_id,
                secrets=self._secrets, recorded_digests=dict(self._files),
                issued_registry=self._allocator.issued_registry())

            # Exact set equality: physical files ≡ manifest index.
            physical = set(rebuilt.files)
            indexed = set(self._files)
            if physical != indexed:
                raise SafetyBarrierTripped(
                    "evidence bundle disagrees with the manifest index: "
                    f"only-on-disk={sorted(physical - indexed)} "
                    f"only-in-index={sorted(indexed - physical)}")
            for relative, digest in rebuilt.files.items():
                if self._files[relative] != digest:
                    raise SafetyBarrierTripped(
                        f"{relative}: digest changed since it was written")

            # Exact set equality: typed identities on disk ≡ identities the
            # writer believes it persisted.
            expected_ids = frozenset(self._persisted)
            if rebuilt.identities != expected_ids:
                raise SafetyBarrierTripped(
                    "typed record identities disagree with the persisted "
                    f"registry: only-on-disk="
                    f"{sorted(rebuilt.identities - expected_ids)} "
                    f"only-in-registry={sorted(expected_ids - rebuilt.identities)}")
            for pair, relative in self._persisted.items():
                if relative not in rebuilt.files:
                    raise SafetyBarrierTripped(
                        f"{pair}: persisted record {relative!r} is not on disk")

            # Exact set equality: correlations on disk ≡ correlations seen.
            disk_requests = {c.serialize()
                             for c in rebuilt.correlations["REQUEST_RECORD"]}
            disk_responses = {c.serialize()
                              for c in rebuilt.correlations["RESPONSE_RECORD"]}
            if disk_requests != set(self._requests):
                raise SafetyBarrierTripped(
                    "REQUEST_RECORD correlations disagree with the registry")
            if disk_responses != set(self._responses):
                raise SafetyBarrierTripped(
                    "RESPONSE_RECORD correlations disagree with the registry")

            summary = derive_run_summary(
                phase=self._phase, semantic=rebuilt.semantic,
                race=rebuilt.race, ledger=self.ledger,
                completion=rebuilt.completion)
            # PASS additionally requires a non-empty evidence bundle.
            if summary["verdict"] == "PASS" and not rebuilt.files:
                summary = dict(summary)
                summary["verdict"] = "INCOMPLETE"
            # The persisted open-reservation counts must equal the ledger's
            # OWN authoritative counts (Codex round-3 BLOCKER 1). A summary
            # whose counts were altered — e.g. zeroed while a reservation is
            # genuinely open — fails closed here rather than being written.
            authoritative_open = self.ledger.open_reservation_counts()
            if (summary["open_put_reservations"],
                    summary["open_race_pairs"]) != authoritative_open:
                raise SafetyBarrierTripped(
                    "summary open-reservation counts disagree with the "
                    f"ledger: summary=({summary['open_put_reservations']}, "
                    f"{summary['open_race_pairs']}) "
                    f"ledger={authoritative_open}")
            validate_summary(summary, self._secrets)
            manifest = {
                "run_id": self.run_id,
                "summary": dict(summary),
                "files": dict(sorted(rebuilt.files.items())),
            }
            payload = json.dumps(manifest, sort_keys=True, indent=2,
                                 ensure_ascii=False).encode("utf-8")
            manifest_path = os.path.join(self.run_dir,
                                         _manifest_filename())
            self._write_new_private_file(manifest_path, payload)
            manifest_sha256 = hashlib.sha256(payload).hexdigest()
            anchor_path = os.path.join(self.anchor_dir,
                                       f"{self.run_id}.sha256")
            self._write_new_private_file(
                anchor_path, (manifest_sha256 + "\n").encode("ascii"))
            _fsync_directory(self.run_dir)
            _fsync_directory(self.anchor_dir)
            return {"manifest_path": manifest_path,
                    "manifest_sha256": manifest_sha256,
                    "anchor_path": anchor_path,
                    "verdict": summary["verdict"]}


def _flatten_race_record(repetition, *, phase, run_id, group,
                         issuance_nonce, status, attribution) -> dict:
    """Flatten a validated RaceRepetition into a RACE_RECORD carrying the
    COMPLETE facts, so the result re-derives from the record (BLOCKER 2)."""
    ident = repetition.identity
    record = {
        "record_kind": "RACE_RECORD", "phase": phase, "run_id": run_id,
        "group": group, "test_id": ident.test_id,
        "repetition": ident.repetition, "key": ident.key,
        "issuance_nonce": issuance_nonce, "setup_state": ident.setup_state,
        "shared_original_etag": repetition.shared_original_etag,
        "absence_confirmed": repetition.absence_confirmed,
        "barrier_generation_id": repetition.barrier.generation_id,
        "barrier_release_mono_ns": repetition.barrier.release_mono_ns,
        "final_state": repetition.final_state.value,
        "final_sha256": repetition.final_sha256,
        "final_length": repetition.final_length,
        "final_etag": repetition.final_etag,
        "race_repetition_status": status, "race_attribution": attribution}
    for prefix, w in zip(("w1", "w2"), repetition.writers):
        record.update({
            f"{prefix}_writer_id": w.writer_id,
            f"{prefix}_http_status": w.http_status,
            f"{prefix}_payload_sha256": w.payload_sha256,
            f"{prefix}_payload_length": w.payload_length,
            f"{prefix}_returned_etag": w.returned_etag,
            f"{prefix}_if_match": w.if_match,
            f"{prefix}_if_none_match": w.if_none_match,
            f"{prefix}_barrier_generation": w.barrier_generation,
            f"{prefix}_barrier_join_mono_ns": w.barrier_join_mono_ns,
            f"{prefix}_send_mono_ns": w.send_mono_ns})
    return record


def _fingerprint(text) -> str | None:
    """A stable, NON-SECRET identity for a credential component."""
    if text is None:
        return None
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def build_request_record(*, phase, run_id, group, test_id, repetition,
                         sequence, endpoint_host, signed,
                         credential=None,
                         t_request_attempt_mono_ns=None) -> dict:
    """Evidence for one outgoing request.

    `t_request_attempt_mono_ns` is the PHYSICAL instant captured at the
    `conn.request()` boundary by the transport (Codex round-3 BLOCKER 3) —
    the only time source K3's throttle window may use. It is None when no
    request was ever attempted.

    EVERY credential fact is DERIVED from the SignedRequest that actually
    went on the wire (Codex BLOCKER 2). There is no `session_token_present`
    argument: token presence comes from the wire headers, and whether it
    was signed comes from SignedHeaders. The group, scope, actions,
    prefixes and validity window are decoded from the TRANSMITTED session
    token, never copied from the caller's `TemporaryCredential` — a
    NamedTuple whose `_replace` would otherwise let evidence claim a group
    or an expiry the signed token does not carry. A supplied credential is
    used only to cross-check identity, and any disagreement with the signed
    claims is rejected.

    The full endpoint hostname is NEVER recorded — it embeds the account
    ID. Only its digest is kept. Secrets are never recorded, only SHA-256
    fingerprints.

    The correlation id is DERIVED from the full five-component identity and
    cannot be overridden (HIGH B).
    """
    headers = signed.header_map()
    token_header = _grammar().security_token_header
    if_match = headers.get("if-match")
    if_none_match = headers.get("if-none-match")
    wire_token = headers.get(token_header)
    token_present = wire_token is not None
    token_signed = token_header in signed.signed_header_names
    token_fingerprint = _fingerprint(wire_token)

    # The access key id that signed this request, read back out of the
    # wire Authorization header rather than taken on trust.
    authorization = headers.get("authorization") or ""
    akid = None
    marker = "Credential="
    if marker in authorization:
        akid = authorization.split(marker, 1)[1].split("/", 1)[0] or None
    akid_fingerprint = _fingerprint(akid)

    credential_facts = {
        "credential_group": None, "credential_scope": None,
        "credential_actions": None, "credential_prefixes": None,
        "credential_issued_at": None, "credential_expires_at": None,
    }
    if credential is not None and type(credential) is not TemporaryCredential:
        raise SafetyBarrierTripped(
            "credential must be exactly TemporaryCredential")
    if token_present:
        # THE TRANSMITTED TOKEN IS THE AUTHORITY (Codex BLOCKER 2). Every
        # credential fact below is decoded from the JWT that actually went
        # on the wire; none is copied from the caller's NamedTuple.
        if akid is None:
            raise SafetyBarrierTripped(
                "a session token was sent without a signing access key")
        claims = validate_transmitted_token_claims(
            wire_token, endpoint_host=endpoint_host, access_key_id=akid)
        if credential is not None:
            # The caller's object may only CROSS-CHECK identity. Any
            # disagreement with the signed claims is misuse, not a
            # preference, so it is rejected rather than silently ignored.
            if _fingerprint(credential.session_token) != token_fingerprint:
                raise SafetyBarrierTripped(
                    "the wire session token is not this credential's token")
            if _fingerprint(credential.access_key_id) != akid_fingerprint:
                raise SafetyBarrierTripped(
                    "the recorded credential did not sign this request")
            if hashlib.sha256(
                    _decode_probe_session_token(wire_token)[2].encode("utf-8")
                    ).hexdigest() != credential.secret_access_key:
                raise SafetyBarrierTripped(
                    "derived secret is not sha256(transmitted jwt)")
            for name, claimed, supplied in (
                    ("group", claims.group, credential.group),
                    ("scope", claims.scope, credential.scope),
                    ("actions", claims.actions, tuple(credential.actions)),
                    ("prefixes", claims.prefix_paths,
                     tuple(credential.prefix_paths)),
                    ("issued_at", claims.issued_at, credential.issued_at),
                    ("expires_at", claims.expires_at, credential.expires_at),
                    ("bucket", claims.bucket, credential.bucket)):
                if claimed != supplied:
                    raise SafetyBarrierTripped(
                        f"credential {name} {supplied!r} disagrees with the "
                        f"transmitted token claim {claimed!r}")
        credential_facts = {
            "credential_group": claims.group,
            "credential_scope": claims.scope,
            "credential_actions": list(claims.actions),
            "credential_prefixes": list(claims.prefix_paths),
            "credential_issued_at": claims.issued_at,
            "credential_expires_at": claims.expires_at,
        }
    elif credential is not None:
        # No token on the wire (I3). Identity may still be cross-checked
        # against the signing key, but NO credential claim facts are
        # recorded: with no transmitted token there is nothing to decode
        # them from, and copying them off the caller's object is exactly
        # the bypass this boundary exists to prevent.
        if _fingerprint(credential.access_key_id) != akid_fingerprint:
            raise SafetyBarrierTripped(
                "the recorded credential did not sign this request")

    amz_date = headers.get("x-amz-date")
    corr = Correlation(phase=phase, run_id=run_id, test_id=test_id,
                       repetition=repetition, sequence=sequence).serialize()
    record = {
        "record_kind": "REQUEST_RECORD",
        "phase": phase, "run_id": run_id, "group": group, "test_id": test_id,
        "repetition": repetition, "sequence": sequence,
        "correlation_id": corr,
        "bucket": signed.target.bucket, "key": signed.target.key,
        "endpoint_host_sha256": hashlib.sha256(
            endpoint_host.encode("utf-8")).hexdigest(),
        "http_method": signed.target.method,
        "query_params": [[name, value] for name, value in signed.target.query],
        "if_match_raw": if_match, "if_match_raw_hex": hex_of(if_match),
        "if_none_match_raw": if_none_match,
        "if_none_match_raw_hex": hex_of(if_none_match),
        "signed_headers": list(signed.signed_header_names),
        # DERIVED from the wire, never supplied.
        "session_token_present": token_present,
        "session_token_signed": token_signed,
        "session_token_sha256": token_fingerprint,
        "access_key_id_sha256": akid_fingerprint,
        "request_time_epoch": (_amz_date_to_epoch(amz_date)
                               if amz_date is not None else None),
        "request_body_len": len(signed.body),
        "request_body_sha256": _sha256_hex(signed.body),
        "multipart_markers_present": any(
            name in _policy().multipart_query_markers
            for name, _ in signed.target.query),
        # The physical conn.request() instant, straight from the transport.
        "t_request_attempt_mono_ns": _exact_opt_int(
            t_request_attempt_mono_ns, "t_request_attempt_mono_ns", minimum=0),
    }
    record.update(credential_facts)
    return record


def build_response_record(*, phase, run_id, group, test_id, repetition,
                          sequence, response, parsed, repetition_status,
                          error_category=None, exception_type_name=None,
                          race_attribution=None, ambiguous_state=None,
                          remote_state=None, reconciliation=None,
                          final_get_len=None, final_get_sha256=None) -> dict:
    """As with requests, the correlation id is DERIVED, never supplied."""
    etag = response.header("ETag") if response is not None else None
    corr = Correlation(phase=phase, run_id=run_id, test_id=test_id,
                       repetition=repetition, sequence=sequence).serialize()
    return {
        "record_kind": "RESPONSE_RECORD",
        "phase": phase, "run_id": run_id, "group": group, "test_id": test_id,
        "repetition": repetition, "sequence": sequence,
        "correlation_id": corr,
        "status": response.status if response is not None else None,
        "etag_raw": etag, "etag_raw_hex": hex_of(etag),
        "error_code": parsed.code if parsed else None,
        "error_message": parsed.message if parsed else None,
        "message_omitted": parsed.message_omitted if parsed else False,
        "request_id": parsed.request_id if parsed else None,
        "host_id_sha256": parsed.host_id_sha256 if parsed else None,
        "cf_ray": response.header("cf-ray") if response is not None else None,
        "response_body_len": (len(response.body)
                              if response is not None else None),
        "response_body_sha256": (_sha256_hex(response.body)
                                 if response is not None else None),
        "body_truncated": (response.body_truncated
                           if response is not None else None),
        "final_get_len": final_get_len, "final_get_sha256": final_get_sha256,
        "t_request_start_mono_ns": (response.t_request_start_mono_ns
                                    if response is not None else None),
        "t_response_end_mono_ns": (response.t_response_end_mono_ns
                                   if response is not None else None),
        "repetition_status": (repetition_status.value
                              if repetition_status is not None else None),
        "race_attribution": (race_attribution.value
                             if race_attribution else None),
        "ambiguous_state": ambiguous_state.value if ambiguous_state else None,
        "remote_state": remote_state.value if remote_state else None,
        "reconciliation": reconciliation.value if reconciliation else None,
        "error_category": error_category.value if error_category else None,
        "exception_type_name": exception_type_name,
    }


# ─────────────────────────────────────────────────────────────────────────
# Disposable parent credential file  (Gate D input)
#
# The ONLY credential source the live runner may read is the explicit
# --credentials-file. There is deliberately no environment fallback, no AWS
# credential chain, no ~/.aws, no wrangler and no default path. The file is
# parsed with a strict, non-executing KEY=VALUE reader: no `source`, no
# shell, no interpolation, no comments, exactly the two expected keys.
# ─────────────────────────────────────────────────────────────────────────

class ParentCredentials(NamedTuple):
    """The disposable, bucket-scoped parent R2 API token, in memory only.

    Never serialised, never logged. Its two values are handed to the
    EvidenceWriter as `secrets` so the evidence secret-scan refuses any
    record that would contain them, and they are used only to mint the
    per-group child credentials.
    """

    access_key_id: str
    secret_access_key: str

    def secret_values(self) -> tuple:
        return (self.access_key_id, self.secret_access_key)


CREDENTIAL_FILE_MAX_BYTES = 4096
_CREDENTIAL_ACCESS_KEY = "R2_ACCESS_KEY_ID"
_CREDENTIAL_SECRET_KEY = "R2_SECRET_ACCESS_KEY"
_CREDENTIAL_KEYS = (_CREDENTIAL_ACCESS_KEY, _CREDENTIAL_SECRET_KEY)


def _probe_repo_root() -> str:
    """The Bible PAL checkout root (scripts/ is one level below it)."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _path_is_inside_repo(path: str) -> bool:
    real = os.path.realpath(path)
    root = os.path.realpath(_probe_repo_root())
    try:
        return os.path.commonpath([real, root]) == root
    except ValueError:
        # Different drives / unrelated roots — cannot be inside the repo.
        return False


def load_probe_credentials_file(path) -> ParentCredentials:
    """Parse the disposable parent credential file, or refuse fail-closed.

    Enforced, in order (every failure raises WITHOUT echoing any value):
      - path is exactly str and free of any denied production name;
      - the path is NOT inside the Bible PAL repository;
      - the entry is a regular file, not a symlink (lstat, then O_NOFOLLOW);
      - it is owned by the current user (where the platform reports uids);
      - its mode grants NO group or other permission (`& 0o077 == 0`);
      - it is at most CREDENTIAL_FILE_MAX_BYTES and decodes as UTF-8;
      - it contains EXACTLY the two expected KEY=VALUE lines, each once,
        no unknown keys, no duplicates, no blank/comment/continuation
        lines, and each value matches the credential grammar.
    """
    _exact_str(path, "credentials-file path", max_len=4096)
    assert_no_denied_names(path)
    if _path_is_inside_repo(path):
        raise MissingAuthorization(
            "the credentials file must live OUTSIDE the Bible PAL repository")

    try:
        pre = os.lstat(path)
    except FileNotFoundError:
        raise MissingAuthorization(
            "the disposable credential file does not exist")
    except OSError:
        raise MissingAuthorization("the credential path cannot be examined")
    if stat.S_ISLNK(pre.st_mode):
        raise MissingAuthorization("the credential file must not be a symlink")

    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        raise MissingAuthorization(
            "the credential file could not be opened (symlink or missing)")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise MissingAuthorization(
                "the credential path is not a regular file")
        if hasattr(os, "getuid") and st.st_uid != os.getuid():
            raise MissingAuthorization(
                "the credential file is not owned by the current user")
        if stat.S_IMODE(st.st_mode) & 0o077:
            raise MissingAuthorization(
                "the credential file is group/other accessible "
                "(required mode: owner-only, e.g. 0600)")
        if st.st_size > CREDENTIAL_FILE_MAX_BYTES:
            raise MissingAuthorization("the credential file is too large")
        raw = b""
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            raw += chunk
            if len(raw) > CREDENTIAL_FILE_MAX_BYTES:
                raise MissingAuthorization("the credential file is too large")
    finally:
        os.close(fd)

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise MissingAuthorization("the credential file is not valid UTF-8")

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()                      # tolerate exactly one trailing NL
    found = {}
    for line in lines:
        if line == "" or any(ch in line for ch in "\x00\r\t"):
            raise MissingAuthorization(
                "the credential file has a blank or malformed line")
        if line.startswith("#") or line.startswith("export ") \
                or "=" not in line:
            raise MissingAuthorization(
                "the credential file must contain only KEY=VALUE lines "
                "(no comments, no `export`, no shell)")
        key, value = line.split("=", 1)
        if key not in _CREDENTIAL_KEYS:
            raise MissingAuthorization(
                "the credential file contains an unexpected key")
        if key in found:
            raise MissingAuthorization(
                "the credential file has a duplicate key")
        if not _grammar().cred.fullmatch(value):
            raise MissingAuthorization(
                "a credential value is empty or malformed")
        found[key] = value

    missing = [k for k in _CREDENTIAL_KEYS if k not in found]
    if missing:
        raise MissingAuthorization(
            "the credential file is missing a required key")
    return ParentCredentials(
        access_key_id=found[_CREDENTIAL_ACCESS_KEY],
        secret_access_key=found[_CREDENTIAL_SECRET_KEY])


# ─────────────────────────────────────────────────────────────────────────
# Live orchestration runner
#
# Composes the already-reviewed primitives — no new CAS/race/evidence
# SEMANTICS live here, only the scheduling that drives them. Every request
# is signed and transmitted through R2Transport; every acceptance decision
# is DERIVED by the existing aggregators/derivations from persisted
# evidence; caps, the same-key guard and production-name isolation are the
# existing objects. The runner is fully injectable (transport factory, wall
# clock, monotonic clock, sleep) so the offline tests drive it with fakes
# and never open a socket.
# ─────────────────────────────────────────────────────────────────────────

def format_amz_date(epoch) -> str:
    """`YYYYMMDDThhmmssZ` for a UTC epoch — the inverse of _amz_date_to_epoch.

    Fixed-offset UTC only; no local timezone is ever consulted.
    """
    from datetime import datetime, timezone
    _exact_int(epoch, "epoch", minimum=1)
    return datetime.fromtimestamp(epoch, timezone.utc).strftime(
        "%Y%m%dT%H%M%SZ")


class ProbeAbandon(ProbeError):
    """A terminal safety property was violated (a mutation where rejection
    was required, an over-privileged child credential, an impossible
    response). The run stops immediately; it never keeps sampling."""

    exit_code = EXIT_ABANDON


#: A well-formed ETag that is deliberately NOT the seeded object's ETag.
#: R2's If-Match compares ETags: any non-match — stale or simply wrong —
#: is a 412, which is exactly the precondition the semantic rows exercise.
_STALE_IF_MATCH = '"stale-precondition-never-matches"'


class _Sent(NamedTuple):
    """The single authoritative facts of one dispatched request.

    The REQUEST_RECORD is built from `signed` — the exact SignedRequest the
    transport transmitted — and `t_request_attempt_mono_ns` is the instant
    captured AT the conn.request boundary (None iff the send failed before
    a request was ever attempted). There is no second, separately-signed
    request anywhere (Codex round-2 section 6)."""

    spec: object
    repetition: int
    sequence: int
    correlation: str
    signed: object                # SignedRequest actually transmitted
    response: object              # RawResponse | None
    transport_failure: object     # TransportFailure | None
    parsed: object                # ParsedError | None
    is_put: bool
    key: str
    reservation: object           # PutReservation | None
    method: str
    t_request_attempt_mono_ns: object   # int | None
    send_phase: object            # SendPhase


class LiveProbeRunner:
    """Drives the full test matrix against a DISPOSABLE bucket.

    Nothing here can address production: the transport, the credential
    claims, the key allocator and the ledger all read the same immutable
    probe policy, whose bucket is `bible-pal-cas-probe` and whose denied
    token is the production bucket. `run()` returns the finalize() summary,
    DERIVED from the persisted evidence on disk, downgraded to ABANDON on
    any terminal safety violation or unresolved reservation.
    """

    def __init__(self, *, account_id, parent, writer,
                 connection_factory=None, wall_clock=time.time,
                 monotonic=time.monotonic_ns, sleep=time.sleep,
                 semantic_delay_seconds=1.0):
        if type(parent) is not ParentCredentials:
            raise SafetyBarrierTripped("parent must be ParentCredentials")
        if type(writer) is not EvidenceWriter:
            raise SafetyBarrierTripped("writer must be an EvidenceWriter")
        self._endpoint_host = build_endpoint_host(account_id)
        self._account_id = account_id
        self._parent = parent
        self._writer = writer
        self._phase = writer._phase
        self._wall_clock = wall_clock
        self._monotonic = monotonic
        self._sleep = sleep
        self._semantic_delay = float(semantic_delay_seconds)
        # The guard measures a same-key gap in SECONDS, derived from the same
        # monotonic (ns) source the runner and races use, so its clock and
        # the injected sleep can never desync.
        self._same_key_guard = SameKeyWriteGuard(
            monotonic=(lambda: self._monotonic() / 1e9), sleep=sleep)
        self._planner = CredentialGroupPlanner()
        # The transport owns the ONLY path to a real socket. In plan mode and
        # every test it is a refusing or fake factory; live, it is
        # real_connection_factory — installed by main() only after gates.
        self._transport = R2Transport(
            endpoint_host=self._endpoint_host,
            connection_factory=connection_factory,
            wall_clock=wall_clock, monotonic=monotonic)
        self._display = {}
        self._abandon_reason = None

    # ── credential per group ─────────────────────────────────────────────

    def _mint_child(self, group):
        now = int(self._wall_clock())
        cred = mint_probe_credential(
            group=group, account_id=self._account_id,
            parent_access_key_id=self._parent.access_key_id,
            parent_secret_access_key=self._parent.secret_access_key, now=now)
        ok, reason = self._planner.can_start(credential=cred, now=now)
        if not ok:
            raise ProbeAbandon(f"group {group} cannot start: {reason}")
        return cred

    # ── one request: reserve → sign+transmit (ONE authority) → persist ───

    def _dispatch(self, *, spec, credential, repetition, sequence, method,
                  key, body=b"", query=(), if_match=None, if_none_match=None,
                  diagnostic=None, identity=None, respect_guard=True,
                  charge_ledger=True,
                  allow_denied_prefix_probe=False) -> _Sent:
        is_put = method == "PUT"
        reservation = None
        if charge_ledger:
            if is_put:
                if respect_guard:
                    self._same_key_guard.wait_until_writable(key)
                reservation = self._writer.ledger.reserve_put(key, len(body))
            else:
                self._writer.ledger.charge_get_head()

        extra = {}
        if if_match is not None:
            extra["if-match"] = if_match
        if if_none_match is not None:
            extra["if-none-match"] = if_none_match

        # ONE transmit authority. Ordinary traffic goes through
        # sign_and_attempt; the three diagnostics go through their OWN exact
        # transport methods, which derive method/bucket/key/query/body/date
        # themselves from the allocator identity (Codex round-3 BLOCKER 2).
        # Both return the exact signed request AND the request-attempt
        # timestamp, so evidence and timing derive from the transmitted
        # object itself.
        if diagnostic is None:
            target = new_request_target(method=method, bucket=_policy().bucket,
                                        key=key, query=tuple(query))
            amz_date = format_amz_date(int(self._wall_clock()))
            attempt = self._transport.sign_and_attempt(
                target=target, body=body, credential=credential,
                amz_date=amz_date, extra_headers=(extra or None),
                allow_denied_prefix_probe=allow_denied_prefix_probe)
        else:
            if extra or query or method != "PUT":
                raise SafetyBarrierTripped(
                    "a diagnostic row has a fixed PUT shape and no "
                    "conditional/content headers")
            exact = {"I2": self._transport.attempt_i2,
                     "I3": self._transport.attempt_i3,
                     "I4": self._transport.attempt_i4}.get(diagnostic)
            if exact is None or spec.id != diagnostic:
                raise SafetyBarrierTripped(
                    f"{diagnostic!r} is not an exact diagnostic row for "
                    f"{spec.id!r}")
            attempt = exact(identity=identity, credential=credential)

        self._writer.write_request_record(build_request_record(
            phase=self._phase, run_id=self._writer.run_id, group=spec.group,
            test_id=spec.id, repetition=repetition, sequence=sequence,
            endpoint_host=self._endpoint_host,
            signed=attempt.signed_request, credential=credential,
            t_request_attempt_mono_ns=attempt.t_request_attempt_mono_ns))
        correlation = Correlation(
            phase=self._phase, run_id=self._writer.run_id, test_id=spec.id,
            repetition=repetition, sequence=sequence).serialize()

        response = attempt.response
        transport_failure = attempt.failure
        if is_put:
            self._same_key_guard.note_write_response_end(key)
        parsed = (parse_s3_error(response.body)
                  if response is not None and response.body else None)
        return _Sent(
            spec=spec, repetition=repetition, sequence=sequence,
            correlation=correlation, signed=attempt.signed_request,
            response=response, transport_failure=transport_failure,
            parsed=parsed, is_put=is_put, key=key, reservation=reservation,
            method=method,
            t_request_attempt_mono_ns=attempt.t_request_attempt_mono_ns,
            send_phase=attempt.send_phase)

    def _finish(self, sent, *, final_get_sha256=None, final_get_len=None,
                final_etag=None, remote_state=None, repetition_status=None,
                ambiguous_state=None, reconciliation=None,
                resolve_committed=None):
        """Persist the RESPONSE record and (for a PUT) resolve the ledger."""
        tf = sent.transport_failure
        record = build_response_record(
            phase=self._phase, run_id=self._writer.run_id, group=sent.spec.group,
            test_id=sent.spec.id, repetition=sent.repetition,
            sequence=sent.sequence, response=sent.response, parsed=sent.parsed,
            repetition_status=repetition_status,
            error_category=(tf.category if tf is not None else None),
            exception_type_name=(tf.exception_type_name if tf is not None
                                 else None),
            ambiguous_state=ambiguous_state, remote_state=remote_state,
            reconciliation=reconciliation, final_get_len=final_get_len,
            final_get_sha256=final_get_sha256)
        if final_etag is not None:
            record["final_etag"] = final_etag
        self._writer.write_response_record(record)
        if sent.is_put and sent.reservation is not None \
                and resolve_committed is not None:
            self._writer.ledger.resolve_put(sent.reservation,
                                            committed=resolve_committed)

    # ── outcome + reconciliation helpers ─────────────────────────────────

    def _put_outcome(self, sent):
        status = sent.response.status if sent.response is not None else None
        return classify_put_outcome(
            transport_failure=sent.transport_failure, status=status)

    def _committed(self, sent):
        """Definite commit decision, or None when the outcome is ambiguous
        (in which case the caller must NOT resolve — an unresolved
        reservation forces ABANDON at finalize)."""
        outcome = self._put_outcome(sent)
        if outcome in DEFINITE_NO_MUTATION_OUTCOMES:
            return False
        if outcome in (PutOutcome.PUT_CONFIRMED,
                       PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN):
            return True
        return None

    def _authoritative_get(self, spec, credential, repetition, sequence, key):
        """A child-credential GET whose body/sha/etag are captured, with its
        own request/response evidence persisted."""
        sent = self._dispatch(spec=spec, credential=credential,
                              repetition=repetition, sequence=sequence,
                              method="GET", key=key)
        resp = sent.response
        sha = length = etag = None
        if resp is None:
            # The verification read itself failed in transport: we learned
            # NOTHING about the remote object. UNKNOWN (never None) so every
            # caller feeds a real RemoteState into the reconciliation
            # machinery and fails closed.
            state = RemoteState.UNKNOWN
        elif 200 <= resp.status < 300:
            state = RemoteState.CONFIRMED
            sha = _sha256_hex(resp.body)
            length = len(resp.body)
            etag = resp.header("ETag")
        else:
            state = classify_remote_state(
                method="GET", status=resp.status,
                error_code=(sent.parsed.code if sent.parsed else None),
                body_truncated=resp.body_truncated)
        self._finish(sent, remote_state=state)
        return sha, length, etag, state

    def _mark(self, test_id, verdict):
        self._display[test_id] = verdict
        if verdict == "ABANDON":
            raise ProbeAbandon(f"{test_id}: terminal safety failure")

    def per_test_display(self) -> dict:
        return dict(self._display)

    # ── semantic rows: B, D, E1 (412-on-every-valid-repetition) ──────────

    def _run_semantic(self, spec, credential):
        for rep in range(1, spec.required_repetitions + 1):
            issued = self._writer.allocate_semantic(spec.id, rep)
            key = issued.identity.key
            seq = [0]

            def nxt():
                seq[0] += 1
                return seq[0]

            # SETUP: positively establish a known object state before the
            # CAS test. Returns the confirmed (sha, length); ABANDONs if it
            # cannot be proven.
            prior_sha, prior_len = self._establish_semantic_setup(
                spec, credential, rep, nxt, key)

            if spec.id == "D":
                if_match, if_none_match = None, "*"
            else:               # B, E1: a non-current If-Match must be 412
                if_match, if_none_match = _STALE_IF_MATCH, None

            other = synthetic_payload("other", 256)
            cas = self._dispatch(spec=spec, credential=credential,
                                 repetition=rep, sequence=nxt(), method="PUT",
                                 key=key, body=other, if_match=if_match,
                                 if_none_match=if_none_match)
            status = cas.response.status if cas.response is not None else None
            outcome = self._put_outcome(cas)

            mutation = None
            resolve = None
            if status == 412:
                # Blocked: the write was rejected server-side. VALID requires
                # a positive proof the object is UNCHANGED.
                obs_sha, obs_len, _e, gstate = self._authoritative_get(
                    spec, credential, rep, nxt(), key)
                if gstate is RemoteState.CONFIRMED \
                        and obs_sha == prior_sha and obs_len == prior_len:
                    mutation = False            # proven unchanged → VALID
                elif gstate is RemoteState.CONFIRMED:
                    mutation = True             # bytes changed → ABANDON
                else:
                    mutation = None             # UNKNOWN/ABSENT → not unchanged
                resolve = False
            elif status is not None and 200 <= status < 300:
                # A blocked precondition was ACCEPTED — the write mutated.
                mutation = True
                resolve = True
            elif next_action(outcome) \
                    is NextAction.RECONCILE_WITH_AUTHORITATIVE_GET:
                obs_sha, obs_len, _e, gstate = self._authoritative_get(
                    spec, credential, rep, nxt(), key)
                recon = reconcile_after_ambiguous_put(
                    get_state=gstate, observed_sha256=obs_sha,
                    observed_length=obs_len,
                    intended_sha256=hashlib.sha256(other).hexdigest(),
                    intended_length=len(other), prior_sha256=prior_sha,
                    prior_length=prior_len)
                if recon is Reconciliation.RECONCILED_SUCCESS:
                    mutation, resolve = True, True     # committed despite block
                elif recon is Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN:
                    mutation, resolve = None, False    # ambiguous, no mutation
                else:
                    # SUPERSEDED / UNKNOWN — cannot prove no mutation. Leave
                    # the reservation unresolved and ABANDON.
                    self._finish(cas, ambiguous_state=outcome,
                                resolve_committed=None)
                    self._mark(spec.id, "ABANDON")
                    return
            else:
                # A definite non-2xx, non-412 status (429/403/4xx) or a
                # before-request failure. No 412 evidence; no mutation.
                mutation = None
                resolve = self._committed(cas)

            self._finish(cas, ambiguous_state=outcome,
                        resolve_committed=resolve)
            self._writer.write_semantic_record(
                issued, http_status=status, outcome=outcome,
                mutation_observed=mutation)
            self._absorb_semantic_verdict(spec.id)

    def _establish_semantic_setup(self, spec, credential, rep, nxt, key):
        """Positively confirm the pre-CAS object state, or ABANDON.

        Returns the confirmed (sha256, length) of the object the CAS test
        will be run against."""
        seed = synthetic_payload("seed", 256)
        sent = self._dispatch(spec=spec, credential=credential,
                             repetition=rep, sequence=nxt(), method="PUT",
                             key=key, body=seed, if_none_match="*")
        self._confirm_committed_or_abandon(spec, credential, rep, nxt, key,
                                           sent, seed)
        prior = (hashlib.sha256(seed).hexdigest(), len(seed))
        if spec.id == "E1":
            # Overwrite so the seeded ETag becomes genuinely stale, then wait
            # out the same-key window and delay the stale writer.
            v2 = synthetic_payload("v2", 256)
            over = self._dispatch(spec=spec, credential=credential,
                                 repetition=rep, sequence=nxt(), method="PUT",
                                 key=key, body=v2)
            self._confirm_committed_or_abandon(spec, credential, rep, nxt, key,
                                               over, v2)
            prior = (hashlib.sha256(v2).hexdigest(), len(v2))
            self._sleep(self._semantic_delay)
        return prior

    def _confirm_committed_or_abandon(self, spec, credential, rep, nxt, key,
                                      sent, expected_body):
        """A setup PUT must be PROVEN to have committed exactly
        `expected_body`. Anything short of that stops the run."""
        want_sha = hashlib.sha256(expected_body).hexdigest()
        want_len = len(expected_body)
        status = sent.response.status if sent.response is not None else None
        outcome = self._put_outcome(sent)
        if status is not None and 200 <= status < 300:
            obs_sha, obs_len, _e, gstate = self._authoritative_get(
                spec, credential, rep, nxt(), key)
            if gstate is RemoteState.CONFIRMED \
                    and obs_sha == want_sha and obs_len == want_len:
                self._finish(sent, resolve_committed=True)
                return
            self._finish(sent, resolve_committed=True)
            self._mark(spec.id, "ABANDON")   # committed wrong/unverifiable
            return
        if next_action(outcome) \
                is NextAction.RECONCILE_WITH_AUTHORITATIVE_GET:
            obs_sha, obs_len, _e, gstate = self._authoritative_get(
                spec, credential, rep, nxt(), key)
            recon = reconcile_after_ambiguous_put(
                get_state=gstate, observed_sha256=obs_sha,
                observed_length=obs_len, intended_sha256=want_sha,
                intended_length=want_len, prior_sha256=None, prior_length=None)
            if recon is Reconciliation.RECONCILED_SUCCESS:
                self._finish(sent, resolve_committed=True)
                return
            if recon is Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN:
                self._finish(sent, resolve_committed=False)  # proven absent
                self._mark(spec.id, "ABANDON")               # setup failed
                return
            self._finish(sent, resolve_committed=None)       # unknown → open
            self._mark(spec.id, "ABANDON")
            return
        # Definite rejection / before-request failure → setup failed.
        self._finish(sent, resolve_committed=self._committed(sent))
        self._mark(spec.id, "ABANDON")

    def _absorb_semantic_verdict(self, test_id):
        verdict, _ = self._writer._semantic.verdict(test_id)
        if verdict is Verdict.ABANDON:
            self._mark(test_id, "ABANDON")

    # ── support rows via the derived TEST_RESULT path ────────────────────

    def _run_support(self, spec, credential):
        for rep in range(1, spec.required_repetitions + 1):
            issued = self._writer.allocate_semantic(spec.id, rep)
            corr = self._support_repetition(spec, credential, rep, issued)
            self._writer.write_test_result_record(issued, evidence_ref=corr)
        self._display[spec.id] = "DONE"

    def _support_repetition(self, spec, credential, rep, issued) -> str:
        tid = spec.id
        key = issued.identity.key
        if tid == "A":
            return self._support_correct_etag(spec, credential, rep, key)
        if tid in ("C", "X1", "X2"):
            return self._support_create_if_absent(spec, credential, rep, key)
        if tid in ("G", "L"):
            return self._support_put_readback(spec, credential, rep, key)
        if tid == "J":
            return self._support_production_put(spec, credential, rep, key)
        if tid in ("H1", "H2", "H3"):
            return self._support_allowed_scope(spec, credential, rep, key)
        if tid in ("H4", "H5", "H6", "H7"):
            return self._support_denied_scope(spec, credential, rep, key)
        if tid == "I1":
            return self._support_signing_ok(spec, credential, rep, key)
        if tid == "I2":
            return self._send_i2_unsigned_token(spec, credential, rep, issued)
        if tid == "I3":
            return self._send_i3_no_token(spec, credential, rep, issued)
        if tid == "I4":
            return self._send_i4_expired_token(spec, credential, rep, issued)
        if tid == "K1":
            return self._support_absent(spec, credential, rep, key)
        if tid == "K2":
            return self._support_denied_contrast(spec, credential, rep, key)
        if tid == "K3":
            return self._support_throttle(spec, credential, rep, key)
        raise SafetyBarrierTripped(f"no support orchestration for {tid!r}")

    def _support_correct_etag(self, spec, credential, rep, key) -> str:
        """A: correct ETag + If-Match must mutate and verify.

        The dependent conditional PUT is issued ONLY after the seed is fully
        reconciled and a usable CURRENT ETag has been proven (Codex round-3
        HIGH 1). While the seed's commit state is unresolved, no second
        same-key write is sent, and the dependent PUT is never issued
        unconditionally — it always carries the proven seed ETag.
        """
        seed_body = synthetic_payload("seed", 256)
        seed = self._dispatch(spec=spec, credential=credential, repetition=rep,
                             sequence=1, method="PUT", key=key,
                             body=seed_body, if_none_match="*")
        # Sequences: 1 seed, 2 seed-verification GET, 3 dependent PUT,
        # 4 final verification GET.
        etag = self._reconcile_seed_and_prove_etag(
            spec, credential, rep, key, seed, seed_body, next_sequence=2)
        # `_reconcile_seed_and_prove_etag` ABANDONs unless it returns a
        # usable current ETag, so from here the seed is proven.
        body = synthetic_payload("a", 256)
        test = self._dispatch(spec=spec, credential=credential, repetition=rep,
                             sequence=3, method="PUT", key=key, body=body,
                             if_match=etag)
        sha, length, _e, _s = self._authoritative_get(
            spec, credential, rep, 4, key)
        self._finish(test, final_get_sha256=sha, final_get_len=length,
                    remote_state=RemoteState.CONFIRMED,
                    resolve_committed=self._committed(test))
        return test.correlation

    def _reconcile_seed_and_prove_etag(self, spec, credential, rep, key, seed,
                                       seed_body, *, next_sequence):
        """Fully settle a setup PUT and return a PROVEN current ETag.

        Routes every outcome through the reviewed state machine
        (`next_action` / `reconcile_after_ambiguous_put`) and then an
        authenticated GET. Returns only when the remote object is positively
        confirmed to be exactly `seed_body` AND carries a usable ETag;
        otherwise it settles the ledger as far as the evidence allows and
        ABANDONs — so a dependent same-key mutation is never sent on an
        unresolved or mismatched setup.
        """
        want_sha = hashlib.sha256(seed_body).hexdigest()
        want_len = len(seed_body)
        outcome = self._put_outcome(seed)
        status = seed.response.status if seed.response is not None else None

        if status is not None and 200 <= status < 300:
            obs_sha, obs_len, etag, gstate = self._authoritative_get(
                spec, credential, rep, next_sequence, key)
            self._finish(seed, resolve_committed=True)
            if gstate is RemoteState.CONFIRMED and obs_sha == want_sha \
                    and obs_len == want_len and etag:
                return etag
            self._mark(spec.id, "ABANDON")     # wrong bytes / no usable ETag
            raise ProbeAbandon(f"{spec.id}: seed not usable")

        if next_action(outcome) \
                is NextAction.RECONCILE_WITH_AUTHORITATIVE_GET:
            obs_sha, obs_len, etag, gstate = self._authoritative_get(
                spec, credential, rep, next_sequence, key)
            recon = reconcile_after_ambiguous_put(
                get_state=gstate, observed_sha256=obs_sha,
                observed_length=obs_len, intended_sha256=want_sha,
                intended_length=want_len, prior_sha256=None, prior_length=None)
            if recon is Reconciliation.RECONCILED_SUCCESS and etag:
                self._finish(seed, resolve_committed=True,
                            reconciliation=recon)
                return etag
            if recon is Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN:
                self._finish(seed, resolve_committed=False,
                            reconciliation=recon)   # proven absent
            elif recon is Reconciliation.RECONCILED_SUCCESS:
                self._finish(seed, resolve_committed=True,
                            reconciliation=recon)   # committed, no ETag
            else:
                self._finish(seed, resolve_committed=None,
                            reconciliation=recon)   # unknown → stays open
            self._mark(spec.id, "ABANDON")
            raise ProbeAbandon(f"{spec.id}: seed could not be reconciled")

        # Definite rejection or a before-request failure: nothing committed.
        self._finish(seed, resolve_committed=self._committed(seed))
        self._mark(spec.id, "ABANDON")
        raise ProbeAbandon(f"{spec.id}: seed was rejected")

    def _support_create_if_absent(self, spec, credential, rep, key) -> str:
        body = synthetic_payload("create", 256)
        create = self._dispatch(spec=spec, credential=credential,
                              repetition=rep, sequence=1, method="PUT",
                              key=key, body=body, if_none_match="*")
        sha, length, _e, _s = self._authoritative_get(
            spec, credential, rep, 2, key)
        self._finish(create, final_get_sha256=sha, final_get_len=length,
                    remote_state=RemoteState.CONFIRMED,
                    resolve_committed=self._committed(create))
        return create.correlation

    def _support_put_readback(self, spec, credential, rep, key) -> str:
        body = synthetic_payload("bytes", 256)
        put = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT", key=key, body=body)
        etag = put.response.header("ETag") if put.response is not None else None
        sha, length, _ge, _s = self._authoritative_get(
            spec, credential, rep, 2, key)
        self._finish(put, final_get_sha256=sha, final_get_len=length,
                    final_etag=(etag if spec.id == "G" else None),
                    remote_state=RemoteState.CONFIRMED,
                    resolve_committed=self._committed(put))
        return put.correlation

    def _support_production_put(self, spec, credential, rep, key) -> str:
        body = production_size_payload(f"j{rep:04d}")
        put = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT", key=key, body=body)
        self._finish(put, resolve_committed=self._committed(put))
        return put.correlation

    def _support_allowed_scope(self, spec, credential, rep, key) -> str:
        method = {"H1": "HEAD", "H2": "GET", "H3": "PUT"}[spec.id]
        if method in ("HEAD", "GET"):
            seed = self._dispatch(spec=spec, credential=credential,
                                repetition=rep, sequence=1, method="PUT",
                                key=key, body=synthetic_payload("s", 256),
                                if_none_match="*")
            self._finish(seed, resolve_committed=self._committed(seed))
            # Same rule as row A (Codex round-3 HIGH 1), applied uniformly:
            # no dependent same-key operation while the setup PUT's commit
            # state is unresolved. The dependent op here is a READ, so an
            # unresolved seed could not cause an unsafe mutation, but the
            # row would still be reading a key whose state is unknown.
            if self._put_outcome(seed) not in (
                    PutOutcome.PUT_CONFIRMED,
                    PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN):
                self._mark(spec.id, "ABANDON")
                return seed.correlation
            sent = self._dispatch(spec=spec, credential=credential,
                                repetition=rep, sequence=2, method=method,
                                key=key)
            self._finish(sent)
            return sent.correlation
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT", key=key,
                            body=synthetic_payload("scope", 256))
        self._finish(sent, resolve_committed=self._committed(sent))
        return sent.correlation

    def _support_denied_scope(self, spec, credential, rep, key) -> str:
        policy = _policy()
        cfg = {
            "H4": ("DELETE", policy.sacrificial_key, ()),
            "H5": ("GET", "", (("list-type", "2"),)),
            "H6": ("GET", policy.denied_out_of_prefix_key, ()),
            "H7": ("PUT", policy.denied_out_of_prefix_key, ()),
        }[spec.id]
        method, target_key, query = cfg
        body = synthetic_payload("denied", 256) if method == "PUT" else b""
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method=method, key=target_key,
                            query=query, body=body,
                            allow_denied_prefix_probe=(
                                target_key == policy.denied_out_of_prefix_key))
        self._assert_denied(sent)
        self._finish(sent, resolve_committed=(False if sent.is_put else None))
        return sent.correlation

    def _support_signing_ok(self, spec, credential, rep, key) -> str:
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT", key=key,
                            body=synthetic_payload("sign", 256))
        self._finish(sent, resolve_committed=self._committed(sent))
        return sent.correlation

    # ── the three signing/expiry diagnostics — internal builders only ────

    def _send_i2_unsigned_token(self, spec, credential, rep, issued) -> str:
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT",
                            key=issued.identity.key,
                            body=diagnostic_body("I2"), diagnostic="I2",
                            identity=issued.identity)
        self._finish(sent, resolve_committed=(
            self._committed(sent) if sent.response is not None else None))
        return sent.correlation

    def _send_i3_no_token(self, spec, credential, rep, issued) -> str:
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT",
                            key=issued.identity.key,
                            body=diagnostic_body("I3"), diagnostic="I3",
                            identity=issued.identity)
        self._assert_denied(sent)
        self._finish(sent, resolve_committed=False)
        return sent.correlation

    def _send_i4_expired_token(self, spec, credential, rep, issued) -> str:
        # Wait until the short-TTL credential has PROVABLY expired. The
        # transport ALSO refuses to run this row while the credential is
        # still valid, so the wait is not the only guard.
        remaining = credential.expires_at - int(self._wall_clock())
        if remaining >= 0:
            self._sleep(remaining + 2)
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="PUT",
                            key=issued.identity.key,
                            body=diagnostic_body("I4"), diagnostic="I4",
                            identity=issued.identity)
        self._assert_denied(sent)
        self._finish(sent, resolve_committed=False)
        return sent.correlation

    def _support_absent(self, spec, credential, rep, key) -> str:
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="GET", key=key)
        self._finish(sent, remote_state=classify_remote_state(
            method="GET",
            status=(sent.response.status if sent.response else None),
            error_code=(sent.parsed.code if sent.parsed else None),
            body_truncated=(sent.response.body_truncated
                            if sent.response else False)))
        return sent.correlation

    def _support_denied_contrast(self, spec, credential, rep, key) -> str:
        policy = _policy()
        sent = self._dispatch(spec=spec, credential=credential, repetition=rep,
                            sequence=1, method="GET",
                            key=policy.denied_out_of_prefix_key,
                            allow_denied_prefix_probe=True)
        self._assert_denied(sent)
        self._finish(sent)
        return sent.correlation

    def _support_throttle(self, spec, credential, rep, key) -> str:
        # HIGH 2: the first same-key write must be SERVER-OBSERVED (a
        # definite 2xx) before the second is even issued; the second must be
        # a definite 429. Anything else stops the run.
        first = self._dispatch(spec=spec, credential=credential, repetition=rep,
                             sequence=1, method="PUT", key=key,
                             body=synthetic_payload("k3a", 256))
        if self._put_outcome(first) not in (
                PutOutcome.PUT_CONFIRMED,
                PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN):
            self._finish(first, resolve_committed=self._committed(first))
            self._mark(spec.id, "ABANDON")   # first write not server-observed
            return first.correlation
        self._finish(first, resolve_committed=True)
        second = self._dispatch(spec=spec, credential=credential,
                              repetition=rep, sequence=2, method="PUT",
                              key=key, body=synthetic_payload("k3b", 256),
                              respect_guard=False)
        status = second.response.status if second.response is not None else None
        if status != 429:
            self._finish(second, resolve_committed=self._committed(second))
            self._mark(spec.id, "ABANDON")   # no definite throttle observed
            return second.correlation
        self._finish(second, resolve_committed=False)
        # The two PHYSICAL transmissions must fall inside R2's documented
        # one-write-per-second window (BLOCKER 3). If the real gap is wider,
        # the 429 is not attributable to same-key throttling and the row is
        # not evidence — stop rather than record a misleading observation.
        first_ns = first.t_request_attempt_mono_ns
        second_ns = second.t_request_attempt_mono_ns
        if type(first_ns) is not int or type(second_ns) is not int \
                or not (0 <= second_ns - first_ns <= K3_THROTTLE_WINDOW_NS):
            self._mark(spec.id, "ABANDON")
        return second.correlation

    def _assert_denied(self, sent):
        status = sent.response.status if sent.response is not None else None
        if status is not None and 200 <= status < 300:
            self._mark(sent.spec.id, "ABANDON")   # scope escape

    # ── race rows: E2, F ─────────────────────────────────────────────────

    def _run_race(self, spec, credential):
        for rep in range(1, spec.required_repetitions + 1):
            self._run_race_repetition(spec, credential, rep)
            verdict, _ = self._writer._race.verdict(spec.id)
            if verdict is Verdict.ABANDON:
                self._mark(spec.id, "ABANDON")

    def _run_race_repetition(self, spec, credential, rep):
        issued = self._writer.allocate_race(spec.id, rep)
        key = issued.identity.key
        seq = [0]

        def nxt():
            seq[0] += 1
            return seq[0]

        shared_etag = None
        absence_confirmed = None
        prior_sha = prior_len = None
        if spec.id == "E2":
            seed_body = synthetic_payload("seed", 256)
            seed = self._dispatch(spec=spec, credential=credential,
                                repetition=rep, sequence=nxt(), method="PUT",
                                key=key, body=seed_body, if_none_match="*")
            shared_etag = (seed.response.header("ETag")
                           if seed.response is not None else None)
            if self._put_outcome(seed) not in (
                    PutOutcome.PUT_CONFIRMED,
                    PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN) \
                    or shared_etag is None:
                self._finish(seed, resolve_committed=self._committed(seed))
                raise ProbeAbandon(f"E2 rep {rep}: seed not established")
            self._finish(seed, resolve_committed=True)
            prior_sha = hashlib.sha256(seed_body).hexdigest()
            prior_len = len(seed_body)
            # Separate the race writers from the seed by more than the
            # 1-write/s window, so a loser is rejected by CAS (412), never by
            # the throttle (429).
            self._same_key_guard.wait_until_writable(key)
        else:                       # F: prove the key is absent first
            _s, _l, _e, state = self._authoritative_get(
                spec, credential, rep, nxt(), key)
            if state is not RemoteState.ABSENT:
                raise ProbeAbandon(f"F rep {rep}: key was not proven absent")
            absence_confirmed = True

        body1 = synthetic_payload("w1", 256)
        body2 = synthetic_payload("w2", 288)
        pair_id = self._writer.ledger.reserve_race_pair_same_key(
            key, len(body1), len(body2))

        generation = f"gen-{rep:04d}"
        release = {}
        barrier = threading.Barrier(
            2, action=lambda: release.__setitem__("t", self._monotonic()))
        results = {}
        seqs = {"w1": nxt(), "w2": nxt()}

        def writer_thread(name, body):
            join_ns = self._monotonic()
            barrier.wait()
            if_match = shared_etag if spec.id == "E2" else None
            if_none_match = "*" if spec.id == "F" else None
            sent = self._dispatch(
                spec=spec, credential=credential, repetition=rep,
                sequence=seqs[name], method="PUT", key=key, body=body,
                if_match=if_match, if_none_match=if_none_match,
                respect_guard=False, charge_ledger=False)
            results[name] = (sent, join_ns, body)

        threads = [threading.Thread(target=writer_thread, args=(n, b))
                   for n, b in (("w1", body1), ("w2", body2))]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        release_ns = release["t"]
        final_sha, final_len, final_etag, final_state = \
            self._authoritative_get(spec, credential, rep, nxt(), key)

        # LEDGER SETTLEMENT reconciles against the authenticated final GET
        # (HIGH 1): a lost-response writer that actually committed is settled
        # correctly, and an unreconcilable state leaves the pair open and
        # ABANDONs — the ledger never undercounts a possibly-committed body.
        ledger_winner = self._reconcile_race_ledger(
            body1, body2, final_state, final_sha, final_len,
            prior_sha, prior_len)
        writers = []
        for name in ("w1", "w2"):
            sent, join_ns, body = results[name]
            status = sent.response.status if sent.response is not None else None
            etag = (sent.response.header("ETag")
                    if sent.response is not None else None)
            writers.append(RaceWriter(
                writer_id=name, http_status=status,
                payload_sha256=hashlib.sha256(body).hexdigest(),
                payload_length=len(body), returned_etag=etag,
                if_match=(shared_etag if spec.id == "E2" else None),
                if_none_match=("*" if spec.id == "F" else None),
                barrier_generation=generation, barrier_join_mono_ns=join_ns,
                send_mono_ns=sent.t_request_attempt_mono_ns))

        for name in ("w1", "w2"):
            self._finish(results[name][0])

        # A writer that never reached conn.request, or a send skew beyond
        # policy (Codex BLOCKER 2: a writer delayed after the barrier), makes
        # this no valid race. Settle the ledger if we can, then ABANDON.
        send1 = writers[0].send_mono_ns
        send2 = writers[1].send_mono_ns
        skew_ok = (type(send1) is int and type(send2) is int
                   and abs(send1 - send2) <= _policy().max_race_send_skew_ns
                   and send1 >= release_ns and send2 >= release_ns)
        if ledger_winner is not None:
            self._writer.ledger.resolve_race_pair(pair_id, winner=ledger_winner)
        if not skew_ok:
            self._mark(spec.id, "ABANDON")
            return
        if ledger_winner is None:
            # Could not reconcile a settlement; the pair stays open and the
            # finalize invariant will ABANDON. Stop now.
            self._mark(spec.id, "ABANDON")
            return

        repetition = RaceRepetition(
            identity=issued.identity, shared_original_etag=shared_etag,
            absence_confirmed=absence_confirmed,
            barrier=RaceBarrierEvidence(generation_id=generation,
                                        release_mono_ns=release_ns),
            writers=tuple(writers), final_state=final_state,
            final_sha256=final_sha, final_length=final_len,
            final_etag=final_etag)
        self._writer.write_race_record(issued, repetition)

    def _reconcile_race_ledger(self, body1, body2, final_state, final_sha,
                               final_len, prior_sha, prior_len):
        """Return the RacePairWinner the authenticated final GET proves, or
        None when no single committed state can be established (→ ABANDON).
        Never guesses: an unexpected final state yields None, keeping both
        writers' bytes conservatively charged."""
        b1s, b1l = hashlib.sha256(body1).hexdigest(), len(body1)
        b2s, b2l = hashlib.sha256(body2).hexdigest(), len(body2)
        if final_state is RemoteState.CONFIRMED and final_sha is not None:
            if final_sha == b1s and final_len == b1l:
                return RacePairWinner.WRITER_1
            if final_sha == b2s and final_len == b2l:
                return RacePairWinner.WRITER_2
            if prior_sha is not None and final_sha == prior_sha \
                    and final_len == prior_len:
                return RacePairWinner.NONE
            return None
        if final_state is RemoteState.ABSENT and prior_sha is None:
            return RacePairWinner.NONE
        return None

    # ── the run ──────────────────────────────────────────────────────────

    def run(self) -> dict:
        try:
            for group, test_ids in sorted(credential_groups().items()):
                credential = self._mint_child(group)
                for test_id in test_ids:
                    spec = test_spec(test_id)
                    self._planner.assert_credential_matches_test(
                        credential, test_id)
                    if spec.category == "semantic":
                        self._run_semantic(spec, credential)
                    elif spec.category == "race":
                        self._run_race(spec, credential)
                    else:
                        self._run_support(spec, credential)
        except ProbeAbandon as exc:
            self._abandon_reason = str(exc)
        except (CapExceeded, LedgerPoisoned) as exc:
            self._abandon_reason = str(exc)

        # DEFENCE IN DEPTH ONLY (Codex round-3 BLOCKER 1). The AUTHORITATIVE
        # rejection of an unresolved reservation now lives in
        # derive_run_summary(), which reads the ledger itself and cannot be
        # bypassed by any caller. This merely surfaces a human-readable
        # reason alongside that already-ABANDON verdict.
        open_puts, open_pairs = self._writer.ledger.open_reservation_counts()
        if (open_puts or open_pairs) and not self._abandon_reason:
            self._abandon_reason = (
                f"unresolved reservations at finalize: {open_puts} puts, "
                f"{open_pairs} race pairs")

        result = self._writer.finalize()
        # A terminal safety violation or an open reservation only ever makes
        # the reported verdict WORSE — it can never turn a non-PASS to PASS.
        if self._abandon_reason and result.get("verdict") != "ABANDON":
            result["verdict"] = "ABANDON"
        result["run_id"] = self._writer.run_id
        result["evidence_dir"] = self._writer.run_dir
        result["ledger"] = self._writer.ledger.snapshot()
        result["per_test"] = self.per_test_display()
        result["abandon_reason"] = self._abandon_reason
        return result


# ─────────────────────────────────────────────────────────────────────────
# Execution gates + plan mode
# ─────────────────────────────────────────────────────────────────────────

class ExecutionGates(NamedTuple):
    execute: bool
    bucket: str | None
    confirmation: str | None
    authorized_by_adam: bool
    account_id: str | None
    credentials_file: str | None

    def assert_may_execute(self) -> None:
        policy = _policy()
        _exact_bool(self.execute, "execute")
        _exact_bool(self.authorized_by_adam, "authorized_by_adam")
        if not self.execute:
            raise MissingAuthorization("--execute was not supplied")
        if not self.authorized_by_adam:
            raise MissingAuthorization("--authorized-by-adam was not supplied")
        if type(self.confirmation) is not str \
                or self.confirmation != policy.execute_confirmation:
            raise MissingAuthorization(
                "the exact confirmation string was not supplied")
        if type(self.bucket) is not str or self.bucket != policy.bucket:
            raise ProductionNameDetected(
                f"--bucket {self.bucket!r} is not the disposable probe bucket")
        if self.account_id is None:
            raise MissingAuthorization("--account-id is required")
        build_endpoint_host(self.account_id)
        if type(self.credentials_file) is not str or not self.credentials_file:
            raise MissingAuthorization("--credentials-file is required")
        if not os.path.isfile(self.credentials_file):
            raise MissingAuthorization(
                "the disposable credential file does not exist; no probe "
                "credentials have been created")


def planned_tests() -> tuple:
    """Display rows, derived from the ONE matrix."""
    return tuple((spec.id, spec.group, spec.description)
                 for spec in _policy().matrix)


PLANNED_TESTS = planned_tests()


def render_plan(*, bucket, account_id) -> str:
    policy = _policy()
    lines = [
        "Bible PAL — DISPOSABLE R2 CAS PROBE (PLAN MODE)",
        "=" * 62,
        "NO SOCKETS ARE OPENED IN THIS MODE.",
        "LIVE EXECUTION NOT PERFORMED IN PLAN MODE.",
        "",
        f"  probe bucket     : {policy.bucket} (immutable policy constant)",
        f"  denied names     : {list(policy.denied_tokens)}",
        f"  key prefix       : {policy.key_prefix}",
        f"  requested bucket : {bucket!r}",
        "  endpoint         : "
        + ("<not resolved: no account id supplied>" if not account_id
           else "https://<account-id>.r2.cloudflarestorage.com"),
        "",
        "Hard caps (FIXED — no extension path exists):",
    ]
    caps = policy.caps
    for name, value in zip(caps._fields, caps):
        lines.append(f"  {name:<28} {value}")
    lines += ["", "Planned tests (derived from the single test matrix):"]
    for spec in policy.matrix:
        lines.append(f"  [{spec.group:<8}] {spec.id:<4} {spec.description}")
    lines += [
        "",
        "Semantic acceptance: EVERY valid repetition of "
        + ", ".join(semantic_test_ids())
        + " must return 412 with a proven-unchanged final state.",
        "Any observed mutation, and any 2xx on a blocked precondition, is "
        "ABANDON-class",
        "evidence and cannot be classified away as an INVALID_THROTTLED "
        "repetition.",
        "",
        "Execution requires ALL of: --execute --authorized-by-adam "
        "--confirm <exact string> --bucket " + policy.bucket + " "
        "--account-id <id> --credentials-file <path>",
        "With every gate satisfied, live execution runs ONLY against the "
        "disposable bucket " + policy.bucket + " using bucket-scoped child "
        "credentials minted from the supplied disposable parent token.",
        "It NEVER touches production; production R2 publication remains "
        "BLOCKED.",
    ]
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="probe_r2_cas.py",
        description="Disposable R2 CAS probe. Plan/offline mode by default.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--plan", action="store_true", default=True,
                      help="default: describe the probe, open zero sockets")
    mode.add_argument("--execute", action="store_true",
                      help="run the live probe against the DISPOSABLE bucket "
                           "(requires every authorization gate)")
    parser.add_argument("--bucket", default=None)
    parser.add_argument("--account-id", default=None)
    parser.add_argument("--confirm", default=None)
    parser.add_argument("--authorized-by-adam", action="store_true")
    parser.add_argument("--credentials-file", default=None)
    parser.add_argument("--evidence-root", default=None,
                        help=f"default: {default_evidence_root()}")
    return parser


def _new_run_id() -> str:
    """A unique, grammar-valid run id. No randomness is required: the
    process id plus a monotonic-derived suffix is unique per invocation,
    and EvidenceWriter hard-errors if the run directory already exists."""
    suffix = int(time.time()) & 0xffffffff
    run_id = f"run-{os.getpid()}-{suffix:x}"
    if not _grammar().run_id.fullmatch(run_id):        # pragma: no cover
        raise SafetyBarrierTripped("generated run id is not grammar-valid")
    return run_id


def _print_safe_summary(result) -> None:
    """Print ONLY non-secret run facts: no account id, no endpoint host,
    no credential material — those never enter the result dict."""
    ledger = result.get("ledger", {})
    print("Bible PAL — DISPOSABLE R2 CAS PROBE (LIVE RESULT)")
    print("=" * 62)
    print(f"  run id          : {result.get('run_id')}")
    print(f"  evidence dir    : {result.get('evidence_dir')}")
    print(f"  manifest sha256 : {result.get('manifest_sha256')}")
    print(f"  put attempts    : {ledger.get('put_operation_count')}")
    print(f"  production puts : {ledger.get('production_size_puts')}")
    print(f"  get/head        : {ledger.get('get_head_count')}")
    print(f"  object keys     : {ledger.get('object_count')}")
    print(f"  uploaded bytes  : {ledger.get('uploaded_bytes')}")
    print(f"  ledger poisoned : {ledger.get('poisoned')}")
    verdict = result.get("verdict")
    print("")
    print(f"  VERDICT         : {verdict}")
    print(f"  GO/NO-GO        : {'GO' if verdict == 'PASS' else 'NO-GO'}")
    print("  Production R2 publication remains BLOCKED.")


def _verdict_exit_code(verdict) -> int:
    if verdict == "PASS":
        return EXIT_OK
    if verdict == "ABANDON":
        return EXIT_ABANDON
    return EXIT_TEST_FAILURE


def run_live_probe(*, account_id, credentials_file, evidence_root=None,
                   connection_factory=None, run_id=None) -> dict:
    """Build the writer + runner and execute the matrix. `connection_factory`
    is a TEST SEAM: when None (the CLI default) the ONLY real socket path,
    `real_connection_factory`, is installed and the ambient environment is
    scrubbed first; offline tests pass a fake factory and no scrub occurs."""
    parent = load_probe_credentials_file(credentials_file)
    root = evidence_root if evidence_root is not None else default_evidence_root()
    assert_no_denied_names(root)
    run_id = run_id if run_id is not None else _new_run_id()

    live = connection_factory is None
    if live:
        home = os.environ.get("HOME") or os.path.expanduser("~")
        # Resolve the evidence root against the real HOME before scrubbing.
        if evidence_root is None:
            root = os.path.join(home, ".local", "state", "bible-pal")
        # A clean, dedicated process: drop proxy/AWS/CF/R2/wrangler vars so
        # no ambient credential or proxy can influence the live requests.
        scrub_process_environment(home)
        connection_factory = real_connection_factory

    writer = EvidenceWriter(root, run_id, secrets=parent.secret_values(),
                            phase="T")
    runner = LiveProbeRunner(
        account_id=account_id, parent=parent, writer=writer,
        connection_factory=connection_factory)
    return runner.run()


def main(argv=None, *, connection_factory=None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    try:
        assert_no_denied_names(args.bucket, args.account_id,
                               args.credentials_file, args.evidence_root)

        if not args.execute:
            print(render_plan(bucket=args.bucket, account_id=args.account_id))
            return EXIT_OK

        gates = ExecutionGates(
            execute=True, bucket=args.bucket, confirmation=args.confirm,
            authorized_by_adam=args.authorized_by_adam,
            account_id=args.account_id,
            credentials_file=args.credentials_file)
        # Validates every authorization gate AND that the credential file
        # exists. Only after this can a socket ever be constructed.
        gates.assert_may_execute()

        result = run_live_probe(
            account_id=args.account_id,
            credentials_file=args.credentials_file,
            evidence_root=args.evidence_root,
            connection_factory=connection_factory)
        _print_safe_summary(result)
        return _verdict_exit_code(result.get("verdict"))

    except ProbeError as exc:
        print(f"REFUSED [{type(exc).__name__}]: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
