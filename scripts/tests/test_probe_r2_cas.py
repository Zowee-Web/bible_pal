#!/usr/bin/env python3
"""Offline verification for the disposable R2 CAS probe.

STRUCTURAL NO-NETWORK GUARANTEE
-------------------------------
These tests do not merely promise not to contact R2. Several install a
socket class that RAISES on construction, so any code path that attempted
to open a connection would fail loudly rather than succeed quietly. The
probe's default connection factory refuses to build a connection at all,
there is no production endpoint default, and live execution is disabled
unconditionally.

THREAT-MODEL NOTE. The source/AST structural checks near the end of this
file are DEFENCE IN DEPTH, not the primary boundary. They can be evaded by
arbitrary dynamic Python, which is explicitly out of scope (see the
probe's module header). The primary boundary is: closure-captured
immutable policy + exact-type validation at every wire boundary.

Nothing here reads the shipped catalog manifest, writes inside the
repository, or needs the network.

Run:
    python3 -m unittest scripts.tests.test_probe_r2_cas -v
"""

from __future__ import annotations

import ast
import base64
import binascii
import builtins
import hashlib
import io
import json
import os
import pathlib
import socket
import stat
import sys
import tempfile
import threading
import unittest
from typing import NamedTuple
from unittest import mock

_HERE = pathlib.Path(__file__).resolve().parent
_SCRIPTS = _HERE.parent
sys.path.insert(0, str(_SCRIPTS))
sys.path.insert(0, str(_HERE))

import probe_r2_cas as probe  # noqa: E402
import independent_verifiers as iv  # noqa: E402


PROBE_BUCKET = "bible-pal-cas-probe"
PRODUCTION_BUCKET = "bible" "-pal-audio"  # split so this file is not a hit
ACCOUNT_ID = "0" * 32
OTHER_ACCOUNT_ID = "9f3c" + "a" * 28
ENDPOINT_HOST = f"{ACCOUNT_ID}.r2.cloudflarestorage.com"
AMZ_DATE = "20260814T120000Z"
AKID = "3d1a2b4c5d6e7f8091a2b3c4d5e6f708"
SECRET = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
RUN_ID = "run-abc"
NONCE = f"{RUN_ID}:000001"
#: Credentials are minted at exactly AMZ_DATE, so a zero signing offset
#: puts the request inside the validity window.
CRED_NOW = probe._amz_date_to_epoch(AMZ_DATE)


def amz_date_at(epoch):
    """Format an epoch as the SigV4 timestamp the probe expects."""
    import datetime
    return datetime.datetime.fromtimestamp(
        epoch, datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

def probe_ast(strip_docstrings: bool = True) -> ast.Module:
    tree = ast.parse((_SCRIPTS / "probe_r2_cas.py").read_text(encoding="utf-8"))
    if strip_docstrings:
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                                 ast.AsyncFunctionDef)):
                body = getattr(node, "body", None)
                if (body and isinstance(body[0], ast.Expr)
                        and isinstance(body[0].value, ast.Constant)
                        and isinstance(body[0].value.value, str)):
                    body.pop(0)
    return tree


def probe_string_literals() -> list:
    return [n.value for n in ast.walk(probe_ast())
            if isinstance(n, ast.Constant) and isinstance(n.value, str)]


def probe_code_signature() -> str:
    return ast.dump(probe_ast())


class SocketsForbidden(AssertionError):
    pass


class _ForbiddenSocket:
    def __init__(self, *a, **k):
        raise SocketsForbidden("a socket was constructed during offline test")


def no_sockets():
    def _forbid(*a, **k):
        raise SocketsForbidden("socket.create_connection was called")
    return mock.patch.multiple(socket, socket=_ForbiddenSocket,
                               create_connection=_forbid)


class RecordingFactory:
    """Records every call. The factory-call count must remain exactly zero
    whenever a barrier should have fired first."""

    def __init__(self, connection=None):
        self.calls = []
        self._connection = connection

    def __call__(self, host, timeout):
        self.calls.append((host, timeout))
        if self._connection is None:
            raise SocketsForbidden("factory invoked with no connection set")
        return self._connection


class FakeResponse:
    def __init__(self, status, headers=(), body=b""):
        self.status = status
        self._headers = list(headers)
        self._body = body

    def getheaders(self):
        return list(self._headers)

    def read(self, amt=None):
        return self._body if amt is None else self._body[:amt]


class FakeConnection:
    def __init__(self, *, response=None, raise_on_request=None,
                 raise_on_getresponse=None):
        self.response = response
        self.raise_on_request = raise_on_request
        self.raise_on_getresponse = raise_on_getresponse
        self.requests = []
        self.closed = False

    def request(self, method, path, body=None, headers=None):
        if self.raise_on_request is not None:
            raise self.raise_on_request
        self.requests.append((method, path, body, dict(headers or {})))

    def getresponse(self):
        if self.raise_on_getresponse is not None:
            raise self.raise_on_getresponse
        return self.response

    def close(self):
        self.closed = True


def make_transport(connection=None, factory=None, wall_clock=None, **kw):
    # Default the wall clock to the AMZ_DATE epoch so sign_and_send's
    # freshness/skew checks pass for a credential minted at that time.
    return probe.R2Transport(
        endpoint_host=ENDPOINT_HOST,
        connection_factory=factory or RecordingFactory(connection),
        monotonic=lambda: 0,
        wall_clock=wall_clock or (lambda: float(AMZ_EPOCH)), **kw)


def probe_key(test_id="B", rep=1, phase="t", run_id=RUN_ID):
    return probe.expected_key_for(phase=phase, run_id=run_id,
                                  test_id=test_id, repetition=rep)


def probe_target(method="PUT", key=None, query=()):
    if key is None:
        key = probe_key()
    return probe.RequestTarget(method=method, bucket=PROBE_BUCKET, key=key,
                               query=tuple(query))


def sign(target, body=b"", session_token=None, extra_headers=None,
         include_content_md5=False, host=ENDPOINT_HOST):
    return probe.sign_request(
        target=target, host=host, access_key_id=AKID,
        secret_access_key=SECRET, session_token=session_token, body=body,
        amz_date=AMZ_DATE, extra_headers=extra_headers,
        include_content_md5=include_content_md5)


def support_specs():
    return [s for s in probe.TEST_MATRIX
            if s.category not in ("semantic", "race")]


class SupportEvidence(NamedTuple):
    """The request/response facts that make one support row DERIVE valid.

    This mirrors the probe's per-test derivation table from the outside: if
    the table changes, these fixtures stop deriving valid and the tests go
    red. Nothing here asserts an outcome — the outcome is whatever the
    probe derives from these facts. In particular there is no
    `session_token_present` knob any more: token presence is whatever the
    signed request really carried.
    """

    method: str = "PUT"
    key: str | None = None            # None -> this repetition's own key
    query: tuple = ()
    body: bytes = b"x"
    if_match: str | None = None
    if_none_match: str | None = None
    #: "signed" -> real child credential in SignedHeaders (the normal case)
    #: "unsigned" -> token physically on the wire but NOT signed (I2 only)
    #: "omitted" -> no token at all, credential still recorded (I3)
    #: "none" -> no child credential involved at all
    token_mode: str = "signed"
    #: Seconds to add to the credential's issue time when signing. Past the
    #: TTL this makes the request provably expired (I4).
    signing_offset: int = 0
    status: int = 200
    etag: str | None = '"e"'
    error_code: str | None = None
    readback: bool = False            # final read returns exactly the body
    final_etag: str | None = None
    remote_state: str | None = None


_SACRIFICIAL = probe._policy().sacrificial_key
_OUT_OF_PREFIX = probe._policy().denied_out_of_prefix_key
_PRODUCTION_BODY = b"J" * probe.PRODUCTION_BODY_BYTES
_EXPIRY_TTL = probe._policy().expiry_group_ttl_seconds

#: One fixture per support matrix row.
SUPPORT_EVIDENCE = {
    "A": SupportEvidence(if_match='"e0"', readback=True, token_mode="none"),
    "C": SupportEvidence(if_none_match="*", readback=True,
                         token_mode="none"),
    "G": SupportEvidence(readback=True, final_etag='"e"', token_mode="none"),
    "H1": SupportEvidence(method="HEAD"),
    "H2": SupportEvidence(method="GET"),
    "H3": SupportEvidence(method="PUT"),
    "H4": SupportEvidence(method="DELETE", key=_SACRIFICIAL, status=403,
                          etag=None, error_code="AccessDenied"),
    # A real ListObjectsV2: bucket-level GET with list-type=2.
    "H5": SupportEvidence(method="GET", key="",
                          query=(("list-type", "2"),), status=403,
                          etag=None, error_code="AccessDenied"),
    "H6": SupportEvidence(method="GET", key=_OUT_OF_PREFIX, status=403,
                          etag=None, error_code="AccessDenied"),
    "H7": SupportEvidence(method="PUT", key=_OUT_OF_PREFIX, status=403,
                          etag=None, error_code="AccessDenied"),
    "I1": SupportEvidence(),
    "I2": SupportEvidence(token_mode="unsigned"),
    "I3": SupportEvidence(token_mode="omitted", status=403, etag=None,
                          error_code="AccessDenied"),
    # Signed after the T-EXPIRY credential's TTL has elapsed.
    "I4": SupportEvidence(signing_offset=_EXPIRY_TTL + 5, status=403,
                          etag=None, error_code="ExpiredToken"),
    "K1": SupportEvidence(method="GET", status=404, etag=None,
                          error_code="NoSuchKey"),
    "K2": SupportEvidence(method="GET", key=_OUT_OF_PREFIX, status=403,
                          etag=None, error_code="AccessDenied"),
    # Sequence 2 of a same-key PUT pair; write_support_repetition lays down
    # the earlier attempt first.
    "K3": SupportEvidence(status=429, etag=None, error_code="SlowDown",
                          token_mode="none"),
    "J": SupportEvidence(body=_PRODUCTION_BODY, token_mode="none"),
    "L": SupportEvidence(readback=True, token_mode="none"),
    "X1": SupportEvidence(if_none_match="*", readback=True,
                          remote_state="CONFIRMED", token_mode="none"),
    "X2": SupportEvidence(if_none_match="*", readback=True,
                          remote_state="CONFIRMED", token_mode="none"),
}


def group_credential(group, now=CRED_NOW):
    """The validated child credential a group's requests must carry."""
    return probe.mint_probe_credential(
        group=group, account_id=ACCOUNT_ID, parent_access_key_id=AKID,
        parent_secret_access_key=SECRET, now=now)


def sign_support_request(spec, key, facts):
    """Sign exactly what the row's fixture says went on the wire, and
    return (signed, credential) for build_request_record."""
    extra = {}
    if facts.if_match is not None:
        extra["if-match"] = facts.if_match
    if facts.if_none_match is not None:
        extra["if-none-match"] = facts.if_none_match
    credential = (None if facts.token_mode == "none"
                  else group_credential(spec.group))
    amz_date = (AMZ_DATE if credential is None
                else amz_date_at(credential.issued_at + facts.signing_offset))
    signed = probe.sign_request(
        target=probe.RequestTarget(method=facts.method, bucket=PROBE_BUCKET,
                                   key=key, query=tuple(facts.query)),
        host=ENDPOINT_HOST,
        access_key_id=(AKID if credential is None
                       else credential.access_key_id),
        secret_access_key=(SECRET if credential is None
                           else credential.secret_access_key),
        session_token=(credential.session_token
                       if credential is not None
                       and facts.token_mode == "signed" else None),
        unsigned_session_token=(credential.session_token
                                if credential is not None
                                and facts.token_mode == "unsigned" else None),
        body=facts.body, amz_date=amz_date,
        extra_headers=extra or None)
    return signed, credential


def write_correlated_evidence(w, spec, rep, *, sequence=1, facts=None):
    """Persist the REQUEST_RECORD + RESPONSE_RECORD pair for one repetition
    and return their shared correlation id."""
    facts = SUPPORT_EVIDENCE[spec.id] if facts is None else facts
    key = facts.key if facts.key is not None else probe_key(
        spec.id, rep, phase=w._phase.lower(), run_id=w.run_id)
    signed, credential = sign_support_request(spec, key, facts)
    w.write_request_record(probe.build_request_record(
        phase=w._phase, run_id=w.run_id, group=spec.group, test_id=spec.id,
        repetition=rep, sequence=sequence, endpoint_host=ENDPOINT_HOST,
        signed=signed, credential=credential))
    headers = () if facts.etag is None else (("ETag", facts.etag),)
    body = (b"" if facts.error_code is None else
            f"<Error><Code>{facts.error_code}</Code></Error>".encode())
    resp = probe.RawResponse(status=facts.status, headers=headers, body=body,
                             body_truncated=False, t_request_start_mono_ns=1,
                             t_response_end_mono_ns=2)
    record = probe.build_response_record(
        phase=w._phase, run_id=w.run_id, group=spec.group, test_id=spec.id,
        repetition=rep, sequence=sequence, response=resp,
        parsed=probe.parse_s3_error(body) if body else None,
        repetition_status=None,
        final_get_sha256=(hashlib.sha256(facts.body).hexdigest()
                          if facts.readback else None),
        final_get_len=len(facts.body) if facts.readback else None,
        remote_state=(probe.RemoteState(facts.remote_state)
                      if facts.remote_state else None))
    if facts.final_etag is not None:
        record["final_etag"] = facts.final_etag
    w.write_response_record(record)
    return probe.Correlation(
        phase=w._phase, run_id=w.run_id, test_id=spec.id, repetition=rep,
        sequence=sequence).serialize()


def completion_from_support_evidence(case, specs=None, facts_for=None):
    """Drive real support-row evidence through a real EvidenceWriter and
    count the DERIVED results. Used wherever a test needs a fully complete
    support matrix without asserting any outcome itself."""
    tmp = tempfile.TemporaryDirectory()
    case.addCleanup(tmp.cleanup)
    w = probe.EvidenceWriter.for_testing(os.path.join(tmp.name, "bp"), RUN_ID)
    completion = probe.MatrixCompletion()
    for spec in (support_specs() if specs is None else specs):
        for rep in range(1, spec.required_repetitions + 1):
            facts = None if facts_for is None else facts_for(spec)
            relative = write_support_repetition(w, spec, rep, facts=facts)
            with open(os.path.join(w.run_dir, relative),
                      encoding="utf-8") as fh:
                completion.count_persisted_test_result(json.load(fh))
    return completion


def write_support_repetition(w, spec, rep, *, sequence=None, facts=None,
                             prior_same_key_put=None):
    """Persist one support-row repetition end to end through the writer:
    REQUEST_RECORD, RESPONSE_RECORD, then the DERIVED TEST_RESULT_RECORD.

    K3 needs TWO same-key PUTs, so unless told otherwise it lays down the
    first attempt (sequence 1) before the throttled one (sequence 2).
    """
    prior = (spec.id == "K3" if prior_same_key_put is None
             else prior_same_key_put)
    if prior:
        write_correlated_evidence(
            w, spec, rep, sequence=1,
            facts=SUPPORT_EVIDENCE["K3"]._replace(status=200, etag='"e"',
                                                  error_code=None))
        sequence = 2 if sequence is None else sequence
    sequence = 1 if sequence is None else sequence
    corr = write_correlated_evidence(w, spec, rep, sequence=sequence,
                                     facts=facts)
    return w.write_test_result_record(w.allocate_semantic(spec.id, rep),
                                      evidence_ref=corr)


def make_credential(group="T-CAS-1", now=1_786_000_000):
    return probe.mint_probe_credential(
        group=group, account_id=ACCOUNT_ID, parent_access_key_id=AKID,
        parent_secret_access_key=SECRET, now=now)


# A credential whose validity window contains AMZ_DATE, so sign_and_send's
# full-credential transport validation passes.
AMZ_EPOCH = probe._amz_date_to_epoch(AMZ_DATE)


def make_transport_credential(group="T-CAS-1"):
    return probe.mint_probe_credential(
        group=group, account_id=ACCOUNT_ID, parent_access_key_id=AKID,
        parent_secret_access_key=SECRET, now=AMZ_EPOCH)


class EvilStr(str):
    """A str subclass whose format/representation differs from its value."""

    def __new__(cls, real, shown):
        obj = super().__new__(cls, real)
        obj._shown = shown
        return obj

    def __str__(self):
        return self._shown

    def __format__(self, spec):
        return self._shown


class EvilDict(dict):
    pass


class EvilRepr:
    def __str__(self):
        return PRODUCTION_BUCKET

    def __repr__(self):
        return PRODUCTION_BUCKET


# ═══════════════════════════════════════════════════════════════════════════
# BLOCKER 1 — policy globals are immutable in effect
# ═══════════════════════════════════════════════════════════════════════════

