#!/bin/bash
# story_dna.sh — Creative Story DNA Planner
# Source this file in generate_v2_batch.sh
#
# Provides deterministic structural diversity for creative story generation.
# Assigns opening_type, structure_type, setting_emphasis, character_archetype,
# tone, and narrator_voice from rotating pools using index-based modular arithmetic.
#
# Usage:
#   source "$SCRIPT_DIR/story_dna.sh"
#   init_dna_guard
#   dna_json=$(get_story_dna "$index" "$story_id")

# ============================================================
# Diversity Pools
# ============================================================

DNA_OPENING_TYPES=(
    "dialogue"
    "action"
    "question"
    "emotional_reflection"
    "memory"
    "object_focus"
    "conflict"
    "setting"
)

DNA_STRUCTURE_TYPES=(
    "conversation"
    "journey"
    "witness"
    "flashback"
    "unexpected_encounter"
    "problem_solution"
    "parallel_lives"
    "object_lesson"
)

# Weighted: 3 low, 3 medium, 2 high — biased away from location-heavy openings
DNA_SETTING_EMPHASIS=(
    "low" "low" "low"
    "medium" "medium" "medium"
    "high" "high"
)

DNA_CHARACTER_ARCHETYPES=(
    "traveling merchant"
    "shepherd"
    "fisherman"
    "widow"
    "child"
    "craftsman"
    "teacher"
    "farmer"
    "healer"
    "stranger"
)

DNA_TONES=(
    "hopeful"
    "reflective"
    "warm"
    "bittersweet"
    "wonder"
    "gentle"
    "solemn"
    "tender"
)

DNA_NARRATOR_VOICES=(
    "fireside"
    "literary"
    "folk_tale"
    "spare"
)

# ============================================================
# Deterministic Rotation
# ============================================================
# Prime-number offsets per pool prevent lockstep rotation.
# Same index always produces the same DNA (deterministic, testable).

compute_story_dna() {
    local idx="$1"
    local story_id="$2"

    local opening="${DNA_OPENING_TYPES[ $((idx % ${#DNA_OPENING_TYPES[@]})) ]}"
    local structure="${DNA_STRUCTURE_TYPES[ $(( (idx + 3) % ${#DNA_STRUCTURE_TYPES[@]} )) ]}"
    local setting="${DNA_SETTING_EMPHASIS[ $(( (idx + 5) % ${#DNA_SETTING_EMPHASIS[@]} )) ]}"
    local archetype="${DNA_CHARACTER_ARCHETYPES[ $(( (idx + 7) % ${#DNA_CHARACTER_ARCHETYPES[@]} )) ]}"
    local tone="${DNA_TONES[ $(( (idx + 11) % ${#DNA_TONES[@]} )) ]}"
    local narrator="${DNA_NARRATOR_VOICES[ $(( (idx + 13) % ${#DNA_NARRATOR_VOICES[@]} )) ]}"

    jq -n \
        --argjson sid "$story_id" \
        --arg ot "$opening" \
        --arg st "$structure" \
        --arg se "$setting" \
        --arg ca "$archetype" \
        --arg tn "$tone" \
        --arg nv "$narrator" \
        '{story_id: $sid, opening_type: $ot, structure_type: $st,
          setting_emphasis: $se, character_archetype: $ca, tone: $tn,
          narrator_voice: $nv}'
}

# ============================================================
# Repetition Guard (batch-local)
# ============================================================
# Tracks recent DNA within the current batch run to prevent
# consecutive stories from sharing the same opening or structure.
# This file is batch-local — reset at batch start.
# For cross-batch truth, read storyDna from existing meta.json files.

DNA_GUARD_FILE=""

init_dna_guard() {
    DNA_GUARD_FILE="${SCRIPT_DIR:-.}/.dna_history.json"
    # Always start fresh per batch
    echo '[]' > "$DNA_GUARD_FILE"
}

