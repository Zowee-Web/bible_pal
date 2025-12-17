#!/bin/bash
# generate_audio_from_text.sh
# Generates audio for an existing text-only story
# CRITICAL: Only for production stories. Every credit spent produces a permanent asset.
#
# Usage: AUDIO_ENABLED=1 ./generate_audio_from_text.sh <story_id>
# Example: AUDIO_ENABLED=1 ./generate_audio_from_text.sh parable_026_joyful_5min

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"

# Source ElevenLabs safety guard
source "$SCRIPT_DIR/elevenlabs_guard.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ Error: curl required${NC}" >&2; exit 1; }

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env not found${NC}"
    exit 1
fi

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

# Validate env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

if [[ -z "${ELEVENLABS_VOICE_ID:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_VOICE_ID not found in .env${NC}"
    exit 1
fi

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: AUDIO_ENABLED=1 $0 <story_id>${NC}"
    echo ""
    echo "Example: AUDIO_ENABLED=1 $0 parable_026_joyful_5min"
    echo ""
    echo -e "${YELLOW}This script generates audio for existing text-only stories.${NC}"
    echo -e "${YELLOW}Every ElevenLabs credit spent produces a permanent production asset.${NC}"
    exit 1
fi

STORY_ID="$1"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Bible PAL - Audio Generation from Existing Text${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Story ID: ${GREEN}$STORY_ID${NC}"
echo ""

# Validate text file exists
TEXT_FILE="$OUTPUT_DIR/${STORY_ID}.txt"
if [[ ! -f "$TEXT_FILE" ]]; then
    echo -e "${RED}❌ Error: Text file not found: $TEXT_FILE${NC}"
    exit 1
fi

# Read story text
STORY_TEXT=$(cat "$TEXT_FILE")
if [[ -z "$STORY_TEXT" ]]; then
    echo -e "${RED}❌ Error: Text file is empty: $TEXT_FILE${NC}"
    exit 1
fi

WORD_COUNT=$(echo "$STORY_TEXT" | wc -w | tr -d ' ')
echo -e "${BLUE}✓ Text file found: $WORD_COUNT words${NC}"

# Load manifest
if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo -e "${RED}❌ Error: manifest.json not found${NC}"
    exit 1
fi

MANIFEST_JSON=$(cat "$MANIFEST_FILE" | jq '.')
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Error: manifest.json is corrupted${NC}"
    exit 1
fi

# Find story in manifest (select first match only)
STORY_INDEX=$(echo "$MANIFEST_JSON" | jq -r --arg id "$STORY_ID" '
    (.parables | to_entries | map(select(.value.storyId == $id)) | .[0].key) // empty
')
if [[ -z "$STORY_INDEX" ]]; then
    echo -e "${RED}❌ Error: Story not found in manifest: $STORY_ID${NC}"
    exit 1
fi

# Check if audio already exists
EXISTING_AUDIO=$(echo "$MANIFEST_JSON" | jq -r --argjson idx "$STORY_INDEX" '.parables[$idx].audioFilePath // empty')
if [[ -n "$EXISTING_AUDIO" && "$EXISTING_AUDIO" != "null" ]]; then
    if [[ "${FORCE_REGEN:-0}" != "1" ]]; then
        echo -e "${YELLOW}⚠ Story already has audio: $EXISTING_AUDIO${NC}"
        echo -e "${YELLOW}Refusing to regenerate (would waste credits).${NC}"
        echo -e "${YELLOW}To overwrite intentionally, set: FORCE_REGEN=1${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ FORCE_REGEN=1: Will overwrite existing audio${NC}"
    fi
fi

# Extract story length for guard validation
STORY_LENGTH=$(echo "$MANIFEST_JSON" | jq -r --argjson idx "$STORY_INDEX" '.parables[$idx].length')
echo -e "${BLUE}Story length: ${STORY_LENGTH} minutes${NC}"

# ELEVENLABS SAFETY GUARD
CHAR_COUNT=$(printf "%s" "$STORY_TEXT" | wc -c | tr -d ' ')
echo -e "${BLUE}Character count: $CHAR_COUNT${NC}"
echo ""

AUDIO_FILE="$OUTPUT_DIR/${STORY_ID}.mp3"

# Check safety guard (validates AUDIO_ENABLED, char limits, acquires lock)
if elevenlabs_check_and_log "$STORY_ID" "$CHAR_COUNT" "$STORY_LENGTH"; then
    # Guard approved - make the API call
    HTTP_CODE=$(elevenlabs_call "$STORY_TEXT" "$AUDIO_FILE" "$ELEVENLABS_VOICE_ID" "$ELEVENLABS_API_KEY")

    if [[ "$HTTP_CODE" == "200" ]]; then
        # Verify audio file exists and is non-empty
        if [[ ! -s "$AUDIO_FILE" ]]; then
            echo -e "${RED}❌ Error: Audio file missing or empty after API success${NC}"
            rm -f "$AUDIO_FILE"
            exit 1
        fi

        FILE_SIZE=$(ls -lh "$AUDIO_FILE" | awk '{print $5}')
        echo -e "${GREEN}✓ Generated audio: ${STORY_ID}.mp3 ($FILE_SIZE)${NC}"
        echo ""

        # Atomically update manifest (write to temp, validate, then move)
        echo -e "${BLUE}→ Updating manifest...${NC}"
        MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq --argjson idx "$STORY_INDEX" --arg audio "${STORY_ID}.mp3" \
            '.parables[$idx].audioFilePath = $audio')

        TEMP_MANIFEST=$(mktemp "${MANIFEST_FILE}.tmp.XXXX")
        echo "$MANIFEST_JSON" | jq '.' > "$TEMP_MANIFEST"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}❌ Error: Failed to write manifest${NC}"
            rm -f "$TEMP_MANIFEST"
            exit 1
        fi
        mv "$TEMP_MANIFEST" "$MANIFEST_FILE"
        echo -e "${GREEN}✓ Manifest updated${NC}"
        echo ""

        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ Audio Generation Complete!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "Story ID:     ${CYAN}$STORY_ID${NC}"
        echo -e "Audio File:   ${CYAN}assets/stories/${STORY_ID}.mp3${NC}"
        echo -e "File Size:    ${CYAN}$FILE_SIZE${NC}"
        echo -e "Characters:   ${CYAN}$CHAR_COUNT (~$CHAR_COUNT credits)${NC}"
        echo ""
    else
        echo -e "${RED}✗ API Error (HTTP $HTTP_CODE)${NC}"
        if [[ -f "$AUDIO_FILE" ]]; then
            ERROR_MSG=$(jq -r '.detail.message // .message // empty' < "$AUDIO_FILE" 2>/dev/null || cat "$AUDIO_FILE")
            echo -e "${RED}Error: $ERROR_MSG${NC}"
            rm "$AUDIO_FILE"
        fi
        echo ""
        echo -e "${RED}Manifest NOT updated (audio generation failed)${NC}"
        exit 1
    fi
else
    # Guard blocked - no changes made
    echo ""
    echo -e "${YELLOW}Audio generation blocked by safety guard.${NC}"
    echo -e "${YELLOW}No changes made to manifest or files.${NC}"
    exit 1
fi
