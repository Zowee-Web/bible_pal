#!/bin/bash
# =============================================================================
# Bible PAL — Bulk upload manifest audio to Cloudflare R2
# =============================================================================
#
# Modes:
#   DRY_RUN=1       Audit every manifest path against R2 in parallel.
#                   Reports would-upload / would-skip (already-on-R2) /
#                   missing-locally / failed counts + sample paths.
#                   No writes, no wrangler auth required.
#   SMALL_BATCH=1   Upload only the first 5 files (live)
#   (default)       Upload every manifest audio path (live)
#
# Usage:
#   DRY_RUN=1     ./scripts/upload_r2_audio.sh   # step 1: audit
#   SMALL_BATCH=1 ./scripts/upload_r2_audio.sh   # step 2: live test (5 files)
#                 ./scripts/upload_r2_audio.sh   # step 3: full upload
#
# Requires: wrangler CLI, authenticated (wrangler login) — for live modes only.
#           Dry-run uses curl HEAD against the public R2 dev URL, no auth.
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
# Dry-run uses curl HEAD against the public R2 dev URL — no wrangler auth needed.
if [ "${DRY_RUN:-0}" != "1" ]; then
    # SIGPIPE guard: `grep -q` closes pipe early, which kills wrangler with
    # SIGPIPE and fails the pipeline under `set -o pipefail`.
    set +o pipefail
    bucket_list_output=$(wrangler r2 bucket list 2>/dev/null)
    set -o pipefail
    if ! echo "$bucket_list_output" | grep -q "$BUCKET"; then
        echo "ERROR: Cannot access R2 bucket '$BUCKET'."
        echo "  Possible causes:"
        echo "    - Not authenticated: run 'wrangler login'"
        echo "    - Bucket name wrong: expected '$BUCKET'"
        echo "    - Bucket doesn't exist in your Cloudflare account"
        echo ""
        echo "  Buckets found:"
        echo "${bucket_list_output:-    (none — auth likely failed)}"
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
    MODE="DRY RUN (audit all $TOTAL paths, no uploads, no auth required)"
    LIMIT=$TOTAL
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

# Find one traditional and one creative path for sample display.
# SIGPIPE guard: `head -1` closes the pipe after one line, which kills
# the upstream `grep` with SIGPIPE and fails the pipeline under
# `set -o pipefail`. That's what was causing exit 141 right after the
# header banner. Awk's `exit` reads-then-stops in a single process so
# there's no inter-process pipe to close prematurely.
SAMPLE_TRAD=$(printf '%s\n' "$AUDIO_PATHS" | awk '/^traditional\// { print; exit }')
SAMPLE_CREA=$(printf '%s\n' "$AUDIO_PATHS" | awk '/^creative\// { print; exit }')

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

# ── Dry-run: full R2 audit + classified report ──────────────────────────────
# Reads AUDIO_BASE_URL from .env (single source of truth shared with the
# Flutter dotenv loader). Probes every path in parallel against the public
# R2 dev URL. No wrangler auth required.
if [ "${DRY_RUN:-0}" = "1" ]; then
    R2_BASE=$(grep '^AUDIO_BASE_URL=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    if [ -z "$R2_BASE" ]; then
        echo "ERROR: AUDIO_BASE_URL not found in .env — required for R2 audit."
        exit 1
    fi
    echo "  Auditing $TOTAL paths against $R2_BASE ..."
    echo ""

    AUDIO_PATHS="$AUDIO_PATHS" R2_BASE="$R2_BASE" ASSETS_DIR="$ASSETS_DIR" python3 - <<'PYEOF'
import os, subprocess, sys, time, random
from concurrent.futures import ThreadPoolExecutor

R2_BASE = os.environ["R2_BASE"]
ASSETS_DIR = os.environ["ASSETS_DIR"]
paths = [p for p in os.environ["AUDIO_PATHS"].strip().split("\n") if p]

# Cloudflare's public *.r2.dev URLs are subject to per-source-IP rate
# limits. 8 workers + exponential backoff on 429 keeps us safely
# under the threshold while still finishing ~1000 probes in <2 min.
MAX_WORKERS = 8
MAX_RETRIES = 4

def probe_once(url):
    r = subprocess.run(
        ["curl", "-sI", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "10", url],
        capture_output=True, text=True,
    )
    return r.stdout.strip()

def classify(rel_path):
    local_file = os.path.join(ASSETS_DIR, rel_path)
    local_ok = os.path.isfile(local_file)
    url = f"{R2_BASE}/{rel_path}"
    code = ""
    for attempt in range(MAX_RETRIES):
        code = probe_once(url)
        if code != "429":
            break
        # Exponential backoff with jitter — 0.5s, 1s, 2s, 4s (plus 0-250ms)
        time.sleep((0.5 * (2 ** attempt)) + random.uniform(0, 0.25))
    if code == "200":
        status = "on_r2"
    elif code == "404":
        status = "absent"
    else:
        status = "error"
    return rel_path, local_ok, status, code

with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
    results = list(pool.map(classify, paths))

would_skip   = [r for r in results if r[2] == "on_r2"]
would_upload = [r for r in results if r[2] == "absent" and r[1]]
missing      = [r for r in results if r[2] == "absent" and not r[1]]
failed       = [r for r in results if r[2] == "error"]

print("  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("    Dry-run R2 audit summary")
print("  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"    Would upload (local present, R2 missing):   {len(would_upload):>5}")
print(f"    Would skip   (already on R2):               {len(would_skip):>5}")
print(f"    Missing      (local absent, cannot upload): {len(missing):>5}")
print(f"    Failed       (probe error, non-200/non-404):{len(failed):>5}")
print(f"    Total manifest audio paths:                 {len(results):>5}")
print("  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

def show(label, rows, max_n=5):
    if not rows:
        return
    print()
    print(f"  Sample {label} (first {min(max_n, len(rows))} of {len(rows)}):")
    for r in rows[:max_n]:
        suffix = ""
        if r[3] not in ("200", "404"):
            suffix = f"  [http={r[3]}]"
        print(f"    - {r[0]}{suffix}")

show("WOULD-UPLOAD paths", would_upload)
show("WOULD-SKIP paths (already on R2)", would_skip)
show("MISSING-LOCAL paths", missing)
show("FAILED probes", failed)

# Exit non-zero only if there are real misses to investigate (probe errors).
# Missing-local and absent-from-R2 are informational, not failures.
sys.exit(1 if failed else 0)
PYEOF
    exit $?
fi

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

    # Live upload — dry-run exits earlier via the R2 audit block above.
    echo "  [$COUNT/$LIMIT] Uploading: $rel_path"
    if wrangler r2 object put "$BUCKET/$rel_path" --file="$local_file" --content-type="audio/mpeg" --remote 2>&1; then
        UPLOADED=$((UPLOADED + 1))
    else
        echo "  [$COUNT/$LIMIT] FAILED: $rel_path"
        FAILED=$((FAILED + 1))
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo "  Uploaded:      $UPLOADED"
echo "  Skipped:       $SKIPPED"
echo "  Missing local: $MISSING"
echo "  Failed:        $FAILED"
echo "  Remaining:     $((TOTAL - UPLOADED - SKIPPED - MISSING - FAILED))"
echo "================================================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
