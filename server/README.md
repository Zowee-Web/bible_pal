# Bible PAL Server Scripts

This directory contains scripts for generating story content and audio.

## One-Off Story Pipeline

For generating individual test stories outside the batch generation process.

### Prerequisites

- Ollama running locally (`ollama serve`)
- `.env` file with `ELEVENLABS_API_KEY` and voice IDs
- `jq` installed for JSON handling

### Generate a Single Story (Text Only)

```bash
# Usage: ./server/tools/gen_one_story_api.sh <mood> <story_id>
./server/tools/gen_one_story_api.sh encouraging 402

# Output: assets/stories/parable_402_encouraging_short.txt
```

**Story Length:** Generates SHORT bucket stories (250-600 words per LOCKED SPEC)

**Moods:** encouraging, joyful, weary, anxious, hurting, neutral

**Why HTTP API?** The script uses Ollama's HTTP API (`stream:false`) instead of `ollama run` CLI because:
- CLI via command substitution (`$(ollama run ...)`) can hang indefinitely
- Stray processes accumulate if timeouts occur
- HTTP API returns complete output reliably

### Generate Audio from Text

```bash
# Usage: AUDIO_ENABLED=1 ./server/tools/gen_one_audio.sh <text_file> [voice_var]
AUDIO_ENABLED=1 ./server/tools/gen_one_audio.sh \
    assets/stories/parable_402_encouraging_5min.txt \
    VOICE_GRACE

# Output: assets/stories/parable_402_encouraging_5min.mp3
```

**Safety:** `AUDIO_ENABLED=1` is required to actually call ElevenLabs (prevents accidental credit usage).

**Voices:** See `.env` for available voice variables (e.g., `VOICE_GRACE`, `VOICE_ARCHER`).

### Full Pipeline Example

```bash
# 1. Generate story text
./server/tools/gen_one_story_api.sh encouraging 403

# 2. Review the generated text
cat assets/stories/parable_403_encouraging_5min.txt

# 3. Generate audio (costs ElevenLabs credits)
AUDIO_ENABLED=1 ./server/tools/gen_one_audio.sh \
    assets/stories/parable_403_encouraging_5min.txt \
    VOICE_GRACE
```

### Troubleshooting

**Ollama hangs or leaves stray processes:**
```bash
# Kill stray ollama run processes
pkill -f "ollama run gemma"

# Verify Ollama is responsive
curl -s http://localhost:11434/api/tags | jq '.models[].name'
```

**ElevenLabs returns HTTP 000:**
- Usually a timeout or network issue
- Check API key is valid: `curl -s -H "xi-api-key: $KEY" https://api.elevenlabs.io/v1/voices | head`
- The scripts use `--connect-timeout 10 --max-time 120` for robust handling

## Batch Generation

For scheduled content generation, see [GENERATION_SCHEDULE.md](GENERATION_SCHEDULE.md).

```bash
# Generate a batch of parables
AUDIO_ENABLED=1 ./server/generate_batch_parables.sh <batch_num> <mood_index>
```

## Directory Structure

```
server/
├── tools/                    # One-off utility scripts
│   ├── gen_one_story_api.sh  # Generate single story via Ollama API
│   └── gen_one_audio.sh      # Generate audio for a text file
├── prompts/                  # Prompt templates
│   └── golden_trad_adult_short.prompt.txt
├── elevenlabs_guard.sh       # Shared safety gate for ElevenLabs calls
├── generate_batch_parables.sh
└── ... (other generation scripts)
```

## Safety Guards

All ElevenLabs calls go through `elevenlabs_guard.sh` which:
- Requires `AUDIO_ENABLED=1` to proceed
- Enforces character limits per story length tier
- Acquires a lock to prevent concurrent calls
- Logs all attempts to `elevenlabs_calls.log`
