#!/bin/bash
# =============================================================================
# Bible PAL — Stage and (optionally) upload the remote catalog to R2
# =============================================================================
#
# Publishes assets/stories/manifest.json VERBATIM as the remote catalog.
# The bundled manifest's own top-level "version" (the catalog generation)
# is authoritative — this script NEVER computes or rewrites a version.
#
# Catalog Currency invariant (docs/INVARIANTS.md):
#   - local version must be a positive integer (else: refuse)
#   - push requires localVersion > confirmedRemoteVersion (strict)
#   - a malformed/unreadable remote catalog BLOCKS the push
#   - equality is never an update; same version + different payload is a
#     version collision and is never published
#
# FAIL-CLOSED REMOTE CLASSIFICATION (non-negotiable):
# The remote catalog key is ESTABLISHED production state. This script
# therefore recognizes exactly three remote states — confirmed, corrupt,
# unknown — and NEVER infers "absent". A nonzero or indeterminate GET is
# UNKNOWN and blocks publication, full stop. Absence is deliberately NOT
# derivable from wrangler's stderr: strings like "not found", "no such",
# "404" and "does not exist" are emitted by transport failures, missing
# helper executables, auth errors and unrelated filesystem errors just as
# readily as by a genuinely missing object, so treating them as confirmed
# absence would let a failed read authorize a blind overwrite of a live,
# possibly NEWER, catalog. Bootstrapping a brand-new key is out of scope
# for this script (see docs/INVARIANTS.md — it requires an explicit,
# machine-verifiable absence probe that wrangler does not currently
# expose).
#
# OPERATIONAL RULE: ONE OWNER-CONTROLLED CATALOG PUBLISHER AT A TIME.
# The read → check → write sequence is NOT atomic: this script narrows the
# publish race with a pre-PUT recheck and a post-PUT verification, but it
# cannot eliminate it. Concurrent publishers can still interleave (v7 then
# v6). Monotonic remote publication is guaranteed ONLY by the operational
# single-publisher rule, never by this script alone.
#
# Usage:
#   ./scripts/upload_r2_catalog.sh           # dry-run (default)
#   ./scripts/upload_r2_catalog.sh --push    # publish to R2 (live upload)
#   ./scripts/upload_r2_catalog.sh --help    # show help
#
# R2 object key: bible-pal-audio/catalog/v1/manifest.json
#
# Requires: wrangler CLI (used read-only except in --push mode)
#           python3 (used for JSON parsing + validation)
# =============================================================================

set -euo pipefail
set +x  # explicit: never trace; we don't want command lines printed.

BUCKET="bible-pal-audio"
CATALOG_KEY="catalog/v1/manifest.json"
ASSETS_DIR="assets/stories"
MANIFEST="$ASSETS_DIR/manifest.json"
STAGING_DIR="build/r2-staging"
STAGED_FILE="$STAGING_DIR/catalog-pending.json"
MAX_SIZE_BYTES=$((5 * 1024 * 1024))
MAX_ENTRIES=5000

# Run from repo root regardless of where the user invoked us from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── Flag parsing ─────────────────────────────────────────────────────────────

print_usage() {
  cat <<EOF
Usage: $0 [--push|--help]

Dry-run by default. Snapshots $MANIFEST VERBATIM (its own
"version" field is the catalog generation — nothing is computed) into a
private per-run temp dir, copies it to $STAGED_FILE for
inspection, validates it against the same gates the app's CatalogService
applies, compares against the live remote catalog, and prints the
wrangler command that would publish it.

Flags:
  --push     Upload the staged catalog to R2 (requires wrangler auth).
  --help     Show this help and exit.

R2 key: $BUCKET/$CATALOG_KEY

FAIL CLOSED: the remote state is confirmed / corrupt / unknown. Absence is
never inferred from a failed read, and only a confirmed state can
authorize a push.

OPERATIONAL RULE: one owner-controlled catalog publisher at a time. The
read/check/write sequence is not atomic — concurrent publishers are not
prevented by this script.
EOF
}

