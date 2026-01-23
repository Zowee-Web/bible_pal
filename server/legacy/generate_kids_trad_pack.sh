#!/bin/bash
# Kid-Friendly Traditional Bible Stories Generator v4.3.6
# MULTI-CHAPTER CONTINUATION: Generate longer stories via continuation chapters
# v4.3: Solves Gemma's 800-1000 word ceiling by generating multiple chapters
# v4.3.1: Polish - remove scene headings, clean sentence endings
# v4.3.2: 5min safety net - bonus mini-segment if below minimum after cleaning
# v4.3.3: KID-SAFETY - explicit content guidelines (no violence/blood/scary imagery)
# v4.3.4: BIBLE FIDELITY - enforce biblical accuracy while maintaining kid-safety
# v4.3.5: LIGHTER FIDELITY - remove AI rewrite, use hard guardrails in prompts only
# v4.3.6: QUALITY GATES - improved hallucination detection, Bible fact anchors, structural leak prevention
#
# Test single story: TEST_MODE=single TEST_STORY_ID=101 timeout 600 server/generate_kids_trad_pack_v4.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
TEMP_DIR="$OUTPUT_DIR/.temp_generation"
LOG_FILE="$OUTPUT_DIR/generation.log"
MANIFEST_CSV="$OUTPUT_DIR/kids_trad_manifest.csv"

# Timeouts
OUTLINE_TIMEOUT=180
SEGMENT_TIMEOUT=240

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

# Logging function - writes to stderr AND log file, NEVER stdout
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] $1" | tee -a "$LOG_FILE" >&2
}

echo "id,filename,mood,length,target_words,actual_words,title,bible_basis,status" > "$MANIFEST_CSV"

log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${BLUE}  Kid-Friendly Bible Stories Generator v4.3.5${NC}"
log "${BLUE}  Multi-chapter | Kid-safety | Hard guardrails (no AI rewrite)${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

STORIES=(
    "101|David and the Giant|David and Goliath|brave_courage|5min|600|540|660"
    "102|Daniel in the Lions' Den|Daniel 6|brave_courage|10min|1200|1080|1320"
    "103|Noah and the Rainbow Promise|Genesis 6-9|hopeful|5min|600|540|660"
    "104|The Good Samaritan|Luke 10:25-37|comforting|10min|1200|1080|1320"
    "105|Jesus Calms the Storm|Mark 4:35-41|calm_peaceful|5min|600|540|660"
    "106|The Lost Sheep|Luke 15:1-7|comforting|15min|1800|1620|1980"
    "107|Feeding the Five Thousand|John 6:1-15|joyful|5min|600|540|660"
    "108|Joseph Forgives His Brothers|Genesis 37-50|hopeful|10min|1200|1080|1320"
    "109|Ruth's Loyal Kindness|Book of Ruth|grateful|10min|1200|1080|1320"
    "110|Esther's Brave Choice|Book of Esther|encouraging|15min|1800|1620|1980"
    "111|The Wise and Foolish Builders|Matthew 7:24-27|trusting|15min|1800|1620|1980"
    "112|The Prodigal Son Comes Home|Luke 15:11-32|joyful|15min|1800|1620|1980"
    "113|Jonah Learns About Mercy|Book of Jonah|calm_peaceful|20min|2400|2160|2640"
    "114|The Boy Samuel Hears God|1 Samuel 3|trusting|20min|2400|2160|2640"
    "115|The Parable of the Sower|Matthew 13:1-23|encouraging|20min|2400|2160|2640"
    "116|Zacchaeus Meets Jesus|Luke 19:1-10|grateful|20min|2400|2160|2640"
)

# Count words
count_words() {
    echo "$1" | wc -w | tr -d ' '
}

