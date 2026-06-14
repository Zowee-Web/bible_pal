# Audio Preflight: TTS-Readability Audit (2026-06-13)

Scope: every Bible PAL traditional story text file that currently has no matching
compressed audio file. Pure read-only analysis. No prose, audio, or commits made.

The goal is to surface the files most likely to sound robotic / awkward in
ElevenLabs and to recommend specific punctuation/breath fixes before rendering —
not to rewrite or modernize the corpus.

---

## Methodology

Pairings inferred from existing repo conventions:

  - Text:       `assets/stories/traditional/<id>/story_<id>_traditional_<lang>_<length>.txt`
  - Reflection: `assets/stories/traditional/<id>/reflection_<id>_traditional_<lang>.txt`
  - Audio:      `assets_audio_compressed/stories/traditional/<id>/` (the published, -18 LUFS mirror)

A text file is "missing audio" iff the matching `.mp3` filename is absent from
the compressed mirror. Kid-suffixed variants were excluded (kid generation paused
per project memory).

Mechanical scoring split each issue between two registers:

  - **Prose-side** issues are fully rewritable (length splits, comma → period,
    semicolon → period, drop a reused phrase).
  - **Scripture-block** issues are limited to punctuation/breath polish only.
    Adam: "Do not change Scripture quotation wording unless absolutely necessary
    for punctuation/breathing only."

Severity tiers (based on prose-side "actionable points"):

| Tier   | Definition |
|--------|------------|
| high   | clearly likely to sound non-human; warrants a fix pass before audio |
| medium | probably acceptable but would benefit from polish |
| low    | minor polish only; do not block audio |
| clean  | safe to render as-is |

After mechanical scoring, the high-severity bucket was manually read and triaged
to distinguish **true positives** (real prose-side issues) from **intentional
Hebraic refrain / scripture-protected** false positives.

---

## Summary counts

Inventory (story + reflection):

  - Total missing-audio text files: **399** across **134** story IDs
    - Story files: 336
    - Reflection files: 63
  - Already-rendered pairs (sanity check): 2,769
  - Kid-variant text files skipped: 41

Mechanical scoring (before manual triage):

| Severity | Count |
|----------|------:|
| high     | 33 |
| medium   | 54 |
| low      | 109 |
| clean    | 203 |

After manual triage of all 33 mechanical highs, the corpus splits into three
operational categories:

| Category | Files | Action |
|---|---:|---|
| **Fix before audio** (true prose-side issues) | **~12** | targeted edit pass |
| **Scripture-pacing polish** (punctuation/breath only) | ~10 | optional, light touch |
| **Safe to render as-is** | ~377 | render now |

Length distribution of missing-audio story files:

| Lang | Length | Missing |
|------|--------|--------:|
| kjv  | short  | 82 |
| kjv  | full   | 97 |
| kjv  | long   | 87 |
| web  | full   | 28 |
| web  | long   | 42 |
| web  | short  | 0 |

WEB short is fully rendered — confirms the existing "short web is default first
render" pattern. The backlog is overwhelmingly KJV variants + WEB full/long.

Reflection files: only 2 of 63 missing-audio reflections show non-clean signal
(both are storyId 1082 KJV/WEB — `repeated phrase` flag is the same Hebraic
refrain pattern, false positive).

---

## Fix before audio (prose-side, true high severity)

These files have real prose-side TTS problems that warrant a quick edit pass
before ElevenLabs rendering. **800-series stories** (legacy corpus) are
over-represented here — they tend toward atmospheric chronicle voice rather
than warm storytelling, and several already have a separate content-audit
flag pending. See note at end.

Each entry lists: missing audio path, severity, dominant issue types,
1-2 example quotes, and the recommended micro-fix shape.

---

### 1. Story 804 — KJV Long (Romans 8:28 meditation) — HIGH

- Text: [assets/stories/traditional/804/story_804_traditional_kjv_long.txt](../assets/stories/traditional/804/story_804_traditional_kjv_long.txt)
- Missing audio: `assets_audio_compressed/stories/traditional/804/audio_804_story_kjv_long.mp3`
- Issues: long sentence (prose) · semicolon chain (prose) · awkward breathing · overloaded ending
- Example (multi-comma serial chain, no internal period anchor):
  > "Without, the city bustled with the push and pull of business, the cries of merchants in crowded streets, the patter of feet upon warm stone, the clatter of pots, the steady hum of daily life continuing on."
