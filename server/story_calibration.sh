#!/bin/bash
# story_calibration.sh
# SINGLE SOURCE OF TRUTH for story length calibration
# Source this file in all generation scripts
#
# LOCKED SPEC: Story lengths are based on storyLength buckets (short/full/long)
# Word count thresholds:
#   short: 250-600 words
#   full:  601-1200 words
#   long:  1201-2000 words
#
# Usage: source "$SCRIPT_DIR/story_calibration.sh"

# ============================================================
# LOCKED SPEC: storyLength word count ranges
# ============================================================
readonly MIN_WORDS_SHORT=250
readonly MAX_WORDS_SHORT=600

readonly MIN_WORDS_FULL=601
readonly MAX_WORDS_FULL=1200

readonly MIN_WORDS_LONG=1201
readonly MAX_WORDS_LONG=2000

# ============================================================
# Legacy minute-based targets (for backwards compatibility)
# These map to storyLength buckets as follows:
#   5min, 10min -> short
#   15min -> full
#   20min -> long
# ============================================================
readonly MIN_WORDS_5=250
readonly MAX_WORDS_5=600

readonly MIN_WORDS_10=250
readonly MAX_WORDS_10=600

readonly MIN_WORDS_15=601
readonly MAX_WORDS_15=1200

readonly MIN_WORDS_20=1201
readonly MAX_WORDS_20=2000

# Helper function: Get min words for storyLength bucket
get_min_words_for_bucket() {
    local bucket=$1
    case "$bucket" in
        short) echo "$MIN_WORDS_SHORT" ;;
        full) echo "$MIN_WORDS_FULL" ;;
        long) echo "$MIN_WORDS_LONG" ;;
        *) echo "$MIN_WORDS_SHORT" ;; # Default to short
    esac
}

# Helper function: Get max words for storyLength bucket
get_max_words_for_bucket() {
    local bucket=$1
    case "$bucket" in
        short) echo "$MAX_WORDS_SHORT" ;;
        full) echo "$MAX_WORDS_FULL" ;;
        long) echo "$MAX_WORDS_LONG" ;;
        *) echo "$MAX_WORDS_SHORT" ;; # Default to short
    esac
}

# Helper function: Get min words for legacy minute-based length
get_min_words() {
    local length=$1
    case "$length" in
        5) echo "$MIN_WORDS_5" ;;
        10) echo "$MIN_WORDS_10" ;;
        15) echo "$MIN_WORDS_15" ;;
        20) echo "$MIN_WORDS_20" ;;
        *) echo "$MIN_WORDS_SHORT" ;; # Default fallback
    esac
}

# Helper function: Get max words for legacy minute-based length
get_max_words() {
    local length=$1
    case "$length" in
        5) echo "$MAX_WORDS_5" ;;
        10) echo "$MAX_WORDS_10" ;;
        15) echo "$MAX_WORDS_15" ;;
        20) echo "$MAX_WORDS_20" ;;
        *) echo "$MAX_WORDS_SHORT" ;; # Default fallback
    esac
}

# Helper function: Compute storyLength bucket from word count
# LOCKED SPEC thresholds: <=600=short, 601-1200=full, 1201+=long
compute_story_length() {
    local word_count=$1
    if (( word_count <= 600 )); then
        echo "short"
    elif (( word_count <= 1200 )); then
        echo "full"
    else
        echo "long"
    fi
}

# ============================================================
# STORY_FACTORY.md mode-specific generation ranges (LOCKED)
# These are STRICTER than the broad bucket ranges above.
# Used by generate_v2_batch.sh for generation-time validation.
# ============================================================

# Traditional — tighter generation targets to center output
# IMPORTANT: These must stay within canonical bucket boundaries
#   short ≤ 600, full 601–1200, long ≥ 1201
readonly TRAD_MIN_SHORT=350
readonly TRAD_MAX_SHORT=450
readonly TRAD_MIN_FULL=700
readonly TRAD_MAX_FULL=850
readonly TRAD_MIN_LONG=1201
readonly TRAD_MAX_LONG=1400

