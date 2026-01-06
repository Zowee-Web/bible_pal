#!/bin/bash
# generate_multivoice_parable.sh
# Generates a multi-voice parable with character dialogue

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
TEMP_DIR="$OUTPUT_DIR/temp_segments"

# Source ElevenLabs safety guard
source "$SCRIPT_DIR/elevenlabs_guard.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ Error: curl required${NC}" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo -e "${RED}❌ Error: ffmpeg required${NC}" >&2; exit 1; }

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env not found${NC}"
    exit 1
fi

source "$ENV_FILE"

# Validate env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Multi-Voice Parable Generation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Load script
SCRIPT_FILE="$SCRIPT_DIR/multivoice_test_parable.json"
if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo -e "${RED}❌ Error: $SCRIPT_FILE not found${NC}"
    exit 1
fi

SEGMENTS=$(jq -c '.[]' "$SCRIPT_FILE")
SEGMENT_COUNT=$(echo "$SEGMENTS" | wc -l | tr -d ' ')

echo -e "${BLUE}Generating $SEGMENT_COUNT audio segments...${NC}"
echo ""

# Generate each segment
SEGMENT_NUM=0
CONCAT_LIST="$TEMP_DIR/concat_list.txt"
> "$CONCAT_LIST"

while IFS= read -r segment; do
    SEGMENT_NUM=$((SEGMENT_NUM + 1))

    VOICE_ID=$(echo "$segment" | jq -r '.voice_id')
    VOICE_NAME=$(echo "$segment" | jq -r '.voice_name')
    TEXT=$(echo "$segment" | jq -r '.text')

    SEGMENT_FILE="$TEMP_DIR/segment_$(printf '%03d' $SEGMENT_NUM).mp3"

    echo -e "${BLUE}→ [$SEGMENT_NUM/$SEGMENT_COUNT] $VOICE_NAME${NC}"

    # ELEVENLABS SAFETY GUARD
    char_count=$(printf "%s" "$TEXT" | wc -c | tr -d ' ')
    segment_id="multivoice_segment_${SEGMENT_NUM}"

    if elevenlabs_check_and_log "$segment_id" "$char_count" "5"; then
        http_code=$(elevenlabs_call "$TEXT" "$SEGMENT_FILE" "$VOICE_ID" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" ]]; then
            echo "file '$SEGMENT_FILE'" >> "$CONCAT_LIST"
            echo -e "${GREEN}✓ Generated segment $SEGMENT_NUM${NC}"
        else
            echo -e "${RED}✗ API Error (HTTP $http_code)${NC}"
            if [[ -f "$SEGMENT_FILE" ]]; then
                error_msg=$(jq -r '.detail.message // .message // empty' < "$SEGMENT_FILE" 2>/dev/null || cat "$SEGMENT_FILE")
                echo -e "${RED}Error: $error_msg${NC}"
                rm "$SEGMENT_FILE"
            fi
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ Audio generation skipped for segment $SEGMENT_NUM${NC}"
        exit 1
    fi

    sleep 0.5  # Rate limiting
done <<< "$SEGMENTS"

echo ""
echo -e "${BLUE}Stitching segments together...${NC}"

# Concatenate all segments
OUTPUT_FILE="$OUTPUT_DIR/parable_multivoice_test.mp3"
ffmpeg -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$OUTPUT_FILE" -y 2>&1 | grep -v "^frame=" || true

if [[ -f "$OUTPUT_FILE" ]]; then
    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo -e "${GREEN}✓ Multi-voice parable created: $FILE_SIZE${NC}"

    # Save text version
    TEXT_FILE="$OUTPUT_DIR/parable_multivoice_test.txt"
    jq -r '.[] | "\(.voice_name): \(.text)\n"' "$SCRIPT_FILE" > "$TEXT_FILE"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Audio: $OUTPUT_FILE"
    echo -e "Text: $TEXT_FILE"
    echo ""

    # Clean up temp files
    # rm -rf "$TEMP_DIR"
else
    echo -e "${RED}✗ Failed to create output file${NC}"
    exit 1
fi
