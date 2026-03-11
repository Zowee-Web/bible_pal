#!/usr/bin/env bash
# =============================================================================
# generate_v2_batch.sh — Bible PAL V2 Story Batch Generator
# =============================================================================
# Generates 44 production stories (16 base stories × 3 lengths) to fill the
# complete WEB mood×length×mode×audience matrix.
#
# USAGE:
#   ./generate_v2_batch.sh [OPTIONS]
#
# OPTIONS:
#   --text-only       Generate text files only (no audio, no ElevenLabs calls)
#   --audio-only      Generate audio for existing text files only
#   --story ID        Generate only the specified base story ID (e.g., --story 504)
#   --dry-run         Show what would be generated without doing anything
#   --skip-existing   Skip stories that already have text files
#
# PREREQUISITES:
#   - Ollama running with mistral-nemo model loaded (for Creative stories)
#     Fallback chain: llama3.1:8b → qwen2.5:7b → gemma:7b
#   - .env with OPENAI_API_KEY (for Traditional stories — gpt-4.1)
#   - .env with ELEVENLABS_API_KEY (for audio generation)
#   - jq installed
#
# ENGINE POLICY (STORY_FACTORY.md Section 0 — LOCKED):
#   Traditional → OpenAI gpt-4.1 ONLY (hard fail otherwise)
#   Creative    → mistral-nemo via Ollama (local, with fallback chain)
#
# =============================================================================

set -uo pipefail  # No -e: individual errors handled per-story

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
STORIES_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$STORIES_DIR/manifest.json"

# Source shared utilities
source "$SCRIPT_DIR/story_calibration.sh"
source "$SCRIPT_DIR/voice_selector.sh"
source "$PROJECT_ROOT/scripts/lib/router_client.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl required${NC}" >&2; exit 1; }

# Load .env
if [[ -f "$ENV_FILE" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
        export "$key=$value"
    done < "$ENV_FILE"
fi

# =============================================================================
# Batch Definition — All 16 base stories
# =============================================================================
# Format: ID|MODE|KID|MOOD|VOICE|BIBLE_REF|BIBLE_KEY
# For creative stories, BIBLE_REF and BIBLE_KEY are empty.

BATCH_STORIES=(
    # Creative Adult WEB
    "504|creative|false|joyful|VOICE_MIRIAM_JOYFUL||"
    "505|creative|false|anxious|VOICE_MARCUS_ANCHOR||"
    "506|creative|false|hurting|VOICE_RUTH_COMFORT||"
    "507|creative|false|neutral|VOICE_ELIJAH_SAGE||"
    # Creative Kid WEB
    "508|creative|true|weary|VOICE_MARY_PONDER||"
    "509|creative|true|anxious|VOICE_DAVID_SHEPHERD||"
    "510|creative|true|hurting|VOICE_HANNAH_HOPE||"
    "511|creative|true|neutral|VOICE_PRISCILLA_TEACHER||"
    # Traditional Adult WEB
    "809|traditional|false|anxious|VOICE_NOAH_PATIENT|Mark 4:35-41|jesus_calms_storm"
    "810|traditional|false|hurting|VOICE_DEBORAH_WISE|John 4:4-26|woman_at_well"
    "811|traditional|false|neutral|VOICE_PETER_BOLD|Luke 24:13-35|road_to_emmaus"
    # Traditional Kid WEB
    "812|traditional|true|joyful|VOICE_LYDIA_GRACIOUS|Luke 15:3-7|lost_sheep"
    "813|traditional|true|anxious|VOICE_ESTHER_BRAVE|Mark 4:35-41|jesus_calms_storm"
    "814|traditional|true|hurting|VOICE_MARTHA_CARING|John 4:4-26|woman_at_well"
    "815|traditional|true|neutral|VOICE_BARNABAS_ENCOURAGER|Luke 24:13-35|road_to_emmaus"
)

# 812 is special — only full and long (short already exists as parable_502)
STORY_812_LENGTHS=("full" "long")
DEFAULT_LENGTHS=("short" "full" "long")

# =============================================================================
# Reflection Templates (deterministic, no LLM needed)
# =============================================================================

get_reflection_text() {
    local mood="$1"
    local is_kid="$2"

    if [[ "$is_kid" == "true" ]]; then
        case "$mood" in
            joyful)  echo "This story shows that good things can happen when we share and care for others. Even one small kindness matters." ;;
            weary)   echo "This story shows that it is okay to rest when we are tired. Even one small rest can help." ;;
            anxious) echo "This story shows that even when things feel scary, we are not alone. Even one small brave thing counts." ;;
            hurting) echo "This story shows that being kind matters, even when things feel unfair. Even one small kindness helps." ;;
            neutral) echo "This story shows that every day has moments worth noticing. Even one small thing can be special." ;;
            *)       echo "This story shows that every day has moments worth noticing. Even one small thing can be special." ;;
        esac
    else
        case "$mood" in
            joyful)  echo "Stories of joy often reflect moments when gratitude and connection come together. These narratives show how small blessings can accumulate into a sense of abundance. And even a small step forward can be enough for today." ;;
            weary)   echo "Weariness in stories often looks like carrying burdens over long stretches. These narratives show that rest and renewal are part of the natural rhythm of life. And even a small step forward can be enough for today." ;;
            anxious) echo "Stories about worry often reflect the tension between what we can control and what we cannot. These narratives show that peace sometimes comes from releasing our grip on outcomes. And even a small step forward can be enough for today." ;;
            hurting) echo "Pain in stories often looks like walking through seasons of loss or disappointment. These narratives show that sorrow and hope can exist together. And even a small step forward can be enough for today." ;;
            neutral) echo "Stories of ordinary days often reflect the steady rhythm of daily faithfulness. These narratives show that meaning can be found in quiet, unremarkable moments. And even a small step forward can be enough for today." ;;
            *)       echo "Stories of ordinary days often reflect the steady rhythm of daily faithfulness. These narratives show that meaning can be found in quiet, unremarkable moments. And even a small step forward can be enough for today." ;;
        esac
    fi
}

