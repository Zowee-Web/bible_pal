#!/bin/bash
# validate_manifest.sh
# Validates that manifest.json matches actual story files on disk
# Checks storyLength field, word counts, and audio file existence
#
# LOCKED SPEC: storyLength is REQUIRED and must be one of: short, full, long
# Word count thresholds:
#   short: 250-600 words
#   full:  601-1200 words
#   long:  1201-2000 words

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

# LOCKED SPEC: storyLength word count ranges (bash 3.2 compatible)
get_min_words_bucket() {
    case "$1" in
        short) echo 250 ;; full) echo 601 ;; long) echo 1201 ;; *) echo 250 ;;
    esac
}
get_max_words_bucket() {
    case "$1" in
        short) echo 600 ;; full) echo 1200 ;; long) echo 2000 ;; *) echo 600 ;;
    esac
}

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
    STORY_LENGTH=$(echo "$STORY" | jq -r '.storyLength // empty')
    TEXT_FILE=$(echo "$STORY" | jq -r '.textFilePath')
    AUDIO_FILE=$(echo "$STORY" | jq -r '.audioFilePath')

    echo -e "${BLUE}[$((i + 1))/$TOTAL_STORIES] $STORY_ID${NC}"

    # CRITICAL: Validate storyLength field exists and is valid
    if [[ -z "$STORY_LENGTH" ]]; then
        echo -e "  ${RED}✗ MISSING storyLength field (REQUIRED)${NC}"
        ((ERRORS++))
    elif [[ "$STORY_LENGTH" != "short" && "$STORY_LENGTH" != "full" && "$STORY_LENGTH" != "long" ]]; then
        echo -e "  ${RED}✗ INVALID storyLength: '$STORY_LENGTH' (must be: short, full, or long)${NC}"
        ((ERRORS++))
    else
        echo -e "  ${GREEN}✓ storyLength: $STORY_LENGTH${NC}"
    fi

    # Check text file exists
    if [[ "$TEXT_FILE" == "null" ]]; then
        echo -e "  ${YELLOW}⚠ No text file path${NC}"
        ((WARNINGS++))
    elif [[ ! -f "$STORIES_DIR/$TEXT_FILE" ]]; then
        echo -e "  ${RED}✗ Text file missing: $TEXT_FILE${NC}"
        ((ERRORS++))
    else
        # Validate word count against storyLength bucket
        WORD_COUNT=$(wc -w < "$STORIES_DIR/$TEXT_FILE" | tr -d ' ')

        if [[ -n "$STORY_LENGTH" && "$STORY_LENGTH" =~ ^(short|full|long)$ ]]; then
            MIN=$(get_min_words_bucket "$STORY_LENGTH")
            MAX=$(get_max_words_bucket "$STORY_LENGTH")

            if (( WORD_COUNT < MIN || WORD_COUNT > MAX )); then
                echo -e "  ${YELLOW}⚠ Word count mismatch: $WORD_COUNT words (storyLength=$STORY_LENGTH expects $MIN-$MAX)${NC}"
                ((WARNINGS++))
            else
                echo -e "  ${GREEN}✓ Word count: $WORD_COUNT (valid for $STORY_LENGTH)${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠ Word count: $WORD_COUNT (cannot validate without valid storyLength)${NC}"
            ((WARNINGS++))
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
