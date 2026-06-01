#!/bin/bash
# =============================================================================
# Bible PAL — Stage and (optionally) upload the remote catalog to R2
# =============================================================================
#
# Reads assets/stories/manifest.json, computes the next catalog version,
# stages a versioned copy under build/r2-staging/, and validates it against
# the same gates the app's CatalogService applies. Dry-run by default —
# pushes only when --push is given explicitly.
#
# Usage:
#   ./scripts/upload_r2_catalog.sh           # dry-run (default)
#   ./scripts/upload_r2_catalog.sh --push    # publish to R2 (live upload)
#   ./scripts/upload_r2_catalog.sh --help    # show help
#
# R2 object key: bible-pal-audio/catalog/v1/manifest.json
#
# Requires: wrangler CLI (auth required only in --push mode)
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

Dry-run by default. Stages $MANIFEST with a computed
"version" field into $STAGED_FILE, validates it
against the same gates the app's CatalogService applies, and prints the
wrangler command that would publish it.

Flags:
  --push     Upload the staged catalog to R2 (requires wrangler auth).
  --help     Show this help and exit.

R2 key: $BUCKET/$CATALOG_KEY
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

# ── Header ───────────────────────────────────────────────────────────────────

echo "================================================================"
echo "  Bible PAL R2 Catalog Upload"
echo "================================================================"
echo "  Mode:    $MODE"
echo "  Bucket:  $BUCKET"
echo "  Key:     $CATALOG_KEY"
echo "  Source:  $MANIFEST"
echo "================================================================"
echo ""

# ── [1/4] Read bundled manifest ──────────────────────────────────────────────