# Clean Ollama output - remove all ANSI/control codes
clean_ollama_output() {
    local text=$1

    # Remove Braille spinner chars (U+2800-28FF)
    text=$(echo "$text" | sed 's/[⠀-⣿]//g')

    # Remove carriage returns
    text=$(echo "$text" | tr -d '\r')

    # Remove ANSI CSI sequences (\e[...letter)
    text=$(echo "$text" | sed $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g')

    # Remove ANSI OSC sequences (\e]...terminated)
    text=$(echo "$text" | sed $'s/\x1b\\][^\x07]*\x07//g')

    # Remove remaining escape sequences
    text=$(echo "$text" | sed $'s/\x1b[^[a-zA-Z]*[a-zA-Z]//g')

    # Remove [K and other bracket codes
    text=$(echo "$text" | sed 's/\[K//g' | sed 's/\[[0-9?]*[a-z]//g')

    # Collapse multiple blank lines
    text=$(echo "$text" | sed '/^$/N;/^\n$/D')

    echo "$text"
}

# Trim text to max words - simple word-level cut only
trim_to_max() {
    local text=$1
    local max_words=$2

    # Normalize whitespace first
    text=$(echo "$text" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    local current_words=$(count_words "$text")

    if [[ $current_words -le $max_words ]]; then
        echo "$text"
        return 0
    fi

    # Just cut at word boundary - sentence splitting is too error-prone
    echo "$text" | awk -v max="$max_words" '{
        for(i=1; i<=max && i<=NF; i++) {
            printf "%s", $i
            if (i < max && i < NF) printf " "
        }
    }'
}

# Ollama call with timeout - returns ONLY cleaned model text to stdout
ollama_call() {
    local prompt=$1
    local timeout_secs=$2
    local call_name=$3
    local output_file=$(mktemp)

    local start_time=$(date +%s)
    log "    ▶ $call_name started"

    if timeout "$timeout_secs" ollama run gemma:7b "$prompt" > "$output_file" 2>&1; then
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        # Clean the output
        local cleaned=$(clean_ollama_output "$(cat "$output_file")")
        local word_count=$(count_words "$cleaned")

        log "    ✓ $call_name completed in ${elapsed}s ($word_count words raw)"

        # Output ONLY cleaned text to stdout (for command substitution)
        echo "$cleaned"
        rm -f "$output_file"
        return 0
    else
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        log "    ${RED}✗ $call_name timed out after ${elapsed}s${NC}"
        rm -f "$output_file"
        return 1
    fi
}

# Generate a single chapter - wrapper around ollama_call
generate_chapter() {
    local prompt=$1
    local timeout=$2
    local label=$3

    ollama_call "$prompt" "$timeout" "$label"
}

# Get last N words from text (for continuation context)
get_last_words() {
    local text=$1
    local n=$2

    echo "$text" | awk -v n="$n" '{
        start = NF - n + 1
        if (start < 1) start = 1
        for (i = start; i <= NF; i++) {
            printf "%s", $i
            if (i < NF) printf " "
        }
    }'
}

# Clean trailing partial sentence (remove text after last proper ending punctuation)
clean_sentence_ending() {
    local text=$1

    # If text already ends with proper punctuation, return as-is
    if [[ "$text" =~ [.!?][[:space:]]*$ ]]; then
        echo "$text"
        return 0
    fi

    # Find last occurrence of sentence-ending punctuation
    # Use perl if available (more reliable), otherwise use sed
    if command -v perl &> /dev/null; then
        echo "$text" | perl -0777 -pe 's/[^.!?]*\z//s'
    else
        # Fallback: iteratively remove last word until we hit punctuation
        local cleaned="$text"
        while [[ ! "$cleaned" =~ [.!?][[:space:]]*$ ]] && [[ -n "$cleaned" ]]; do
            cleaned=$(echo "$cleaned" | sed 's/[[:space:]]*[^[:space:]]*$//')
        done
        echo "$cleaned"
    fi
}

