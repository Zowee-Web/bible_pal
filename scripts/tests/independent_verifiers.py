#!/usr/bin/env python3
"""Independently authored verifiers for the CAS probe's crypto.

WHY THIS FILE EXISTS
--------------------
scripts/probe_r2_cas.py produces AWS SigV4 signatures and Cloudflare R2
temporary credentials. If the only thing that checked those outputs were
the code that produced them, a consistent misreading of either spec would
sail through every test.

Everything here is written from the published specifications WITHOUT
importing or consulting scripts/probe_r2_cas.py. The decomposition,
helper names and control flow are deliberately different: this module
builds the canonical request from an explicit list of parts and does its
own percent-encoding table, where the probe uses urllib and string joins.

HONEST LIMITATION
-----------------
This file and the probe were authored in the same session by the same
agent. That is weaker than two genuinely independent authors, and it is
exactly the gap that independent Codex review is meant to close. It is
recorded here so a reviewer is not misled about the strength of the
"independent" claim.

There is no network access at import or call time.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json

# ─────────────────────────────────────────────────────────────────────────
# Percent-encoding, built from the RFC 3986 unreserved set by hand rather
# than by delegating to urllib (which is what the probe uses).
# ─────────────────────────────────────────────────────────────────────────

_UNRESERVED = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789"
    "-._~"
)


def uri_encode(value: str, encode_slash: bool) -> str:
    out = []
    for byte in value.encode("utf-8"):
        char = chr(byte)
        if char in _UNRESERVED:
            out.append(char)
        elif char == "/" and not encode_slash:
            out.append("/")
        else:
            out.append("%%%02X" % byte)
    return "".join(out)


def hex_sha256(data: bytes) -> str:
    digest = hashlib.sha256()
    digest.update(data)
    return digest.hexdigest()


def _sign(key: bytes, message: str) -> bytes:
    return hmac.new(key, message.encode("utf-8"), hashlib.sha256).digest()


def independent_signing_key(secret: str, datestamp: str, region: str,
                            service: str) -> bytes:
    stage1 = _sign(("AWS4" + secret).encode("utf-8"), datestamp)
    stage2 = _sign(stage1, region)
    stage3 = _sign(stage2, service)
    return _sign(stage3, "aws4_request")


def collapse_whitespace(value: str) -> str:
    """AWS header-value canonicalisation: trim, collapse runs of
    whitespace (spaces AND tabs and other whitespace) to one space.

    Written as an explicit character walk — deliberately not the
    probe's `" ".join(value.split())` construction — so the two
    implementations agree by matching the SPEC, not by sharing code.
    """
    out: list[str] = []
    in_gap = False
    for ch in value:
        if ch.isspace():
            in_gap = True
            continue
        if in_gap and out:
            out.append(" ")
        in_gap = False
        out.append(ch)
    return "".join(out)


def independent_canonical_request(*, method: str, path: str,
                                  query_pairs, headers, payload_hash: str
                                  ) -> tuple[str, str]:
    """Return (canonical_request, signed_headers).

    `headers` is a mapping of already-lowercased names to raw values.
    """
    canonical_uri = uri_encode(path, encode_slash=False)

    encoded_pairs = []
    for name, value in query_pairs:
        encoded_pairs.append(
            (uri_encode(name, encode_slash=True),
             uri_encode(value, encode_slash=True)))
    encoded_pairs.sort()
    canonical_query = "&".join(f"{n}={v}" for n, v in encoded_pairs)

    names = sorted(headers)
    canonical_headers = ""
    for name in names:
        canonical_headers += name + ":" + collapse_whitespace(headers[name]) + "\n"
    signed_headers = ";".join(names)

    parts = [
        method,
        canonical_uri,
        canonical_query,
        canonical_headers,
        signed_headers,
        payload_hash,
    ]
    return "\n".join(parts), signed_headers


def independent_authorization(*, method: str, path: str, query_pairs,
                              headers, payload: bytes, amz_date: str,
                              region: str, service: str,
                              access_key_id: str, secret_access_key: str
                              ) -> dict:
    payload_hash = hex_sha256(payload)
    canonical, signed_headers = independent_canonical_request(
        method=method, path=path, query_pairs=query_pairs,
        headers=headers, payload_hash=payload_hash)

    datestamp = amz_date[0:8]
    scope = "/".join((datestamp, region, service, "aws4_request"))
    string_to_sign = "\n".join((
        "AWS4-HMAC-SHA256",
        amz_date,
        scope,
        hex_sha256(canonical.encode("utf-8")),
    ))
    key = independent_signing_key(secret_access_key, datestamp, region, service)
    signature = hmac.new(
        key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    header = ("AWS4-HMAC-SHA256 "
              f"Credential={access_key_id}/{scope}, "
              f"SignedHeaders={signed_headers}, "
              f"Signature={signature}")
    return {
        "canonical_request": canonical,
        "string_to_sign": string_to_sign,
        "signature": signature,
        "signed_headers": signed_headers,
        "authorization": header,
        "payload_hash": payload_hash,
    }


# ─────────────────────────────────────────────────────────────────────────
# Cloudflare R2 temporary-credential verification
# ─────────────────────────────────────────────────────────────────────────

def _b64url_decode(segment: str) -> bytes:
    padding = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode(segment + padding)


def independent_inspect_credential(*, session_token: str,
                                   secret_access_key: str,
                                   parent_secret_access_key: str) -> dict:
    """Decode and verify a locally signed R2 temporary credential.

    Returns the decoded header and claims plus verification booleans. Does
    not raise on mismatch — the caller asserts, so a failure reports which
    specific property broke.
    """
    raw = base64.b64decode(session_token.encode("ascii"))
    prefix_ok = raw.startswith(b"jwt/")
    jwt = raw[4:].decode("utf-8") if prefix_ok else raw.decode("utf-8")

    pieces = jwt.split(".")
    structure_ok = len(pieces) == 3
    header = json.loads(_b64url_decode(pieces[0])) if structure_ok else {}
    claims = json.loads(_b64url_decode(pieces[1])) if structure_ok else {}

    expected_sig = hmac.new(
        parent_secret_access_key.encode("utf-8"),
        (pieces[0] + "." + pieces[1]).encode("utf-8"),
        hashlib.sha256).digest() if structure_ok else b""
    actual_sig = _b64url_decode(pieces[2]) if structure_ok else b""

    recomputed_secret = hashlib.sha256(jwt.encode("utf-8")).hexdigest()

    # base64.b64decode with validate=True rejects the URL-safe alphabet,
    # which is how we prove the session token uses STANDARD base64.
    standard_base64 = True
    try:
        base64.b64decode(session_token.encode("ascii"), validate=True)
    except Exception:  # noqa: BLE001
        standard_base64 = False

    return {
        "session_token_prefix_ok": prefix_ok,
        "jwt_structure_ok": structure_ok,
        "header": header,
        "claims": claims,
        "signature_ok": hmac.compare_digest(expected_sig, actual_sig),
        "derived_secret_ok": hmac.compare_digest(
            recomputed_secret, secret_access_key),
        "standard_base64": standard_base64,
        "jwt": jwt,
    }


# ═════════════════════════════════════════════════════════════════════════
# PROVENANCE — every fixed literal below is labelled with its exact source
# ═════════════════════════════════════════════════════════════════════════
#
# ── SOURCE A: the normative SigV4 algorithm ──────────────────────────────
# RETRIEVED AND READ 2026-08-16 from the official AWS page below. This
# page supplied, verbatim: the canonical-request layout; the UriEncode
# rules (unreserved set A-Za-z0-9 - . _ ~, space as %20 not '+',
# uppercase hex, '/' unencoded only as the object-key path separator);
# the canonical-query rule ("URI-encode each name and value individually.
# You must also sort the parameters in the canonical query string
# alphabetically by key name. The sorting occurs after encoding.");
# header canonicalisation (lowercase, alphabetical, trimmed, sequential
# spaces collapsed); the four-step signing-key derivation
# (DateKey -> DateRegionKey -> DateRegionServiceKey -> SigningKey); and
# the requirement that x-amz-security-token appear in CanonicalHeaders
# when using temporary credentials.
SIGV4_ALGORITHM_DOC_URL = (
    "https://docs.aws.amazon.com/IAM/latest/UserGuide/"
    "reference_sigv-create-signed-request.html")
SIGV4_ALGORITHM_DOC_SECTIONS = (
    "Create a canonical request",
    "Create a string to sign",
    "Derive a signing key",
    "Calculate the signature",
    "Signing requests with temporary security credentials",
)
SIGV4_ALGORITHM_DOC_CHECKED = "2026-08-16"
#
# ── SOURCE B: locally reproduced SigV4 fixtures ──────────────────────────
#
# LABEL (Codex MEDIUM 3, OPTION B): these are LOCALLY REPRODUCED SigV4
# fixtures based on the official AWS algorithm (SOURCE A). They are NOT
# claimed as "published AWS vectors", "official golden values" or "AWS
# fixed vectors" — the downloadable SigV4 test-suite bundle could not be
# retrieved from this environment (its pages are script-rendered), so no
# bundle URL and no bundle SHA-256 is pinned and none was invented.
#
# Each fixture's INPUTS are the well-known AWS example inputs; each
# fixture's expected OUTPUTS are what SOURCE A's algorithm produces, as
# computed by the independent implementation in this file. Their standing
# is exactly "reproduces under the official AWS algorithm", nothing
# stronger. A reviewer wanting upstream provenance should open the AWS
# pages named on each fixture and compare.
#
# A third fixture (the S3 "single chunk" GetObject worked example) was
# considered and DROPPED, twice: its recalled signature did not reproduce
# computationally and the page could not be retrieved to adjudicate. A
# fixture is never bent to fit our output — it is removed.
#
# If any literal below is ever shown to disagree with the official
# algorithm's output, fix the literal — never the signer.

# ── SOURCE C: Cloudflare R2 temporary-credential DERIVED FIXTURE ─────────
#
# LABEL: derived fixture from the official recipe.
# NOT a Cloudflare-published golden value — Cloudflare publishes the
# RECIPE, not these numbers. The values below were computed OUT OF BAND by
# a standalone script implementing that recipe directly, never by calling
# probe_r2_cas, so the probe is checked against digests it did not produce.
#
# The recipe (JWT claims bucket/scope/actions/paths, sub=account id,
# iss=parent access key id, aud=endpoint HOST, HS256 over the parent
# secret access key; derived secret = SHA-256 hex of the signed JWT
# string; session token = standard base64 of "jwt/" + JWT) is documented
# at:
#
# The probe additionally signs a `group` claim so that two matrix groups
# sharing a TTL cannot mint byte-identical tokens; that is a probe-side
# scoping decision, not a Cloudflare-published claim, and the fixture
# below was RECOMPUTED out of band for the new claim set rather than
# copied from the probe.
CLOUDFLARE_TEMP_CREDENTIAL_DOC_URLS = (
    "https://developers.cloudflare.com/r2/api/s3/temporary-credentials/",
    "https://developers.cloudflare.com/r2/examples/"
    "authenticate-r2-temp-credentials/",
)
CLOUDFLARE_TEMP_CREDENTIAL_DOC_SECTIONS = (
    "Generate locally (client-side signing)",
    "Scope of a credential",
)
CLOUDFLARE_TEMP_CREDENTIAL_DOC_CHECKED = "2026-08-14"
GOLDEN_CREDENTIAL_PROVENANCE = "derived fixture from official recipe"

GOLDEN_CREDENTIAL_INPUTS = {
    "account_id": "0" * 32,
    "parent_access_key_id": "3d1a2b4c5d6e7f8091a2b3c4d5e6f708",
    "parent_secret_access_key": "parent-secret-access-key-value-for-tests",
    "now": 1_786_000_000,
    "group": "T-CAS-1",   # 900s TTL
}
GOLDEN_DERIVED_SECRET = (
    "ed3e3acb4d6f1691fb5ae4bd9aae0ba53cc94b2b3940b7cc296e279dd4547370")
GOLDEN_SESSION_TOKEN_SHA256 = (
    "a43a1dbd500f7e41ebb8e835f39eaedf7fa09851f34ccea0eb55991020e0a5f3")


#: SOURCE B fixture 1 — locally reproduced signing-key derivation.
#: AWS page   : docs.aws.amazon.com/IAM/latest/UserGuide/
#:              reference_sigv-create-signed-request.html
#: Section    : "Derive a signing key" (well-known example inputs:
#:              secret/20120215/us-east-1/iam)
#: Status     : expected_key_hex is what SOURCE A's derivation produces for
#:              those inputs, computed independently in this file; NOT
#:              re-read from an AWS page this session.
AWS_SIGNING_KEY_VECTOR = {
    "secret": "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    "datestamp": "20120215",
    "region": "us-east-1",
    "service": "iam",
    "expected_key_hex":
        "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d",
}

#: SOURCE B fixture 2 — locally reproduced `get-vanilla` case.
#: AWS page   : docs.aws.amazon.com/general/latest/gr/
#:              signature-v4-test-suite.html  (bundle NOT retrievable from
#:              this environment; URL recorded, contents NOT pinned)
#: Inputs     : get-vanilla (AKIDEXAMPLE / 20150830 / us-east-1 / service)
#: Status     : expected_canonical_request and expected_signature are what
#:              SOURCE A's algorithm produces for those inputs, computed
#:              independently in this file. Not re-read from an AWS page
#:              this session; NOT claimed as a published/golden vector.
#
# The `expected_string_to_sign` literal is DERIVED, not recalled. Its
# fourth line is sha256(canonical_request); because the canonical request
# AND the final signature both reproduce under SOURCE A, and
# signature = HMAC(signing_key, string_to_sign), the string-to-sign our
# code builds is forced to equal the fixture's. An earlier hand-entered
# digest here was wrong and was REMOVED rather than reconciled — a fixture
# is never bent to fit our output. See
# test_aws_get_vanilla_string_to_sign_is_derived, which recomputes the
# fourth line instead of trusting the literal.
AWS_GET_VANILLA_VECTOR = {
    "method": "GET",
    "path": "/",
    "query_pairs": (),
    "headers": {
        "host": "example.amazonaws.com",
        "x-amz-date": "20150830T123600Z",
    },
    "payload": b"",
    "amz_date": "20150830T123600Z",
    "region": "us-east-1",
    "service": "service",
    "access_key_id": "AKIDEXAMPLE",
    "secret_access_key": "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    "expected_canonical_request": (
        "GET\n"
        "/\n"
        "\n"
        "host:example.amazonaws.com\n"
        "x-amz-date:20150830T123600Z\n"
        "\n"
        "host;x-amz-date\n"
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ),
    "expected_string_to_sign_head": (
        "AWS4-HMAC-SHA256\n"
        "20150830T123600Z\n"
        "20150830/us-east-1/service/aws4_request"
    ),
    "expected_string_to_sign": (
        "AWS4-HMAC-SHA256\n"
        "20150830T123600Z\n"
        "20150830/us-east-1/service/aws4_request\n"
        "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63"
    ),
    "expected_signature":
        "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
}
