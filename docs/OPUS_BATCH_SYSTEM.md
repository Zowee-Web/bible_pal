# Bible PAL — Opus 4.6 Batch Generation System

**Status:** LOCKED
**Version:** 1.0
**Created:** 2026-03-29
**Author:** Claude Opus 4.6

This document is the canonical source of truth for all story generation in the
Opus 4.6 system. It governs batch structure, quality standards, generation
workflow, and manifest rules.

Any deviation from this document requires explicit approval before proceeding.

---

## 0. Document Hierarchy

This document operates within the existing Bible PAL documentation hierarchy:

1. `docs/INVARIANTS.md` — Non-negotiable app rules (highest authority)
2. `docs/SPEC.md` — Product specification
3. `docs/STORY_FACTORY.md` — Story generation contracts and engine architecture
4. **`docs/OPUS_BATCH_SYSTEM.md`** — This file (batch workflow and quality rules)
5. `CLAUDE.md` — Workflow guide

If this document conflicts with INVARIANTS.md or SPEC.md, those documents win.
If this document conflicts with STORY_FACTORY.md on Opus-specific topics
(batch structure, word count targets, length policy), this document wins.

---

## 1. System Architecture

Two completely separate systems exist. They must never be mixed.

### Legacy System (FROZEN)

| Property     | Value                          |
|-------------|-------------------------------|
| ID ranges   | 500s (creative), 800s (traditional) |
| Manifest    | `assets/stories/manifest.json` |
| Status      | Frozen — never modify or extend |
| Engines     | gpt-4.1 (traditional), Ollama (creative) |

### Opus System (ACTIVE)

| Property     | Value                          |
|-------------|-------------------------------|
| ID ranges   | 1000–1999 (traditional), 2000–2999 (creative) |
| Manifest    | `assets/stories/manifest_opus.json` |
| Status      | Active — all new content goes here |
| Engine      | Claude Opus 4.6 only           |

**Rules:**
- Never place new stories into legacy ID ranges.
- Never modify `manifest.json`.
- Never route generation through `generate_v2_batch.sh` or legacy pipelines.
- All new stories use `manifest_opus.json` exclusively.

---

## 2. Batch Structure (Locked)

Every batch contains exactly **32 unique story IDs**:

| Category          | Count | ID Range    | Lanes    |
|-------------------|-------|-------------|----------|
| Traditional adult | 8     | 1000–1999   | WEB + KJV |
| Traditional kid   | 8     | 1000–1999   | WEB only  |
| Creative adult    | 8     | 2000–2999   | WEB only  |
| Creative kid      | 8     | 2000–2999   | WEB only  |

### KJV Lane Rule (Critical)

"8 KJV stories" means 8 KJV **lanes** on the same 8 traditional adult IDs.
KJV is NEVER a separate story ID. Each traditional adult ID produces:
- 3 WEB text files (short/full/long)
- 3 KJV text files (short/full/long)
- 2 reflections (WEB + KJV)
- 1 meta JSON

### Mood Distribution

Each batch covers all 8 moods exactly once per category:
`anxious`, `brave_courage`, `calm_peaceful`, `encouraging`,
`grateful`, `hurting`, `joyful`, `weary`

### Voice Rotation

- No voice repeats within a single batch category.
- Track cross-batch voice usage to prevent overuse over time.
- Voice assignments are recorded in meta JSON.

### Scripture Anchors

- Traditional stories must use unused anchors from `assets/stories/scripture_anchor_registry.json`.
- Kid stories reuse the same anchors as adult (same passage, different audience).
- Verify anchors against existing stories on disk before assignment.
- Creative stories use themes, not scripture anchors.

---

## 3. Length System

### Required vs Optional

| Length | Status   |
|--------|----------|
| Short  | REQUIRED |
| Full   | REQUIRED |
| Long   | OPTIONAL |

**Long Story Policy:**
- If a story cannot support a strong long version without padding, repetition,
  or quality loss — do NOT create one.
- Quality is always prioritized over length uniformity.
- Each story declares its available lengths in meta and manifest.

### Word Count Targets

**Traditional (adult and kid):**

| Bucket | Target Range | Aim For |
|--------|-------------|---------|
| Short  | 350–450     | 400     |
| Full   | 700–850     | 780     |
| Long   | 1201–1400   | 1300    |

**Creative (adult and kid):**

| Bucket | Target Range | Aim For |
|--------|-------------|---------|
| Short  | 250–380     | 320     |
| Full   | 450–650     | 550     |
| Long   | 750–1050    | 900     |

These are hard targets. Stories outside these ranges must be corrected.

---

## 4. Daniel Standard (Quality Contract)