- Example (semicolon-paralleled "some" chain):
  > "Some looked wearied from work; some were hunched in thought; some moved busily, attending unto the needs of the others."
- **Fix:** the whole story carries a chronicle-meditation register, not a story-form voice. Break the long "There were…" / "Some… some… some…" serial sentences into 2-3 sentences each. Replace semicolons with periods in narration (keep within Scripture). This is the closest match in the corpus to the "formal chronicle instead of Ruth warmly telling one person a story" pattern Adam flagged.

### 2. Story 807 — KJV Long & Full (Psalm 127 meditation) — HIGH

- Text long: [assets/stories/traditional/807/story_807_traditional_kjv_long.txt](../assets/stories/traditional/807/story_807_traditional_kjv_long.txt)
- Text full: [assets/stories/traditional/807/story_807_traditional_kjv_full.txt](../assets/stories/traditional/807/story_807_traditional_kjv_full.txt)
- Missing audio: `audio_807_story_kjv_long.mp3`, `audio_807_story_kjv_full.mp3`
- Issues: long sentence (prose) · awkward breathing (prose)
- Example (long sentence with em-dash chain, no period anchor):
  > "Yet though they kept watch with all the skill and courage they could gather, at times they felt fear pressing upon them — a fear that their watching might not be enough, that their strength alone could not keep the city from every threat that moved in the darkness."
- Example (atmospheric run-on opening):
  > "In the quiet of a growing city, where the stones of new buildings rose day by day, and where hammers rang through the early morning, the people came and went, with hope in their hearts and dreams in their hands."
- **Fix:** atmospheric extension paragraphs need period anchors. Convert "X, where Y, where Z" run-ons into two sentences. Watch repeated "builders / watchmen" pairings — they form a refrain at high frequency.

### 3. Story 811 — KJV Long (Emmaus road) — HIGH

- Text: [assets/stories/traditional/811/story_811_traditional_kjv_long.txt](../assets/stories/traditional/811/story_811_traditional_kjv_long.txt)
- Missing audio: `audio_811_story_kjv_long.mp3`
- Issues: long sentence (prose) · awkward breathing · overloaded ending
- Example (overloaded ending, 44w, multi-clause):
  > "In the quiet of that upper room, faith and astonishment were woven together as, through shared words and remembrances, the truth became firm among them: the Lord was alive, revealed in the most unlooked-for company, and known in the simple breaking of bread."
- Example (declarative recap with no internal period):
  > "They told of all that had befallen them in the way, declaring how Jesus had walked with them, how he had opened unto them the scriptures, and above all, how he was known of them in breaking of bread."
- **Fix:** ending must "settle" (per `feedback_story_settles_endings`), not stack four clauses. Split the closing sentence into 2 with the colon → period. Also flagged for **legacy content audit** in project memory (`project_800_series_content_audit`).

### 4. Story 822 — KJV Full (Samuel's calling) — HIGH

- Text: [assets/stories/traditional/822/story_822_traditional_kjv_full.txt](../assets/stories/traditional/822/story_822_traditional_kjv_full.txt)
- Missing audio: `audio_822_story_kjv_full.mp3`
- Issues: long sentence (prose) · semicolon chain (prose, embedded in dialogue tags) · repeated phrase (some legitimate)
- Example (atmospheric extension paragraph 17 — comma chain, no period anchor):
  > "The old priest's heart was heavy for his sons, but he trusted Samuel's calling, and sometimes he found a measure of peace beholding the boy who hearkened and ever answered."
- Example (closing extension paragraph):
  > "As the days and seasons passed in Shiloh, Samuel moved among the people quietly, learning to hearken for the voice of God in ways both loud and soft."
- **Fix:** the iconic Samuel-Eli back-and-forth (paragraphs 3-9) is excellent and should be untouched. The added atmospheric extensions (paragraphs 15 and 17) are the real concern — convert each into 2-3 shorter period-anchored sentences. The "lie down again Samuel" / "for thy servant heareth" 4-gram repeats are Scripture-rooted and should not be touched.

### 5. Story 801 — KJV Long (Sermon / Matthew 11:28-30) — HIGH