generate_story() {
    local id=$1
    local title=$2
    local basis=$3
    local mood=$4
    local length=$5
    local target=$6
    local min=$7
    local max=$8

    local filename="parable_${id}_${mood}_${length}_kid_trad.txt"
    local filepath="$OUTPUT_DIR/$filename"
    local story_temp="$TEMP_DIR/story_$id"

    mkdir -p "$story_temp"

    log "${BLUE}━━ Story #$id: $title ━━${NC}"
    log "  Mood: $mood | Length: $length | Target: $target words ($min-$max)"

    # STEP 1: Generate outline
    log "  ${BLUE}[1/N] Generating outline...${NC}"
    local outline_prompt="Create a 6-beat outline that matches the Biblical account of $basis for a kid-friendly story (ages 6-11).

STORY: $title (based on $basis)
MOOD: $mood

First, list 4-8 BIBLICAL FACTS that must not change (bullet points):
- Key characters (who they are)
- Key events (what actually happens in the Bible)
- Key outcome (how it ends in the Biblical account)

Then, list 5-6 simple scene beats following these facts. One emotional arc.

Total outline: under 120 words.

KID-SAFETY CONTEXT:
- Story must be gentle and age-appropriate (ages 6-11)
- Avoid graphic violence, blood, death descriptions, scary imagery
- Focus on courage, faith, kindness, hope
- Keep conflict gentle; characters can be worried but not terrified

BIBLICAL FIDELITY:
- Stay faithful to $basis
- Do not invent major plot changes or extra characters that alter the core story
- Keep key actions and outcomes from the Biblical account

IMPORTANT: This outline is for planning only. Do NOT include any outline text, headings, scene numbers, or labels (like 'Resolution:', 'Conclusion:', 'Ending:') in the actual story."

    local outline
    if ! outline=$(ollama_call "$outline_prompt" "$OUTLINE_TIMEOUT" "Outline"); then
        log "  ${RED}✗ FAIL: Outline generation failed${NC}"
        echo "$id,$filename,$mood,$length,$target,0,$title,$basis,FAIL_OUTLINE" >> "$MANIFEST_CSV"
        return 1
    fi

    echo "$outline" > "$story_temp/outline.txt"

    # Decide: 5min uses 3-segment approach, longer uses multi-chapter
    if [[ "$length" == "5min" ]]; then
        # === 5MIN PATH: Keep existing 3-segment approach ===
        log "  ${BLUE}[Using 3-segment approach for 5min]${NC}"

        local seg_a_target=130 seg_a_max=140
        local seg_b_target=250 seg_b_max=280
        local seg_c_target=130 seg_c_max=140

        # Segment A
        log "  ${BLUE}[2/4] Generating Segment A (opening)...${NC}"
        local seg_a_prompt="Write the opening of this Bible story for kids (ages 6-11).

## $title

MOOD: $mood
TARGET: Write approximately $seg_a_target words. Write with rich detail and sensory descriptions.

OUTLINE:
$outline

Opening section:
- 3-4 paragraphs (each 2-4 sentences)
- Introduce main character with descriptive details
- Include sensory details (sights, sounds, feelings)
- Set the scene vividly
- Gentle, warm tone appropriate for children

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change the sequence of key events or the outcome
- Do NOT add extra locations, chase scenes, or invented plot twists
- You MAY add gentle dialogue, feelings, and kid-friendly descriptions
- You MAY soften violent wording (e.g., 'fell down' instead of graphic details)
- The plot MUST match the Bible account for $basis
- Follow the outline Facts that must not change exactly

Write the opening section with rich storytelling. Aim for around $seg_a_target words."

        local segment_a_raw
        if ! segment_a_raw=$(ollama_call "$seg_a_prompt" "$SEGMENT_TIMEOUT" "Segment A"); then
            log "  ${RED}✗ FAIL: Segment A generation failed${NC}"
            echo "$id,$filename,$mood,$length,$target,0,$title,$basis,FAIL_SEGMENT_A" >> "$MANIFEST_CSV"
            return 1
        fi

        echo "$segment_a_raw" > "$story_temp/segment_a_raw.txt"
        local a_raw_words=$(count_words "$segment_a_raw")

        local segment_a=$(trim_to_max "$segment_a_raw" "$seg_a_max")
        echo "$segment_a" > "$story_temp/segment_a.txt"
        local a_words=$(count_words "$segment_a")

        log "    Segment A: $a_raw_words words raw → $a_words words after trim (max: $seg_a_max)"

        # Segment B
        log "  ${BLUE}[3/4] Generating Segment B (challenge)...${NC}"
        local seg_b_prompt="Continue this Bible story with the middle section.

STORY SO FAR:
$segment_a

TARGET: Write approximately $seg_b_target words. Write with rich detail and vivid storytelling.

Middle section:
- 4-6 paragraphs with descriptive details
- The main challenge or journey
- Show character thoughts and feelings
- Include sensory details and concrete moments
- Same gentle, warm tone

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change the sequence of key events or the outcome
- Do NOT add extra locations, chase scenes, or invented plot twists
- You MAY add gentle dialogue, feelings, and kid-friendly descriptions
- You MAY soften violent wording (e.g., 'fell down' instead of graphic details)
- The plot MUST match the Bible account for $basis
- Follow the outline Facts that must not change exactly

Continue the story with engaging detail. Aim for around $seg_b_target words."

        local segment_b_raw
        if ! segment_b_raw=$(ollama_call "$seg_b_prompt" "$SEGMENT_TIMEOUT" "Segment B"); then
            log "  ${RED}✗ FAIL: Segment B generation failed${NC}"
            echo "$id,$filename,$mood,$length,$target,$a_words,$title,$basis,FAIL_SEGMENT_B" >> "$MANIFEST_CSV"
            return 1
        fi

        echo "$segment_b_raw" > "$story_temp/segment_b_raw.txt"
        local b_raw_words=$(count_words "$segment_b_raw")

        local segment_b=$(trim_to_max "$segment_b_raw" "$seg_b_max")
        echo "$segment_b" > "$story_temp/segment_b.txt"
        local b_words=$(count_words "$segment_b")

        log "    Segment B: $b_raw_words words raw → $b_words words after trim (max: $seg_b_max)"

        # Segment C
        log "  ${BLUE}[4/4] Generating Segment C (resolution)...${NC}"
        local seg_c_prompt="Complete this Bible story with the ending.

STORY SO FAR:
$segment_a

$segment_b

TARGET: Write approximately $seg_c_target words. Write with warm, descriptive detail.

Resolution section:
- 3-4 paragraphs with descriptive storytelling
- How the challenge resolves with emotional detail
- Character's feelings and realizations
- Gentle kid reflection (2-3 sentences)
- Warm, hopeful closing

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change the sequence of key events or the outcome
- Do NOT add extra locations, chase scenes, or invented plot twists
- You MAY add gentle dialogue, feelings, and kid-friendly descriptions
- You MAY soften violent wording (e.g., 'fell down' instead of graphic details)
- The plot MUST match the Bible account for $basis
- Follow the outline Facts that must not change exactly

Complete the story with rich detail. Aim for around $seg_c_target words."

        local segment_c_raw
        if ! segment_c_raw=$(ollama_call "$seg_c_prompt" "$SEGMENT_TIMEOUT" "Segment C"); then
            log "  ${RED}✗ FAIL: Segment C generation failed${NC}"
            echo "$id,$filename,$mood,$length,$target,$((a_words + b_words)),$title,$basis,FAIL_SEGMENT_C" >> "$MANIFEST_CSV"
            return 1
        fi

        echo "$segment_c_raw" > "$story_temp/segment_c_raw.txt"
        local c_raw_words=$(count_words "$segment_c_raw")

        local segment_c=$(trim_to_max "$segment_c_raw" "$seg_c_max")
        echo "$segment_c" > "$story_temp/segment_c.txt"
        local c_words=$(count_words "$segment_c")

        log "    Segment C: $c_raw_words words raw → $c_words words after trim (max: $seg_c_max)"

        # Combine
        local full_story="$segment_a

$segment_b

$segment_c"

        # Clean any trailing partial sentence
        full_story=$(clean_sentence_ending "$full_story")
        local total_words=$(count_words "$full_story")

        # If below minimum, generate one small bonus continuation
        if [[ $total_words -lt $min ]]; then
            log "  ${YELLOW}[5min bonus: $total_words < $min, generating mini-continuation]${NC}"

            local context=$(get_last_words "$full_story" 250)
            local needed=$((min - total_words + 30))
            local bonus_cap=$((needed > 100 ? needed : 100))

            local bonus_prompt="Continue the SAME story. Do NOT restart or recap. Write 1-2 more short paragraphs to complete the story.

STORY SO FAR (ending):
$context

Write the final continuation:
- 1-2 paragraphs only
- Kid-friendly (ages 6-11), traditional tone
- Bring story to a gentle close
- Aim for ~$needed words

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change events or outcome from $basis
- You MAY add gentle dialogue and feelings; you MAY soften violent wording

CRITICAL: Output ONLY story prose. Do NOT include headings, scene numbers, markdown formatting, bullet lists, or labels like 'Resolution:', 'Conclusion:', 'Ending:', 'Scene 1', etc. Write pure narrative text only.

Continue now."

            local bonus_raw
            if bonus_raw=$(ollama_call "$bonus_prompt" "$SEGMENT_TIMEOUT" "5min bonus"); then
                local bonus_raw_words=$(count_words "$bonus_raw")
                local bonus_trimmed=$(trim_to_max "$bonus_raw" "$bonus_cap")
                local bonus_words=$(count_words "$bonus_trimmed")

                log "    5min bonus: $bonus_raw_words words raw → $bonus_words words after trim (cap: $bonus_cap)"

                full_story="$full_story

$bonus_trimmed"

                # Clean ending again after bonus
                full_story=$(clean_sentence_ending "$full_story")
                total_words=$(count_words "$full_story")

                log "  ${BLUE}Final: $total_words words (A+B+C+bonus, cleaned ending)${NC}"
            else
                log "  ${YELLOW}5min bonus failed, proceeding with $total_words words${NC}"
                log "  ${BLUE}Final: $total_words words (A:$a_words + B:$b_words + C:$c_words, cleaned ending)${NC}"
            fi
        else
            log "  ${BLUE}Final: $total_words words (A:$a_words + B:$b_words + C:$c_words, cleaned ending)${NC}"
        fi

        echo "$full_story" > "$filepath"

    else
        # === MULTI-CHAPTER PATH for 10/15/20min ===
        log "  ${BLUE}[Using multi-chapter continuation approach]${NC}"

        local chapter_count chapter_target chapter_cap
        case "$length" in
            10min)
                chapter_count=4
                chapter_target=320
                chapter_cap=380
                ;;
            15min)
                chapter_count=6
                chapter_target=320
                chapter_cap=380
                ;;
            20min)
                chapter_count=8
                chapter_target=320
                chapter_cap=380
                ;;
        esac

        log "  ${BLUE}[Will generate $chapter_count chapters, ~$chapter_target words each]${NC}"

        local full_story=""
        local current_words=0

        for (( i=1; i<=chapter_count; i++ )); do
            local remaining=$((max - current_words))
            if [[ $remaining -le 0 ]]; then
                log "    ${GREEN}✓ Reached max words, stopping chapter generation${NC}"
                break
            fi

            log "  ${BLUE}[Chapter $i/$chapter_count]${NC}"

            # Context: last ~300 words of story so far
            local context
            if [[ -z "$full_story" ]]; then
                context="[This is the start of the story]"
            else
                context=$(get_last_words "$full_story" 300)
            fi

            # Determine if this is the last chapter
            local is_last=""
            if [[ $i -eq $chapter_count ]]; then
                is_last="This is the FINAL chapter - bring the story to a warm, complete conclusion with a gentle kid reflection."
            fi

            local chapter_prompt="Continue the SAME story. Do NOT restart or recap. Write the next scene only.

