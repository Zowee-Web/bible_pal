#!/usr/bin/env bash
# elevenlabs_guard.sh
# Shared safety gate for ALL ElevenLabs API calls
# Prevents accidental credit usage and enforces character limits

# USAGE:
#   source server/elevenlabs_guard.sh
#   if elevenlabs_check_and_log "$story_id" "$char_count" "$length_minutes"; then
#       # Safe to call ElevenLabs
#       elevenlabs_call "$story_text" "$output_file" "$voice_id" "$api_key"
#   else
#       # Audio generation blocked
#       exit 1
#   fi

GUARD_LOCK_DIR="/tmp/biblepal_elevenlabs.lock"
GUARD_LOG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/elevenlabs_calls.log"

# Character limits per tier (narrated audio calibration)
# 5min: 600-750 words × ~5 chars/word = ~3000-3750 chars (max 6000 safety margin)
# 10min: 1200-1500 words × ~5 = ~6000-7500 chars (max 12000)
# 15min: 1800-2250 words × ~5 = ~9000-11250 chars (max 18000)
# 20min: 2400-3000 words × ~5 = ~12000-15000 chars (max 24000)
# Bash 3.2 compatible (no associative arrays)
get_char_limit() {
    local length=$1
    case "$length" in
        5) echo "6000" ;;
        10) echo "12000" ;;
        15) echo "18000" ;;
        20) echo "24000" ;;
        *) echo "6000" ;;
    esac
}

# elevenlabs_check_and_log: Validate and log ElevenLabs call attempt
# Args: story_id char_count length_minutes
# Returns: 0 if safe to proceed, 1 if blocked
elevenlabs_check_and_log() {
    local story_id="$1"
    local char_count="$2"
    local length_minutes="$3"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local script_name=$(basename "$0")

    # Initialize log file if it doesn't exist
    if [[ ! -f "$GUARD_LOG_FILE" ]]; then
        echo "timestamp,script,story_id,char_count,length,status,message" > "$GUARD_LOG_FILE"
    fi

    # Check if audio generation is enabled
    if [[ "${AUDIO_ENABLED:-0}" != "1" ]]; then
        echo "$timestamp,$script_name,$story_id,$char_count,$length_minutes,BLOCKED,AUDIO_DISABLED" >> "$GUARD_LOG_FILE"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo -e "${YELLOW}⚠ AUDIO_DISABLED: No ElevenLabs call made${NC}" >&2
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo -e "Story ID: ${GREEN}$story_id${NC}" >&2
        echo -e "Character count: ${GREEN}$char_count${NC}" >&2
        echo -e "Estimated credits: ${GREEN}~$char_count${NC}" >&2
        echo -e "Audio generation blocked by safety guard" >&2
        echo "" >&2
        echo -e "${YELLOW}To enable audio generation, run: AUDIO_ENABLED=1 $script_name [args]${NC}" >&2
        echo "" >&2
        return 1
    fi

    # Validate character count against tier limit
    local max_chars=$(get_char_limit "$length_minutes")
    if (( char_count > max_chars )); then
        echo "$timestamp,$script_name,$story_id,$char_count,$length_minutes,BLOCKED,CHAR_LIMIT_EXCEEDED:$max_chars" >> "$GUARD_LOG_FILE"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo -e "${RED}❌ SAFETY GUARD: Character count exceeds limit${NC}" >&2
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
        echo -e "${RED}Story: $story_id${NC}" >&2
        echo -e "${RED}Characters: $char_count (max: $max_chars for ${length_minutes}min stories)${NC}" >&2
        echo -e "${RED}Refusing to call ElevenLabs. Fix calibration before retrying.${NC}" >&2
        echo "" >&2
        return 1
    fi

    # Acquire lock (prevents concurrent calls)
    local lock_attempts=0
    while ! mkdir "$GUARD_LOCK_DIR" 2>/dev/null; do
        lock_attempts=$((lock_attempts + 1))
        if (( lock_attempts > 30 )); then
            echo "$timestamp,$script_name,$story_id,$char_count,$length_minutes,BLOCKED,LOCK_TIMEOUT" >> "$GUARD_LOG_FILE"
            echo -e "${RED}❌ ERROR: Could not acquire ElevenLabs lock after 30 seconds${NC}" >&2
            return 1
        fi
        echo -e "${YELLOW}Waiting for ElevenLabs lock... (attempt $lock_attempts/30)${NC}" >&2
        sleep 1
    done

    # Log successful validation
    echo "$timestamp,$script_name,$story_id,$char_count,$length_minutes,APPROVED,~$char_count credits" >> "$GUARD_LOG_FILE"
    echo -e "${GREEN}✓ Safety guard passed: $char_count chars (~$char_count credits)${NC}" >&2

    return 0
}

