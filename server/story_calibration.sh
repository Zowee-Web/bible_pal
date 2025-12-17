#!/bin/bash
# story_calibration.sh
# SINGLE SOURCE OF TRUTH for story length calibration
# Source this file in all generation scripts
#
# CRITICAL: Story lengths are calibrated to NARRATED audio playback (~130-150 wpm)
# NOT silent reading speed. All stories MUST pass narrated word-count validation.
#
# Usage: source "$SCRIPT_DIR/story_calibration.sh"

# Word count targets by length (minutes)
# Format: MIN_WORDS_<length> and MAX_WORDS_<length>

# 5-minute stories
readonly MIN_WORDS_5=600
readonly MAX_WORDS_5=750

# 10-minute stories
readonly MIN_WORDS_10=1200
readonly MAX_WORDS_10=1500

# 15-minute stories
readonly MIN_WORDS_15=1800
readonly MAX_WORDS_15=2250

# 20-minute stories
readonly MIN_WORDS_20=2400
readonly MAX_WORDS_20=3000

# Helper function: Get min words for a length
get_min_words() {
    local length=$1
    case "$length" in
        5) echo "$MIN_WORDS_5" ;;
        10) echo "$MIN_WORDS_10" ;;
        15) echo "$MIN_WORDS_15" ;;
        20) echo "$MIN_WORDS_20" ;;
        *) echo "600" ;; # Default fallback
    esac
}

# Helper function: Get max words for a length
get_max_words() {
    local length=$1
    case "$length" in
        5) echo "$MAX_WORDS_5" ;;
        10) echo "$MAX_WORDS_10" ;;
        15) echo "$MAX_WORDS_15" ;;
        20) echo "$MAX_WORDS_20" ;;
        *) echo "750" ;; # Default fallback
    esac
}

# Export functions for use in scripts
export -f get_min_words
export -f get_max_words
