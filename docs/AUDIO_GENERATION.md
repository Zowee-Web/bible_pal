# Bible PAL - Audio Generation Documentation

**Task Group 5: ElevenLabs Audio Pipeline**

This document explains how to generate real audio narration for Bible PAL parables using the ElevenLabs Text-to-Speech API v3.

---

## Overview

The audio generation pipeline converts parable text files into high-quality MP3 narration using ElevenLabs TTS. The system is designed to:

- Replace placeholder audio files with real narration
- Maintain a calm, contemplative "Bible PAL aesthetic"
- Support batch generation for all test parables
- Be extensible for future nightly batch jobs

---

## Quick Start

### Prerequisites

1. **ElevenLabs API Account**
   - Sign up at [elevenlabs.io](https://elevenlabs.io)
   - Get your API key from the dashboard
   - Choose a voice ID (or use default)

2. **System Requirements**
   - macOS/Linux terminal
   - `curl` (pre-installed on most systems)
   - `jq` (required for JSON parsing): `brew install jq`

### Setup

1. **Create `.env` file** in project root:

```bash
# Bible PAL - ElevenLabs Configuration
ELEVENLABS_API_KEY=your_api_key_here
ELEVENLABS_VOICE_ID=your_voice_id_here
```

2. **Choose a Voice**

Visit the [ElevenLabs Voice Library](https://elevenlabs.io/voice-library) and select a voice suitable for contemplative Bible narration. Recommended characteristics:
- Deep, calm, resonant
- Slow speaking rate
- Clear enunciation
- Warm, comforting tone

Example voices:
- **Adam** - Deep, authoritative, warm
- **Antoni** - Calm, well-balanced, contemplative
- **Arnold** - Crisp, conversational, trustworthy

Copy the Voice ID from the voice settings page and add it to your `.env` file.

### Generate Audio

Run the generation script from the project root:

```bash
./generate_test_audio.sh
```

**Expected Output:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Bible PAL - Audio Generation Pipeline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Checking dependencies...
✓ Dependencies OK

✓ API Key loaded
✓ Voice ID: EXAVITQu4vr4xnSDxMaL

📝 Processing 5 parables...

[1/5] Processing: parable_001_joyful_5min.txt
  📊 Word count: 742 (~4 min estimated)
  🎙️  Generating audio...
  ✓ Generated: parable_001_joyful_5min.mp3 (3.2M)

[2/5] Processing: parable_002_weary_10min.txt
  📊 Word count: 1543 (~10 min estimated)
  🎙️  Generating audio...
  ✓ Generated: parable_002_weary_10min.mp3 (6.8M)

...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Generation Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Success: 5/5

🎉 All audio files generated successfully!
You can now run the Flutter app to test playback.
```

---

## Script Details

### File: `generate_test_audio.sh`

The script performs the following operations:

1. **Dependency Check**
   - Verifies `curl` is installed
   - Checks for `jq` (optional)

2. **Configuration Loading**
   - Reads `.env` file
   - Validates API key and Voice ID

3. **Batch Processing**
   - Iterates through all 5 test parable text files
   - Reads text content
   - Estimates audio length based on word count

4. **API Request**
   - Calls ElevenLabs Text-to-Speech API v3
   - Uses optimized voice settings for contemplative narration:
     - **Stability:** 0.65 (consistent tone)
     - **Similarity Boost:** 0.75 (close to original voice)
     - **Style:** 0.30 (calm, not overly expressive)
     - **Speaker Boost:** Enabled (enhanced clarity)

5. **File Management**
   - Saves MP3 files to `assets/stories/`
   - Replaces placeholder files
   - Reports file sizes and success status

### Voice Settings Explained

```json
{
  "stability": 0.65,
  "similarity_boost": 0.75,
  "style": 0.30,
  "use_speaker_boost": true
}
```

- **Stability (0.65):** Moderate-high consistency. Prevents voice from wandering while maintaining natural variation.
- **Similarity Boost (0.75):** High fidelity to the original voice characteristics.
- **Style (0.30):** Low-moderate expressiveness. Calm and contemplative, not dramatic or overly emotional.
- **Speaker Boost:** Enhanced clarity for spoken word content.

These settings create a warm, meditative narration suitable for Bible parables.

---

## File Structure

### Input Files (Text)

```
assets/stories/
├── parable_001_joyful_5min.txt       (~750 words, 5 min)
├── parable_002_weary_10min.txt       (~1500 words, 10 min)
├── parable_003_anxious_15min.txt     (~2250 words, 15 min)
├── parable_004_hurting_20min.txt     (~3000 words, 20 min)
└── parable_005_neutral_10min.txt     (~1500 words, 10 min)
```

### Output Files (Audio)

```
assets/stories/
├── parable_001_joyful_5min.mp3       (Real ElevenLabs narration)
├── parable_002_weary_10min.mp3       (Real ElevenLabs narration)
├── parable_003_anxious_15min.txt     (Real ElevenLabs narration)
├── parable_004_hurting_20min.mp3     (Real ElevenLabs narration)
└── parable_005_neutral_10min.mp3     (Real ElevenLabs narration)
```

All filenames match the `manifest.json` exactly. No Flutter code changes required.

---

## Testing Audio in App

After generating audio files:

1. **Run Flutter App**

```bash
flutter run
```

2. **Test Playback Flow**
   - Tap "PAL's Parables" on main menu
   - Enter mood (e.g., "feeling grateful")
   - Select 5-minute length
   - Parable should load and play with real narration

3. **Verify Audio Quality**
   - Check narration speed (should be slow and contemplative)
   - Verify audio clarity
   - Confirm playback controls work (play/pause/stop)

4. **Test All Parables**
   - Try different moods to hear all 5 parables
   - Verify each audio file plays correctly
   - Check that scripture sources display properly

---

## Troubleshooting

### Error: "curl: command not found"

**Solution:** Install curl (pre-installed on macOS/most Linux):

```bash
brew install curl  # macOS
```

### Error: "jq is not installed"

**Solution:** Install jq (required for JSON parsing):

```bash
brew install jq  # macOS
```

### Error: "ELEVENLABS_API_KEY not found"

**Solution:** Create or update `.env` file:

```bash
echo "ELEVENLABS_API_KEY=your_key_here" >> .env
echo "ELEVENLABS_VOICE_ID=your_voice_here" >> .env
```

### Error: "HTTP 401 Unauthorized"

**Solution:** API key is invalid or expired. Verify your key at [elevenlabs.io/app/settings](https://elevenlabs.io/app/settings).

### Error: "HTTP 429 Too Many Requests"

**Solution:** You've hit the API rate limit. Wait a few minutes or upgrade your ElevenLabs plan.

### Error: "HTTP 400 Bad Request"

**Solution:** Check Voice ID is correct. List available voices:

```bash
curl https://api.elevenlabs.io/v1/voices \
  -H "xi-api-key: $ELEVENLABS_API_KEY" | jq
```

### Audio Quality Issues

**Problem:** Narration too fast or robotic

**Solution:** Adjust voice settings in `generate_test_audio.sh`:

```bash
# Slower, more contemplative
STABILITY="0.75"
SIMILARITY_BOOST="0.80"
STYLE="0.20"

# Faster, more conversational
STABILITY="0.50"
SIMILARITY_BOOST="0.70"
STYLE="0.50"
```

---

## Manual Generation (Single File)

To regenerate a single parable audio file:

```bash
# Set variables
TEXT_FILE="assets/stories/parable_001_joyful_5min.txt"
AUDIO_FILE="assets/stories/parable_001_joyful_5min.mp3"
VOICE_ID="your_voice_id_here"
API_KEY="your_api_key_here"

# Read text content
TEXT_CONTENT=$(<"$TEXT_FILE")

# Generate audio
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
  -H "xi-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"text\": \"$TEXT_CONTENT\",
    \"model_id\": \"eleven_multilingual_v2\",
    \"voice_settings\": {
      \"stability\": 0.65,
      \"similarity_boost\": 0.75,
      \"style\": 0.30,
      \"use_speaker_boost\": true
    }
  }" \
  --output "$AUDIO_FILE"