PUSH=0
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=1 ;;
    --help|-h) print_usage; exit 0 ;;
    *)
      echo "ERROR: Unknown flag: $arg" >&2
      echo "" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# ── Preflight ────────────────────────────────────────────────────────────────

if ! command -v wrangler &>/dev/null; then
  echo "ERROR: wrangler CLI not found." >&2
  echo "  Install:      npm install -g wrangler" >&2
  echo "  Authenticate: wrangler login" >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found." >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: Bundled manifest not found at $MANIFEST" >&2
  exit 1
fi

if [ "$PUSH" = "1" ]; then
  MODE="PUSH (live upload to R2)"
  # Same auth check pattern as scripts/upload_r2_audio.sh.
  if ! wrangler r2 bucket list 2>/dev/null | grep -q "$BUCKET"; then
    echo "ERROR: Cannot access R2 bucket '$BUCKET'." >&2
    echo "  - Not authenticated? Run: wrangler login" >&2
    echo "  - Bucket name wrong? Expected: $BUCKET" >&2
    echo "  - Bucket missing? Check your Cloudflare account." >&2
    exit 1
  fi
else
  MODE="DRY RUN (validation only — no upload)"
fi

PUB_TMP="$(mktemp -d)"
trap 'rm -rf "$PUB_TMP"' EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────

# THE one validation path. Every catalog this script touches — local
# manifest, staged copy, observed remote, pre-PUT recheck, post-PUT
# verification — is judged by the SAME comprehensive validator, which
# mirrors the app's effective runtime acceptance (CatalogService gates +
# the full Parable.fromJson field contract). Local/staged/remote checks
# therefore cannot drift from one another.
VALIDATOR="scripts/validate_catalog_manifest.py"
if [ ! -f "$VALIDATOR" ]; then
  echo "ERROR: comprehensive validator not found at $VALIDATOR" >&2
  exit 1
fi
INSPECT_ERR_FILE="$PUB_TMP/inspect.err"

# inspect_catalog <file>
# Prints "VERSION ENTRY_COUNT SEMANTIC_SHA256" when the file passes the
# comprehensive validator; nonzero exit otherwise. Validator failure
# detail is written to $INSPECT_ERR_FILE for callers that relay it.
# The semantic SHA-256 hashes the canonical JSON (sorted object keys,
# compact separators, array order preserved), so formatting differences
# never change it while any content difference does.
inspect_catalog() {
  python3 "$VALIDATOR" "$1" \
    --max-bytes "$MAX_SIZE_BYTES" --max-entries "$MAX_ENTRIES" \
    2>"$INSPECT_ERR_FILE"
}

