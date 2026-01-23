#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_peter_denial_reflection_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
Some moments do not need explanation to be heavy. Peter'"'"'s denial unfolds slowly, under ordinary pressure, where no crowd demands loyalty and no one forces betrayal—only fear and fatigue remain.
<break time="300ms"/>
<break time="700ms"/>

This story reminds us that failure does not always come in dramatic collapse. Sometimes it comes quietly, in the space between who we believe ourselves to be and what we choose when the fire is close.
<break time="300ms"/>
<break time="700ms"/>

If today has held moments you wish had gone differently, this story does not turn away from you. It allows the weight to remain, trusting that what follows does not need to be spoken yet.
<break time="1200ms"/>
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
