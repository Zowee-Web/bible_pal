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
#   --style VALUE     Override ElevenLabs style (expressiveness: 0.0-1.0, default 0.0)
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
source "$SCRIPT_DIR/story_dna.sh"
source "$PROJECT_ROOT/scripts/lib/router_client.sh"

# ElevenLabs audio defaults
# Bakeoff finding: text rhythm matters more than TTS model/style settings.
# turbo_v2_5 with well-paced text sounds better than v3 with flat prose.
STORY_STYLE_DEFAULT="0.0"
REFLECTION_STYLE_DEFAULT="0.0"
ELEVENLABS_MODEL="eleven_turbo_v2_5"
ELEVENLABS_STABILITY="0.6"
ELEVENLABS_SIMILARITY="0.8"

# Creative character name pool (avoids "Lily" / "Eli" repetition)
CREATIVE_NAME_POOL=(
    "Abigail" "Caleb" "Hannah" "Levi" "Micah" "Naomi"
    "Ezra" "Miriam" "Jonah" "Eliana" "Silas" "Tobias"
    "Aria" "Theo" "Mila" "Rowan" "Kai" "Iris" "Nova"
    "Leo" "Sage" "Luca" "Zara" "Nadia" "Finn" "Clara"
)
CREATIVE_NAMES_USED=()

select_creative_name() {
    # Pick a name not yet used in this batch run
    local available=()
    for name in "${CREATIVE_NAME_POOL[@]}"; do
        local used=false
        for u in "${CREATIVE_NAMES_USED[@]+"${CREATIVE_NAMES_USED[@]}"}"; do
            if [[ "$u" == "$name" ]]; then used=true; break; fi
        done
        if [[ "$used" == "false" ]]; then available+=("$name"); fi
    done
    # If all names used, reset pool
    if [[ ${#available[@]} -eq 0 ]]; then
        CREATIVE_NAMES_USED=()
        available=("${CREATIVE_NAME_POOL[@]}")
    fi
    # Pick random name from available
    local idx=$((RANDOM % ${#available[@]}))
    local picked="${available[$idx]}"
    CREATIVE_NAMES_USED+=("$picked")
    echo "$picked"
}

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
# Batch Definition — All 34 base stories
# =============================================================================
# Format: ID|MODE|KID|MOOD|VOICE|BIBLE_REF|BIBLE_KEY
# For creative stories, BIBLE_REF and BIBLE_KEY are empty.

BATCH_STORIES=(
    # Creative Adult WEB
    "504|creative|false|joyful|VOICE_MIRIAM_JOYFUL||"
    "505|creative|false|anxious|VOICE_MARCUS_ANCHOR||"
    "506|creative|false|hurting|VOICE_NATASHA_AFRICAN_AMERICAN||"
    "507|creative|false|neutral|VOICE_JAMES_BRITISH_PROFESSIONAL||"
    "518|creative|false|weary|VOICE_ELIJAH_SAGE||"
    # Creative Kid WEB
    "508|creative|true|weary|VOICE_ARABELLA||"
    "509|creative|true|anxious|VOICE_DAVID_SHEPHERD||"
    "510|creative|true|hurting|VOICE_HANNAH_HOPE||"
    "511|creative|true|neutral|VOICE_PRISCILLA_TEACHER||"
    "519|creative|true|joyful|VOICE_RUTH_COMFORT||"
    # Traditional Adult WEB
    "809|traditional|false|anxious|VOICE_NOAH_PATIENT|Mark 4:35-41|jesus_calms_storm"
    "820|traditional|false|joyful|VOICE_SARAH_STORYTELLER|Luke 15:3-7|lost_sheep"
    "821|traditional|false|weary|VOICE_SAMUEL_EARNEST|Matthew 11:28-30|rest_for_the_weary"
    "822|traditional|false|calm_peaceful|VOICE_JOHN_BELOVED|1 Samuel 3|samuel_listens"
    "823|traditional|false|encouraging|VOICE_MARY_PONDER|Esther 4-7|queen_esther"
    "810|traditional|false|hurting|VOICE_DEBORAH_WISE|John 4:4-26|woman_at_well"
    "811|traditional|false|neutral|VOICE_PETER_BOLD|Luke 24:13-35|road_to_emmaus"
    # Traditional Kid WEB
    "812|traditional|true|joyful|VOICE_LYDIA_GRACIOUS|Luke 15:3-7|lost_sheep"
    "813|traditional|true|anxious|VOICE_ESTHER_BRAVE|Mark 4:35-41|jesus_calms_storm"
    "814|traditional|true|hurting|VOICE_MARTHA_CARING|John 4:4-26|woman_at_well"
    "815|traditional|true|neutral|VOICE_BARNABAS_ENCOURAGER|Luke 24:13-35|road_to_emmaus"
    # --- Batch 3: Coverage gap fill (brave_courage, calm_peaceful, encouraging) ---
    # Creative Adult WEB
    "512|creative|false|brave_courage|VOICE_NATASHA_AFRICAN_AMERICAN||"
    "514|creative|false|calm_peaceful|VOICE_JAMES_HUSKY||"
    "516|creative|false|encouraging|VOICE_PRISCILLA_TEACHER||"
    # Creative Kid WEB
    "513|creative|true|brave_courage|VOICE_ARCHER||"
    "515|creative|true|calm_peaceful|VOICE_JAMES_BRITISH_PROFESSIONAL||"
    "517|creative|true|encouraging|VOICE_LILY_WOLFF||"
    # Traditional Adult WEB
    "816|traditional|false|brave_courage|VOICE_BRADFORD|Daniel 6|daniel_lions_den"
    # Traditional Kid WEB
    "817|traditional|true|brave_courage|VOICE_JANE_PROFESSIONAL|Daniel 6|daniel_lions_den"
    "818|traditional|true|calm_peaceful|VOICE_ARABELLA|1 Samuel 3|samuel_listens"
    "819|traditional|true|encouraging|VOICE_REVEREND_MICHAEL_C_VINCENT|Esther 4-7|queen_esther"
    "824|traditional|true|weary|VOICE_SARAH_STORYTELLER|Matthew 11:28-30|rest_for_the_weary"
    # --- Batch 46: Traditional Adult WEB (new scripture anchors, ADR-022) ---
    "825|traditional|false|anxious|VOICE_MARCUS_ANCHOR|1 Kings 19:9-18|elijah_at_horeb"
    "826|traditional|false|brave_courage|VOICE_NOAH_PATIENT|1 Samuel 17:1-54|david_and_goliath"
    "827|traditional|false|calm_peaceful|VOICE_DEBORAH_WISE|Luke 10:38-42|mary_and_martha"
    "828|traditional|false|encouraging|VOICE_SARAH_STORYTELLER|Ruth 1:1-22|ruth_and_naomi"
    "829|traditional|false|hurting|VOICE_MARY_PONDER|Genesis 21:14-21|hagar_in_wilderness"
    "830|traditional|false|joyful|VOICE_PETER_BOLD|Luke 15:11-32|prodigal_son"
    "831|traditional|false|neutral|VOICE_SAMUEL_EARNEST|Genesis 41:1-40|joseph_interprets_pharaohs_dreams"
    "832|traditional|false|weary|VOICE_JOHN_BELOVED|Exodus 18:13-27|moses_and_jethro"
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
            joyful)        echo "Good things grow when we share them. Even one small act of kindness can make a day brighter." ;;
            weary)         echo "It is okay to rest when you are tired. Even a short rest can help you feel ready again." ;;
            anxious)       echo "Feeling scared does not mean you are alone. Even one small brave thing can make a big difference." ;;
            hurting)       echo "It is okay to feel sad sometimes. Even one kind moment can help your heart feel lighter." ;;
            neutral)       echo "Every day has something worth noticing. Even one small thing can turn out to be special." ;;
            brave_courage) echo "Being brave does not mean you are not afraid. It means you try anyway. Even one small step counts." ;;
            calm_peaceful) echo "Being quiet and listening can help you feel calm inside. Even one still moment can bring you peace." ;;
            encouraging)   echo "Standing up for someone else takes real courage. Even one kind word can change someone's day." ;;
            *)             echo "Every day has something worth noticing. Even one small thing can turn out to be special." ;;
        esac
    else
        case "$mood" in
            joyful)        echo "Joy often arrives quietly — in a shared meal, a moment of thanks, a small gift freely given. It grows when we notice it. Even one moment of gratitude can be enough for today." ;;
            weary)         echo "Weariness runs deep when the road has been long. Rest is not giving up — it is part of the journey. Even a small pause can restore more than you expect." ;;
            anxious)       echo "Anxiety tightens its grip when we try to hold everything at once. Sometimes peace begins with letting go of just one thing. Even a single breath can steady you for today." ;;
            hurting)       echo "Pain does not always announce when it will ease. But sorrow and hope often share the same space. Even a small step forward, taken gently, can be enough for today." ;;
            neutral)       echo "Not every day carries a dramatic lesson. Sometimes faithfulness looks like showing up quietly and doing the next thing. Even an ordinary moment can hold more than it seems." ;;
            brave_courage) echo "Courage doesn't always feel strong. Sometimes it looks like taking one step forward while fear still lingers. Even that small step can be enough for today." ;;
            calm_peaceful) echo "Stillness is not emptiness. Sometimes the quietest moment is where clarity arrives. Even one breath taken in peace can carry you further than you think." ;;
            encouraging)   echo "One act of support can shift more than you realize. Standing beside someone — even silently — can change the weight of what they carry. Even a small gesture can be enough for today." ;;
            *)             echo "Not every day carries a dramatic lesson. Sometimes faithfulness looks like showing up quietly and doing the next thing. Even an ordinary moment can hold more than it seems." ;;
        esac
    fi
}