# fetch_remote_state <body_file> <err_file>
# Sets REMOTE_STATE (confirmed | corrupt | unknown), REMOTE_VERSION,
# REMOTE_COUNT, REMOTE_SHA, REMOTE_STATUS.
#
# FAIL CLOSED. There is deliberately NO "absent" outcome and stderr is
# NEVER consulted to classify state — it is only echoed (redacted) to help
# the operator diagnose an UNKNOWN. Confirmation requires ALL of:
#   1. the GET process exits 0, and
#   2. it actually wrote a non-empty object body to $body_file, and
#   3. those bytes pass the comprehensive catalog validator.
# Anything else is UNKNOWN (no evidence about the remote) or CORRUPT
# (bytes exist but are unusable). Both block --push.
fetch_remote_state() {
  local body_file="$1" err_file="$2"
  REMOTE_STATE="unknown"
  REMOTE_VERSION=0
  REMOTE_COUNT=0
  REMOTE_SHA=""
  REMOTE_STATUS="UNKNOWN (remote state not established) — PUSH BLOCKED"

  # A leftover body from an earlier call must never be mistaken for this
  # call's response.
  rm -f "$body_file"
  : > "$err_file"

  local fetch_exit=0
  wrangler r2 object get "$BUCKET/$CATALOG_KEY" --remote --file="$body_file" \
      >/dev/null 2>"$err_file" || fetch_exit=$?

  if [ "$fetch_exit" != "0" ]; then
    # Transport failure, missing helper, auth failure, network failure,
    # rate limit, genuinely-missing object — INDISTINGUISHABLE here, and
    # every one of them is treated as UNKNOWN.
    REMOTE_STATE="unknown"
    REMOTE_STATUS="UNKNOWN (remote GET exited $fetch_exit; absence is never inferred) — PUSH BLOCKED"
    return 0
  fi

  if [ ! -f "$body_file" ]; then
    REMOTE_STATE="unknown"
    REMOTE_STATUS="UNKNOWN (remote GET reported success but wrote no object body) — PUSH BLOCKED"
    return 0
  fi

  local body_bytes
  body_bytes=$(wc -c < "$body_file" | tr -d ' ')
  if [ "$body_bytes" -eq 0 ]; then
    REMOTE_STATE="unknown"
    REMOTE_STATUS="UNKNOWN (remote GET reported success but the object body is empty) — PUSH BLOCKED"
    return 0
  fi

  local out
  if out=$(inspect_catalog "$body_file"); then
    read -r REMOTE_VERSION REMOTE_COUNT REMOTE_SHA <<< "$out"
    REMOTE_STATE="confirmed"
    REMOTE_STATUS="v$REMOTE_VERSION, $REMOTE_COUNT entries (confirmed)"
  else
    # Object bytes exist but fail the comprehensive runtime-acceptance
    # validation (malformed JSON, invalid version, empty/invalid
    # parables, entries the app's Parable.fromJson would reject, …).
    # The true remote generation is unknowable and it must NOT supply
    # a version watermark → publishing would be blind.
    REMOTE_STATE="corrupt"
    REMOTE_STATUS="UNKNOWN/CORRUPT (object exists but fails catalog validation) — PUSH BLOCKED"
  fi
}

