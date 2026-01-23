#!/bin/bash
# generate_kidfriendly_batch.sh - Kid-friendly parable generation
# Generates 5 kid-friendly parables (one per mood, 5min each)
# Uses Ollama + Gemma 7B for text generation, ElevenLabs for audio

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"
TIMESTAMP=$(date +"%Y%m%d_%H%M")
LOG_FILE="$SCRIPT_DIR/logs/kidfriendly_batch_${TIMESTAMP}_gemma_prompts.txt"

# Source ElevenLabs safety guard and story calibration
source "$SCRIPT_DIR/elevenlabs_guard.sh"
source "$SCRIPT_DIR/story_calibration.sh"
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
command -v ollama >/dev/null 2>&1 || { echo -e "${RED}❌ Error: ollama required${NC}" >&2; exit 1; }

# HARD FAIL IF GEMMA IS MISSING
if ! ollama list | awk '{print $1}' | grep -qx "gemma:7b"; then
    echo -e "${RED}❌ Error: Ollama model gemma:7b not found. Install with: ollama pull gemma:7b${NC}"
    ollama list || true
    exit 1
fi

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

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Kid-Friendly Parable Generation (v2)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Initialize log
echo "Kid-Friendly Parable Generation - $TIMESTAMP" > "$LOG_FILE"
echo "Using Ollama model: gemma:7b" >> "$LOG_FILE"
echo "Target length: 1100-1300 words" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Load manifest
if [[ -f "$MANIFEST_FILE" ]]; then
    if ! MANIFEST_JSON=$(cat "$MANIFEST_FILE" | jq '.' 2>/dev/null); then
        echo -e "${RED}❌ Error: manifest.json is corrupted${NC}"
        exit 1
    fi
else
    MANIFEST_JSON='{"parables":[]}'
fi

# Function to generate kid-friendly story text with SEGMENTED GENERATION
generate_kidfriendly_story() {
    local mood=$1
    local story_num=$2

    # Target: ~1200 words for 5 minutes
    local target_words=1200
    local min_acceptable=1100
    local max_acceptable=1400
    local chunk_size=400  # Smaller chunks for better control

    # Build mood-specific kid-friendly prompt
    local mood_context=""
    case "$mood" in
        joyful)
            mood_context="The child listener is happy and wants to celebrate! Create a joyful story about sharing happiness, being grateful, and seeing God's love in good moments. Use happy themes like gardens, rainbows, celebrations, or helping others."
            ;;
        weary)
            mood_context="The child listener is tired or had a long day. Create a gentle, comforting story about rest, taking breaks, and trusting that everything will be okay. Use calming themes like bedtime, peaceful places, or kind helpers."
            ;;
        anxious)
            mood_context="The child listener is worried or nervous about something. Create a reassuring story about feeling brave, asking for help, and knowing that God is always with us. Use themes like facing new things, finding courage, or discovering you're not alone."
            ;;
        hurting)
            mood_context="The child listener is sad or something hurt their feelings. Create a tender, healing story about it being okay to cry, receiving comfort, and how hurts can get better. Use themes like healing, friendship, gentle care, or finding hope again."
            ;;
        neutral)
            mood_context="The child listener is calm and ready to learn. Create a thoughtful story about discovering something special in everyday life, being curious, or learning an important lesson. Use themes like exploring, noticing small wonders, or understanding kindness."
            ;;
    esac

    # SEGMENTED GENERATION LOOP
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
            # First segment - establish the story
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
            # Continuation segment - use only last ~60 lines as context
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

        # Log the prompt
        echo "=== STORY $story_num ($mood) - SEGMENT $segment_num ===" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        echo "$prompt" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        echo "--- GEMMA 7B OUTPUT ---" >> "$LOG_FILE"

        # Generate segment using Ollama Gemma 7B
        local segment
        segment=$(ollama run gemma:7b "$prompt" 2>&1)

        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Gemma 7B generation failed on segment $segment_num${NC}" >&2
            return 1
        fi

        # Clean up ANSI codes and artifacts
        segment=$(echo "$segment" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | sed $'s/\x1b\\[?[0-9]*[a-z]//g')
        segment=$(echo "$segment" | tr -d '\r' | sed 's/\[K//g' | sed 's/\[?[0-9]*[hl]//g')
        segment=$(echo "$segment" | sed 's/^>.*$//')
        segment=$(echo "$segment" | sed '/^$/N;/^\n$/D')
        segment=$(echo "$segment" | sed 's/[⠀-⣿]//g')
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Log the output
        echo "$segment" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"

        # Append to full story
        if [[ -n "$full_story" ]]; then
            full_story="$full_story

$segment"
        else
            full_story="$segment"
        fi

        # Count words
        current_words=$(echo "$full_story" | wc -w | tr -d ' ')
        echo -e "${BLUE}    Segment $segment_num complete: $current_words words total${NC}" >&2
    done

    echo "$full_story"
}