# =============================================================================
# LLM Reflection Generation + Validation (ADR-024)
# =============================================================================
# Generates a story-specific reflection via LLM, validates it, and falls back
# to the deterministic template if validation fails.

# =============================================================================
# Traditional Passage Boundary Trim (ADR-025)
# =============================================================================
# Deterministic post-generation trim: find the passage's final line in the
# generated text and truncate everything after it. This is the hard mechanical
# stop that catches echo+linger patterns the LLM produces despite prompt rules.

trim_to_passage_boundary() {
    local text="$1"
    local final_line="$2"

    if [[ -z "$final_line" ]]; then
        echo "$text"
        return 0
    fi

    # Escape special regex chars in the final line for grep
    local escaped_line
    escaped_line=$(printf '%s' "$final_line" | sed 's/[.[\*^$()+?{|\\]/\\&/g')

    # Find the last line number containing the final line text
    local last_match_line
    last_match_line=$(echo "$text" | grep -n -i "$escaped_line" | tail -1 | cut -d: -f1)

    if [[ -z "$last_match_line" ]]; then
        # Final line not found in text — return as-is (can't trim)
        echo "$text"
        return 0
    fi

    # Truncate everything after the line containing the final passage line
    local trimmed
    trimmed=$(echo "$text" | head -n "$last_match_line")

    # Strip trailing blank lines
    trimmed=$(echo "$trimmed" | sed -e :a -e '/^[[:space:]]*$/{' -e '$d' -e N -e ba -e '}')

    echo "$trimmed"
    return 0
}

# =============================================================================
# Traditional Boundary Drift Validator (ADR-025)
# =============================================================================
# Lightweight post-generation check for obvious post-boundary continuation.
# Logs to meta.json but does NOT block generation — flagged stories are
# generated but marked for human review.

check_boundary_drift() {
    local text="$1"

    # Check last ~30% of text for continuation phrases
    local total_lines
    total_lines=$(echo "$text" | wc -l | tr -d ' ')
    local tail_start=$(( total_lines * 70 / 100 ))
    [[ $tail_start -lt 1 ]] && tail_start=1
    local tail_text
    tail_text=$(echo "$text" | tail -n +"$tail_start")

    local drift_patterns=(
        "as evening fell"
        "as the evening"
        "as dusk"
        "as nighttime settled"
        "as night fell"
        "later that day"
        "in the days that followed"
        "in the hours that followed"
        "from then on"
        "from that day"
        "when they departed"
        "when the guests departed"
        "when at last .* rose to leave"
        "afterward"
        "the lesson lingered"
        "the lesson remained"
        "long after"
        "in the days ahead"
        "in the weeks that followed"
        "she would find herself"
        "he would find himself"
    )

    for pattern in "${drift_patterns[@]}"; do
        local match
        match=$(echo "$tail_text" | grep -oi "$pattern" | head -1)
        if [[ -n "$match" ]]; then
            echo "flagged:$match"
            return 0
        fi
    done

    echo "pass"
    return 0
}