class PolicyImmutabilityTests(unittest.TestCase):
    """Rebinding exported, public-looking policy names must change nothing
    that is enforced."""

    #: Names rebindable to unsafe values, including the load-bearing
    #: transport/parse constants (BLOCKER 2) and the policy TYPES the
    #: closure references (BLOCKER 1).
    POLICY_NAMES = (
        "PROBE_BUCKET", "DENIED_NAME_TOKENS", "PROBE_KEY_PREFIX",
        "SACRIFICIAL_KEY", "DENIED_OUT_OF_PREFIX_KEY",
        "PRODUCTION_BODY_BYTES", "PROBE_ACTIONS", "PROBE_CREDENTIAL_SCOPE",
        "PROBE_CREDENTIAL_PREFIXES", "GROUP_TTL_SECONDS",
        "EXPIRY_GROUP_TTL_SECONDS", "EXPIRY_GROUP", "EXECUTE_CONFIRMATION",
        "ALLOWED_EXTRA_HEADERS", "TRANSPORT_OWNED_HEADERS", "TEST_MATRIX",
        "SEMANTIC_TESTS", "RACE_TESTS", "PLANNED_TESTS",
        "SEMANTIC_REQUIRED_VALID", "SEMANTIC_MAX_ATTEMPTS",
        "MAX_ERROR_BODY_BYTES", "MAX_RESPONSE_BODY_BYTES",
        "SIGV4_SERVICE", "R2_REGION", "MULTIPART_QUERY_MARKERS",
        "SCRUB_EXACT", "SCRUB_PREFIXES", "_Policy", "_Caps", "TestSpec",
        # Round-6 additions (Codex HIGH).
        "AMBIGUOUS_OUTCOMES", "DEFINITE_NO_MUTATION_OUTCOMES",
        "MAX_EVIDENCE_FILE_BYTES", "TEST_RESULT_OUTCOMES", "RECORD_KINDS",
        "ACCEPTANCE_RECORD_KINDS", "ISSUANCE_KIND_FOR_RECORD",
        "INCONCLUSIVE", "MANIFEST_FILENAME", "_RECORD_KIND_DIRS",
        "_RAW_HEX_PAIRS",
    )

    def setUp(self):
        self._saved = {name: getattr(probe, name)
                       for name in self.POLICY_NAMES
                       if hasattr(probe, name)}
        self.addCleanup(self._restore)

    def _restore(self):
        for name, value in self._saved.items():
            setattr(probe, name, value)

    def _subvert_everything(self):
        """Rebind every exported policy name — and the policy TYPES the
        closure references — to unsafe/broader values."""
        probe.PROBE_BUCKET = PRODUCTION_BUCKET
        probe.DENIED_NAME_TOKENS = ()
        probe.PROBE_KEY_PREFIX = ""
        probe.SACRIFICIAL_KEY = "anything"
        probe.DENIED_OUT_OF_PREFIX_KEY = "anything"
        probe.PRODUCTION_BODY_BYTES = 1
        probe.PROBE_ACTIONS = ("DeleteObject", "ListObjectsV2")
        probe.PROBE_CREDENTIAL_SCOPE = "admin-read-write"
        probe.PROBE_CREDENTIAL_PREFIXES = ("",)
        probe.GROUP_TTL_SECONDS = 86400
        probe.EXPIRY_GROUP_TTL_SECONDS = 86400
        probe.EXPIRY_GROUP = "T-CAS-1"
        probe.EXECUTE_CONFIRMATION = "yes"
        probe.ALLOWED_EXTRA_HEADERS = frozenset({"host", "authorization"})
        probe.TRANSPORT_OWNED_HEADERS = frozenset()
        probe.TEST_MATRIX = ()
        probe.SEMANTIC_TESTS = ()
        probe.RACE_TESTS = ()
        probe.PLANNED_TESTS = ()
        probe.SEMANTIC_REQUIRED_VALID = 1
        probe.SEMANTIC_MAX_ATTEMPTS = 1000
        # BLOCKER 2 — load-bearing transport/parse constants.
        probe.SIGV4_SERVICE = "evil"
        probe.R2_REGION = "evil"
        probe.MULTIPART_QUERY_MARKERS = ()
        probe.MAX_ERROR_BODY_BYTES = 0
        probe.MAX_RESPONSE_BODY_BYTES = 1
        probe.SCRUB_EXACT = ()
        probe.SCRUB_PREFIXES = ()
        # BLOCKER 1 — the policy TYPES the closure names.
        probe._Policy = None
        probe._Caps = None
        probe.TestSpec = None
        # Round-6 HIGH — the last exported collections used near safety
        # control flow and evidence enforcement.
        probe.AMBIGUOUS_OUTCOMES = frozenset()
        probe.DEFINITE_NO_MUTATION_OUTCOMES = frozenset()
        probe.MAX_EVIDENCE_FILE_BYTES = 1
        probe.TEST_RESULT_OUTCOMES = frozenset()
        probe.RECORD_KINDS = frozenset()
        probe.ACCEPTANCE_RECORD_KINDS = frozenset()
        probe.ISSUANCE_KIND_FOR_RECORD = {}
        # The derivation/layout constants found by the round-6 sweep. A
        # "successful" INCONCLUSIVE would turn every failed derivation into
        # a win; an empty raw/hex pair list would disable MEDIUM 1.
        probe.INCONCLUSIVE = probe.TestResultDerivation(
            "SCOPE_DENIED_OK", True, True)
        probe.MANIFEST_FILENAME = "notes.txt"
        probe._RECORD_KIND_DIRS = {}
        probe._RAW_HEX_PAIRS = ()

    def test_rebinding_ambiguous_outcomes_cannot_change_next_action(self):
        """HIGH: next_action matches the enum exhaustively, so emptying the
        exported set cannot turn an ambiguous PUT into a plain CONTINUE."""
        ambiguous = (probe.PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN,
                     probe.PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN,
                     probe.PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN,
                     probe.PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN)
        before = {o: probe.next_action(o) for o in probe.PutOutcome}
        self._subvert_everything()
        for outcome in ambiguous:
            with self.subTest(outcome=outcome):
                self.assertIs(probe.next_action(outcome),
                              probe.NextAction.RECONCILE_WITH_AUTHORITATIVE_GET)
        self.assertEqual({o: probe.next_action(o) for o in probe.PutOutcome},
                         before)

    def test_next_action_covers_every_outcome_exhaustively(self):
        for outcome in probe.PutOutcome:
            with self.subTest(outcome=outcome):
                self.assertIs(type(probe.next_action(outcome)),
                              probe.NextAction)
        # And it never reads the exported set at all.
        source = ast.dump(probe_ast())
        body = source[source.index("next_action"):]
        self.assertNotIn("AMBIGUOUS_OUTCOMES",
                         body[:body.index("reconcile_after_ambiguous_put")])

    def test_rebinding_evidence_size_bound_changes_nothing(self):
        """HIGH: the bound comes from captured policy, so shrinking the
        exported constant cannot start rejecting good evidence, and
        enlarging it cannot start accepting oversized files."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = os.path.join(tmp.name, "bible-pal")
        w = probe.EvidenceWriter.for_testing(root, RUN_ID)
        w.write_semantic_record(
            w.allocate_semantic("B", 1), http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        probe.MAX_EVIDENCE_FILE_BYTES = 1          # far too small
        rebuilt = probe.reconstruct_run_from_disk(
            w.run_dir, phase="T", run_id=RUN_ID, secrets=(),
            issued_registry=w._allocator.issued_registry())
        self.assertEqual(len(rebuilt.files), 2)    # issuance + semantic
        # Now the other direction: an oversized file is still refused.
        probe.MAX_EVIDENCE_FILE_BYTES = 10 ** 9
        victim = os.path.join(
            w.run_dir, w._persisted[("SEMANTIC_RECORD", "B", 1)])
        with open(victim, "wb") as fh:
            fh.write(b"{}" + b" " * (probe._policy().max_evidence_file_bytes
                                     + 1))
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=RUN_ID, secrets=(),
                issued_registry=w._allocator.issued_registry())

    def test_no_enforcement_reads_a_module_level_mutable_collection(self):
        """A standing sweep: every exported frozenset/dict/tuple that looks
        like policy must be reachable only as display, i.e. rebinding the
        whole lot must not change a validated record's verdict."""
        signed = sign(probe_target(key=probe_key("B", 1)), body=b"x")
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed)
        self.assertEqual(probe.validate_record(record, ()), "REQUEST_RECORD")
        self._subvert_everything()
        self.assertEqual(probe.validate_record(record, ()), "REQUEST_RECORD")

    def test_rebinding_inconclusive_cannot_manufacture_a_win(self):
        """HIGH sweep: the denial row's failure path must stay a failure."""
        spec = probe.test_spec("H4")
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        w = probe.EvidenceWriter.for_testing(
            os.path.join(tmp.name, "bp"), RUN_ID)
        self._subvert_everything()
        relative = write_support_repetition(
            w, spec, 1,
            facts=SUPPORT_EVIDENCE["H4"]._replace(
                status=200, etag='"e"', error_code=None))
        with open(os.path.join(w.run_dir, relative), encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertEqual(record["outcome_classification"], "INCONCLUSIVE")
        self.assertFalse(record["derived_valid"])
        self.assertFalse(record["derived_production_size"])

    def test_rebinding_raw_hex_pairs_cannot_disable_the_check(self):
        signed = sign(probe_target(key=probe_key("B", 1)), body=b"x",
                      extra_headers={"if-match": '"abc"'})
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed)
        record["if_match_raw_hex"] = probe.hex_of("something else entirely")
        self._subvert_everything()
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())

    def test_rebinding_manifest_name_cannot_hide_a_stray_file(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        w = probe.EvidenceWriter.for_testing(
            os.path.join(tmp.name, "bp"), RUN_ID)
        w.write_semantic_record(
            w.allocate_semantic("B", 1), http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        with open(os.path.join(w.run_dir, "notes.txt"), "w",
                  encoding="utf-8") as fh:
            fh.write("stray")
        self._subvert_everything()   # MANIFEST_FILENAME -> "notes.txt"
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=RUN_ID, secrets=(),
                issued_registry=w._allocator.issued_registry())

    def test_rebinding_acceptance_kinds_cannot_skip_issuance(self):
        """HIGH sweep: emptying the exported acceptance-kind set must not
        remove the physical-issuance requirement."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        w = probe.EvidenceWriter.for_testing(
            os.path.join(tmp.name, "bp"), "run-noissue2")
        record = {
            "record_kind": "SEMANTIC_RECORD", "phase": "T",
            "run_id": w.run_id, "group": "T-CAS-1", "test_id": "B",
            "repetition": 1, "key": probe_key("B", 1, run_id=w.run_id),
            "issuance_nonce": f"{w.run_id}:000001", "status": 412,
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
            "mutation_observed": False, "credential_expired": False,
            "repetition_status": "VALID"}
        w._write_bytes(probe.expected_relative_for_record(record),
                       json.dumps(record, sort_keys=True, indent=2,
                                  ensure_ascii=False).encode("utf-8"))
        self._subvert_everything()
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                issued_registry=w._allocator.issued_registry())

    def test_rebinding_cannot_redirect_the_wire_target(self):
        self._subvert_everything()
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        signed = probe.sign_request(
            target=probe.RequestTarget(
                method="PUT", bucket=PRODUCTION_BUCKET,
                key="catalog/v1/manifest.json"),
            host=ENDPOINT_HOST, access_key_id=AKID, secret_access_key=SECRET,
            session_token=None, body=b"x", amz_date=AMZ_DATE)
        with no_sockets():
            with self.assertRaises(probe.ProductionNameDetected):
                transport.send_signed_offline(signed)
        self.assertEqual(factory.calls, [],
                         "connection factory was reached after rebinding")
        self.assertEqual(transport.ledger, [])

    def test_rebinding_cannot_broaden_credential_claims(self):
        self._subvert_everything()
        cred = make_credential()
        report = iv.independent_inspect_credential(
            session_token=cred.session_token,
            secret_access_key=cred.secret_access_key,
            parent_secret_access_key=SECRET)
        claims = report["claims"]
        self.assertEqual(claims["bucket"], PROBE_BUCKET)
        self.assertEqual(claims["scope"], "object-read-write")
        self.assertEqual(claims["actions"],
                         ["HeadObject", "GetObject", "PutObject"])
        self.assertEqual(claims["paths"]["prefixPaths"], ["catalog/"])
        self.assertEqual(claims["paths"]["objectPaths"], [])
        self.assertEqual(claims["exp"] - claims["iat"], 900)
        self.assertEqual(cred.bucket, PROBE_BUCKET)
        self.assertEqual(cred.actions,
                         ("HeadObject", "GetObject", "PutObject"))

    def test_rebinding_cannot_disable_the_denylist(self):
        self._subvert_everything()
        with self.assertRaises(probe.ProductionNameDetected):
            probe.assert_no_denied_names(PRODUCTION_BUCKET)

    def test_rebinding_cannot_widen_header_ownership(self):
        self._subvert_everything()
        with self.assertRaises(probe.SafetyBarrierTripped):
            sign(probe_target(), body=b"x",
                 extra_headers={"host": "evil.example"})
        with self.assertRaises(probe.SafetyBarrierTripped):
            sign(probe_target(), body=b"x",
                 extra_headers={"authorization": "AWS4-HMAC-SHA256 evil"})

    def test_rebinding_cannot_change_key_allocation(self):
        self._subvert_everything()
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        issued = alloc.allocate(phase="t", test_id="B", repetition=1)
        self.assertTrue(issued.identity.key.startswith("catalog/probe/"))

    def test_rebinding_cannot_lower_resource_caps(self):
        self._subvert_everything()
        caps = probe.fixed_resource_caps()
        self.assertEqual(caps.max_put_attempts, 650)
        self.assertEqual(caps.max_production_size_puts, 60)
        self.assertEqual(probe.ResourceLedger()._caps, caps)

    def test_rebinding_cannot_lower_aggregator_thresholds(self):
        self._subvert_everything()
        agg = probe.SemanticAggregator()
        self.assertEqual(agg.required_valid("B"), 10)
        self.assertEqual(agg.max_attempts("B"), 20)

    def test_policy_accessor_returns_the_same_instance(self):
        """BLOCKER 1: rebinding _Policy/_Caps/TestSpec does not change the
        captured instance identity or contents."""
        before = probe._policy()
        before_id = id(before)
        self._subvert_everything()
        after = probe._policy()
        self.assertEqual(id(after), before_id)
        self.assertIs(after, before)
        self.assertEqual(after.bucket, "bible-pal-cas-probe")
        self.assertEqual(after.denied_tokens, ("bible-pal-audio",))
        self.assertEqual(after.caps.max_put_attempts, 650)
        self.assertEqual(len(after.matrix), 26)

    def test_rebinding_cannot_change_transport_constants(self):
        """BLOCKER 2: multipart detection, signer scope, and body/error
        bounds all read the captured policy."""
        self._subvert_everything()
        # Multipart-shaped request still refused.
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_target_allowed(
                probe.RequestTarget(method="GET", bucket=PROBE_BUCKET,
                                    key="", query=(("uploadId", "1"),)))
        # Signer scope still auto/s3.
        signed = sign(probe_target(), body=b"x")
        self.assertIn("/auto/s3/aws4_request",
                      signed.header_map()["authorization"])
        # Error-body bound unchanged (a small valid error still parses).
        self.assertEqual(
            probe.parse_s3_error(
                b"<Error><Code>NoSuchKey</Code></Error>").code, "NoSuchKey")
        # Response bound unchanged: a large response still truncates at the
        # original cap, not at the rebound "1".
        big = b"y" * 5000
        transport = make_transport(FakeConnection(
            response=FakeResponse(200, [], big)))
        resp = transport.send_signed_offline(sign(probe_target(method="GET")))
        self.assertEqual(len(resp.body), 5000)
        self.assertFalse(resp.body_truncated)

    def test_rebinding_cannot_disable_environment_scrub(self):
        self._subvert_everything()
        self.assertEqual(
            probe.forbidden_environment_keys({"AWS_SECRET_ACCESS_KEY": "x"}),
            ["AWS_SECRET_ACCESS_KEY"])
        self.assertEqual(
            probe.forbidden_environment_keys({"HTTPS_PROXY": "x"}),
            ["HTTPS_PROXY"])

    def test_timing_limits_live_in_the_captured_policy(self):
        """LOW: the planner/guard timing limits are captured policy, not
        mutable class-level policy."""
        policy = probe._policy()
        self.assertEqual(policy.same_key_min_gap_seconds, 3.0)
        self.assertEqual(policy.credential_safety_factor, 1.5)
        self.assertEqual(policy.credential_required_margin_seconds, 120.0)
        self.assertEqual(policy.expiry_max_age_seconds, 10.0)
        self.assertGreater(policy.max_race_send_skew_ns, 0)
        self.assertGreater(policy.max_amz_date_skew_seconds, 0)
        # The class-level display aliases equal the policy values.
        self.assertEqual(probe.SameKeyWriteGuard.MIN_GAP_SECONDS,
                         policy.same_key_min_gap_seconds)
        self.assertEqual(probe.CredentialGroupPlanner.SAFETY_FACTOR,
                         policy.credential_safety_factor)
        # And the guard reads the policy, not the mutable class attribute.
        clock = {"t": 0.0}
        guard = probe.SameKeyWriteGuard(
            monotonic=lambda: clock["t"], sleep=lambda s: None)
        probe.SameKeyWriteGuard.MIN_GAP_SECONDS = 0.0   # try to weaken it
        try:
            guard.note_write_response_end("k", mono_ts=0.0)
            clock["t"] = 1.0
            self.assertAlmostEqual(guard.seconds_until_writable("k"), 2.0)
        finally:
            probe.SameKeyWriteGuard.MIN_GAP_SECONDS = \
                policy.same_key_min_gap_seconds

    def test_rebinding_cannot_weaken_execution_gates(self):
        self._subvert_everything()
        gates = probe.ExecutionGates(
            execute=True, bucket=PRODUCTION_BUCKET, confirmation="yes",
            authorized_by_adam=True, account_id=ACCOUNT_ID,
            credentials_file="/nonexistent")
        with self.assertRaises(probe.MissingAuthorization):
            gates.assert_may_execute()

    def test_policy_object_is_immutable(self):
        policy = probe._policy()
        with self.assertRaises(AttributeError):
            policy.bucket = PRODUCTION_BUCKET
        # NamedTuple: object.__setattr__ cannot reach it either.
        with self.assertRaises(AttributeError):
            object.__setattr__(policy, "bucket", PRODUCTION_BUCKET)

    def test_exported_aliases_match_the_policy_at_import(self):
        policy = probe._policy()
        self.assertEqual(probe.PROBE_BUCKET, policy.bucket)
        self.assertEqual(probe.DENIED_NAME_TOKENS, policy.denied_tokens)


# ═══════════════════════════════════════════════════════════════════════════
# BLOCKER 2 — status/outcome matrix, no contradictory evidence
# ═══════════════════════════════════════════════════════════════════════════

class StatusOutcomeMatrixTests(unittest.TestCase):

    def test_412_pairs_only_with_conditional_rejection(self):
        self.assertEqual(probe.allowed_outcomes_for_status(412),
                         frozenset({probe.PutOutcome
                                    .DEFINITE_CONDITIONAL_REJECTION}))

    def test_429_401_403_other4xx_5xx_pairings(self):
        cases = {
            429: probe.PutOutcome.DEFINITE_THROTTLE_REJECTION,
            401: probe.PutOutcome.DEFINITE_AUTH_REJECTION,
            403: probe.PutOutcome.DEFINITE_AUTH_REJECTION,
            404: probe.PutOutcome.DEFINITE_CLIENT_REJECTION,
            400: probe.PutOutcome.DEFINITE_CLIENT_REJECTION,
            500: probe.PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN,
            503: probe.PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN,
        }
        for status, outcome in cases.items():
            with self.subTest(status=status):
                self.assertEqual(probe.allowed_outcomes_for_status(status),
                                 frozenset({outcome}))

    def test_2xx_allows_only_success_family(self):
        allowed = probe.allowed_outcomes_for_status(200)
        self.assertEqual(allowed, frozenset({
            probe.PutOutcome.PUT_CONFIRMED,
            probe.PutOutcome.PUT_SUCCEEDED_VERIFY_UNKNOWN,
            probe.PutOutcome.SUPERSEDED_AFTER_PUBLISH}))

    def test_no_status_allows_only_transport_states(self):
        allowed = probe.allowed_outcomes_for_status(None)
        self.assertEqual(allowed, frozenset({
            probe.PutOutcome.BEFORE_REQUEST_FAILURE,
            probe.PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN,
            probe.PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN}))

    def test_every_outcome_is_reachable_from_some_status(self):
        reachable = set()
        for status in [None] + list(range(200, 300)) \
                + list(range(400, 600)):
            reachable |= probe.allowed_outcomes_for_status(status)
        self.assertEqual(reachable, set(probe.PutOutcome))

    def test_1xx_and_3xx_fail_closed(self):
        """No legitimate probe response is informational or a redirect —
        the transport refuses redirects outright — so these status classes
        have no matrix entry and must raise rather than be mapped."""
        for status in (100, 199, 300, 301, 302, 307, 308, 399):
            with self.subTest(status=status):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.allowed_outcomes_for_status(status)
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.classify_put_outcome(transport_failure=None,
                                               status=status)

    def test_contradictory_pair_raises(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_status_outcome_consistent(
                412, probe.PutOutcome.PUT_CONFIRMED)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_status_outcome_consistent(
                200, probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_status_outcome_consistent(
                None, probe.PutOutcome.PUT_CONFIRMED)

    def test_classify_always_produces_a_consistent_pair(self):
        for status in [None] + list(range(200, 300)) + list(range(400, 600)):
            outcome = probe.classify_put_outcome(
                transport_failure=None, status=status)
            probe.assert_status_outcome_consistent(status, outcome)


class SemanticEvidenceValidationTests(unittest.TestCase):

    def identity(self, test_id="B", rep=1):
        return probe.RepetitionIdentity(
            phase="t", run_id=RUN_ID, test_id=test_id, repetition=rep,
            key=probe_key(test_id, rep))

    def evidence(self, *, test_id="B", rep=1, status=412, outcome=None,
                 mutation=False, expired=False):
        if outcome is None:
            outcome = probe.classify_put_outcome(
                transport_failure=None, status=status)
        return probe.SemanticEvidence(
            identity=self.identity(test_id, rep), http_status=status,
            outcome=outcome, mutation_observed=mutation,
            credential_expired=expired)

    def test_412_with_put_confirmed_is_refused(self):
        """Codex BLOCKER 2's exact counterexample."""
        bad = probe.SemanticEvidence(
            identity=self.identity(), http_status=412,
            outcome=probe.PutOutcome.PUT_CONFIRMED, mutation_observed=False)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_semantic_evidence(bad)
        agg = probe.SemanticAggregator()
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(bad)

    def test_contradictory_evidence_cannot_reach_pass(self):
        agg = probe.SemanticAggregator()
        for rep in range(1, 10):
            agg.record(self.evidence(rep=rep))
        bad = probe.SemanticEvidence(
            identity=self.identity(rep=10), http_status=412,
            outcome=probe.PutOutcome.PUT_CONFIRMED, mutation_observed=False)
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(bad)
        self.assertIs(agg.verdict("B")[0], probe.Verdict.FAIL)

    def test_namedtuple_evidence_cannot_be_mutated(self):
        """object.__setattr__ cannot touch a tuple — the fix for 'frozen
        only nominally'."""
        good = self.evidence()
        for field, value in (("http_status", 200),
                             ("mutation_observed", None),
                             ("outcome", probe.PutOutcome.PUT_CONFIRMED)):
            with self.subTest(field=field):
                with self.assertRaises(AttributeError):
                    object.__setattr__(good, field, value)

    def test_mutated_identity_tuple_cannot_be_forged(self):
        ident = self.identity()
        with self.assertRaises(AttributeError):
            object.__setattr__(ident, "key", "catalog/v1/manifest.json")

    def test_record_revalidates_completely(self):
        """A hand-built evidence object with a mismatched key is rejected
        at record(), not merely at construction."""
        bogus = probe.SemanticEvidence(
            identity=probe.RepetitionIdentity(
                phase="t", run_id=RUN_ID, test_id="B", repetition=1,
                key="catalog/probe/t/run-abc/b/9999/obj.json"),
            http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        agg = probe.SemanticAggregator()
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(bogus)

    def test_non_semantic_test_id_refused(self):
        agg = probe.SemanticAggregator()
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(self.evidence(test_id="A"))


# ═══════════════════════════════════════════════════════════════════════════
# BLOCKER 3 — aggregator is fixed-purpose and identity-checked
# ═══════════════════════════════════════════════════════════════════════════

class SemanticAggregatorTests(unittest.TestCase):

    def evidence(self, test_id="B", rep=1, status=412, mutation=False,
                 expired=False, key=None):
        outcome = probe.classify_put_outcome(
            transport_failure=None, status=status)
        ident = probe.RepetitionIdentity(
            phase="t", run_id=RUN_ID, test_id=test_id, repetition=rep,
            key=key if key is not None else probe_key(test_id, rep))
        return probe.SemanticEvidence(
            identity=ident, http_status=status, outcome=outcome,
            mutation_observed=mutation, credential_expired=expired)

    def clean(self, test_id="B", n=10):
        agg = probe.SemanticAggregator()
        for rep in range(1, n + 1):
            agg.record(self.evidence(test_id, rep))
        return agg

    def test_no_configurable_thresholds(self):
        import inspect
        params = set(inspect.signature(
            probe.SemanticAggregator.__init__).parameters)
        self.assertEqual(params, {"self"})
        self.assertNotIn("required_valid", params)
        self.assertNotIn("max_attempts", params)

    def test_overall_takes_no_test_id_list(self):
        import inspect
        params = set(inspect.signature(
            probe.SemanticAggregator.overall).parameters)
        self.assertEqual(params, {"self"})

    def test_overall_always_evaluates_b_d_e1(self):
        self.assertEqual(probe.semantic_test_ids(), ("B", "D", "E1"))
        agg = probe.SemanticAggregator()
        verdict, reasons = agg.overall()
        self.assertIs(verdict, probe.Verdict.FAIL)
        self.assertEqual(len(reasons), 3)

    def test_overall_with_no_evidence_fails(self):
        self.assertIs(probe.SemanticAggregator().overall()[0],
                      probe.Verdict.FAIL)

    def test_one_412_cannot_pass(self):
        agg = probe.SemanticAggregator()
        agg.record(self.evidence(rep=1))
        self.assertIs(agg.verdict("B")[0], probe.Verdict.FAIL)

    def test_ten_references_to_the_same_evidence_cannot_pass(self):
        agg = probe.SemanticAggregator()
        single = self.evidence(rep=1)
        agg.record(single)
        for _ in range(9):
            with self.assertRaises(probe.SafetyBarrierTripped):
                agg.record(single)
        self.assertIs(agg.verdict("B")[0], probe.Verdict.FAIL)

    def test_duplicate_test_repetition_refused(self):
        agg = probe.SemanticAggregator()
        agg.record(self.evidence(rep=3))
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(self.evidence(rep=3))

    def test_two_repetitions_sharing_a_key_refused(self):
        agg = probe.SemanticAggregator()
        agg.record(self.evidence(rep=1))
        # Repetition 2 that claims repetition 1's key: the identity check
        # rejects it because key must match its own repetition number.
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(self.evidence(rep=2, key=probe_key("B", 1)))

    def test_all_valid_412_passes(self):
        self.assertIs(self.clean().verdict("B")[0], probe.Verdict.PASS)

    def test_mutation_dominates_under_any_label(self):
        agg = probe.SemanticAggregator()
        agg.record(self.evidence(rep=1, status=429, mutation=True))
        for rep in range(2, 12):
            agg.record(self.evidence(rep=rep))
        verdict, reason = agg.verdict("B")
        self.assertIs(verdict, probe.Verdict.ABANDON)
        self.assertIn("MUTATED", reason)

    def test_412_with_mutation_abandons(self):
        agg = self.clean(n=9)
        agg.record(self.evidence(rep=10, status=412, mutation=True))
        self.assertIs(agg.verdict("B")[0], probe.Verdict.ABANDON)

    def test_2xx_acceptance_abandons(self):
        agg = self.clean(n=9)
        agg.record(self.evidence(rep=10, status=200))
        verdict, reason = agg.verdict("B")
        self.assertIs(verdict, probe.Verdict.ABANDON)
        self.assertIn("2xx", reason)

    def test_throttle_is_invalid_not_passing(self):
        agg = probe.SemanticAggregator()
        for rep in range(1, 6):
            agg.record(self.evidence("D", rep))
        for rep in range(6, 11):
            agg.record(self.evidence("D", rep, status=429))
        verdict, reason = agg.verdict("D")
        self.assertIs(verdict, probe.Verdict.FAIL)
        self.assertIn("INCONCLUSIVE", reason)

    def test_attempt_cap(self):
        agg = probe.SemanticAggregator()
        for rep in range(1, 22):
            agg.record(self.evidence(rep=rep))
        self.assertIs(agg.verdict("B")[0], probe.Verdict.FAIL)

    def test_adversarial_matrix_no_hidden_pass(self):
        for status in (200, 201, 204, 412, 429, 403, 500, None):
            for mutation in (True, False, None):
                agg = probe.SemanticAggregator()
                for rep in range(1, 10):
                    agg.record(self.evidence(rep=rep))
                agg.record(self.evidence(rep=10, status=status,
                                         mutation=mutation))
                verdict, _ = agg.verdict("B")
                if mutation is True or (status is not None
                                        and 200 <= status < 300):
                    self.assertIs(verdict, probe.Verdict.ABANDON,
                                  f"status={status} mutation={mutation}")
                elif status == 412 and mutation is False:
                    self.assertIs(verdict, probe.Verdict.PASS)
                else:
                    self.assertIs(verdict, probe.Verdict.FAIL,
                                  f"status={status} mutation={mutation}")

    def test_derivation_labels(self):
        cases = {
            (412, False): probe.RepetitionStatus.VALID,
            (429, False): probe.RepetitionStatus.INVALID_THROTTLED,
            (500, False): probe.RepetitionStatus.INVALID_AMBIGUOUS,
            (412, None): probe.RepetitionStatus.INVALID_AMBIGUOUS,
        }
        for (status, mutation), expected in cases.items():
            with self.subTest(status=status, mutation=mutation):
                derived, _ = probe.derive_semantic_status(
                    self.evidence(status=status, mutation=mutation))
                self.assertIs(derived, expected)
        derived, _ = probe.derive_semantic_status(
            self.evidence(status=403, expired=True))
        self.assertIs(derived, probe.RepetitionStatus.INVALID_CREDENTIAL_EXPIRED)

    def test_overall_abandon_dominates(self):
        agg = probe.SemanticAggregator()
        for rep in range(1, 11):
            agg.record(self.evidence("B", rep))
            agg.record(self.evidence("D", rep, mutation=(rep == 5)))
            agg.record(self.evidence("E1", rep))
        self.assertIs(agg.overall()[0], probe.Verdict.ABANDON)


# ═══════════════════════════════════════════════════════════════════════════
# HIGH 1 — sign-to-send binding
# ═══════════════════════════════════════════════════════════════════════════

class SignToSendBindingTests(unittest.TestCase):

    def test_live_primitive_never_consumes_a_signed_request(self):
        import inspect
        params = inspect.signature(probe.R2Transport.sign_and_send).parameters
        self.assertNotIn("signed", params)
        for name in params:
            self.assertNotIn("signed", name)
        # It takes primitives + a credential instead.
        for expected in ("target", "body", "credential", "amz_date"):
            self.assertIn(expected, params)

    def test_sign_and_send_transmits_what_it_signed(self):
        conn = FakeConnection(response=FakeResponse(200, [("ETag", '"e"')]))
        transport = make_transport(conn)
        cred = make_transport_credential()
        body = b'{"probe":1}'
        transport.sign_and_send(target=probe_target(), body=body,
                                credential=cred, amz_date=AMZ_DATE)
        method, path, sent_body, headers = conn.requests[0]
        self.assertEqual(sent_body, body)
        self.assertEqual(headers["x-amz-content-sha256"],
                         hashlib.sha256(body).hexdigest())
        self.assertEqual(headers["x-amz-date"], AMZ_DATE)
        self.assertIn("authorization", headers)
        self.assertIn("x-amz-security-token", headers)
        self.assertNotIn("host", headers)
        self.assertNotIn("content-length", headers)

    def test_mutating_a_standalone_signed_request_cannot_reach_the_live_api(self):
        """A SignedRequest is a NamedTuple, so it cannot be mutated at all;
        and the live API would not accept one even if it could be."""
        signed = sign(probe_target(), body=b"x")
        for field in ("headers", "body", "host", "signature"):
            with self.subTest(field=field):
                with self.assertRaises(AttributeError):
                    object.__setattr__(signed, field, "tampered")
        import inspect
        self.assertNotIn(
            "signed",
            inspect.signature(probe.R2Transport.sign_and_send).parameters)

    def test_tampered_header_tuple_is_refused_by_the_offline_path(self):
        """Even the offline helper refuses a poisoned header set."""
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        signed = sign(probe_target(), body=b"x")
        poisoned = signed._replace(
            headers=tuple(list(signed.headers) + [("host", "evil.example")]))
        with no_sockets():
            with self.assertRaises(probe.SafetyBarrierTripped):
                transport.send_signed_offline(poisoned)
        self.assertEqual(factory.calls, [])

    def test_missing_required_header_refused(self):
        signed = sign(probe_target(), body=b"x")
        stripped = signed._replace(
            headers=tuple(h for h in signed.headers
                          if h[0] != "authorization"))
        transport = make_transport(FakeConnection(response=FakeResponse(200)))
        with self.assertRaises(probe.SafetyBarrierTripped):
            transport.send_signed_offline(stripped)

    def test_sign_and_send_requires_a_real_credential(self):
        transport = make_transport(FakeConnection(response=FakeResponse(200)))
        for bad in (None, "creds", {"access_key_id": AKID}):
            with self.subTest(bad=type(bad).__name__):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    transport.sign_and_send(
                        target=probe_target(), body=b"x", credential=bad,
                        amz_date=AMZ_DATE)

    def test_sign_and_send_rejects_non_probe_credential_bucket(self):
        cred = make_transport_credential()._replace(bucket=PRODUCTION_BUCKET)
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        with no_sockets():
            with self.assertRaises(probe.ProbeError):
                transport.sign_and_send(target=probe_target(), body=b"x",
                                        credential=cred, amz_date=AMZ_DATE)
        self.assertEqual(factory.calls, [])

    def test_sign_and_send_enforces_target_barriers(self):
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        evil = probe.RequestTarget(method="PUT", bucket=PRODUCTION_BUCKET,
                                   key="catalog/v1/manifest.json")
        with no_sockets():
            with self.assertRaises(probe.ProductionNameDetected):
                transport.sign_and_send(target=evil, body=b"x",
                                        credential=make_transport_credential(),
                                        amz_date=AMZ_DATE)
        self.assertEqual(factory.calls, [])

    def test_sign_and_send_validates_full_credential(self):
        """HIGH 2: adversarial credentials must be refused before any
        socket, each via the complete transport-side validator."""
        transport_factory = RecordingFactory(
            FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST,
            connection_factory=transport_factory, monotonic=lambda: 0,
            wall_clock=lambda: float(AMZ_EPOCH))
        good = make_transport_credential()
        wrong_host = f"{'1' * 32}.r2.cloudflarestorage.com"
        cases = {
            "admin_scope": good._replace(scope="admin-read-write"),
            "delete_action": good._replace(
                actions=("HeadObject", "DeleteObject")),
            "empty_prefix": good._replace(prefix_paths=("",)),
            "wrong_group": good._replace(group="T-ADMIN"),
            "wrong_ttl": good._replace(expires_at=good.issued_at + 3600),
            "changed_secret": good._replace(
                secret_access_key="e" * 64),
            "changed_token": good._replace(session_token="dGFtcGVyZWQ="),
            "iss_mismatch": good._replace(access_key_id="a" * 32),
        }
        for name, cred in cases.items():
            with self.subTest(case=name):
                with no_sockets():
                    with self.assertRaises(probe.ProbeError):
                        transport.sign_and_send(
                            target=probe_target(), body=b"x",
                            credential=cred, amz_date=AMZ_DATE)
        # A different-audience credential (minted for another account).
        other = probe.mint_probe_credential(
            group="T-CAS-1", account_id="1" * 32, parent_access_key_id=AKID,
            parent_secret_access_key=SECRET, now=AMZ_EPOCH)
        with no_sockets():
            with self.assertRaises(probe.ProbeError):
                transport.sign_and_send(target=probe_target(), body=b"x",
                                        credential=other, amz_date=AMZ_DATE)
        # Expired: valid credential but amz_date outside the window.
        with no_sockets():
            with self.assertRaises(probe.ProbeError):
                transport.sign_and_send(
                    target=probe_target(), body=b"x", credential=good,
                    amz_date="20990101T000000Z")
        self.assertEqual(transport_factory.calls, [],
                         "a bad credential reached the connection factory")
        _ = wrong_host


class WallClockFreshnessTests(unittest.TestCase):
    """MEDIUM 1: credential freshness uses the ACTUAL wall clock, not the
    caller's amz_date."""

    def _transport(self, wall_now):
        return probe.R2Transport(
            endpoint_host=ENDPOINT_HOST,
            connection_factory=RecordingFactory(
                FakeConnection(response=FakeResponse(200, [("ETag", '"e"')]))),
            monotonic=lambda: 0, wall_clock=lambda: float(wall_now))

    def test_historical_credential_and_date_rejected_today(self):
        # Credential + amz_date both from the past; wall clock is "now".
        past = 1_600_000_000    # 2020-ish
        cred = probe.mint_probe_credential(
            group="T-CAS-1", account_id=ACCOUNT_ID, parent_access_key_id=AKID,
            parent_secret_access_key=SECRET, now=past)
        transport = self._transport(1_900_000_000)   # far future "now"
        with no_sockets():
            with self.assertRaises(probe.SafetyBarrierTripped):
                transport.sign_and_send(
                    target=probe_target(), body=b"x", credential=cred,
                    amz_date="20200913T122253Z")

    def test_current_credential_and_date_accepted(self):
        now = AMZ_EPOCH
        cred = probe.mint_probe_credential(
            group="T-CAS-1", account_id=ACCOUNT_ID, parent_access_key_id=AKID,
            parent_secret_access_key=SECRET, now=now)
        transport = self._transport(now + 5)   # a few seconds later
        resp = transport.sign_and_send(
            target=probe_target(), body=b"x", credential=cred,
            amz_date=AMZ_DATE)
        self.assertEqual(resp.status, 200)

    def test_amz_date_outside_skew_rejected(self):
        now = AMZ_EPOCH
        cred = make_transport_credential()
        transport = self._transport(now)
        skewed = "20990101T000000Z"   # far from now
        with no_sockets():
            with self.assertRaises(probe.SafetyBarrierTripped):
                transport.sign_and_send(
                    target=probe_target(), body=b"x", credential=cred,
                    amz_date=skewed)

    def test_wall_clock_default_is_time_time(self):
        import inspect
        default = inspect.signature(
            probe.R2Transport.__init__).parameters["wall_clock"].default
        self.assertIs(default, __import__("time").time)


# ═══════════════════════════════════════════════════════════════════════════
# BLOCKER 1 (cont) — wire target / type confusion
# ═══════════════════════════════════════════════════════════════════════════

class WireBindingTests(unittest.TestCase):

    def test_builder_refuses_str_subclass_bucket_and_key(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.new_request_target(
                method="PUT", bucket=EvilStr(PROBE_BUCKET, PRODUCTION_BUCKET),
                key=probe_key())
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.new_request_target(
                method="PUT", bucket=PROBE_BUCKET,
                key=EvilStr(probe_key(), "catalog/v1/manifest.json"))

    def test_evil_bucket_never_reaches_the_factory(self):
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        signed = sign(probe_target(), body=b"x")
        evil = signed._replace(
            target=probe.RequestTarget(
                method="PUT", bucket=EvilStr(PROBE_BUCKET, PRODUCTION_BUCKET),
                key=probe_key()))
        with no_sockets():
            with self.assertRaises(probe.SafetyBarrierTripped):
                transport.send_signed_offline(evil)
        self.assertEqual(factory.calls, [])
        self.assertEqual(transport.ledger, [])

    def test_query_value_subclass_refused(self):
        target = probe.RequestTarget(
            method="GET", bucket=PROBE_BUCKET, key="",
            query=((EvilStr("prefix", "uploads"), "1"),))
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_target_allowed(target)

    def test_extra_header_overrides_refused(self):
        for name in ("host", "Host", "HOST", "authorization",
                     "Authorization", "content-length", "Content-Length",
                     "x-amz-date", "X-Amz-Date", "x-amz-content-sha256",
                     "x-amz-security-token"):
            with self.subTest(name=name):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    sign(probe_target(), body=b"x", session_token="T",
                         extra_headers={name: "spoofed"})

    def test_mapping_subclass_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            sign(probe_target(), body=b"x",
                 extra_headers=EvilDict({"if-match": '"e"'}))

    def test_object_with_malicious_str_refused_by_scan(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_no_denied_names(EvilRepr())

    def test_denied_name_scan_refuses_polymorphic_str(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_no_denied_names(EvilStr("ok", PRODUCTION_BUCKET))

    def test_production_bucket_rejected_before_connection(self):
        factory = RecordingFactory(FakeConnection(response=FakeResponse(200)))
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=factory,
            monotonic=lambda: 0, wall_clock=lambda: float(AMZ_EPOCH))
        signed = probe.sign_request(
            target=probe.RequestTarget(method="PUT", bucket=PRODUCTION_BUCKET,
                                       key=probe_key()),
            host=ENDPOINT_HOST, access_key_id=AKID, secret_access_key=SECRET,
            session_token=None, body=b"x", amz_date=AMZ_DATE)
        with no_sockets():
            with self.assertRaises(probe.ProductionNameDetected):
                transport.send_signed_offline(signed)
        self.assertEqual(factory.calls, [])

    def test_host_bound_to_validated_endpoint(self):
        conn = FakeConnection(response=FakeResponse(200))
        transport = make_transport(conn)
        transport.send_signed_offline(sign(probe_target(), body=b"x"))
        _, _, _, headers = conn.requests[0]
        self.assertNotIn("host", headers)
        self.assertEqual(transport.endpoint_host, ENDPOINT_HOST)

    def test_no_injectable_allowlist_parameter(self):
        import inspect
        for fn in (probe.R2Transport.__init__, probe.R2Transport.sign_and_send,
                   probe.R2Transport.send_signed_offline,
                   probe.assert_target_allowed):
            self.assertNotIn("allowed_buckets",
                             inspect.signature(fn).parameters)


# ═══════════════════════════════════════════════════════════════════════════
# HIGH 2 — race identity is enforced
# ═══════════════════════════════════════════════════════════════════════════

class RaceIdentityTests(unittest.TestCase):

    def test_allocator_derives_setup_state(self):
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        e2 = alloc.allocate_race(phase="t", test_id="E2", repetition=1).identity
        f = alloc.allocate_race(phase="t", test_id="F", repetition=1).identity
        self.assertEqual(e2.setup_state, "SEEDED_ETAG_CAPTURED")
        self.assertEqual(f.setup_state, "PROVEN_ABSENT")
        self.assertEqual(e2.repetition_id, "E2/1")

    def test_allocator_issues_a_capability(self):
        """HIGH 3: allocate returns an IssuedIdentity that resolve() accepts;
        a manually built identity has no matching nonce."""
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        issued = alloc.allocate(phase="t", test_id="B", repetition=1)
        self.assertIsInstance(issued, probe.IssuedIdentity)
        self.assertIs(alloc.resolve(issued), issued.identity)
        # A fabricated capability with a made-up nonce is refused.
        fake = probe.IssuedIdentity(identity=issued.identity, nonce="x:000001")
        with self.assertRaises(probe.SafetyBarrierTripped):
            alloc.resolve(fake)
        # A different allocator never issued it.
        other = probe.ProbeKeyAllocator("run-other")
        with self.assertRaises(probe.SafetyBarrierTripped):
            other.resolve(issued)

    def test_allocate_race_signature_has_no_setup_state(self):
        import inspect
        params = inspect.signature(
            probe.ProbeKeyAllocator.allocate_race).parameters
        self.assertNotIn("setup_state", params)

    def test_e2_with_proven_absent_fails(self):
        bad = probe.RaceIdentity(
            phase="t", run_id=RUN_ID, test_id="E2", repetition=1,
            key=probe_key("E2", 1), setup_state="PROVEN_ABSENT")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_identity(bad)

    def test_f_with_seeded_etag_fails(self):
        bad = probe.RaceIdentity(
            phase="t", run_id=RUN_ID, test_id="F", repetition=1,
            key=probe_key("F", 1), setup_state="SEEDED_ETAG_CAPTURED")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_identity(bad)

    def test_e2_identity_with_f_key_fails(self):
        bad = probe.RaceIdentity(
            phase="t", run_id=RUN_ID, test_id="E2", repetition=1,
            key=probe_key("F", 1), setup_state="SEEDED_ETAG_CAPTURED")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_identity(bad)

    def test_repetition_id_key_mismatch_fails(self):
        bad = probe.RaceIdentity(
            phase="t", run_id=RUN_ID, test_id="E2", repetition=7,
            key=probe_key("E2", 3), setup_state="SEEDED_ETAG_CAPTURED")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_identity(bad)

    def test_free_form_stale_key_refused(self):
        bad = probe.RaceIdentity(
            phase="t", run_id=RUN_ID, test_id="E2", repetition=1,
            key="catalog/probe/whatever/stale.json",
            setup_state="SEEDED_ETAG_CAPTURED")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_identity(bad)

    def test_non_race_test_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.race_setup_state_for("B")
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        with self.assertRaises(probe.SafetyBarrierTripped):
            alloc.allocate_race(phase="t", test_id="B", repetition=1)

    def test_allocator_reuse_refused(self):
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        alloc.allocate_race(phase="t", test_id="E2", repetition=1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            alloc.allocate_race(phase="t", test_id="E2", repetition=1)
        alloc2 = probe.ProbeKeyAllocator(RUN_ID)
        alloc2.allocate(phase="t", test_id="B", repetition=1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            alloc2.allocate(phase="t", test_id="B", repetition=1)

    def test_only_two_race_types_exist(self):
        self.assertEqual(probe.race_test_ids(), ("E2", "F"))


SHARED_ETAG = '"seed-original-etag"'
BARRIER_GEN = "gen-1"
BARRIER_RELEASE = 1000
BARRIER = probe.RaceBarrierEvidence(generation_id=BARRIER_GEN,
                                    release_mono_ns=BARRIER_RELEASE)


def race_writer(wid, status, payload, etag, *, test="E2",
                barrier_generation=BARRIER_GEN, join_ns=900, send_ns=1010):
    """Build a RaceWriter with the correct conditional for the race type,
    joining the shared barrier before release and sending just after."""
    if test == "E2":
        if_match, if_none_match = SHARED_ETAG, None
    else:
        if_match, if_none_match = None, "*"
    return probe.RaceWriter(
        writer_id=wid, http_status=status,
        payload_sha256=hashlib.sha256(payload).hexdigest(),
        payload_length=len(payload), returned_etag=etag,
        if_match=if_match, if_none_match=if_none_match,
        barrier_generation=barrier_generation,
        barrier_join_mono_ns=join_ns, send_mono_ns=send_ns)


class RaceModelTests(unittest.TestCase):

    def setUp(self):
        self.alloc = probe.ProbeKeyAllocator(RUN_ID)
        self._rep = 0

    def identity(self, test_id="E2"):
        self._rep += 1
        return self.alloc.allocate_race(phase="t", test_id=test_id,
                                        repetition=self._rep).identity

    def writer(self, wid, status, payload, etag, test="E2"):
        return race_writer(wid, status, payload, etag, test=test)

    def repetition(self, writers, final_payload, final_etag, *,
                   identity=None, test="E2",
                   final_state=probe.RemoteState.CONFIRMED,
                   final_length=None,
                   shared_original_etag=SHARED_ETAG,
                   absence_confirmed=None, barrier=BARRIER):
        if identity is None:
            identity = self.identity(test)
        if final_length is None and final_payload is not None:
            final_length = len(final_payload)
        if test == "F":
            shared_original_etag, absence_confirmed = None, True
        return probe.RaceRepetition(
            identity=identity, shared_original_etag=shared_original_etag,
            absence_confirmed=absence_confirmed, barrier=barrier,
            writers=tuple(writers), final_state=final_state,
            final_sha256=(hashlib.sha256(final_payload).hexdigest()
                          if final_payload is not None else None),
            final_length=final_length, final_etag=final_etag)

    def test_one_winner_412_loser_is_valid_cas(self):
        status, reason, attributions = probe.classify_race_repetition(
            self.repetition(
                [self.writer("W1", 200, b"aaa", '"e-win"'),
                 self.writer("W2", 412, b"bbb", None)], b"aaa", '"e-win"'))
        self.assertIs(status, probe.RaceRepetitionStatus.VALID_CAS, reason)
        self.assertEqual(attributions, [probe.RaceAttribution.CAS])

    def test_one_winner_429_loser_is_throttled_not_valid(self):
        """HIGH 1: a 429 loser is INVALID_THROTTLED, NEVER a valid CAS
        repetition — and never PASS at the aggregator."""
        status, _, attributions = probe.classify_race_repetition(
            self.repetition(
                [self.writer("W1", 200, b"aaa", '"e-win"'),
                 self.writer("W2", 429, b"bbb", None)], b"aaa", '"e-win"'))
        self.assertIs(status, probe.RaceRepetitionStatus.INVALID_THROTTLED)
        self.assertEqual(attributions, [probe.RaceAttribution.THROTTLE])

    def test_f_race_valid_cas(self):
        status, reason, _ = probe.classify_race_repetition(
            self.repetition(
                [self.writer("W1", 200, b"aaa", '"e-win"', test="F"),
                 self.writer("W2", 412, b"bbb", None, test="F")],
                b"aaa", '"e-win"', test="F"))
        self.assertIs(status, probe.RaceRepetitionStatus.VALID_CAS, reason)

    def test_e2_wrong_barrier_generation_refused(self):
        w1 = self.writer("W1", 200, b"aaa", '"e"')._replace(
            barrier_generation="other-gen")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [w1, self.writer("W2", 412, b"bbb", None)], b"aaa", '"e"'))

    def test_send_before_release_refused(self):
        # HIGH 2: a writer that sent before the barrier release is refused.
        w1 = self.writer("W1", 200, b"aaa", '"e"')._replace(send_ns=None) \
            if False else self.writer("W1", 200, b"aaa", '"e"')
        w1 = w1._replace(send_mono_ns=BARRIER_RELEASE - 1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [w1, self.writer("W2", 412, b"bbb", None)], b"aaa", '"e"'))

    def test_join_after_release_refused(self):
        w1 = self.writer("W1", 200, b"aaa", '"e"')._replace(
            barrier_join_mono_ns=BARRIER_RELEASE + 5)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [w1, self.writer("W2", 412, b"bbb", None)], b"aaa", '"e"'))

    def test_large_send_skew_refused(self):
        w1 = self.writer("W1", 200, b"aaa", '"e"')._replace(
            send_mono_ns=BARRIER_RELEASE + 1)
        w2 = self.writer("W2", 412, b"bbb", None)._replace(
            send_mono_ns=BARRIER_RELEASE + 10**18)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [w1, w2], b"aaa", '"e"'))

    def test_near_simultaneous_sends_accepted(self):
        w1 = self.writer("W1", 200, b"aaa", '"e-win"')._replace(
            send_mono_ns=BARRIER_RELEASE + 1)
        w2 = self.writer("W2", 412, b"bbb", None)._replace(
            send_mono_ns=BARRIER_RELEASE + 3)
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [w1, w2], b"aaa", '"e-win"'))
        self.assertIs(status, probe.RaceRepetitionStatus.VALID_CAS)

    def test_e2_writer_wrong_if_match_refused(self):
        w1 = self.writer("W1", 200, b"aaa", '"e"')._replace(
            if_match='"different-etag"')
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [w1, self.writer("W2", 412, b"bbb", None)], b"aaa", '"e"'))

    def test_e2_with_absence_confirmed_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(self.repetition(
                [self.writer("W1", 200, b"aaa", '"e"'),
                 self.writer("W2", 412, b"bbb", None)], b"aaa", '"e"',
                absence_confirmed=True))

    def test_f_without_absence_refused(self):
        writers = [self.writer("W1", 200, b"aaa", '"e"', test="F"),
                   self.writer("W2", 412, b"bbb", None, test="F")]
        rep = probe.RaceRepetition(
            identity=self.identity("F"), shared_original_etag=None,
            absence_confirmed=False, barrier=BARRIER, writers=tuple(writers),
            final_state=probe.RemoteState.CONFIRMED,
            final_sha256=hashlib.sha256(b"aaa").hexdigest(),
            final_length=3, final_etag='"e-win"')
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_race_repetition(rep)

    def test_one_writer_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.classify_race_repetition(self.repetition(
                [self.writer("W1", 200, b"a", '"e"')], b"a", '"e"'))

    def test_three_writers_refused(self):
        writers = [self.writer(f"W{i}", 412, bytes([i]) * 3, None)
                   for i in range(3)]
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.classify_race_repetition(
                self.repetition(writers, b"\x00\x00\x00", '"e"'))

    def test_duplicate_writer_id_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.classify_race_repetition(self.repetition(
                [self.writer("W", 200, b"aaa", '"e"'),
                 self.writer("W", 412, b"bbb", None)], b"aaa", '"e"'))

    def test_identical_payloads_refused(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.classify_race_repetition(self.repetition(
                [self.writer("W1", 200, b"same", '"e"'),
                 self.writer("W2", 412, b"same", None)], b"same", '"e"'))

    def test_two_winners_abandon(self):
        status, reason, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 200, b"aaa", '"e1"'),
             self.writer("W2", 200, b"bbb", '"e2"')], b"bbb", '"e2"'))
        self.assertIs(status, probe.RaceRepetitionStatus.ABANDON)
        self.assertIn("safety property", reason)

    def test_zero_winners_inconclusive(self):
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 412, b"aaa", None),
             self.writer("W2", 429, b"bbb", None)], b"zzz", '"e"'))
        self.assertIs(status, probe.RaceRepetitionStatus.INCONCLUSIVE)

    def test_missing_final_etag_inconclusive(self):
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 200, b"aaa", '"e-win"'),
             self.writer("W2", 412, b"bbb", None)], b"aaa", None))
        self.assertIs(status, probe.RaceRepetitionStatus.INCONCLUSIVE)

    def test_winner_etag_ne_final_etag_inconclusive(self):
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 200, b"aaa", '"e-win"'),
             self.writer("W2", 412, b"bbb", None)], b"aaa", '"other"'))
        self.assertIs(status, probe.RaceRepetitionStatus.INCONCLUSIVE)

    def test_matching_hash_wrong_length_inconclusive(self):
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 200, b"aaa", '"e-win"'),
             self.writer("W2", 412, b"bbb", None)], b"aaa", '"e-win"',
            final_length=999))
        self.assertIs(status, probe.RaceRepetitionStatus.INCONCLUSIVE)

    def test_final_matches_loser_abandons(self):
        status, _, _ = probe.classify_race_repetition(self.repetition(
            [self.writer("W1", 200, b"aaa", '"e-win"'),
             self.writer("W2", 412, b"bbb", None)], b"bbb", '"e-win"'))
        self.assertIs(status, probe.RaceRepetitionStatus.ABANDON)

    def test_attribution_mapping(self):
        self.assertIs(probe.attribute_loser(412), probe.RaceAttribution.CAS)
        self.assertIs(probe.attribute_loser(429),
                      probe.RaceAttribution.THROTTLE)
        for status in (200, 403, 500, None):
            self.assertIsNone(probe.attribute_loser(status))