- Text: [assets/stories/traditional/801/story_801_traditional_kjv_long.txt](../assets/stories/traditional/801/story_801_traditional_kjv_long.txt)
- Missing audio: `audio_801_story_kjv_long.mp3`
- Issues: long sentence (prose) · semicolon chain (prose) · awkward breathing · overloaded ending
- Example (multi-comma serial chain):
  > "Jesus' eyes searched the multitude, beholding the mothers wearied by many days' care, the old man leaning upon his staff, the tradesman with rough palms and hunched back, even the children whose faces too bare shadows."
- Example (overloaded ending, 43w):
  > "In the midst of heat and toil and longing, the Teacher's voice left an imprint — an invitation enduring beyond the moment, borne upon the footsteps of all that departed that hillside at dusk, and echoing still in…"
- **Fix:** convert the "beholding A, B, C, D" enumerations into list-style sentences with periods. The ending needs to taper, not stack. 800-series content-audit flag applies.

### 6. Story 816 — KJV Long & Full (Daniel in lions' den) — HIGH

- Text long: [assets/stories/traditional/816/story_816_traditional_kjv_long.txt](../assets/stories/traditional/816/story_816_traditional_kjv_long.txt)
- Text full: [assets/stories/traditional/816/story_816_traditional_kjv_full.txt](../assets/stories/traditional/816/story_816_traditional_kjv_full.txt)
- Missing audio: `audio_816_story_kjv_long.mp3`, `audio_816_story_kjv_full.mp3`
- Issues: long sentence (prose) · semicolon chain (prose) · awkward breathing · overloaded ending
- Example (60+ word prose run-on wrapping a long Scripture quote — needs structural split):
  > "Knowing they could find no occasion against Daniel concerning the affairs of the kingdom, the officials consulted together and said, 'We shall not find any occasion against this Daniel, except we find it against him concerning the law of his God.'"
- Example (semicolon-chained narration around Scripture):
  > "The king spake with a troubled heart unto Daniel, 'Thy God whom thou servest continually, he will deliver thee.' And a stone was brought, and laid upon the mouth of the den; and the king sealed it with his own…"
- Example (ending — Darius decree quote runs 42w, no internal period):
  > "He delivereth and rescueth, and he worketh signs and wonders in heaven and in earth, who hath delivered Daniel from the power of the lions."
- **Fix:** the very long sentence describing the satraps' approach to Darius needs to be split prose-side. Keep the verbatim Scripture quote intact; the framing sentence can be broken in half. Add period breaks between "And a stone was brought" / "And the king sealed it" — drop the semicolons.

### 7. Story 826 — KJV Full (David vs Goliath) — HIGH

- Text: [assets/stories/traditional/826/story_826_traditional_kjv_full.txt](../assets/stories/traditional/826/story_826_traditional_kjv_full.txt)
- Missing audio: `audio_826_story_kjv_full.mp3`
- Issues: long sentence (prose) · semicolon chain (prose) · awkward breathing · repeated phrase (likely intentional)
- Example (narration semicolon chain bridging two Scripture quotes):
  > "'I cannot go with these,' he said; 'for I have not proved them.' He put them off; and, with his staff in his hand, he chose him five smooth stones out of the brook."
- Example (action recap, no internal period anchor):
  > "He put his hand in his bag, and took thence a stone, and slang it, and smote the Philistine in his forehead, that the stone sunk into his forehead; and he fell upon his face to the earth."
- **Fix:** replace the narration semicolons with periods. The "smote… in his forehead, that the stone sunk into his forehead" repeat is from the 1 Samuel 17 source — leave it but split it into two sentences so the listener gets a breath.

### 8. Story 819 — KJV Long (Esther — Mordecai honored) — HIGH

- Text: [assets/stories/traditional/819/story_819_traditional_kjv_long.txt](../assets/stories/traditional/819/story_819_traditional_kjv_long.txt)
- Missing audio: `audio_819_story_kjv_long.mp3`
- Issues: long sentence (prose) · Scripture-block pacing · repeated phrase (Scripture-rooted)
- Example (compound narrative sentence — paraphrases what Haman thought + spoke):
  > "The king said, 'What shall be done unto the man whom the king delighteth to honour?' Haman thought the king meant himself, and answered that royal apparel and the king's horse should be brought, and a noble prince…"
- **Fix:** "and answered that A, and B, and C" needs period splits. The "whom the king delighteth to honour" 4-gram is the Esther 6 refrain — leave it.