# Function to generate title
generate_title() {
    local mood=$1
    local story_text=$2

    local prompt="Read this children's parable and create a simple, friendly title (3-5 words) that a child would understand. Return ONLY the title, nothing else.

Parable:
$story_text

Title:"

    local title
    title=$(ollama run gemma:7b "$prompt" 2>&1 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')

    # Fallback titles
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

# Function to generate one parable
generate_parable() {
    local mood=$1
    local mood_index=$2
    local story_num=$((BASE_NUM + mood_index + 1))
    local story_id=$(printf "parable_%03d_%s_5min_kid" "$story_num" "$mood")

    # Check if exists
    local exists=$(echo "$MANIFEST_JSON" | jq -r --arg id "$story_id" '(.parables // []) | map(select(.storyId == $id)) | length')
    if [[ "$exists" != "0" ]]; then
        echo -e "${YELLOW}⊙ Skipping $story_id (exists)${NC}"
        return 0
    fi

    echo -e "${BLUE}→ Generating: $story_id${NC}" >&2

    # Generate story text
    local story_text=$(generate_kidfriendly_story "$mood" "$story_num")

    if [[ $? -ne 0 ]] || [[ -z "$story_text" ]]; then
        echo -e "${RED}✗ Story generation failed${NC}" >&2
        return 1
    fi

    local audio_file="$OUTPUT_DIR/${story_id}.mp3"
    local text_file="$OUTPUT_DIR/${story_id}.txt"

    # Save text
    echo "$story_text" > "$text_file"

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

with open('$text_file', 'r') as f:
    text = f.read()

cleaned = remove_duplicate_paragraphs(text)

with open('$text_file', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true

    # WORDCOUNT VALIDATION (REQUIRED)
    local words=$(wc -w < "$text_file" | tr -d ' ')
    echo -e "${BLUE}  Word count: $words${NC}" >&2

    if (( words < 1100 || words > 1400 )); then
        echo -e "${RED}❌ Error: $story_id wordcount $words outside 1100–1400 range${NC}" >&2
        echo -e "${RED}   Failed wordcount validation. Aborting.${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}  ✓ Wordcount validation passed ($words words)${NC}" >&2

    # Generate title
    local title=$(generate_title "$mood" "$story_text")
    echo -e "${BLUE}  Title: $title${NC}" >&2

    # ELEVENLABS SAFETY GUARD
    local char_count=$(printf "%s" "$story_text" | wc -c | tr -d ' ')
    local audio_generated=false

    if elevenlabs_check_and_log "$story_id" "$char_count" "5"; then
        local http_code=$(elevenlabs_call "$story_text" "$audio_file" "$ELEVENLABS_VOICE_ID" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" ]]; then
            local file_size=$(ls -lh "$audio_file" | awk '{print $5}')
            echo -e "${GREEN}✓ Generated: $story_id ($words words, $file_size audio)${NC}" >&2
            audio_generated=true
        else
            echo -e "${RED}✗ API Error (HTTP $http_code)${NC}" >&2
            if [[ -f "$audio_file" ]]; then
                local error_msg=$(jq -r '.detail.message // .message // empty' < "$audio_file" 2>/dev/null || cat "$audio_file")
                echo -e "${RED}Error: $error_msg${NC}" >&2
                rm "$audio_file"
            fi
            audio_file=""
        fi
    else
        echo -e "${YELLOW}⚠ Audio generation skipped for $story_id${NC}" >&2
        audio_file=""
    fi

    # Add to manifest (with or without audio)
    local audio_path
    if [[ -n "$audio_file" ]]; then
        audio_path="${story_id}.mp3"
    else
        audio_path="null"
    fi

    local new_entry=$(jq -n \
        --arg id "$story_id" \
        --arg title "$title" \
        --arg mood "$mood" \
        --arg audio "$audio_path" \
        --arg text "${story_id}.txt" \
        '{
            storyId: $id,
            title: $title,
            mood: $mood,
            length: 5,
            faithTradition: "Protestant",
            storytellingMode: "creative",
            kidFriendly: true,
            audioFilePath: (if $audio == "null" then null else $audio end),
            textFilePath: $text
        }')

    MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq ".parables += [$new_entry]")

    if [[ "$audio_generated" != true ]]; then
        return 1
    fi
}

# Generate 5 parables (one per mood)
MOODS=("joyful" "weary" "anxious" "hurting" "neutral")

# Compute base story number once to avoid collisions
BASE_NUM=$(echo "$MANIFEST_JSON" | jq '.parables | length')

echo -e "${BLUE}Generating 5 kid-friendly parables (5min each, 1100-1300 words)...${NC}" >&2
echo "" >&2

for i in "${!MOODS[@]}"; do
    generate_parable "${MOODS[$i]}" "$i" || exit 1
    sleep 2  # Be nice to ElevenLabs API
done

# Save manifest
echo "$MANIFEST_JSON" | jq '.' > "$MANIFEST_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Kid-friendly batch complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total parables: $(echo "$MANIFEST_JSON" | jq '.parables | length')"
echo -e "Log saved: $LOG_FILE"
echo ""
