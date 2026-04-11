#!/bin/bash
# =============================================================================
# Bible PAL — Bulk upload manifest audio to Cloudflare R2
# =============================================================================
#
# Modes:
#   DRY_RUN=1      Preview first 5 uploads, no network calls
#   SMALL_BATCH=1   Upload only the first 5 files (live)
#   (default)       Upload all 644 files
#
# Usage:
#   DRY_RUN=1     ./scripts/upload_r2_audio.sh   # step 1: preview
#   SMALL_BATCH=1 ./scripts/upload_r2_audio.sh   # step 2: live test (5 files)
#                 ./scripts/upload_r2_audio.sh   # step 3: full upload
#
# Requires: wrangler CLI, authenticated (wrangler login)
# =============================================================================

set -euo pipefail

BUCKET="bible-pal-audio"
ASSETS_DIR="assets/stories"
MANIFEST="$ASSETS_DIR/manifest.json"

# Counters
UPLOADED=0
SKIPPED=0
MISSING=0
FAILED=0

# ── Preflight checks ────────────────────────────────────────────────────────

# 1. wrangler installed?
if ! command -v wrangler &>/dev/null; then
    echo "ERROR: wrangler CLI not found."
    echo "  Install:      npm install -g wrangler"
    echo "  Authenticate: wrangler login"
    exit 1
fi

# 2. wrangler authenticated? (list buckets as a test)
if [ "${DRY_RUN:-0}" != "1" ]; then
    if ! wrangler r2 bucket list 2>/dev/null | grep -q "$BUCKET"; then
        echo "ERROR: Cannot access R2 bucket '$BUCKET'."
        echo "  Possible causes:"
        echo "    - Not authenticated: run 'wrangler login'"
        echo "    - Bucket name wrong: expected '$BUCKET'"
        echo "    - Bucket doesn't exist in your Cloudflare account"
        echo ""
        echo "  Buckets found:"
        wrangler r2 bucket list 2>/dev/null || echo "    (none — auth likely failed)"
        exit 1
    fi
fi

# 3. Manifest exists?
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Manifest not found at $MANIFEST"
    exit 1
fi

# ── Extract audio paths from manifest ────────────────────────────────────────
# ONLY audioFilePath and reflectionAudioPath — both are always .mp3
# This ignores textFilePath, scriptureTextFilePath, and all other fields.

AUDIO_PATHS=$(python3 -c "
import json, sys
with open('$MANIFEST') as f:
    m = json.load(f)
paths = set()
for p in m.get('parables', []):
    for key in ('audioFilePath', 'reflectionAudioPath'):
        v = p.get(key, '')
        if v and v.endswith('.mp3'):
            paths.add(v)
        elif v:
            print(f'WARNING: non-mp3 path skipped: {v}', file=sys.stderr)
for p in sorted(paths):
    print(p)
")

TOTAL=$(echo "$AUDIO_PATHS" | wc -l | tr -d ' ')

# ── Determine mode ───────────────────────────────────────────────────────────

if [ "${DRY_RUN:-0}" = "1" ]; then
    MODE="DRY RUN (preview only, no uploads)"
    LIMIT=5
elif [ "${SMALL_BATCH:-0}" = "1" ]; then
    MODE="SMALL BATCH (first 5 files, live upload)"
    LIMIT=5
else
    MODE="FULL UPLOAD (all $TOTAL files)"
    LIMIT=$TOTAL
fi

# ── Header ───────────────────────────────────────────────────────────────────

echo "================================================================"
echo "  Bible PAL R2 Audio Upload"
echo "================================================================"
echo "  Mode:      $MODE"
echo "  Bucket:    $BUCKET"
echo "  Manifest:  $MANIFEST"
echo "  Total manifest audio files: $TOTAL"
echo "  Files this run: $LIMIT"
echo "================================================================"
echo ""

# ── Sample commands ──────────────────────────────────────────────────────────

# Find one traditional and one creative path for sample display
SAMPLE_TRAD=$(echo "$AUDIO_PATHS" | grep "^traditional/" | head -1)
SAMPLE_CREA=$(echo "$AUDIO_PATHS" | grep "^creative/" | head -1)

echo "Sample wrangler commands:"
echo ""
if [ -n "$SAMPLE_TRAD" ]; then
    echo "  Traditional:"
    echo "    wrangler r2 object put \"$BUCKET/$SAMPLE_TRAD\" \\"
    echo "      --file=\"$ASSETS_DIR/$SAMPLE_TRAD\" \\"
    echo "      --content-type=\"audio/mpeg\" --remote"
    echo ""
fi
if [ -n "$SAMPLE_CREA" ]; then
    echo "  Creative:"
    echo "    wrangler r2 object put \"$BUCKET/$SAMPLE_CREA\" \\"
    echo "      --file=\"$ASSETS_DIR/$SAMPLE_CREA\" \\"
    echo "      --content-type=\"audio/mpeg\" --remote"
    echo ""
fi
echo "----------------------------------------------------------------"
echo ""

# ── Upload loop ──────────────────────────────────────────────────────────────

COUNT=0
for rel_path in $AUDIO_PATHS; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -gt $LIMIT ]; then
        break
    fi

    local_file="$ASSETS_DIR/$rel_path"

    # Safety: only .mp3 files
    if [[ "$rel_path" != *.mp3 ]]; then
        echo "  [$COUNT/$LIMIT] SKIP (not .mp3): $rel_path"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Safety: must be under creative/ or traditional/
    if [[ "$rel_path" != creative/* && "$rel_path" != traditional/* ]]; then
        echo "  [$COUNT/$LIMIT] SKIP (unexpected prefix): $rel_path"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Check local file exists
    if [ ! -f "$local_file" ]; then
        echo "  [$COUNT/$LIMIT] MISSING: $rel_path"
        MISSING=$((MISSING + 1))
        continue
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        SIZE=$(du -h "$local_file" | cut -f1 | tr -d ' ')
        echo "  [$COUNT/$LIMIT] WOULD UPLOAD: $rel_path ($SIZE)"
        echo "    -> R2 key: $BUCKET/$rel_path"
        UPLOADED=$((UPLOADED + 1))
    else
        echo "  [$COUNT/$LIMIT] Uploading: $rel_path"
        if wrangler r2 object put "$BUCKET/$rel_path" --file="$local_file" --content-type="audio/mpeg" --remote 2>&1; then
            UPLOADED=$((UPLOADED + 1))
        else
            echo "  [$COUNT/$LIMIT] FAILED: $rel_path"
            FAILED=$((FAILED + 1))
        fi
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "  Would upload:  $UPLOADED"
else
    echo "  Uploaded:      $UPLOADED"
fi
echo "  Skipped:       $SKIPPED"
echo "  Missing local: $MISSING"
echo "  Failed:        $FAILED"
echo "  Remaining:     $((TOTAL - UPLOADED - SKIPPED - MISSING - FAILED))"
echo "================================================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