echo "Generated: $AUDIO_FILE"
```

---

## Cost Estimation

ElevenLabs pricing (as of December 2024):

- **Free Tier:** 10,000 characters/month
- **Starter Plan:** $5/month - 30,000 characters
- **Creator Plan:** $22/month - 100,000 characters

### Test Parable Library Cost

Estimated character count:
- 5 parables × ~3,500 characters each = **~17,500 characters**

**Cost:** Free tier or $5/month Starter plan is sufficient for initial testing.

### Future Nightly Batch Generation

For production use with larger parable libraries:
- 100 parables × ~3,500 characters = 350,000 characters
- Recommended: Creator Plan ($22/month) or higher

---

## Integration with Future Nightly Batch Jobs

The `generate_test_audio.sh` script is designed to be extended for nightly batch generation. Future enhancements:

### 1. Batch Processing All Parables

Modify script to read all `.txt` files from `assets/stories/`:

```bash
# Find all text files dynamically
TEXT_FILES=($(find "$STORIES_DIR" -name "*.txt" -type f))
```

### 2. Differential Updates

Only regenerate files that have changed:

```bash
# Check if text file is newer than audio file
if [ "$TEXT_PATH" -nt "$AUDIO_PATH" ]; then
    echo "Text file updated, regenerating audio..."