# =============================================================================
# Prompt Template Builder
# =============================================================================

build_prompt() {
    local mode="$1"
    local mood="$2"
    local length_bucket="$3"
    local is_kid="$4"
    local bible_ref="$5"
    local bible_key="${6:-}"

    local template_file
    if [[ "$mode" == "creative" ]]; then
        template_file="$SCRIPT_DIR/prompts/creative_prompt.template.txt"
    else
        template_file="$SCRIPT_DIR/prompts/traditional_prompt.template.txt"
    fi

    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}Error: Template not found: $template_file${NC}" >&2
        return 1
    fi

    # Read template and substitute variables
    local prompt
    prompt=$(cat "$template_file")
    prompt="${prompt//\{\{MOOD\}\}/$mood}"
    prompt="${prompt//\{\{LENGTH_BUCKET\}\}/$length_bucket}"
    prompt="${prompt//\{\{LANGUAGE_STYLE\}\}/WEB}"
    prompt="${prompt//\{\{BIBLE_SOURCE_REF\}\}/$bible_ref}"

    # Inject narrative anchors from story seed (Traditional mode only)
    local anchors_block=""
    local seeds_file="$SCRIPT_DIR/seeds/traditional_seeds.json"
    if [[ "$mode" == "traditional" && -n "$bible_key" && -f "$seeds_file" ]]; then
        local seed
        seed=$(jq -r --arg key "$bible_key" '.[$key] // empty' "$seeds_file" 2>/dev/null)
        if [[ -n "$seed" ]]; then
            local chars setting conflict tp theme sensory
            chars=$(echo "$seed" | jq -r '.characters | join(", ")')
            setting=$(echo "$seed" | jq -r '.setting')
            conflict=$(echo "$seed" | jq -r '.conflict')
            tp=$(echo "$seed" | jq -r '.turning_point')
            theme=$(echo "$seed" | jq -r '.theme')
            sensory=$(echo "$seed" | jq -r '.sensory_atmosphere // empty')
            anchors_block="## NARRATIVE ANCHORS
Characters: $chars
Setting: $setting
Conflict: $conflict
Turning point: $tp
Theme: $theme"
            if [[ -n "$sensory" ]]; then
                anchors_block="$anchors_block
Sensory atmosphere: $sensory"
            fi
            anchors_block="$anchors_block
"
        fi
    fi
    prompt="${prompt//\{\{NARRATIVE_ANCHORS\}\}/$anchors_block}"

    # Inject scene blueprint for full/long stories (skip for short)
    # Long stories get expanded pacing notes to allow each scene to breathe
    local blueprint_block=""
    local pacing_note=""
    if [[ "$length_bucket" == "long" ]]; then
        pacing_note="Let each scene breathe — use sensory detail, transitions, and unhurried pacing."
    fi
    if [[ "$length_bucket" == "full" || "$length_bucket" == "long" ]]; then
        if [[ "$mode" == "traditional" && -n "$conflict" && -n "$tp" ]]; then
            # Traditional with seed: use conflict and turning point from seed
            blueprint_block="
## SCENE BLUEPRINT (follow this pacing)
Scene 1 – Establish the setting and characters
Scene 2 – $conflict
Scene 3 – Tension deepens
Scene 4 – $tp
Scene 5 – Resolution and scriptural conclusion"
        elif [[ "$mode" == "traditional" ]]; then
            blueprint_block="
## SCENE BLUEPRINT (follow this pacing)
Scene 1 – Establish the setting and characters
Scene 2 – Tension or need appears
Scene 3 – Conflict deepens
Scene 4 – Turning point from scripture
Scene 5 – Resolution and scriptural conclusion"
        else
            # Creative mode
            blueprint_block="
## SCENE BLUEPRINT (follow this pacing)
Scene 1 – Ground the listener in setting and character
Scene 2 – Tension or need appears
Scene 3 – Conflict deepens
Scene 4 – Turning point or moment of clarity
Scene 5 – Quiet resolution with gentle hope"
        fi
        if [[ -n "$pacing_note" ]]; then
            blueprint_block="$blueprint_block
$pacing_note"
        fi
        blueprint_block="$blueprint_block
"
    fi
    prompt="${prompt//\{\{SCENE_BLUEPRINT\}\}/$blueprint_block}"

    # Remove conditional KJV block (we're WEB only)
    prompt=$(echo "$prompt" | sed '/{{#if LANGUAGE_STYLE == KJV}}/,/{{\/if}}/d')

    # Add kid-safe constraints if needed
    if [[ "$is_kid" == "true" ]]; then
        prompt="$prompt