The Daniel Standard is the locked quality benchmark for all Opus stories.
Named after Story 816 (Daniel in the Lions' Den, VOICE_BRADFORD).

### Universal Requirements

Every story must:
- Unfold scene-by-scene (never summarized or compressed)
- Include physical grounding (environment, movement, sensory detail)
- Maintain audio-ready pacing and rhythm
- Use sentences of 8–18 words (with short emphasis beats of 1–5 words)
- Use paragraphs of 1–3 sentences
- Alternate sentence lengths for spoken rhythm
- Include dialogue to break exposition

### Traditional Guardrails

Traditional stories must also:
- Remain faithful to the specific scripture passage
- Preserve all characters, events, and outcomes from the passage
- End where the passage ends (no aftermath or added resolution)
- Use third-person narrative posture

**Forbidden in Traditional:**
- Added theology or interpretation
- Symbolism or allegory not in the passage
- Inner monologue not implied by scripture
- Invented dialogue outside the passage
- Devotional commentary ("This teaches us...")
- MoDC companionship voice ("I sit with you")
- First/second person spiritual guide posture

### Creative Guardrails

Creative stories must:
- Be original (not Bible retellings)
- Weave biblical themes naturally (faith, hope, love, kindness, perseverance)
- Use third-person or gentle omniscient narrative
- End with quiet hope or gentle resolution

**Forbidden in Creative:**
- Scripture claims or quoting
- Doctrine taught as fact
- Commands or prescriptions ("you should")
- Advice ("try to", "remember to")
- Dependency language
- Therapeutic promises

### Kid Story Adjustments

Kid stories (ages 5–10) use:
- Simpler vocabulary and shorter sentences
- More concrete sensory details
- Warm, gentle tone (like a parent at bedtime)
- Same scripture faithfulness (traditional) or theme rules (creative)

### Style Reference

Target this feel for Traditional WEB:

> In the days when Darius was king, Daniel served with wisdom and integrity
> in the courts of Babylon. The king set over his kingdom a hundred and
> twenty leaders, and above them he appointed three high officials, one of
> whom was Daniel. Because of Daniel's excellent spirit, the king considered
> setting him over the whole realm. This stirred up envy among the other
> officials. They looked for a fault in Daniel's service, but he was faithful.

---

## 5. Generation Method

- All stories are generated directly by Claude Opus 4.6.
- Prompt templates (`server/prompts/traditional_prompt.template.txt`,
  `server/prompts/creative_prompt.template.txt`) serve as quality guides only.
- Do NOT route through `generate_v2_batch.sh` or other model pipelines.
- Stories should match the quality and structure of existing Opus stories
  in the 1000–2015 range exactly.

### Parallelization

Use parallel agents to generate stories efficiently:
- Group stories by category (trad adult, trad kid, creative adult, creative kid)
- Each agent handles 4–8 stories
- Include quality references and word count targets in each agent prompt

---

## 6. File Structure

### Directory Layout

```
assets/stories/traditional/<id>/
  story_<id>_traditional_web_short.txt
  story_<id>_traditional_web_full.txt
  story_<id>_traditional_web_long.txt     (if long exists)
  story_<id>_traditional_kjv_short.txt    (adult only)
  story_<id>_traditional_kjv_full.txt     (adult only)
  story_<id>_traditional_kjv_long.txt     (adult only, if long exists)
  reflection_<id>_traditional_web.txt
  reflection_<id>_traditional_kjv.txt     (adult only)
  meta_<id>.json

assets/stories/creative/<id>/
  story_<id>_creative_web_short.txt
  story_<id>_creative_web_full.txt
  story_<id>_creative_web_long.txt        (if long exists)
  reflection_<id>_creative_web.txt
  meta_<id>.json
```

### Meta JSON Schema

Traditional adult (dual-lane):
```json
{
  "schemaVersion": 2,
  "storyId": 1016,
  "mode": "traditional",
  "kidFriendly": false,
  "primaryLanguageStyle": "WEB",
  "lanes": ["web", "kjv"],
  "mood": "anxious",
  "scriptureAnchor": "Genesis 12:1-9",
  "bibleStoryKey": "abram_called",
  "lengths": ["short", "full", "long"],
  "voiceKey": "VOICE_RUTH_COMFORT",
  "createdByModel": "claude-opus-4-6",
  "generationBatch": "PAL_OPUS_BATCH_01",
  "generationContractVersion": "STORY_FACTORY_v2.3",
  "reflectionQuestion": "...",
  "title": "...",
  "files": {
    "short": { "storyText": "story_1016_traditional_web_short.txt" },
    "full": { "storyText": "story_1016_traditional_web_full.txt" },
    "long": { "storyText": "story_1016_traditional_web_long.txt" },
    "reflection": { "reflectionText": "reflection_1016_traditional_web.txt" }
  },
  "reflections": {
    "web": "reflection_1016_traditional_web.txt",
    "kjv": "reflection_1016_traditional_kjv.txt"
  },
  "reflectionSource": "llm",
  "storyVoiceKey": "VOICE_RUTH_COMFORT",
  "reflectionVoiceKey": "VOICE_RUTH_COMFORT"
}
```

**Text-only entries:** Omit `audioFilePath` entirely. Do not fabricate paths.

**`lengths` field:** Must reflect only the lengths that actually exist on disk.

---

## 7. Manifest Rules

### manifest_opus.json

- Standalone file at `assets/stories/manifest_opus.json`.
- Contains ONLY Opus stories (IDs 1000–2999).
- Never modify `manifest.json` (legacy system).
- Built from on-disk scan — only stories that exist are included.
- Top-level key: `"parables"` (array of entries).

### Manifest Entry Schema

```json
{
  "storyId": "story_1016_anxious_short_traditional",
  "title": "...",
  "mood": "anxious",
  "emotionalTags": [],
  "storytellingMode": "traditional",
  "kidFriendly": false,
  "textFilePath": "traditional/1016/story_1016_traditional_web_short.txt",
  "translationId": "WEB",
  "languageStyle": "WEB",
  "narratorVoiceKey": "VOICE_RUTH_COMFORT",
  "storyLength": "short",
  "availableLengths": ["short", "full", "long"],
  "reflectionQuestion": "...",
  "bibleSourceRef": "Genesis 12:1-9",
  "bibleStoryKey": "abram_called"
}
```

- `audioFilePath`: Include only if audio file exists on disk. Omit for text-only.
- `availableLengths`: Must match what exists on disk for this story.
- One entry per length per lane (e.g., a dual-lane story with 3 lengths = 6 entries).

---

## 8. Review + Correction Pipeline

Every batch must complete this pipeline before the manifest is built.

### Phase 1: Generation
- Generate all 32 stories using parallel agents.
- Each agent receives quality references, word count targets, and guardrails.

### Phase 2: Full Audit
- Run word count checks on every text file.
- Flag all stories outside target ranges.
- Spot-check 2–3 stories per category for Daniel Standard quality.

### Phase 3: Correction
- **Under-length:** Fully regenerate with scene expansion (not patching).
- **Over-length:** Trim carefully or fully regenerate. For longs, consider dropping.
- **Low quality:** Full rewrite. Never patch a bad story.
- **Over-length longs:** Drop the long file entirely if trimming would hurt quality.

### Phase 4: Re-audit
- Verify all corrections hit targets.
- If corrections overcorrected, run another pass.

### Phase 5: Manifest Generation Gate

The manifest MUST NOT be built until ALL of the following are true:

- [ ] All stories pass word count validation
- [ ] All stories meet Daniel Standard quality (spot-checked)
- [ ] All `availableLengths` fields are correct and match on-disk files
- [ ] All referenced files exist on disk (File Integrity Invariant)
- [ ] No story references a dropped long in meta or manifest
- [ ] All meta JSON files have correct `lengths` arrays

Only after all gates pass: build `manifest_opus.json` by scanning on-disk files.

---

## 9. Batch Naming

Sequential batch names:
```
PAL_OPUS_BATCH_01
PAL_OPUS_BATCH_02
PAL_OPUS_BATCH_03
...
```

### ID Continuity

Before starting a batch:
1. Scan `assets/stories/traditional/` for the highest existing ID in 1000–1999.
2. Scan `assets/stories/creative/` for the highest existing ID in 2000–2999.
3. Start the new batch at the next available IDs.

Do not guess or assume — always scan.

---

## 10. Safety Rule

If any instruction conflicts with this system:
1. **STOP** — do not proceed.
2. **Explain** the specific conflict.
3. **Ask** for clarification before taking action.

Never improvise or deviate from this system without explicit approval.

---

## 11. Batch History

| Batch              | IDs              | Date       | Notes                    |
|--------------------|-----------------|------------|--------------------------|
| PAL_OPUS_BATCH_01  | 1016–1031, 2016–2031 | 2026-03-29 | First batch under this system. 10 longs retained, 22 dropped for quality. |

---

## 12. Cross-Batch Tracking (Recommended)

To prevent drift over time:

- **Scripture anchors:** Check registry before each batch. Update after.
- **Voice rotation:** Track which voices were used in recent batches.
  Avoid assigning the same voice to the same mood in consecutive batches.
- **Creative DNA:** Vary opening types, structures, and tones across batches.
  Track in batch notes to prevent repetition.
- **KJV reflection tone:** KJV reflections should use elevated classical language
  matching the KJV lane, not modern English.