### 9. Story 830 — KJV Long (Prodigal son) — HIGH

- Text: [assets/stories/traditional/830/story_830_traditional_kjv_long.txt](../assets/stories/traditional/830/story_830_traditional_kjv_long.txt)
- Missing audio: `audio_830_story_kjv_long.mp3`
- Issues: semicolon chain (prose) · Scripture-block pacing · overloaded ending
- Example (narration semicolon chain):
  > "One by one, his friends slipped away; the feasts grew quieter; the food waned."
- **Fix:** replace narration semicolons with periods (parable-style cadence loves short hard stops, per `feedback_speakable_prose`). Keep the Luke 15 quotation intact.

### 10. Story 823 — KJV Full & Long (Esther) — HIGH (Scripture-pacing-heavy)

- Text full: [assets/stories/traditional/823/story_823_traditional_kjv_full.txt](../assets/stories/traditional/823/story_823_traditional_kjv_full.txt)
- Text long: [assets/stories/traditional/823/story_823_traditional_kjv_long.txt](../assets/stories/traditional/823/story_823_traditional_kjv_long.txt)
- Missing audio: `audio_823_story_kjv_full.mp3`, `audio_823_story_kjv_long.mp3`
- Issues: long Scripture quote runs · awkward breathing inside Scripture quotes · prose framing with no internal period
- Example (Esther's plea — direct KJV quote, very long single breath):
  > "She sent one last message unto Mordecai, saying, 'Go, gather together all the Jews that are present in Shushan, and fast ye for me, and neither eat nor drink three days, night or day: I also and my maidens will…'"
- Example (Mordecai's reply — colon + semicolon + colon in one sentence):
  > "For if thou altogether holdest thy peace at this time, then shall there enlargement and deliverance arise to the Jews from another place; but thou and thy father's house shall be destroyed: and who knoweth whether…"
- **Fix:** these are direct KJV quotes — wording is locked. The fix is **punctuation only**: convert internal colons to em-dashes or periods to give ElevenLabs longer breath markers. Iconic "if I perish, I perish" must stay verbatim. Optional, light touch only.

### 11. Story 825 — KJV Full (Saul / Lord was not with him) — MEDIUM (Scripture-pacing only)

- Text: [assets/stories/traditional/825/story_825_traditional_kjv_full.txt](../assets/stories/traditional/825/story_825_traditional_kjv_full.txt)
- Issues: Scripture block pacing only · repeated phrase ("but the Lord was not / the Lord was not" — biblical refrain)
- **Action:** safe to render. Optional: confirm Scripture quote breath spacing.

### 12. Stories 1105 KJV Full/Long (Paul's storm, Acts 27) — MEDIUM

- Issues flagged as "long sentence (prose)" are actually the Acts 27:23-25 direct quote ("For there stood by me this night the angel of God…"). Scripture-protected.
- **Action:** safe to render. Optional: add em-dash breath in Scripture if needed.

---

## Safe to render as-is (false-positive high/medium flags)

These stories triggered mechanical flags but on inspection are intentional
Hebraic refrain, direct Scripture-quote wording, or both. They read cleanly and
the patterned repetition is the literary point.

| Story | Variant | Flag pattern | Why safe |
|---|---|---|---|
| 1038 | KJV long | repeated 4-grams "the evening and the morning were the" | Genesis 1 day-refrain — iconic, intentional |
| 1038 | WEB long | repeated 4-grams "There was evening and there was morning" | Same Genesis 1 refrain in WEB phrasing |
| 1046 | KJV full | same Genesis 1 refrain | Creation retelling |
| 1063 | KJV short | "while he was yet speaking, there came also another" / "I only am escaped to tell thee" | Job 1 iconic refrain — exactly the desired Hebraic hammer effect |
| 1031 | KJV full | "an omer for every man" | Exodus 16 manna instruction — direct Scripture content |
| 1043 | KJV short/full | "the flesh and the unleavened cakes" | Exodus 12 Passover instruction — direct Scripture content |
| 834 | KJV long | "fearful and afraid let him return" / "the Lord set every man's…" | Gideon's army call — direct Scripture content |
| 809 | KJV long | "the wind and the sea obey him" | Mark 4 disciples' line — direct Scripture |
| 831 | KJV full/long | "behold seven ears" / "are seven years and" | Joseph's interpretation of Pharaoh's dream — Scripture |
| 1487 | KJV/WEB long | "righteous with the wicked" + patterned "What if there are X found there" | Genesis 18 Abraham bargaining — patterned dialogue is the literary point |
| 1091 | WEB long | "fall down and worship" / "worship the golden image" | Daniel 3 herald's decree + repeated test — verbatim Scripture |
| 1079 | WEB long | "Have you not known? Have you not heard?" + "the ones who…" catalogs | Isaiah 40 — iconic refrain, also reads with perfectly tapering ending |
| 1511 | WEB/KJV long | "shall not come into this city" repeated 3× | Isaiah 37:33 — verbatim refrain in the actual prophecy |
| 1109 | WEB long | "blessed are the barren" + "fall on us" + "cover us" | Luke 23 verbatim Jesus quotation |
| 1082 | KJV/WEB reflection | repeated 4-gram | reflection-only, reads fine |

Total in safe-to-render bucket: approximately 21 of the 33 mechanical highs +
all 109 low-tier files + all 203 clean-tier files = **roughly 350 of 399** are
safe to render now.

---

## Common patterns observed

1. **Scripture-block pacing is the dominant issue in the KJV variants.** The
   KJV's long flowing sentences with internal semicolons/colons sound great
   visually but stack multi-breath runs into a single ElevenLabs inhale. Fix
   is punctuation/breath substitution, never wording change.

2. **Hebraic refrain ≠ robotic repetition.** Genesis day-refrain, Job
   "while he was yet speaking" hammer, Isaiah "have you not known", Abraham's
   bargaining pattern — these are literarily the point. The mechanical
   repeat-phrase detector will always over-flag here; manual judgment is
   required. The audit treats these as safe.

3. **800-series legacy stories cluster in the true-high tier.** 18 of 33
   mechanical highs are storyId 801–834. They tend toward atmospheric
   chronicle voice rather than warm storytelling — exactly the "formal
   chronicle instead of Ruth warmly telling a story" register Adam flagged.
   These ALSO have a separate pending **content audit** flag per project
   memory (`project_800_series_content_audit`: 811 and 815 confirmed
   off-anchor). Recommend bundling the TTS-readability pass with the content
   audit pass for 800-series rather than fixing prose twice.

4. **WEB stories are mostly clean.** Only 5 of 33 mechanical highs are WEB
   (and all 5 are false positives on inspection). The audio-first /
   speakable-prose discipline (`feedback_audio_first_immersion`,
   `feedback_speakable_prose`, locked B23+) has clearly landed on the
   1000-series WEB corpus.

5. **The "overloaded ending" flag is the highest-signal real issue.** Six
   stories triggered it, and in every case the closing sentence had stacked
   3+ clauses with colons/em-dashes, which audio listeners will hear as the
   narrator running out of breath at the end (violates
   `feedback_tapering_endings`).

6. **No issues found in reflection-only renders.** Of 63 missing-audio
   reflections, only 2 trigger any mechanical signal (storyId 1082) and both
   are false-positive refrain hits. Reflections are safe to batch-render.

---

## Suggested next step

1. **Quick punctuation/breath pass** on the ~12 true-high stories
   (804, 807×2, 811, 822, 801, 816×2, 826, 819, 830, 823×2). Estimated 10-20
   minutes per file for targeted comma → period / semicolon → period /
   end-sentence taper. Total: 1.5-2 hours.

2. **Bundle 800-series TTS prep with the content audit** rather than running
   two passes. The 18 missing-audio 800-series highs overlap heavily with
   the legacy content-audit backlog already in project memory; both passes
   touch the same paragraphs.

3. **Render everything else now.** ~377 of 399 missing-audio text files are
   safe to send to ElevenLabs as-is. The reflection backlog (61 of 63 safe)
   is fully unblocked.

4. **For Scripture-pacing-only stories** (823, 825, 1105, 1109): render
   first, then listen. If a passage actually stumbles in audio, do a
   targeted punctuation-only retouch and re-render. Do not pre-emptively
   edit Scripture wording.

---

## Appendix — Raw data

Per-file mechanical scoring with every flag, every example quote, and every
metric is in:

  - `/tmp/missing_audio.json` — full missing-pair inventory
  - `/tmp/tts_scores_v2.json` — full per-file scoring with examples

These are tmp artifacts; if you want them committed they can be moved into
`docs/reports/` on request.