# elevenlabs_call: Make the actual ElevenLabs API call
# Args: story_text output_file voice_id api_key [model_id]
# Returns: HTTP status code
#
# Optional 5th arg: model_id (default: "eleven_turbo_v2_5")
#   PAL audio generation passes "eleven_v3" here.
#
# Robust curl invocation:
#   - --connect-timeout 10: fail fast if server unreachable
#   - --max-time 120: hard cap on total request time
#   - -sS: silent but show errors
#   - Captures curl exit code for diagnostics
elevenlabs_call() {
    local story_text="$1"
    local output_file="$2"
    local voice_id="$3"
    local api_key="$4"
    local model_id="${5:-eleven_turbo_v2_5}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local script_name=$(basename "$0")

    echo -e "${BLUE}→ Calling ElevenLabs API (model: $model_id)...${NC}" >&2

    # Build JSON payload using jq for proper escaping
    local json_payload
    json_payload=$(jq -n --arg text "$story_text" --arg model "$model_id" '{
        text: $text,
        model_id: $model,
        voice_settings: {
            stability: 0.6,
            similarity_boost: 0.8,
            style: 0.0,
            use_speaker_boost: true
        }
    }')

    local http_code
    local curl_exit
    http_code=$(curl -sS \
        --connect-timeout 10 \
        --max-time 120 \
        -w "%{http_code}" \
        -o "$output_file" \
        -X POST \
        "https://api.elevenlabs.io/v1/text-to-speech/${voice_id}" \
        -H "xi-api-key: $api_key" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>&1) || curl_exit=$?

    # Release lock
    rmdir "$GUARD_LOCK_DIR" 2>/dev/null

    # Check curl exit code first
    if [[ -n "${curl_exit:-}" && "$curl_exit" -ne 0 ]]; then
        echo "$timestamp,$script_name,FAILED,CURL_EXIT_$curl_exit,HTTP_$http_code" >> "$GUARD_LOG_FILE"
        echo -e "${RED}✗ Curl failed (exit code: $curl_exit, HTTP: $http_code)${NC}" >&2
        echo "000"
        return 1
    fi

    # Log the result
    if [[ "$http_code" == "200" ]]; then
        local file_size=$(ls -lh "$output_file" 2>/dev/null | awk '{print $5}')
        echo "$timestamp,$script_name,SENT,HTTP_$http_code,$file_size" >> "$GUARD_LOG_FILE"
        echo -e "${GREEN}✓ ElevenLabs API call successful ($file_size)${NC}" >&2
    else
        echo "$timestamp,$script_name,FAILED,HTTP_$http_code" >> "$GUARD_LOG_FILE"
        echo -e "${RED}✗ ElevenLabs API Error (HTTP $http_code)${NC}" >&2
        # Print diagnostic if response file exists
        if [[ -f "$output_file" ]]; then
            local error_msg
            error_msg=$(jq -r '.detail.message // .detail // .message // empty' < "$output_file" 2>/dev/null || head -100 "$output_file")
            if [[ -n "$error_msg" ]]; then
                echo -e "${RED}  Detail: $error_msg${NC}" >&2
            fi
        fi
    fi

    echo "$http_code"
}

# elevenlabs_release_lock: Emergency lock release (call in trap handlers)
# Never fails - always returns 0
elevenlabs_release_lock() {
    rm -rf "$GUARD_LOCK_DIR" 2>/dev/null || true
    return 0
}
