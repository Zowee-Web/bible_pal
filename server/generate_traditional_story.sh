#!/bin/bash
# generate_traditional_story.sh
# Generates ONE traditional Bible story retelling using Gemma 7B
# Usage: ./generate_traditional_story.sh <mood> <bible_story_ref> [story_number]
#
# Mood options: joyful, weary, anxious, hurting, neutral
# Bible story reference: e.g., "Mark 4:35-41" or "David and Goliath"
# Story number: optional (defaults to next available in manifest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"

# Source ElevenLabs safety guard
source "$SCRIPT_DIR/elevenlabs_guard.sh"

# Trap to release lock on exit
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
command -v ollama >/dev/null 2>&1 || { echo -e "${RED}❌ Error: ollama required${NC}" >&2; exit 1; }

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
if [[ $# -lt 2 ]]; then
    echo -e "${RED}Usage: $0 <mood> <bible_story_ref> [story_number]${NC}"
    echo "Moods: joyful, weary, anxious, hurting, neutral"
    echo "Example: $0 weary \"Mark 4:35-41\""
    exit 1
fi

MOOD="$1"
BIBLE_STORY="$2"
STORY_NUM="${3:-}"

# Validate mood
case "$MOOD" in
    joyful|weary|anxious|hurting|neutral)
        ;;
    *)
        echo -e "${RED}❌ Invalid mood: $MOOD${NC}"
        echo "Valid moods: joyful, weary, anxious, hurting, neutral"
        exit 1
        ;;
esac

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Bible PAL - Traditional Story Generation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Mood: ${GREEN}$MOOD${NC}"
echo -e "Bible Story: ${GREEN}$BIBLE_STORY${NC}"
echo -e "Model: ${GREEN}gemma:7b (via Ollama)${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Load or init manifest
if [[ -f "$MANIFEST_FILE" ]]; then
    if ! MANIFEST_JSON=$(cat "$MANIFEST_FILE" | jq '.' 2>/dev/null); then
        echo -e "${RED}❌ Error: manifest.json is corrupted${NC}"
        exit 1
    fi
else
    MANIFEST_JSON='{"parables":[]}'
fi

# Calculate story number if not provided (FIX 1: removed invalid 'local')
if [[ -z "$STORY_NUM" ]]; then
    total_parables=$(echo "$MANIFEST_JSON" | jq '.parables | length')
    STORY_NUM=$((total_parables + 1))
fi

# CRITICAL: Story length is calibrated to NARRATED audio playback (~130-150 wpm)
# NOT silent reading speed. All stories MUST pass narrated word-count validation.
# 5min = 600-750 words | 10min = 1200-1500 | 15min = 1800-2250 | 20min = 2400-3000
LENGTH=5
story_id=$(printf "parable_%03d_%s_%dmin" "$STORY_NUM" "$MOOD" "$LENGTH")

# Check if exists
exists=$(echo "$MANIFEST_JSON" | jq -r --arg id "$story_id" '(.parables // []) | map(select(.storyId == $id)) | length')
if [[ "$exists" != "0" ]]; then
    echo -e "${YELLOW}⚠ Story $story_id already exists in manifest${NC}"
    exit 1
fi

echo -e "${BLUE}→ Generating: $story_id${NC}"
echo ""

# FIX 2: Set MOOD_CONTEXT BEFORE it's used in CINEMATIC_PROMPT
case "$MOOD" in
    joyful)
        MOOD_CONTEXT="joyful and grateful. They want to celebrate God's goodness and deepen their gratitude. The story should acknowledge their joy while inviting them into deeper connection with God's heart."
        ;;
    weary)
        MOOD_CONTEXT="exhausted and burned out, carrying heavy burdens. They need rest and release. The story should reveal the beauty of Sabbath rest, divine provision, and trusting God with what they cannot control."
        ;;
    anxious)
        MOOD_CONTEXT="anxious and worried, overwhelmed by uncertainties. They need peace. The story should show bringing fears to God, finding peace through trust, and experiencing God's presence in the midst of anxiety."
        ;;
    hurting)
        MOOD_CONTEXT="experiencing deep pain, loss, or brokenness. They need comfort. The story should reveal God's nearness to the brokenhearted, the healing journey, and how wounds can become places where grace enters."
        ;;
    neutral)
        MOOD_CONTEXT="in a reflective, open state. They are seeking God in the ordinary. The story should help them find God in everyday moments, see the sacred in the mundane, and discover meaning in routine."
        ;;
esac

# TRADITIONAL_PROMPT - The core template for faithful Bible story retellings
TRADITIONAL_PROMPT="You are retelling a real Bible story faithfully.

Write a faithful, poetic retelling of the Bible story: $BIBLE_STORY

LENGTH:
• Approximately 5 minutes when spoken aloud with expressive narration
• Target 600–750 words (narrated speaking rate: ~130-150 wpm)

