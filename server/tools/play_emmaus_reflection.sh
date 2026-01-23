#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_emmaus_reflection_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
Some journeys do not begin with hope, but they are not without purpose. The road to Emmaus was walked in confusion and sorrow, yet understanding came not through answers, but through presence.
<break time="350ms"/>
<break time="800ms"/>

If your day has carried questions that do not yet have names, this story does not hurry them away. It reminds us that clarity often comes while we are still walking, and recognition may arrive quietly, long after we have begun the journey.
<break time="1400ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.60,
    "similarity_boost": 0.82,
    "style": 0.15,
    "use_speaker_boost": True
  }
}, ensure_ascii=False))
PY
)"

curl -sS -X POST \
  "https://api.elevenlabs.io/v1/text-to-speech/${ELEVENLABS_VOICE_ID}?output_format=mp3_44100_128" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
  -d "$JSON" \
  --output "$OUT"

echo "Saved: $OUT"
