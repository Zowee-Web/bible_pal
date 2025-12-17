# Bible PAL - Parable Generation Schedule

## Month 1 Plan (Creator Plan $22/month)

**Budget:** 393,923 characters available (293,923 banked + 100,000 monthly)

**Schedule:** Every 4 days (7-8 batches over 30 days)

**Per Batch:**
- 3 × 5-minute parables (~4,500 chars each)
- 1 × 10-minute parable (~9,000 chars)
- 1 × 15-minute parable (~13,500 chars)
- 1 × 20-minute parable (~18,000 chars)
- **Total per batch: ~54,000 characters**

**Expected Output:**
- 7-8 batches × 6 parables = **42 total parables**
- 21 × 5min, 7 × 10min, 7 × 15min, 7 × 20min
- Covers all 5 moods with variety

**Total Usage:** ~378,000 characters (fits within budget ✅)

## Generation Commands

### Batch 1 (Day 1) - Joyful mood
```bash
./server/generate_batch_parables.sh 1 0
```

### Batch 2 (Day 5) - Weary mood
```bash
./server/generate_batch_parables.sh 2 1
```

### Batch 3 (Day 9) - Anxious mood
```bash
./server/generate_batch_parables.sh 3 2
```

### Batch 4 (Day 13) - Hurting mood
```bash
./server/generate_batch_parables.sh 4 3
```

### Batch 5 (Day 17) - Neutral mood
```bash
./server/generate_batch_parables.sh 5 4
```

### Batch 6 (Day 21) - Joyful mood (cycle repeats)
```bash
./server/generate_batch_parables.sh 6 0
```

### Batch 7 (Day 25) - Weary mood
```bash
./server/generate_batch_parables.sh 7 1
```

### Batch 8 (Day 29) - Optional final batch (Anxious mood)
```bash
./server/generate_batch_parables.sh 8 2
```

## Quick Reference

**Mood Index:**
- 0 = joyful
- 1 = weary
- 2 = anxious
- 3 = hurting
- 4 = neutral

**Faith Tradition Alternation:**
- Odd batch numbers (1, 3, 5, 7) = Protestant
- Even batch numbers (2, 4, 6, 8) = Catholic

## Month 2+ Plan (Pro Plan $99/month)

After upgrading to Pro plan:
- 500,000 characters/month
- Can increase to every 3 days or add more variety in lengths
- Consider adding more 10/15/20 min parables

## Notes

- Each generation includes automatic manifest.json updates
- Text files are saved alongside audio for reference
- Script handles rate limiting between API calls
- Generated files go to `assets/stories/` directory