## ADDITIONAL: KID-FRIENDLY REQUIREMENTS
- Write for a child aged 5-9
- Use simple words and short sentences (average 12 words or fewer)
- Avoid frightening, violent, or complex emotional content
- Focus on wonder, kindness, safety, and gentle lessons
- No references to death, war, weapons, or monsters
- Characters should feel safe and cared for throughout"
    fi

    echo "$prompt"
}

# =============================================================================
# Creative Model Selection
# =============================================================================
# Primary: mistral-nemo (strongest storytelling model at 12B params)
# Fallback chain: llama3.1:8b → qwen2.5:7b → gemma:7b
#
# All creative lengths use mistral-nemo by default.
# Mixtral (8x7b) available as optional long-story model if installed.

CREATIVE_MODEL_PRIMARY="mistral-nemo"
CREATIVE_MODEL_FALLBACK="llama3.1:8b"
CREATIVE_MODEL_FALLBACK2="qwen2.5:7b"
CREATIVE_MODEL_LEGACY="gemma:7b"

# Returns the best available creative model for a given length bucket.
# Tries the Universal Model Router first (server/model_router/); if unavailable
# or errored, falls back to the original hardcoded logic. See ADR-016.
# NOTE: Uses grep without -q to avoid pipefail+SIGPIPE race condition
get_creative_model() {
    local length_bucket="${1:-short}"

    # --- Try Universal Model Router first ---
    if command -v python3 >/dev/null 2>&1 && \
       [[ -f "${SCRIPT_DIR}/../server/model_router/cli.py" ]]; then
        local router_result
        router_result=$(cd "${SCRIPT_DIR}/.." && python3 -m server.model_router.cli resolve creative_story 2>/dev/null) || true
        if [[ -n "$router_result" ]]; then
            local model
            model=$(echo "$router_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model',''))" 2>/dev/null) || true
            if [[ -n "$model" ]]; then
                local is_fb
                is_fb=$(echo "$router_result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_fallback',False))" 2>/dev/null) || true
                if [[ "$is_fb" == "True" ]]; then
                    echo -e "${YELLOW}  Router selected (fallback): $model${NC}" >&2
                else
                    echo -e "${BLUE}  Router selected: $model${NC}" >&2
                fi
                echo "$model"
                return 0
            fi
        fi
        echo -e "${YELLOW}  Router unavailable, using hardcoded fallback chain${NC}" >&2
    fi

    # --- Hardcoded fallback (original logic, preserved for backward compat) ---
    local model_list
    model_list=$(ollama list 2>/dev/null) || true

    # Check if primary model is available
    if echo "$model_list" | grep "^${CREATIVE_MODEL_PRIMARY}" >/dev/null 2>&1; then
        echo "$CREATIVE_MODEL_PRIMARY"
        return 0
    fi

    # Fallback chain
    if echo "$model_list" | grep "^${CREATIVE_MODEL_FALLBACK}" >/dev/null 2>&1; then
        echo -e "${YELLOW}  Model fallback: $CREATIVE_MODEL_PRIMARY unavailable, using $CREATIVE_MODEL_FALLBACK${NC}" >&2
        echo "$CREATIVE_MODEL_FALLBACK"
        return 0
    fi

    if echo "$model_list" | grep "^${CREATIVE_MODEL_FALLBACK2}" >/dev/null 2>&1; then
        echo -e "${YELLOW}  Model fallback: using $CREATIVE_MODEL_FALLBACK2${NC}" >&2
        echo "$CREATIVE_MODEL_FALLBACK2"
        return 0
    fi

    echo -e "${YELLOW}  Model fallback: using legacy $CREATIVE_MODEL_LEGACY${NC}" >&2
    echo "$CREATIVE_MODEL_LEGACY"
}

# =============================================================================
# Text Generation via Ollama HTTP API
# =============================================================================