TITLE: $title
MOOD: $mood
THIS IS CHAPTER $i of $chapter_count
$is_last

OUTLINE:
$outline

STORY SO FAR (last part):
$context

Write the next scene:
- 2-5 short paragraphs
- Kid-friendly (ages 6-11)
- Traditional Bible storytelling tone
- Rich sensory details
- Aim for ~$chapter_target words
- End naturally but not required to conclude (unless final chapter)

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change the sequence of key events or the outcome
- Do NOT add extra locations, chase scenes, or invented plot twists
- You MAY add gentle dialogue, feelings, and kid-friendly descriptions
- You MAY soften violent wording (e.g., 'fell down' instead of graphic details)
- The plot MUST match the Bible account for $basis
- Follow the outline Facts that must not change exactly

CRITICAL: Output ONLY story prose. Do NOT include headings, scene numbers, markdown formatting, bullet lists, or labels like 'Resolution:', 'Conclusion:', 'Ending:', 'Scene 1', 'Chapter 2', etc. Write pure narrative text only.

Continue the story now."

            local chapter_raw
            if ! chapter_raw=$(generate_chapter "$chapter_prompt" "$SEGMENT_TIMEOUT" "Chapter $i"); then
                log "  ${RED}✗ FAIL: Chapter $i generation failed${NC}"
                echo "$id,$filename,$mood,$length,$target,$current_words,$title,$basis,FAIL_CHAPTER_$i" >> "$MANIFEST_CSV"
                return 1
            fi

            echo "$chapter_raw" > "$story_temp/chapter_${i}_raw.txt"
            local chapter_raw_words=$(count_words "$chapter_raw")

            # Cap this chapter
            local actual_cap=$chapter_cap
            if [[ $remaining -lt $chapter_cap ]]; then
                actual_cap=$remaining
            fi

            local chapter_trimmed=$(trim_to_max "$chapter_raw" "$actual_cap")
            echo "$chapter_trimmed" > "$story_temp/chapter_${i}.txt"
            local chapter_words=$(count_words "$chapter_trimmed")

            log "    Chapter $i: $chapter_raw_words words raw → $chapter_words words after trim (cap: $actual_cap)"

            # Append to full story
            if [[ -n "$full_story" ]]; then
                full_story="$full_story

