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
MANIFEST_FILE="$PROJECT_ROOT/assets/stories/manifest.json"
STORIES_DIR="$PROJECT_ROOT/assets/stories"

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

# Start with the opening brace
echo '{"parables":[' > "$TEMP_MANIFEST"

# Process each story
for i in $(seq 0 $((TOTAL_STORIES - 1))); do
    STORY=$(jq ".parables[$i]" "$MANIFEST_FILE")
    STORY_ID=$(echo "$STORY" | jq -r '.storyId')
    TEXT_FILE=$(echo "$STORY" | jq -r '.textFilePath')
    EXISTING_LENGTH=$(echo "$STORY" | jq -r '.storyLength // empty')

    # Check if storyLength already exists
    if [[ -n "$EXISTING_LENGTH" ]]; then
        echo -e "[$((i + 1))/$TOTAL_STORIES] ${YELLOW}SKIP${NC} $STORY_ID (already has storyLength: $EXISTING_LENGTH)"
        ((SKIPPED++))

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
        ((MISSING_TEXT++))
        ((ERRORS++))

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
    ((UPDATED++))

    # Add storyLength field to story JSON
    UPDATED_STORY=$(echo "$STORY" | jq --arg sl "$STORY_LENGTH" '. + {storyLength: $sl}')

    # Add comma for all but first entry
    if [[ $i -gt 0 ]]; then
        echo "," >> "$TEMP_MANIFEST"
    fi
    echo "$UPDATED_STORY" >> "$TEMP_MANIFEST"
done

# Close the JSON
echo ']}'  >> "$TEMP_MANIFEST"

# Format the JSON properly
FORMATTED_MANIFEST=$(jq '.' "$TEMP_MANIFEST")

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
else
    # Backup original
    cp "$MANIFEST_FILE" "${MANIFEST_FILE}.bak"
    echo -e "Backup saved to: ${BLUE}manifest.json.bak${NC}"

    # Write new manifest
    echo "$FORMATTED_MANIFEST" > "$MANIFEST_FILE"
    echo -e "${GREEN}Manifest updated successfully!${NC}"
fi

echo -e "${BLUE}================================================${NC}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
