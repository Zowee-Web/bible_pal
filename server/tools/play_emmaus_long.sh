#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_emmaus_long_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
On the same day, two of them were going to a village named Emmaus, which was about seven miles from Jerusalem, and they spoke with one another about all the things that had happened. The road stretched out before them, winding through open country, and the dust rose softly beneath their feet as they walked, the city falling farther behind with every step. Their voices carried low and steady, shaped by grief and confusion rather than haste, as they returned again and again to the same memories.
<break time="700ms"/>

As they walked and talked together, Jesus himself came near and went with them, but their eyes were kept from recognizing him. He joined their pace without drawing attention, matching the rhythm of their steps as though he had been walking with them all along. The road held the three of them in a shared silence before he spoke.
<break time="700ms"/>

Jesus said to them, "What are you talking about with one another as you walk?" They stopped, their forward motion breaking, and stood still with faces marked by sorrow. One of them, named Cleopas, answered him, "Are you the only stranger in Jerusalem who doesn'"'"'t know the things which have happened there in these days?"
<break time="400ms"/>

He said to them, "What things?" They replied, "The things concerning Jesus of Nazareth, who was a prophet mighty in deed and word before God and all the people, and how the chief priests and our rulers delivered him up to be condemned to death and crucified him." The words came carefully, as though naming the events again might finally give them shape.
<break time="700ms"/>

"But we were hoping that it was he who would redeem Israel," they continued, "yes, and besides all this, it is now the third day since these things happened." Their steps resumed, slower now, the weight of expectation lingering in the space between them. "Also, certain women of our company amazed us," they said, "having been early at the tomb, and when they didn'"'"'t find his body, they came saying that they had also seen a vision of angels, who said that he was alive."
<break time="700ms"/>

"Some of those who were with us went to the tomb and found it just as the women had said," they added, "but him they didn'"'"'t see." The road narrowed slightly, bordered by fields still marked by morning, and the sound of their walking filled the pauses between their words.
<break time="700ms"/>

Jesus said to them, "Foolish men, and slow of heart to believe in all that the prophets have spoken. Didn'"'"'t the Christ have to suffer these things and to enter into his glory?" And beginning from Moses and from all the prophets, he explained to them in all the Scriptures the things concerning himself. His voice moved steadily, unhurried, unfolding the words that had been spoken long before.
<break time="400ms"/>

As they drew near to the village where they were going, he acted as though he would go further. The road bent toward the houses ahead, and the light had begun to soften, stretching the afternoon toward evening. They urged him, saying, "Stay with us, for it is almost evening, and the day is almost over."
<break time="700ms"/>

He went in to stay with them. When he had sat down at the table with them, he took the bread, blessed it, and broke it, and gave it to them. Their eyes were opened, and they recognized him, and he vanished out of their sight.
<break time="900ms"/>

They said to one another, "Weren'"'"'t our hearts burning within us while he spoke to us along the road, and while he opened the Scriptures to us?" The room held the stillness of what had just been revealed, the broken bread resting before them as the moment passed.
<break time="700ms"/>

They rose up that same hour and returned to Jerusalem, though the road lay dark ahead of them now. The distance that had weighed on them earlier no longer slowed their steps, and the night received them as they went.
<break time="700ms"/>

When they arrived, they found the eleven gathered together, and those who were with them, saying, "The Lord is risen indeed, and has appeared to Simon!" They told the things that happened on the way, and how he was recognized by them in the breaking of the bread.
<break time="1200ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.55,
    "similarity_boost": 0.85,
    "style": 0.22,
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
