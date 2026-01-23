#!/bin/bash
# generate_single_kidfriendly.sh - Generate ONE kid-friendly parable at a time
# Usage: ./generate_single_kidfriendly.sh <mood>
# Example: ./generate_single_kidfriendly.sh joyful
# Moods: joyful, weary, anxious, hurting, neutral

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"
TIMESTAMP=$(date +"%Y%m%d_%H%M")
LOG_FILE="$SCRIPT_DIR/logs/kidfriendly_single_${TIMESTAMP}_gemma_prompts.txt"

# Source ElevenLabs safety guard
source "$SCRIPT_DIR/elevenlabs_guard.sh"

# Trap to release lock on exit
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [[ $# -eq 0 ]]; then
    echo -e "${RED}❌ Error: Mood required${NC}" >&2
    echo "Usage: $0 <mood>" >&2
    echo "Moods: joyful, weary, anxious, hurting, neutral" >&2
    exit 1
fi

MOOD="$1"
VALID_MOODS=("joyful" "weary" "anxious" "hurting" "neutral")

if [[ ! " ${VALID_MOODS[@]} " =~ " ${MOOD} " ]]; then
    echo -e "${RED}❌ Error: Invalid mood '$MOOD'${NC}" >&2
    echo "Valid moods: joyful, weary, anxious, hurting, neutral" >&2
    exit 1
fi

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ Error: curl required${NC}" >&2; exit 1; }
command -v ollama >/dev/null 2>&1 || { echo -e "${RED}❌ Error: ollama required${NC}" >&2; exit 1; }

# HARD FAIL IF GEMMA IS MISSING
if ! ollama list | awk '{print $1}' | grep -qx "gemma:7b"; then
    echo -e "${RED}❌ Error: Ollama model gemma:7b not found. Install with: ollama pull gemma:7b${NC}" >&2
    ollama list || true
    exit 1
fi

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env not found${NC}" >&2
    exit 1
fi

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

# Validate env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}" >&2
    exit 1
fi

if [[ -z "${ELEVENLABS_VOICE_ID:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_VOICE_ID not found in .env${NC}" >&2
    exit 1
fi

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "${BLUE}  Bible PAL - Single Kid-Friendly Parable${NC}" >&2
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "${BLUE}Mood: ${GREEN}$MOOD${NC}" >&2
echo "" >&2

# Initialize log
echo "Kid-Friendly Single Parable Generation - $TIMESTAMP" > "$LOG_FILE"
echo "Using Ollama model: gemma:7b" >> "$LOG_FILE"
echo "Target length: 600-750 words (CORRECTED for narrated audio ~130-150 wpm)" >> "$LOG_FILE"
echo "Mood: $MOOD" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Load manifest
if [[ -f "$MANIFEST_FILE" ]]; then
    if ! MANIFEST_JSON=$(cat "$MANIFEST_FILE" | jq '.' 2>/dev/null); then
        echo -e "${RED}❌ Error: manifest.json is corrupted${NC}" >&2
        exit 1
    fi
else
    MANIFEST_JSON='{"parables":[]}'
fi

# Source the generation functions from the batch script
source "$SCRIPT_DIR/generate_kidfriendly_batch.sh" 2>/dev/null || {
    # If sourcing fails, define functions inline
    generate_kidfriendly_story() {
        local mood=$1
        local story_num=$2

        # CORRECTED CALIBRATION: 5min narrated audio = 600-750 words (~130-150 wpm speaking rate)
        local target_words=675
        local min_acceptable=600
        local max_acceptable=750
        local chunk_size=700  # Generate full 600-750 words in ONE segment (not multiple)

        local mood_context=""
        case "$mood" in
            joyful) mood_context="The child listener is happy and wants to celebrate! Create a joyful story about sharing happiness, being grateful, and seeing God's love in good moments. Use happy themes like gardens, rainbows, celebrations, or helping others." ;;
            weary) mood_context="The child listener is tired or had a long day. Create a gentle, comforting story about rest, taking breaks, and trusting that everything will be okay. Use calming themes like bedtime, peaceful places, or kind helpers." ;;
            anxious) mood_context="The child listener is worried or nervous about something. Create a reassuring story about feeling brave, asking for help, and knowing that God is always with us. Use themes like facing new things, finding courage, or discovering you're not alone." ;;
            hurting) mood_context="The child listener is sad or something hurt their feelings. Create a tender, healing story about it being okay to cry, receiving comfort, and how hurts can get better. Use themes like healing, friendship, gentle care, or finding hope again." ;;
            neutral) mood_context="The child listener is calm and ready to learn. Create a thoughtful story about discovering something special in everyday life, being curious, or learning an important lesson. Use themes like exploring, noticing small wonders, or understanding kindness." ;;
        esac

        local full_story=""
        local current_words=0
        local segment_num=0
        local max_segments=10

        echo -e "${BLUE}  → Generating story in segments (target: $target_words words)${NC}" >&2

        while [[ $current_words -lt $min_acceptable ]] && [[ $segment_num -lt $max_segments ]]; do
            segment_num=$((segment_num + 1))
            local words_needed=$((target_words - current_words))
            local this_chunk=$((words_needed < chunk_size ? words_needed : chunk_size))

            local prompt=""
            if [[ $segment_num -eq 1 ]]; then
                prompt="You are creating a modern Christian parable specifically for children (ages 6-10). Write in the style of a gentle bedtime story.

Context: $mood_context

Write the BEGINNING of a parable (approximately $this_chunk words). This is PART 1 of a longer story.

REQUIREMENTS:
- Use simple, clear language for ages 6-10
- Create a relatable child protagonist (or friendly animal)
- Use modern, familiar settings (home, school, park, neighborhood)
- Include gentle sensory details (colors, sounds, feelings)
- Show emotions children understand
- Use warm, encouraging tone
- DO NOT conclude the story yet - this is just the beginning
- Write approximately $this_chunk words

AVOID:
- Complex theology or abstract concepts
- Fear-based imagery or scary elements
- Adult themes
- Long sentences or complicated vocabulary

Begin the parable now (write $this_chunk words):"
            else
                local story_tail=$(echo "$full_story" | tail -n 60)
                prompt="Continue this children's parable. Write the NEXT SECTION (approximately $this_chunk words).

Context: $mood_context

STORY SO FAR (recent context):
$story_tail

CONTINUATION REQUIREMENTS:
- Continue naturally from where the story left off
- Maintain the same character, setting, and tone
- Keep language simple and child-appropriate
- Deepen the character's experience or discovery
- Current word count: $current_words words, target: $target_words words
- If we're close to $target_words words, bring the story to a hopeful conclusion
- If not close yet, continue developing the narrative
- Write approximately $this_chunk words

Continue the parable now (write $this_chunk words):"
            fi

            echo "=== STORY $story_num ($mood) - SEGMENT $segment_num ===" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
            echo "$prompt" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
            echo "--- GEMMA 7B OUTPUT ---" >> "$LOG_FILE"

            local segment
            segment=$(ollama run gemma:7b "$prompt" 2>&1)

            if [[ $? -ne 0 ]]; then
                echo -e "${RED}Error: Gemma 7B generation failed on segment $segment_num${NC}" >&2
                return 1
            fi

            segment=$(echo "$segment" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | sed $'s/\x1b\\[?[0-9]*[a-z]//g')
            segment=$(echo "$segment" | tr -d '\r' | sed 's/\[K//g' | sed 's/\[?[0-9]*[hl]//g')
            segment=$(echo "$segment" | sed 's/^>.*$//')
            segment=$(echo "$segment" | sed '/^$/N;/^\n$/D')
            segment=$(echo "$segment" | sed 's/[⠀-⣿]//g')
            segment=$(echo "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            echo "$segment" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"

            if [[ -n "$full_story" ]]; then
                full_story="$full_story

$segment"
            else
                full_story="$segment"
            fi

            current_words=$(echo "$full_story" | wc -w | tr -d ' ')
            echo -e "${BLUE}    Segment $segment_num complete: $current_words words total${NC}" >&2
        done

        echo "$full_story"
    }

    generate_title() {
        local mood=$1
        local story_text=$2

        local prompt="Read this children's parable and create a simple, friendly title (3-5 words) that a child would understand. Return ONLY the title, nothing else.

Parable:
$story_text

Title:"

        local title
        title=$(ollama run gemma:7b "$prompt" 2>&1 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')

        if [[ -z "$title" ]] || [[ $? -ne 0 ]]; then
            case "$mood" in
                joyful) title="A Happy Day" ;;
                weary) title="Time to Rest" ;;
                anxious) title="Being Brave" ;;
                hurting) title="Finding Comfort" ;;
                neutral) title="A Special Discovery" ;;
            esac
        fi

        echo "$title"
    }
}