fi
```

### 3. Cron Job Setup

Schedule nightly generation:

```bash
# Edit crontab
crontab -e

# Add line (runs at 2 AM daily)
0 2 * * * cd /path/to/bible_pal && ./generate_test_audio.sh >> logs/audio_generation.log 2>&1
```

### 4. Error Notifications

Send email on failure:

```bash
# Add to script
if [ $FAILED -gt 0 ]; then
    echo "Audio generation failed" | mail -s "Bible PAL Audio Alert" admin@example.com
fi
```

### 5. Cloud Storage Integration

Upload generated files to S3/Cloud Storage:

```bash
# After successful generation
aws s3 sync assets/stories/ s3://bible-pal-audio/ \
  --exclude "*.txt" \
  --include "*.mp3"
```

---

## API Reference

### ElevenLabs Text-to-Speech v1 API

**Endpoint:**
```
POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}
```

**Headers:**
```
xi-api-key: <your_api_key>
Content-Type: application/json
```

**Request Body:**
```json
{
  "text": "Your parable text here...",
  "model_id": "eleven_multilingual_v2",
  "voice_settings": {
    "stability": 0.65,
    "similarity_boost": 0.75,
    "style": 0.30,
    "use_speaker_boost": true
  }
}
```

**Response:**
- **Success (200):** Binary MP3 audio data
- **Error (4xx/5xx):** JSON error message

**Documentation:** [ElevenLabs API Docs](https://docs.elevenlabs.io/api-reference/text-to-speech)

---

## Voice Customization

### Finding the Right Voice

1. Visit [ElevenLabs Voice Library](https://elevenlabs.io/voice-library)
2. Filter by:
   - **Use Case:** Narration / Audiobook
   - **Gender:** Male / Female
   - **Accent:** American / British / Neutral
3. Preview voices with sample Bible text
4. Copy Voice ID from voice settings

### Creating a Custom Voice

For a truly unique Bible PAL voice:

1. Use ElevenLabs **Voice Design** feature
2. Adjust sliders:
   - **Age:** Mature (40-60)
   - **Accent:** Neutral or slight regional
   - **Tone:** Warm, comforting
3. Generate and test
4. Save Voice ID to `.env`

### Voice Cloning (Professional Voice)

For premium quality:

1. Record 1-5 minutes of clean voice samples
2. Upload to ElevenLabs Voice Cloning
3. Train custom voice model
4. Use cloned Voice ID in script

---

## Best Practices

### 1. Text Preparation

Before generating audio:
- Remove markdown formatting (**, ##, etc.)
- Ensure proper punctuation for natural pauses
- Use "..." for contemplative pauses
- Avoid excessive line breaks

### 2. Voice Consistency

- Use the same Voice ID for all parables
- Keep voice settings consistent
- Regenerate all audio if changing voices

### 3. Quality Control

After generation:
- Listen to entire audio file
- Check for mispronunciations (especially Bible names)
- Verify pacing matches parable mood
- Confirm file size is reasonable (~1MB per minute)

### 4. Version Control

- **Do NOT commit `.env`** (contains API secrets)
- **Do NOT commit MP3 files** to git (use Git LFS or external storage)
- **Do commit** text files and `manifest.json`

Add to `.gitignore`:
```
.env
*.mp3
```

### 5. Backup Strategy

- Keep original placeholder MP3s in `backups/`
- Save generated audio to cloud storage
- Version text files for regeneration capability

---

## Maintenance

### Regenerating All Audio

To regenerate all audio files (e.g., after changing voices):

```bash
# Remove existing audio files
rm assets/stories/*.mp3

# Regenerate with new settings
./generate_test_audio.sh
```

### Updating Voice Settings

Edit `generate_test_audio.sh` and modify:

```bash
# Voice settings for calm, contemplative narration
STABILITY="0.65"       # Adjust 0.0 - 1.0
SIMILARITY_BOOST="0.75"  # Adjust 0.0 - 1.0
STYLE="0.30"          # Adjust 0.0 - 1.0
```

### Adding New Parables

1. Create new `.txt` file in `assets/stories/`
2. Add entry to `manifest.json`
3. Add filename to `TEXT_FILES` array in script
4. Run `./generate_test_audio.sh`

---

## FAQ

**Q: How long does generation take?**
A: ~5-15 seconds per parable. Total: ~1-2 minutes for all 5 test parables.

**Q: Can I use other TTS providers?**
A: Yes, modify the script to call other APIs (Google Cloud TTS, AWS Polly, Azure Speech).

**Q: What if I run out of characters?**
A: Upgrade your ElevenLabs plan or regenerate only changed files.

**Q: Can I use SSML for better control?**
A: Yes, ElevenLabs supports SSML. Wrap text in `<speak>` tags and use `<break>`, `<emphasis>`, etc.

**Q: How do I change narration speed?**
A: ElevenLabs doesn't have a native speed parameter. Use SSML `<prosody rate="slow">` or post-process with `ffmpeg`.

**Q: Should I commit audio files to Git?**
A: No, use Git LFS or external storage (S3, Google Cloud Storage). Audio files are large and change frequently.

---

## Summary

**Task Group 5 Deliverables:**

✅ **Script Created:** `generate_test_audio.sh`
- Reads 5 text files from `assets/stories/`
- Calls ElevenLabs API v3 for each file
- Saves MP3 files with exact manifest filenames
- Provides detailed progress output

✅ **Documentation Created:** `docs/AUDIO_GENERATION.md`
- Step-by-step setup instructions
- Voice selection guide
- Troubleshooting section
- Integration with future nightly batch jobs

✅ **No Flutter Code Modified**
- All changes are terminal automation
- Existing Flutter app works unchanged
- Audio files drop-in replacement for placeholders

**Next Steps:**
1. Run `./generate_test_audio.sh` to generate real audio
2. Test playback in Flutter app
3. Verify audio quality and pacing
4. Adjust voice settings if needed

**Bible PAL is now ready for real audio testing!** 🎉