# Seed the guard from existing meta.json files (cross-batch awareness)
seed_dna_guard_from_metadata() {
    local stories_dir="$1"
    local creative_dir="$stories_dir/creative"
    [[ -d "$creative_dir" ]] || return 0

    local recent_dna='[]'
    local count=0
    # Scan creative meta files in reverse ID order; collect last 3 WITH storyDna
    for meta_file in $(ls -1 "$creative_dir"/*/meta_*.json 2>/dev/null | sort -t'_' -k2 -n -r); do
        [ $count -ge 3 ] && break
        local dna
        dna=$(jq '.storyDna // empty' "$meta_file" 2>/dev/null)
        if [ -n "$dna" ] && [ "$dna" != "null" ]; then
            recent_dna=$(echo "$recent_dna" | jq --argjson d "$dna" '[$d] + .')
            count=$((count + 1))
        fi
    done

    echo "$recent_dna" > "$DNA_GUARD_FILE"
}

check_repetition_guard() {
    local opening="$1"
    local structure="$2"
    local max_consecutive=2

    [[ -f "$DNA_GUARD_FILE" ]] || return 0

    local history
    history=$(cat "$DNA_GUARD_FILE")
    local history_len
    history_len=$(echo "$history" | jq 'length')

    [[ $history_len -eq 0 ]] && return 0

    local consecutive_opening=0
    local consecutive_structure=0

    for ((i = history_len - 1; i >= 0 && i >= history_len - max_consecutive; i--)); do
        local prev_opening prev_structure
        prev_opening=$(echo "$history" | jq -r ".[$i].opening_type")
        prev_structure=$(echo "$history" | jq -r ".[$i].structure_type")

        [[ "$prev_opening" == "$opening" ]] && consecutive_opening=$((consecutive_opening + 1))
        [[ "$prev_structure" == "$structure" ]] && consecutive_structure=$((consecutive_structure + 1))
    done

    if [[ $consecutive_opening -ge $max_consecutive ]] || \
       [[ $consecutive_structure -ge $max_consecutive ]]; then
        return 1  # Collision
    fi
    return 0
}

record_dna() {
    local dna_json="$1"
    [[ -f "$DNA_GUARD_FILE" ]] || return 0

    local history
    history=$(cat "$DNA_GUARD_FILE")
    history=$(echo "$history" | jq --argjson new "$dna_json" '. + [$new] | .[-3:]')
    echo "$history" > "$DNA_GUARD_FILE"
}

# ============================================================
# Main Entry Point
# ============================================================
# Returns valid DNA with repetition guard applied.
# If guard detects collision, advances the index (up to 4 attempts).

get_story_dna() {
    local base_idx="$1"
    local story_id="$2"
    local max_advances=4
    local idx=$base_idx

    for ((attempt = 0; attempt < max_advances; attempt++)); do
        local dna
        dna=$(compute_story_dna "$idx" "$story_id")
        local opening structure
        opening=$(echo "$dna" | jq -r '.opening_type')
        structure=$(echo "$dna" | jq -r '.structure_type')

        if check_repetition_guard "$opening" "$structure"; then
            record_dna "$dna"
            echo "$dna"
            return 0
        fi

        echo -e "  DNA: collision at index $idx, advancing..." >&2
        idx=$((idx + 1))
    done

    # Fallback: use base index DNA even if collision
    local dna
    dna=$(compute_story_dna "$base_idx" "$story_id")
    record_dna "$dna"
    echo "$dna"
}

# ============================================================
# Batch Ordinal Computation
# ============================================================
# Compute the ordinal position of a story among creative entries in a batch.
# Usage: compute_creative_ordinal <target_id> <story_def1> [story_def2 ...]
# Prints the 0-based ordinal index to stdout.
# Returns non-zero if the story ID is not found.

compute_creative_ordinal() {
    local target_id="$1"
    shift
    local ordinal=0

    for story_def in "$@"; do
        IFS='|' read -r id mode _ <<< "$story_def"

        if [[ "$id" == "$target_id" ]]; then
            echo "$ordinal"
            return 0
        fi

        if [[ "$mode" == "creative" ]]; then
            ordinal=$((ordinal + 1))
        fi
    done

    echo "ERROR: story $target_id not found in batch definition" >&2
    return 1
}