$chapter_trimmed"
            else
                full_story="$chapter_trimmed"
            fi

            current_words=$(count_words "$full_story")
            log "    Running total: $current_words words"
        done

        # Check if we need bonus chapters to reach minimum
        local bonus_attempts=0
        while [[ $current_words -lt $min && $bonus_attempts -lt 3 ]]; do
            bonus_attempts=$((bonus_attempts + 1))
            local remaining=$((max - current_words))
            if [[ $remaining -le 0 ]]; then
                break
            fi

            log "  ${YELLOW}[Bonus chapter $bonus_attempts to reach minimum]${NC}"

            local context=$(get_last_words "$full_story" 300)
            local bonus_prompt="Continue the SAME story. Do NOT restart. Write one more scene.

TITLE: $title
MOOD: $mood

STORY SO FAR (last part):
$context

Write the next scene:
- 2-4 paragraphs
- Kid-friendly, traditional tone
- Aim for ~$chapter_target words
- Continue naturally

KID-SAFETY RULES (CRITICAL):
- NO graphic violence, blood, gore, or death descriptions
- NO scary or frightening imagery (monsters, demons, grotesque details)
- NO intense fear or terror - use 'worried' or 'nervous' instead
- Keep conflict gentle and age-appropriate
- Focus on courage, faith, kindness, and hope
- Use positive, warm, comforting language