# raw_sha256 <file> — hash of the EXACT bytes on disk (not semantic).
raw_sha256() {
  python3 -c 'import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

print_redacted_stderr() {
  # Redact anything that looks like a long opaque token (>=20 chars of
  # base64-ish characters) so account IDs / request IDs don't appear in
  # shared logs. The user's own email and bucket names survive.
  sed -E 's/[A-Za-z0-9_-]{20,}/<redacted>/g; s/^/    /' "$1" >&2
}

# ── Header ───────────────────────────────────────────────────────────────────

echo "================================================================"
echo "  Bible PAL R2 Catalog Upload"
echo "================================================================"
echo "  Mode:    $MODE"
echo "  Bucket:  $BUCKET"
echo "  Key:     $CATALOG_KEY"
echo "  Source:  $MANIFEST (published verbatim)"
echo "  Rule:    ONE owner-controlled catalog publisher at a time"
echo "================================================================"
echo ""

# ── [1/5] Read + validate local manifest ─────────────────────────────────────

echo "[1/5] Reading bundled manifest:"

GIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=""
if ! git diff --quiet -- "$MANIFEST" 2>/dev/null; then
  GIT_DIRTY=" (manifest has UNCOMMITTED changes)"
fi

# IMMUTABLE PER-RUN SNAPSHOT. Everything downstream — validation, the
# monotonicity gate, the staged copy, the bytes actually PUT and the
# post-PUT comparison — is derived from this private snapshot inside the
# run's own 0700 temp dir, never re-read from the shared working tree.
# An edit to $MANIFEST (or to the world-writable staging dir) after this
# point can therefore never change what gets published.
SOURCE_SNAPSHOT="$PUB_TMP/source-snapshot.json"
cp "$MANIFEST" "$SOURCE_SNAPSHOT"
chmod 400 "$SOURCE_SNAPSHOT"

if ! LOCAL_OUT=$(inspect_catalog "$SOURCE_SNAPSHOT"); then
  echo "ERROR: refusing to stage $MANIFEST — it fails the comprehensive" >&2
  echo "catalog validation (the same contract the app enforces at runtime)." >&2
  echo "This script never invents or repairs a version. Details:" >&2
  sed 's/^/  /' "$INSPECT_ERR_FILE" >&2
  exit 1
fi
read -r LOCAL_VERSION LOCAL_COUNT LOCAL_SHA <<< "$LOCAL_OUT"
SOURCE_RAW_SHA=$(raw_sha256 "$SOURCE_SNAPSHOT")

echo "  git_commit:     $GIT_SHA$GIT_DIRTY"
echo "  local_version:  $LOCAL_VERSION (authoritative — published verbatim)"
echo "  parables:       $LOCAL_COUNT"
echo "  semantic_sha:   $LOCAL_SHA"
echo "  raw_sha256:     $SOURCE_RAW_SHA (snapshot bytes)"
echo ""

# ── [2/5] Read remote catalog state ──────────────────────────────────────────

echo "[2/5] Reading remote catalog state:"

REMOTE_BODY="$PUB_TMP/remote-observed.json"
REMOTE_ERR="$PUB_TMP/remote-observed.err"
fetch_remote_state "$REMOTE_BODY" "$REMOTE_ERR"
OBSERVED_STATE="$REMOTE_STATE"
OBSERVED_VERSION="$REMOTE_VERSION"
OBSERVED_COUNT="$REMOTE_COUNT"
OBSERVED_SHA="$REMOTE_SHA"

echo "  remote_state:   $REMOTE_STATUS"
echo ""

# ── [3/5] Monotonicity gate ──────────────────────────────────────────────────

echo "[3/5] Version monotonicity gate (strict: local > remote):"

case "$OBSERVED_STATE" in
  confirmed)
    if [ "$LOCAL_VERSION" -le "$OBSERVED_VERSION" ]; then
      echo "ERROR: local version $LOCAL_VERSION is not greater than the" >&2
      echo "confirmed remote version $OBSERVED_VERSION." >&2
      echo "" >&2
      if [ "$LOCAL_VERSION" -eq "$OBSERVED_VERSION" ]; then
        echo "Equal versions are NEVER an update. If the content differs this" >&2
        echo "is a version collision — bump the manifest version via the" >&2
        echo "normal PR flow and re-run." >&2
      else
        echo "Publishing would move the catalog generation backwards." >&2
      fi
      exit 1
    fi
    echo "  OK: $LOCAL_VERSION > $OBSERVED_VERSION"
    ;;
  corrupt)
    if [ "$PUSH" = "1" ]; then
      echo "ERROR: refusing to --push over an UNKNOWN/CORRUPT remote catalog." >&2
      echo "The object exists but could not be validated, so the true remote" >&2
      echo "generation is unknowable. Inspect it manually:" >&2
      echo "  wrangler r2 object get \"$BUCKET/$CATALOG_KEY\" --remote --file=remote.json" >&2
      exit 1
    fi
    echo "  BLOCKED for push (dry-run continues): remote is UNKNOWN/CORRUPT."
    ;;
  unknown)
    if [ "$PUSH" = "1" ]; then
      echo "ERROR: refusing to --push without a confirmed remote catalog state." >&2
      echo "" >&2
      echo "The remote read for $BUCKET/$CATALOG_KEY did not produce a validated" >&2
      echo "catalog, so this script cannot tell whether the catalog already" >&2
      echo "exists at some higher version or simply could not be read." >&2
      echo "" >&2
      echo "Absence is NEVER inferred: a failed read is not evidence that the" >&2
      echo "object is missing, and publishing on that assumption could silently" >&2
      echo "overwrite a NEWER live catalog. Fix the read, then re-run." >&2
      echo "" >&2
      echo "read diagnostics (token-like strings redacted):" >&2
      print_redacted_stderr "$REMOTE_ERR"
      echo "" >&2
      echo "Common fixes:" >&2
      echo "  - wrangler login            (auth)" >&2
      echo "  - wrangler r2 bucket list   (verify bucket access)" >&2
      echo "  - check network connectivity" >&2
      exit 1
    fi
    echo "  BLOCKED for push (dry-run continues): remote state is UNKNOWN."
    ;;