validate_reflection() {
    local text="$1"

    # Strip leading/trailing whitespace
    text=$(echo "$text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Remove surrounding quotes if LLM wrapped output in them
    text=$(echo "$text" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')

    # Word count check: 15-60 words
    local wc
    wc=$(echo "$text" | wc -w | tr -d ' ')
    if [[ $wc -lt 15 ]] || [[ $wc -gt 60 ]]; then
        echo "FAIL:word_count:$wc" >&2
        return 1
    fi

    # Banned patterns (case-insensitive)
    local banned_patterns=(
        "This story teaches"
        "This story shows"
        "We should"
        "We can learn"
        "You should"
        "You can learn"
        "Have you ever"
        "What would you"
        "God's plan"
        "God's grace"
        "His grace"
        "the Lord works"
        "the Lord has"
        "Holy Spirit"
        "Jesus Christ"
        "Yahweh"
        "God wants"
        "God is"
    )

    for pattern in "${banned_patterns[@]}"; do
        if echo "$text" | grep -qi "$pattern"; then
            echo "FAIL:banned_pattern:$pattern" >&2
            return 1
        fi
    done

    # No exclamation marks
    if echo "$text" | grep -q '!'; then
        echo "FAIL:exclamation_mark" >&2
        return 1
    fi

    # No question marks (no questions to listener)
    if echo "$text" | grep -q '?'; then
        echo "FAIL:question_mark" >&2
        return 1
    fi

    echo "$text"
    return 0
}

generate_llm_reflection() {
    local mode="$1"
    local mood="$2"
    local bible_ref="$3"
    local is_kid="$4"
    local story_text="$5"

    local template_file="$SCRIPT_DIR/prompts/reflection_prompt.template.txt"
    if [[ ! -f "$template_file" ]]; then
        echo "FAIL:no_template" >&2
        return 1
    fi

    local audience="adult"
    [[ "$is_kid" == "true" ]] && audience="child"

    # Build prompt from template
    local prompt
    prompt=$(cat "$template_file")
    prompt="${prompt//\{\{MOOD\}\}/$mood}"
    prompt="${prompt//\{\{BIBLE_SOURCE_REF\}\}/$bible_ref}"
    prompt="${prompt//\{\{AUDIENCE\}\}/$audience}"

    # Use first ~500 words of story text to keep prompt size reasonable
    local trimmed_story
    trimmed_story=$(echo "$story_text" | head -c 3000)
    prompt="${prompt//\{\{STORY_TEXT\}\}/$trimmed_story}"

    # Generate with small token budget (reflections are short)
    local raw_text
    raw_text=$(generate_text "$mode" "$prompt" 200 "short" 2>/dev/null) || true

    if [[ -z "$raw_text" ]]; then
        echo "FAIL:empty_response" >&2
        return 1
    fi

    # Sanitize: strip metadata, quotes, markdown
    raw_text=$(echo "$raw_text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    raw_text=$(echo "$raw_text" | sed '/^[[:space:]]*$/d')  # Remove blank lines
    raw_text=$(echo "$raw_text" | sed -e 's/^\*\*.*\*\*[[:space:]]*//' )  # Remove bold headers
    raw_text=$(echo "$raw_text" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')  # Remove wrapping quotes

    # Validate
    local validated
    validated=$(validate_reflection "$raw_text") || return 1

    echo "$validated"
    return 0
}

# =============================================================================
# Story Text Sanitizer (strips LLM metadata leakage)
# =============================================================================

sanitize_story_text() {
    local text="$1"
    # Remove word count variants (with or without markdown bold)
    text=$(echo "$text" | sed '/^[[:space:]]*\*\{0,2\}[Ww]ord [Cc]ount[:\*].*$/d')
    text=$(echo "$text" | sed '/^[[:space:]]*\*\{0,2\}[Tt]otal [Ww]ords[:\*].*$/d')
    text=$(echo "$text" | sed '/^[[:space:]]*\*\{0,2\}[Aa]pproximate [Ww]ord [Cc]ount[:\*].*$/d')
    # Remove title-like markdown bold headers on first line (e.g. **Title Here** or **Title:** Something)
    # BSD sed requires -e splitting for commands inside braces
    text=$(echo "$text" | sed -e '1{' -e '/^\*\*.*\*\*/d' -e '}')
    # Remove source citations like "(source: ...)"
    text=$(echo "$text" | sed '/^[[:space:]]*(source:.*)/d')
    # Remove other metadata markers
    text=$(echo "$text" | sed '/^[[:space:]]*Story ID:/d; /^[[:space:]]*Model:/d; /^[[:space:]]*Generated by/d')
    # Remove exact consecutive duplicate paragraphs (continuation artifacts)
    text=$(echo "$text" | awk -v RS='\n\n' -v ORS='\n\n' '!seen[$0]++ || $0 ~ /^[[:space:]]*$/')
    # Strip leading/trailing blank lines (BSD sed compatible)
    text=$(echo "$text" | sed -n '/./,$p' | sed -e :a -e '/^[[:space:]]*$/{' -e '$d' -e N -e ba -e '}')
    echo "$text"
}

# =============================================================================
# Opening Type Validation + Retry
# =============================================================================
# Validates first sentence against the DNA opening type.
# Only checks types where regex is reliable: dialogue, question, memory.
# If validation fails, regenerates once with a forceful anchor instruction.

extract_first_sentence() {
    local text="$1"
    # Normalize: strip leading whitespace/newlines
    text=$(echo "$text" | sed -e 's/^[[:space:]]*//')
    # Extract up to first sentence-ending punctuation followed by space or EOL.
    # Use ". " or "! " or "? " to avoid splitting on "..." or "Wait..."
    # Also handle sentence ending at end of line (no trailing space).
    echo "$text" | sed -n '1,/[.!?][[:space:]]/{ s/\([.!?]\)[[:space:]].*/\1/p; }' | head -1
}

check_opening_compliance() {
    local text="$1"
    local opening_type="$2"

    # Normalize: strip leading whitespace/newlines
    local clean
    clean=$(echo "$text" | sed -e 's/^[[:space:]]*//')

    case "$opening_type" in
        dialogue)
            # First line's first non-blank character must be a quotation mark
            echo "$clean" | head -1 | grep -q '^[""'"'"']'
            return $?
            ;;
        question)
            # First sentence must contain a question mark
            local first_sent
            first_sent=$(extract_first_sentence "$clean")
            # Fallback: if extraction failed, check first 200 chars
            [[ -z "$first_sent" ]] && first_sent=$(echo "$clean" | head -c 200)
            echo "$first_sent" | grep -q '?'
            return $?
            ;;
        memory)
            # First sentence must reference the past
            local first_sent
            first_sent=$(extract_first_sentence "$clean")
            [[ -z "$first_sent" ]] && first_sent=$(echo "$clean" | head -c 200)
            echo "$first_sent" | grep -qi 'years ago\|remember\|recalled\|once,\|long before\|back when\|long ago\|he once\|she once\|used to'
            return $?
            ;;
        *)
            # Skip validation for action, emotional_reflection, object_focus, conflict, setting
            return 0
            ;;
    esac
}