generate_text_ollama() {
    local prompt="$1"
    local num_predict="${2:-4096}"  # Token limit: ~3000 tokens = ~2000 words
    local model="${3:-$CREATIVE_MODEL_PRIMARY}"  # Model override (default: mistral-nemo)
    local max_retries=2
    local attempt=0

    while [[ $attempt -le $max_retries ]]; do
        attempt=$((attempt + 1))

        local response
        response=$(curl -s --connect-timeout 10 --max-time 600 \
            -X POST "http://localhost:11434/api/generate" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson np "$num_predict" \
                '{model: $model, prompt: $prompt, stream: false, options: {num_predict: $np, temperature: 0.8}}')" \
            2>/dev/null)

        if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
            echo -e "${YELLOW}  Attempt $attempt failed (no response), retrying...${NC}" >&2
            sleep 3
            continue
        fi

        # Extract generated text
        local text
        text=$(echo "$response" | jq -r '.response // empty')

        if [[ -n "$text" ]]; then
            # Clean ANSI escapes, Braille spinner chars, artifacts
            text=$(echo "$text" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g')
            text=$(echo "$text" | sed $'s/\x1b\\[?[0-9]*[a-z]//g')
            text=$(echo "$text" | tr -d '\r')
            text=$(echo "$text" | sed 's/\[K//g; s/\[?[0-9]*[hl]//g')
            text=$(echo "$text" | sed 's/[⠀-⣿]//g')
            text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            echo "$text"
            return 0
        fi

        echo -e "${YELLOW}  Attempt $attempt: empty response, retrying...${NC}" >&2
        sleep 3
    done

    echo -e "${RED}  All $max_retries attempts failed${NC}" >&2
    return 1
}

# =============================================================================
# Text Generation via OpenAI Responses API (Traditional stories ONLY)
# =============================================================================

generate_text_openai() {
    local prompt="$1"
    local max_tokens="${2:-4096}"
    local max_retries=2
    local attempt=0

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo -e "${RED}  FATAL: OPENAI_API_KEY not set. Traditional stories require OpenAI gpt-4.1.${NC}" >&2
        return 1
    fi

    while [[ $attempt -le $max_retries ]]; do
        attempt=$((attempt + 1))

        local response
        response=$(curl -s --connect-timeout 10 --max-time 600 \
            -X POST "https://api.openai.com/v1/responses" \
            -H "Authorization: Bearer ${OPENAI_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg model "gpt-4.1" --arg input "$prompt" --argjson max_tokens "$max_tokens" \
                '{model: $model, input: $input, max_output_tokens: $max_tokens}')" \
            2>/dev/null)

        local curl_status=$?
        if [[ $curl_status -ne 0 ]] || [[ -z "$response" ]]; then
            echo -e "${YELLOW}  Attempt $attempt failed (no response), retrying...${NC}" >&2
            sleep 3
            continue
        fi

        # Check for API errors
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo -e "${RED}  Attempt $attempt: API error: $error_msg${NC}" >&2
            # Non-transient errors — abort immediately
            local error_type
            error_type=$(echo "$response" | jq -r '.error.type // empty' 2>/dev/null)
            if [[ "$error_type" == "authentication_error" ]] || [[ "$error_type" == "invalid_request_error" ]]; then
                return 1
            fi
            sleep 3
            continue
        fi

        # Extract text from Responses API output
        local text
        text=$(echo "$response" | jq -r '.output[0].content[0].text // empty' 2>/dev/null)

        if [[ -n "$text" ]]; then
            text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            echo "$text"
            return 0
        fi

        echo -e "${YELLOW}  Attempt $attempt: empty response, retrying...${NC}" >&2
        sleep 3
    done

    echo -e "${RED}  All $max_retries attempts failed for OpenAI${NC}" >&2
    return 1
}

# =============================================================================
# Engine Routing — STORY_FACTORY.md Section 0 (LOCKED)
# =============================================================================

# Returns the engine name for a given storytelling mode
get_engine_for_mode() {
    local mode="$1"
    case "$mode" in
        traditional) echo "openai" ;;
        creative)    echo "ollama" ;;
        *)
            echo -e "${RED}  FATAL: Unknown mode '$mode'. Aborting.${NC}" >&2
            exit 1
            ;;
    esac
}

# Dispatches text generation to the correct engine based on mode
generate_text() {
    local mode="$1"
    local prompt="$2"
    local num_predict="$3"
    local length_bucket="${4:-short}"  # Used for creative model selection
    local engine
    engine=$(get_engine_for_mode "$mode")

    case "$engine" in
        openai)
            generate_text_openai "$prompt" "$num_predict"
            ;;
        ollama)
            local model
            model=$(get_creative_model "$length_bucket")
            echo -e "${BLUE}  Ollama model: $model${NC}" >&2
            generate_text_ollama "$prompt" "$num_predict" "$model"
            ;;
        *)
            echo -e "${RED}  FATAL: Unknown engine '$engine'${NC}" >&2
            return 1
            ;;
    esac
}

# Returns the createdByModel value for meta.json based on mode
get_model_label_for_mode() {
    local mode="$1"
    case "$mode" in
        traditional) echo "gpt-4.1" ;;
        creative)
            local model
            model=$(get_creative_model "short" 2>/dev/null)
            echo "$model"
            ;;
        *)           echo "unknown" ;;
    esac
}

# =============================================================================
# Title Generation via Model Router
# =============================================================================