BIBLE FIDELITY RULES (CRITICAL - must follow):
- Do NOT invent new major characters, extra enemies, extra battles, or new subplots
- Do NOT change events or outcome from $basis
- You MAY add gentle dialogue and feelings; you MAY soften violent wording

CRITICAL: Output ONLY story prose. Do NOT include headings, scene numbers, markdown formatting, bullet lists, or labels like 'Resolution:', 'Conclusion:', 'Ending:', 'Scene 1', etc. Write pure narrative text only.

Write now."

            local bonus_raw
            if bonus_raw=$(generate_chapter "$bonus_prompt" "$SEGMENT_TIMEOUT" "Bonus $bonus_attempts"); then
                local bonus_raw_words=$(count_words "$bonus_raw")
                local actual_cap=$chapter_cap
                if [[ $remaining -lt $chapter_cap ]]; then
                    actual_cap=$remaining
                fi

                local bonus_trimmed=$(trim_to_max "$bonus_raw" "$actual_cap")
                local bonus_words=$(count_words "$bonus_trimmed")

                log "    Bonus $bonus_attempts: $bonus_raw_words words raw → $bonus_words words after trim"

                full_story="$full_story

$bonus_trimmed"
                current_words=$(count_words "$full_story")
                log "    Running total: $current_words words"
            else
                log "    ${YELLOW}Bonus chapter failed, stopping${NC}"
                break
            fi
        done

        # Final trim if over max
        if [[ $current_words -gt $max ]]; then
            log "  ${YELLOW}[Trimming final story to max: $max words]${NC}"
            full_story=$(trim_to_max "$full_story" "$max")
            current_words=$(count_words "$full_story")
        fi

        # Clean any trailing partial sentence
        full_story=$(clean_sentence_ending "$full_story")
        local total_words=$(count_words "$full_story")

        echo "$full_story" > "$filepath"

        log "  ${BLUE}Final: $total_words words (cleaned ending)${NC}"
    fi

    # Final validation (common for both paths)
    if [[ $total_words -ge $min && $total_words -le $max ]]; then
        log "  ${GREEN}✓✓✓ PASS: Story within target range${NC}"
        echo "$id,$filename,$mood,$length,$target,$total_words,$title,$basis,PASS" >> "$MANIFEST_CSV"
        return 0
    else
        log "  ${YELLOW}⚠ WARNING: Final out of range ($total_words not in $min-$max)${NC}"
        echo "$id,$filename,$mood,$length,$target,$total_words,$title,$basis,PASS_OUT_OF_RANGE" >> "$MANIFEST_CSV"
        return 0
    fi
}