get_opening_anchor() {
    local opening_type="$1"
    case "$opening_type" in
        dialogue)
            echo 'a quotation mark ("). The very first character of the story must be "'
            ;;
        question)
            echo 'a question word (What, Why, How, Where, When, Who, Is, Can, Did, Would, Could)'
            ;;
        memory)
            echo 'a time reference (Years ago, Long before, Once, He remembered)'
            ;;
        *)
            echo ''
            ;;
    esac
}

validate_and_retry_opening() {
    local text="$1"
    local opening_type="$2"
    local original_prompt="$3"
    local num_predict="$4"
    local length="$5"
    local min_wc="${6:-0}"
    local max_wc="${7:-999999}"

    # Only validate types we can reliably check
    local anchor
    anchor=$(get_opening_anchor "$opening_type")
    [[ -z "$anchor" ]] && echo "$text" && return 0

    if check_opening_compliance "$text" "$opening_type"; then
        echo -e "${GREEN}  Opening validation: PASS${NC}" >&2
        echo "$text"
        return 0
    fi

    echo -e "${YELLOW}  Opening validation: FAIL (opening_type=$opening_type) → retry${NC}" >&2

    # Retry with forceful anchor instruction
    local retry_prompt="$original_prompt

CRITICAL RETRY RULE:
Your first sentence must begin with $anchor.
Do not write any introductory setting or context sentence before it."

    local retry_text
    retry_text=$(generate_text "creative" "$retry_prompt" "$num_predict" "$length" 2>/dev/null) || true

    if [[ -n "$retry_text" ]]; then
        retry_text=$(sanitize_story_text "$retry_text")
        local retry_wc
        retry_wc=$(echo "$retry_text" | wc -w | tr -d ' ')

        # Guard: never accept a retry that breaks word count compliance
        if [[ $retry_wc -lt $min_wc ]] || [[ $retry_wc -gt $max_wc ]]; then
            local orig_wc
            orig_wc=$(echo "$text" | wc -w | tr -d ' ')
            echo -e "${YELLOW}  Opening retry: $retry_wc words outside range $min_wc–$max_wc — keeping original ($orig_wc words)${NC}" >&2
            echo "$text"
            return 0
        fi

        if check_opening_compliance "$retry_text" "$opening_type"; then
            echo -e "${GREEN}  Opening validation: PASS after retry ($retry_wc words)${NC}" >&2
            echo "$retry_text"
            return 0
        else
            echo -e "${YELLOW}  Opening validation: FAIL after retry — accepted ($retry_wc words)${NC}" >&2
            echo "$retry_text"
            return 0
        fi
    fi

    # Retry failed entirely, keep original
    echo -e "${YELLOW}  Opening validation: retry failed — keeping original${NC}" >&2
    echo "$text"
    return 0
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

    # Inject character name for creative stories (avoids "Lily" repetition)
    if [[ "$mode" == "creative" ]]; then
        local char_name
        char_name=$(select_creative_name)
        prompt="${prompt//\{\{CHARACTER_NAME\}\}/$char_name}"
        echo -e "  Character name: ${CYAN}$char_name${NC}" >&2

        # Inject Story DNA variables (computed in process_story before length loop)
        if [[ -n "${CURRENT_STORY_DNA:-}" ]]; then
            local dna_ot dna_st dna_se dna_ca dna_tn dna_nv
            dna_ot=$(echo "$CURRENT_STORY_DNA" | jq -r '.opening_type')
            dna_st=$(echo "$CURRENT_STORY_DNA" | jq -r '.structure_type')
            dna_se=$(echo "$CURRENT_STORY_DNA" | jq -r '.setting_emphasis')
            dna_ca=$(echo "$CURRENT_STORY_DNA" | jq -r '.character_archetype')
            dna_tn=$(echo "$CURRENT_STORY_DNA" | jq -r '.tone')
            dna_nv=$(echo "$CURRENT_STORY_DNA" | jq -r '.narrator_voice')
            prompt="${prompt//\{\{OPENING_TYPE\}\}/$dna_ot}"
            prompt="${prompt//\{\{STRUCTURE_TYPE\}\}/$dna_st}"
            prompt="${prompt//\{\{SETTING_EMPHASIS\}\}/$dna_se}"
            prompt="${prompt//\{\{CHARACTER_ARCHETYPE\}\}/$dna_ca}"
            prompt="${prompt//\{\{TONE\}\}/$dna_tn}"
            prompt="${prompt//\{\{NARRATOR_VOICE\}\}/$dna_nv}"

            # Inject place-name avoidance list
            local avoid_file="$SCRIPT_DIR/data/creative_place_names_avoid.txt"
            local avoid_block=""
            if [[ -f "$avoid_file" ]]; then
                local avoid_names
                avoid_names=$(tr '\n' ', ' < "$avoid_file" | sed 's/,*$//')
                if [[ -n "$avoid_names" ]]; then
                    avoid_block="Do NOT use these fictional place names: $avoid_names"
                fi
            fi
            prompt="${prompt//\{\{PLACE_NAMES_AVOID\}\}/$avoid_block}"
        fi
    fi

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
            # Extract passage final line for boundary enforcement (ADR-025)
            local final_line
            final_line=$(echo "$seed" | jq -r '.passageFinalLine // empty')
            if [[ -n "$final_line" ]]; then
                local final_line_block="The passage ends with: \"$final_line\"
The LAST SENTENCE of your story must convey this final line. No text is allowed after it. STOP writing immediately after this moment."
                prompt="${prompt//\{\{PASSAGE_FINAL_LINE\}\}/$final_line_block}"
            fi
        fi
    fi
    prompt="${prompt//\{\{NARRATIVE_ANCHORS\}\}/$anchors_block}"
    # Fallback: if no passageFinalLine was injected, use generic instruction
    prompt="${prompt//\{\{PASSAGE_FINAL_LINE\}\}/End the story at the last recorded event in the passage. Do not continue beyond it.}"

    # Inject scene blueprint for full/long stories (skip for short)
    # Long stories get expanded pacing notes to allow each scene to breathe
    local blueprint_block=""
    local pacing_note=""
    if [[ "$length_bucket" == "long" ]]; then
        pacing_note="Let each scene breathe — use sensory detail, transitions, and unhurried pacing."
    fi
    if [[ "$length_bucket" == "full" || "$length_bucket" == "long" ]]; then
        if [[ "$mode" == "traditional" && -n "${conflict:-}" && -n "${tp:-}" ]]; then
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
    local style="${4:-$STORY_STYLE_DEFAULT}"

    local voice_id
    voice_id=$(get_voice_id "$voice_key")
    if [[ -z "$voice_id" || "$voice_id" == "null" ]]; then
        echo -e "${RED}  Error: Unknown voice key $voice_key${NC}" >&2
        return 1
    fi

    local char_count=${#text}
    # eleven_v3 has ~5000 char limit; fall back to eleven_multilingual_v2 for longer texts
    local model="$ELEVENLABS_MODEL"
    if [[ "$char_count" -gt 5000 && "$model" == "eleven_v3" ]]; then
        model="eleven_multilingual_v2"
        echo -e "${YELLOW}  Audio: ${char_count} chars (>5000, using $model fallback) → $output_file${NC}"
    else
        echo -e "${BLUE}  Audio: ${char_count} chars → $output_file${NC}"
    fi

    # Source ElevenLabs guard for safety
    if [[ -f "$SCRIPT_DIR/elevenlabs_guard.sh" ]]; then
        source "$SCRIPT_DIR/elevenlabs_guard.sh"
    fi

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -X POST "https://api.elevenlabs.io/v1/text-to-speech/${voice_id}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg text "$text" \
            --arg style "$style" \
            --arg model "$model" \
            --arg stability "$ELEVENLABS_STABILITY" \
            --arg similarity "$ELEVENLABS_SIMILARITY" \
            '{
            text: $text,
            model_id: $model,
            voice_settings: {
                stability: ($stability | tonumber),
                similarity_boost: ($similarity | tonumber),
                style: ($style | tonumber),
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

    # ADR-026: Traditional passage length capability — only attempt supported lengths
    local skipped_lengths_json="{}"
    if [[ "$mode" == "traditional" && -n "$bible_key" ]]; then
        local seeds_file="$SCRIPT_DIR/seeds/traditional_seeds.json"
        if [[ -f "$seeds_file" ]]; then
            local supported_lengths_json
            supported_lengths_json=$(jq -r --arg key "$bible_key" '.[$key].supportedLengths // empty' "$seeds_file" 2>/dev/null)
            if [[ -n "$supported_lengths_json" && "$supported_lengths_json" != "null" ]]; then
                local filtered_lengths=()
                for len in "${lengths[@]}"; do
                    if echo "$supported_lengths_json" | jq -e --arg l "$len" 'index($l) != null' >/dev/null 2>&1; then
                        filtered_lengths+=("$len")
                    else
                        echo -e "${YELLOW}  ⚠ Skipping $len: not supported for $bible_key (ADR-026)${NC}"
                        skipped_lengths_json=$(echo "$skipped_lengths_json" | jq --arg len "$len" \
                            '.[$len] = "intentionally_unavailable: exceeds_max_supported_length"')
                    fi
                done
                lengths=("${filtered_lengths[@]}")
            fi
        fi
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

    # Word count flags: track when stories exceed prompt targets but are accepted
    # ADR-023: quality over strict compliance
    local wc_flags_json="{}"

    # Boundary validation: track Traditional mode drift (ADR-025)
    local boundary_validation_json="{}"

    # Extract passage final line for boundary trim (ADR-025)
    local story_final_line=""
    if [[ "$mode" == "traditional" && -n "$bible_key" ]]; then
        local seeds_path="$SCRIPT_DIR/seeds/traditional_seeds.json"
        if [[ -f "$seeds_path" ]]; then
            story_final_line=$(jq -r --arg key "$bible_key" '.[$key].passageFinalLine // empty' "$seeds_path" 2>/dev/null)
        fi
    fi

    # --- Compute Story DNA for Creative stories (once per base story) ---
    if [[ "$mode" == "creative" ]]; then
        CURRENT_STORY_DNA=$(get_story_dna "$CREATIVE_STORY_INDEX" "$story_id")
        CREATIVE_STORY_INDEX=$((CREATIVE_STORY_INDEX + 1))
        local dna_opening dna_structure dna_setting dna_archetype dna_tone dna_narrator
        dna_opening=$(echo "$CURRENT_STORY_DNA" | jq -r '.opening_type')
        dna_structure=$(echo "$CURRENT_STORY_DNA" | jq -r '.structure_type')
        dna_setting=$(echo "$CURRENT_STORY_DNA" | jq -r '.setting_emphasis')
        dna_archetype=$(echo "$CURRENT_STORY_DNA" | jq -r '.character_archetype')
        dna_tone=$(echo "$CURRENT_STORY_DNA" | jq -r '.tone')
        dna_narrator=$(echo "$CURRENT_STORY_DNA" | jq -r '.narrator_voice')
        echo -e "  ${CYAN}DNA: opening=$dna_opening structure=$dna_structure setting=$dna_setting archetype=$dna_archetype tone=$dna_tone narrator=$dna_narrator${NC}"
    else
        CURRENT_STORY_DNA=""
    fi

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

                # Add explicit word count instruction (prompt target is tighter than acceptance)
                local prompt_target_max
                prompt_target_max=$(get_prompt_target_max_for_mode "$length" "$mode" "$is_kid")
                prompt="$prompt

CRITICAL: This story MUST be at least $min_wc words and no more than $prompt_target_max words. Write a complete, detailed story with rich descriptions and fully developed scenes. Do not stop early."

                text=$(generate_text "$mode" "$prompt" "$num_predict" "$length" 2>/dev/null) || true

                if [[ -z "$text" ]]; then
                    echo -e "${RED}  ✗ Attempt $wc_attempt: text generation returned empty${NC}"
                    sleep 3
                    continue
                fi

                # Sanitize LLM output (remove metadata, titles, word counts)
                text=$(sanitize_story_text "$text")
                # ADR-025: Trim initial generation to passage boundary (Traditional mode)
                if [[ "$mode" == "traditional" ]] && [[ -n "$story_final_line" ]]; then
                    text=$(trim_to_passage_boundary "$text" "$story_final_line")
                fi

                wc=$(echo "$text" | wc -w | tr -d ' ')
                echo -e "  Attempt $wc_attempt: $wc words (need $min_wc-$max_wc)"

                if [[ $wc -ge $min_wc ]]; then
                    break  # Good enough
                fi

                # If too short, try extending by feeding partial text back
                if [[ $wc -lt $min_wc ]] && [[ $wc_attempt -lt $max_wc_attempts ]]; then
                    echo -e "${YELLOW}  Too short ($wc < $min_wc), attempting continuation...${NC}"
                    # Build continuation prompt — mode-aware (ADR-025)
                    local trad_boundary_rules=""
                    if [[ "$mode" == "traditional" ]]; then
                        # Extract passageFinalLine for boundary enforcement
                        local cont_final_line=""
                        if [[ -n "$bible_key" && -f "$SCRIPT_DIR/seeds/traditional_seeds.json" ]]; then
                            cont_final_line=$(jq -r --arg key "$bible_key" '.[$key].passageFinalLine // empty' "$SCRIPT_DIR/seeds/traditional_seeds.json" 2>/dev/null)
                        fi
                        trad_boundary_rules="
TRADITIONAL MODE CONTINUATION RULES (NON-NEGOTIABLE):
- This is a Traditional Bible story anchored to: $bible_ref
- Continue ONLY within the events of that Scripture passage
- You MUST stop at the passage boundary — do NOT add events after it
- No aftermath, departure, evening scenes, or emotional resolution beyond what Scripture records
- No imported teachings from other passages
- No invented dialogue, reconciliation, or character change not in the passage
- If you are near the end of the passage, finish at the exact boundary and stop
- Do NOT add atmospheric closure, lingering silence, or repeat the final line after reaching it"
                        if [[ -n "$cont_final_line" ]]; then
                            trad_boundary_rules="$trad_boundary_rules
- The passage ends with: \"$cont_final_line\" — this MUST be the last moment in the story. STOP immediately after it. No text after this line."
                        fi
                    fi

                    local continue_prompt="You are continuing a story that was cut short. Continue with several more paragraphs to bring the story to its scriptural conclusion.

IMPORTANT RULES FOR CONTINUATION:
- Pick up exactly where the story left off — do NOT restart or summarize
- Maintain the same characters, setting, tone, and narrative voice
- Write continuous prose paragraphs (no headings, no bullets)
- Write for spoken narration — keep sentences under 22 words
- Do NOT repeat any content from the existing story
- Do NOT include word counts, metadata, titles, or \"The End\"
- Write ONLY story prose
$trad_boundary_rules
STORY SO FAR:
$text

CONTINUE THE STORY FROM HERE:"
                    local continuation
                    continuation=$(generate_text "$mode" "$continue_prompt" "$num_predict" "$length" 2>/dev/null) || true
                    if [[ -n "$continuation" ]]; then
                        text="$text

$continuation"
                        # Sanitize combined text (remove any metadata from continuation)
                        text=$(sanitize_story_text "$text")
                        # ADR-025: Trim continuation to passage boundary (Traditional mode)
                        if [[ "$mode" == "traditional" ]] && [[ -n "$story_final_line" ]]; then
                            text=$(trim_to_passage_boundary "$text" "$story_final_line")
                        fi
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
                # ADR-026: Traditional stories with passage boundary constraints may be
                # naturally shorter than the bucket minimum. Accept if story has content
                # and boundary trim will be applied. Scripture integrity > word count.
                if [[ "$mode" == "traditional" ]] && [[ -n "$story_final_line" ]] && [[ $wc -ge 150 ]]; then
                    echo -e "${YELLOW}  ⚠ Word count $wc below minimum $min_wc but accepted (Traditional passage boundary priority)${NC}"
                else
                    echo -e "${RED}  FAIL: Word count $wc below minimum $min_wc after $max_wc_attempts attempts${NC}"
                    echo -e "${RED}  Aborting $length variant for story $story_id — no file saved${NC}"
                    rm -f "$text_file"
                    continue
                fi
            fi

            # ADR-023: Track if story exceeds prompt target but fits canonical bucket
            local prompt_tgt_max
            prompt_tgt_max=$(get_prompt_target_max_for_mode "$length" "$mode" "$is_kid")
            if [[ $wc -gt $prompt_tgt_max ]] && [[ $wc -le $max_wc ]]; then
                echo -e "${YELLOW}  ⚠ Word count $wc exceeds prompt target $prompt_tgt_max but within bucket max $max_wc (accepted)${NC}"
                wc_flags_json=$(echo "$wc_flags_json" | jq --arg len "$length" \
                    --argjson tgt "$prompt_tgt_max" --argjson actual "$wc" \
                    --argjson bmax "$max_wc" \
                    '.[$len] = {promptTarget: $tgt, actual: $actual, bucketMax: $bmax, accepted: "within_bucket"}')
            elif [[ $wc -gt $max_wc ]]; then
                echo -e "${YELLOW}  ⚠ Word count $wc exceeds bucket max $max_wc (saving as-is, flagged)${NC}"
                wc_flags_json=$(echo "$wc_flags_json" | jq --arg len "$length" \
                    --argjson tgt "$prompt_tgt_max" --argjson actual "$wc" \
                    --argjson bmax "$max_wc" \
                    '.[$len] = {promptTarget: $tgt, actual: $actual, bucketMax: $bmax, accepted: "over_bucket"}')
            fi

            # Opening type validation + retry (creative stories only)
            if [[ "$mode" == "creative" ]] && [[ -n "${CURRENT_STORY_DNA:-}" ]]; then
                local dna_opening_type
                dna_opening_type=$(echo "$CURRENT_STORY_DNA" | jq -r '.opening_type')
                text=$(validate_and_retry_opening "$text" "$dna_opening_type" "$prompt" "$num_predict" "$length" "$min_wc" "$max_wc")
                # Update word count after potential retry
                wc=$(echo "$text" | wc -w | tr -d ' ')
            fi

            # ADR-025: Trim Traditional stories to passage boundary (deterministic hard stop)
            if [[ "$mode" == "traditional" ]] && [[ -n "$story_final_line" ]]; then
                local pre_trim_wc=$wc
                text=$(trim_to_passage_boundary "$text" "$story_final_line")
                wc=$(echo "$text" | wc -w | tr -d ' ')
                if [[ $wc -lt $pre_trim_wc ]]; then
                    echo -e "${CYAN}  Boundary trim: $pre_trim_wc → $wc words (removed post-boundary text)${NC}"
                fi
            fi

            echo "$text" > "$text_file"
            echo -e "${GREEN}  ✓ Saved: $text_file ($wc words)${NC}"

            # ADR-025: Boundary drift check (Traditional mode only)
            if [[ "$mode" == "traditional" ]]; then
                local drift_result
                drift_result=$(check_boundary_drift "$text")
                if [[ "$drift_result" == "pass" ]]; then
                    echo -e "${GREEN}  ✓ Boundary check: PASS${NC}"
                else
                    echo -e "${YELLOW}  ⚠ Boundary check: FLAGGED ($drift_result)${NC}"
                fi
                boundary_validation_json=$(echo "$boundary_validation_json" | jq --arg len "$length" --arg result "$drift_result" \
                    '.[$len] = $result')
            fi

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

        # --- PHASE 2: Create reflection text (ADR-024: LLM-first with template fallback) ---
        local reflection_file="$story_dir/reflection_${story_id}_${mode}_web.txt"
        local reflection_text=""
        local reflection_source="template"

        # Try LLM-generated reflection using the "full" story text for best context
        local full_text_file="$story_dir/story_${story_id}_${mode}_web_full.txt"
        if [[ -s "$full_text_file" ]] && [[ -n "$bible_ref" ]]; then
            local story_context
            story_context=$(cat "$full_text_file")
            echo -e "${BLUE}  Generating LLM reflection...${NC}"

            local llm_reflection
            local attempt=0
            local max_attempts=2
            while [[ $attempt -lt $max_attempts ]]; do
                attempt=$((attempt + 1))
                llm_reflection=$(generate_llm_reflection "$mode" "$mood" "$bible_ref" "$is_kid" "$story_context" 2>/dev/null) || true

                if [[ -n "$llm_reflection" ]]; then
                    # Validate
                    local validated
                    validated=$(validate_reflection "$llm_reflection" 2>/dev/null)
                    if [[ $? -eq 0 ]] && [[ -n "$validated" ]]; then
                        reflection_text="$validated"
                        reflection_source="llm"
                        echo -e "${GREEN}  ✓ LLM reflection (attempt $attempt): $reflection_text${NC}"
                        break
                    else
                        local fail_reason
                        fail_reason=$(validate_reflection "$llm_reflection" 2>&1 >/dev/null || true)
                        echo -e "${YELLOW}  ⚠ LLM reflection attempt $attempt failed validation: $fail_reason${NC}"
                    fi
                else
                    echo -e "${YELLOW}  ⚠ LLM reflection attempt $attempt returned empty${NC}"
                fi
                sleep 1
            done
        fi

        # Fallback to template if LLM failed
        if [[ -z "$reflection_text" ]]; then
            reflection_text=$(get_reflection_text "$mood" "$is_kid")
            reflection_source="template"
            echo -e "${YELLOW}  Using template reflection (fallback)${NC}"
        fi

        echo "$reflection_text" > "$reflection_file"
        echo -e "${GREEN}  ✓ Reflection text saved (source: $reflection_source)${NC}"
    fi

    # --- PHASE 3: Generate audio (if enabled) ---
    # Track ElevenLabs character usage per length for credit logging
    local el_credits_json="{}"
    local el_credits_total=0

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
                # ADR-026: Traditional stories may be under minimum due to passage boundary trim
                if [[ "$mode" == "traditional" ]] && [[ -n "${story_final_line:-}" ]] && [[ $text_wc -ge 150 ]]; then
                    echo -e "${YELLOW}  Audio gate: $text_wc words below $audio_min but accepted (Traditional passage boundary)${NC}"
                else
                    echo -e "${RED}  AUDIO GATE FAIL: $length text has $text_wc words (need $audio_min-$audio_max)${NC}"
                    echo -e "${RED}  Skipping audio generation to avoid wasting ElevenLabs credits${NC}"
                    continue
                fi
            fi

            if [[ "$SKIP_EXISTING" == "true" ]] && [[ -s "$audio_file" ]]; then
                echo -e "${YELLOW}  Skipping $length audio (exists)${NC}"
                continue
            fi

            local text
            text=$(cat "$text_file")
            local char_count=${#text}
            generate_audio_elevenlabs "$text" "$voice_key" "$audio_file" "$STORY_STYLE_DEFAULT" || true
            el_credits_json=$(echo "$el_credits_json" | jq --arg len "$length" --argjson cc "$char_count" '.[$len] = $cc')
            el_credits_total=$((el_credits_total + char_count))
            sleep 2  # Pace ElevenLabs requests
        done

        # Reflection audio
        local reflection_file="$story_dir/reflection_${story_id}_${mode}_web.txt"
        local reflection_audio="$story_dir/audio_${story_id}_reflection.mp3"

        if [[ -s "$reflection_file" ]] && { [[ "$SKIP_EXISTING" != "true" ]] || [[ ! -s "$reflection_audio" ]]; }; then
            local reflection_text
            reflection_text=$(cat "$reflection_file")
            local refl_char_count=${#reflection_text}
            generate_audio_elevenlabs "$reflection_text" "$voice_key" "$reflection_audio" "$REFLECTION_STYLE_DEFAULT" || true
            el_credits_json=$(echo "$el_credits_json" | jq --argjson cc "$refl_char_count" '.reflection = $cc')
            el_credits_total=$((el_credits_total + refl_char_count))
            sleep 1
        fi

        if [[ $el_credits_total -gt 0 ]]; then
            el_credits_json=$(echo "$el_credits_json" | jq --argjson t "$el_credits_total" '.total = $t')
            echo -e "${CYAN}  ElevenLabs credits used: ${el_credits_total} chars${NC}"
        fi
    elif [[ "$TEXT_ONLY" != "true" ]]; then
        echo -e "${YELLOW}  ⚠ Audio skipped: set AUDIO_ENABLED=1 in .env${NC}"
    fi

    # --- PHASE 4: Validate/update meta.json (createdByModel + generationContractVersion) ---
    local meta_file="$story_dir/meta_${story_id}.json"
    local updated_meta

    if [[ -f "$meta_file" ]]; then
        # Validate createdByModel matches expected engine
        local meta_model
        meta_model=$(jq -r '.createdByModel // empty' "$meta_file")
        if [[ -n "$meta_model" ]] && [[ "$meta_model" != "$expected_model" ]]; then
            echo -e "${RED}  META MISMATCH: createdByModel='$meta_model' but expected '$expected_model'${NC}"
            echo -e "${YELLOW}  Updating meta.json to reflect correct engine...${NC}"
        fi
        updated_meta=$(jq --arg model "$expected_model" --arg contract "STORY_FACTORY_v2.3" \
            '.createdByModel = $model | .generationContractVersion = $contract' "$meta_file")
    else
        # Create meta.json from scratch
        local reflection_text
        reflection_text=$(get_reflection_text "$mood" "$is_kid")

        # Build files object
        local files_json="{}"
        for len in "${lengths[@]}"; do
            local txt_name="story_${story_id}_${mode}_web_${len}.txt"
            local aud_name="audio_${story_id}_story_${len}.mp3"
            if [[ -s "$story_dir/$txt_name" ]]; then
                files_json=$(echo "$files_json" | jq --arg l "$len" --arg t "$txt_name" --arg a "$aud_name" \
                    '.[$l] = {storyText: $t, storyAudio: $a}')
            fi
        done
        local refl_txt="reflection_${story_id}_${mode}_web.txt"
        local refl_aud="audio_${story_id}_reflection.mp3"
        files_json=$(echo "$files_json" | jq --arg t "$refl_txt" --arg a "$refl_aud" \
            '.reflection = {reflectionText: $t, reflectionAudio: $a}')

        # Determine batch label from comment context
        local batch_label="PAL_V2_BATCH_46"

        updated_meta=$(jq -n \
            --argjson schema 2 \
            --argjson sid "$story_id" \
            --arg mode "$mode" \
            --argjson kid "$([ "$is_kid" = "true" ] && echo true || echo false)" \
            --arg lang "WEB" \
            --arg mood "$mood" \
            --arg anchor "$bible_ref" \
            --arg bkey "$bible_key" \
            --argjson lengths "$(printf '%s\n' "${lengths[@]}" | jq -R . | jq -s .)" \
            --arg vkey "$voice_key" \
            --arg model "$expected_model" \
            --arg batch "$batch_label" \
            --arg contract "STORY_FACTORY_v2.3" \
            --arg refl "$reflection_text" \
            --argjson files "$files_json" \
            '{
                schemaVersion: $schema,
                storyId: $sid,
                mode: $mode,
                kidFriendly: $kid,
                languageStyle: $lang,
                mood: $mood,
                scriptureAnchor: $anchor,
                bibleStoryKey: $bkey,
                lengths: $lengths,
                voiceKey: $vkey,
                voiceKeys: {short: $vkey, full: $vkey, long: $vkey, reflection: $vkey},
                createdByModel: $model,
                generationBatch: $batch,
                generationContractVersion: $contract,
                reflectionQuestion: $refl,
                files: $files
            }')
        echo -e "${GREEN}  ✓ Created meta.json for story $story_id${NC}"
    fi

    # Add storyDna to meta.json for creative stories
    if [[ "$mode" == "creative" ]] && [[ -n "${CURRENT_STORY_DNA:-}" ]]; then
        updated_meta=$(echo "$updated_meta" | jq --argjson dna "$CURRENT_STORY_DNA" \
            '.storyDna = {opening_type: $dna.opening_type, structure_type: $dna.structure_type, setting_emphasis: $dna.setting_emphasis, character_archetype: $dna.character_archetype, tone: $dna.tone}')
    fi

    # ADR-023: Record word count flags in meta.json
    local has_flags
    has_flags=$(echo "$wc_flags_json" | jq 'length')
    if [[ "$has_flags" -gt 0 ]]; then
        updated_meta=$(echo "$updated_meta" | jq --argjson flags "$wc_flags_json" \
            '.wordCountFlags = $flags')
        echo -e "${YELLOW}  ✓ Recorded wordCountFlags for ${has_flags} length(s)${NC}"
    fi
    # Note: if no new flags were generated (e.g. audio-only run), preserve existing flags

    # ADR-024: Record reflection source and resolved text in meta.json
    if [[ -n "${reflection_source:-}" ]] && [[ -n "${reflection_text:-}" ]]; then
        updated_meta=$(echo "$updated_meta" | jq \
            --arg src "$reflection_source" \
            --arg txt "$reflection_text" \
            '.reflectionSource = $src | .reflectionText = $txt')
    fi

    # ADR-025: Record boundary validation results in meta.json (Traditional only)
    local has_boundary
    has_boundary=$(echo "$boundary_validation_json" | jq 'length')
    if [[ "$has_boundary" -gt 0 ]]; then
        updated_meta=$(echo "$updated_meta" | jq --argjson bv "$boundary_validation_json" \
            '.boundaryValidation = $bv')
    fi

    # ADR-026: Record skipped lengths in meta.json
    local has_skipped
    has_skipped=$(echo "$skipped_lengths_json" | jq 'length')
    if [[ "$has_skipped" -gt 0 ]]; then
        updated_meta=$(echo "$updated_meta" | jq --argjson sl "$skipped_lengths_json" \
            '.skippedLengths = $sl')
    fi

    echo "$updated_meta" > "$meta_file"
    echo -e "${GREEN}  ✓ meta.json: createdByModel=$expected_model, contract=STORY_FACTORY_v2.3${NC}"

    # --- PHASE 5: Append to generation log ---
    local gen_log="$STORIES_DIR/.generation_log.json"
    local log_entry
    log_entry=$(jq -n \
        --argjson sid "$story_id" \
        --arg mode "$mode" \
        --arg mood "$mood" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg model "$expected_model" \
        --argjson flags "$wc_flags_json" \
        --argjson credits "$el_credits_json" \
        '{storyId: $sid, mode: $mode, mood: $mood, timestamp: $ts, model: $model, wordCountFlags: $flags, elevenLabsCredits: $credits}')
    if [[ -f "$gen_log" ]]; then
        local updated_log
        updated_log=$(jq --argjson entry "$log_entry" '. += [$entry]' "$gen_log")
        echo "$updated_log" > "$gen_log"
    else
        echo "[$log_entry]" | jq '.' > "$gen_log"
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
STYLE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --text-only)   TEXT_ONLY="true"; shift ;;
        --audio-only)  AUDIO_ONLY="true"; shift ;;
        --dry-run)     DRY_RUN="true"; shift ;;
        --skip-existing) SKIP_EXISTING="true"; shift ;;
        --story)       SINGLE_STORY="$2"; shift 2 ;;
        --style)       STYLE_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--text-only] [--audio-only] [--story ID] [--dry-run] [--skip-existing] [--style VALUE]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Apply style override if set
if [[ -n "$STYLE_OVERRIDE" ]]; then
    echo -e "${CYAN}[audio] Using style override: $STYLE_OVERRIDE${NC}"
    STORY_STYLE_DEFAULT="$STYLE_OVERRIDE"
    REFLECTION_STYLE_DEFAULT="$STYLE_OVERRIDE"
fi

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

# Initialize Story DNA diversity system (Creative stories only)
CREATIVE_STORY_INDEX=0
CURRENT_STORY_DNA=""
init_dna_guard
seed_dna_guard_from_metadata "$STORIES_DIR"

# For single-story mode, compute the creative ordinal that this story
# would have in a full batch run. Without this, every --story run
# incorrectly uses index 0 (DNA collision bug).
if [[ -n "$SINGLE_STORY" ]]; then
    if ! CREATIVE_STORY_INDEX=$(compute_creative_ordinal "$SINGLE_STORY" "${BATCH_STORIES[@]}"); then
        echo "ERROR: Failed to compute creative ordinal for story $SINGLE_STORY" >&2
        exit 1
    fi
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
