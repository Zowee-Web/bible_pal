#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_poetic_vivid_plus_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
When evening came, the light loosened its hold on the hills, and the lake darkened beneath the falling sky. Jesus said to his disciples, "Let'"'"'s cross over to the other side," and they set the boat free from the shore. The voices of the crowd thinned behind them as water opened wide ahead, and other boats followed, small and scattered upon the deep.
<break time="520ms"/>

The wind descended without warning, swift and cutting, sweeping across the lake. Waves rose in quick succession, striking the boat and climbing its sides until water spilled across the deck. The wood strained and groaned beneath the blows, and the men braced themselves, shifting and gripping as the vessel pitched, the lake pressing in with relentless force.
<break time="520ms"/>

Jesus was in the stern, asleep on a cushion. While the storm beat against the boat and the night closed around them, he remained unmoved. They crossed the heaving deck toward him, shaken by spray and wind, and woke him, their voices breaking through the roar. "Teacher," they cried, "don'"'"'t you care that we are dying?"
<break time="280ms"/>
<break time="520ms"/>

Jesus stood and faced the wind and the sea. He spoke and said to the sea, "Peace. Be still." The wind fell away, the waves sank low, and the water spread smooth and silent beneath the boat. A great calm took hold of the lake, sudden and complete, as though the storm had never been there.
<break time="520ms"/>

Jesus turned to them and said, "Why are you so afraid? How is it that you have no faith?" They did not answer him. Fear came upon them again as they looked upon the quiet water and then at him. They said to one another, "Who then is this, that even the wind and the sea obey him?"
<break time="650ms"/>

Scripture Reference: Mark 4:35–41 (World English Bible)
</speak>'

JSON="$(python3 - <<PY
import json
ssml = '''$SSML'''
print(json.dumps({
  "text": ssml,
  "voice_settings": {
    "stability": 0.50,
    "similarity_boost": 0.85,
    "style": 0.20,
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
