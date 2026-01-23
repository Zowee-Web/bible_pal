#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_lyric_vivid_test_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
On the third day there was a wedding in Cana of Galilee, and the place was alive with motion and sound, with voices rising and folding into one another as water was drawn, bread was passed, and vessels stood waiting along the walls, their stone bodies cool beneath hurried hands. Jesus was there with his disciples, and his mother also, moving among the gathered people as the feast unfolded in layers—music drifting above the low work of servants, laughter spilling across tables, and the steady rhythm of celebration carrying the hour forward.
<break time="600ms"/>

When the wine ran out, the absence moved quietly through the servants before it reached her, and she came to Jesus and said, "They have no wine." Jesus answered her, "Woman, what does that have to do with you and me? My hour has not yet come," and the words settled between them even as the feast continued, cups still lifted, unaware of what had already been lost.
<break time="320ms"/>
<break time="600ms"/>

His mother turned to the servants and said, "Whatever he says to you, do it," and nearby stood six stone water jars set there for the Jews'"'"' purification, large and empty, shaped for ritual and now waiting in stillness. Jesus said to them, "Fill the water jars with water," and they obeyed, drawing again and again until the jars were filled to the brim, the surface of the water trembling under the weight of what it held.
<break time="320ms"/>
<break time="600ms"/>

Then he said, "Now draw some out, and take it to the ruler of the feast," and the servants lifted the ladle and carried the cup forward through the gathered crowd, past voices and movement, toward the one who watched over the celebration. When the ruler tasted the water that had become wine—though he did not know where it came from, while the servants who drew the water knew—he called the bridegroom and said, "Every man serves the good wine first, and when the guests have drunk freely, then the inferior; but you have kept the good wine until now."
<break time="600ms"/>

This beginning of signs Jesus did in Cana of Galilee, and he revealed his glory, and his disciples believed in him, while the wedding continued and the joy of the feast carried on without pause. The jars stood emptied of their gift, the music did not stop, and yet something had passed quietly through the room, leaving behind more than wine—an unseen turning that those who had seen it would not forget.
<break time="750ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.48,
    "similarity_boost": 0.88,
    "style": 0.30,
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