# Compute story number
BASE_NUM=$(echo "$MANIFEST_JSON" | jq '.parables | length')
STORY_NUM=$((BASE_NUM + 1))
STORY_ID=$(printf "parable_%03d_%s_5min_kid" "$STORY_NUM" "$MOOD")

# Check if exists
EXISTS=$(echo "$MANIFEST_JSON" | jq -r --arg id "$STORY_ID" '(.parables // []) | map(select(.storyId == $id)) | length')
if [[ "$EXISTS" != "0" ]]; then
    echo -e "${YELLOW}⊙ Story $STORY_ID already exists${NC}" >&2
    echo -e "${YELLOW}   Skipping generation. Delete existing files first if you want to regenerate.${NC}" >&2
    exit 0
fi

echo -e "${BLUE}→ Generating: $STORY_ID${NC}" >&2

# Generate story text
STORY_TEXT=$(generate_kidfriendly_story "$MOOD" "$STORY_NUM")

if [[ $? -ne 0 ]] || [[ -z "$STORY_TEXT" ]]; then
    echo -e "${RED}✗ Story generation failed${NC}" >&2
    exit 1
fi

AUDIO_FILE="$OUTPUT_DIR/${STORY_ID}.mp3"
TEXT_FILE="$OUTPUT_DIR/${STORY_ID}.txt"

