#!/usr/bin/env bash
set -euo pipefail

: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
: "${ELEVENLABS_VOICE_ID:?Set ELEVENLABS_VOICE_ID}"

OUT="bp_lazarus_long_female_$(date +%Y%m%d_%H%M%S).mp3"

SSML='<speak>
The road into Bethany lay quiet beneath the weight of waiting, and the village stood still as though holding its breath. News had already passed through the narrow paths and low doorways, carried from mouth to mouth with growing urgency: Lazarus was sick. The sickness had lingered, deepening day by day, until hope itself began to thin.
<break time="1000ms"/>

Mary and Martha sent word to Jesus, their message brief and unadorned, carried by urgency rather than explanation. "Lord, behold, he whom you love is sick." The words bore the weight of friendship and trust, resting on the certainty that Jesus would come, because he always had before.
<break time="1000ms"/>

When Jesus heard it, he did not rise at once. He remained where he was, surrounded by his disciples, the air still and the moment unhurried. He said, "This sickness is not to death, but for the glory of God, that God'"'"'s Son may be glorified by it."
<break time="600ms"/>

Though he loved Martha, and her sister, and Lazarus, he stayed where he was two days longer. Then he said to the disciples, "Let'"'"'s go into Judea again." They answered him carefully, remembering the stones once lifted against him.
<break time="1000ms"/>

When Jesus arrived, he found that Lazarus had already been in the tomb four days. Many had come to sit with Mary and Martha, their voices low, the house heavy with mourning. Martha went out to meet him, while Mary remained seated inside.
<break time="1000ms"/>

Martha said, "Lord, if you had been here, my brother would not have died. Even now I know that whatever you ask of God, God will give you." Jesus said, "Your brother will rise again."
<break time="600ms"/>

Jesus said to her, "I am the resurrection and the life." She answered, "Yes, Lord. I have believed that you are the Christ." Then she went and called Mary.
<break time="1000ms"/>

Mary came to Jesus and fell at his feet, weeping. Jesus saw her weeping, and those who came with her also weeping, and he was deeply moved. He said, "Where have you laid him?"
<break time="600ms"/>

They brought him to the tomb, a cave with a stone laid against it. Jesus wept. Some said, "See how much affection he had for him."
<break time="1000ms"/>

Jesus said, "Take away the stone." Martha said, "Lord, by this time there is a stench." Jesus said, "Didn'"'"'t I tell you that if you believed, you would see God'"'"'s glory?"
<break time="1000ms"/>

Jesus lifted his eyes and said, "Father, I thank you that you listened to me." Then he cried with a loud voice, "Lazarus, come out."
<break time="1400ms"/>

He who was dead came out. Jesus said, "Free him, and let him go." Many believed, and others went away speaking of what had happened.
<break time="2000ms"/>
</speak>'

JSON="$(python3 - <<PY
import json
print(json.dumps({
  "text": '''$SSML''',
  "voice_settings": {
    "stability": 0.55,
    "similarity_boost": 0.85,
    "style": 0.18,
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
