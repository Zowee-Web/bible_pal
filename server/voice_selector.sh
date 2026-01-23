#!/usr/bin/env bash
# voice_selector.sh
# Canonical voice selection utility for Bible PAL audio generation.
# Uses server/voices.json as the single source of truth for allowed narrator voices.
#
# COMPATIBILITY: macOS bash 3.2+ and Linux bash 4+
# - Does NOT use mapfile (unavailable in bash 3.2)
# - Does NOT use ${var,,} lowercase syntax (unavailable in bash 3.2)
# - Uses portable MD5 hashing (macOS md5 / Linux md5sum)
#
# Usage:
#   source "$SCRIPT_DIR/voice_selector.sh"
#   voice_key=$(select_voice_for_story "parable_001_joyful_5min" "false")
#   voice_id=$(get_voice_id "$voice_key")
#
# Functions:
#   get_allowed_voice_keys    - Returns list of valid voiceKeys from voices.json
#   get_kid_voice_keys        - Returns voiceKeys for kid-compatible voices
#   validate_voice_key        - Checks if a voiceKey is in the allowlist
#   select_voice_for_story    - Deterministic voice selection based on storyId
#   get_voice_id              - Looks up ElevenLabs ID for a voiceKey
#   get_voice_display_name    - Gets human-readable name for a voiceKey
#   get_fallback_voice        - Returns the default fallback voiceKey
#
# IMPORTANT: All voice selection MUST go through this utility to ensure:
#   1. Only voices in voices.json are used (allowlist enforcement)
#   2. Forbidden voices (Grace, Abilene, Grant) are never selected
#   3. Consistent deterministic assignment across regenerations

set -euo pipefail

# Resolve the directory containing this script
# Works when sourced or executed directly, from any working directory
# Compatible with bash 3.2+ (macOS default)
_resolve_voice_selector_dir() {
    local source_file=""

    # Try BASH_SOURCE first (works in bash when sourced)
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        source_file="${BASH_SOURCE[0]}"
    elif [ -n "${0:-}" ]; then
        # Fallback to $0 (works when executed directly)
        source_file="$0"
    fi

    if [ -n "$source_file" ] && [ -f "$source_file" ]; then
        # Resolve to absolute path
        local dir
        dir="$(cd "$(dirname "$source_file")" && pwd)"
        echo "$dir"
    else
        # Last resort: assume we're in the project root
        if [ -f "server/voices.json" ]; then
            echo "$(pwd)/server"
        elif [ -f "voices.json" ]; then
            pwd
        else
            echo "ERROR: Cannot resolve voice_selector.sh directory" >&2
            return 1
        fi
    fi
}

VOICE_SELECTOR_DIR="$(_resolve_voice_selector_dir)"
VOICES_FILE="$VOICE_SELECTOR_DIR/voices.json"

# Validate voices.json exists
if [ ! -f "$VOICES_FILE" ]; then
    echo "ERROR: voices.json not found at $VOICES_FILE" >&2
    echo "VOICE_SELECTOR_DIR=$VOICE_SELECTOR_DIR" >&2
    exit 1
fi

# Get list of allowed voice keys from voices.json
# Returns one voiceKey per line
get_allowed_voice_keys() {
    jq -r '.voices[].voiceKey' "$VOICES_FILE"
}

# Get list of kid-compatible voice keys
# Returns voiceKeys where audience includes "kid"
get_kid_voice_keys() {
    jq -r '.voices[] | select(.audience | index("kid")) | .voiceKey' "$VOICES_FILE"
}

# Validate that a voiceKey exists in the allowlist
# Returns 0 if valid, 1 if invalid
validate_voice_key() {
    local voice_key="$1"

    if [ -z "$voice_key" ]; then
        return 1
    fi

    local exists
    exists=$(jq -r --arg key "$voice_key" '.voices[] | select(.voiceKey == $key) | .voiceKey' "$VOICES_FILE")

    if [ -n "$exists" ]; then
        return 0
    else
        return 1
    fi
}

# Get the fallback voice key from voices.json
get_fallback_voice() {
    jq -r '.selectionAlgorithm.fallback // "VOICE_JAMES_HUSKY"' "$VOICES_FILE"
}