LOCAL_COUNT=$(python3 -c "
import json
with open('$MANIFEST') as f:
    m = json.load(f)
print(len(m.get('parables', [])))
")
LOCAL_VERSION=$(python3 -c "
import json
with open('$MANIFEST') as f:
    m = json.load(f)
v = m.get('version')
print(v if isinstance(v, int) else 0)
")

echo "[1/4] Reading bundled manifest:"
echo "  parables:       $LOCAL_COUNT"
echo "  local_version:  $LOCAL_VERSION"
echo ""

# ── [2/4] Compute next version ───────────────────────────────────────────────

echo "[2/4] Computing next version:"

REMOTE_VERSION=0
REMOTE_STATUS=""
REMOTE_TMP="$(mktemp)"
# Trap so the tmp file is always removed even if a later step exits.
trap 'rm -f "$REMOTE_TMP"' EXIT

# `wrangler r2 object get` writes the object body to the file given via
# --file. Any failure (404, network, auth) is tolerated: we fall back to
# remote_version=0 and print a warning. Push mode prints a stronger
# warning but still proceeds — the app's CatalogService will reject a
# non-monotonic version, so the worst case is a rejected upload, not
# silent corruption.
if wrangler r2 object get "$BUCKET/$CATALOG_KEY" --remote --file="$REMOTE_TMP" >/dev/null 2>&1; then
  REMOTE_VERSION=$(python3 -c "
import json
try:
    with open('$REMOTE_TMP') as f:
        m = json.load(f)
    v = m.get('version')
    print(v if isinstance(v, int) else 0)
except Exception:
    print(0)
")
  REMOTE_STATUS="$REMOTE_VERSION"
else
  if [ "$PUSH" = "1" ]; then
    REMOTE_STATUS="unreachable (treating as 0 — verify before pushing)"
  else
    REMOTE_STATUS="unknown (dry-run did not require auth; treating as 0)"
  fi
fi

NEXT_VERSION=$LOCAL_VERSION
if [ "$REMOTE_VERSION" -gt "$NEXT_VERSION" ]; then
  NEXT_VERSION=$REMOTE_VERSION
fi
NEXT_VERSION=$((NEXT_VERSION + 1))

echo "  local_version:  $LOCAL_VERSION"
echo "  remote_version: $REMOTE_STATUS"
echo "  next_version:   $NEXT_VERSION"
echo ""

# ── [3/4] Stage catalog ──────────────────────────────────────────────────────

echo "[3/4] Staging catalog:"
mkdir -p "$STAGING_DIR"

# Write the bundled manifest verbatim, overwriting (or adding) only the
# top-level "version" field. NEVER edit assets/stories/manifest.json.
python3 -c "
import json
with open('$MANIFEST') as f:
    m = json.load(f)
m['version'] = $NEXT_VERSION
with open('$STAGED_FILE', 'w') as f:
    json.dump(m, f, separators=(',', ':'))
"

STAGED_SIZE=$(wc -c < "$STAGED_FILE" | tr -d ' ')
STAGED_SIZE_HUMAN=$(du -h "$STAGED_FILE" | cut -f1 | tr -d ' ')
echo "  staged:  $STAGED_FILE"
echo "  size:    $STAGED_SIZE_HUMAN ($STAGED_SIZE bytes)"
echo ""

# ── [4/4] Validate staged catalog ────────────────────────────────────────────

echo "[4/4] Validating staged catalog:"

python3 - <<PYEOF
import json, os, sys

STAGED = "$STAGED_FILE"
MAX_SIZE = $MAX_SIZE_BYTES
MAX_ENTRIES = $MAX_ENTRIES

# Allowed translations — mirror of lib/core/bible_translation_registry.dart.
# That registry is the SINGLE SOURCE OF TRUTH; if it ever changes, update
# this set in the same commit.
ALLOWED = {"WEB", "KJV", "ASV", "YLT", "DRA"}

errors = []

try:
    with open(STAGED) as f:
        m = json.load(f)
except Exception as e:
    print(f"  FAIL json: parse failed -- {e}", file=sys.stderr)
    sys.exit(1)
print("  OK json: parseable")

if "parables" not in m or not isinstance(m["parables"], list):
    errors.append('schema: top-level "parables" missing or not a list')
else:
    print("  OK schema: parables list present")

v = m.get("version")
if not isinstance(v, int):
    errors.append(f"version: must be int, got {type(v).__name__}")
else:
    print(f"  OK version: integer ({v})")

n = len(m.get("parables", []))
if n > MAX_ENTRIES:
    errors.append(f"entry_count: {n} > {MAX_ENTRIES}")
else:
    print(f"  OK entry_count: {n} <= {MAX_ENTRIES}")

sz = os.path.getsize(STAGED)
if sz > MAX_SIZE:
    errors.append(f"size: {sz} > {MAX_SIZE}")
else:
    print(f"  OK size: {sz} bytes <= {MAX_SIZE} bytes")

banned_seen = set()
for p in m.get("parables", []):
    for key in ("translationId", "languageStyle"):
        val = p.get(key)
        if isinstance(val, str) and val.strip().upper() not in ALLOWED:
            banned_seen.add(val)
if banned_seen:
    errors.append(f"translations: banned/unknown ids found: {sorted(banned_seen)}")
else:
    print(f"  OK translations: all in {sorted(ALLOWED)}")

if errors:
    print("", file=sys.stderr)
    print("Validation failed:", file=sys.stderr)
    for e in errors:
        print(f"  FAIL {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo ""

# ── Final action ─────────────────────────────────────────────────────────────

if [ "$PUSH" = "1" ]; then
  echo "Uploading to R2:"
  echo "  wrangler r2 object put \"$BUCKET/$CATALOG_KEY\" \\"
  echo "    --file=\"$STAGED_FILE\" \\"
  echo "    --content-type=\"application/json\" \\"
  echo "    --remote"
  echo ""
  wrangler r2 object put "$BUCKET/$CATALOG_KEY" \
    --file="$STAGED_FILE" \
    --content-type="application/json" \
    --remote
  echo ""
  echo "Catalog v$NEXT_VERSION published to $BUCKET/$CATALOG_KEY"
else
  echo "Would push:"
  echo "  wrangler r2 object put \"$BUCKET/$CATALOG_KEY\" \\"
  echo "    --file=\"$STAGED_FILE\" \\"
  echo "    --content-type=\"application/json\" \\"
  echo "    --remote"
  echo ""
  echo "DRY RUN: no upload performed."
  echo "Re-run with --push to publish."
fi
