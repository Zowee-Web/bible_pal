#!/usr/bin/env bash
# Minimal Ruth (VOICE_RUTH_COMFORT) test-batch generator.
#
# Generates ~16 audio files covering ONE complete PAL flow so the user can
# trial Ruth's voice end-to-end before committing to a full 468-file
# regeneration. Lines used:
#
#   - 3 openings           (OPENING_GENTLE_01..03)
#   - 4 prompts (1 per TOD) (MORNING_DAY_01, AFTERNOON_DAY_01, EVENING_DAY_01, LATE_NIGHT_DAY_01)
#   - 4 reflections (weary) (REFL_WEARY_01..04)
#   - 3 transitions         (TRANS_01..03)
#   - 2 framings (David)    (FRAME_DAVID_ANOINTED_01..02)
#
# Output: assets/pal/audio/VOICE_RUTH_COMFORT/<LINE_ID>.mp3
# Skips files that already exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/pal/audio/VOICE_RUTH_COMFORT"
RUTH_VOICE_ID="jBpfuIE2acCO8z3wKNLl"
MODEL_ID="eleven_v3"

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env not found at $ENV_FILE" >&2
  exit 1
fi
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
  value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
  export "$key=$value"
done < "$ENV_FILE"

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  echo "Error: ELEVENLABS_API_KEY not set" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# id|text pairs (pipe-delimited; texts must not contain literal pipes)
LINES=(
  # Openings
  "OPENING_GENTLE_01|I'm here. What's today been like for you?"
  "OPENING_GENTLE_02|You don't have to filter anything… how's your day been?"
  "OPENING_GENTLE_03|What's been sitting with you today?"
  # Prompts (one per time window)
  "MORNING_DAY_01|How's your morning starting out?"
  "AFTERNOON_DAY_01|How's the middle of your day going?"
  "EVENING_DAY_01|How's your evening settling in?"
  "LATE_NIGHT_DAY_01|How are you sitting with this part of the night?"
  # Reflections (weary)
  "REFL_WEARY_01|That sounds like it's been sitting on you for a while."
  "REFL_WEARY_02|I can hear how tired that feels… not just physically."
  "REFL_WEARY_03|Some kinds of tired go deeper than sleep fixes."
  "REFL_WEARY_04|That's the kind of weight people don't always see."
  # Transitions (bridge into the story)
  "TRANS_01|There's a story that meets you right there."
  "TRANS_02|Let's walk into a moment that feels close to this."
  "TRANS_03|I think there's a story you'll connect with."
  # Framings (David Anointed)
  "FRAME_DAVID_ANOINTED_01|David was the one nobody thought to call — until God did."
  "FRAME_DAVID_ANOINTED_02|Everyone overlooked David. But being overlooked isn't the same as being forgotten."
)

generate_one() {
  local id="$1"
  local text="$2"
  local out="$OUTPUT_DIR/$id.mp3"
  if [[ -f "$out" ]]; then
    echo "  [skip] $id (exists)"
    return 0
  fi
  local payload
  payload=$(jq -n --arg t "$text" --arg m "$MODEL_ID" '{
    text: $t,
    model_id: $m,
    voice_settings: {stability: 0.55, similarity_boost: 0.75, style: 0.10, use_speaker_boost: true}
  }')
  local http
  http=$(curl -sS -o "$out" -w "%{http_code}" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "https://api.elevenlabs.io/v1/text-to-speech/$RUTH_VOICE_ID" \
    --data-binary "$payload")
  if [[ "$http" != "200" ]]; then
    echo "  [FAIL $http] $id"
    rm -f "$out"
    return 1
  fi
  local size=$(wc -c <"$out" | tr -d ' ')
  echo "  [ok ${size}b] $id"
}

echo "Generating Ruth test batch -> $OUTPUT_DIR"
echo "Lines: ${#LINES[@]}"
echo

ok=0
fail=0
for entry in "${LINES[@]}"; do
  id="${entry%%|*}"
  text="${entry#*|}"
  if generate_one "$id" "$text"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done

echo
echo "Done. ok=$ok fail=$fail"
ls "$OUTPUT_DIR" | wc -l | awk '{print "  files in dir: "$1}'