# Creative Adult — tighter generation targets
readonly CREATIVE_ADULT_MIN_SHORT=250
readonly CREATIVE_ADULT_MAX_SHORT=400
readonly CREATIVE_ADULT_MIN_FULL=650
readonly CREATIVE_ADULT_MAX_FULL=900
readonly CREATIVE_ADULT_MIN_LONG=1201
readonly CREATIVE_ADULT_MAX_LONG=1400

# Creative Kid — tighter generation targets
readonly CREATIVE_KID_MIN_SHORT=300
readonly CREATIVE_KID_MAX_SHORT=500
readonly CREATIVE_KID_MIN_FULL=650
readonly CREATIVE_KID_MAX_FULL=900
readonly CREATIVE_KID_MIN_LONG=1201
readonly CREATIVE_KID_MAX_LONG=1400

# Mode-aware min words: get_min_words_for_mode <bucket> <mode> [is_kid]
get_min_words_for_mode() {
    local bucket="$1"
    local mode="$2"
    local is_kid="${3:-false}"

    if [[ "$mode" == "traditional" ]]; then
        case "$bucket" in
            short) echo "$TRAD_MIN_SHORT" ;;
            full)  echo "$TRAD_MIN_FULL" ;;
            long)  echo "$TRAD_MIN_LONG" ;;
            *)     echo "$TRAD_MIN_SHORT" ;;
        esac
    elif [[ "$is_kid" == "true" ]]; then
        case "$bucket" in
            short) echo "$CREATIVE_KID_MIN_SHORT" ;;
            full)  echo "$CREATIVE_KID_MIN_FULL" ;;
            long)  echo "$CREATIVE_KID_MIN_LONG" ;;
            *)     echo "$CREATIVE_KID_MIN_SHORT" ;;
        esac
    else
        case "$bucket" in
            short) echo "$CREATIVE_ADULT_MIN_SHORT" ;;
            full)  echo "$CREATIVE_ADULT_MIN_FULL" ;;
            long)  echo "$CREATIVE_ADULT_MIN_LONG" ;;
            *)     echo "$CREATIVE_ADULT_MIN_SHORT" ;;
        esac
    fi
}

# Mode-aware max words: get_max_words_for_mode <bucket> <mode> [is_kid]
get_max_words_for_mode() {
    local bucket="$1"
    local mode="$2"
    local is_kid="${3:-false}"

    if [[ "$mode" == "traditional" ]]; then
        case "$bucket" in
            short) echo "$TRAD_MAX_SHORT" ;;
            full)  echo "$TRAD_MAX_FULL" ;;
            long)  echo "$TRAD_MAX_LONG" ;;
            *)     echo "$TRAD_MAX_SHORT" ;;
        esac
    elif [[ "$is_kid" == "true" ]]; then
        case "$bucket" in
            short) echo "$CREATIVE_KID_MAX_SHORT" ;;
            full)  echo "$CREATIVE_KID_MAX_FULL" ;;
            long)  echo "$CREATIVE_KID_MAX_LONG" ;;
            *)     echo "$CREATIVE_KID_MAX_SHORT" ;;
        esac
    else
        case "$bucket" in
            short) echo "$CREATIVE_ADULT_MAX_SHORT" ;;
            full)  echo "$CREATIVE_ADULT_MAX_FULL" ;;
            long)  echo "$CREATIVE_ADULT_MAX_LONG" ;;
            *)     echo "$CREATIVE_ADULT_MAX_SHORT" ;;
        esac
    fi
}

# Export functions for use in scripts
export -f get_min_words
export -f get_max_words
export -f get_min_words_for_bucket
export -f get_max_words_for_bucket
export -f compute_story_length
export -f get_min_words_for_mode
export -f get_max_words_for_mode