# Save text
echo "$STORY_TEXT" > "$TEXT_FILE"

# DEDUPLICATION CHECK: Remove repetitive paragraphs at the end
# This prevents issues from segmented generation creating duplicate content
python3 -c "
import sys
import re

def remove_duplicate_paragraphs(text):
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]

    # Check last 4 paragraphs for duplicates
    if len(paragraphs) >= 4:
        # Check if last 2 paragraphs match the 2 before them
        if paragraphs[-2:] == paragraphs[-4:-2]:
            paragraphs = paragraphs[:-2]

    return '\n\n'.join(paragraphs) + '\n'

with open('$TEXT_FILE', 'r') as f:
    text = f.read()

cleaned = remove_duplicate_paragraphs(text)

with open('$TEXT_FILE', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true

# WORDCOUNT VALIDATION
WORDS=$(wc -w < "$TEXT_FILE" | tr -d ' ')
echo -e "${BLUE}  Word count: $WORDS${NC}" >&2

if (( WORDS < 600 || WORDS > 750 )); then
    echo -e "${RED}❌ Error: $STORY_ID wordcount $WORDS outside 600–750 range (narrated audio calibration)${NC}" >&2
    echo -e "${RED}   Failed wordcount validation. Aborting.${NC}" >&2
    rm "$TEXT_FILE"
    exit 1
fi

echo -e "${GREEN}  ✓ Wordcount validation passed ($WORDS words)${NC}" >&2

# Generate title
TITLE=$(generate_title "$MOOD" "$STORY_TEXT")
echo -e "${BLUE}  Title: $TITLE${NC}" >&2

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ELEVENLABS SAFETY GUARD
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CHAR_COUNT=$(printf "%s" "$STORY_TEXT" | wc -c | tr -d ' ')
echo -e "${BLUE}  Character count: $CHAR_COUNT${NC}" >&2

# Check safety guard (validates AUDIO_ENABLED, char limits, acquires lock)
if elevenlabs_check_and_log "$STORY_ID" "$CHAR_COUNT" 5; then
    # Guard approved - make the API call
    HTTP_CODE=$(elevenlabs_call "$STORY_TEXT" "$AUDIO_FILE" "$ELEVENLABS_VOICE_ID" "$ELEVENLABS_API_KEY")

    if [[ "$HTTP_CODE" == "200" ]]; then
        FILE_SIZE=$(ls -lh "$AUDIO_FILE" | awk '{print $5}')
        echo -e "${GREEN}✓ Generated: $STORY_ID ($WORDS words, $FILE_SIZE audio)${NC}" >&2
        AUDIO_PATH="${STORY_ID}.mp3"
    else
        if [[ -f "$AUDIO_FILE" ]]; then
            ERROR_MSG=$(jq -r '.detail.message // .message // empty' < "$AUDIO_FILE" 2>/dev/null || cat "$AUDIO_FILE")
            echo -e "${RED}Error: $ERROR_MSG${NC}" >&2
            rm "$AUDIO_FILE"
        fi
        rm "$TEXT_FILE"
        exit 1
    fi
else
    # Guard blocked - audio generation disabled or failed validation
    # Text file already saved, continue without audio
    AUDIO_PATH="null"
fi

# Add to manifest
if [[ "$AUDIO_PATH" == "null" ]]; then
    NEW_ENTRY=$(jq -n \
        --arg id "$STORY_ID" \
        --arg title "$TITLE" \
        --arg mood "$MOOD" \
        --arg text "${STORY_ID}.txt" \
        '{
            storyId: $id,
            title: $title,
            mood: $mood,
            length: 5,
            faithTradition: "Protestant",
            storytellingMode: "creative",
            kidFriendly: true,
            audioFilePath: null,
            textFilePath: $text
        }')
else
    NEW_ENTRY=$(jq -n \
        --arg id "$STORY_ID" \
        --arg title "$TITLE" \
        --arg mood "$MOOD" \
        --arg audio "$AUDIO_PATH" \
        --arg text "${STORY_ID}.txt" \
        '{
            storyId: $id,
            title: $title,
            mood: $mood,
            length: 5,
            faithTradition: "Protestant",
            storytellingMode: "creative",
            kidFriendly: true,
            audioFilePath: $audio,
            textFilePath: $text
        }')
fi

MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq ".parables += [$NEW_ENTRY]")
echo "$MANIFEST_JSON" | jq '.' > "$MANIFEST_FILE"

echo "" >&2
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "${GREEN}✓ Single parable generation complete!${NC}" >&2
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
echo -e "Story ID: ${GREEN}$STORY_ID${NC}" >&2
echo -e "Log saved: $LOG_FILE" >&2
echo "" >&2