# Deterministic voice selection based on storyId
# Uses MD5 hash of storyId to select voice index
# Args:
#   $1 - storyId (e.g., "parable_001_joyful_5min")
#   $2 - is_kid ("true" or "false") - filter to kid-compatible voices
# Returns: voiceKey (printed to stdout)
select_voice_for_story() {
    local story_id="$1"
    local is_kid="${2:-false}"

    # Get voice count based on kid mode
    local voice_count
    local selected_voice

    if [ "$is_kid" = "true" ]; then
        voice_count=$(jq '[.voices[] | select(.audience | index("kid"))] | length' "$VOICES_FILE")
    else
        voice_count=$(jq '.voices | length' "$VOICES_FILE")
    fi

    if [ "$voice_count" -eq 0 ]; then
        echo "ERROR: No voices available in pool" >&2
        get_fallback_voice
        return
    fi

    # Deterministic hash: md5 of storyId
    # macOS uses 'md5 -q', Linux uses 'md5sum'
    local hash_hex
    if command -v md5 >/dev/null 2>&1; then
        # macOS
        hash_hex=$(printf '%s' "$story_id" | md5 -q)
    else
        # Linux
        hash_hex=$(printf '%s' "$story_id" | md5sum | cut -d' ' -f1)
    fi

    # Take first 8 hex chars and convert to decimal
    # Use printf to extract substring (bash 3.2 compatible)
    hash_hex=$(printf '%.8s' "$hash_hex")

    # Convert hex to decimal using printf (portable)
    local hash_dec
    hash_dec=$(printf '%d' "0x$hash_hex")

    local index=$((hash_dec % voice_count))

    # Get voice at index using jq
    if [ "$is_kid" = "true" ]; then
        selected_voice=$(jq -r --argjson idx "$index" '[.voices[] | select(.audience | index("kid"))] | .[$idx].voiceKey' "$VOICES_FILE")
    else
        selected_voice=$(jq -r --argjson idx "$index" '.voices[$idx].voiceKey' "$VOICES_FILE")
    fi

    printf '%s\n' "$selected_voice"
}

# Get ElevenLabs voice ID for a voiceKey
# Args:
#   $1 - voiceKey (e.g., "VOICE_JAMES_HUSKY")
# Returns: ElevenLabs voice ID or empty string if not found
get_voice_id() {
    local voice_key="$1"

    local voice_id
    voice_id=$(jq -r --arg key "$voice_key" '.voices[] | select(.voiceKey == $key) | .elevenLabsId' "$VOICES_FILE")

    if [ -z "$voice_id" ] || [ "$voice_id" = "null" ]; then
        echo "ERROR: voiceKey '$voice_key' not found in voices.json" >&2
        return 1
    fi

    printf '%s\n' "$voice_id"
}

# Get voice display name for a voiceKey
get_voice_display_name() {
    local voice_key="$1"
    jq -r --arg key "$voice_key" '.voices[] | select(.voiceKey == $key) | .displayName' "$VOICES_FILE"
}

# Check if a voice name is in the forbidden list
# Returns 0 if forbidden (bad), 1 if allowed (good)
is_voice_forbidden() {
    local voice_name="$1"

    # Convert to lowercase using tr (bash 3.2 compatible)
    local voice_lower
    voice_lower=$(printf '%s' "$voice_name" | tr '[:upper:]' '[:lower:]')

    local forbidden_list
    forbidden_list=$(jq -r '._forbiddenVoices.voices[]' "$VOICES_FILE" 2>/dev/null || echo "")

    local f f_lower
    for f in $forbidden_list; do
        f_lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
        if [ "$voice_lower" = "$f_lower" ]; then
            return 0  # Is forbidden
        fi
    done

    return 1  # Not forbidden
}

# Print voice pool summary (for debugging)
print_voice_pool_summary() {
    echo "=== Voice Pool Summary ==="
    echo "Total voices: $(jq '.voices | length' "$VOICES_FILE")"
    echo "Kid-compatible: $(jq '[.voices[] | select(.audience | index("kid"))] | length' "$VOICES_FILE")"
    echo "Adult-only: $(jq '[.voices[] | select(.audience | index("kid") | not)] | length' "$VOICES_FILE")"
    echo "Fallback: $(get_fallback_voice)"
    echo ""
    echo "Forbidden voices:"
    jq -r '._forbiddenVoices.voices[]' "$VOICES_FILE" 2>/dev/null | sed 's/^/  - /'
    echo ""
}

# Export VOICES_FILE for use by scripts that source this file
export VOICES_FILE