generate_title_ollama() {
    local story_text="$1"

    local prompt="Read this story and create a short, evocative title (3-6 words) that captures its essence. Return ONLY the title, nothing else.

Story:
$(echo "$story_text" | head -20)

Title:"

    local raw_text
    raw_text=$(router_generate "story_title" "$prompt" 0.8 64 30) || {
        echo "Untitled Story"
        return 1
    }

    local title
    title=$(echo "$raw_text" \
        | head -1 \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | sed 's/^"//;s/"$//' \
        | sed 's/^\*\*//;s/\*\*$//')

    if [[ -z "$title" ]] || [[ ${#title} -gt 80 ]]; then
        echo "Untitled Story"
    else
        echo "$title"
    fi
}

# =============================================================================
# Audio Generation via ElevenLabs
# =============================================================================

generate_audio_elevenlabs() {
    local text="$1"
    local voice_key="$2"
    local output_file="$3"

    local voice_id
    voice_id=$(get_voice_id "$voice_key")
    if [[ -z "$voice_id" || "$voice_id" == "null" ]]; then
        echo -e "${RED}  Error: Unknown voice key $voice_key${NC}" >&2
        return 1
    fi

    local char_count=${#text}
    echo -e "${BLUE}  Audio: ${char_count} chars → $output_file${NC}"

    # Source ElevenLabs guard for safety
    if [[ -f "$SCRIPT_DIR/elevenlabs_guard.sh" ]]; then
        source "$SCRIPT_DIR/elevenlabs_guard.sh"
    fi

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -X POST "https://api.elevenlabs.io/v1/text-to-speech/${voice_id}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg text "$text" '{
            text: $text,
            model_id: "eleven_turbo_v2_5",
            voice_settings: {
                stability: 0.6,
                similarity_boost: 0.8,
                style: 0.0,
                use_speaker_boost: true
            }
        }')" \
        -o "$output_file")

    if [[ "$http_code" == "200" ]] && [[ -s "$output_file" ]]; then
        local size
        size=$(ls -lh "$output_file" | awk '{print $5}')
        echo -e "${GREEN}  ✓ Audio: $size${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Audio failed: HTTP $http_code${NC}" >&2
        rm -f "$output_file"
        return 1
    fi
}

# =============================================================================
# Process a Single Base Story
# =============================================================================

process_story() {
    local story_def="$1"

    # Parse definition
    IFS='|' read -r story_id mode is_kid mood voice_key bible_ref bible_key <<< "$story_def"

    local story_dir
    if [[ "$mode" == "creative" ]]; then
        story_dir="$STORIES_DIR/creative/$story_id"
    else
        story_dir="$STORIES_DIR/traditional/$story_id"
    fi

    # Determine lengths for this story
    local lengths=("${DEFAULT_LENGTHS[@]}")
    if [[ "$story_id" == "812" ]]; then
        lengths=("${STORY_812_LENGTHS[@]}")
    fi

    local audience="adult"
    [[ "$is_kid" == "true" ]] && audience="kid"

    # --- ENGINE GATE (STORY_FACTORY.md Section 0 — LOCKED) ---
    local expected_engine
    expected_engine=$(get_engine_for_mode "$mode")
    local expected_model
    expected_model=$(get_model_label_for_mode "$mode")

    # Validate engine prerequisites
    if [[ "$expected_engine" == "openai" ]] && [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo -e "${RED}FATAL: Story $story_id is Traditional but OPENAI_API_KEY is not set.${NC}"
        echo -e "${RED}Traditional stories MUST use gpt-4.1 (STORY_FACTORY.md Section 0).${NC}"
        echo -e "${RED}Skipping story $story_id entirely.${NC}"
        return 1
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Story $story_id: $mode $audience $mood${NC}"
    echo -e "${CYAN}Engine: $expected_engine ($expected_model)${NC}"
    echo -e "${CYAN}Voice: $voice_key | Lengths: ${lengths[*]}${NC}"
    [[ -n "$bible_ref" ]] && echo -e "${CYAN}Scripture: $bible_ref ($bible_key)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    mkdir -p "$story_dir"

    # --- PHASE 1: Generate text for each length ---
    if [[ "$AUDIO_ONLY" != "true" ]]; then
        for length in "${lengths[@]}"; do
            local text_file="$story_dir/story_${story_id}_${mode}_web_${length}.txt"

            if [[ "$SKIP_EXISTING" == "true" ]] && [[ -s "$text_file" ]]; then
                # Check if existing file meets mode-specific word count
                local existing_wc
                existing_wc=$(wc -w < "$text_file" | tr -d ' ')
                local min_check
                min_check=$(get_min_words_for_mode "$length" "$mode" "$is_kid")
                if [[ $existing_wc -ge $min_check ]]; then
                    echo -e "${YELLOW}  Skipping $length text (exists, ${existing_wc}w)${NC}"
                    continue
                else
                    echo -e "${YELLOW}  Re-generating $length text (${existing_wc}w < ${min_check}w min)${NC}"
                fi
            fi

            echo -e "${BLUE}  Generating $length text...${NC}"
            local min_wc max_wc
            min_wc=$(get_min_words_for_mode "$length" "$mode" "$is_kid")
            max_wc=$(get_max_words_for_mode "$length" "$mode" "$is_kid")

            # Token budget: ~1.5 tokens per word, plus overhead
            local num_predict
            case "$length" in
                short) num_predict=1200 ;;
                full)  num_predict=2400 ;;
                long)  num_predict=4096 ;;
            esac

            # Retry loop for word count enforcement
            local wc_attempt=0
            local max_wc_attempts=3
            local text=""
            local wc=0

            while [[ $wc_attempt -lt $max_wc_attempts ]]; do
                wc_attempt=$((wc_attempt + 1))

                local prompt
                prompt=$(build_prompt "$mode" "$mood" "$length" "$is_kid" "$bible_ref" "$bible_key")

                # Add explicit minimum word count instruction
                prompt="$prompt

CRITICAL: This story MUST be at least $min_wc words and no more than $max_wc words. Write a complete, detailed story with rich descriptions and fully developed scenes. Do not stop early."

                text=$(generate_text "$mode" "$prompt" "$num_predict" "$length" 2>/dev/null) || true

                if [[ -z "$text" ]]; then
                    echo -e "${RED}  ✗ Attempt $wc_attempt: text generation returned empty${NC}"
                    sleep 3
                    continue
                fi

                wc=$(echo "$text" | wc -w | tr -d ' ')
                echo -e "  Attempt $wc_attempt: $wc words (need $min_wc-$max_wc)"

                if [[ $wc -ge $min_wc ]]; then
                    break  # Good enough
                fi

                # If too short, try extending by feeding partial text back
                if [[ $wc -lt $min_wc ]] && [[ $wc_attempt -lt $max_wc_attempts ]]; then
                    echo -e "${YELLOW}  Too short ($wc < $min_wc), attempting continuation...${NC}"
                    local words_remaining=$((min_wc - wc))
                    local continue_prompt="You are continuing a story that was cut short. The story so far is ${wc} words and needs to reach at least ${min_wc} words total. Write approximately ${words_remaining} more words.

IMPORTANT RULES FOR CONTINUATION:
- Pick up exactly where the story left off — do NOT restart or summarize
- Maintain the same characters, setting, tone, and narrative voice
- Write continuous prose paragraphs (no headings, no bullets)
- Write for spoken narration — keep sentences under 22 words
- Build toward a satisfying resolution with quiet hope
- Do NOT repeat any content from the existing story

STORY SO FAR:
$text

CONTINUE THE STORY FROM HERE:"
                    local continuation
                    continuation=$(generate_text "$mode" "$continue_prompt" "$num_predict" "$length" 2>/dev/null) || true
                    if [[ -n "$continuation" ]]; then
                        text="$text

$continuation"
                        wc=$(echo "$text" | wc -w | tr -d ' ')
                        echo -e "  After continuation: $wc words"
                        if [[ $wc -ge $min_wc ]]; then
                            break
                        fi
                    fi
                fi

                sleep 2
            done

            if [[ -z "$text" ]]; then
                echo -e "${RED}  ✗ Text generation failed for $length after $max_wc_attempts attempts${NC}"
                continue
            fi

            if [[ $wc -lt $min_wc ]]; then
                echo -e "${RED}  FAIL: Word count $wc below minimum $min_wc after $max_wc_attempts attempts${NC}"
                echo -e "${RED}  Aborting $length variant for story $story_id — no file saved${NC}"
                rm -f "$text_file"
                continue
            fi

            # Warn if over max (save as-is — could be trimmed in future)
            if [[ $wc -gt $max_wc ]]; then
                echo -e "${YELLOW}  ⚠ Word count $wc exceeds max $max_wc (saving as-is)${NC}"
            fi

            echo "$text" > "$text_file"
            echo -e "${GREEN}  ✓ Saved: $text_file ($wc words)${NC}"

            # Generate title from first length variant
            if [[ "$length" == "${lengths[0]}" ]]; then
                local title
                title=$(generate_title_ollama "$text")
                echo -e "  Title: ${GREEN}$title${NC}"
                echo "$title" > "$story_dir/.title"
            fi

            # Kid-safe validation
            if [[ "$is_kid" == "true" ]] && [[ -f "$SCRIPT_DIR/kid_bedtime_validator.sh" ]]; then
                echo -e "  Running kid-safe validation..."
                if bash "$SCRIPT_DIR/kid_bedtime_validator.sh" "$text_file" >/dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ Kid-safe: PASS${NC}"
                else
                    echo -e "${YELLOW}  ⚠ Kid-safe: FAIL (review needed)${NC}"
                fi
            fi

            sleep 2  # Pace Ollama requests
        done

        # --- PHASE 2: Create reflection text ---
        local reflection_file="$story_dir/reflection_${story_id}_${mode}_web.txt"
        local reflection_text
        reflection_text=$(get_reflection_text "$mood" "$is_kid")
        echo "$reflection_text" > "$reflection_file"
        echo -e "${GREEN}  ✓ Reflection text saved${NC}"
    fi

    # --- PHASE 3: Generate audio (if enabled) ---
    if [[ "$TEXT_ONLY" != "true" ]] && [[ "${AUDIO_ENABLED:-0}" == "1" ]]; then
        if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
            echo -e "${YELLOW}  ⚠ Skipping audio: no API key${NC}"
            return 0
        fi

        for length in "${lengths[@]}"; do
            local text_file="$story_dir/story_${story_id}_${mode}_web_${length}.txt"
            local audio_file="$story_dir/audio_${story_id}_story_${length}.mp3"

            if [[ ! -s "$text_file" ]]; then
                echo -e "${YELLOW}  ⚠ No text for $length, skipping audio${NC}"
                continue
            fi

            # --- AUDIO GATE: Validate word count before spending ElevenLabs credits ---
            local text_wc
            text_wc=$(wc -w < "$text_file" | tr -d ' ')
            local audio_min audio_max
            audio_min=$(get_min_words_for_mode "$length" "$mode" "$is_kid")
            audio_max=$(get_max_words_for_mode "$length" "$mode" "$is_kid")
            if [[ $text_wc -lt $audio_min ]] || [[ $text_wc -gt $audio_max ]]; then
                echo -e "${RED}  AUDIO GATE FAIL: $length text has $text_wc words (need $audio_min-$audio_max)${NC}"
                echo -e "${RED}  Skipping audio generation to avoid wasting ElevenLabs credits${NC}"
                continue
            fi

            if [[ "$SKIP_EXISTING" == "true" ]] && [[ -s "$audio_file" ]]; then
                echo -e "${YELLOW}  Skipping $length audio (exists)${NC}"
                continue
            fi

            local text
            text=$(cat "$text_file")
            generate_audio_elevenlabs "$text" "$voice_key" "$audio_file" || true
            sleep 2  # Pace ElevenLabs requests
        done

        # Reflection audio
        local reflection_file="$story_dir/reflection_${story_id}_${mode}_web.txt"
        local reflection_audio="$story_dir/audio_${story_id}_reflection.mp3"

        if [[ -s "$reflection_file" ]] && { [[ "$SKIP_EXISTING" != "true" ]] || [[ ! -s "$reflection_audio" ]]; }; then
            local reflection_text
            reflection_text=$(cat "$reflection_file")
            generate_audio_elevenlabs "$reflection_text" "$voice_key" "$reflection_audio" || true
            sleep 1
        fi
    elif [[ "$TEXT_ONLY" != "true" ]]; then
        echo -e "${YELLOW}  ⚠ Audio skipped: set AUDIO_ENABLED=1 in .env${NC}"
    fi

    # --- PHASE 4: Validate/update meta.json (createdByModel + generationContractVersion) ---
    local meta_file="$story_dir/meta_${story_id}.json"
    if [[ -f "$meta_file" ]]; then
        # Validate createdByModel matches expected engine
        local meta_model
        meta_model=$(jq -r '.createdByModel // empty' "$meta_file")
        if [[ -n "$meta_model" ]] && [[ "$meta_model" != "$expected_model" ]]; then
            echo -e "${RED}  META MISMATCH: createdByModel='$meta_model' but expected '$expected_model'${NC}"
            echo -e "${YELLOW}  Updating meta.json to reflect correct engine...${NC}"
        fi
        # Update createdByModel and add generationContractVersion
        local updated_meta
        updated_meta=$(jq --arg model "$expected_model" --arg contract "STORY_FACTORY_v2.3" \
            '.createdByModel = $model | .generationContractVersion = $contract' "$meta_file")
        echo "$updated_meta" > "$meta_file"
        echo -e "${GREEN}  ✓ meta.json: createdByModel=$expected_model, contract=STORY_FACTORY_v2.3${NC}"
    else
        echo -e "${YELLOW}  ⚠ No meta.json found for story $story_id (create separately)${NC}"
    fi

    echo ""
}

# =============================================================================
# Manifest Update
# =============================================================================

update_manifest() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Updating manifest.json...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local manifest
    manifest=$(cat "$MANIFEST_FILE")
    local added=0

    for story_def in "${BATCH_STORIES[@]}"; do
        IFS='|' read -r story_id mode is_kid mood voice_key bible_ref bible_key <<< "$story_def"

        local story_dir
        if [[ "$mode" == "creative" ]]; then
            story_dir="$STORIES_DIR/creative/$story_id"
        else
            story_dir="$STORIES_DIR/traditional/$story_id"
        fi

        local lengths=("${DEFAULT_LENGTHS[@]}")
        [[ "$story_id" == "812" ]] && lengths=("${STORY_812_LENGTHS[@]}")

        # Read title
        local title="Untitled Story"
        if [[ -f "$story_dir/.title" ]]; then
            title=$(cat "$story_dir/.title")
        fi

        # Emotional tags by mood
        local emotional_tags
        case "$mood" in
            joyful)  emotional_tags='["grateful"]' ;;
            weary)   emotional_tags='["overwhelmed"]' ;;
            anxious) emotional_tags='["anxious"]' ;;
            hurting) emotional_tags='["sad", "grief"]' ;;
            neutral) emotional_tags='["waiting"]' ;;
            *)       emotional_tags='[]' ;;
        esac

        local rel_dir
        if [[ "$mode" == "creative" ]]; then
            rel_dir="creative/$story_id"
        else
            rel_dir="traditional/$story_id"
        fi

        for length in "${lengths[@]}"; do
            local minutes
            case "$length" in
                short) minutes=5 ;;
                full)  minutes=15 ;;
                long)  minutes=20 ;;
            esac

            # Build storyId string
            local manifest_id
            if [[ "$is_kid" == "true" ]]; then
                manifest_id="story_${story_id}_${mood}_${length}_kid_${mode}"
            else
                manifest_id="story_${story_id}_${mood}_${length}_${mode}"
            fi

            # Check if already in manifest
            local exists
            exists=$(echo "$manifest" | jq -r --arg id "$manifest_id" '[.parables[] | select(.storyId == $id)] | length')
            if [[ "$exists" != "0" ]]; then
                continue
            fi

            # Check for text file
            local text_file_name="story_${story_id}_${mode}_web_${length}.txt"
            local audio_file_name="audio_${story_id}_story_${length}.mp3"
            local reflection_audio_name="audio_${story_id}_reflection.mp3"

            # Build text/audio paths (relative to assets/stories/)
            local text_path="${rel_dir}/${text_file_name}"
            local audio_path="${rel_dir}/${audio_file_name}"
            local reflection_path="${rel_dir}/${reflection_audio_name}"

            # Skip manifest entry if text file does not exist (generation failed)
            if [[ ! -s "$STORIES_DIR/$text_path" ]]; then
                echo -e "${YELLOW}  Skipping manifest entry for $manifest_id (no text file)${NC}"
                continue
            fi

            # Check if audio file exists
            local actual_audio="null"
            [[ -s "$STORIES_DIR/$audio_path" ]] && actual_audio="\"$audio_path\""

            local actual_text="\"$text_path\""

            local actual_reflection="null"
            [[ -s "$STORIES_DIR/$reflection_path" ]] && actual_reflection="\"$reflection_path\""

            # Build manifest entry
            local entry
            if [[ -n "$bible_ref" ]]; then
                entry=$(jq -n \
                    --arg id "$manifest_id" \
                    --arg title "$title" \
                    --arg mood "$mood" \
                    --argjson tags "$emotional_tags" \
                    --argjson length "$minutes" \
                    --arg mode "$mode" \
                    --argjson kid "$([[ "$is_kid" == "true" ]] && echo true || echo false)" \
                    --argjson audio "$actual_audio" \
                    --argjson text "$actual_text" \
                    --argjson reflection "$actual_reflection" \
                    --arg voice "$voice_key" \
                    --arg storyLen "$length" \
                    --arg bibleRef "$bible_ref" \
                    --arg bibleKey "$bible_key" \
                    '{
                        storyId: $id,
                        title: $title,
                        mood: $mood,
                        emotionalTags: $tags,
                        length: $length,
                        storytellingMode: $mode,
                        kidFriendly: $kid,
                        audioFilePath: $audio,
                        textFilePath: $text,
                        reflectionAudioPath: $reflection,
                        translationId: "WEB",
                        languageStyle: "WEB",
                        narratorVoiceKey: $voice,
                        storyLength: $storyLen,
                        bibleSourceRef: $bibleRef,
                        bibleStoryKey: $bibleKey
                    }')
            else
                entry=$(jq -n \
                    --arg id "$manifest_id" \
                    --arg title "$title" \
                    --arg mood "$mood" \
                    --argjson tags "$emotional_tags" \
                    --argjson length "$minutes" \
                    --arg mode "$mode" \
                    --argjson kid "$([[ "$is_kid" == "true" ]] && echo true || echo false)" \
                    --argjson audio "$actual_audio" \
                    --argjson text "$actual_text" \
                    --argjson reflection "$actual_reflection" \
                    --arg voice "$voice_key" \
                    --arg storyLen "$length" \
                    '{
                        storyId: $id,
                        title: $title,
                        mood: $mood,
                        emotionalTags: $tags,
                        length: $length,
                        storytellingMode: $mode,
                        kidFriendly: $kid,
                        audioFilePath: $audio,
                        textFilePath: $text,
                        reflectionAudioPath: $reflection,
                        translationId: "WEB",
                        languageStyle: "WEB",
                        narratorVoiceKey: $voice,
                        storyLength: $storyLen
                    }')
            fi

            manifest=$(echo "$manifest" | jq ".parables += [$entry]")
            added=$((added + 1))
        done
    done

    # Write updated manifest
    echo "$manifest" | jq '.' > "$MANIFEST_FILE"
    echo -e "${GREEN}✓ Added $added entries to manifest.json${NC}"
}

