#!/usr/bin/env bash
# backfill_narrator_voice_key.sh
# One-time script to populate narratorVoiceKey for existing audio entries in manifest.json
#
# COMPATIBILITY: macOS bash 3.2+ and Linux bash 4+
#
# Usage:
#   ./server/tools/backfill_narrator_voice_key.sh [--dry-run]
#
# What it does:
#   - Reads assets/stories/manifest.json
#   - For each parable with audioFilePath but no narratorVoiceKey:
#     - Determines if it's a kid story based on storyId containing "_kid"
#     - Computes narratorVoiceKey using deterministic select_voice_for_story()
#     - Updates the manifest entry
#   - Writes updated manifest atomically (temp file + mv)
#
# Idempotent: Running twice makes no changes the second time.

set -euo pipefail

# Resolve script directory (works when run from any location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SERVER_DIR/.." && pwd)"
MANIFEST_FILE="$PROJECT_ROOT/assets/stories/manifest.json"

# Source voice_selector.sh for deterministic voice selection
source "$SERVER_DIR/voice_selector.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - narratorVoiceKey Backfill${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
fi
echo ""

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq is required${NC}" >&2; exit 1; }

# Check manifest exists
if [ ! -f "$MANIFEST_FILE" ]; then
    echo -e "${RED}❌ Error: Manifest not found at $MANIFEST_FILE${NC}"
    exit 1
fi

# Validate manifest is valid JSON
if ! jq '.' "$MANIFEST_FILE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Manifest is not valid JSON${NC}"
    exit 1
fi

# Count entries
total_count=$(jq '.parables | length' "$MANIFEST_FILE")
echo -e "Total parables in manifest: ${GREEN}$total_count${NC}"

# Find entries with audio but no narratorVoiceKey
# Using jq to get storyIds that need updating
needs_update=$(jq -r '.parables[] | select((.audioFilePath // "") != "" and ((.narratorVoiceKey // "") == "" or .narratorVoiceKey == null)) | .storyId' "$MANIFEST_FILE")

# Count entries that need updating
update_count=0
for story_id in $needs_update; do
    update_count=$((update_count + 1))
done

# Count entries that already have narratorVoiceKey
has_key_count=$(jq '[.parables[] | select((.narratorVoiceKey // "") != "")] | length' "$MANIFEST_FILE")

# Count entries without audio (text-only)
no_audio_count=$(jq '[.parables[] | select((.audioFilePath // "") == "")] | length' "$MANIFEST_FILE")

echo -e "Entries already with narratorVoiceKey: ${GREEN}$has_key_count${NC}"
echo -e "Entries without audio (text-only): ${YELLOW}$no_audio_count${NC}"
echo -e "Entries needing backfill: ${YELLOW}$update_count${NC}"
echo ""

if [ "$update_count" -eq 0 ]; then
    echo -e "${GREEN}✓ All audio entries already have narratorVoiceKey. Nothing to do.${NC}"
    exit 0
fi

# Process each entry that needs updating
echo -e "${BLUE}Processing entries...${NC}"

# Create a temporary file for the updated manifest
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Copy current manifest to temp
cp "$MANIFEST_FILE" "$TEMP_FILE"

updated_count=0
skipped_count=0

for story_id in $needs_update; do
    # Determine if this is a kid story
    # Convention: storyId contains "_kid" for kid-friendly stories
    is_kid="false"
    case "$story_id" in
        *_kid*) is_kid="true" ;;
    esac

    # Get deterministic voice key for this story
    voice_key=$(select_voice_for_story "$story_id" "$is_kid")

    if [ -z "$voice_key" ] || [ "$voice_key" = "null" ]; then
        echo -e "${RED}✗ Failed to get voice key for $story_id${NC}"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    # Validate voice key is in allowlist
    if ! validate_voice_key "$voice_key"; then
        echo -e "${RED}✗ Voice key $voice_key not in allowlist for $story_id${NC}"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} $story_id → $voice_key (kid=$is_kid)"
    else
        # Update the manifest entry using jq
        jq --arg id "$story_id" --arg key "$voice_key" \
            '(.parables[] | select(.storyId == $id)) |= . + {narratorVoiceKey: $key}' \
            "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"

        echo -e "  ${GREEN}✓${NC} $story_id → $voice_key (kid=$is_kid)"
    fi

    updated_count=$((updated_count + 1))
done

echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}DRY RUN COMPLETE - No changes made${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Would update: ${GREEN}$updated_count${NC} entries"
    echo -e "Would skip: ${RED}$skipped_count${NC} entries"
    echo ""
    echo -e "Run without --dry-run to apply changes."
else
    # Validate the updated manifest is valid JSON
    if ! jq '.' "$TEMP_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: Updated manifest is not valid JSON. Aborting.${NC}"
        exit 1
    fi

    # Atomically replace the manifest
    mv "$TEMP_FILE" "$MANIFEST_FILE"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Backfill complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Updated: ${GREEN}$updated_count${NC} entries"
    echo -e "Skipped: ${RED}$skipped_count${NC} entries"
    echo ""

    # Verify
    final_missing=$(jq '[.parables[] | select((.audioFilePath // "") != "" and ((.narratorVoiceKey // "") == "" or .narratorVoiceKey == null))] | length' "$MANIFEST_FILE")
    if [ "$final_missing" -eq 0 ]; then
        echo -e "${GREEN}✓ Verification passed: All audio entries now have narratorVoiceKey${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: $final_missing entries still missing narratorVoiceKey${NC}"
    fi
fi