FAITHFULNESS (CRITICAL):
1. This must be a REAL Bible story, not an invented parable
2. Follow the biblical narrative accurately - no invented outcomes
3. Do NOT add doctrine or theology not present in the passage
4. Do NOT invent dialogue unless scripture records it
5. Do NOT add \"God said...\" unless scripture says it
6. Character emotions and sensory details are allowed if plausible
7. Stay within the bounds of what scripture describes
8. No modern interpretations or applications

TONE:
• Reverent and contemplative
• Immersive and human
• Narratively engaging but factually faithful
• Calm but engaging

STRUCTURE:
• Tell the story chronologically
• Use sensory detail to bring scenes alive
• Focus on ONE main character's experience
• Let the spiritual meaning emerge from the events themselves
• End where scripture ends - no added moral

BIBLICAL CONTEXT:
• Faithful to the actual biblical account
• Respect the text and its original meaning
• God's presence should be portrayed as scripture portrays it
• No additions beyond what scripture describes

IMPORTANT AVOID:
• No moral summaries or applications
• No \"this teaches us\" language
• No sermon-style explanations
• No verse citations within the text
• No invented content beyond plausible sensory details

OUTPUT RULES:
• Story text only
• No title
• No verse numbers
• No explanation or application

MOOD CONTEXT: The listener is feeling $MOOD_CONTEXT

Retell this Bible story now:"

# Generate story with segmented continuation
# CORRECTED CALIBRATION: 5min narrated audio = 600-750 words (~130-150 wpm speaking rate)
MAX_ATTEMPTS=3
MIN_WORDS=600
MAX_WORDS=750
MAX_SEGMENTS=10
attempt=1
story_text=""
word_count=0

while [[ $attempt -le $MAX_ATTEMPTS ]]; do
    if [[ $attempt -gt 1 ]]; then
        echo -e "${YELLOW}⚠ Attempt $attempt of $MAX_ATTEMPTS (previous: $word_count words)${NC}"
    fi

    # Reset for new attempt
    story_text=""
    word_count=0
    segment=1

    # Segment loop: build story until we reach MIN_WORDS
    while [[ $segment -le $MAX_SEGMENTS ]] && [[ $word_count -lt $MIN_WORDS ]]; do
        echo -e "${BLUE}→ Generating segment $segment via Ollama API...${NC}"

        if [[ $segment -eq 1 ]]; then
            # First segment: use full TRADITIONAL_PROMPT
            prompt="$TRADITIONAL_PROMPT"
        else
            # Continuation segment: include trailing context
            trailing_context=$(echo "$story_text" | tail -c 2000)
            prompt="Continue the SAME story from exactly where it left off. Do not restart. Do not add a title. Output story text only.

Story so far (trailing context):
$trailing_context

Continue the story now:"
        fi

        # Call Ollama API
        story_response=$(curl -s http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d '{
            "model": "gemma:7b",
            "prompt": '"$(echo "$prompt" | jq -Rs .)"',
            "stream": false,
            "options": {
                "num_predict": 900,
                "num_ctx": 4096,
                "temperature": 0.7
            }
        }')

        # Check if API call was successful
        if [[ $? -ne 0 ]] || [[ -z "$story_response" ]]; then
            echo -e "${RED}✗ Ollama API call failed on segment $segment${NC}" >&2
            exit 1
        fi

        # Extract response text
        segment_text=$(echo "$story_response" | jq -r '.response // empty')

        if [[ -z "$segment_text" ]]; then
            echo -e "${RED}✗ Empty response from Ollama on segment $segment${NC}" >&2
            exit 1
        fi

        # Append segment with blank line separator
        if [[ -n "$story_text" ]]; then
            story_text="$story_text

