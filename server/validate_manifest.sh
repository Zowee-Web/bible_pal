#!/bin/bash
# validate_manifest.sh
# Validates that manifest.json matches actual story files on disk
# Checks word counts, audio file existence, and length calibration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$PROJECT_ROOT/assets/stories/manifest.json"
STORIES_DIR="$PROJECT_ROOT/assets/stories"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Word count targets (narrated audio ~130-150 wpm)
declare -A MIN_WORDS=(
    [5]=600
    [10]=1200
    [15]=1800
    [20]=2400
)

declare -A MAX_WORDS=(
    [5]=750
    [10]=1500
    [15]=2250
    [20]=3000
)

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq required${NC}" >&2; exit 1; }

# Check manifest exists
if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo -e "${RED}❌ Error: manifest.json not found${NC}" >&2
    exit 1
fi

# Validate JSON syntax
if ! jq '.' "$MANIFEST_FILE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: manifest.json has invalid JSON syntax${NC}" >&2
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Manifest Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Count total stories
TOTAL_STORIES=$(jq '.parables | length' "$MANIFEST_FILE")
echo -e "Total stories in manifest: ${BLUE}$TOTAL_STORIES${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Validate each story
for i in $(seq 0 $((TOTAL_STORIES - 1))); do
    STORY=$(jq ".parables[$i]" "$MANIFEST_FILE")
    STORY_ID=$(echo "$STORY" | jq -r '.storyId')
    LENGTH=$(echo "$STORY" | jq -r '.length')
    TEXT_FILE=$(echo "$STORY" | jq -r '.textFilePath')
    AUDIO_FILE=$(echo "$STORY" | jq -r '.audioFilePath')

    echo -e "${BLUE}[$((i + 1))/$TOTAL_STORIES] $STORY_ID${NC}"

    # Check text file exists
    if [[ ! -f "$STORIES_DIR/$TEXT_FILE" ]]; then
        echo -e "  ${RED}✗ Text file missing: $TEXT_FILE${NC}"
        ((ERRORS++))
    else
        # Validate word count
        WORD_COUNT=$(wc -w < "$STORIES_DIR/$TEXT_FILE" | tr -d ' ')
        MIN=${MIN_WORDS[$LENGTH]:-600}
        MAX=${MAX_WORDS[$LENGTH]:-750}

        if (( WORD_COUNT < MIN || WORD_COUNT > MAX )); then
            echo -e "  ${RED}✗ Word count out of range: $WORD_COUNT (expected: $MIN-$MAX for ${LENGTH}min)${NC}"
            ((ERRORS++))
        else
            echo -e "  ${GREEN}✓ Word count: $WORD_COUNT${NC}"
        fi
    fi

    # Check audio file
    if [[ "$AUDIO_FILE" == "null" ]]; then
        echo -e "  ${YELLOW}⚠ No audio file (text-only story)${NC}"
        ((WARNINGS++))
    elif [[ ! -f "$STORIES_DIR/$AUDIO_FILE" ]]; then
        echo -e "  ${RED}✗ Audio file missing: $AUDIO_FILE${NC}"
        ((ERRORS++))
    else
        FILE_SIZE=$(ls -lh "$STORIES_DIR/$AUDIO_FILE" | awk '{print $5}')
        echo -e "  ${GREEN}✓ Audio file: $FILE_SIZE${NC}"
    fi

    echo ""
done

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ Validation passed!${NC}"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Warnings: $WARNINGS${NC}"
    fi
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s)${NC}"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Warnings: $WARNINGS${NC}"
    fi
    exit 1
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