# =============================================================================
# Main
# =============================================================================

# Parse arguments
TEXT_ONLY="false"
AUDIO_ONLY="false"
DRY_RUN="false"
SKIP_EXISTING="false"
SINGLE_STORY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --text-only)   TEXT_ONLY="true"; shift ;;
        --audio-only)  AUDIO_ONLY="true"; shift ;;
        --dry-run)     DRY_RUN="true"; shift ;;
        --skip-existing) SKIP_EXISTING="true"; shift ;;
        --story)       SINGLE_STORY="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--text-only] [--audio-only] [--story ID] [--dry-run] [--skip-existing]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL — V2 Batch Story Generator${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Stories: ${GREEN}${#BATCH_STORIES[@]} base stories${NC}"
echo -e "Mode:    ${GREEN}$( [[ "$TEXT_ONLY" == "true" ]] && echo "TEXT ONLY" || ([[ "$AUDIO_ONLY" == "true" ]] && echo "AUDIO ONLY" || echo "FULL (text + audio)") )${NC}"
[[ -n "$SINGLE_STORY" ]] && echo -e "Filter:  ${GREEN}Story $SINGLE_STORY only${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN — showing plan only${NC}"
    echo ""
    for story_def in "${BATCH_STORIES[@]}"; do
        IFS='|' read -r id mode kid mood voice bible_ref bible_key <<< "$story_def"
        local_audience="adult"
        [[ "$kid" == "true" ]] && local_audience="kid"
        local_lengths="short,full,long"
        [[ "$id" == "812" ]] && local_lengths="full,long"
        echo -e "  $id: $mode $local_audience $mood → $voice [$local_lengths] ${bible_ref:+($bible_ref)}"
    done
    echo ""
    echo -e "Total manifest entries: ${GREEN}44${NC}"
    exit 0
fi

# Process stories
for story_def in "${BATCH_STORIES[@]}"; do
    if [[ -n "$SINGLE_STORY" ]]; then
        IFS='|' read -r id _ <<< "$story_def"
        [[ "$id" != "$SINGLE_STORY" ]] && continue
    fi
    process_story "$story_def"
done

# Update manifest
update_manifest

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  V2 Batch Generation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total manifest entries: $(jq '.parables | length' "$MANIFEST_FILE")"
echo ""
echo -e "Next steps:"
echo -e "  1. Review generated text files for quality"
echo -e "  2. Set AUDIO_ENABLED=1 in .env and re-run with --audio-only"
echo -e "  3. Run: flutter test"
echo -e "  4. Run: flutter analyze"
echo ""