esac
echo ""

# ── [4/5] Stage catalog (verbatim) ───────────────────────────────────────────

echo "[4/5] Staging catalog verbatim:"
mkdir -p "$STAGING_DIR"

# Byte-verbatim copies of the immutable per-run snapshot. NEVER edit
# assets/stories/manifest.json here, and never rewrite "version".
#
#   $STAGED_FILE  — operator-visible artifact under build/. Informational
#                   ONLY: it lives in a shared, writable directory, so it
#                   is never the thing uploaded.
#   $UPLOAD_FILE  — the private per-run byte source for the PUT, inside
#                   this run's 0700 temp dir.
UPLOAD_FILE="$PUB_TMP/catalog-upload.json"
# `cp` gives a NEW destination the SOURCE's permission bits, and the
# snapshot is deliberately 0400. Copying it straight onto the shared
# staging path would leave a read-only artifact behind and every LATER
# run of this script would die with "Permission denied" — the operator
# copy is inspectable output, not an immutability guard. Remove any
# previous (possibly read-only) artifact first, then restore a normal
# mode. $UPLOAD_FILE needs no such care: it lives in this run's own
# 0700 temp dir and 0400 is exactly the guard we want there.
rm -f "$STAGED_FILE"
cp "$SOURCE_SNAPSHOT" "$STAGED_FILE"
chmod 644 "$STAGED_FILE"
cp "$SOURCE_SNAPSHOT" "$UPLOAD_FILE"
chmod 400 "$UPLOAD_FILE"

if ! cmp -s "$SOURCE_SNAPSHOT" "$STAGED_FILE" \
    || ! cmp -s "$SOURCE_SNAPSHOT" "$UPLOAD_FILE"; then
  echo "ERROR: staged copies are not byte-identical to the source snapshot" >&2
  exit 1
fi

STAGED_SIZE=$(wc -c < "$UPLOAD_FILE" | tr -d ' ')
STAGED_SIZE_HUMAN=$(du -h "$UPLOAD_FILE" | cut -f1 | tr -d ' ')
echo "  staged:  $STAGED_FILE (operator copy)"
echo "  upload:  private per-run snapshot (not the staging dir)"
echo "  size:    $STAGED_SIZE_HUMAN ($STAGED_SIZE bytes)"
echo ""

echo "  Validating staged catalog (comprehensive runtime contract):"

# Same single validation path as local/remote/post-PUT, run against the
# EXACT bytes that will be uploaded. Failure detail goes straight to
# stderr; the last stdout line is "VERSION COUNT SHA".
if ! STAGED_REPORT=$(python3 "$VALIDATOR" "$UPLOAD_FILE" \
    --max-bytes "$MAX_SIZE_BYTES" --max-entries "$MAX_ENTRIES" --report); then
  echo "ERROR: staged catalog failed validation — aborting." >&2
  exit 1
fi
echo "$STAGED_REPORT" | sed '$d'
read -r STAGED_VERSION STAGED_COUNT STAGED_SHA \
    <<< "$(echo "$STAGED_REPORT" | tail -1)"

if [ "$STAGED_SHA" != "$LOCAL_SHA" ] \
    || [ "$STAGED_VERSION" != "$LOCAL_VERSION" ] \
    || [ "$STAGED_COUNT" != "$LOCAL_COUNT" ]; then
  echo "ERROR: staged catalog does not match the local manifest." >&2
  exit 1
