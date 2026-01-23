# LEGACY Scripts

This directory contains **legacy minute-based generation scripts** that have been deprecated in favor of the new storyLength bucket system (Short/Full/Long).

**DO NOT USE** these scripts for new content generation. They are retained for reference only.

## Why These Were Deprecated

The app migrated from a minute-based story length system (5/10/15/20 min) to a simpler bucket system:
- **Short Story**: 250-600 words
- **Full Story**: 601-1200 words
- **Long Story**: 1201-2000 words

See `docs/DECISIONS.md` (ADR-009) for the migration rationale.

## Active Generation Scripts

Use these scripts instead (in `server/`):
- `generate_adult_traditional_stories.sh` - For adult traditional stories
- `tools/gen_one_story_api.sh` - Single story generation via API
- `tools/gen_one_audio.sh` - Audio generation for existing stories

## Files in This Directory

| File | Original Purpose |
|------|------------------|
| `generate_kids_trad_pack.sh` | Kid traditional story batch generation |
| `generate_kid_stories.sh` | Single kid story generation |
| `generate_kidfriendly_batch.sh` | Kid-friendly batch generation |
| `generate_single_kidfriendly.sh` | Single kid-friendly generation |
| `generate_kid_audio.sh` | Kid audio batch generation |
| `generate_voice_test_batch.sh` | Voice testing batch |
| `generate_cinematic_story.sh` | Cinematic story generation |
| `generate_batch_parables_old.sh.disabled` | Old batch generation |
