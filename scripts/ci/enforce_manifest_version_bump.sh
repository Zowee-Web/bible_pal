#!/usr/bin/env bash
# =============================================================================
# Catalog Currency invariant — CI gate (docs/INVARIANTS.md)
# =============================================================================
#
# Compares assets/stories/manifest.json in the working tree against the SAME
# file at an explicitly supplied base revision, and enforces the catalog
# generation bump contract via scripts/check_manifest_version_bump.py.
#
# Both CI entry points share this script so the PR check and the
# protected-branch push/merge check can never drift apart:
#   - pull_request  -> base = github.event.pull_request.base.sha
#   - push          -> base = github.event.before (the ref's previous tip)
#
# The base revision is always supplied by the caller from trustworthy event
# context. This script never guesses HEAD^.
#
# Usage: scripts/ci/enforce_manifest_version_bump.sh <base-sha>
# =============================================================================

set -euo pipefail

MANIFEST_PATH="assets/stories/manifest.json"

BASE_SHA="${1:-}"
if [ -z "$BASE_SHA" ]; then
  echo "ERROR: base revision SHA is required" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Shallow CI clones usually lack the base commit. Fetching it is read-only
# and must succeed before the comparison can be trusted.
if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$BASE_SHA"
fi

WORK_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BASE_MANIFEST="$WORK_DIR/base_manifest.$$.json"
trap 'rm -f "$BASE_MANIFEST"' EXIT

if git cat-file -e "$BASE_SHA:$MANIFEST_PATH" 2>/dev/null; then
  git show "$BASE_SHA:$MANIFEST_PATH" > "$BASE_MANIFEST"
  python3 scripts/check_manifest_version_bump.py \
    --base "$BASE_MANIFEST" \
    --current "$MANIFEST_PATH"
else
  echo "Base revision $BASE_SHA has no $MANIFEST_PATH — treating as a new file."
  python3 scripts/check_manifest_version_bump.py \
    --no-base --current "$MANIFEST_PATH"
fi