fi

echo ""

# ── [5/5] Publish report ─────────────────────────────────────────────────────

echo "[5/5] Publish report:"
echo "  git_commit:       $GIT_SHA$GIT_DIRTY"
echo "  local_version:    $LOCAL_VERSION"
echo "  remote_state:     $REMOTE_STATUS"
echo "  local_entries:    $LOCAL_COUNT"
if [ "$OBSERVED_STATE" = "confirmed" ]; then
  echo "  remote_entries:   $OBSERVED_COUNT"
  if [ "$LOCAL_COUNT" -gt "$OBSERVED_COUNT" ]; then
    echo "  entry_delta:      INCREASED by $((LOCAL_COUNT - OBSERVED_COUNT))"
  elif [ "$LOCAL_COUNT" -lt "$OBSERVED_COUNT" ]; then
    echo "  entry_delta:      DECREASED by $((OBSERVED_COUNT - LOCAL_COUNT)) — verify this is intentional!"
  else
    echo "  entry_delta:      unchanged"
  fi
else
  echo "  remote_entries:   n/a ($OBSERVED_STATE)"
fi
echo "  staged_sha256:    $STAGED_SHA (semantic)"
echo ""

# ── Final action ─────────────────────────────────────────────────────────────

if [ "$PUSH" = "1" ]; then
  echo "Pre-PUT recheck: re-fetching remote state (one publisher at a time!):"
  RECHECK_BODY="$PUB_TMP/remote-recheck.json"
  RECHECK_ERR="$PUB_TMP/remote-recheck.err"
  fetch_remote_state "$RECHECK_BODY" "$RECHECK_ERR"

  RECHECK_OK=1
  if [ "$REMOTE_STATE" != "$OBSERVED_STATE" ]; then
    RECHECK_OK=0
  elif [ "$REMOTE_STATE" = "confirmed" ]; then
    if [ "$REMOTE_VERSION" != "$OBSERVED_VERSION" ] || [ "$REMOTE_SHA" != "$OBSERVED_SHA" ]; then
      RECHECK_OK=0
    fi
  fi
  if [ "$RECHECK_OK" != "1" ]; then
    echo "ERROR: remote catalog state CHANGED between staging and push:" >&2
    echo "  observed:  $OBSERVED_STATE v$OBSERVED_VERSION sha=${OBSERVED_SHA:-n/a}" >&2
    echo "  recheck:   $REMOTE_STATE v$REMOTE_VERSION sha=${REMOTE_SHA:-n/a}" >&2
    echo "Another publisher may be active. STOPPING without uploading." >&2
    echo "Re-run this script from a clean state once you hold the publish lock." >&2
    exit 1
  fi
  echo "  OK: remote state unchanged since staging."
  echo ""

  # Immutable-bytes gate: re-validate and re-hash the EXACT file about to
  # be uploaded, immediately before the PUT. Nothing between this check
  # and the wrangler invocation reads the working tree or the shared
  # staging dir, so the bytes validated here are the bytes published.
  echo "Pre-PUT byte integrity check:"
  if ! PREPUT_OUT=$(inspect_catalog "$UPLOAD_FILE"); then
    echo "ERROR: the upload snapshot no longer passes catalog validation." >&2
    sed 's/^/  /' "$INSPECT_ERR_FILE" >&2
    exit 1
  fi
  read -r PREPUT_VERSION PREPUT_COUNT PREPUT_SHA <<< "$PREPUT_OUT"
  PREPUT_RAW_SHA=$(raw_sha256 "$UPLOAD_FILE")
  if [ "$PREPUT_VERSION" != "$LOCAL_VERSION" ] \
      || [ "$PREPUT_COUNT" != "$LOCAL_COUNT" ] \
      || [ "$PREPUT_SHA" != "$LOCAL_SHA" ] \
      || [ "$PREPUT_RAW_SHA" != "$SOURCE_RAW_SHA" ]; then
    echo "ERROR: upload snapshot changed after staging — refusing to PUT." >&2
    echo "  expected: v$LOCAL_VERSION, $LOCAL_COUNT entries, raw=$SOURCE_RAW_SHA" >&2
    echo "  actual:   v$PREPUT_VERSION, $PREPUT_COUNT entries, raw=$PREPUT_RAW_SHA" >&2
    exit 1
  fi
  echo "  OK: v$PREPUT_VERSION, $PREPUT_COUNT entries, raw sha256 $PREPUT_RAW_SHA"
  echo ""

  echo "Uploading to R2:"
  echo "  wrangler r2 object put \"$BUCKET/$CATALOG_KEY\" \\"
  echo "    --file=<private per-run snapshot> \\"
  echo "    --content-type=\"application/json; charset=utf-8\" \\"
  echo "    --remote"
  echo ""
  # charset=utf-8 is explicit: JSON is UTF-8 by RFC 8259, but an HTTP
  # client that trusts the header (package:http defaults to latin-1 when
  # no charset is given) would otherwise mojibake the 361 corpus entries
  # carrying non-ASCII text. CatalogService no longer trusts the header
  # either — belt and braces.
  wrangler r2 object put "$BUCKET/$CATALOG_KEY" \
    --file="$UPLOAD_FILE" \
    --content-type="application/json; charset=utf-8" \
    --remote
  echo ""

  # Proves the uploaded file was never swapped underneath the PUT.
  POSTPUT_RAW_SHA=$(raw_sha256 "$UPLOAD_FILE")
  if [ "$POSTPUT_RAW_SHA" != "$SOURCE_RAW_SHA" ]; then
    echo "ERROR: the upload snapshot changed during the PUT (raw sha256" >&2
    echo "$SOURCE_RAW_SHA -> $POSTPUT_RAW_SHA). Investigate immediately." >&2
    exit 1
  fi

  echo "Post-PUT verification (read-only):"
  VERIFY_BODY="$PUB_TMP/remote-verify.json"
  VERIFY_ERR="$PUB_TMP/remote-verify.err"
  fetch_remote_state "$VERIFY_BODY" "$VERIFY_ERR"
  if [ "$REMOTE_STATE" != "confirmed" ] \
      || [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ] \
      || [ "$REMOTE_COUNT" != "$LOCAL_COUNT" ] \
      || [ "$REMOTE_SHA" != "$STAGED_SHA" ]; then
    echo "ERROR: post-PUT verification FAILED:" >&2
    echo "  expected: confirmed v$LOCAL_VERSION, $LOCAL_COUNT entries, sha=$STAGED_SHA" >&2
    echo "  actual:   $REMOTE_STATE v$REMOTE_VERSION, $REMOTE_COUNT entries, sha=${REMOTE_SHA:-n/a}" >&2
    echo "The uploaded object does not match what was staged. Investigate" >&2
    echo "immediately — another publisher may have raced this upload." >&2
    exit 1
  fi
  echo "  OK: remote now serves v$REMOTE_VERSION, $REMOTE_COUNT entries,"
  echo "      semantic sha $REMOTE_SHA (matches staged)."
  echo ""
  echo "Catalog v$LOCAL_VERSION published to $BUCKET/$CATALOG_KEY"
else
  echo "Would push:"
  echo "  wrangler r2 object put \"$BUCKET/$CATALOG_KEY\" \\"
  echo "    --file=<private per-run snapshot> \\"
  echo "    --content-type=\"application/json; charset=utf-8\" \\"
  echo "    --remote"
  echo ""
  echo "Immediately before the PUT, --push re-fetches the remote state and"
  echo "STOPS if it no longer matches what was observed above, then"
  echo "re-validates and re-hashes the exact bytes it is about to upload."
  echo ""
  echo "DRY RUN: no upload performed."
  echo "Re-run with --push to publish."
fi