class RaceAggregatorTests(unittest.TestCase):
    """HIGH 1: fixed-purpose race acceptance, thresholds from the matrix."""

    def setUp(self):
        self.alloc = probe.ProbeKeyAllocator(RUN_ID)

    def rep(self, test_id, n, loser_status):
        winner = race_writer("W1", 200, b"aaa" + bytes([n % 251]),
                             '"e-%d"' % n, test=test_id)
        loser = race_writer("W2", loser_status, b"bbb" + bytes([n % 251]),
                            None, test=test_id)
        ident = self.alloc.allocate_race(phase="t", test_id=test_id,
                                         repetition=n).identity
        final = b"aaa" + bytes([n % 251])
        kwargs = dict(
            identity=ident, barrier=BARRIER, writers=(winner, loser),
            final_state=probe.RemoteState.CONFIRMED,
            final_sha256=hashlib.sha256(final).hexdigest(),
            final_length=len(final), final_etag='"e-%d"' % n)
        if test_id == "E2":
            kwargs.update(shared_original_etag=SHARED_ETAG,
                          absence_confirmed=None)
        else:
            kwargs.update(shared_original_etag=None, absence_confirmed=True)
        return probe.RaceRepetition(**kwargs)

    def test_no_constructor_or_overall_params(self):
        import inspect
        self.assertEqual(set(inspect.signature(
            probe.RaceAggregator.__init__).parameters), {"self"})
        self.assertEqual(set(inspect.signature(
            probe.RaceAggregator.overall).parameters), {"self"})

    def test_thresholds_from_matrix(self):
        spec = probe.test_spec("E2")
        self.assertEqual(spec.required_repetitions, 30)
        self.assertEqual(spec.max_attempts, 45)
        agg = probe.RaceAggregator()
        for n in range(1, spec.required_repetitions + 1):
            agg.record(self.rep("E2", n, 412))
        self.assertIs(agg.verdict("E2")[0], probe.Verdict.PASS)

    def test_below_required_fails(self):
        agg = probe.RaceAggregator()
        for n in range(1, 30):   # one short of 30
            agg.record(self.rep("E2", n, 412))
        self.assertIs(agg.verdict("E2")[0], probe.Verdict.FAIL)

    def test_throttled_repetitions_do_not_count(self):
        agg = probe.RaceAggregator()
        for n in range(1, 31):
            agg.record(self.rep("E2", n, 429))   # all throttled
        verdict, reason = agg.verdict("E2")
        self.assertIs(verdict, probe.Verdict.FAIL)
        self.assertIn("INCONCLUSIVE", reason)

    def test_duplicate_identity_refused(self):
        agg = probe.RaceAggregator()
        agg.record(self.rep("E2", 1, 412))
        with self.assertRaises(probe.SafetyBarrierTripped):
            agg.record(self.rep("E2", 1, 412))

    def test_abandon_dominates(self):
        agg = probe.RaceAggregator()
        # one abandon repetition
        winner = race_writer("W1", 200, b"aaa", '"e"')
        winner2 = race_writer("W2", 200, b"bbb", '"e2"')
        ident = self.alloc.allocate_race(phase="t", test_id="E2",
                                         repetition=1).identity
        agg.record(probe.RaceRepetition(
            identity=ident, shared_original_etag=SHARED_ETAG,
            absence_confirmed=None, barrier=BARRIER, writers=(winner, winner2),
            final_state=probe.RemoteState.CONFIRMED,
            final_sha256=hashlib.sha256(b"bbb").hexdigest(),
            final_length=3, final_etag='"e2"'))
        self.assertIs(agg.verdict("E2")[0], probe.Verdict.ABANDON)

    def test_race_verdict_wrapper_still_works(self):
        verdict, _, _ = probe.race_verdict(self.rep("E2", 1, 412))
        self.assertIs(verdict, probe.Verdict.PASS)
        verdict, _, _ = probe.race_verdict(self.rep("E2", 2, 429))
        self.assertIs(verdict, probe.Verdict.FAIL)   # throttle not PASS


# ═══════════════════════════════════════════════════════════════════════════
# HIGH 3 — evidence record schema
# ═══════════════════════════════════════════════════════════════════════════

