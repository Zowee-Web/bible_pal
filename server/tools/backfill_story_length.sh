#!/bin/bash
# backfill_story_length.sh
# Adds storyLength field to manifest.json entries based on word count
#
# LOCKED SPEC word count thresholds:
# - short: <= 600 words
# - full: 601-1200 words
# - long: 1201-2000 words
#
# Usage: ./backfill_story_length.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Overridable so tests can run against a fixture tree instead of the corpus.
MANIFEST_FILE="${MANIFEST_FILE_OVERRIDE:-$PROJECT_ROOT/assets/stories/manifest.json}"
STORIES_DIR="${STORIES_DIR_OVERRIDE:-$PROJECT_ROOT/assets/stories}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - no changes will be made${NC}"
    echo ""
fi

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq required${NC}" >&2; exit 1; }

# Check manifest exists
if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo -e "${RED}Error: manifest.json not found at $MANIFEST_FILE${NC}" >&2
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Story Length Backfill Tool${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "LOCKED SPEC thresholds:"
echo -e "  short: <= 600 words"
echo -e "  full:  601-1200 words"
echo -e "  long:  1201-2000 words"
echo ""

# Function to compute storyLength from word count
compute_story_length() {
    local word_count=$1
    if (( word_count <= 600 )); then
        echo "short"
    elif (( word_count <= 1200 )); then
        echo "full"
    else
        echo "long"
    fi
}

# Count stories
TOTAL_STORIES=$(jq '.parables | length' "$MANIFEST_FILE")
echo -e "Total stories in manifest: ${BLUE}$TOTAL_STORIES${NC}"
echo ""

# Track statistics
UPDATED=0
SKIPPED=0
ERRORS=0
MISSING_TEXT=0

# Create temp file for new manifest
TEMP_MANIFEST=$(mktemp)
trap "rm -f $TEMP_MANIFEST" EXIT

# Build the updated entries as a bare JSON array. The final merge replaces
# ONLY .parables in the original manifest, so top-level root metadata (the
# catalog "version" field etc.) is preserved — never reconstructed.
echo '[' > "$TEMP_MANIFEST"

# Process each story
for i in $(seq 0 $((TOTAL_STORIES - 1))); do
    STORY=$(jq ".parables[$i]" "$MANIFEST_FILE")
    STORY_ID=$(echo "$STORY" | jq -r '.storyId')
    TEXT_FILE=$(echo "$STORY" | jq -r '.textFilePath')
    EXISTING_LENGTH=$(echo "$STORY" | jq -r '.storyLength // empty')

    # Check if storyLength already exists
    if [[ -n "$EXISTING_LENGTH" ]]; then
        echo -e "[$((i + 1))/$TOTAL_STORIES] ${YELLOW}SKIP${NC} $STORY_ID (already has storyLength: $EXISTING_LENGTH)"
        SKIPPED=$((SKIPPED + 1))

        # Add comma for all but first entry
        if [[ $i -gt 0 ]]; then
            echo "," >> "$TEMP_MANIFEST"
        fi
        echo "$STORY" >> "$TEMP_MANIFEST"
        continue
    fi

    # Check if text file exists
    FULL_TEXT_PATH="$STORIES_DIR/$TEXT_FILE"
    if [[ ! -f "$FULL_TEXT_PATH" ]]; then
        echo -e "[$((i + 1))/$TOTAL_STORIES] ${RED}ERROR${NC} $STORY_ID - text file missing: $TEXT_FILE"
        MISSING_TEXT=$((MISSING_TEXT + 1))
        ERRORS=$((ERRORS + 1))

        # Keep story as-is (will fail validation later)
        if [[ $i -gt 0 ]]; then
            echo "," >> "$TEMP_MANIFEST"
        fi
        echo "$STORY" >> "$TEMP_MANIFEST"
        continue
    fi

    # Count words in text file
    WORD_COUNT=$(wc -w < "$FULL_TEXT_PATH" | tr -d ' ')
    STORY_LENGTH=$(compute_story_length "$WORD_COUNT")

    echo -e "[$((i + 1))/$TOTAL_STORIES] ${GREEN}UPDATE${NC} $STORY_ID: $WORD_COUNT words -> $STORY_LENGTH"
    UPDATED=$((UPDATED + 1))

    # Add storyLength field to story JSON
    UPDATED_STORY=$(echo "$STORY" | jq --arg sl "$STORY_LENGTH" '. + {storyLength: $sl}')

    # Add comma for all but first entry
    if [[ $i -gt 0 ]]; then
        echo "," >> "$TEMP_MANIFEST"
    fi
    echo "$UPDATED_STORY" >> "$TEMP_MANIFEST"
done

# Close the JSON array
echo ']'  >> "$TEMP_MANIFEST"

# Merge the rebuilt parables into the ORIGINAL manifest object so every
# other top-level key (catalog "version" etc.) survives the rewrite.
FORMATTED_MANIFEST=$(jq --slurpfile newp "$TEMP_MANIFEST" '.parables = $newp[0]' "$MANIFEST_FILE")

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "Summary:"
echo -e "  Updated:     ${GREEN}$UPDATED${NC}"
echo -e "  Skipped:     ${YELLOW}$SKIPPED${NC}"
echo -e "  Errors:      ${RED}$ERRORS${NC}"
if [[ $MISSING_TEXT -gt 0 ]]; then
    echo -e "  Missing text: ${RED}$MISSING_TEXT${NC}"
fi
echo ""

if [[ $DRY_RUN == true ]]; then
    echo -e "${YELLOW}DRY RUN - no changes made${NC}"
    echo -e "Run without --dry-run to apply changes"
elif [[ $ERRORS -gt 0 ]]; then
    # NEVER mutate the manifest after a processing error. A partially
    # understood corpus produces a partially correct manifest, and the
    # previous behaviour wrote it anyway before exiting nonzero — leaving
    # the catalog silently mutated by a run the operator was told failed.
    echo -e "${RED}ERRORS DETECTED ($ERRORS) - manifest left UNCHANGED${NC}" >&2
    echo -e "Fix the reported problems and re-run." >&2
else
    # Atomic, validated replacement. The temp file lives in the manifest's
    # OWN directory so the final rename is a same-filesystem atomic swap:
    # a reader either sees the whole old manifest or the whole new one,
    # never a truncated file.
    MANIFEST_DIR="$(cd "$(dirname "$MANIFEST_FILE")" && pwd)"
    STAGED_MANIFEST=$(mktemp "$MANIFEST_DIR/.$(basename "$MANIFEST_FILE").staged.XXXXXX")
    # shellcheck disable=SC2064 — expand STAGED_MANIFEST now, not at exit.
    trap "rm -f '$TEMP_MANIFEST' '$STAGED_MANIFEST'" EXIT

    printf '%s\n' "$FORMATTED_MANIFEST" > "$STAGED_MANIFEST"

    # Validate the staged bytes BEFORE they can replace anything.
    if ! jq empty "$STAGED_MANIFEST" 2>/dev/null; then
        echo -e "${RED}ERROR: staged manifest is not valid JSON - aborting${NC}" >&2
        exit 1
    fi
    STAGED_COUNT=$(jq '.parables | length' "$STAGED_MANIFEST")
    if [[ "$STAGED_COUNT" != "$TOTAL_STORIES" ]]; then
        echo -e "${RED}ERROR: staged manifest has $STAGED_COUNT entries, expected $TOTAL_STORIES - aborting${NC}" >&2
        exit 1
    fi
    # Every top-level key of the original must survive (catalog "version"
    # and any future root metadata).
    ORIGINAL_KEYS=$(jq -S 'keys' "$MANIFEST_FILE")
    STAGED_KEYS=$(jq -S 'keys' "$STAGED_MANIFEST")
    if [[ "$ORIGINAL_KEYS" != "$STAGED_KEYS" ]]; then
        echo -e "${RED}ERROR: staged manifest root keys differ from the original - aborting${NC}" >&2
        exit 1
    fi

    # FULL semantic validation, not just structure. The structural checks
    # above cannot see a duplicate storyId, an unsafe asset path, a
    # non-canonical languageStyle or an invalid catalog generation — all
    # of which the app and the publisher would reject. Validating the
    # EXACT staged bytes before any backup or rename means a manifest that
    # would poison the catalog never reaches disk.
    VALIDATOR="$PROJECT_ROOT/scripts/validate_catalog_manifest.py"
    if [[ ! -f "$VALIDATOR" ]]; then
        echo -e "${RED}ERROR: catalog validator not found at $VALIDATOR - aborting${NC}" >&2
        exit 1
    fi
    echo -e "Validating staged manifest against the active catalog contract..."
    if ! python3 "$VALIDATOR" "$STAGED_MANIFEST" >/dev/null; then
        echo -e "${RED}ERROR: staged manifest FAILS catalog validation - aborting${NC}" >&2
        echo -e "The original manifest is unchanged and no backup was written." >&2
        exit 1
    fi

    # mktemp creates 0600; carry the manifest's own mode across the swap.
    # BSD stat uses -f for the format string, GNU stat uses -c and treats
    # -f as --file-system (which exits 0 with unrelated output), so the
    # BSD result is validated as octal before it is trusted.
    ORIGINAL_MODE=$(stat -f "%OLp" "$MANIFEST_FILE" 2>/dev/null || true)
    case "$ORIGINAL_MODE" in
        [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
        *) ORIGINAL_MODE=$(stat -c "%a" "$MANIFEST_FILE" 2>/dev/null \
               || echo 644) ;;
    esac
    chmod "$ORIGINAL_MODE" "$STAGED_MANIFEST"

    # Backup original only once the replacement is known-good.
    cp "$MANIFEST_FILE" "${MANIFEST_FILE}.bak"
    echo -e "Backup saved to: ${BLUE}manifest.json.bak${NC}"

    mv "$STAGED_MANIFEST" "$MANIFEST_FILE"
    echo -e "${GREEN}Manifest updated successfully!${NC}"
fi

echo -e "${BLUE}================================================${NC}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