TEST_MODE="${TEST_MODE:-single}"

case "$TEST_MODE" in
    single)
        log "${YELLOW}━━ SINGLE TEST: Story #101 only ━━${NC}"
        IFS='|' read -r id title basis mood length target min max <<< "101|David and the Giant|David and Goliath|brave_courage|5min|600|540|660"
        generate_story "$id" "$title" "$basis" "$mood" "$length" "$target" "$min" "$max"
        log ""
        log "${GREEN}Single test complete.${NC}"
        column -t -s',' "$MANIFEST_CSV" >&2
        ;;

    test)
        log "${YELLOW}━━ TEST MODE: 4 stories (1 per length) ━━${NC}"
        TEST_STORIES=(
            "101|David and the Giant|David and Goliath|brave_courage|5min|600|540|660"
            "102|Daniel in the Lions' Den|Daniel 6|brave_courage|10min|1200|1080|1320"
            "110|Esther's Brave Choice|Book of Esther|encouraging|15min|1800|1620|1980"
            "113|Jonah Learns About Mercy|Book of Jonah|calm_peaceful|20min|2400|2160|2640"
        )

        for story_def in "${TEST_STORIES[@]}"; do
            IFS='|' read -r id title basis mood length target min max <<< "$story_def"
            generate_story "$id" "$title" "$basis" "$mood" "$length" "$target" "$min" "$max"
            log ""
        done

        log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log "${GREEN}Test complete. Results:${NC}"
        column -t -s',' "$MANIFEST_CSV" >&2
        ;;

    full)
        log "${GREEN}━━ FULL MODE: All 16 stories ━━${NC}"
        success=0
        warn=0

        for story_def in "${STORIES[@]}"; do
            IFS='|' read -r id title basis mood length target min max <<< "$story_def"
            if generate_story "$id" "$title" "$basis" "$mood" "$length" "$target" "$min" "$max"; then
                if grep -q "PASS_OUT_OF_RANGE" "$MANIFEST_CSV"; then
                    warn=$((warn + 1))
                else
                    success=$((success + 1))
                fi
            fi
            log ""
        done

        log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log "${GREEN}Generation complete. Pass: $success | Warnings: $warn${NC}"
        column -t -s',' "$MANIFEST_CSV" >&2
        ;;

    *)
        echo "Usage: TEST_MODE=[single|test|full] $0" >&2
        exit 1
        ;;
esac
