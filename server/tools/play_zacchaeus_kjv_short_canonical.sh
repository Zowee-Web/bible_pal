#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_zacchaeus_kjv_short_canonical_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
And Jesus entered and passed through Jericho, and the city stirred beneath his passing. The narrow streets tightened with bodies and voices, footsteps echoing against stone, as the multitude pressed near, each person leaning forward to catch sight of him who moved steadily through their midst.
<break time="900ms"/>

And behold, there was a man named Zacchaeus, which was the chief among the publicans, and he was rich. He sought to see Jesus who he was, but could not for the press, because he was little of stature. So he ran before the crowd, his robe gathered in haste, and climbed up into a sycamore tree that stood beside the road, its branches lifting him above the heads of men, for he was to pass that way.
<break time="900ms"/>

And when Jesus came to the place, he stood still, and looked up, and saw him.
<break time="180ms"/>
And he said unto him, "Zacchaeus, make haste, and come down; for to day I must abide at thy house."
<break time="500ms"/>
And Zacchaeus made haste, and came down, and received him joyfully, his gladness plain and unhidden.
<break time="900ms"/>

But when they saw it, they all murmured, saying, that he was gone to be guest with a man that is a sinner. The sound passed quietly through the crowd, carried from one to another.
<break time="180ms"/>
Yet Zacchaeus stood, and said unto the Lord, "Behold, Lord, the half of my goods I give to the poor; and if I have taken any thing from any man by false accusation, I restore him fourfold." His words were simple and direct, spoken without flourish, yet they settled with weight.
<break time="900ms"/>

And Jesus said unto him, "This day is salvation come to this house, forsomuch as he also is a son of Abraham. For the Son of man is come to seek and to save that which was lost." And the house, once known for its gain, bore witness to a turning that had come quietly, marked not by noise, but by a man who came down when he was called.
<break time="1600ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.55,
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
