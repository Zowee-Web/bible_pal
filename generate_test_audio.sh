#!/bin/bash

##############################################################################
# Bible PAL - ElevenLabs Audio Generation Script
# Task Group 5: Generate Real Audio from Test Parable Text Files
#
# Purpose:
#   - Replace placeholder MP3 files with real ElevenLabs narration
#   - Use ElevenLabs Text-to-Speech API v3
#   - Generate audio for all 5 sample parables
#   - Maintain calm, slow, contemplative "Bible PAL aesthetic"
#
# Requirements:
#   - ElevenLabs API key in .env file
#   - curl installed (pre-installed on macOS/Linux)
#   - jq installed (required for JSON parsing): brew install jq
#
# Usage:
#   ./generate_test_audio.sh
##############################################################################

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
STORIES_DIR="assets/stories"
ENV_FILE=".env"
ELEVENLABS_API_URL="https://api.elevenlabs.io/v1/text-to-speech"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Audio Generation Pipeline${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Check for required commands
echo -e "${YELLOW}🔍 Checking dependencies...${NC}"
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ Error: curl is not installed${NC}"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ Error: jq is not installed (required for JSON parsing)${NC}"
    echo -e "${YELLOW}Install with: brew install jq${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dependencies OK${NC}\n"

# Load API key from .env
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    echo -e "${YELLOW}Please create a .env file with:${NC}"
    echo -e "${YELLOW}ELEVENLABS_API_KEY=your_api_key_here${NC}"
    echo -e "${YELLOW}ELEVENLABS_VOICE_ID=your_voice_id_here${NC}"
    exit 1
fi

# Source .env file - properly handle inline comments
while IFS='=' read -r key value; do
    # Skip empty lines and comments
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    # Remove inline comments from value
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    # Export the variable
    export "$key=$value"
done < "$ENV_FILE"

if [ -z "$ELEVENLABS_API_KEY" ]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

if [ -z "$ELEVENLABS_VOICE_ID" ]; then
    echo -e "${RED}❌ Error: ELEVENLABS_VOICE_ID not found in .env${NC}"
    echo -e "${YELLOW}Please add ELEVENLABS_VOICE_ID to your .env file${NC}"
    exit 1
fi

echo -e "${GREEN}✓ API Key loaded${NC}"
echo -e "${GREEN}✓ Voice ID: ${ELEVENLABS_VOICE_ID}${NC}\n"

# Define parable files
declare -a TEXT_FILES=(
    "parable_001_joyful_5min.txt"
    "parable_002_weary_10min.txt"
    "parable_003_anxious_15min.txt"
    "parable_004_hurting_20min.txt"
    "parable_005_neutral_10min.txt"
)

# Voice settings for calm, contemplative narration
# stability: higher = more consistent (0.0 - 1.0)
# similarity_boost: higher = closer to original voice (0.0 - 1.0)
# style: expressiveness (0.0 - 1.0)
STABILITY="0.65"
SIMILARITY_BOOST="0.75"
STYLE="0.30"

echo -e "${BLUE}📝 Processing ${#TEXT_FILES[@]} parables...${NC}\n"

# Counter
TOTAL=${#TEXT_FILES[@]}
CURRENT=0
SUCCESS=0
FAILED=0

# Process each text file
for TEXT_FILE in "${TEXT_FILES[@]}"; do
    CURRENT=$((CURRENT + 1))

    # Derive MP3 filename from text filename
    MP3_FILE="${TEXT_FILE%.txt}.mp3"
    TEXT_PATH="$STORIES_DIR/$TEXT_FILE"
    AUDIO_PATH="$STORIES_DIR/$MP3_FILE"

    echo -e "${YELLOW}[$CURRENT/$TOTAL] Processing: $TEXT_FILE${NC}"

    # Check if text file exists
    if [ ! -f "$TEXT_PATH" ]; then
        echo -e "${RED}  ❌ Text file not found: $TEXT_PATH${NC}\n"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Read text content
    TEXT_CONTENT=$(<"$TEXT_PATH")

    # Estimate audio length (rough: 150 words per minute)
    WORD_COUNT=$(echo "$TEXT_CONTENT" | wc -w | xargs)
    ESTIMATED_MINUTES=$((WORD_COUNT / 150))
    echo -e "  📊 Word count: $WORD_COUNT (~$ESTIMATED_MINUTES min estimated)"

    # Create JSON payload with voice settings
    JSON_PAYLOAD=$(jq -n \
        --arg text "$TEXT_CONTENT" \
        --arg stability "$STABILITY" \
        --arg similarity "$SIMILARITY_BOOST" \
        --arg style "$STYLE" \
        '{
            text: $text,
            model_id: "eleven_multilingual_v2",
            voice_settings: {
                stability: ($stability | tonumber),
                similarity_boost: ($similarity | tonumber),
                style: ($style | tonumber),
                use_speaker_boost: true
            }
        }')

    # Call ElevenLabs API
    echo -e "  🎙️  Generating audio..."
    HTTP_CODE=$(curl -s -w "%{http_code}" -o "$AUDIO_PATH.tmp" \
        -X POST "$ELEVENLABS_API_URL/$ELEVENLABS_VOICE_ID" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD")

    # Check HTTP response
    if [ "$HTTP_CODE" -eq 200 ]; then
        # Successful generation
        mv "$AUDIO_PATH.tmp" "$AUDIO_PATH"
        FILE_SIZE=$(du -h "$AUDIO_PATH" | cut -f1)
        echo -e "${GREEN}  ✓ Generated: $MP3_FILE ($FILE_SIZE)${NC}\n"
        SUCCESS=$((SUCCESS + 1))
    else
        # API error
        echo -e "${RED}  ❌ API Error (HTTP $HTTP_CODE)${NC}"
        if [ -f "$AUDIO_PATH.tmp" ]; then
            # Try to parse error message
            ERROR_MSG=$(cat "$AUDIO_PATH.tmp" 2>/dev/null | jq -r '.detail.message // .message // "Unknown error"' 2>/dev/null || cat "$AUDIO_PATH.tmp")
            echo -e "${RED}  Error: $ERROR_MSG${NC}"
            rm "$AUDIO_PATH.tmp"
        fi
        echo ""
        FAILED=$((FAILED + 1))
    fi
done

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Generation Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Success: $SUCCESS/$TOTAL${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}✗ Failed:  $FAILED/$TOTAL${NC}"
fi
echo ""

# List generated files
if [ $SUCCESS -gt 0 ]; then
    echo -e "${BLUE}Generated audio files:${NC}"
    ls -lh "$STORIES_DIR"/*.mp3 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
fi

# Final status
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All audio files generated successfully!${NC}"
    echo -e "${GREEN}You can now run the Flutter app to test playback.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some files failed to generate. Check errors above.${NC}"
    exit 1
fi