$segment_text"
        else
            story_text="$segment_text"
        fi

        # Cleanup and count words
        story_text=$(echo "$story_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        word_count=$(echo "$story_text" | wc -w | tr -d ' ')

        echo -e "${CYAN}→ Segment $segment complete: $word_count total words${NC}"

        segment=$((segment + 1))
    done

    echo -e "${CYAN}→ Story generation complete: $word_count words across $((segment - 1)) segment(s)${NC}"

    # Check word count bounds
    if [[ $word_count -ge $MIN_WORDS ]] && [[ $word_count -le $MAX_WORDS ]]; then
        echo -e "${GREEN}✓ Word count within target range ($MIN_WORDS-$MAX_WORDS)${NC}"
        break
    else
        if [[ $attempt -eq $MAX_ATTEMPTS ]]; then
            echo -e "${RED}✗ Failed after $MAX_ATTEMPTS attempts${NC}"
            echo -e "${RED}Final word count: $word_count (required: $MIN_WORDS-$MAX_WORDS)${NC}"
            exit 1
        fi
        attempt=$((attempt + 1))
    fi
done

echo ""

# Defensive safety check: validate story output before saving
if [[ -z "$story_text" ]] || [[ $word_count -lt 50 ]]; then
    echo -e "${RED}✗ Story generation returned empty/invalid output${NC}"
    echo -e "${RED}Word count: $word_count (minimum acceptable: 50)${NC}"
    exit 1
fi

# Save text file
text_file="$OUTPUT_DIR/${story_id}.txt"
echo "$story_text" > "$text_file"
echo -e "${GREEN}✓ Saved text: ${story_id}.txt${NC}"

# Generate title from story using Gemma 7B
echo -e "${BLUE}→ Generating title...${NC}"
title_prompt="Read this Bible-inspired story and create a short, evocative title (3-6 words) that captures its essence without being preachy. Return ONLY the title, nothing else.

Story:
$story_text

Title:"

# Generate title using Ollama HTTP API with num_predict for short output
title_response=$(curl -s http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{
    "model": "gemma:7b",
    "prompt": '"$(echo "$title_prompt" | jq -Rs .)"',
    "stream": false,
    "options": {
        "num_predict": 60,
        "temperature": 0.7
    }
}')

title=$(echo "$title_response" | jq -r '.response // empty' | head -1 | sed -E 's/^[[:space:]]*[Tt]itle:[[:space:]]*//' | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e 's/^"//;s/"$//' -e "s/^'//;s/'$//")

# If title generation fails, use mood-based fallback
if [[ -z "$title" ]]; then
    case "$MOOD" in
        joyful) title="A Story of Joy" ;;
        weary) title="Finding Rest" ;;
        anxious) title="Peace in Uncertainty" ;;
        hurting) title="Healing and Hope" ;;
        neutral) title="Seeing the Sacred" ;;
    esac
fi

echo -e "${GREEN}✓ Title: \"$title\"${NC}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELEVENLABS SAFETY GUARD
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
char_count=$(printf "%s" "$story_text" | wc -c | tr -d ' ')
echo -e "${BLUE}Character count: $char_count${NC}"

audio_file="$OUTPUT_DIR/${story_id}.mp3"

# Check safety guard (validates AUDIO_ENABLED, char limits, acquires lock)
if elevenlabs_check_and_log "$story_id" "$char_count" "$LENGTH"; then
    # Guard approved - make the API call
    http_code=$(elevenlabs_call "$story_text" "$audio_file" "$ELEVENLABS_VOICE_ID" "$ELEVENLABS_API_KEY")

    if [[ "$http_code" != "200" ]]; then
        if [[ -f "$audio_file" ]]; then
            error_msg=$(jq -r '.detail.message // .message // empty' < "$audio_file" 2>/dev/null || cat "$audio_file")
            echo -e "${RED}Error: $error_msg${NC}"
            rm "$audio_file"
        fi
        exit 1
    fi

    file_size=$(ls -lh "$audio_file" | awk '{print $5}')
    echo -e "${GREEN}✓ Generated audio: ${story_id}.mp3 ($file_size)${NC}"
else
    # Guard blocked - audio generation disabled or failed validation
    # Text file already saved, continue without audio
    audio_file=""  # Mark as no audio for manifest
fi

# Add to manifest
echo -e "${BLUE}→ Adding to manifest...${NC}"
if [[ -n "$audio_file" ]]; then
    audio_path="${story_id}.mp3"
else
    audio_path="null"
fi

new_entry=$(jq -n \
    --arg id "$story_id" \
    --arg title "$title" \
    --arg mood "$MOOD" \
    --argjson length "$LENGTH" \
    --arg audio "$audio_path" \
    --arg text "${story_id}.txt" \
    '{
        storyId: $id,
        title: $title,
        mood: $mood,
        length: $length,
        faithTradition: "Unspecified",
        storytellingMode: "traditional",
        kidFriendly: false,
        audioFilePath: (if $audio == "null" then null else $audio end),
        textFilePath: $text
    }')

MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq ".parables += [$new_entry]")
echo "$MANIFEST_JSON" | jq '.' > "$MANIFEST_FILE"

echo -e "${GREEN}✓ Added to manifest${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Traditional Story Generation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Story ID:     ${CYAN}$story_id${NC}"
echo -e "Title:        ${CYAN}$title${NC}"
echo -e "Word Count:   ${CYAN}$word_count words${NC}"
echo -e "Text File:    ${CYAN}assets/stories/${story_id}.txt${NC}"
echo -e "Audio File:   ${CYAN}assets/stories/${story_id}.mp3${NC}"
echo -e "Manifest ID:  ${CYAN}$story_id${NC}"
echo ""
echo -e "Total stories in library: ${CYAN}$(echo "$MANIFEST_JSON" | jq '.parables | length')${NC}"
