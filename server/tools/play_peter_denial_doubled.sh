#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_peter_denial_doubled_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
They seized Jesus and led him away, and the crowd moved with them through the narrow streets, torchlight breaking against stone and shadow as the night closed in. Peter followed at a distance, keeping space between himself and those who walked ahead, watching the movement of bodies and listening to the sound of voices carried forward by the cold air. Each step took him farther from the moment of arrest and closer to a place he did not know how to leave.
<break time="650ms"/>

When they came to the high priest'"'"'s house, the gate stood open and people passed through in small groups, their footsteps slowing as they entered the courtyard beyond. A fire burned at its center, its light uneven and low, and servants and guards gathered around it, warming their hands and speaking quietly among themselves. Peter entered after them and stood near the edge, letting others settle first before he moved closer.
<break time="650ms"/>

He found a place among those seated near the fire, close enough to feel its warmth yet far enough to remain unnoticed. The flames rose and fell, casting light across faces and then withdrawing it again, and Peter'"'"'s face appeared and disappeared in the shifting glow. Around him, voices rose and fell, fragments of conversation breaking off and fading into the night.
<break time="650ms"/>

As he sat there, a servant girl noticed him, her attention caught by his face as the firelight lingered on it. She looked closely, her gaze steady, and then spoke clearly so that others could hear. "This man also was with him," she said, and several heads turned in his direction.
<break time="350ms"/>

Peter denied it at once, saying, "Woman, I don'"'"'t know him," and his words came quickly, as though speed alone could erase them. The fire crackled, someone laughed nearby, and the moment seemed to pass as others returned to their talk. Peter shifted where he sat, angling his body slightly away from the center of the fire.
<break time="650ms"/>

After a little while, as the night deepened and the crowd thinned, another saw him and spoke again. "You also are one of them," he said, and the accusation settled heavier in the quiet that followed. Peter answered, "Man, I am not," and his voice was firm enough to end the exchange.
<break time="350ms"/>

Time passed, marked only by the fire sinking lower and the sound of movement in the house beyond the courtyard. Peter remained where he was, neither leaving nor stepping closer, listening as voices rose and fell around him. About an hour later, another confidently affirmed, "Truly this man also was with him, for he is a Galilean," and the words carried across the space without hesitation.
<break time="350ms"/>

Peter replied, "Man, I don'"'"'t know what you are talking about," and immediately, while he was still speaking, a rooster crowed.
<break time="900ms"/>

The Lord turned and looked at Peter. In that moment, Peter remembered the word of the Lord, how he had said to him, "Before the rooster crows, you will deny me three times." Peter rose, left the fire behind, passed back through the gate, and went out into the night, where he wept bitterly.
<break time="1200ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.52,
    "similarity_boost": 0.88,
    "style": 0.26,
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
