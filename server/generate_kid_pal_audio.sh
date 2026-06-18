#!/bin/bash
# generate_kid_pal_audio.sh
# Pre-renders the kid PAL reflection + transition audio (SPEC 51.7) for all 3
# PAL voices, using the same premium engine + settings as the rest of PAL audio
# (eleven_v3, stability 0.35 / similarity 0.75 / style 0.40 / speaker boost).
#
# CRITICAL: SERVER-SIDE script. Generated MP3s ship as bundled assets; the
# mobile app NEVER calls ElevenLabs at runtime.
#
# Source of truth is the Dart const (lib/core/kid_pal_*_lines.dart). Run the
# extractor first to refresh the manifest this reads:
#     python3 server/extract_kid_pal_lines.py
#
# Usage:
#     ./server/generate_kid_pal_audio.sh                 # all 3 voices
#     ./server/generate_kid_pal_audio.sh VOICE_HOPE      # one voice
#     FORCE_REGEN=1 ./server/generate_kid_pal_audio.sh   # overwrite existing
#
# Output: assets/pal/audio/{voiceKey}/{lineId}.mp3 (38 lines x 3 voices = 114).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
VOICES_FILE="$SCRIPT_DIR/voices.json"
MANIFEST="$SCRIPT_DIR/kid_pal_lines_manifest.json"
OUTPUT_BASE="$PROJECT_ROOT/assets/pal/audio"

# PAL audio standard: eleven_v3 (premium voice experience). Story audio uses
# eleven_turbo_v2_5 separately. Do not mix.
PAL_MODEL_ID="eleven_v3"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

command -v jq >/dev/null 2>&1   || { echo -e "${RED}Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl required${NC}" >&2; exit 1; }

for f in "$ENV_FILE" "$VOICES_FILE" "$MANIFEST"; do
    [[ -f "$f" ]] || { echo -e "${RED}Error: required file not found: $f${NC}" >&2; exit 1; }
done

# Load .env (manual parse: tolerate comments / blank lines)
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}Error: ELEVENLABS_API_KEY not found in .env${NC}" >&2
    exit 1
fi

# Voice filter: optional first arg selects a single voice.
ALL_VOICES=("VOICE_HOPE" "VOICE_SHEPHERD" "VOICE_STILLWATER")
if [[ $# -ge 1 ]]; then
    PAL_VOICES=("$1")
else
    PAL_VOICES=("${ALL_VOICES[@]}")
fi

resolve_voice_id() {
    local voice_key="$1" el_id
    el_id=$(jq -r --arg key "$voice_key" \
        '.palVoices[] | select(.voiceKey == $key) | .elevenLabsId' "$VOICES_FILE")
    if [[ -z "$el_id" || "$el_id" == "null" ]]; then
        echo -e "${RED}Error: voice key '$voice_key' not found in voices.json palVoices${NC}" >&2
        exit 1
    fi
    echo "$el_id"
}

collect_lines() {
    # All kid lines (reflection + transition) as id\ttext pairs.
    jq -r '(.reflection + .transition)[] | "\(.id)\t\(.text)"' "$MANIFEST"
}

generate_one() {
    local voice_key="$1" el_id="$2" line_id="$3" text="$4"
    local output_dir="$OUTPUT_BASE/$voice_key"
    local output_file="$output_dir/${line_id}.mp3"

    if [[ -f "$output_file" && -s "$output_file" && "${FORCE_REGEN:-0}" != "1" ]]; then
        echo -e "  ${GREEN}skip${NC} $voice_key/$line_id.mp3 (exists)"
        return 2  # signal: skipped
    fi

    mkdir -p "$output_dir"
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -s ' ')
    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    local json_payload http_code curl_exit=0
    json_payload=$(jq -n --arg text "$text" --arg model "$PAL_MODEL_ID" '{
        text: $text, model_id: $model,
        voice_settings: {stability:0.35, similarity_boost:0.75, style:0.40, use_speaker_boost:true}
    }')

    http_code=$(curl -sS --connect-timeout 10 --max-time 120 -w "%{http_code}" \
        -o "$output_file" -X POST \
        "https://api.elevenlabs.io/v1/text-to-speech/${el_id}" \
        -H "xi-api-key: $ELEVENLABS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload") || curl_exit=$?

    if [[ "$curl_exit" -ne 0 ]]; then
        echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (curl error $curl_exit)"; rm -f "$output_file"; return 1
    fi
    if [[ "$http_code" == "200" && -s "$output_file" ]]; then
        echo -e "  ${GREEN}done${NC} $voice_key/$line_id.mp3 (${char_count} chars)"; return 0
    fi
    echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (HTTP $http_code)"; rm -f "$output_file"; return 1
}

echo -e "${CYAN}Bible PAL - Kid PAL audio (SPEC 51.7)  model=${PAL_MODEL_ID}${NC}"

TOTAL=0; GENERATED=0; SKIPPED=0; FAILED=0
lines=$(collect_lines)

for voice_key in "${PAL_VOICES[@]}"; do
    el_id=$(resolve_voice_id "$voice_key")
    echo -e "\n${CYAN}Voice: $voice_key${NC} (${el_id:0:8}...)"
    while IFS=$'\t' read -r line_id text; do
        [[ -z "$line_id" ]] && continue
        ((TOTAL++)) || true
        set +e; generate_one "$voice_key" "$el_id" "$line_id" "$text"; rc=$?; set -e
        case "$rc" in
            0) ((GENERATED++)) || true ;;
            2) ((SKIPPED++)) || true ;;
            *) ((FAILED++)) || true ;;
        esac
    done <<< "$lines"
done

echo -e "\n${CYAN}Total: ${TOTAL}  Generated: ${GENERATED}  Skipped: ${SKIPPED}  Failed: ${FAILED}${NC}"
[[ "$FAILED" -eq 0 ]]