class EvidenceFieldValidationTests(unittest.TestCase):

    def test_no_default_str_in_json_serialisation(self):
        """No json.dump/dumps call may pass `default=`.

        Checked structurally rather than by raw text: a text scan would
        fire on the explanatory comment, and argparse's unrelated
        `add_argument(default=None)` is legitimate. The concern is
        precisely that a JSON serialiser could stringify a rogue object
        into evidence.
        """
        found = []
        for node in ast.walk(probe_ast()):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            is_json_dump = (
                isinstance(func, ast.Attribute)
                and func.attr in ("dump", "dumps")
                and isinstance(func.value, ast.Name)
                and func.value.id == "json")
            if is_json_dump:
                for keyword in node.keywords:
                    if keyword.arg == "default":
                        found.append(node.lineno)
        self.assertEqual(found, [],
                         f"json.dumps(default=...) at lines {found}")

    def test_nested_dict_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record(
                {"phase": {"authorization": "secret"}})

    def test_list_in_scalar_field_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"status": [200]})

    def test_object_with_malicious_str_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"phase": EvilRepr()})

    def test_str_subclass_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record(
                {"phase": EvilStr("T", PRODUCTION_BUCKET)})

    def test_full_r2_host_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"error_message": ENDPOINT_HOST})

    def test_bare_account_id_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"error_code": "a" * 32})
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"request_id": ACCOUNT_ID})

    def test_authorization_shaped_value_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record(
                {"error_message": "AWS4-HMAC-SHA256 Credential=x"})

    def test_jwt_shaped_value_refused(self):
        jwt = "eyJhbGciOi.eyJidWNrZXQi.c2lnbmF0dXJl"
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"request_id": jwt})

    def test_session_token_shaped_value_refused(self):
        token = base64.b64encode(b"jwt/" + b"x" * 64).decode()
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"error_message": token})

    def test_huge_string_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"error_message": "x" * 5000})

    def test_unknown_field_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"surprise": "x"})

    def test_wrong_bucket_refused(self):
        # Any non-probe bucket is refused; the field validator fires before
        # the denylist scan, so accept either refusal class.
        for bucket in ("some-other-bucket", PRODUCTION_BUCKET):
            with self.subTest(bucket=bucket):
                with self.assertRaises(probe.ProbeError):
                    probe.validate_evidence_record({"bucket": bucket})

    def test_non_probe_key_refused(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record({"key": "catalog/v1/manifest.json"})

    def test_out_of_range_and_wrong_type_scalars_refused(self):
        for record in ({"status": 999}, {"status": "412"},
                       {"repetition": 0}, {"repetition": True},
                       {"session_token_present": "yes"},
                       {"request_body_len": -1},
                       {"endpoint_host_sha256": "abc"},
                       {"http_method": "PATCH"},
                       {"phase": "X"}, {"group": "T-ADMIN"},
                       {"test_id": "ZZ"},
                       {"race_attribution": "MAYBE"},
                       {"remote_state": "PROBABLY"},
                       {"exception_type_name": "bad name!"},
                       {"signed_headers": ["Host"]},
                       {"signed_headers": "host"},
                       {"etag_raw": "not-an-etag"}):
            with self.subTest(record=record):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_evidence_record(record)

    def test_valid_record_accepted(self):
        probe.validate_evidence_record({
            "phase": "T", "group": "T-CAS-1", "test_id": "B",
            "repetition": 1, "sequence": 0, "bucket": PROBE_BUCKET,
            "key": probe_key(), "http_method": "PUT", "status": 412,
            "endpoint_host_sha256": hashlib.sha256(b"x").hexdigest(),
            "etag_raw": '"abc"', "etag_raw_hex": hex(0)[2:] + "0",
            "signed_headers": ["authorization", "x-amz-date"],
            "session_token_present": True,
            "repetition_status": "VALID",
            "remote_state": "CONFIRMED",
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
        })

    def test_weak_and_star_and_dotted_etags_accepted(self):
        # HIGH 3: ordinary opaque ETags — including dotted ones — pass.
        for etag in ('W/"abc"', "*", '"d41d8cd98f00b204e9800998ecf8427e"',
                     '"abc.def.ghi"', 'W/"v1.2.3-opaque"'):
            with self.subTest(etag=etag):
                probe.validate_evidence_record({"if_match_raw": etag})

    def test_credential_shaped_etag_inner_refused(self):
        """HIGH 3: unwrap (W/)?"..." and inspect the INNER value — a quoted
        session token / JWT / Authorization value is rejected."""
        # NOTE: a bare 32-hex value is NOT included — that is a legitimate
        # single-part MD5 ETag, not a credential. The endpoint host, JWT,
        # session-token and Authorization shapes are what must be rejected.
        jwt = "eyJhbGciOiJIUzI1NiJ9.eyJidWNrZXQiOiJ4In0.c2lnbmF0dXJlaGVyZQ"
        session = base64.b64encode(b"jwt/" + b"x" * 64).decode()
        for inner in (jwt, session, "AWS4-HMAC-SHA256 Credential=x",
                      ENDPOINT_HOST):
            for wrapped in (f'"{inner}"', f'W/"{inner}"'):
                with self.subTest(wrapped=wrapped[:24]):
                    with self.assertRaises(probe.EvidenceValidationError):
                        probe.validate_evidence_record(
                            {"etag_raw": wrapped})

    def test_ordinary_md5_etag_accepted(self):
        # A normal single-part MD5 ETag is 32 hex; it must NOT be mistaken
        # for an account id.
        probe.validate_evidence_record(
            {"etag_raw": '"d41d8cd98f00b204e9800998ecf8427e"'})

    def test_embedded_account_id_in_longer_etag_rejected(self):
        """MEDIUM 2: exactly-32-hex is a legitimate MD5 ETag, but a 32-hex
        account-id run embedded inside a LONGER ETag is rejected."""
        acct = "0" * 32
        for field in ("etag_raw", "if_match_raw", "if_none_match_raw",
                      "final_etag"):
            for wrapped in (f'"opaque-{acct}-tail"', f'W/"{acct}-tail"',
                            f'"prefix{acct}"'):
                with self.subTest(field=field, wrapped=wrapped[:20]):
                    with self.assertRaises(probe.EvidenceValidationError):
                        probe.validate_evidence_record({field: wrapped})
        # But the bare 32-hex remains fine in every ETag field.
        for field in ("etag_raw", "if_match_raw", "final_etag"):
            probe.validate_evidence_record({field: f'"{acct}"'})

    def test_free_text_scans_anywhere_not_just_prefix(self):
        # A dangerous shape embedded mid-string is caught.
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_evidence_record(
                {"error_message": f"failed near {ACCOUNT_ID} today"})

    def test_evidence_writer_requires_explicit_secrets(self):
        import inspect
        params = inspect.signature(probe.EvidenceWriter.__init__).parameters
        self.assertIn("secrets", params)
        self.assertIs(params["secrets"].default,
                      inspect.Parameter.empty,
                      "secrets must not default at the persistence boundary")


class DerivedSummaryTests(unittest.TestCase):
    """BLOCKER 3: the RUN_SUMMARY verdict is DERIVED — there is no path to
    persist a caller-chosen verdict, and PASS is impossible unless every
    gate says PASS."""

    def _semantic_all_pass(self):
        agg = probe.SemanticAggregator()
        for test_id in probe.semantic_test_ids():
            for rep in range(1, 11):
                ident = probe.RepetitionIdentity(
                    phase="t", run_id=RUN_ID, test_id=test_id, repetition=rep,
                    key=probe_key(test_id, rep))
                agg.record(probe.SemanticEvidence(
                    identity=ident, http_status=412,
                    outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                    mutation_observed=False))
        return agg

    def _race_all_pass(self):
        agg = probe.RaceAggregator()
        alloc = probe.ProbeKeyAllocator("run-race")
        for test_id in probe.race_test_ids():
            for n in range(1, probe.test_spec(test_id).required_repetitions + 1):
                winner = race_writer("W1", 200, b"aaa" + bytes([n % 251]),
                                     '"e-%d"' % n, test=test_id)
                loser = race_writer("W2", 412, b"bbb" + bytes([n % 251]),
                                    None, test=test_id)
                ident = alloc.allocate_race(phase="t", test_id=test_id,
                                            repetition=n).identity
                final = b"aaa" + bytes([n % 251])
                kwargs = dict(
                    identity=ident, barrier=BARRIER, writers=(winner, loser),
                    final_state=probe.RemoteState.CONFIRMED,
                    final_sha256=hashlib.sha256(final).hexdigest(),
                    final_length=len(final), final_etag='"e-%d"' % n)
                if test_id == "E2":
                    kwargs.update(shared_original_etag=SHARED_ETAG,
                                  absence_confirmed=None)
                else:
                    kwargs.update(shared_original_etag=None,
                                  absence_confirmed=True)
                agg.record(probe.RaceRepetition(**kwargs))
        return agg

    def _full_completion(self):
        """Completion counted ONLY from DERIVED TEST_RESULT_RECORDs written
        through a real writer (BLOCKER 1) — there is no counter API."""
        return completion_from_support_evidence(self)

    def test_empty_run_is_incomplete_never_pass(self):
        s = probe.derive_run_summary(
            phase="T", semantic=probe.SemanticAggregator(),
            race=probe.RaceAggregator(), ledger=probe.ResourceLedger())
        self.assertEqual(s["verdict"], "INCOMPLETE")

    def test_pass_only_when_every_gate_passes(self):
        s = probe.derive_run_summary(
            phase="T", semantic=self._semantic_all_pass(),
            race=self._race_all_pass(), ledger=probe.ResourceLedger(),
            completion=self._full_completion())
        self.assertEqual(s["verdict"], "PASS")
        probe.validate_summary(s, ())

    def test_missing_semantic_tests_blocks_pass(self):
        # Semantic all pass, race all pass, but non-semantic tests not
        # reported complete → INCOMPLETE.
        s = probe.derive_run_summary(
            phase="T", semantic=self._semantic_all_pass(),
            race=self._race_all_pass(), ledger=probe.ResourceLedger())
        self.assertEqual(s["verdict"], "INCOMPLETE")

    def test_poisoned_ledger_forces_abandon(self):
        ledger = probe.ResourceLedger.for_testing(
            probe.ResourceCaps(60, 1, 1000, 300, 10**9, 10**9))
        ledger.reserve_put("catalog/probe/t/1", 1)
        with self.assertRaises(probe.CapExceeded):
            ledger.reserve_put("catalog/probe/t/2", 1)
        s = probe.derive_run_summary(
            phase="T", semantic=self._semantic_all_pass(),
            race=self._race_all_pass(), ledger=ledger,
            completion=self._full_completion())
        self.assertEqual(s["verdict"], "ABANDON")
        self.assertTrue(s["ledger_poisoned"])

    def test_abandon_semantic_forces_abandon(self):
        agg = probe.SemanticAggregator()
        ident = probe.RepetitionIdentity(
            phase="t", run_id=RUN_ID, test_id="B", repetition=1,
            key=probe_key("B", 1))
        agg.record(probe.SemanticEvidence(
            identity=ident, http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=True))   # mutation despite precondition
        s = probe.derive_run_summary(
            phase="T", semantic=agg, race=probe.RaceAggregator(),
            ledger=probe.ResourceLedger())
        self.assertEqual(s["verdict"], "ABANDON")

    def test_finalize_takes_no_caller_state(self):
        """BLOCKER 1: finalize accepts NO caller aggregator/ledger/
        completion/verdict — it uses writer-owned state only."""
        import inspect
        params = set(inspect.signature(
            probe.EvidenceWriter.finalize).parameters)
        self.assertEqual(params, {"self"})


class WriterOwnedAcceptanceTests(unittest.TestCase):
    """BLOCKER 1: the final PASS is tied to persisted evidence the writer
    itself produced. No externally-prepared state can create a PASS."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def writer(self, run_id="run-acc"):
        return probe.EvidenceWriter.for_testing(self.root, run_id)

    def _fill_semantic(self, w):
        for test_id in probe.semantic_test_ids():
            for rep in range(1, 11):
                iss = w.allocate_semantic(test_id, rep)
                w.write_semantic_record(
                    iss, http_status=412,
                    outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                    mutation_observed=False)

    def _fill_race(self, w):
        for test_id in probe.race_test_ids():
            n = probe.test_spec(test_id).required_repetitions
            for rep in range(1, n + 1):
                iss = w.allocate_race(test_id, rep)
                ident = iss.identity
                w1 = race_writer("W1", 200, b"aaa" + bytes([rep % 251]),
                                 '"e-%d"' % rep, test=test_id)
                w2 = race_writer("W2", 412, b"bbb" + bytes([rep % 251]),
                                 None, test=test_id)
                final = b"aaa" + bytes([rep % 251])
                kwargs = dict(
                    identity=ident, barrier=BARRIER, writers=(w1, w2),
                    final_state=probe.RemoteState.CONFIRMED,
                    final_sha256=hashlib.sha256(final).hexdigest(),
                    final_length=len(final), final_etag='"e-%d"' % rep)
                if test_id == "E2":
                    kwargs.update(shared_original_etag=SHARED_ETAG,
                                  absence_confirmed=None)
                else:
                    kwargs.update(shared_original_etag=None,
                                  absence_confirmed=True)
                w.write_race_record(iss, probe.RaceRepetition(**kwargs))

    def _fill_completion(self, w):
        """Every support-row repetition is backed by a persisted request,
        response and TEST_RESULT_RECORD (BLOCKER 1). There is no way to
        assert completion without the evidence files."""
        for spec in support_specs():
            for rep in range(1, spec.required_repetitions + 1):
                write_support_repetition(w, spec, rep)

    def test_zero_records_cannot_pass(self):
        w = self.writer("run-empty")
        self.assertEqual(w.finalize()["verdict"], "INCOMPLETE")

    def test_full_run_passes(self):
        w = self.writer("run-full")
        self._fill_semantic(w)
        self._fill_race(w)
        self._fill_completion(w)
        self.assertEqual(w.finalize()["verdict"], "PASS")

    def test_semantic_but_no_completion_is_incomplete(self):
        w = self.writer("run-partial")
        self._fill_semantic(w)
        self._fill_race(w)
        self.assertEqual(w.finalize()["verdict"], "INCOMPLETE")

    def test_dropping_a_record_from_the_index_prevents_pass(self):
        w = self.writer("run-del")
        self._fill_semantic(w)
        self._fill_race(w)
        self._fill_completion(w)
        # Remove one persisted semantic file from the manifest index. The
        # file is still on disk, so the two now disagree → refused.
        victim = next(rel for rel in w._files if rel.startswith("semantic"))
        del w._files[victim]
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_fabricated_identity_cannot_write(self):
        w = self.writer("run-fab")
        good = w.allocate_semantic("B", 1)
        fake = probe.IssuedIdentity(identity=good.identity, nonce="run-x:1")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.write_semantic_record(
                fake, http_status=412,
                outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                mutation_observed=False)

    def test_nonce_cannot_be_reused(self):
        w = self.writer("run-reuse")
        iss = w.allocate_semantic("B", 1)
        w.write_semantic_record(
            iss, http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.write_semantic_record(
                iss, http_status=412,
                outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                mutation_observed=False)

    def test_mutation_run_abandons(self):
        w = self.writer("run-mut")
        self._fill_race(w)
        self._fill_completion(w)
        # Nine clean B reps then a mutation on rep 10.
        for rep in range(1, 10):
            iss = w.allocate_semantic("B", rep)
            w.write_semantic_record(
                iss, http_status=412,
                outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                mutation_observed=False)
        iss = w.allocate_semantic("B", 10)
        w.write_semantic_record(
            iss, http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=True)   # mutation despite precondition
        for test_id in ("D", "E1"):
            for rep in range(1, 11):
                i = w.allocate_semantic(test_id, rep)
                w.write_semantic_record(
                    i, http_status=412,
                    outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                    mutation_observed=False)
        self.assertEqual(w.finalize()["verdict"], "ABANDON")


# ═══════════════════════════════════════════════════════════════════════════
# BLOCKER 2 — the PHYSICAL persisted records are the source of truth
# ═══════════════════════════════════════════════════════════════════════════

class DiskAuthoritativeFinalizationTests(unittest.TestCase):
    """Finalization rebuilds every aggregator from the files on disk.

    Codex's reproduction: with in-memory state authorizing PASS, deleting a
    persisted evidence file left the verdict at PASS. These tests pin the
    corrected model — a deleted, altered, extra, misplaced, unmanifested,
    untyped, oversized or foreign file makes PASS impossible.
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def _passing_writer(self, run_id="run-disk"):
        w = probe.EvidenceWriter.for_testing(self.root, run_id)
        for test_id in probe.semantic_test_ids():
            for rep in range(1, 11):
                w.write_semantic_record(
                    w.allocate_semantic(test_id, rep), http_status=412,
                    outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                    mutation_observed=False)
        for test_id in probe.race_test_ids():
            for rep in range(1, probe.test_spec(
                    test_id).required_repetitions + 1):
                iss = w.allocate_race(test_id, rep)
                final = b"aaa" + bytes([rep % 251])
                kwargs = dict(
                    identity=iss.identity, barrier=BARRIER,
                    writers=(race_writer("W1", 200, final, '"e-%d"' % rep,
                                         test=test_id),
                             race_writer("W2", 412,
                                         b"bbb" + bytes([rep % 251]), None,
                                         test=test_id)),
                    final_state=probe.RemoteState.CONFIRMED,
                    final_sha256=hashlib.sha256(final).hexdigest(),
                    final_length=len(final), final_etag='"e-%d"' % rep)
                if test_id == "E2":
                    kwargs.update(shared_original_etag=SHARED_ETAG,
                                  absence_confirmed=None)
                else:
                    kwargs.update(shared_original_etag=None,
                                  absence_confirmed=True)
                w.write_race_record(iss, probe.RaceRepetition(**kwargs))
        for spec in support_specs():
            for rep in range(1, spec.required_repetitions + 1):
                write_support_repetition(w, spec, rep)
        return w

    def _path(self, w, relative):
        return os.path.join(w.run_dir, relative)

    def _a(self, w, prefix):
        return next(rel for rel in sorted(w._files)
                    if rel.startswith(prefix))

    # ── the baseline: a real bundle still passes ─────────────────────────

    def test_full_bundle_passes_from_disk(self):
        w = self._passing_writer()
        result = w.finalize()
        self.assertEqual(result["verdict"], "PASS")
        # The manifest records exactly the physical files.
        with open(result["manifest_path"], encoding="utf-8") as fh:
            manifest = json.load(fh)
        on_disk = set(probe._iter_evidence_files(w.run_dir))
        self.assertEqual(set(manifest["files"]), on_disk)

    # ── Codex's exact reproduction ───────────────────────────────────────

    def test_deleting_a_physical_record_prevents_pass(self):
        """CODEX REPRODUCTION: the file is removed from DISK only; the
        in-memory aggregators are untouched and still 'know' it passed."""
        for prefix in ("semantic_record/", "race_record/",
                       "test_result_record/", "request/", "response/"):
            with self.subTest(prefix=prefix):
                tmp = tempfile.TemporaryDirectory()
                self.addCleanup(tmp.cleanup)
                self.root = os.path.join(tmp.name, "bible-pal")
                w = self._passing_writer("run-del-phys")
                os.unlink(self._path(w, self._a(w, prefix)))
                with self.assertRaises(probe.SafetyBarrierTripped):
                    w.finalize()

    def test_altering_a_persisted_byte_prevents_pass(self):
        w = self._passing_writer()
        victim = self._path(w, self._a(w, "semantic_record/"))
        with open(victim, "r+b") as fh:
            body = bytearray(fh.read())
            body[-2] = body[-2] ^ 0x20   # one byte, still parseable JSON
            fh.seek(0)
            fh.write(bytes(body))
            fh.truncate()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_extra_unmanifested_file_prevents_pass(self):
        w = self._passing_writer()
        extra = self._path(w, "semantic_record/b/0099.json")
        with open(extra, "w", encoding="utf-8") as fh:
            json.dump({"record_kind": "SEMANTIC_RECORD"}, fh)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_dropping_a_persisted_identity_prevents_pass(self):
        """The in-memory identity registry cannot silently shrink."""
        w = self._passing_writer()
        pair = next(iter(w._persisted))
        del w._persisted[pair]
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_extra_index_entry_prevents_pass(self):
        w = self._passing_writer()
        w._files["semantic_record/b/0099.json"] = "0" * 64
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_forged_index_digest_prevents_pass(self):
        w = self._passing_writer()
        victim = self._a(w, "race_record/")
        w._files[victim] = "1" * 64
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    # ── structural refusals during enumeration ──────────────────────────

    def test_symlinked_evidence_file_prevents_pass(self):
        w = self._passing_writer()
        real = self._path(w, self._a(w, "semantic_record/"))
        link = self._path(w, "semantic_record/b/0098.json")
        os.symlink(real, link)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_unexpected_evidence_directory_prevents_pass(self):
        w = self._passing_writer()
        os.mkdir(self._path(w, "extra_records"), 0o700)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_stray_top_level_file_prevents_pass(self):
        w = self._passing_writer()
        with open(self._path(w, "notes.txt"), "w", encoding="utf-8") as fh:
            fh.write("hello")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_generic_untyped_file_prevents_pass(self):
        """Written through the writer's OWN low-level helper, so it is even
        recorded in the index — an untyped file still fails closed."""
        w = self._passing_writer()
        w._write_bytes("semantic_record/b/extra.json",
                       b'{"hello": "world"}')
        with self.assertRaises((probe.SafetyBarrierTripped,
                                probe.EvidenceValidationError)):
            w.finalize()

    def test_non_json_evidence_file_prevents_pass(self):
        w = self._passing_writer()
        with open(self._path(w, "semantic_record/b/notes.txt"), "w",
                  encoding="utf-8") as fh:
            fh.write("hello")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_oversized_evidence_file_prevents_pass(self):
        w = self._passing_writer()
        victim = self._path(w, self._a(w, "semantic_record/"))
        with open(victim, "wb") as fh:
            fh.write(b"{}" + b" " * (probe.MAX_EVIDENCE_FILE_BYTES + 1))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_unparseable_evidence_file_prevents_pass(self):
        w = self._passing_writer()
        victim = self._path(w, self._a(w, "semantic_record/"))
        with open(victim, "wb") as fh:
            fh.write(b"{not json")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    # ── content-level refusals during reconstruction ────────────────────

    def test_record_at_the_wrong_path_prevents_pass(self):
        """A valid record copied to a second name is a duplicate identity;
        the canonical path is derived from the record itself."""
        w = self._passing_writer()
        victim = self._a(w, "semantic_record/")
        with open(self._path(w, victim), "rb") as fh:
            payload = fh.read()
        moved = "semantic_record/b/0097.json"
        with open(self._path(w, moved), "wb") as fh:
            fh.write(payload)
        w._files[moved] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_foreign_run_record_prevents_pass(self):
        """A fully self-consistent record from ANOTHER run is still refused,
        because reconstruction scopes every record to this run id."""
        w = self._passing_writer()
        spec = probe.test_spec("H2")   # not used by _passing_writer's rep 1
        other_tmp = tempfile.TemporaryDirectory()
        self.addCleanup(other_tmp.cleanup)
        other = probe.EvidenceWriter.for_testing(
            os.path.join(other_tmp.name, "bp"), "run-other")
        relative = write_support_repetition(other, spec, 1)
        with open(os.path.join(other.run_dir, relative), "rb") as fh:
            payload = fh.read()
        record = json.loads(payload)
        self.assertEqual(record["run_id"], "run-other")
        self.assertEqual(probe.validate_record(record, ()),
                         "TEST_RESULT_RECORD")
        # Drop the foreign run's own file into THIS bundle, indexed.
        os.unlink(self._path(w, relative))
        with open(self._path(w, relative), "wb") as fh:
            fh.write(payload)
        w._files[relative] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_foreign_run_key_prevents_pass(self):
        """A record whose allocated key belongs to another run is refused —
        the key's run component is cross-checked against the record."""
        w = self._passing_writer()
        victim = self._a(w, "semantic_record/")
        with open(self._path(w, victim), encoding="utf-8") as fh:
            record = json.load(fh)
        record["key"] = probe_key(record["test_id"], record["repetition"],
                                  run_id="run-other")
        payload = json.dumps(record, sort_keys=True, indent=2,
                             ensure_ascii=False).encode("utf-8")
        with open(self._path(w, victim), "wb") as fh:
            fh.write(payload)
        w._files[victim] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises((probe.SafetyBarrierTripped,
                                probe.EvidenceValidationError)):
            w.finalize()

    def test_stored_result_must_match_the_recomputed_one(self):
        """A SELF-CONSISTENT but wrong stored result is still refused:
        reconstruction recomputes it from the referenced physical evidence
        and requires equality (BLOCKER 1)."""
        w = self._passing_writer()
        victim = self._a(w, "test_result_record/")
        with open(self._path(w, victim), encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertTrue(record["derived_valid"])
        # Downgrade coherently — the structural validator has no complaint.
        record["outcome_classification"] = "INCONCLUSIVE"
        record["derived_valid"] = False
        record["derived_production_size"] = False
        self.assertEqual(probe.validate_record(record, ()),
                         "TEST_RESULT_RECORD")
        payload = json.dumps(record, sort_keys=True, indent=2,
                             ensure_ascii=False).encode("utf-8")
        with open(self._path(w, victim), "wb") as fh:
            fh.write(payload)
        w._files[victim] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_upgraded_stored_result_is_refused(self):
        """The same check in the other direction: a losing repetition
        relabelled as a win cannot survive recomputation."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-upgrade")
        spec = probe.test_spec("H4")
        relative = write_support_repetition(
            w, spec, 1,
            facts=SUPPORT_EVIDENCE["H4"]._replace(
                status=200, etag='"e"', error_code=None))
        with open(self._path(w, relative), encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertEqual(record["outcome_classification"], "INCONCLUSIVE")
        record["outcome_classification"] = "SCOPE_DENIED_OK"
        record["derived_valid"] = True
        payload = json.dumps(record, sort_keys=True, indent=2,
                             ensure_ascii=False).encode("utf-8")
        with open(self._path(w, relative), "wb") as fh:
            fh.write(payload)
        w._files[relative] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_orphan_response_on_disk_prevents_pass(self):
        """Even if the writer's registry is consistent, a response whose
        request file is gone is an orphan at reconstruction."""
        w = self._passing_writer()
        request = self._a(w, "request/")
        os.unlink(self._path(w, request))
        del w._files[request]
        del w._requests[
            next(c for c in w._requests
                 if probe.expected_relative_for_record(
                     {"record_kind": "REQUEST_RECORD",
                      "correlation_id": c}) == request)]
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_reconstruction_refuses_a_foreign_phase(self):
        w = self._passing_writer()
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="P", run_id=w.run_id, secrets=(),
                issued_registry=w._allocator.issued_registry())

    def test_reconstruction_rejects_bad_arguments(self):
        w = self._passing_writer()
        for kwargs in ({"phase": "X"}, {"phase": True},
                       {"run_id": "no"}, {"run_id": None}):
            base = {"phase": "T", "run_id": w.run_id, "secrets": (),
                    "issued_registry": w._allocator.issued_registry()}
            base.update(kwargs)
            with self.subTest(**kwargs):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.reconstruct_run_from_disk(w.run_dir, **base)

    def test_empty_run_is_incomplete_not_pass(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-nothing")
        self.assertEqual(w.finalize()["verdict"], "INCOMPLETE")

    def test_in_memory_aggregators_are_not_the_authority(self):
        """The writer keeps fail-fast aggregators, but finalize ignores them:
        a bundle with no support evidence is INCOMPLETE even though the
        semantic/race aggregators are fully satisfied in memory."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-failfast")
        for test_id in probe.semantic_test_ids():
            for rep in range(1, 11):
                w.write_semantic_record(
                    w.allocate_semantic(test_id, rep), http_status=412,
                    outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                    mutation_observed=False)
        self.assertEqual(len(w._semantic.valid("B")), 10)
        self.assertEqual(w.finalize()["verdict"], "INCOMPLETE")

    def test_no_completion_authority_on_the_writer(self):
        """BLOCKER 1: the bare-counter completion API is DELETED, and the
        writer holds no MatrixCompletion of its own."""
        self.assertFalse(hasattr(probe.EvidenceWriter, "report_completion"))
        self.assertFalse(hasattr(probe.MatrixCompletion, "report"))
        w = probe.EvidenceWriter.for_testing(self.root, "run-nocount")
        self.assertFalse(hasattr(w, "_completion"))


class TestResultRecordWriterTests(unittest.TestCase):
    """BLOCKER 1 + 2: a support row completes only via DERIVED results."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)
        self.w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        self.spec = probe.test_spec("H1")

    def _ref(self, rep=1, sequence=1, test_id=None):
        return probe.Correlation(
            phase="T", run_id=RUN_ID,
            test_id=test_id if test_id is not None else self.spec.id,
            repetition=rep, sequence=sequence).serialize()

    def test_writer_takes_no_outcome_or_production_argument(self):
        """The two caller-authority arguments are DELETED."""
        import inspect
        params = set(inspect.signature(
            probe.EvidenceWriter.write_test_result_record).parameters)
        self.assertEqual(params, {"self", "issued", "evidence_ref", "group"})
        for gone in ("outcome_classification", "production_size",
                     "observations", "evidence_refs", "valid"):
            self.assertNotIn(gone, params)

    def test_result_requires_persisted_response_evidence(self):
        issued = self.w.allocate_semantic(self.spec.id, 1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_test_result_record(issued, evidence_ref=self._ref())

    def test_result_rejects_malformed_reference(self):
        issued = self.w.allocate_semantic(self.spec.id, 1)
        for ref in (None, 1, [], "H1/1/1", ""):
            with self.subTest(ref=ref):
                with self.assertRaises((probe.SafetyBarrierTripped,
                                        probe.EvidenceValidationError)):
                    self.w.write_test_result_record(issued, evidence_ref=ref)

    def test_result_rejects_cross_test_reference(self):
        write_correlated_evidence(self.w, probe.test_spec("H2"), 1)
        issued = self.w.allocate_semantic(self.spec.id, 1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_test_result_record(
                issued, evidence_ref=self._ref(test_id="H2"))

    def test_result_refuses_semantic_and_race_rows(self):
        for test_id in probe.semantic_test_ids() + probe.race_test_ids():
            with self.subTest(test_id=test_id):
                issued = self.w.allocate_semantic(test_id, 1)
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self.w.write_test_result_record(
                        issued, evidence_ref=self._ref(test_id=test_id))

    def test_denial_row_cannot_be_satisfied_by_success(self):
        """CODEX REPRODUCTION: H4 is the DeleteObject DENIAL row. Three
        HTTP 200 responses must NOT complete it, whatever anyone calls
        them — there is no argument left to call them anything."""
        spec = probe.test_spec("H4")
        success = SUPPORT_EVIDENCE["H4"]._replace(
            status=200, etag='"e"', error_code=None)
        completion = probe.MatrixCompletion()
        for rep in range(1, spec.required_repetitions + 1):
            relative = write_support_repetition(self.w, spec, rep,
                                                facts=success)
            record = self._read(relative)
            self.assertEqual(record["outcome_classification"], "INCONCLUSIVE")
            self.assertFalse(record["derived_valid"])
            completion.count_persisted_test_result(record)
        self.assertFalse(completion.is_complete("H4"))

    def test_denial_row_is_satisfied_by_an_actual_denial(self):
        spec = probe.test_spec("H4")
        completion = probe.MatrixCompletion()
        for rep in range(1, spec.required_repetitions + 1):
            record = self._read(write_support_repetition(self.w, spec, rep))
            self.assertEqual(record["outcome_classification"],
                             "SCOPE_DENIED_OK")
            self.assertTrue(record["derived_valid"])
            completion.count_persisted_test_result(record)
        self.assertTrue(completion.is_complete("H4"))

    def test_category_mismatched_outcomes_are_unreachable(self):
        """No support row can produce another category's outcome."""
        forbidden = {
            "H1": {"ARCHIVE_CREATED", "AUDIT_CREATED", "ABSENT_CONFIRMED"},
            "X1": {"SCOPE_ALLOWED_OK", "SCOPE_DENIED_OK"},
            "K1": {"SIGNING_CONTRACT_OK", "ARCHIVE_CREATED"},
        }
        for test_id, banned in forbidden.items():
            spec = probe.test_spec(test_id)
            for facts in (SUPPORT_EVIDENCE[test_id],
                          SUPPORT_EVIDENCE[test_id]._replace(status=200),
                          SUPPORT_EVIDENCE[test_id]._replace(status=403)):
                with self.subTest(test_id=test_id, status=facts.status):
                    tmp = tempfile.TemporaryDirectory()
                    self.addCleanup(tmp.cleanup)
                    w = probe.EvidenceWriter.for_testing(
                        os.path.join(tmp.name, "bp"), RUN_ID)
                    relative = write_support_repetition(w, spec, 1,
                                                        facts=facts)
                    outcome = self._read(relative, writer=w)[
                        "outcome_classification"]
                    self.assertNotIn(outcome, banned)

    def test_validity_is_derived_not_asserted(self):
        facts = SUPPORT_EVIDENCE["H1"]._replace(status=500)
        record = self._read(
            write_support_repetition(self.w, self.spec, 1, facts=facts))
        self.assertEqual(record["outcome_classification"], "INCONCLUSIVE")
        self.assertFalse(record["derived_valid"])
        completion = probe.MatrixCompletion()
        completion.count_persisted_test_result(record)
        self.assertEqual(completion.counts(self.spec.id), (0, 1, 0))
        self.assertFalse(completion.is_complete(self.spec.id))

    def test_duplicate_result_for_a_repetition_refused(self):
        write_support_repetition(self.w, self.spec, 1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.allocate_semantic(self.spec.id, 1)
        corr = write_correlated_evidence(self.w, self.spec, 2)
        issued = self.w.allocate_semantic(self.spec.id, 2)
        self.w.write_test_result_record(issued, evidence_ref=corr)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_test_result_record(issued, evidence_ref=corr)

    def _read(self, relative, writer=None):
        writer = writer if writer is not None else self.w
        with open(os.path.join(writer.run_dir, relative),
                  encoding="utf-8") as fh:
            return json.load(fh)


class PerTestDerivationTableTests(unittest.TestCase):
    """BLOCKER 1: every support row has its OWN derivation, and there is no
    shared cross-category success list."""

    def _sequence(self, spec):
        """K3's throttled attempt is the SECOND same-key write."""
        return 2 if spec.id == "K3" else 1

    def _siblings(self, spec, rep=1):
        """K3 needs an earlier same-key PUT to have really happened."""
        if spec.id != "K3":
            return ()
        first, _ = self._pair(
            spec,
            SUPPORT_EVIDENCE["K3"]._replace(status=200, etag='"e"',
                                            error_code=None),
            rep=rep, sequence=1)
        return (first,)

    def _pair(self, spec, facts, rep=1, sequence=1):
        """Build the request/response pair a derivation sees, without any
        writer involved."""
        key = facts.key if facts.key is not None else probe_key(
            spec.id, rep, run_id=RUN_ID)
        signed, credential = sign_support_request(spec, key, facts)
        request = probe.build_request_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id=spec.id,
            repetition=rep, sequence=sequence, endpoint_host=ENDPOINT_HOST,
            signed=signed, credential=credential)
        headers = () if facts.etag is None else (("ETag", facts.etag),)
        body = (b"" if facts.error_code is None else
                f"<Error><Code>{facts.error_code}</Code></Error>".encode())
        resp = probe.RawResponse(
            status=facts.status, headers=headers, body=body,
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        response = probe.build_response_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id=spec.id,
            repetition=rep, sequence=sequence, response=resp,
            parsed=probe.parse_s3_error(body) if body else None,
            repetition_status=None,
            final_get_sha256=(hashlib.sha256(facts.body).hexdigest()
                              if facts.readback else None),
            final_get_len=len(facts.body) if facts.readback else None,
            remote_state=(probe.RemoteState(facts.remote_state)
                          if facts.remote_state else None))
        if facts.final_etag is not None:
            response["final_etag"] = facts.final_etag
        return request, response

    def test_every_support_row_has_its_own_derivation(self):
        table = probe._derivations()
        self.assertEqual(set(table), {s.id for s in support_specs()})
        # Distinct callables — no row shares another row's semantics by
        # accident, apart from the deliberately parameterised scope rows.
        self.assertGreaterEqual(len({id(f) for f in table.values()}),
                                len(table))

    def test_semantic_and_race_rows_have_no_derivation(self):
        for test_id in probe.semantic_test_ids() + probe.race_test_ids():
            with self.subTest(test_id=test_id):
                self.assertNotIn(test_id, probe._derivations())
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.derive_test_result(
                        probe.test_spec(test_id), {}, {})

    def test_happy_path_facts_derive_the_expected_outcome(self):
        expected = {
            "A": "CORRECT_ETAG_ACCEPTED", "C": "CREATE_IF_ABSENT_OK",
            "G": "ETAG_ROUNDTRIP_OK", "H1": "SCOPE_ALLOWED_OK",
            "H2": "SCOPE_ALLOWED_OK", "H3": "SCOPE_ALLOWED_OK",
            "H4": "SCOPE_DENIED_OK", "H5": "SCOPE_DENIED_OK",
            "H6": "SCOPE_DENIED_OK", "H7": "SCOPE_DENIED_OK",
            "I1": "SIGNING_CONTRACT_OK",
            "I2": "SIGNING_DIAGNOSTIC_RECORDED",
            "I3": "SIGNING_CONTRACT_OK",
            "I4": "CREDENTIAL_EXPIRY_ENFORCED",
            "K1": "ABSENT_CONFIRMED", "K2": "DENIAL_CONTRAST_OK",
            "K3": "THROTTLE_OBSERVED", "J": "SINGLE_PART_PROVEN",
            "L": "BYTE_INTEGRITY_OK", "X1": "ARCHIVE_CREATED",
            "X2": "AUDIT_CREATED",
        }
        self.assertEqual(set(expected), {s.id for s in support_specs()})
        for test_id, outcome in expected.items():
            with self.subTest(test_id=test_id):
                spec = probe.test_spec(test_id)
                request, response = self._pair(spec,
                                               SUPPORT_EVIDENCE[test_id],
                                               sequence=self._sequence(spec))
                result = probe.derive_test_result(
                    spec, request, response,
                    sibling_requests=self._siblings(spec))
                self.assertEqual(result.outcome, outcome)
                self.assertTrue(result.valid)
                self.assertEqual(result.production_size, test_id == "J")

    def test_a_2xx_can_never_satisfy_a_denial_row(self):
        for test_id in ("H4", "H5", "H6", "H7"):
            spec = probe.test_spec(test_id)
            for status in (200, 201, 204):
                with self.subTest(test_id=test_id, status=status):
                    facts = SUPPORT_EVIDENCE[test_id]._replace(
                        status=status, etag='"e"', error_code=None)
                    result = probe.derive_test_result(
                        spec, *self._pair(spec, facts))
                    self.assertEqual(result.outcome, "INCONCLUSIVE")
                    self.assertFalse(result.valid)

    def test_wrong_method_never_satisfies_a_row(self):
        for test_id, wrong in (("H1", "PUT"), ("H2", "HEAD"),
                               ("H4", "GET"), ("K1", "PUT"), ("J", "GET"),
                               ("A", "GET"), ("C", "GET"), ("L", "GET")):
            with self.subTest(test_id=test_id, method=wrong):
                spec = probe.test_spec(test_id)
                facts = SUPPORT_EVIDENCE[test_id]._replace(method=wrong)
                result = probe.derive_test_result(
                    spec, *self._pair(spec, facts))
                self.assertEqual(result.outcome, "INCONCLUSIVE")

    def test_wrong_key_target_never_satisfies_a_denial_row(self):
        swaps = {
            "H4": _OUT_OF_PREFIX, "H6": _SACRIFICIAL,
            "H7": _SACRIFICIAL, "K2": _SACRIFICIAL,
        }
        for test_id, key in swaps.items():
            with self.subTest(test_id=test_id):
                spec = probe.test_spec(test_id)
                facts = SUPPORT_EVIDENCE[test_id]._replace(key=key)
                result = probe.derive_test_result(
                    spec, *self._pair(spec, facts))
                self.assertEqual(result.outcome, "INCONCLUSIVE")

    def test_absence_uses_the_existing_classifier(self):
        spec = probe.test_spec("K1")
        # HEAD 404 is deliberately NOT absence.
        for facts in (SUPPORT_EVIDENCE["K1"]._replace(method="HEAD"),
                      SUPPORT_EVIDENCE["K1"]._replace(error_code="NoSuchBucket"),
                      SUPPORT_EVIDENCE["K1"]._replace(status=403)):
            with self.subTest(facts=facts):
                result = probe.derive_test_result(
                    spec, *self._pair(spec, facts))
                self.assertEqual(result.outcome, "INCONCLUSIVE")

    def test_throttle_requires_an_actual_429(self):
        spec = probe.test_spec("K3")
        for status in (200, 403, 503):
            with self.subTest(status=status):
                facts = SUPPORT_EVIDENCE["K3"]._replace(status=status)
                self.assertEqual(
                    probe.derive_test_result(
                        spec, *self._pair(spec, facts)).outcome,
                    "INCONCLUSIVE")

    def test_signing_rows_read_signed_headers(self):
        # I1 requires the token to be IN SignedHeaders.
        spec = probe.test_spec("I1")
        request, response = self._pair(spec, SUPPORT_EVIDENCE["I1"])
        self.assertIn("x-amz-security-token", request["signed_headers"])
        # Remove it: the row can no longer be satisfied.
        request["signed_headers"] = [h for h in request["signed_headers"]
                                     if h != "x-amz-security-token"]
        self.assertEqual(
            probe.derive_test_result(spec, request, response).outcome,
            "INCONCLUSIVE")

    def test_i3_requires_an_actual_rejection(self):
        spec = probe.test_spec("I3")
        facts = SUPPORT_EVIDENCE["I3"]._replace(status=200, etag='"e"',
                                                error_code=None)
        self.assertEqual(
            probe.derive_test_result(spec, *self._pair(spec, facts)).outcome,
            "INCONCLUSIVE")

    def test_readback_mismatch_fails_integrity_rows(self):
        for test_id in ("A", "C", "G", "L"):
            with self.subTest(test_id=test_id):
                spec = probe.test_spec(test_id)
                request, response = self._pair(spec,
                                               SUPPORT_EVIDENCE[test_id])
                response["final_get_sha256"] = "f" * 64
                self.assertEqual(
                    probe.derive_test_result(spec, request, response).outcome,
                    "INCONCLUSIVE")

    def test_archive_and_audit_run_through_their_classifiers(self):
        for test_id, idempotent in (("X1", "ARCHIVE_IDEMPOTENT"),
                                    ("X2", "AUDIT_IDEMPOTENT")):
            spec = probe.test_spec(test_id)
            with self.subTest(test_id=test_id, case="idempotent"):
                facts = SUPPORT_EVIDENCE[test_id]._replace(
                    status=412, etag=None, error_code="PreconditionFailed")
                self.assertEqual(
                    probe.derive_test_result(
                        spec, *self._pair(spec, facts)).outcome,
                    idempotent)
            with self.subTest(test_id=test_id, case="collision"):
                facts = SUPPORT_EVIDENCE[test_id]._replace(
                    status=412, etag=None, error_code="PreconditionFailed",
                    readback=False, remote_state="CONFIRMED")
                self.assertEqual(
                    probe.derive_test_result(
                        spec, *self._pair(spec, facts)).outcome,
                    "INCONCLUSIVE")

    def test_derivation_refuses_mismatched_evidence(self):
        spec = probe.test_spec("H1")
        request, response = self._pair(spec, SUPPORT_EVIDENCE["H1"])
        other = probe.test_spec("H2")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.derive_test_result(other, request, response)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.derive_test_result(spec, response, request)
        mismatched = dict(response, correlation_id=probe.Correlation(
            phase="T", run_id=RUN_ID, test_id="H1", repetition=1,
            sequence=9).serialize())
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.derive_test_result(spec, request, mismatched)


class FabricatedIssuanceTests(unittest.TestCase):
    """BLOCKER 1: Codex's exact reproduction — ten fabricated B issuance
    records plus ten matching B semantic records, with the allocator never
    called, must not reach a PASS."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def _issuance(self, w, rep):
        return {
            "record_kind": "ISSUANCE_RECORD", "phase": "T",
            "run_id": w.run_id, "test_id": "B", "repetition": rep,
            "key": probe_key("B", rep, run_id=w.run_id),
            "issuance_nonce": f"{w.run_id}:{rep:06d}",
            "identity_kind": "semantic"}

    def _semantic(self, w, rep):
        return {
            "record_kind": "SEMANTIC_RECORD", "phase": "T",
            "run_id": w.run_id, "group": "T-CAS-1", "test_id": "B",
            "repetition": rep, "key": probe_key("B", rep, run_id=w.run_id),
            "issuance_nonce": f"{w.run_id}:{rep:06d}", "status": 412,
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
            "mutation_observed": False, "credential_expired": False,
            "repetition_status": "VALID"}

    def test_persist_typed_refuses_issuance_records(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab1")
        record = self._issuance(w, 1)
        # Shape-valid: the refusal is structural, not a validation accident.
        self.assertEqual(probe.validate_record(record, ()),
                         "ISSUANCE_RECORD")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w._persist_typed("ISSUANCE_RECORD", "B", 1, record)
        self.assertEqual(w._allocator.issued_registry(), {})
        self.assertEqual(w._files, {})

    def test_ten_fabricated_issuances_cannot_pass(self):
        """CODEX REPRODUCTION, verbatim: no allocator call at all."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab2")
        for rep in range(1, 11):
            with self.assertRaises(probe.SafetyBarrierTripped):
                w._persist_typed("ISSUANCE_RECORD", "B", rep,
                                 self._issuance(w, rep))
        self.assertEqual(w._allocator.issued_registry(), {})
        # Even if the semantic records are forced onto disk anyway, the
        # bundle cannot reach PASS.
        for rep in range(1, 11):
            record = self._semantic(w, rep)
            w._write_bytes(probe.expected_relative_for_record(record),
                           json.dumps(record, sort_keys=True, indent=2,
                                      ensure_ascii=False).encode("utf-8"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_fabricated_capability_is_refused(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab3")
        identity = probe.RepetitionIdentity(
            phase="t", run_id=w.run_id, test_id="B", repetition=1,
            key=probe_key("B", 1, run_id=w.run_id))
        forged = probe.IssuedIdentity(identity=identity,
                                      nonce=f"{w.run_id}:000001")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w._persist_allocator_issuance(forged)
        for bogus in (None, "nonce", identity, (identity, "n")):
            with self.subTest(bogus=type(bogus).__name__):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    w._persist_allocator_issuance(bogus)

    def test_foreign_allocator_capability_is_refused(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab4")
        other = probe.ProbeKeyAllocator("run-elsewhere")
        issued = other.allocate(phase="t", test_id="B", repetition=1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w._persist_allocator_issuance(issued)

    def test_real_capability_is_accepted(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab5")
        issued = w.allocate_semantic("B", 1)
        self.assertIn(issued.nonce, w._allocator.issued_registry())
        self.assertIn(("ISSUANCE_RECORD", "B", 1), w._persisted)

    def test_registry_without_physical_issuance_refuses(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab6")
        w.allocate_semantic("B", 1)
        relative = w._persisted[("ISSUANCE_RECORD", "B", 1)]
        os.unlink(os.path.join(w.run_dir, relative))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_physical_issuance_without_registry_entry_refuses(self):
        """A real issuance file, but an allocator that never minted it."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab7")
        w.allocate_semantic("B", 1)
        w._allocator = probe.ProbeKeyAllocator(w.run_id)   # amnesiac issuer
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_reconstruction_requires_the_registry_to_agree(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-fab8")
        w.allocate_semantic("B", 1)
        registry = w._allocator.issued_registry()
        # Agreeing registry: fine.
        probe.reconstruct_run_from_disk(
            w.run_dir, phase="T", run_id=w.run_id, secrets=(),
            issued_registry=registry)
        # A registry claiming a different key for the same nonce: refused.
        nonce = next(iter(registry))
        tampered = dict(registry)
        tampered[nonce] = registry[nonce]._replace(
            key=probe_key("D", 1, run_id=w.run_id))
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                issued_registry=tampered)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                issued_registry={})


class MandatoryIssuanceRegistryTests(unittest.TestCase):
    """BLOCKER 1: acceptance reconstruction cannot run without the
    allocator's issuance registry. There is no optional path."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def _fabricate_ten_b_records(self, w):
        """Ten physical B issuance + semantic records, ZERO allocator
        calls — Codex's exact reproduction."""
        for rep in range(1, 11):
            issuance = {
                "record_kind": "ISSUANCE_RECORD", "phase": "T",
                "run_id": w.run_id, "test_id": "B", "repetition": rep,
                "key": probe_key("B", rep, run_id=w.run_id),
                "issuance_nonce": f"{w.run_id}:{rep:06d}",
                "identity_kind": "semantic"}
            semantic = {
                "record_kind": "SEMANTIC_RECORD", "phase": "T",
                "run_id": w.run_id, "group": "T-CAS-1", "test_id": "B",
                "repetition": rep,
                "key": probe_key("B", rep, run_id=w.run_id),
                "issuance_nonce": f"{w.run_id}:{rep:06d}", "status": 412,
                "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
                "mutation_observed": False, "credential_expired": False,
                "repetition_status": "VALID"}
            for record in (issuance, semantic):
                # Shape-valid on purpose: only issuance authenticity is
                # missing.
                probe.validate_record(record, ())
                w._write_bytes(
                    probe.expected_relative_for_record(record),
                    json.dumps(record, sort_keys=True, indent=2,
                               ensure_ascii=False).encode("utf-8"))
        self.assertEqual(w._allocator.issued_registry(), {})

    def test_registry_is_a_mandatory_keyword_with_no_default(self):
        import inspect
        parameter = inspect.signature(
            probe.reconstruct_run_from_disk).parameters["issued_registry"]
        self.assertIs(parameter.default, inspect.Parameter.empty)
        self.assertIs(parameter.kind, inspect.Parameter.KEYWORD_ONLY)

    def test_no_registry_ten_b_reproduction_cannot_pass(self):
        """CODEX REPRODUCTION: reconstruct without a registry at all."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-noreg")
        self._fabricate_ten_b_records(w)
        with self.assertRaises(TypeError):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=())
        for registry in (None, (), [], "registry", 0):
            with self.subTest(registry=registry):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.reconstruct_run_from_disk(
                        w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                        issued_registry=registry)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                issued_registry={})
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_real_registry_and_matching_issuance_is_accepted(self):
        w = probe.EvidenceWriter.for_testing(self.root, "run-okreg")
        w.write_semantic_record(
            w.allocate_semantic("B", 1), http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        rebuilt = probe.reconstruct_run_from_disk(
            w.run_dir, phase="T", run_id=w.run_id, secrets=(),
            issued_registry=w._allocator.issued_registry())
        self.assertEqual(len(rebuilt.semantic.valid("B")), 1)

    def test_structural_auditor_cannot_return_acceptance_state(self):
        """The registry-free path exists but is incapable of a verdict."""
        w = probe.EvidenceWriter.for_testing(self.root, "run-audit")
        self._fabricate_ten_b_records(w)
        report = probe.inspect_evidence_bundle_structure(w.run_dir)
        self.assertEqual(report["file_count"], 20)
        self.assertEqual(report["counts_by_directory"],
                         {"issuance_record": 10, "semantic_record": 10})
        for value in report.values():
            self.assertNotIsInstance(value, probe.SemanticAggregator)
            self.assertNotIsInstance(value, probe.RaceAggregator)
            self.assertNotIsInstance(value, probe.MatrixCompletion)
        self.assertNotIn("verdict", report)
        source = ast.dump(probe_ast())
        body = source[source.index("inspect_evidence_bundle_structure"):]
        body = body[:body.index("EvidenceWriter")]
        for banned in ("SemanticAggregator", "RaceAggregator",
                       "MatrixCompletion", "derive_run_summary"):
            self.assertNotIn(banned, body)


class TransmittedTokenAuthorityTests(unittest.TestCase):
    """BLOCKER 2: credential facts come from the token that was actually
    transmitted, never from the caller's TemporaryCredential."""

    def _signed(self, credential, *, key=None, amz_date=AMZ_DATE):
        return probe.sign_request(
            target=probe_target(key=key or probe_key("H4", 1)),
            host=ENDPOINT_HOST, access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=credential.session_token, body=b"x",
            amz_date=amz_date)

    def _build(self, credential, signed, *, spec_id="H4", group=None):
        spec = probe.test_spec(spec_id)
        return probe.build_request_record(
            phase="T", run_id=RUN_ID, group=group or spec.group,
            test_id=spec_id, repetition=1, sequence=1,
            endpoint_host=ENDPOINT_HOST, signed=signed,
            credential=credential)

    # ── ATTACK A: fake group ────────────────────────────────────────────
    def test_group_tampering_is_refused(self):
        """CODEX ATTACK A: a real T-CAS-1 token, presented as T-SCOPE."""
        real = group_credential("T-CAS-1")
        signed = self._signed(real)
        tampered = real._replace(group="T-SCOPE")
        with self.assertRaises(probe.SafetyBarrierTripped):
            self._build(tampered, signed)
        # And the honest record never claims T-SCOPE.
        honest = self._build(real, signed, group="T-CAS-1")
        self.assertEqual(honest["credential_group"], "T-CAS-1")

    def test_h4_cannot_be_satisfied_by_a_foreign_group_token(self):
        """The tampered evidence cannot even be constructed, so H4 never
        sees a record claiming its own group."""
        real = group_credential("T-CAS-1")
        signed = probe.sign_request(
            target=probe.RequestTarget(
                method="DELETE", bucket=PROBE_BUCKET,
                key=probe._policy().sacrificial_key),
            host=ENDPOINT_HOST, access_key_id=real.access_key_id,
            secret_access_key=real.secret_access_key,
            session_token=real.session_token, body=b"", amz_date=AMZ_DATE)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.build_request_record(
                phase="T", run_id=RUN_ID, group="T-SCOPE", test_id="H4",
                repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
                signed=signed, credential=real._replace(group="T-SCOPE"))
        # Recorded honestly, the token's real group is T-CAS-1, so the
        # T-SCOPE row H4 derives INCONCLUSIVE.
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-SCOPE", test_id="H4",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed, credential=real)
        self.assertEqual(record["credential_group"], "T-CAS-1")
        response = probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-SCOPE", test_id="H4",
            repetition=1, sequence=1,
            response=probe.RawResponse(
                status=403, headers=(),
                body=b"<Error><Code>AccessDenied</Code></Error>",
                body_truncated=False, t_request_start_mono_ns=1,
                t_response_end_mono_ns=2),
            parsed=probe.parse_s3_error(
                b"<Error><Code>AccessDenied</Code></Error>"),
            repetition_status=None)
        self.assertEqual(
            probe.derive_test_result(probe.test_spec("H4"), record,
                                     response).outcome,
            "INCONCLUSIVE")

    # ── ATTACK B: fake expiry ───────────────────────────────────────────
    def test_expiry_tampering_is_refused(self):
        """CODEX ATTACK B: a token valid for another ~59s, presented as
        already expired."""
        real = group_credential("T-EXPIRY")
        request_time = real.expires_at - 59
        signed = self._signed(real, key=probe_key("I4", 1),
                              amz_date=amz_date_at(request_time))
        tampered = real._replace(expires_at=request_time)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self._build(tampered, signed, spec_id="I4")

    def test_i4_inconclusive_when_the_token_is_still_valid(self):
        real = group_credential("T-EXPIRY")
        request_time = real.expires_at - 59
        signed = self._signed(real, key=probe_key("I4", 1),
                              amz_date=amz_date_at(request_time))
        request = self._build(real, signed, spec_id="I4")
        # The RECORDED expiry is the token's, not any caller's.
        self.assertEqual(request["credential_expires_at"], real.expires_at)
        self.assertLess(request["request_time_epoch"],
                        request["credential_expires_at"])
        response = probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-EXPIRY", test_id="I4",
            repetition=1, sequence=1,
            response=probe.RawResponse(
                status=403, headers=(),
                body=b"<Error><Code>AccessDenied</Code></Error>",
                body_truncated=False, t_request_start_mono_ns=1,
                t_response_end_mono_ns=2),
            parsed=probe.parse_s3_error(
                b"<Error><Code>AccessDenied</Code></Error>"),
            repetition_status=None)
        self.assertEqual(
            probe.derive_test_result(probe.test_spec("I4"), request,
                                     response).outcome,
            "INCONCLUSIVE")

    def test_i4_valid_for_an_honestly_expired_token(self):
        real = group_credential("T-EXPIRY")
        request_time = real.expires_at + 5
        signed = self._signed(real, key=probe_key("I4", 1),
                              amz_date=amz_date_at(request_time))
        request = self._build(real, signed, spec_id="I4")
        self.assertGreaterEqual(request["request_time_epoch"],
                                request["credential_expires_at"])
        response = probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-EXPIRY", test_id="I4",
            repetition=1, sequence=1,
            response=probe.RawResponse(
                status=403, headers=(),
                body=b"<Error><Code>ExpiredToken</Code></Error>",
                body_truncated=False, t_request_start_mono_ns=1,
                t_response_end_mono_ns=2),
            parsed=probe.parse_s3_error(
                b"<Error><Code>ExpiredToken</Code></Error>"),
            repetition_status=None)
        result = probe.derive_test_result(probe.test_spec("I4"), request,
                                          response)
        self.assertEqual(result.outcome, "CREDENTIAL_EXPIRY_ENFORCED")
        self.assertTrue(result.valid)

    # ── C: every fact equals the decoded claim ─────────────────────────
    def test_every_credential_fact_equals_the_decoded_claim(self):
        for group in probe.credential_groups():
            with self.subTest(group=group):
                credential = group_credential(group)
                signed = self._signed(credential)
                record = self._build(credential, signed, group=group,
                                     spec_id="H4")
                claims = probe.validate_transmitted_token_claims(
                    credential.session_token, endpoint_host=ENDPOINT_HOST,
                    access_key_id=credential.access_key_id)
                self.assertEqual(record["credential_group"], claims.group)
                self.assertEqual(record["credential_scope"], claims.scope)
                self.assertEqual(tuple(record["credential_actions"]),
                                 claims.actions)
                self.assertEqual(tuple(record["credential_prefixes"]),
                                 claims.prefix_paths)
                self.assertEqual(record["credential_issued_at"],
                                 claims.issued_at)
                self.assertEqual(record["credential_expires_at"],
                                 claims.expires_at)

    def test_every_replaceable_field_is_cross_checked(self):
        real = group_credential("T-CAS-1")
        signed = self._signed(real)
        for field, value in (("group", "T-SCOPE"),
                             ("scope", "admin-read-write"),
                             ("actions", ("DeleteObject",)),
                             ("prefix_paths", ("",)),
                             ("issued_at", real.issued_at - 1),
                             ("expires_at", real.expires_at + 1),
                             ("bucket", "some-other-bucket")):
            with self.subTest(field=field):
                with self.assertRaises((probe.SafetyBarrierTripped,
                                        probe.ProductionNameDetected)):
                    self._build(real._replace(**{field: value}), signed,
                                group="T-CAS-1")

    def test_a_foreign_token_beside_a_real_credential_is_refused(self):
        real = group_credential("T-CAS-1")
        other = group_credential("T-SCOPE")
        signed = self._signed(other)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self._build(real, signed, group="T-CAS-1")

    # ── E: structural vs transport validation ──────────────────────────
    def test_structural_validator_accepts_an_expired_token(self):
        credential = group_credential("T-EXPIRY")
        claims = probe.validate_transmitted_token_claims(
            credential.session_token, endpoint_host=ENDPOINT_HOST,
            access_key_id=credential.access_key_id)
        self.assertEqual(claims.group, "T-EXPIRY")
        self.assertEqual(claims.expires_at, credential.expires_at)

    def test_transport_validator_still_rejects_an_expired_credential(self):
        credential = group_credential("T-EXPIRY")
        probe.validate_probe_credential_for_transport(
            credential, endpoint_host=ENDPOINT_HOST,
            now=credential.issued_at)
        for now in (credential.expires_at,
                    credential.expires_at + 1,
                    credential.issued_at - 1):
            with self.subTest(now=now):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.validate_probe_credential_for_transport(
                        credential, endpoint_host=ENDPOINT_HOST, now=now)

    def test_structural_validator_still_enforces_policy(self):
        credential = group_credential("T-CAS-1")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_transmitted_token_claims(
                credential.session_token, endpoint_host=ENDPOINT_HOST,
                access_key_id="0" * 40)          # not the issuer
        with self.assertRaises(probe.EndpointRefused):
            probe.validate_transmitted_token_claims(
                credential.session_token, endpoint_host="evil.example.com",
                access_key_id=credential.access_key_id)
        for bogus in ("not-a-token", "", base64.b64encode(b"nope").decode()):
            with self.subTest(bogus=bogus[:12]):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.validate_transmitted_token_claims(
                        bogus, endpoint_host=ENDPOINT_HOST,
                        access_key_id=credential.access_key_id)

    def test_i3_records_no_credential_claims(self):
        """With no token transmitted there is nothing to decode, so the
        builder records no credential facts at all."""
        spec = probe.test_spec("I3")
        signed, credential = sign_support_request(
            spec, probe_key("I3", 1, run_id=RUN_ID), SUPPORT_EVIDENCE["I3"])
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id="I3",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed, credential=credential)
        for field in ("credential_group", "credential_scope",
                      "credential_actions", "credential_prefixes",
                      "credential_issued_at", "credential_expires_at"):
            self.assertIsNone(record[field], field)
        self.assertFalse(record["session_token_present"])


class WeakDerivationRegressionTests(unittest.TestCase):
    """BLOCKER 2: every mandatory row Codex satisfied with weak evidence."""

    def _pair(self, spec, facts, rep=1, sequence=1):
        key = facts.key if facts.key is not None else probe_key(
            spec.id, rep, run_id=RUN_ID)
        signed, credential = sign_support_request(spec, key, facts)
        request = probe.build_request_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id=spec.id,
            repetition=rep, sequence=sequence, endpoint_host=ENDPOINT_HOST,
            signed=signed, credential=credential)
        headers = () if facts.etag is None else (("ETag", facts.etag),)
        body = (b"" if facts.error_code is None else
                f"<Error><Code>{facts.error_code}</Code></Error>".encode())
        resp = probe.RawResponse(
            status=facts.status, headers=headers, body=body,
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        response = probe.build_response_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id=spec.id,
            repetition=rep, sequence=sequence, response=resp,
            parsed=probe.parse_s3_error(body) if body else None,
            repetition_status=None,
            final_get_sha256=(hashlib.sha256(facts.body).hexdigest()
                              if facts.readback else None),
            final_get_len=len(facts.body) if facts.readback else None,
            remote_state=(probe.RemoteState(facts.remote_state)
                          if facts.remote_state else None))
        if facts.final_etag is not None:
            response["final_etag"] = facts.final_etag
        return request, response

    def _derived_outcome(self, test_id, facts, siblings=(), sequence=1):
        spec = probe.test_spec(test_id)
        request, response = self._pair(spec, facts, sequence=sequence)
        return probe.derive_test_result(spec, request, response,
                                        sibling_requests=siblings).outcome

    # ── H4: DELETE + 403 with NO child token ────────────────────────────
    def test_h4_without_a_child_token_is_inconclusive(self):
        for mode in ("none", "omitted", "unsigned"):
            with self.subTest(token_mode=mode):
                facts = SUPPORT_EVIDENCE["H4"]._replace(token_mode=mode)
                self.assertEqual(self._derived_outcome("H4", facts), "INCONCLUSIVE")
        self.assertEqual(self._derived_outcome("H4", SUPPORT_EVIDENCE["H4"]),
                         "SCOPE_DENIED_OK")

    def test_h1_to_h7_all_require_the_child_credential(self):
        for test_id in ("H1", "H2", "H3", "H4", "H5", "H6", "H7",
                        "I1", "K1", "K2"):
            with self.subTest(test_id=test_id):
                facts = SUPPORT_EVIDENCE[test_id]._replace(token_mode="none")
                self.assertEqual(self._derived_outcome(test_id, facts),
                                 "INCONCLUSIVE")

    def test_group_is_part_of_the_signed_credential(self):
        """Two groups must not mint byte-identical child credentials, or
        "the credential for this group" would not be a provable fact."""
        tokens = {g: group_credential(g).session_token
                  for g in probe.credential_groups()}
        self.assertEqual(len(set(tokens.values())), len(tokens))

    def test_a_credential_from_another_group_is_refused(self):
        spec = probe.test_spec("H1")
        key = probe_key("H1", 1, run_id=RUN_ID)
        facts = SUPPORT_EVIDENCE["H1"]
        foreign = group_credential("T-CAS-1")   # H1 lives in T-SCOPE
        signed = probe.sign_request(
            target=probe.RequestTarget(method=facts.method,
                                       bucket=PROBE_BUCKET, key=key),
            host=ENDPOINT_HOST, access_key_id=foreign.access_key_id,
            secret_access_key=foreign.secret_access_key,
            session_token=foreign.session_token, body=facts.body,
            amz_date=AMZ_DATE)
        request = probe.build_request_record(
            phase="T", run_id=RUN_ID, group=spec.group, test_id="H1",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed, credential=foreign)
        _, response = self._pair(spec, facts)
        self.assertEqual(
            probe.derive_test_result(spec, request, response).outcome,
            "INCONCLUSIVE")

    def test_recorded_credential_must_have_signed_the_request(self):
        spec = probe.test_spec("H1")
        facts = SUPPORT_EVIDENCE["H1"]
        signed, credential = sign_support_request(
            spec, probe_key("H1", 1, run_id=RUN_ID), facts)
        del credential
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.build_request_record(
                phase="T", run_id=RUN_ID, group=spec.group, test_id="H1",
                repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
                signed=signed, credential=group_credential("T-CAS-1"))

    # ── H5: an ordinary object GET is not a ListObjectsV2 ───────────────
    def test_h5_ordinary_object_get_403_is_inconclusive(self):
        facts = SUPPORT_EVIDENCE["H5"]._replace(key=None, query=())
        self.assertEqual(self._derived_outcome("H5", facts), "INCONCLUSIVE")

    def test_h5_requires_the_list_type_query(self):
        for query in ((), (("list-type", "1"),), (("prefix", "catalog/"),)):
            with self.subTest(query=query):
                facts = SUPPORT_EVIDENCE["H5"]._replace(query=query)
                self.assertEqual(self._derived_outcome("H5", facts), "INCONCLUSIVE")
        self.assertEqual(self._derived_outcome("H5", SUPPORT_EVIDENCE["H5"]),
                         "SCOPE_DENIED_OK")

    # ── I2: the token must really have been transmitted ────────────────
    def test_i2_without_a_transmitted_token_is_inconclusive(self):
        for mode in ("omitted", "none", "signed"):
            with self.subTest(token_mode=mode):
                facts = SUPPORT_EVIDENCE["I2"]._replace(token_mode=mode)
                self.assertEqual(self._derived_outcome("I2", facts), "INCONCLUSIVE")
        self.assertEqual(self._derived_outcome("I2", SUPPORT_EVIDENCE["I2"]),
                         "SIGNING_DIAGNOSTIC_RECORDED")

    def test_token_presence_cannot_be_claimed_by_a_caller(self):
        import inspect
        params = set(inspect.signature(probe.build_request_record).parameters)
        self.assertNotIn("session_token_present", params)
        self.assertNotIn("session_token_sha256", params)
        # And the derived value follows the wire, not any argument.
        spec = probe.test_spec("I2")
        request, _ = self._pair(spec, SUPPORT_EVIDENCE["I2"])
        self.assertTrue(request["session_token_present"])
        self.assertFalse(request["session_token_signed"])
        self.assertNotIn(probe._grammar().security_token_header,
                         request["signed_headers"])

    # ── I4: expiry must be proven, not assumed ─────────────────────────
    def test_i4_inside_the_validity_window_is_inconclusive(self):
        for offset in (0, 1, _EXPIRY_TTL - 1):
            with self.subTest(offset=offset):
                facts = SUPPORT_EVIDENCE["I4"]._replace(
                    signing_offset=offset, error_code="AccessDenied")
                self.assertEqual(self._derived_outcome("I4", facts), "INCONCLUSIVE")

    def test_i4_after_expiry_is_valid(self):
        request, response = self._pair(probe.test_spec("I4"),
                                       SUPPORT_EVIDENCE["I4"])
        self.assertGreaterEqual(request["request_time_epoch"],
                                request["credential_expires_at"])
        self.assertEqual(self._derived_outcome("I4", SUPPORT_EVIDENCE["I4"]),
                         "CREDENTIAL_EXPIRY_ENFORCED")
        del response

    # ── K3: one 429 proves nothing ─────────────────────────────────────
    def test_k3_single_head_429_is_inconclusive(self):
        facts = SUPPORT_EVIDENCE["K3"]._replace(method="HEAD")
        self.assertEqual(self._derived_outcome("K3", facts), "INCONCLUSIVE")

    def test_k3_single_put_429_with_no_prior_write_is_inconclusive(self):
        self.assertEqual(self._derived_outcome("K3", SUPPORT_EVIDENCE["K3"]),
                         "INCONCLUSIVE")

    def test_k3_requires_a_prior_same_key_put(self):
        spec = probe.test_spec("K3")
        first, _ = self._pair(
            spec, SUPPORT_EVIDENCE["K3"]._replace(status=200, etag='"e"',
                                                  error_code=None),
            sequence=1)
        self.assertEqual(
            self._derived_outcome("K3", SUPPORT_EVIDENCE["K3"], siblings=(first,),
                          sequence=2),
            "THROTTLE_OBSERVED")
        # A prior GET, or a prior PUT to a different key, does not count.
        other_key, _ = self._pair(
            spec, SUPPORT_EVIDENCE["K3"]._replace(
                status=200, etag='"e"', error_code=None,
                key=probe._policy().sacrificial_key), sequence=1)
        self.assertEqual(
            self._derived_outcome("K3", SUPPORT_EVIDENCE["K3"],
                          siblings=(other_key,), sequence=2),
            "INCONCLUSIVE")

    # ── X1 / X2: unconditional writes cannot satisfy create-only ───────
    def test_x1_and_x2_reject_unconditional_requests(self):
        for test_id in ("X1", "X2"):
            for facts in (SUPPORT_EVIDENCE[test_id]._replace(
                              if_none_match=None),
                          SUPPORT_EVIDENCE[test_id]._replace(method="GET"),
                          SUPPORT_EVIDENCE[test_id]._replace(
                              if_none_match=None, method="GET")):
                with self.subTest(test_id=test_id, method=facts.method,
                                  inm=facts.if_none_match):
                    self.assertEqual(self._derived_outcome(test_id, facts),
                                     "INCONCLUSIVE")

    def test_x1_and_x2_412_requires_exact_readback(self):
        for test_id, idempotent in (("X1", "ARCHIVE_IDEMPOTENT"),
                                    ("X2", "AUDIT_IDEMPOTENT")):
            base = SUPPORT_EVIDENCE[test_id]._replace(
                status=412, etag=None, error_code="PreconditionFailed")
            with self.subTest(test_id=test_id, case="exact"):
                self.assertEqual(self._derived_outcome(test_id, base), idempotent)
            with self.subTest(test_id=test_id, case="no readback"):
                self.assertEqual(
                    self._derived_outcome(test_id, base._replace(readback=False)),
                    "INCONCLUSIVE")
            with self.subTest(test_id=test_id, case="unconfirmed"):
                self.assertEqual(
                    self._derived_outcome(test_id, base._replace(remote_state=None)),
                    "INCONCLUSIVE")

    def test_no_archive_placeholders_remain(self):
        """The version/semantic-hash placeholders are DELETED, and the row
        descriptions claim only raw-byte idempotency."""
        for name in ("_ARCHIVE_PLACEHOLDER_VERSION",
                     "_ARCHIVE_PLACEHOLDER_SEMANTIC_SHA256"):
            self.assertFalse(hasattr(probe, name))
        for test_id in ("X1", "X2"):
            description = probe.test_spec(test_id).description
            self.assertIn("raw-byte", description)
            self.assertNotIn("version", description)


class ValidationGrammarIsolationTests(unittest.TestCase):
    """BLOCKER 3: a SYSTEMATIC sweep. Rebind every module-level grammar
    name to a permissive/empty/wrong value and verify that nothing which
    was rejected becomes accepted, and nothing valid becomes invalid."""

    #: Every module-level grammar alias, discovered rather than listed by
    #: hand, so a future addition cannot quietly escape the sweep.
    GRAMMAR_NAMES = tuple(sorted(
        name for name in vars(probe)
        if (name.endswith("_RE") or name.endswith("_OUTCOMES")
            or name in ("_ALLOWED_METHODS", "_ALLOWED_HTTP_METHODS",
                        "_ALLOWED_PHASES", "_EMPTY_SHA256",
                        "_BLANK_PARSED_ERROR", "_RAW_HEX_PAIRS",
                        "_RECORD_KIND_DIRS", "MANIFEST_FILENAME",
                        "INCONCLUSIVE", "RECORD_KINDS",
                        "ACCEPTANCE_RECORD_KINDS", "TEST_RESULT_OUTCOMES",
                        "MAX_EVIDENCE_FILE_BYTES"))))

    class _MatchAnything:
        """A stand-in that says yes to everything."""

        def fullmatch(self, *a, **k):
            class _M:
                def group(self, *_a, **_k):
                    return "anything"
            return _M()

        match = fullmatch

        def search(self, *a, **k):
            return None       # "no credential shape here, honest"

    def setUp(self):
        self._saved = {name: getattr(probe, name)
                       for name in self.GRAMMAR_NAMES}
        self.addCleanup(self._restore)

    def _restore(self):
        for name, value in self._saved.items():
            setattr(probe, name, value)

    def _subvert(self):
        permissive = self._MatchAnything()
        for name in self.GRAMMAR_NAMES:
            current = getattr(probe, name)
            if hasattr(current, "fullmatch"):
                setattr(probe, name, permissive)
            elif isinstance(current, frozenset):
                setattr(probe, name, frozenset())
            elif isinstance(current, (tuple, list)):
                setattr(probe, name, ())
            elif isinstance(current, dict):
                setattr(probe, name, {})
            elif isinstance(current, str):
                setattr(probe, name, "")
            elif isinstance(current, int):
                setattr(probe, name, 1)
            else:
                setattr(probe, name, None)

    def test_the_sweep_actually_covers_the_grammar(self):
        for expected in ("_ETAG_RE", "_SHA256_RE", "_CORRELATION_RE",
                         "_ALLOCATED_KEY_RE", "_ISSUANCE_NONCE_RE",
                         "_CRED_RE", "_ACCOUNT_ID_RE", "_JWT_ANYWHERE_RE",
                         "_SESSION_TOKEN_ANYWHERE_RE", "_LIVE_KEY_RE",
                         "_TRANSPORT_ONLY_OUTCOMES", "_SUCCESS_OUTCOMES"):
            self.assertIn(expected, self.GRAMMAR_NAMES)
        self.assertGreaterEqual(len(self.GRAMMAR_NAMES), 25)

    def test_malformed_values_stay_rejected(self):
        """Codex's exact reproduction is the first case: rebinding
        _ETAG_RE must not turn a malformed ETag into a valid one."""
        cases = [
            ("etag", {"etag_raw": "not-an-etag"}),
            ("etag weird", {"etag_raw": "<script>"}),
            ("sha256", {"request_body_sha256": "nothex"}),
            ("key", {"key": "catalog/v1/manifest.json"}),
            ("http method", {"http_method": "PATCH"}),
            ("phase", {"phase": "X"}),
            ("group", {"group": "T-ADMIN"}),
            ("test id", {"test_id": "ZZ"}),
            ("correlation", {"correlation_id": "B/1/1"}),
            ("nonce", {"issuance_nonce": "not-a-nonce"}),
            ("cf-ray", {"cf_ray": "bad ray!"}),
            ("signed headers", {"signed_headers": ["Host"]}),
            ("identifier", {"exception_type_name": "bad name!"}),
            ("writer id", {"writer_id": "bad id!"}),
            ("barrier", {"barrier_generation_id": "bad gen!"}),
            ("status", {"status": 999}),
        ]
        for label, record in cases:
            with self.subTest(label=label, when="before"):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_evidence_record(record)
        self._subvert()
        for label, record in cases:
            with self.subTest(label=label, when="after"):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_evidence_record(record)

    def test_credential_shapes_stay_rejected(self):
        leaks = [
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhYmMifQ.c2lnbmF0dXJlLXZhbHVl",
            "and0L2V5SmhiR2NpT2lKSVV6STFOaUo5Cg==",
            "0" * 32,
            f"{ACCOUNT_ID}.r2.cloudflarestorage.com",
        ]
        for leak in leaks:
            with self.subTest(leak=leak[:16], when="before"):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_evidence_record({"error_message": leak})
        self._subvert()
        for leak in leaks:
            with self.subTest(leak=leak[:16], when="after"):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_evidence_record({"error_message": leak})

    def test_valid_values_stay_valid(self):
        good = {
            "phase": "T", "group": "T-CAS-1", "test_id": "B",
            "repetition": 1, "sequence": 0, "bucket": PROBE_BUCKET,
            "key": probe_key(), "http_method": "PUT", "status": 412,
            "endpoint_host_sha256": hashlib.sha256(b"x").hexdigest(),
            "etag_raw": '"abc"', "etag_raw_hex": probe.hex_of('"abc"'),
            "signed_headers": ["authorization", "x-amz-date"],
            "session_token_present": True,
            "repetition_status": "VALID", "remote_state": "CONFIRMED",
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
        }
        probe.validate_evidence_record(good)
        self._subvert()
        probe.validate_evidence_record(good)

    def test_allowed_outcomes_for_status_is_unchanged(self):
        before = {status: probe.allowed_outcomes_for_status(status)
                  for status in (None, 200, 201, 400, 401, 403, 412, 429,
                                 500, 503)}
        self._subvert()
        after = {status: probe.allowed_outcomes_for_status(status)
                 for status in before}
        self.assertEqual(before, after)
        for status in (100, 302):
            with self.subTest(status=status):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.allowed_outcomes_for_status(status)

    def test_signing_and_endpoint_shapes_stay_enforced(self):
        self._subvert()
        with self.assertRaises(probe.EndpointRefused):
            probe.sign_request(
                target=probe_target(), host="evil.example.com",
                access_key_id=AKID, secret_access_key=SECRET,
                session_token=None, body=b"x", amz_date=AMZ_DATE)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.sign_request(
                target=probe_target(), host=ENDPOINT_HOST,
                access_key_id=AKID, secret_access_key=SECRET,
                session_token=None, body=b"x", amz_date="not-a-date")
        with self.assertRaises(probe.EndpointRefused):
            probe.build_endpoint_host("not-an-account-id")

    def test_identity_and_correlation_shapes_stay_enforced(self):
        self._subvert()
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.ProbeKeyAllocator("NO")
        with self.assertRaises((probe.SafetyBarrierTripped,
                                probe.EvidenceValidationError)):
            probe.parse_correlation("B/1/1")
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.validate_repetition_identity(probe.RepetitionIdentity(
                phase="t", run_id=RUN_ID, test_id="B", repetition=1,
                key="catalog/v1/manifest.json"))

    def test_parse_error_stays_blank_when_unparseable(self):
        blank = probe.parse_s3_error(b"<<<not xml")
        self._subvert()
        self.assertEqual(probe.parse_s3_error(b"<<<not xml"), blank)
        self.assertIsNone(probe.parse_s3_error(b"<<<not xml").code)

    def test_a_full_bundle_still_passes_after_rebinding(self):
        """The sweep must not be vacuous in the other direction either."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        w = probe.EvidenceWriter.for_testing(
            os.path.join(tmp.name, "bp"), RUN_ID)
        spec = probe.test_spec("H1")
        self._subvert()
        relative = write_support_repetition(w, spec, 1)
        with open(os.path.join(w.run_dir, relative), encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["outcome_classification"],
                             "SCOPE_ALLOWED_OK")


class MatrixClaimTests(unittest.TestCase):
    """Every support row's description must state only what it proves."""

    def test_credential_claiming_rows_actually_require_a_credential(self):
        claims_credential = {
            spec.id for spec in support_specs()
            if "child" in spec.description or "token" in spec.description}
        self.assertEqual(
            claims_credential,
            {"H1", "H2", "H3", "H4", "H5", "H6", "H7",
             "I1", "I2", "I3", "K1", "K2"})

    def test_no_row_claims_a_scope_prefix_it_cannot_observe(self):
        # "under catalog/" claimed a prefix-scoping property the row never
        # persisted; it is gone.
        for spec in support_specs():
            with self.subTest(test_id=spec.id):
                self.assertNotIn("under catalog/", spec.description)

    def test_i4_description_states_the_timing_property(self):
        self.assertIn("expires_at", probe.test_spec("I4").description)

    def test_k3_description_states_repeated_same_key_writes(self):
        self.assertIn("same-key", probe.test_spec("K3").description)

    def test_h5_description_states_the_list_query(self):
        self.assertIn("list-type=2", probe.test_spec("H5").description)


class ProductionSizeDerivationTests(unittest.TestCase):
    """BLOCKER 2: production size comes from the persisted REQUEST_RECORD's
    request_body_len, never from a caller flag."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)
        self.spec = probe.test_spec("J")

    def _run(self, facts):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        completion = probe.MatrixCompletion()
        for rep in range(1, self.spec.required_repetitions + 1):
            relative = write_support_repetition(w, self.spec, rep,
                                                facts=facts)
            with open(os.path.join(w.run_dir, relative),
                      encoding="utf-8") as fh:
                completion.count_persisted_test_result(json.load(fh))
        return completion

    def test_one_byte_j_never_counts_as_production_size(self):
        completion = self._run(SUPPORT_EVIDENCE["J"]._replace(body=b"x"))
        valid, attempts, production = completion.counts("J")
        self.assertEqual(production, 0)
        self.assertEqual(valid, 0)
        self.assertEqual(attempts, self.spec.required_repetitions)
        self.assertFalse(completion.is_complete("J"))

    def test_exact_production_size_counts(self):
        completion = self._run(SUPPORT_EVIDENCE["J"])
        valid, attempts, production = completion.counts("J")
        self.assertEqual(production, self.spec.production_size_repetitions)
        self.assertEqual(valid, self.spec.required_repetitions)
        self.assertTrue(completion.is_complete("J"))

    def test_off_by_one_body_lengths_are_refused(self):
        exact = probe.PRODUCTION_BODY_BYTES
        self.assertEqual(exact, 2_589_207)
        # One byte short: signs fine, but derives non-production-size.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        w = probe.EvidenceWriter.for_testing(
            os.path.join(tmp.name, "bp"), RUN_ID)
        relative = write_support_repetition(
            w, self.spec, 1,
            facts=SUPPORT_EVIDENCE["J"]._replace(body=b"J" * (exact - 1)))
        with open(os.path.join(w.run_dir, relative), encoding="utf-8") as fh:
            self.assertFalse(json.load(fh)["derived_production_size"])
        # One byte over: the signer refuses it before any evidence exists.
        with self.assertRaises(probe.SafetyBarrierTripped):
            sign(probe_target(key=probe_key("J", 2, run_id=RUN_ID)),
                 body=b"J" * (exact + 1))

    def test_multipart_markers_disqualify_a_j_repetition(self):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        key = probe_key("J", 1, run_id=RUN_ID)
        signed = sign(probe_target(key=key, query=(("uploads", ""),)),
                      body=b"J" * probe.PRODUCTION_BODY_BYTES)
        w.write_request_record(probe.build_request_record(
            phase="T", run_id=RUN_ID, group=self.spec.group, test_id="J",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed))
        resp = probe.RawResponse(
            status=200, headers=(("ETag", '"e"'),), body=b"",
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        w.write_response_record(probe.build_response_record(
            phase="T", run_id=RUN_ID, group=self.spec.group, test_id="J",
            repetition=1, sequence=1, response=resp, parsed=None,
            repetition_status=None))
        corr = probe.Correlation(phase="T", run_id=RUN_ID, test_id="J",
                                 repetition=1, sequence=1).serialize()
        relative = w.write_test_result_record(
            w.allocate_semantic("J", 1), evidence_ref=corr)
        with open(os.path.join(w.run_dir, relative), encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertEqual(record["outcome_classification"], "INCONCLUSIVE")
        self.assertFalse(record["derived_production_size"])


class IssuanceProofTests(unittest.TestCase):
    """BLOCKER 3: acceptance evidence is worthless without a PHYSICAL
    ISSUANCE_RECORD that the allocator wrote."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def writer(self, run_id=RUN_ID):
        return probe.EvidenceWriter.for_testing(self.root, run_id)

    def _semantic(self, w, test_id="B", rep=1):
        return w.write_semantic_record(
            w.allocate_semantic(test_id, rep), http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)

    def test_no_generic_trusted_persistence_method(self):
        """The generic `_persist` bypass is DELETED."""
        self.assertFalse(hasattr(probe.EvidenceWriter, "_persist"))

    def test_allocation_persists_a_physical_issuance_record(self):
        w = self.writer()
        issued = w.allocate_semantic("B", 1)
        relative = w._persisted[("ISSUANCE_RECORD", "B", 1)]
        self.assertEqual(relative, "issuance_record/b/0001.json")
        with open(os.path.join(w.run_dir, relative), encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertEqual(record["issuance_nonce"], issued.nonce)
        self.assertEqual(record["identity_kind"], "semantic")
        self.assertEqual(record["key"], issued.identity.key)
        self.assertEqual(probe.validate_record(record, ()),
                         "ISSUANCE_RECORD")

    def test_identity_kind_is_derived_from_the_matrix(self):
        w = self.writer()
        cases = [("B", "semantic"), ("E2", "race"), ("H1", "support"),
                 ("J", "support"), ("X1", "support")]
        for test_id, expected in cases:
            with self.subTest(test_id=test_id):
                self.assertEqual(probe.issuance_kind_for_test(test_id),
                                 expected)
        for test_id, expected in cases:
            issued = (w.allocate_race(test_id, 1)
                      if expected == "race" else
                      w.allocate_semantic(test_id, 1))
            relative = w._persisted[("ISSUANCE_RECORD", test_id, 1)]
            with open(os.path.join(w.run_dir, relative),
                      encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["identity_kind"], expected)
            del issued

    def test_low_level_persistence_of_ten_semantic_records_cannot_pass(self):
        """CODEX REPRODUCTION: ten B SEMANTIC_RECORDs written straight to
        disk through the low-level byte writer, with ZERO allocator
        issuance, must not reconstruct as ten valid repetitions."""
        w = self.writer("run-bypass")
        for rep in range(1, 11):
            record = {
                "record_kind": "SEMANTIC_RECORD", "phase": "T",
                "run_id": w.run_id, "group": "T-CAS-1", "test_id": "B",
                "repetition": rep,
                "key": probe_key("B", rep, run_id=w.run_id),
                "issuance_nonce": f"{w.run_id}:{rep:06d}", "status": 412,
                "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
                "mutation_observed": False, "credential_expired": False,
                "repetition_status": "VALID"}
            # Shape-valid: the ONLY thing missing is real issuance.
            self.assertEqual(probe.validate_record(record, ()),
                             "SEMANTIC_RECORD")
            w._write_bytes(
                probe.expected_relative_for_record(record),
                json.dumps(record, sort_keys=True, indent=2,
                           ensure_ascii=False).encode("utf-8"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.reconstruct_run_from_disk(
                w.run_dir, phase="T", run_id=w.run_id, secrets=(),
                issued_registry=w._allocator.issued_registry())
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_deleting_the_issuance_record_prevents_pass(self):
        w = self.writer("run-noissue")
        self._semantic(w)
        os.unlink(os.path.join(
            w.run_dir, w._persisted[("ISSUANCE_RECORD", "B", 1)]))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_issuance_cannot_back_two_acceptance_records(self):
        w = self.writer("run-twoback")
        self._semantic(w, "B", 1)
        # Copy the semantic record onto D's canonical path with D's
        # identity but B's nonce: one issuance, two acceptance records.
        source = w._persisted[("SEMANTIC_RECORD", "B", 1)]
        with open(os.path.join(w.run_dir, source), encoding="utf-8") as fh:
            record = json.load(fh)
        nonce = record["issuance_nonce"]
        w.allocate_semantic("D", 1)
        clone = dict(record, test_id="D", group="T-CAS-2",
                     key=probe_key("D", 1, run_id=w.run_id),
                     issuance_nonce=nonce)
        w._write_bytes(probe.expected_relative_for_record(clone),
                       json.dumps(clone, sort_keys=True, indent=2,
                                  ensure_ascii=False).encode("utf-8"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_issuance_kind_must_match_the_evidence_kind(self):
        """A support issuance cannot back a SEMANTIC_RECORD."""
        w = self.writer("run-kindswap")
        issued = w.allocate_semantic("H1", 1)   # identity_kind == "support"
        record = {
            "record_kind": "SEMANTIC_RECORD", "phase": "T",
            "run_id": w.run_id, "group": "T-CAS-1", "test_id": "B",
            "repetition": 1, "key": probe_key("B", 1, run_id=w.run_id),
            "issuance_nonce": issued.nonce, "status": 412,
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
            "mutation_observed": False, "credential_expired": False,
            "repetition_status": "VALID"}
        w._write_bytes(probe.expected_relative_for_record(record),
                       json.dumps(record, sort_keys=True, indent=2,
                                  ensure_ascii=False).encode("utf-8"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_semantic_writer_refuses_support_rows(self):
        w = self.writer("run-catmix")
        for test_id in ("H1", "J", "X1", "A"):
            with self.subTest(test_id=test_id):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self._semantic(w, test_id, 1)

    def test_dangling_evidence_reference_cannot_count(self):
        """CODEX REPRODUCTION: three H1 TEST_RESULT records referencing
        responses that do not physically exist must not complete H1."""
        w = self.writer("run-dangle")
        spec = probe.test_spec("H1")
        for rep in range(1, spec.required_repetitions + 1):
            issued = w.allocate_semantic("H1", rep)
            ref = probe.Correlation(
                phase="T", run_id=w.run_id, test_id="H1", repetition=rep,
                sequence=1).serialize()
            record = {
                "record_kind": "TEST_RESULT_RECORD", "phase": "T",
                "run_id": w.run_id, "group": spec.group, "test_id": "H1",
                "repetition": rep,
                "key": probe_key("H1", rep, run_id=w.run_id),
                "issuance_nonce": issued.nonce,
                "outcome_classification": "SCOPE_ALLOWED_OK",
                "derived_valid": True, "derived_production_size": False,
                "evidence_refs": [ref]}
            self.assertEqual(probe.validate_record(record, ()),
                             "TEST_RESULT_RECORD")
            w._write_bytes(probe.expected_relative_for_record(record),
                           json.dumps(record, sort_keys=True, indent=2,
                                      ensure_ascii=False).encode("utf-8"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()

    def test_response_without_a_request_cannot_satisfy_a_result(self):
        w = self.writer("run-noreq")
        spec = probe.test_spec("H1")
        write_support_repetition(w, spec, 1)
        request = next(rel for rel in w._files if rel.startswith("request/"))
        os.unlink(os.path.join(w.run_dir, request))
        del w._files[request]
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()


class RawHexPairTests(unittest.TestCase):
    """MEDIUM 1: a hex field is a transcription of its raw field, never an
    independent blob."""

    def _request(self, **over):
        signed = sign(probe_target(key=probe_key("B", 1)), body=b"x",
                      extra_headers={"if-match": '"abc"'})
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed)
        record.update(over)
        return record

    def test_benign_correct_pair_accepted(self):
        record = self._request()
        self.assertEqual(record["if_match_raw"], '"abc"')
        self.assertEqual(record["if_match_raw_hex"],
                         probe.hex_of('"abc"'))
        self.assertEqual(probe.validate_record(record, ()), "REQUEST_RECORD")

    def test_independent_hex_blob_rejected(self):
        forged = probe.hex_of("AWS4-HMAC-SHA256 Credential=FAKE")
        record = self._request(if_match_raw_hex=forged)
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())

    def test_hex_without_raw_rejected(self):
        record = self._request()
        del record["if_match_raw"]
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())

    def test_raw_without_hex_rejected(self):
        record = self._request()
        del record["if_match_raw_hex"]
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())

    def test_half_null_pair_rejected(self):
        for over in ({"if_match_raw": None},
                     {"if_match_raw_hex": None}):
            with self.subTest(over=over):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_record(self._request(**over), ())

    def test_both_null_accepted(self):
        record = self._request(if_match_raw=None, if_match_raw_hex=None)
        self.assertEqual(probe.validate_record(record, ()), "REQUEST_RECORD")

    def test_etag_pair_enforced_on_responses(self):
        resp = probe.RawResponse(
            status=200, headers=(("ETag", '"abc"'),), body=b"",
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        record = probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, response=resp, parsed=None,
            repetition_status=None)
        self.assertEqual(probe.validate_record(record, ()), "RESPONSE_RECORD")
        record["etag_raw_hex"] = probe.hex_of('"zzz"')
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())

    def test_every_hex_field_is_paired(self):
        """No hex field may exist without a declared raw partner."""
        paired = {name for pair in probe._RAW_HEX_PAIRS for name in pair}
        every = (probe._REQUEST_ALLOWED | probe._RESPONSE_ALLOWED
                 | probe._SEMANTIC_ALLOWED | probe._RACE_ALLOWED
                 | probe._TEST_RESULT_ALLOWED | probe._ISSUANCE_ALLOWED)
        for name in every:
            if name.endswith("_hex"):
                self.assertIn(name, paired, f"{name} has no raw partner")


class StrictEvidenceJsonTests(unittest.TestCase):
    """LOW: reconstruction refuses JSON that plain json.loads would accept
    with a silently chosen meaning."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def test_duplicate_keys_rejected(self):
        text = '{"status": 200, "status": 412}'
        self.assertEqual(json.loads(text)["status"], 412)   # the ambiguity
        with self.assertRaises(probe.StrictJsonRejected):
            probe.strict_json_loads(text)

    def test_nonstandard_constants_rejected(self):
        for text in ('{"n": NaN}', '{"n": Infinity}', '{"n": -Infinity}'):
            with self.subTest(text=text):
                with self.assertRaises(probe.StrictJsonRejected):
                    probe.strict_json_loads(text)

    def test_ordinary_json_still_parses(self):
        self.assertEqual(probe.strict_json_loads('{"a": [1, 2], "b": null}'),
                         {"a": [1, 2], "b": None})

    def test_duplicate_keys_on_disk_prevent_pass(self):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        w.write_semantic_record(
            w.allocate_semantic("B", 1), http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)
        victim = w._persisted[("SEMANTIC_RECORD", "B", 1)]
        path = os.path.join(w.run_dir, victim)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        tampered = text.replace('"status": 412,',
                                '"status": 412,\n  "status": 200,', 1)
        self.assertNotEqual(tampered, text)
        payload = tampered.encode("utf-8")
        with open(path, "wb") as fh:
            fh.write(payload)
        w._files[victim] = hashlib.sha256(payload).hexdigest()
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.finalize()


class MatrixRaceMetadataTests(unittest.TestCase):
    """MEDIUM 2: TEST_MATRIX is the ONLY source of race setup metadata."""

    def test_no_separate_race_setup_mapping(self):
        self.assertFalse(hasattr(probe, "race_setup_by_test"))
        self.assertNotIn("race_setup_by_test", probe._Policy._fields)

    def test_race_rows_have_setup_state_and_others_do_not(self):
        for spec in probe.TEST_MATRIX:
            with self.subTest(test_id=spec.id):
                if spec.category == "race":
                    self.assertIsNotNone(spec.race_setup_state)
                    self.assertIs(type(spec.race_setup_state), str)
                else:
                    self.assertIsNone(spec.race_setup_state)

    def test_race_test_ids_equals_rows_with_setup_metadata(self):
        self.assertEqual(
            set(probe.race_test_ids()),
            {s.id for s in probe.TEST_MATRIX
             if s.race_setup_state is not None})

    def test_setup_state_derives_from_the_matrix(self):
        self.assertEqual(probe.race_setup_state_for("E2"),
                         "SEEDED_ETAG_CAPTURED")
        self.assertEqual(probe.race_setup_state_for("F"), "PROVEN_ABSENT")
        for test_id in ("B", "H1", "J", "X1"):
            with self.subTest(test_id=test_id):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.race_setup_state_for(test_id)

    def test_allocator_validation_uses_the_matrix(self):
        allocator = probe.ProbeKeyAllocator(RUN_ID)
        issued = allocator.allocate_race(phase="t", test_id="F", repetition=1)
        self.assertEqual(issued.identity.setup_state, "PROVEN_ABSENT")


class PersistBeforeRegistryTests(unittest.TestCase):
    """MEDIUM 1: the correlation registry advances only AFTER the bytes are
    durably written, so a failed request write cannot legitimise a later
    response."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)
        self.w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)

    def _request(self):
        signed = sign(probe_target(key=probe_key("B", 1, run_id=RUN_ID)),
                      body=b"x")
        return probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed)

    def _response(self, status=412):
        resp = probe.RawResponse(
            status=status, headers=(("ETag", '"e"'),),
            body=b"<Error><Code>PreconditionFailed</Code></Error>",
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        return probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, response=resp,
            parsed=probe.parse_s3_error(resp.body), repetition_status=None)

    def test_failed_request_write_leaves_no_correlation(self):
        boom = IOError("disk full")
        with mock.patch.object(probe.EvidenceWriter, "_write_bytes",
                               side_effect=boom):
            with self.assertRaises(IOError):
                self.w.write_request_record(self._request())
        self.assertEqual(self.w._requests, {})
        # The response is therefore still an orphan.
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_response_record(self._response())

    def test_failed_response_write_leaves_no_response_record(self):
        self.w.write_request_record(self._request())
        with mock.patch.object(probe.EvidenceWriter, "_write_bytes",
                               side_effect=IOError("disk full")):
            with self.assertRaises(IOError):
                self.w.write_response_record(self._response())
        self.assertEqual(self.w._responses, {})
        # A retry after the failure is NOT a duplicate.
        self.w.write_response_record(self._response())
        self.assertEqual(list(self.w._responses.values()), [412])

    def test_successful_writes_record_the_observed_status(self):
        self.w.write_request_record(self._request())
        self.w.write_response_record(self._response(status=200))
        corr = probe.Correlation(phase="T", run_id=RUN_ID, test_id="B",
                                 repetition=1, sequence=1).serialize()
        self.assertEqual(self.w._responses[corr], 200)

    def test_cross_run_evidence_refused_at_the_door(self):
        other = probe.build_request_record(
            phase="T", run_id="run-other", group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=sign(probe_target(
                key=probe_key("B", 1, run_id="run-other")), body=b"x"),
            )
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_request_record(other)

    def test_cross_phase_evidence_refused_at_the_door(self):
        """A fully self-consistent phase P record cannot enter a phase T
        writer's bundle."""
        self.assertEqual(self.w._phase, "T")
        other = probe.build_request_record(
            phase="P", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=sign(probe_target(
                key=probe_key("B", 1, phase="p", run_id=RUN_ID)), body=b"x"),
            )
        self.assertEqual(probe.validate_record(other, ()), "REQUEST_RECORD")
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.w.write_request_record(other)


class CanonicalEvidencePathTests(unittest.TestCase):
    """A record's file path is a pure function of its own identity."""

    def test_typed_record_paths_are_derived(self):
        for kind, directory in (("TEST_RESULT_RECORD", "test_result_record"),
                                ("SEMANTIC_RECORD", "semantic_record"),
                                ("RACE_RECORD", "race_record"),
                                ("ISSUANCE_RECORD", "issuance_record")):
            with self.subTest(kind=kind):
                self.assertEqual(
                    probe.expected_relative_for_record(
                        {"record_kind": kind, "test_id": "H1",
                         "repetition": 3}),
                    f"{directory}/h1/0003.json")

    def test_correlated_record_paths_are_derived(self):
        corr = probe.Correlation(phase="T", run_id=RUN_ID, test_id="B",
                                 repetition=2, sequence=7).serialize()
        for kind, directory in (("REQUEST_RECORD", "request"),
                                ("RESPONSE_RECORD", "response")):
            with self.subTest(kind=kind):
                self.assertEqual(
                    probe.expected_relative_for_record(
                        {"record_kind": kind, "correlation_id": corr}),
                    f"{directory}/T_{RUN_ID}_B_0002_000007.json")

    def test_every_record_kind_has_a_directory(self):
        self.assertEqual(set(probe._RECORD_KIND_DIRS), probe.RECORD_KINDS)


class ExpiredCredentialTests(unittest.TestCase):
    """HIGH 1: credential_expired is coherent ONLY with a 401/403 auth
    rejection; it can never contribute a VALID repetition."""

    def _evidence(self, status, outcome, expired):
        ident = probe.RepetitionIdentity(
            phase="t", run_id=RUN_ID, test_id="B", repetition=1,
            key=probe_key("B", 1))
        return probe.SemanticEvidence(
            identity=ident, http_status=status, outcome=outcome,
            mutation_observed=False, credential_expired=expired)

    def test_expired_with_401_403_is_invalid_credential_expired(self):
        for status in (401, 403):
            ev = self._evidence(
                status, probe.PutOutcome.DEFINITE_AUTH_REJECTION, True)
            derived, abandon = probe.derive_semantic_status(ev)
            self.assertIsNone(abandon)
            self.assertIs(derived,
                          probe.RepetitionStatus.INVALID_CREDENTIAL_EXPIRED)

    def test_expired_with_412_or_2xx_or_429_or_5xx_refused(self):
        for status, outcome in (
                (412, probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION),
                (200, probe.PutOutcome.PUT_CONFIRMED),
                (429, probe.PutOutcome.DEFINITE_THROTTLE_REJECTION),
                (503, probe.PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN)):
            with self.subTest(status=status):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    probe.validate_semantic_evidence(
                        self._evidence(status, outcome, True))

    def test_ten_expired_412s_cannot_pass(self):
        # Expired + 412 is refused at record(), so it can never even be
        # counted as VALID — the aggregator stays empty and FAILs.
        agg = probe.SemanticAggregator()
        for rep in range(1, 11):
            ident = probe.RepetitionIdentity(
                phase="t", run_id=RUN_ID, test_id="B", repetition=rep,
                key=probe_key("B", rep))
            ev = probe.SemanticEvidence(
                identity=ident, http_status=412,
                outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
                mutation_observed=False, credential_expired=True)
            with self.assertRaises(probe.SafetyBarrierTripped):
                agg.record(ev)
        self.assertIs(agg.verdict("B")[0], probe.Verdict.FAIL)


class RecordKindTests(unittest.TestCase):
    """BLOCKER 3: persisted records declare and satisfy a kind."""

    def _semantic_record(self, **over):
        record = {
            "record_kind": "SEMANTIC_RECORD",
            "phase": "T", "run_id": RUN_ID, "group": "T-CAS-1",
            "test_id": "B", "repetition": 1, "key": probe_key("B", 1),
            "issuance_nonce": NONCE, "status": 412,
            "ambiguous_state": "DEFINITE_CONDITIONAL_REJECTION",
            "mutation_observed": False, "credential_expired": False,
            "repetition_status": "VALID"}
        record.update(over)
        return record

    def test_good_semantic_record(self):
        self.assertEqual(probe.validate_record(self._semantic_record(), ()),
                         "SEMANTIC_RECORD")

    def test_empty_and_kindless_rejected(self):
        for bad in ({}, {"phase": "P"}, {"record_kind": "NOPE"}):
            with self.subTest(bad=bad):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_record(bad, ())

    def test_group_test_mismatch_rejected(self):
        # B belongs to T-CAS-1, not T-RACE.
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(
                self._semantic_record(group="T-RACE"), ())

    def test_412_put_confirmed_rejected(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(
                self._semantic_record(ambiguous_state="PUT_CONFIRMED"), ())

    def test_wrong_repetition_status_rejected(self):
        # 412 with a proven-unchanged final derives VALID; claiming
        # INVALID_THROTTLED is a lie.
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(
                self._semantic_record(repetition_status="INVALID_THROTTLED"),
                ())

    def test_mutation_semantic_record_rejected(self):
        # A record encoding mutation must not persist as accepted.
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(
                self._semantic_record(mutation_observed=True), ())

    def test_key_identity_mismatch_rejected(self):
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(
                self._semantic_record(key=probe_key("B", 2)), ())  # rep!=key

    def _flat_race(self, *, loser_status=412, status="VALID_CAS",
                   attribution="CAS", **over):
        w1 = race_writer("W1", 200, b"aaa", '"e-win"')
        w2 = race_writer("W2", loser_status, b"bbb", None)
        rep = probe.RaceRepetition(
            identity=probe.RaceIdentity(
                phase="t", run_id=RUN_ID, test_id="E2", repetition=1,
                key=probe_key("E2", 1), setup_state="SEEDED_ETAG_CAPTURED"),
            shared_original_etag=SHARED_ETAG, absence_confirmed=None,
            barrier=BARRIER, writers=(w1, w2),
            final_state=probe.RemoteState.CONFIRMED,
            final_sha256=hashlib.sha256(b"aaa").hexdigest(),
            final_length=3, final_etag='"e-win"')
        record = probe._flatten_race_record(
            rep, phase="T", run_id=RUN_ID, group="T-RACE",
            issuance_nonce=NONCE, status=status, attribution=attribution)
        record.update(over)
        return record

    def test_good_race_record_derives(self):
        # 412 loser + correct labels validates.
        self.assertEqual(probe.validate_record(self._flat_race(), ()),
                         "RACE_RECORD")

    def test_fact_free_race_record_rejected(self):
        # Dropping the writer facts makes it un-derivable → rejected.
        bad = self._flat_race()
        del bad["w1_http_status"]
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(bad, ())

    def test_race_record_caller_label_cannot_lie(self):
        # A 429 loser DERIVES INVALID_THROTTLED; labelling it VALID_CAS/CAS
        # is rejected because the facts re-derive differently.
        bad = self._flat_race(loser_status=429, status="VALID_CAS",
                              attribution="CAS")
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(bad, ())
        # The honest 429 labels validate.
        ok = self._flat_race(loser_status=429, status="INVALID_THROTTLED",
                             attribution="THROTTLE")
        self.assertEqual(probe.validate_record(ok, ()), "RACE_RECORD")

    def test_request_record_roundtrip(self):
        signed = sign(probe_target(key=probe_key("B", 1)), body=b"x")
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1,
            endpoint_host=ENDPOINT_HOST, signed=signed,
            )
        self.assertEqual(probe.validate_record(record, ()), "REQUEST_RECORD")

    def test_request_group_test_mismatch_rejected(self):
        signed = sign(probe_target(key=probe_key("B", 1)), body=b"x")
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-RACE", test_id="B",
            repetition=1, sequence=1,
            endpoint_host=ENDPOINT_HOST, signed=signed,
            )
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())


class RequestResponseCorrelationTests(unittest.TestCase):
    """MEDIUM 3: request/response records carry matrix identity and a
    response must correlate to a persisted request."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def _request(self, test_id="B", group="T-CAS-1", rep=1, seq=1,
                 run_id=RUN_ID):
        signed = sign(probe_target(key=probe_key(test_id, rep)), body=b"x")
        return probe.build_request_record(
            phase="T", run_id=run_id, group=group, test_id=test_id,
            repetition=rep, sequence=seq, endpoint_host=ENDPOINT_HOST,
            signed=signed)

    def _response(self, test_id="B", group="T-CAS-1", rep=1, seq=1,
                  run_id=RUN_ID):
        resp = probe.RawResponse(status=412, headers=(("ETag", '"e"'),),
                                 body=b"<Error><Code>PreconditionFailed"
                                 b"</Code></Error>", body_truncated=False,
                                 t_request_start_mono_ns=1,
                                 t_response_end_mono_ns=2)
        return probe.build_response_record(
            phase="T", run_id=run_id, group=group, test_id=test_id,
            repetition=rep, sequence=seq, response=resp,
            parsed=probe.parse_s3_error(resp.body), repetition_status=None)

    def test_response_needs_a_request(self):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.write_response_record(self._response())   # orphan
        w.write_request_record(self._request())
        w.write_response_record(self._response())       # now OK
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.write_response_record(self._response())   # duplicate

    def test_b_labelled_t_race_rejected(self):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        with self.assertRaises(probe.EvidenceValidationError):
            w.write_request_record(self._request(group="T-RACE"))

    def test_response_test_mismatch_rejected(self):
        w = probe.EvidenceWriter.for_testing(self.root, RUN_ID)
        w.write_request_record(self._request(test_id="B"))
        # A response whose correlation id points at B's request but claims
        # D is rejected (correlation encodes test_id).
        resp = self._response(test_id="D", group="T-CAS-2")
        with self.assertRaises(probe.SafetyBarrierTripped):
            w.write_response_record(resp)


class FullCorrelationIdentityTests(unittest.TestCase):
    """HIGH B: a correlation id carries the COMPLETE five-component identity
    (phase/run/test/repetition/sequence) and every component is cross-checked
    against the record's own fields."""

    def _record(self, **overrides):
        signed = sign(probe_target(key=probe_key("B", 1, run_id=RUN_ID)),
                      body=b"x")
        record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1, endpoint_host=ENDPOINT_HOST,
            signed=signed)
        record.update(overrides)
        return record

    def test_correlation_serializes_all_five_components(self):
        corr = probe.Correlation(phase="T", run_id=RUN_ID, test_id="B",
                                 repetition=4, sequence=9)
        self.assertEqual(corr.serialize(), f"T/{RUN_ID}/B/4/9")
        self.assertEqual(probe.parse_correlation(corr.serialize()), corr)

    def test_builders_cannot_be_handed_a_correlation(self):
        import inspect
        for builder in (probe.build_request_record,
                        probe.build_response_record):
            with self.subTest(builder=builder.__name__):
                params = inspect.signature(builder).parameters
                self.assertNotIn("correlation_id", params)
                self.assertIn("run_id", params)

    def test_every_component_mismatch_is_rejected(self):
        base = self._record()
        good = probe.parse_correlation(base["correlation_id"])
        mismatches = {
            "phase": good._replace(phase="P"),
            "run_id": good._replace(run_id="run-other"),
            "test_id": good._replace(test_id="D"),
            "repetition": good._replace(repetition=2),
            "sequence": good._replace(sequence=2),
        }
        for component, corr in mismatches.items():
            with self.subTest(component=component):
                bad = self._record(correlation_id=corr.serialize())
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_record(bad, ())

    def test_legacy_three_component_correlation_is_rejected(self):
        for legacy in ("B/1/1", "T/B/1/1", f"{RUN_ID}/B/1/1"):
            with self.subTest(legacy=legacy):
                with self.assertRaises(probe.EvidenceValidationError):
                    probe.validate_record(
                        self._record(correlation_id=legacy), ())

    def test_malformed_correlations_are_rejected(self):
        for value in ("", "/", "T//B/1/1", "X/run-abc/B/1/1",
                      f"T/{RUN_ID}/B/1", f"T/{RUN_ID}/B/1/1/1",
                      f"T/{RUN_ID}/B/-1/1", f"T/{RUN_ID}/B/1/x",
                      f"T/{RUN_ID}/B/1/1 ", None, 1):
            with self.subTest(value=value):
                with self.assertRaises((probe.EvidenceValidationError,
                                        probe.SafetyBarrierTripped)):
                    probe.parse_correlation(value)

    def test_run_id_is_a_required_field_on_both_kinds(self):
        for required in (probe._REQUEST_REQUIRED, probe._RESPONSE_REQUIRED):
            self.assertIn("run_id", required)


# ═══════════════════════════════════════════════════════════════════════════
# HIGH A — the same-key race pair is settled through an opaque handle
# ═══════════════════════════════════════════════════════════════════════════

class SameKeyRacePairApiTests(unittest.TestCase):
    """The coordinator receives an OPAQUE pair id, not the reservations, and
    the winner is an enum — so a caller cannot settle half a pair, forge a
    handle, or smuggle a bool/int through the winner argument."""

    def setUp(self):
        self.ledger = probe.ResourceLedger()

    def _pair(self, key="catalog/probe/t/rk", a=100, b=100):
        return self.ledger.reserve_race_pair_same_key(key, a, b)

    def test_handle_is_an_opaque_string(self):
        handle = self._pair()
        self.assertIs(type(handle), str)
        self.assertRegex(handle, r"^pair-[0-9]{6}$")
        for attribute in ("first", "second", "token", "key", "length",
                          "first_len", "second_len", "prior_size",
                          "_replace", "_fields"):
            self.assertFalse(hasattr(handle, attribute))

    def test_forged_handles_are_refused(self):
        self._pair()
        for forged in ("pair-000002", "pair-999999", "pair-1", "",
                       "catalog/probe/t/rk", None, 1, True):
            with self.subTest(forged=forged):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self.ledger.resolve_race_pair(
                        forged, winner=probe.RacePairWinner.NONE)

    def test_a_pair_settles_exactly_once(self):
        handle = self._pair()
        self.ledger.resolve_race_pair(
            handle, winner=probe.RacePairWinner.WRITER_1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.ledger.resolve_race_pair(
                handle, winner=probe.RacePairWinner.WRITER_1)

    def test_winner_must_be_the_enum(self):
        for winner in (True, False, 1, 2, 0, None, "WRITER_1", "1"):
            with self.subTest(winner=winner):
                handle = self._pair(key=f"catalog/probe/t/rk-{winner!r}")
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self.ledger.resolve_race_pair(handle, winner=winner)

    def test_each_enum_winner_settles_the_right_length(self):
        for winner, expected in ((probe.RacePairWinner.WRITER_1, 10),
                                 (probe.RacePairWinner.WRITER_2, 20),
                                 (probe.RacePairWinner.NONE, None)):
            with self.subTest(winner=winner):
                ledger = probe.ResourceLedger()
                key = "catalog/probe/t/rk"
                handle = ledger.reserve_race_pair_same_key(key, 10, 20)
                ledger.resolve_race_pair(handle, winner=winner)
                self.assertEqual(ledger._live_objects.get(key), expected)

    def test_equal_keys_are_refused_by_the_two_key_api(self):
        """The two-key reservation must never be used for a same-key race,
        and it refuses BEFORE any reservation escapes or any cap is charged."""
        before = self.ledger.snapshot()
        with self.assertRaises(probe.SafetyBarrierTripped):
            self.ledger.reserve_race_pair(
                "catalog/probe/t/same", 10, "catalog/probe/t/same", 20)
        self.assertEqual(self.ledger.snapshot(), before)
        self.assertFalse(self.ledger.poisoned)

    def test_pair_reservations_never_reach_resolve_put(self):
        handle = self._pair()
        state = self.ledger._race_pairs[handle]
        for reservation in (state.first, state.second):
            with self.subTest(token=reservation.token):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self.ledger.resolve_put(reservation, committed=True)

    def test_pair_state_is_an_immutable_namedtuple(self):
        handle = self._pair()
        state = self.ledger._race_pairs[handle]
        self.assertIsInstance(state, tuple)
        with self.assertRaises(AttributeError):
            object.__setattr__(state, "key", "catalog/probe/t/elsewhere")


# ═══════════════════════════════════════════════════════════════════════════
# MEDIUM 1 — ledger concurrency and poisoning
# ═══════════════════════════════════════════════════════════════════════════

class ResourceLedgerTests(unittest.TestCase):

    def test_live_ledger_takes_no_caps(self):
        import inspect
        self.assertEqual(
            list(inspect.signature(probe.ResourceLedger.__init__).parameters),
            ["self"])
        caps = probe.fixed_resource_caps()
        self.assertEqual(caps.max_put_attempts, 650)
        self.assertEqual(caps.max_get_head, 1000)
        self.assertEqual(caps.max_object_keys, 300)
        self.assertEqual(caps.max_uploaded_bytes, 170 * 1000 * 1000)
        self.assertEqual(caps.max_peak_storage_bytes, 120 * 1000 * 1000)

    def test_production_size_derives_from_body_length(self):
        ledger = probe.ResourceLedger.for_testing(probe.ResourceCaps(
            1, 100, 100, 100, 10**9, 10**9))
        ledger.reserve_put("catalog/probe/p/1", probe.PRODUCTION_BODY_BYTES)
        with self.assertRaises(probe.CapExceeded):
            ledger.reserve_put("catalog/probe/p/2",
                               probe.PRODUCTION_BODY_BYTES)

    def test_race_pair_reserved_before_barrier(self):
        """The sanctioned concurrency model: the coordinator charges both
        writers sequentially before releasing the barrier."""
        ledger = probe.ResourceLedger()
        first, second = ledger.reserve_race_pair(
            "catalog/probe/t/a", 10, "catalog/probe/t/b", 20)
        self.assertEqual(ledger.snapshot()["put_operation_count"], 2)
        self.assertEqual(ledger.snapshot()["uploaded_bytes"], 30)
        self.assertNotEqual(first.token, second.token)

    def test_same_key_race_pair_resolves_atomically(self):
        """HIGH 4 — Codex's exact regression: same-key pair, writer 2 wins
        100 bytes, writer 1 loses, then commit another 100-byte object;
        live storage must be 200 and cap 150 must poison."""
        ledger = probe.ResourceLedger.for_testing(
            probe.ResourceCaps(60, 650, 1000, 300, 10**9, 150))
        handle = ledger.reserve_race_pair_same_key(
            "catalog/probe/t/racekey", 100, 100)
        # Both attempts already counted.
        self.assertEqual(ledger.snapshot()["put_operation_count"], 2)
        self.assertEqual(ledger.snapshot()["uploaded_bytes"], 200)
        ledger.resolve_race_pair(
            handle, winner=probe.RacePairWinner.WRITER_2)   # writer 2 wins
        self.assertEqual(sum(ledger._live_objects.values()), 100)
        # Committing another 100-byte object pushes live to 200 > cap 150;
        # the breach is detected at reserve time and poisons the ledger.
        with self.assertRaises(probe.CapExceeded):
            ledger.reserve_put("catalog/probe/t/other", 100)
        self.assertTrue(ledger.poisoned)

    def test_same_key_race_pair_no_independent_resolve(self):
        """HIGH A: the same-key handle is an OPAQUE id, so there is no
        reservation to hand to resolve_put in the first place."""
        ledger = probe.ResourceLedger()
        handle = ledger.reserve_race_pair_same_key(
            "catalog/probe/t/rk", 50, 50)
        self.assertIs(type(handle), str)
        self.assertFalse(hasattr(handle, "first"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            ledger.resolve_put(handle, committed=True)

    def test_same_key_race_neither_commits_restores_prior(self):
        ledger = probe.ResourceLedger()
        seed = ledger.reserve_put("catalog/probe/t/rk", 40)
        ledger.resolve_put(seed, committed=True)   # prior object exists
        handle = ledger.reserve_race_pair_same_key(
            "catalog/probe/t/rk", 100, 100)
        ledger.resolve_race_pair(
            handle, winner=probe.RacePairWinner.NONE)   # neither committed
        self.assertEqual(ledger._live_objects.get("catalog/probe/t/rk"), 40)

    def test_concurrent_reservations_cannot_undercount(self):
        ledger = probe.ResourceLedger()
        errors = []
        barrier = threading.Barrier(8)

        def worker(index):
            try:
                barrier.wait()
                for rep in range(10):
                    ledger.reserve_put(f"catalog/probe/t/{index}/{rep}", 1)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(i,))
                   for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        snap = ledger.snapshot()
        self.assertEqual(snap["put_operation_count"], 80)
        self.assertEqual(snap["uploaded_bytes"], 80)
        self.assertEqual(snap["object_count"], 80)

    def test_cap_breach_poisons_the_ledger(self):
        ledger = probe.ResourceLedger.for_testing(probe.ResourceCaps(
            60, 2, 100, 100, 10**9, 10**9))
        ledger.reserve_put("catalog/probe/t/1", 1)
        ledger.reserve_put("catalog/probe/t/2", 1)
        with self.assertRaises(probe.CapExceeded):
            ledger.reserve_put("catalog/probe/t/3", 1)
        self.assertTrue(ledger.poisoned)
        # Catching CapExceeded and continuing is impossible.
        for call in (lambda: ledger.reserve_put("catalog/probe/t/4", 1),
                     lambda: ledger.charge_get_head(),
                     lambda: ledger.reserve_race_pair(
                         "catalog/probe/t/5", 1, "catalog/probe/t/6", 1)):
            with self.assertRaises(probe.LedgerPoisoned):
                call()

    def test_poisoned_is_reported_in_snapshot(self):
        ledger = probe.ResourceLedger.for_testing(probe.ResourceCaps(
            60, 1, 100, 100, 10**9, 10**9))
        ledger.reserve_put("catalog/probe/t/1", 1)
        with self.assertRaises(probe.CapExceeded):
            ledger.reserve_put("catalog/probe/t/2", 1)
        self.assertTrue(ledger.snapshot()["poisoned"])

    def test_412_and_429_still_count(self):
        ledger = probe.ResourceLedger()
        res = ledger.reserve_put("catalog/probe/t/a", 100)
        ledger.resolve_put(res, committed=False)
        snap = ledger.snapshot()
        self.assertEqual(snap["put_operation_count"], 1)
        self.assertEqual(snap["uploaded_bytes"], 100)

    def test_overwrite_replaces_not_double_counts(self):
        ledger = probe.ResourceLedger()
        r1 = ledger.reserve_put("catalog/probe/t/same", 100)
        ledger.resolve_put(r1, committed=True)
        r2 = ledger.reserve_put("catalog/probe/t/same", 250)
        ledger.resolve_put(r2, committed=True)
        self.assertEqual(sum(ledger._live_objects.values()), 250)
        self.assertEqual(ledger.object_count, 1)
        self.assertEqual(ledger.snapshot()["put_operation_count"], 2)

    def test_ambiguous_stays_charged(self):
        ledger = probe.ResourceLedger()
        ledger.reserve_put("catalog/probe/t/amb", 600)
        self.assertEqual(sum(ledger._live_objects.values()), 600)

    def test_double_resolve_refused(self):
        ledger = probe.ResourceLedger()
        res = ledger.reserve_put("catalog/probe/t/a", 10)
        ledger.resolve_put(res, committed=True)
        with self.assertRaises(probe.SafetyBarrierTripped):
            ledger.resolve_put(res, committed=True)

    def test_forged_reservation_cannot_undercount(self):
        """MEDIUM 1: Codex's exact proof — a forged PutReservation with a
        real open token but a different key must not resolve, must not
        undercount, and must fail closed."""
        ledger = probe.ResourceLedger()
        # Commit object B (large), leave it charged.
        res_b = ledger.reserve_put("catalog/probe/t/B", 500)
        ledger.resolve_put(res_b, committed=True)
        # Reserve object A (small); capture A's real token.
        res_a = ledger.reserve_put("catalog/probe/t/A", 10)
        forged = probe.PutReservation(
            key="catalog/probe/t/B", body_len=500, prior_size=None,
            had_prior=False, token=res_a.token)
        with self.assertRaises(probe.SafetyBarrierTripped):
            ledger.resolve_put(forged, committed=False)
        # B remains accounted; the ledger is poisoned, not undercounting.
        self.assertTrue(ledger.poisoned)
        self.assertEqual(ledger._live_objects.get("catalog/probe/t/B"), 500)

    def test_reservation_is_resolved_from_stored_record(self):
        # Even a non-forged reservation is resolved from the stored copy.
        ledger = probe.ResourceLedger()
        res = ledger.reserve_put("catalog/probe/t/x", 100)
        ledger.resolve_put(res, committed=False)
        self.assertNotIn("catalog/probe/t/x", ledger._live_objects)

    def test_object_count_separate_from_put_count(self):
        ledger = probe.ResourceLedger()
        for _ in range(3):
            res = ledger.reserve_put("catalog/probe/t/same", 1)
            ledger.resolve_put(res, committed=False)
        self.assertEqual(ledger.object_count, 1)
        self.assertEqual(ledger.snapshot()["put_operation_count"], 3)

    def test_input_validation(self):
        ledger = probe.ResourceLedger()
        with self.assertRaises(probe.SafetyBarrierTripped):
            ledger.reserve_put("catalog/probe/t/x", -1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            ledger.charge_get_head(0)


# ═══════════════════════════════════════════════════════════════════════════
# MEDIUM 2 — one immutable test matrix
# ═══════════════════════════════════════════════════════════════════════════

class TestMatrixTests(unittest.TestCase):

    def test_ids_are_unique(self):
        ids = [spec.id for spec in probe.TEST_MATRIX]
        self.assertEqual(len(ids), len(set(ids)))

    def test_all_derived_views_agree(self):
        matrix_ids = {spec.id for spec in probe.TEST_MATRIX}
        self.assertEqual(probe.known_test_ids(), matrix_ids)
        planned = {t for t, _, _ in probe.planned_tests()}
        self.assertEqual(planned, matrix_ids)
        grouped = set()
        for ids in probe.credential_groups().values():
            grouped |= set(ids)
        self.assertEqual(grouped, matrix_ids)

    def test_no_test_is_in_two_groups(self):
        seen = {}
        for group, ids in probe.credential_groups().items():
            for test_id in ids:
                self.assertNotIn(test_id, seen)
                seen[test_id] = group

    def test_group_cost_derives_from_matrix(self):
        planner = probe.CredentialGroupPlanner()
        for group, ids in probe.credential_groups().items():
            expected = sum(probe.test_spec(i).cost_seconds for i in ids)
            self.assertEqual(planner.estimated_group_cost(group), expected)

    def test_no_drifting_duplicate_lists_exist(self):
        """The round-1 drift (K2/L/PROD-*) cannot recur: there is no
        separate cost table or group table to drift from."""
        self.assertFalse(hasattr(probe, "TEST_COST_SECONDS"))
        self.assertFalse(hasattr(probe, "CREDENTIAL_GROUPS"))
        self.assertFalse(hasattr(probe, "KNOWN_TEST_IDS"))

    def test_categories_are_coherent(self):
        self.assertEqual(probe.semantic_test_ids(), ("B", "D", "E1"))
        self.assertEqual(probe.race_test_ids(), ("E2", "F"))
        for spec in probe.TEST_MATRIX:
            self.assertGreaterEqual(spec.cost_seconds, 0.0)
            self.assertGreaterEqual(spec.required_repetitions, 1)
            self.assertGreaterEqual(spec.max_attempts,
                                    spec.required_repetitions)

    def test_matrix_is_immutable(self):
        spec = probe.TEST_MATRIX[0]
        with self.assertRaises(AttributeError):
            object.__setattr__(spec, "group", "T-ADMIN")

    def test_every_execution_field_is_consumed(self):
        """MEDIUM 2: no TestSpec execution-relevant field is decoration.

        Each field is demonstrably read by acceptance/planning logic:
          - group           -> credential_groups() partitions by it
          - cost_seconds    -> CredentialGroupPlanner.estimated_group_cost
          - category        -> semantic/race id derivation + summary routing
          - required_repetitions / max_attempts -> aggregator verdicts +
                               MatrixCompletion.is_complete
          - production_size_repetitions -> MatrixCompletion.is_complete
          - id / description-> planned_tests() display + test_spec lookup
        """
        # group consumed
        grouped = {t for ids in probe.credential_groups().values()
                   for t in ids}
        self.assertEqual(grouped, probe.known_test_ids())
        # cost_seconds consumed
        planner = probe.CredentialGroupPlanner()
        for group in probe.credential_groups():
            self.assertEqual(
                planner.estimated_group_cost(group),
                sum(probe.test_spec(i).cost_seconds
                    for i in probe.credential_groups()[group]))
        # category consumed
        self.assertEqual(
            set(probe.semantic_test_ids()) | set(probe.race_test_ids()),
            {s.id for s in probe.TEST_MATRIX
             if s.category in ("semantic", "race")})
        # required/max/production_size consumed by MatrixCompletion, which
        # now counts ONLY validated TEST_RESULT_RECORDs (BLOCKER 1).
        spec = probe.test_spec("J")   # a production-size test (>0)
        self.assertGreater(spec.production_size_repetitions, 0)
        # Short of the production-size target: counted but incomplete. The
        # one-byte body derives non-production-size, so the row stays open.
        short = completion_from_support_evidence(
            self, specs=[spec],
            facts_for=lambda s: SUPPORT_EVIDENCE["J"]._replace(body=b"x"))
        self.assertFalse(short.is_complete(spec.id),
                         "production_size_repetitions is not enforced")
        # Attempts beyond the cap are refused at count time.
        capped = probe.MatrixCompletion()
        source = completion_from_support_evidence(self, specs=[spec])
        one = dict(source._by_test)   # derived facts, reused as fixtures
        del one
        with self.assertRaises(probe.EvidenceValidationError):
            for rep in range(1, spec.max_attempts + 2):
                capped.count_persisted_test_result({
                    "record_kind": "TEST_RESULT_RECORD", "phase": "T",
                    "run_id": RUN_ID, "group": spec.group,
                    "test_id": spec.id, "repetition": rep,
                    "key": probe_key(spec.id, rep, run_id=RUN_ID),
                    "issuance_nonce": NONCE,
                    "outcome_classification": "SINGLE_PART_PROVEN",
                    "derived_valid": True, "derived_production_size": False,
                    "evidence_refs": []})
        # Every required repetition valid + production-size → complete.
        full = completion_from_support_evidence(self, specs=[spec])
        self.assertTrue(full.is_complete(spec.id))
        # id + description consumed by planned_tests()
        planned = {t: d for t, _, d in probe.planned_tests()}
        self.assertEqual(set(planned), probe.known_test_ids())
        for spec in probe.TEST_MATRIX:
            self.assertEqual(planned[spec.id], spec.description)


# ═══════════════════════════════════════════════════════════════════════════
# MEDIUM 3 — provenance
# ═══════════════════════════════════════════════════════════════════════════

class ProvenanceTests(unittest.TestCase):

    def test_algorithm_source_recorded(self):
        self.assertTrue(iv.SIGV4_ALGORITHM_DOC_URL.startswith(
            "https://docs.aws.amazon.com/"))
        self.assertIn("Derive a signing key", iv.SIGV4_ALGORITHM_DOC_SECTIONS)
        self.assertEqual(iv.SIGV4_ALGORITHM_DOC_CHECKED, "2026-08-16")

    def test_cloudflare_fixture_is_labelled_derived_not_published(self):
        self.assertEqual(iv.GOLDEN_CREDENTIAL_PROVENANCE,
                         "derived fixture from official recipe")
        for url in iv.CLOUDFLARE_TEMP_CREDENTIAL_DOC_URLS:
            self.assertTrue(url.startswith(
                "https://developers.cloudflare.com/"))

    def test_every_aws_fixture_names_a_source(self):
        source = (_HERE / "independent_verifiers.py").read_text(
            encoding="utf-8")
        for marker in ("SOURCE B fixture 1", "SOURCE B fixture 2"):
            self.assertIn(marker, source)
        self.assertIn("docs.aws.amazon.com/general/latest/gr/", source)

    def test_fixtures_labelled_locally_reproduced(self):
        """MEDIUM 3: fixtures carry the honest 'locally reproduced' label
        and an explicit negation of the stronger claims."""
        source = (_HERE / "independent_verifiers.py").read_text(
            encoding="utf-8")
        self.assertIn("locally reproduced", source.lower())
        # The stronger claims appear ONLY inside an explicit negation.
        self.assertIn("NOT", source)
        self.assertIn("official golden value", source)  # in the negation
        self.assertRegex(source, r"NOT[^.]*official golden value")

    def test_no_unpinned_bundle_claim(self):
        source = (_HERE / "independent_verifiers.py").read_text(
            encoding="utf-8")
        self.assertIn("bundle NOT retrievable", source)


# ═══════════════════════════════════════════════════════════════════════════
# AWS vectors + SigV4 parity
# ═══════════════════════════════════════════════════════════════════════════

class LocallyReproducedSigV4FixtureTests(unittest.TestCase):
    # LOW: renamed from AwsFixedVectorTests — these fixtures are locally
    # reproduced under the official AWS algorithm, not claimed as fixed
    # official AWS vectors.

    def test_signing_key_vector(self):
        v = iv.AWS_SIGNING_KEY_VECTOR
        for derive in (iv.independent_signing_key, probe.derive_signing_key):
            with self.subTest(impl=derive.__module__):
                self.assertEqual(
                    binascii.hexlify(derive(
                        v["secret"], v["datestamp"], v["region"],
                        v["service"])).decode(),
                    v["expected_key_hex"])

    def test_get_vanilla(self):
        g = iv.AWS_GET_VANILLA_VECTOR
        result = iv.independent_authorization(
            method=g["method"], path=g["path"], query_pairs=g["query_pairs"],
            headers=g["headers"], payload=g["payload"],
            amz_date=g["amz_date"], region=g["region"], service=g["service"],
            access_key_id=g["access_key_id"],
            secret_access_key=g["secret_access_key"])
        self.assertEqual(result["canonical_request"],
                         g["expected_canonical_request"])
        self.assertEqual(result["signature"], g["expected_signature"])
        head, _, tail = result["string_to_sign"].rpartition("\n")
        self.assertEqual(head, g["expected_string_to_sign_head"])
        self.assertEqual(tail, hashlib.sha256(
            g["expected_canonical_request"].encode()).hexdigest())


class SigV4ParityTests(unittest.TestCase):

    CASES = (
        ("head", "HEAD", probe_key("H1", 1), b"", (), {}),
        ("get", "GET", probe_key("H2", 1), b"", (), {}),
        ("put_small", "PUT", probe_key("B", 1), b'{"a":1}', (), {}),
        ("if_match", "PUT", probe_key("B", 2), b"x", (),
         {"if-match": '"d41d8cd98f00b204e9800998ecf8427e"'}),
        ("if_match_weak", "PUT", probe_key("B", 3), b"x", (),
         {"if-match": 'W/"abc123"'}),
        ("if_none_match_star", "PUT", probe_key("C", 1), b"x", (),
         {"if-none-match": "*"}),
        ("list_query", "GET", "", b"",
         (("list-type", "2"), ("prefix", "catalog/")), {}),
        ("query_order", "GET", "", b"",
         (("prefix", "catalog/"), ("list-type", "2"), ("delimiter", "/")), {}),
        ("query_repeat", "GET", "", b"", (("x-id", "b"), ("x-id", "a")), {}),
        ("query_empty", "GET", "", b"", (("acl", ""),), {}),
        ("dots_tilde", "GET", "catalog/probe/t/x/v7.0.1_a-b~c.json", b"",
         (), {}),
        ("ws_header", "PUT", probe_key("D", 1), b"y", (),
         {"content-type": "  application/json;    charset=utf-8  "}),
        ("tab_header", "PUT", probe_key("D", 2), b"y", (),
         {"content-type": "application/json\t\tcharset=utf-8"}),
    )

    def _independent(self, target, signed, body):
        return iv.independent_authorization(
            method=target.method,
            path=f"/{target.bucket}/{target.key}" if target.key
                 else f"/{target.bucket}",
            query_pairs=list(target.query),
            headers={n: v for n, v in signed.canonical_headers},
            payload=body, amz_date=AMZ_DATE, region=probe.R2_REGION,
            service=probe.SIGV4_SERVICE, access_key_id=AKID,
            secret_access_key=SECRET)

    def test_parity(self):
        for name, method, key, body, query, extra in self.CASES:
            for token in (None, "sess+tok/en=="):
                with self.subTest(case=name, token=bool(token)):
                    target = probe_target(method=method, key=key, query=query)
                    signed = sign(target, body=body, session_token=token,
                                  extra_headers=dict(extra))
                    expected = self._independent(target, signed, body)
                    self.assertEqual(signed.canonical_request,
                                     expected["canonical_request"])
                    self.assertEqual(signed.string_to_sign,
                                     expected["string_to_sign"])
                    self.assertEqual(signed.signature, expected["signature"])

    def test_query_encoded_then_sorted(self):
        # 'Z' -> "Z" (0x5A); 'é' -> "%C3%A9" (starts '%', 0x25). After
        # encoding %C3%A9 sorts BEFORE Z; sorting RAW would reverse them.
        expected = "%C3%A9=2&Z=1"
        self.assertEqual(probe._canonical_query((("Z", "1"), ("é", "2"))),
                         expected)
        self.assertEqual(probe._canonical_query((("é", "2"), ("Z", "1"))),
                         expected)
        self.assertEqual(sorted((("Z", "1"), ("é", "2")))[0][0], "Z")

    def test_query_specials(self):
        self.assertEqual(
            probe._canonical_query((("a+b", "c/d"), ("e%f", "g~h"))),
            "a%2Bb=c%2Fd&e%25f=g~h")
        self.assertEqual(probe._canonical_query((("acl", ""),)), "acl=")
        self.assertEqual(probe._canonical_query((("k", "a=b&c"),)),
                         "k=a%3Db%26c")

    def test_canonical_uri_edges(self):
        for key, expected in {
            "catalog/probe/t/a b/o.json":
                "/bible-pal-cas-probe/catalog/probe/t/a%20b/o.json",
            "catalog/probe/t/a~b/o.json":
                "/bible-pal-cas-probe/catalog/probe/t/a~b/o.json",
        }.items():
            with self.subTest(key=key):
                self.assertEqual(
                    probe.target_canonical_path(probe_target(key=key)),
                    expected)

    def test_content_md5_raw_digest(self):
        body = b"bible-pal-probe"
        signed = sign(probe_target(), body=body, include_content_md5=True)
        self.assertEqual(signed.header_map()["content-md5"],
                         base64.b64encode(hashlib.md5(body).digest()).decode())

    def test_header_whitespace_and_tabs(self):
        self.assertEqual(probe.normalise_header_value("  a\t\tb   c "),
                         "a b c")

    def test_content_length_not_signed(self):
        signed = sign(probe_target(), body=b"abc")
        self.assertNotIn("content-length", signed.signed_header_names)
        self.assertNotIn("content-length", signed.header_map())

    def test_security_token_signed(self):
        signed = sign(probe_target(), body=b"x", session_token="TOK+EN/==")
        self.assertIn("x-amz-security-token", signed.signed_header_names)
        self.assertIn("x-amz-security-token:TOK+EN/==\n",
                      signed.canonical_request)
        other = sign(probe_target(), body=b"x", session_token="OTHER")
        self.assertNotEqual(signed.signature, other.signature)

    def test_credential_scope(self):
        self.assertIn(f"/{AMZ_DATE[:8]}/auto/s3/aws4_request",
                      sign(probe_target()).header_map()["authorization"])


# ═══════════════════════════════════════════════════════════════════════════
# Transport, fault injection, state machine
# ═══════════════════════════════════════════════════════════════════════════

class TransportAndFaultTests(unittest.TestCase):

    def _failure(self, exc, on):
        kw = ({"raise_on_request": exc} if on == "request"
              else {"raise_on_getresponse": exc})
        transport = make_transport(FakeConnection(
            response=FakeResponse(200), **kw))
        with self.assertRaises(probe.TransportFailure) as ctx:
            transport.send_signed_offline(sign(probe_target(), body=b"x"))
        return ctx.exception

    def test_factory_failure_is_before_request(self):
        class Dying:
            def __call__(self, host, timeout):
                raise ConnectionRefusedError("connect failed")
        transport = probe.R2Transport(
            endpoint_host=ENDPOINT_HOST, connection_factory=Dying(),
            monotonic=lambda: 0)
        with self.assertRaises(probe.TransportFailure) as ctx:
            transport.send_signed_offline(sign(probe_target(), body=b"x"))
        self.assertIs(ctx.exception.phase, probe.SendPhase.BEFORE_REQUEST)
        self.assertIs(probe.classify_put_outcome(
            transport_failure=ctx.exception, status=None),
            probe.PutOutcome.BEFORE_REQUEST_FAILURE)

    def test_request_failures_are_always_ambiguous(self):
        for exc in (ConnectionResetError("before bytes"),
                    BrokenPipeError("partial send"),
                    ConnectionResetError("after commit"),
                    TimeoutError("during write")):
            with self.subTest(exc=type(exc).__name__):
                failure = self._failure(exc, on="request")
                self.assertIs(failure.phase, probe.SendPhase.DURING_REQUEST)
                outcome = probe.classify_put_outcome(
                    transport_failure=failure, status=None)
                self.assertIs(
                    outcome,
                    probe.PutOutcome.REQUEST_ATTEMPTED_COMMIT_UNKNOWN)
                self.assertIs(
                    probe.next_action(outcome),
                    probe.NextAction.RECONCILE_WITH_AUTHORITATIVE_GET)

    def test_response_wait_failures_are_ambiguous(self):
        for exc in (TimeoutError("await"), ConnectionResetError("reset")):
            with self.subTest(exc=type(exc).__name__):
                failure = self._failure(exc, on="getresponse")
                self.assertIs(failure.phase, probe.SendPhase.AWAITING_RESPONSE)
                self.assertIs(probe.classify_put_outcome(
                    transport_failure=failure, status=None),
                    probe.PutOutcome.RESPONSE_LOST_COMMIT_UNKNOWN)

    def test_definite_statuses(self):
        for status, outcome in ((412, probe.PutOutcome
                                 .DEFINITE_CONDITIONAL_REJECTION),
                                (429, probe.PutOutcome
                                 .DEFINITE_THROTTLE_REJECTION),
                                (403, probe.PutOutcome
                                 .DEFINITE_AUTH_REJECTION)):
            with self.subTest(status=status):
                got = probe.classify_put_outcome(transport_failure=None,
                                                 status=status)
                self.assertIs(got, outcome)
                self.assertIn(got, probe.DEFINITE_NO_MUTATION_OUTCOMES)
                self.assertIsNot(got,
                                 probe.PutOutcome.BEFORE_REQUEST_FAILURE)

    def test_5xx_ambiguous(self):
        for status in (500, 503):
            outcome = probe.classify_put_outcome(transport_failure=None,
                                                 status=status)
            self.assertIs(outcome,
                          probe.PutOutcome.SERVER_ERROR_COMMIT_UNKNOWN)
            self.assertIn(outcome, probe.AMBIGUOUS_OUTCOMES)

    def test_no_replay_branch(self):
        for outcome in probe.PutOutcome:
            self.assertNotIn("REPLAY", probe.next_action(outcome).value)
        for outcome in probe.AMBIGUOUS_OUTCOMES:
            self.assertIs(probe.next_action(outcome),
                          probe.NextAction.RECONCILE_WITH_AUTHORITATIVE_GET)

    def test_reconciliation_table(self):
        common = dict(intended_sha256="a" * 64, intended_length=10,
                      prior_sha256="b" * 64, prior_length=10)
        self.assertIs(probe.reconcile_after_ambiguous_put(
            get_state=probe.RemoteState.CONFIRMED, observed_sha256="a" * 64,
            observed_length=10, **common),
            probe.Reconciliation.RECONCILED_SUCCESS)
        self.assertIs(probe.reconcile_after_ambiguous_put(
            get_state=probe.RemoteState.CONFIRMED, observed_sha256="b" * 64,
            observed_length=10, **common),
            probe.Reconciliation.NO_MUTATION_RESTART_FROM_FRESH_PLAN)
        self.assertIs(probe.reconcile_after_ambiguous_put(
            get_state=probe.RemoteState.CONFIRMED, observed_sha256="c" * 64,
            observed_length=10, **common),
            probe.Reconciliation.SUPERSEDED_CONFLICT)
        self.assertIs(probe.reconcile_after_ambiguous_put(
            get_state=probe.RemoteState.UNKNOWN, observed_sha256=None,
            observed_length=None, **common),
            probe.Reconciliation.UNKNOWN_HUMAN_INTERVENTION)

    def test_exception_category_is_safe(self):
        secret = "SUPER-SECRET-VALUE"
        failure = self._failure(ConnectionRefusedError(secret), on="request")
        self.assertNotIn(secret, failure.category.value)
        self.assertNotIn(secret, str(failure))
        self.assertNotIn(secret, failure.exception_type_name)

    def test_redirects_refused(self):
        for status in (301, 302, 307, 308):
            with self.subTest(status=status):
                transport = make_transport(FakeConnection(
                    response=FakeResponse(status, [("Location", "https://x")])))
                with self.assertRaises(probe.SafetyBarrierTripped):
                    transport.send_signed_offline(
                        sign(probe_target(), body=b"x"))

    def test_response_bounded(self):
        big = b"x" * (probe.MAX_RESPONSE_BODY_BYTES + 100)
        transport = make_transport(FakeConnection(
            response=FakeResponse(200, [], big)))
        response = transport.send_signed_offline(
            sign(probe_target(method="GET")), max_response_bytes=1024)
        self.assertTrue(response.body_truncated)
        self.assertEqual(len(response.body), 1024)

    def test_single_part_invariant(self):
        conn = FakeConnection(response=FakeResponse(200))
        transport = make_transport(conn)
        transport.send_signed_offline(sign(probe_target(method="GET")))
        transport.send_signed_offline(sign(probe_target(), body=b"x"))
        probe.assert_single_part(transport.ledger)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_single_part([{"method": "PUT", "query": []},
                                      {"method": "PUT", "query": []}])
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.assert_single_part([{"method": "PUT",
                                       "query": ["uploadId"]}])

    def test_host_mismatch_refused(self):
        transport = make_transport(FakeConnection(response=FakeResponse(200)))
        signed = probe.sign_request(
            target=probe_target(), host="1" * 32 + ".r2.cloudflarestorage.com",
            access_key_id=AKID, secret_access_key=SECRET, session_token=None,
            body=b"x", amz_date=AMZ_DATE)
        with self.assertRaises(probe.EndpointRefused):
            transport.send_signed_offline(signed)


# ═══════════════════════════════════════════════════════════════════════════
# Error parsing, absence, credentials, guards, payloads, evidence writer
# ═══════════════════════════════════════════════════════════════════════════

class ErrorParsingTests(unittest.TestCase):

    def test_simple(self):
        self.assertEqual(
            probe.parse_s3_error(b"<Error><Code>NoSuchKey</Code></Error>").code,
            "NoSuchKey")

    def test_rejections(self):
        cases = {
            "duplicate": b"<Error><Code>A</Code><Code>B</Code></Error>",
            "nested": b"<Error><D><Code>NoSuchKey</Code></D></Error>",
            "children": b"<Error><Code>No<x/>Key</Code></Error>",
            "wrong_root": b"<NotError><Code>NoSuchKey</Code></NotError>",
            "malformed": b"<<not xml",
            "dtd": (b'<!DOCTYPE Error [<!ENTITY x "y">]>'
                    b"<Error><Code>NoSuchKey</Code></Error>"),
        }
        for name, payload in cases.items():
            with self.subTest(case=name):
                self.assertIsNone(probe.parse_s3_error(payload).code)

    def test_oversized_and_truncated(self):
        payload = (b"<Error><Code>NoSuchKey</Code><Message>"
                   + b"x" * (probe.MAX_ERROR_BODY_BYTES + 10)
                   + b"</Message></Error>")
        self.assertIsNone(probe.parse_s3_error(payload).code)
        self.assertIsNone(probe.parse_s3_error(
            b"<Error><Code>NoSuchKey</Code></Error>", truncated=True).code)

    def test_opaque_message_omitted(self):
        parsed = probe.parse_s3_error(
            b"<Error><Code>AccessDenied</Code>"
            b"<Message>tok_ABCDEFGHIJKLMNOPQRSTUV leaked</Message>"
            b"<HostId>host-abc</HostId></Error>")
        self.assertEqual(parsed.code, "AccessDenied")
        self.assertIsNone(parsed.message)
        self.assertTrue(parsed.message_omitted)
        self.assertEqual(parsed.host_id_sha256,
                         hashlib.sha256(b"host-abc").hexdigest())

    def test_safe_message_kept(self):
        self.assertEqual(probe.parse_s3_error(
            b"<Error><Code>PreconditionFailed</Code>"
            b"<Message>At least one of the preconditions failed</Message>"
            b"</Error>").message,
            "At least one of the preconditions failed")


class AbsenceTests(unittest.TestCase):

    def test_absent_requires_get_404_nosuchkey(self):
        self.assertIs(probe.classify_remote_state(
            method="GET", status=404, error_code="NoSuchKey"),
            probe.RemoteState.ABSENT)

    def test_head_never_absent(self):
        self.assertIs(probe.classify_remote_state(
            method="HEAD", status=404, error_code="NoSuchKey"),
            probe.RemoteState.UNKNOWN)

    def test_other_states_unknown(self):
        for status, code in ((403, "AccessDenied"), (429, None), (500, None),
                             (404, "NoSuchBucket")):
            with self.subTest(status=status):
                self.assertIs(probe.classify_remote_state(
                    method="GET", status=status, error_code=code),
                    probe.RemoteState.UNKNOWN)
        self.assertIs(probe.classify_remote_state(
            method="GET", status=None, error_code=None,
            transport_failed=True), probe.RemoteState.UNKNOWN)
        self.assertIs(probe.classify_remote_state(
            method="GET", status=200, error_code=None, body_valid=True,
            body_truncated=True), probe.RemoteState.UNKNOWN)

    def test_confirmed_and_corrupt(self):
        self.assertIs(probe.classify_remote_state(
            method="GET", status=200, error_code=None, body_valid=True),
            probe.RemoteState.CONFIRMED)
        self.assertIs(probe.classify_remote_state(
            method="GET", status=200, error_code=None, body_valid=False),
            probe.RemoteState.CORRUPT)
        self.assertIs(probe.classify_remote_state(
            method="GET", status=200, error_code=None, body_valid=None),
            probe.RemoteState.UNKNOWN)


class TemporaryCredentialTests(unittest.TestCase):

    def test_fields_verified_independently(self):
        cred = make_credential()
        report = iv.independent_inspect_credential(
            session_token=cred.session_token,
            secret_access_key=cred.secret_access_key,
            parent_secret_access_key=SECRET)
        for flag in ("session_token_prefix_ok", "jwt_structure_ok",
                     "signature_ok", "derived_secret_ok", "standard_base64"):
            self.assertTrue(report[flag], flag)
        claims = report["claims"]
        self.assertEqual(report["header"], {"alg": "HS256", "typ": "JWT"})
        self.assertEqual(claims["sub"], ACCOUNT_ID)
        self.assertEqual(claims["iss"], AKID)
        self.assertEqual(claims["aud"], ENDPOINT_HOST)
        self.assertEqual(claims["bucket"], PROBE_BUCKET)
        self.assertEqual(claims["scope"], "object-read-write")
        self.assertEqual(claims["actions"],
                         ["HeadObject", "GetObject", "PutObject"])
        self.assertEqual(claims["paths"]["prefixPaths"], ["catalog/"])
        self.assertEqual(claims["paths"]["objectPaths"], [])

    def test_golden_fixture_pinned_out_of_band(self):
        cred = probe.mint_probe_credential(
            group=iv.GOLDEN_CREDENTIAL_INPUTS["group"],
            account_id=iv.GOLDEN_CREDENTIAL_INPUTS["account_id"],
            parent_access_key_id=iv.GOLDEN_CREDENTIAL_INPUTS[
                "parent_access_key_id"],
            parent_secret_access_key=iv.GOLDEN_CREDENTIAL_INPUTS[
                "parent_secret_access_key"],
            now=iv.GOLDEN_CREDENTIAL_INPUTS["now"])
        self.assertEqual(cred.secret_access_key, iv.GOLDEN_DERIVED_SECRET)
        self.assertEqual(
            hashlib.sha256(cred.session_token.encode()).hexdigest(),
            iv.GOLDEN_SESSION_TOKEN_SHA256)

    def test_no_widening_parameters(self):
        import inspect
        params = set(inspect.signature(probe.mint_probe_credential).parameters)
        for forbidden in ("scope", "actions", "prefix_paths", "object_paths",
                          "bucket", "audience", "aud", "ttl_seconds", "ttl"):
            self.assertNotIn(forbidden, params)

    def test_ttls(self):
        self.assertEqual(make_credential("T-EXPIRY").expires_at
                         - make_credential("T-EXPIRY").issued_at, 60)
        for group in ("T-CAS-1", "T-CAS-2", "T-RACE", "T-SCOPE", "T-SHAPE"):
            cred = make_credential(group)
            self.assertEqual(cred.expires_at - cred.issued_at, 900)

    def test_rejections(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            make_credential("T-ADMIN")
        for bad in ("", "SHORT", "G" * 32, OTHER_ACCOUNT_ID.upper(), "0" * 31):
            with self.subTest(account=bad):
                with self.assertRaises(probe.EndpointRefused):
                    probe.mint_probe_credential(
                        group="T-CAS-1", account_id=bad,
                        parent_access_key_id=AKID,
                        parent_secret_access_key=SECRET, now=1)

    def test_redacted_summary_has_no_secret(self):
        cred = make_credential()
        blob = json.dumps(cred.redacted_summary())
        self.assertNotIn(cred.secret_access_key, blob)
        self.assertNotIn(cred.session_token, blob)


class GroupPlannerTests(unittest.TestCase):

    def cred(self, group="T-CAS-1", ttl=900, issued=1_000_000):
        return probe.TemporaryCredential(
            group=group, access_key_id="A" * 8, secret_access_key="B" * 8,
            session_token="C" * 8, issued_at=issued, expires_at=issued + ttl,
            bucket=PROBE_BUCKET, scope="object-read-write",
            actions=("HeadObject",), prefix_paths=("catalog/",))

    def test_no_caller_cost(self):
        import inspect
        self.assertNotIn("estimated_cost_seconds", set(inspect.signature(
            probe.CredentialGroupPlanner.can_start).parameters))

    def test_admission(self):
        planner = probe.CredentialGroupPlanner()
        self.assertTrue(planner.can_start(credential=self.cred(),
                                          now=1_000_000)[0])
        self.assertFalse(planner.can_start(credential=self.cred(),
                                           now=1_000_800)[0])

    def test_expiry_policy(self):
        planner = probe.CredentialGroupPlanner()
        fresh = self.cred("T-EXPIRY", ttl=60, issued=1_000_000)
        self.assertTrue(planner.can_start(credential=fresh, now=1_000_002)[0])
        self.assertFalse(planner.can_start(credential=fresh, now=1_000_050)[0])

    def test_expiry_credential_never_reused(self):
        planner = probe.CredentialGroupPlanner()
        expiry = self.cred("T-EXPIRY", ttl=60)
        planner.assert_credential_matches_test(expiry, "I4")
        for other in ("B", "E2", "H1", "J"):
            with self.subTest(test=other):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    planner.assert_credential_matches_test(expiry, other)
        with self.assertRaises(probe.SafetyBarrierTripped):
            planner.assert_credential_matches_test(self.cred("T-CAS-1"), "I4")
        with self.assertRaises(probe.SafetyBarrierTripped):
            planner.assert_credential_matches_test(self.cred("T-CAS-1"), "E2")


class WriteGuardTests(unittest.TestCase):

    class Clock:
        def __init__(self):
            self.now = 1000.0
            self.slept = []

        def monotonic(self):
            return self.now

        def sleep(self, s):
            self.slept.append(s)
            self.now += s

        def advance(self, s):
            self.now += s

    def setUp(self):
        self.clock = self.Clock()
        self.guard = probe.SameKeyWriteGuard(
            monotonic=self.clock.monotonic, sleep=self.clock.sleep)

    def test_min_gap_is_three_seconds(self):
        self.assertEqual(probe.SameKeyWriteGuard.MIN_GAP_SECONDS, 3.0)

    def test_first_write_no_wait(self):
        self.assertEqual(self.guard.wait_until_writable("k"), 0.0)
        self.assertEqual(self.clock.slept, [])

    def test_gap_from_response_end(self):
        self.guard.note_write_response_end("k")
        self.clock.advance(1.0)
        self.assertAlmostEqual(self.guard.wait_until_writable("k"), 2.0)
        self.assertEqual(self.guard.seconds_until_writable("k"), 0.0)

    def test_loops_when_clock_underadvances(self):
        clock = self.Clock()
        sleeps = []

        def lazy(s):
            sleeps.append(s)
            clock.now += s / 2.0

        guard = probe.SameKeyWriteGuard(monotonic=clock.monotonic, sleep=lazy)
        guard.note_write_response_end("k")
        self.assertGreaterEqual(guard.wait_until_writable("k"), 3.0)
        self.assertGreater(len(sleeps), 1)

    def test_nonadvancing_clock_raises(self):
        guard = probe.SameKeyWriteGuard(monotonic=lambda: 1000.0,
                                        sleep=lambda s: None)
        guard.note_write_response_end("k", mono_ts=1000.0)
        with self.assertRaises(probe.SafetyBarrierTripped):
            guard.wait_until_writable("k")

    def test_keys_independent(self):
        self.guard.note_write_response_end("k1")
        self.assertEqual(self.guard.seconds_until_writable("k2"), 0.0)
        self.assertGreater(self.guard.seconds_until_writable("k1"), 0.0)


class KeyAllocatorTests(unittest.TestCase):

    def test_format_and_uniqueness(self):
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        issued = alloc.allocate(phase="t", test_id="B", repetition=1)
        self.assertEqual(issued.identity.key,
                         "catalog/probe/t/run-abc/b/0001/obj.json")
        keys = {alloc.allocate(phase="t", test_id="B",
                               repetition=r).identity.key
                for r in range(2, 12)}
        self.assertEqual(len(keys), 10)

    def test_reuse_and_bad_inputs_refused(self):
        alloc = probe.ProbeKeyAllocator(RUN_ID)
        alloc.allocate(phase="t", test_id="B", repetition=1)
        with self.assertRaises(probe.SafetyBarrierTripped):
            alloc.allocate(phase="t", test_id="B", repetition=1)
        for kwargs in ({"phase": "x", "test_id": "B", "repetition": 1},
                       {"phase": "t", "test_id": "ZZ", "repetition": 1},
                       {"phase": "t", "test_id": "B", "repetition": 0}):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    alloc.allocate(**kwargs)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.ProbeKeyAllocator("../evil")


class ArchiveAuditTests(unittest.TestCase):

    SEM = "5" * 64
    RAW = "7" * 64

    def expected(self):
        return probe.new_archive_expectation(
            version=7, semantic_sha256=self.SEM, raw_sha256=self.RAW,
            length=1234)

    def test_archive_paths(self):
        exp = self.expected()
        self.assertIs(probe.classify_archive(create_status=200, expected=exp),
                      probe.ArchiveOutcome.CREATED)
        idem = probe.classify_archive(
            create_status=412, get_state=probe.RemoteState.CONFIRMED,
            observed_version=7, observed_semantic_sha256=self.SEM,
            observed_raw_sha256=self.RAW, observed_length=1234, expected=exp)
        self.assertIs(idem, probe.ArchiveOutcome.IDEMPOTENT_EXISTING_ARCHIVE)
        self.assertTrue(probe.archive_allows_pointer_mutation(idem))

    def test_archive_collision_blocks_pointer(self):
        exp = self.expected()
        for field, value in (("observed_raw_sha256", "e" * 64),
                             ("observed_semantic_sha256", "e" * 64),
                             ("observed_length", 9999),
                             ("observed_version", 8)):
            kwargs = dict(create_status=412,
                          get_state=probe.RemoteState.CONFIRMED,
                          observed_version=7, observed_semantic_sha256=self.SEM,
                          observed_raw_sha256=self.RAW, observed_length=1234,
                          expected=exp)
            kwargs[field] = value
            with self.subTest(field=field):
                outcome = probe.classify_archive(**kwargs)
                self.assertIs(outcome, probe.ArchiveOutcome.VERSION_COLLISION)
                self.assertFalse(probe.archive_allows_pointer_mutation(outcome))

    def test_archive_unknown_blocks(self):
        exp = self.expected()
        for status in (403, 429, 500, None):
            self.assertFalse(probe.archive_allows_pointer_mutation(
                probe.classify_archive(create_status=status, expected=exp)))

    def test_audit_never_rolls_back(self):
        for outcome in (probe.AuditOutcome.COLLISION,
                        probe.AuditOutcome.UNKNOWN):
            self.assertIs(probe.classify_publication(
                pointer_committed_and_verified=True, audit_outcome=outcome),
                probe.PublicationClassification
                .PUBLICATION_SUCCEEDED_AUDIT_FAILED)
        self.assertFalse(probe.audit_failure_permits_pointer_rollback())
        self.assertFalse(probe.audit_failure_permits_pointer_replay())

    def test_audit_success_and_uncommitted(self):
        self.assertIs(probe.classify_publication(
            pointer_committed_and_verified=True,
            audit_outcome=probe.AuditOutcome.CREATED),
            probe.PublicationClassification.PUBLICATION_SUCCEEDED)
        self.assertIs(probe.classify_publication(
            pointer_committed_and_verified=False,
            audit_outcome=probe.AuditOutcome.CREATED),
            probe.PublicationClassification.PUBLICATION_NOT_COMMITTED)

    def test_audit_repair(self):
        self.assertIs(probe.classify_audit(
            create_status=412, get_state=probe.RemoteState.CONFIRMED,
            observed_sha256="a" * 64, expected_sha256="a" * 64),
            probe.AuditOutcome.IDEMPOTENT_EXISTING_AUDIT)
        self.assertIs(probe.classify_audit(
            create_status=412, get_state=probe.RemoteState.CONFIRMED,
            observed_sha256="b" * 64, expected_sha256="a" * 64),
            probe.AuditOutcome.COLLISION)


class PayloadTests(unittest.TestCase):

    def test_exact_sizes(self):
        self.assertEqual(len(probe.production_size_payload("p")), 2_589_207)
        for size in range(80, 140):
            self.assertEqual(len(probe.synthetic_payload("s", size)), size)

    def test_valid_json_not_catalog(self):
        for size in (128, 4096, probe.PRODUCTION_BODY_BYTES):
            with self.subTest(size=size):
                decoded = json.loads(probe.synthetic_payload("s", size))
                self.assertTrue(decoded["__probe__"])
                self.assertNotIn("parables", decoded)

    def test_rejections(self):
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.synthetic_payload("../evil", 4096)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.synthetic_payload("ok", 4)


class EvidenceWriterTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self._tmp.name, "bible-pal")
        self.addCleanup(self._tmp.cleanup)

    def writer(self, run_id):
        return probe.EvidenceWriter.for_testing(self.root, run_id)

    def write_one_semantic(self, w, test_id="B", rep=1):
        issued = w.allocate_semantic(test_id, rep)
        return w.write_semantic_record(
            issued, http_status=412,
            outcome=probe.PutOutcome.DEFINITE_CONDITIONAL_REJECTION,
            mutation_observed=False)

    def test_secrets_required(self):
        with self.assertRaises(TypeError):
            probe.EvidenceWriter(self.root, "run-x")  # missing secrets
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.EvidenceWriter(self.root, "run-x", secrets="notatuple")

    def test_modes_and_anchor(self):
        w = self.writer("run-1")
        rel = self.write_one_semantic(w)
        for d in (w.root, w.evidence_dir, w.anchor_dir, w.run_dir):
            self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(
            os.path.join(w.run_dir, rel)).st_mode), 0o600)
        result = w.finalize()
        self.assertFalse(os.path.abspath(result["anchor_path"]).startswith(
            os.path.abspath(w.run_dir) + os.sep))
        with open(result["anchor_path"], encoding="ascii") as h:
            self.assertEqual(h.read().strip(), result["manifest_sha256"])

    def test_run_dir_exclusivity(self):
        self.writer("dupe")
        with self.assertRaises(FileExistsError):
            self.writer("dupe")

    def test_partial_write_looped(self):
        w = self.writer("run-3")
        real_write = os.write
        state = {"first": True}

        def choppy(fd, data):
            if state["first"] and len(data) > 4:
                state["first"] = False
                return real_write(fd, data[:4])
            return real_write(fd, data)

        with mock.patch.object(os, "write", choppy):
            rel = self.write_one_semantic(w)
        with open(os.path.join(w.run_dir, rel), encoding="utf-8") as h:
            self.assertEqual(json.load(h)["test_id"], "B")

    def test_directory_safety(self):
        base = self._tmp.name
        loose = os.path.join(base, "loose")
        os.mkdir(loose, 0o755)
        before = stat.S_IMODE(os.stat(loose).st_mode)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.EvidenceWriter.for_testing(loose, "runx")
        self.assertEqual(stat.S_IMODE(os.stat(loose).st_mode), before)

        real = os.path.join(base, "real")
        os.mkdir(real, 0o700)
        link = os.path.join(base, "link")
        os.symlink(real, link)
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.EvidenceWriter.for_testing(link, "runx")

        root = os.path.join(base, "ok-root")
        os.mkdir(root, 0o700)
        elsewhere = os.path.join(base, "elsewhere")
        os.mkdir(elsewhere, 0o700)
        os.symlink(elsewhere, os.path.join(root, "cas-probe-evidence"))
        with self.assertRaises(probe.SafetyBarrierTripped):
            probe.EvidenceWriter.for_testing(root, "runx")

    def test_unsafe_run_ids(self):
        for run_id in ("../x", "a/b", "", "x" * 100):
            with self.subTest(run_id=run_id):
                with self.assertRaises(probe.SafetyBarrierTripped):
                    self.writer(run_id)

    def test_default_root_outside_repo(self):
        root = probe.default_evidence_root()
        self.assertTrue(root.endswith(
            os.path.join(".local", "state", "bible-pal")))
        self.assertFalse(os.path.abspath(root).startswith(
            str(_SCRIPTS.parent) + os.sep))

    def test_record_builders_are_kind_valid(self):
        credential = group_credential("T-CAS-1")
        signed = probe.sign_request(
            target=probe_target(key=probe_key("B", 1)), host=ENDPOINT_HOST,
            access_key_id=credential.access_key_id,
            secret_access_key=credential.secret_access_key,
            session_token=credential.session_token, body=b"x",
            amz_date=AMZ_DATE)
        request_record = probe.build_request_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=1,
            endpoint_host=ENDPOINT_HOST, signed=signed,
            credential=credential)
        self.assertEqual(
            probe.validate_record(request_record,
                                  (credential.session_token,)),
            "REQUEST_RECORD")
        # The token itself is never stored — only its fingerprint.
        self.assertNotIn(credential.session_token,
                         json.dumps(request_record))
        self.assertEqual(request_record["session_token_sha256"],
                         hashlib.sha256(
                             credential.session_token.encode()).hexdigest())
        self.assertTrue(request_record["session_token_signed"])
        blob = json.dumps(request_record)
        self.assertNotIn(ENDPOINT_HOST, blob)
        self.assertNotIn(ACCOUNT_ID, blob)

        response = probe.RawResponse(
            status=412, headers=(("ETag", '"abc"'), ("cf-ray", "r1")),
            body=b"<Error><Code>PreconditionFailed</Code></Error>",
            body_truncated=False, t_request_start_mono_ns=1,
            t_response_end_mono_ns=2)
        response_record = probe.build_response_record(
            phase="T", run_id=RUN_ID, group="T-CAS-1", test_id="B",
            repetition=1, sequence=2,
            response=response, parsed=probe.parse_s3_error(response.body),
            repetition_status=probe.RepetitionStatus.VALID)
        self.assertEqual(probe.validate_record(response_record, ()),
                         "RESPONSE_RECORD")
        self.assertEqual(response_record["etag_raw"], '"abc"')


# ═══════════════════════════════════════════════════════════════════════════
# CLI / no-network / repository hygiene
# ═══════════════════════════════════════════════════════════════════════════

class CliAndNoNetworkTests(unittest.TestCase):

    def test_default_factory_refuses(self):
        transport = probe.R2Transport(endpoint_host=ENDPOINT_HOST)
        with no_sockets():
            with self.assertRaises(probe.SafetyBarrierTripped):
                transport.send_signed_offline(sign(probe_target(), body=b"x"))

    def test_plan_mode_zero_sockets(self):
        for argv in ([], ["--plan"]):
            buf = io.StringIO()
            with no_sockets(), mock.patch("sys.stdout", buf):
                self.assertEqual(probe.main(argv), probe.EXIT_OK)
            self.assertIn("NO SOCKETS", buf.getvalue())
            self.assertIn("LIVE EXECUTION IS DISABLED", buf.getvalue())

    def test_cli_refuses_production_bucket(self):
        with no_sockets(), mock.patch("sys.stderr", io.StringIO()):
            self.assertEqual(
                probe.main(["--plan", "--bucket", PRODUCTION_BUCKET]),
                probe.EXIT_PRODUCTION_NAME_DETECTED)

    def test_execute_refuses_even_with_a_real_credentials_file(self):
        """Codex: even if all authorization args and a real-looking
        credential file exist, the CLI must still refuse."""
        with tempfile.NamedTemporaryFile("w", suffix=".env",
                                         delete=False) as handle:
            handle.write("AWS_ACCESS_KEY_ID=x\nAWS_SECRET_ACCESS_KEY=y\n")
            cred_path = handle.name
        self.addCleanup(os.unlink, cred_path)
        argv = ["--execute", "--bucket", PROBE_BUCKET,
                "--account-id", ACCOUNT_ID,
                "--confirm", probe.EXECUTE_CONFIRMATION,
                "--authorized-by-adam", "--credentials-file", cred_path]
        err = io.StringIO()
        with no_sockets(), mock.patch("sys.stderr", err):
            code = probe.main(argv)
        self.assertEqual(code, probe.EXIT_MISSING_AUTHORIZATION)
        self.assertIn("not enabled in this build", err.getvalue())

    def test_execute_gate_removal_refuses(self):
        base = ["--execute", "--bucket", PROBE_BUCKET,
                "--account-id", ACCOUNT_ID,
                "--confirm", probe.EXECUTE_CONFIRMATION,
                "--authorized-by-adam",
                "--credentials-file", "/nonexistent/probe.env"]
        for drop in (["--authorized-by-adam"],
                     ["--confirm", probe.EXECUTE_CONFIRMATION]):
            argv = [a for a in base if a not in drop]
            with no_sockets(), mock.patch("sys.stderr", io.StringIO()):
                self.assertEqual(probe.main(argv),
                                 probe.EXIT_MISSING_AUTHORIZATION)

    def test_plan_states_semantic_rule(self):
        rendered = probe.render_plan(bucket=PROBE_BUCKET, account_id=None)
        self.assertIn("EVERY valid repetition", rendered)
        self.assertNotIn("at least one", rendered.lower())


class ManifestAndHygieneTests(unittest.TestCase):

    def test_never_opens_the_manifest(self):
        opened = []
        real_open, real_os_open = builtins.open, os.open

        def traced(file, *a, **k):
            opened.append(str(file))
            return real_open(file, *a, **k)

        def traced_os(path, *a, **k):
            opened.append(str(path))
            return real_os_open(path, *a, **k)

        with no_sockets(), mock.patch.object(builtins, "open", traced), \
                mock.patch.object(os, "open", traced_os), \
                mock.patch("sys.stdout", io.StringIO()):
            probe.main(["--plan"])
            probe.synthetic_payload("a", 4096)
            probe.production_size_payload("b")
        self.assertEqual([p for p in opened if p.endswith("manifest.json")],
                         [])

    def test_only_stdlib_imports(self):
        tree = ast.parse(
            (_SCRIPTS / "probe_r2_cas.py").read_text(encoding="utf-8"))
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
        self.assertEqual(sorted(imported - set(sys.stdlib_module_names)), [])

    def test_writes_nothing_into_the_repo(self):
        repo_root = _SCRIPTS.parent
        snapshot = lambda: {p for p in repo_root.rglob("*") if p.is_file()  # noqa: E731
                            and "scratchpad" not in p.parts
                            and ".git" not in p.parts}
        before = snapshot()
        with no_sockets(), mock.patch("sys.stdout", io.StringIO()):
            probe.main(["--plan"])
        self.assertEqual(snapshot() - before, set())


class RepositoryContractTests(unittest.TestCase):
    """DEFENCE IN DEPTH ONLY.

    These AST checks can be evaded by arbitrary dynamic Python, which the
    probe's header explicitly places outside the threat model. They are
    not the primary boundary — closure-captured policy plus exact-type
    validation at every wire boundary is.
    """

    def setUp(self):
        self.code = probe_code_signature()

    def test_no_multipart_or_copy(self):
        for symbol in ("CreateMultipartUpload", "UploadPart",
                       "CompleteMultipartUpload", "CopyObject",
                       "x-amz-copy-source"):
            self.assertNotIn(symbol, self.code)

    def test_no_rest_temp_credentials(self):
        for symbol in ("api.cloudflare.com", "temp-access-credentials",
                       "Bearer"):
            self.assertNotIn(symbol, self.code)

    def test_no_scratchpad_or_staging(self):
        self.assertNotIn("scratchpad", self.code)
        self.assertNotIn("build/r2-staging", self.code)

    def test_no_shell_out(self):
        forbidden_modules = {"subprocess", "pty", "shlex"}
        forbidden_attrs = {"system", "popen", "execv", "execve", "spawnv",
                           "fork", "posix_spawn"}
        for node in ast.walk(probe_ast()):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    self.assertNotIn(alias.name.split(".")[0],
                                     forbidden_modules)
            elif isinstance(node, ast.ImportFrom) and node.module:
                self.assertNotIn(node.module.split(".")[0], forbidden_modules)
            elif isinstance(node, ast.Attribute):
                self.assertNotIn(node.attr, forbidden_attrs)

    def test_no_wrangler_literal_except_scrub_prefix(self):
        # "WRANGLER_" appears in the scrub list twice now: the closure
        # policy value and its display alias. Both are the env-scrub
        # prefix — the opposite of a wrangler dependency.
        wrangler = [lit for lit in probe_string_literals()
                    if "wrangler" in lit.lower()]
        self.assertTrue(wrangler)
        self.assertTrue(all(lit == "WRANGLER_" for lit in wrangler))

    def test_no_dialable_url_or_account_literal(self):
        import re
        for literal in probe_string_literals():
            if "<" in literal:
                continue
            self.assertFalse(literal.startswith(("http://", "https://"))
                             and len(literal) > len("https://"))
            self.assertIsNone(re.search(r"[0-9a-f]{32}\.r2\.", literal))

    def test_urllib_request_not_used(self):
        self.assertNotIn("urllib.request", self.code)
        self.assertIn("http.client", self.code)

    def test_threat_model_is_documented(self):
        source = (_SCRIPTS / "probe_r2_cas.py").read_text(encoding="utf-8")
        self.assertIn("THREAT MODEL", source)
        self.assertIn("OUT OF SCOPE", source)
        self.assertIn("monkeypatch", source)
        self.assertIn("clean, dedicated process", source)


if __name__ == "__main__":  # pragma: no cover
    unittest.main(verbosity=2)
