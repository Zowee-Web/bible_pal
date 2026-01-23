# Bible PAL - Parable Generation Schedule

## Story Length Buckets (LOCKED SPEC)

| Bucket | Word Range | Approx Characters |
|--------|------------|-------------------|
| short  | 250-600    | ~2,500-6,000      |
| full   | 601-1200   | ~6,000-12,000     |
| long   | 1201-2000  | ~12,000-20,000    |

**Default:** All generation defaults to `short` bucket.

## Month 1 Plan (Creator Plan $22/month)

**Budget:** 393,923 characters available (293,923 banked + 100,000 monthly)

**Schedule:** Every 4 days (7-8 batches over 30 days)

**Per Batch (Bucket-Based):**
- 3 × short stories (~4,500 chars each)
- 1 × full story (~9,000 chars)
- 1 × long story (~16,000 chars)
- **Total per batch: ~38,500 characters**

**Expected Output:**
- 7-8 batches × 5 stories = **35-40 total stories**
- Mix of short, full, and long across all moods
- Covers all 6 moods with variety

**Total Usage:** ~270,000-310,000 characters (fits within budget ✅)

## Generation Commands

### One-Off Story Generation (Recommended)

```bash
# Generate single SHORT story via Ollama API
./server/tools/gen_one_story_api.sh <mood> <story_id>

# Example: Generate encouraging story #402
./server/tools/gen_one_story_api.sh encouraging 402
# Output: assets/stories/parable_402_encouraging_short.txt

# Generate audio (costs ElevenLabs credits)
AUDIO_ENABLED=1 ./server/tools/gen_one_audio.sh \
    assets/stories/parable_402_encouraging_short.txt \
    VOICE_GRACE
```

### Batch Generation

```bash
# Generate batch of parables (batch_num, mood_index)
AUDIO_ENABLED=1 ./server/generate_batch_parables.sh 1 0
```

**Mood Index:**
- 0 = joyful
- 1 = weary
- 2 = anxious
- 3 = hurting
- 4 = neutral
- 5 = encouraging

**Faith Tradition Alternation:**
- Odd batch numbers (1, 3, 5, 7) = Protestant
- Even batch numbers (2, 4, 6, 8) = Catholic

## Adult Traditional Stories

```bash
# Generate adult traditional stories (SHORT bucket)
./server/generate_adult_traditional_stories.sh

# With golden prompt mode
./server/generate_adult_traditional_stories.sh --golden-prompt
```

## Month 2+ Plan (Pro Plan $99/month)

After upgrading to Pro plan:
- 500,000 characters/month
- Can increase generation frequency
- Consider adding more full/long bucket stories

## Notes

- Each generation includes automatic manifest.json updates
- Text files are saved alongside audio for reference
- Script handles rate limiting between API calls
- Generated files go to `assets/stories/` directory
- All stories include `storyLength` field in manifest

## Legacy Documentation

For historical reference on the deprecated minute-based system, see:
- `server/legacy/README.md`
- `server/prompts/legacy/README.md`
