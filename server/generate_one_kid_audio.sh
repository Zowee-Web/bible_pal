#!/bin/bash
# Generate audio for a single kid-safe story using ElevenLabs
# Uses VOICE_ARABELLA (nurturing, tender female)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"

# Source shared components
source "$SCRIPT_DIR/elevenlabs_guard.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Validate API key
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

# Check argument
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <story_id>"
    echo "Example: $0 parable_114_samuel_listens_5min_kid_safe"
    exit 1
fi

STORY_ID="$1"
TEXT_FILE="$OUTPUT_DIR/${STORY_ID}.txt"
AUDIO_FILE="$OUTPUT_DIR/${STORY_ID}.mp3"

# Check file exists
if [[ ! -f "$TEXT_FILE" ]]; then
    echo -e "${RED}❌ Text file not found: $TEXT_FILE${NC}"
    exit 1
fi

# Get story text and character count
STORY_TEXT=$(cat "$TEXT_FILE")
CHAR_COUNT=$(printf "%s" "$STORY_TEXT" | wc -c | tr -d ' ')
WORD_COUNT=$(echo "$STORY_TEXT" | wc -w | tr -d ' ')

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Kid Bedtime Story Audio Generation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Story ID: ${GREEN}$STORY_ID${NC}"
echo -e "Word count: ${GREEN}$WORD_COUNT${NC}"
echo -e "Character count: ${GREEN}$CHAR_COUNT${NC}"
echo -e "Voice: ${GREEN}VOICE_ARABELLA${NC} - Nurturing, tender female"
echo -e "Output: ${GREEN}$AUDIO_FILE${NC}"
echo ""

# Extract length from story_id
if [[ $STORY_ID =~ _([0-9]+)min ]]; then
    LENGTH="${BASH_REMATCH[1]}"
else
    LENGTH=5  # default for kid bedtime stories
fi

# Call with AUDIO_ENABLED
export AUDIO_ENABLED=1
if elevenlabs_check_and_log "$STORY_ID" "$CHAR_COUNT" "$LENGTH"; then
    http_code=$(elevenlabs_call "$STORY_TEXT" "$AUDIO_FILE" "$VOICE_ARABELLA" "$ELEVENLABS_API_KEY")

    if [[ "$http_code" == "200" ]]; then
        file_size=$(ls -lh "$AUDIO_FILE" | awk '{print $5}')
        echo ""
        echo -e "${GREEN}✓ Audio generated successfully!${NC}"
        echo -e "  File: ${GREEN}$AUDIO_FILE${NC}"
        echo -e "  Size: ${GREEN}$file_size${NC}"
    else
        echo -e "${RED}❌ Audio generation failed (HTTP $http_code)${NC}"
        if [[ -f "$AUDIO_FILE" ]]; then
            echo "Error response:"
            cat "$AUDIO_FILE"
            rm "$AUDIO_FILE"
        fi
        exit 1
    fi
fi
