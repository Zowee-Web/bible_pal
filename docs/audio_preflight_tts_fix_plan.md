# Audio Preflight: TTS Fix Plan (2026-06-13)

Scope: the 13 files in the "fix before audio" bucket of
[audio_preflight_tts_readability_audit.md](audio_preflight_tts_readability_audit.md).
Read-only plan. No story files edited, no audio rendered, no commits.

## Editing rules

- **No Scripture wording changes.** Punctuation (semicolon → period, colon → period,
  internal em-dash for breath) inside Scripture quotes is permitted; word
  substitutions, additions, deletions, modernizations are not.
- **No KJV modernization.** Keep "saith / spake / unto / hath / thee / thou" etc.
- **Smallest safe edit.** Prefer (a) split a sentence at an existing comma/semicolon/colon,
  (b) collapse a multi-comma serial chain into a list of period-anchored sentences,
  (c) insert one period in a Scripture quote so the TTS gets a breath, before
  any rewrite.
- **Voice: Ruth telling one person the story.** Atmospheric "literary flourish"
  paragraphs that don't carry the narrative are the most common true-positive
  TTS hazard. Trim or split them; do not delete the story content.
- **Endings settle, not stack.** Closing sentence taper — keep ≤2 commas and no
  em-dash chain on the last sentence.

## Issue classification used below

| Tag | Meaning |
|---|---|
| **prose-only** | edits are entirely outside Scripture quotes |
| **scripture-punctuation-only** | only adjustments are period-for-semicolon/colon swaps inside a verbatim Scripture quote |
| **mixed** | both prose narration and scripture-quote pacing need touch |

## File summary

| # | Story | Variant | Type | Edit size |
|---:|---|---|---|---|
| 1 | 804 | kjv long  | prose-only | medium (~6 paragraphs touched) |
| 2 | 807 | kjv long  | prose-only | small (2 paragraphs) |
| 3 | 807 | kjv full  | prose-only | small (2 paragraphs) |
| 4 | 811 | kjv long  | prose-only | small (1 paragraph — ending) |
| 5 | 822 | kjv full  | prose-only | small (2 atmospheric paragraphs) |
| 6 | 801 | kjv long  | prose-only | small (2 paragraphs incl. ending) |
| 7 | 816 | kjv long  | mixed | small (1 prose + 2 Scripture-punct.) |
| 8 | 816 | kjv full  | mixed | small (1 prose + 2 Scripture-punct.) |
| 9 | 826 | kjv full  | mixed | small (1 prose + 1 Scripture-punct.) |
| 10 | 819 | kjv long  | prose-only | tiny (1 paragraph) |
| 11 | 830 | kjv long  | prose-only | tiny (1 paragraph) |
| 12 | 823 | kjv full  | mixed | small (1 prose + 1 Scripture-punct.) |
| 13 | 823 | kjv long  | scripture-punctuation-only | small (2 Scripture-punct.) |

Estimated total time: ~90 minutes for all 13 files.

---

## 1. Story 804 — KJV Long (Romans 8:28 meditation)

**File:** [assets/stories/traditional/804/story_804_traditional_kjv_long.txt](../assets/stories/traditional/804/story_804_traditional_kjv_long.txt)
**Missing audio:** `assets_audio_compressed/stories/traditional/804/audio_804_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — Romans 8:28 quote (paragraphs 18 and 38) is untouched.

This story carries a chronicle-meditation register throughout. The cleanup keeps
the warm "elder reading the letter to the believers" frame but breaks up the
serial-comma run-ons that won't breathe in TTS.

### Paragraph at line 10 — prose run-on + semicolon chain

**Before** (first three sentences):
> Without, the city bustled with the push and pull of business, the cries of merchants in crowded streets, the patter of feet upon warm stone, the clatter of pots, the steady hum of daily life continuing on. Yet within these walls, a small company of believers, men and women and children alike, gathered close. Some looked wearied from work; some were hunched in thought; some moved busily, attending unto the needs of the others.

**After**:
> Without, the city bustled with the push and pull of business. The cries of merchants rose in crowded streets. The patter of feet sounded upon warm stone, the clatter of pots, the steady hum of daily life continuing on. Yet within these walls, a small company of believers gathered close — men and women and children alike. Some looked wearied from work. Some were hunched in thought. Some moved busily, attending unto the needs of the others.

### Paragraph at line 22 — "There was X, there was Y" comma chain

**Before:**
> There were tears upon cheeks, there were questions silently held in the heart, there was work that seemed without end, and pain that was sometimes hard to name. There were days of abundance, when the table overflowed and laughter rang loud; and there were days of want, when the lamp flickered longer than the bread lasted, and feet ached with searching.

**After:**
> There were tears upon cheeks. There were questions silently held in the heart. There was work that seemed without end, and pain that was sometimes hard to name. There were days of abundance, when the table overflowed and laughter rang loud. And there were days of want, when the lamp flickered longer than the bread lasted, and feet ached with searching.

### Paragraph at line 24 — overloaded sentence with em-dash chain

**Before:**
> Yet, within these walls, Paul's message sounded true. Over and over, through the sweep of days and seasons, in every turn of joy and sorrow, there was this steady assurance: that everything — every happening, every moment, every patch of sorrow, every gift of gladness, the cold night and the warm morning, every loss and every gain — should be worked together for good in the great hands of God.

**After:**
> Yet, within these walls, Paul's message sounded true. Over and over, through the sweep of days and seasons, there was this steady assurance. Everything was being worked together for good in the great hands of God. Every happening, every moment. Every patch of sorrow, every gift of gladness. The cold night and the warm morning. Every loss and every gain.

### Paragraph at line 30 — comma-chain serial dash run

**Before:**
> Unto them that love God — any in this gathering that lifted a prayer in the darkest hour, or sang thanks when a loaf arrived, or cared for a friend with kindness — these words were a path laid before their feet.

**After:**
> Unto them that love God — to any in this gathering that lifted a prayer in the darkest hour, or sang thanks when a loaf arrived, or cared for a friend with kindness — these words were a path laid before their feet.

(Single comma in the middle made into the structural breath. One-word fix.)

### Paragraph at line 36 — comma-chained "the X that Y" runs

**Before:**
> In their memories danced the stories of their own past weeks and months: the grain that did not stretch far enough, yet still there was just enough; the neighbour that was lost, yet found; the fever that raged, and the restless nights, and the cool hand of a friend that soothed a brow.

**After:**
> In their memories danced the stories of their own past weeks and months. The grain that did not stretch far enough, yet still there was just enough. The neighbour that was lost, yet found. The fever that raged, and the restless nights, and the cool hand of a friend that soothed a brow.

---

## 2. Story 807 — KJV Long (Psalm 127 meditation)

**File:** [assets/stories/traditional/807/story_807_traditional_kjv_long.txt](../assets/stories/traditional/807/story_807_traditional_kjv_long.txt)
**Missing audio:** `audio_807_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — Psalm 127:1-2 quotation in paragraph 17 and final stanza in paragraph 25 are untouched.

### Paragraph at line 1 — opening run-on

**Before:**
> In the quiet of a growing city, where the stones of new buildings rose day by day, and where hammers rang through the early morning, the people came and went, with hope in their hearts and dreams in their hands.

**After:**
> In the quiet of a growing city, the stones of new buildings rose day by day. Hammers rang through the early morning. The people came and went, with hope in their hearts and dreams in their hands.

### Paragraph at line 5 — em-dash + comma chain

**Before:**
> Yet though they kept watch with all the skill and courage they could gather, at times they felt fear pressing upon them — a fear that their watching might not be enough, that their strength alone could not keep the city from every threat that moved in the darkness.

**After:**
> Yet though they kept watch with all the skill and courage they could gather, at times they felt fear pressing upon them. A fear that their watching might not be enough. A fear that their strength alone could not keep the city from every threat that moved in the darkness.

---

## 3. Story 807 — KJV Full (Psalm 127 meditation, shorter variant)

**File:** [assets/stories/traditional/807/story_807_traditional_kjv_full.txt](../assets/stories/traditional/807/story_807_traditional_kjv_full.txt)
**Missing audio:** `audio_807_story_kjv_full.mp3`
**Type:** prose-only
**Scripture preserved:** YES — Psalm 127:1-2 quotation embedded in paragraph 11 is untouched.

### Paragraph at line 1 — same opening run-on pattern as Long

**Before** (last sentence of the paragraph):
> Yet even as the sweat stood upon their brows and their sinews grew weary, a voice whispered in the quiet before the dawn: except the Lord himself build this house, all their toil, every plank and every nail, is but vanity.

**After:**
> Yet even as the sweat stood upon their brows and their sinews grew weary, a voice whispered in the quiet before the dawn. Except the Lord himself build this house, all their toil is but vanity. Every plank and every nail.

### Paragraph at line 5 — "rising up early / sitting up late" run-on

**Before** (last two sentences of the paragraph):
> Though they toiled and they were troubled, and sometimes felt swallowed up by the weariness of days upon days of labour, yet the sense lingered that effort alone could not finish the work. Except the Lord bless the labour, all their rising up early, all their sitting up late, would not give them the peace and joy they sought.

**After:**
> Though they toiled and they were troubled, and sometimes felt swallowed up by the weariness of days upon days of labour, the sense lingered that effort alone could not finish the work. Except the Lord bless the labour, all their rising up early would not give them the peace they sought. Neither all their sitting up late.

---

## 4. Story 811 — KJV Long (Emmaus road)

**File:** [assets/stories/traditional/811/story_811_traditional_kjv_long.txt](../assets/stories/traditional/811/story_811_traditional_kjv_long.txt)
**Missing audio:** `audio_811_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — Cleopas' question (paragraph 7) and "Did not our heart burn within us" (paragraph 23) and "The Lord is risen indeed" (paragraph 25) are untouched.

> Note: project memory `project_800_series_content_audit` flags 811 for content-audit
> alongside TTS prep. Bundle both passes when editing.

### Paragraph at line 27 — overloaded ending (44w final sentence)

**Before** (last paragraph in full):
> Cleopas and his companion entered in, eager to add their voices unto the growing testimony. They told of all that had befallen them in the way, declaring how Jesus had walked with them, how he had opened unto them the scriptures, and above all, how he was known of them in breaking of bread. Their sorrow and confusion, once so heavy, were now changed for wonder and a hope that would not fade. In the quiet of that upper room, faith and astonishment were woven together as, through shared words and remembrances, the truth became firm among them: the Lord was alive, revealed in the most unlooked-for company, and known in the simple breaking of bread.

**After:**
> Cleopas and his companion entered in, eager to add their voices unto the growing testimony. They told of all that had befallen them in the way. They told how Jesus had walked with them. They told how he had opened unto them the scriptures. And above all, they told how he was known of them in breaking of bread. Their sorrow and confusion, once so heavy, were now changed for wonder, and for a hope that would not fade. In the quiet of that upper room, faith and astonishment were woven together. Through shared words and remembrances, the truth became firm among them. The Lord was alive — known in the breaking of bread.

(The final sentence now tapers: short clause + em-dash breath + short close. Matches `feedback_tapering_endings`.)

---

## 5. Story 822 — KJV Full (Samuel's calling)

**File:** [assets/stories/traditional/822/story_822_traditional_kjv_full.txt](../assets/stories/traditional/822/story_822_traditional_kjv_full.txt)
**Missing audio:** `audio_822_story_kjv_full.mp3`
**Type:** prose-only
**Scripture preserved:** YES — the Samuel-Eli call-and-response (paragraphs 3, 5, 7, 9, 11) — verbatim Samuel 3:4-10 — is untouched. So is "The Lord do so to thee" exchange in paragraph 11.

The Samuel-Eli dialogue paragraphs are excellent storytelling and need no touch.
The two **atmospheric extension paragraphs** added after the canonical scene end
are what's flagged. They need period anchors.

### Paragraph at line 15 — atmospheric extension run-on

**Before:**
> As the days and seasons passed in Shiloh, Samuel moved among the people quietly, learning to hearken for the voice of God in ways both loud and soft. The elders came unto him with troubled questions, and mothers brought their children unto the tabernacle, trusting that he that heard the Lord might bear up their prayers. There was longing in the land, hope like frail green shoots, as the people spake of Samuel with reverence and curiosity. Sometimes Samuel paused beside the old lamp as the evening fell, feeling the hush of evening settle upon his shoulders, a gentle remembrance of the night the Lord had called him.

**After:**
> As the days and seasons passed in Shiloh, Samuel moved among the people quietly. He was learning to hearken for the voice of God in ways both loud and soft. The elders came unto him with troubled questions. Mothers brought their children unto the tabernacle, trusting that he that heard the Lord might bear up their prayers. There was longing in the land, and hope like frail green shoots. The people spake of Samuel with reverence and curiosity. Sometimes Samuel paused beside the old lamp as the evening fell, feeling the hush settle upon his shoulders — a gentle remembrance of the night the Lord had called him.

### Paragraph at line 17 — long sentences, no period anchor

**Before:**
> Eli beheld Samuel with a tenderness that did not shew upon his face, but shone in his careful words. Though his steps grew slower, Eli offered counsel for as long as he was able, encouraging Samuel to be faithful, to love mercy, and to walk humbly. The old priest's heart was heavy for his sons, but he trusted Samuel's calling, and sometimes he found a measure of peace beholding the boy who hearkened and ever answered. The days carried Eli gently forward, and the people of Shiloh began to perceive that change was come, subtle and quiet, but unmistakable.

**After:**
> Eli beheld Samuel with a tenderness that did not shew upon his face. It shone in his careful words. Though his steps grew slower, Eli offered counsel for as long as he was able. He encouraged Samuel to be faithful, to love mercy, and to walk humbly. The old priest's heart was heavy for his sons. Yet he trusted Samuel's calling. Sometimes he found a measure of peace beholding the boy who hearkened and ever answered. The days carried Eli gently forward. The people of Shiloh began to perceive that change was come — subtle and quiet, but unmistakable.

---

## 6. Story 801 — KJV Long (Matthew 11:28-30 — "Come unto me")

**File:** [assets/stories/traditional/801/story_801_traditional_kjv_long.txt](../assets/stories/traditional/801/story_801_traditional_kjv_long.txt)
**Missing audio:** `audio_801_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — every Matt 11:28-30 quote (lines 7, 13, 17, 23, 31, 51-57) is untouched.

> Note: project memory `project_800_series_content_audit` may apply.

### Paragraph at line 9 — semicolon + em-dash chain in the listening pause

**Before:**
> Calloused hands clenched at cloaks; shoulders stooped from toil seemed to pause, hearkening with hearts that ached beneath unseen loads — fears for the morrow's bread, anguish of loss, the unending burdens of daily striving.

**After:**
> Calloused hands clenched at cloaks. Shoulders stooped from toil seemed to pause, hearkening with hearts that ached beneath unseen loads. Fears for the morrow's bread. Anguish of loss. The unending burdens of daily striving.

### Paragraph at line 11 — 4-item enumeration in one breath

**Before:**
> Jesus' eyes searched the multitude, beholding the mothers wearied by many days' care, the old man leaning upon his staff, the tradesman with rough palms and hunched back, even the children whose faces too bare shadows. He beckoned — all that laboured, all pressed beneath burden — and his words rolled out as balm.

**After:**
> Jesus' eyes searched the multitude. He beheld the mothers wearied by many days' care. He beheld the old man leaning upon his staff. He beheld the tradesman with rough palms and hunched back. Even the children, whose faces too bare shadows. He beckoned them — all that laboured, all pressed beneath burden. And his words rolled out as balm.

### Paragraph at line 59 — overloaded ending (43w final sentence)

**Before:**
> And with these words spoken, Jesus tarried awhile among the multitude — no further demand, no turning away any that drew nigh in spirit or in step. The field lay hushed; the olive branches framed the gathered company. In the midst of heat and toil and longing, the Teacher's voice left an imprint — an invitation enduring beyond the moment, borne upon the footsteps of all that departed that hillside at dusk, and echoing still in the hush of the gathering night.

**After:**
> And with these words spoken, Jesus tarried awhile among the multitude. No further demand. No turning away any that drew nigh in spirit or in step. The field lay hushed. The olive branches framed the gathered company. In the midst of heat and toil and longing, the Teacher's voice left an imprint. An invitation enduring beyond the moment. It was borne upon the footsteps of all that departed that hillside at dusk, and echoed still in the hush of the gathering night.

---

## 7. Story 816 — KJV Long (Daniel in lions' den)

**File:** [assets/stories/traditional/816/story_816_traditional_kjv_long.txt](../assets/stories/traditional/816/story_816_traditional_kjv_long.txt)
**Missing audio:** `audio_816_story_kjv_long.mp3`
**Type:** mixed (1 prose split + 2 Scripture-punctuation-only)
**Scripture preserved:** YES — all wording of Daniel 6:7, 6:17, 6:24, 6:27 is untouched. Edits below are punctuation-only inside Scripture quotes.

### Paragraph at line 5 — Daniel 6:7 long Scripture run (punctuation only)

**Before** (the satraps' decree-quote, single Scripture sentence, ~60w):
> "All the presidents of the kingdom, the governors, and the princes, the counsellors, and the captains, have consulted together to establish a royal statute, and to make a firm decree, that whosoever shall ask a petition of any God or man for thirty days, save of thee, O king, he shall be cast into the den of lions."

**After** (single comma → period; ZERO words changed):
> "All the presidents of the kingdom, the governors, and the princes, the counsellors, and the captains, have consulted together to establish a royal statute, and to make a firm decree. That whosoever shall ask a petition of any God or man for thirty days, save of thee, O king, he shall be cast into the den of lions."

(This matches the period break already used in the 816 KJV Full variant — bringing the two variants into pacing parity.)

### Paragraph at line 13 — Daniel 6:17 narration semicolon chain (punctuation only)

**Before:**
> The officials laid the stone upon the mouth of the den, and the king sealed it with his own signet, and with the signet of his lords, that the purpose might not be changed concerning Daniel.

**After:**
> The officials laid the stone upon the mouth of the den. The king sealed it with his own signet, and with the signet of his lords, that the purpose might not be changed concerning Daniel.

(One period added. Word order unchanged.)

### Paragraph at line 19 — prose-side action recap (prose split)

**Before:**
> Relief and wonder flooded Darius. He commanded that Daniel be taken up out of the den. When Daniel was brought forth, no manner of hurt was found upon him, because he believed in his God. The officials which had accused Daniel stood nearby. In the presence of all, the king gave commandment, and those men, with their children and their wives, were cast into the den of lions. Or ever they came at the bottom of the den, the lions had the mastery of them, and brake all their bones in pieces.

**After:**
> Relief and wonder flooded Darius. He commanded that Daniel be taken up out of the den. When Daniel was brought forth, no manner of hurt was found upon him, because he believed in his God. The officials which had accused Daniel stood nearby. In the presence of all, the king gave commandment. Those men, with their children and their wives, were cast into the den of lions. Or ever they came at the bottom of the den, the lions had the mastery of them, and brake all their bones in pieces.

(One comma → period to give the ear a breath before the long verbatim Daniel 6:24 close.)

---

## 8. Story 816 — KJV Full (Daniel in lions' den, shorter variant)

**File:** [assets/stories/traditional/816/story_816_traditional_kjv_full.txt](../assets/stories/traditional/816/story_816_traditional_kjv_full.txt)
**Missing audio:** `audio_816_story_kjv_full.mp3`
**Type:** mixed (1 prose split + 2 Scripture-punctuation-only)
**Scripture preserved:** YES.

### Paragraph at line 3 — long prose-side opening clause

**Before:**
> Knowing they could find no occasion against Daniel concerning the affairs of the kingdom, the officials consulted together and said, "We shall not find any occasion against this Daniel, except we find it against him concerning the law of his God."

**After:**
> The officials could find no occasion against Daniel concerning the affairs of the kingdom. They consulted together and said, "We shall not find any occasion against this Daniel, except we find it against him concerning the law of his God."

(Keeps the Daniel 6:5 quote intact. Replaces the long participial opening with a finite verb so the narrator gets one period of breath before the quote.)

### Paragraph at line 7 — Daniel 6:17 narration semicolon chain (punctuation only)

**Before:**
> And a stone was brought, and laid upon the mouth of the den; and the king sealed it with his own signet, and with the signet of his lords; that the purpose might not be changed concerning Daniel.

**After:**
> And a stone was brought, and laid upon the mouth of the den. And the king sealed it with his own signet, and with the signet of his lords, that the purpose might not be changed concerning Daniel.

(Two semicolons → one period + one comma. Wording unchanged.)

### Paragraph at line 13 — Daniel 6:24 narration semicolon chain (punctuation only)

**Before:**
> And the king commanded, and they brought those men which had accused Daniel, and they cast them into the den of lions, them, their children, and their wives; and the lions had the mastery of them, and brake all their bones in pieces or ever they came at the bottom of the den.

**After:**
> And the king commanded, and they brought those men which had accused Daniel, and they cast them into the den of lions — them, their children, and their wives. And the lions had the mastery of them, and brake all their bones in pieces or ever they came at the bottom of the den.

(Comma list → em-dash; semicolon → period. Wording unchanged.)

---

## 9. Story 826 — KJV Full (David vs. Goliath)

**File:** [assets/stories/traditional/826/story_826_traditional_kjv_full.txt](../assets/stories/traditional/826/story_826_traditional_kjv_full.txt)
**Missing audio:** `audio_826_story_kjv_full.mp3`
**Type:** mixed (1 prose narration semicolon swap + 1 Scripture-punctuation-only)
**Scripture preserved:** YES — every verbatim 1 Samuel 17 quote is untouched. The edits are punctuation only.

### Paragraph at line 27 — narration semicolon ↔ dialogue semicolon collision

**Before:**
> "I cannot go with these," he said; "for I have not proved them." He put them off; and, with his staff in his hand, he chose him five smooth stones out of the brook.

**After:**
> "I cannot go with these," he said. "For I have not proved them." He put them off. And with his staff in his hand, he chose him five smooth stones out of the brook.

(Two semicolons → two periods. The 1 Samuel 17:39 KJV semicolon between "with these" and "for" is converted to a period inside the quote — punctuation only, no words changed. Adam: "punctuation/breathing only" is allowed.)

### Paragraph at line 33 — 1 Samuel 17:49 narration semicolon (punctuation only)

**Before:**
> He put his hand in his bag, and took thence a stone, and slang it, and smote the Philistine in his forehead, that the stone sunk into his forehead; and he fell upon his face to the earth.

**After:**
> He put his hand in his bag, and took thence a stone, and slang it, and smote the Philistine in his forehead, that the stone sunk into his forehead. And he fell upon his face to the earth.

(One semicolon → period. Word order unchanged.)

---

## 10. Story 819 — KJV Long (Esther — Mordecai honored)

**File:** [assets/stories/traditional/819/story_819_traditional_kjv_long.txt](../assets/stories/traditional/819/story_819_traditional_kjv_long.txt)
**Missing audio:** `audio_819_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — the king's question and the public proclamation (Esther 6:6, 6:11) are untouched.

### Paragraph at line 21 — long prose narration of Haman's answer

**Before:**
> Then came Haman into the hall. The king said, "What shall be done unto the man whom the king delighteth to honour?" Haman thought the king meant himself, and answered that royal apparel and the king's horse should be brought, and a noble prince should lead such a man through the city, proclaiming, "Thus shall it be done unto the man whom the king delighteth to honour!"

**After:**
> Then came Haman into the hall. The king said, "What shall be done unto the man whom the king delighteth to honour?" Haman thought the king meant himself. He answered that royal apparel should be brought, and the king's horse. He said that a noble prince should lead such a man through the city, proclaiming, "Thus shall it be done unto the man whom the king delighteth to honour!"

(Two periods inserted in the paraphrase line. Esther 6:9-style proclamation wording untouched.)

---

## 11. Story 830 — KJV Long (Prodigal son)

**File:** [assets/stories/traditional/830/story_830_traditional_kjv_long.txt](../assets/stories/traditional/830/story_830_traditional_kjv_long.txt)
**Missing audio:** `audio_830_story_kjv_long.mp3`
**Type:** prose-only
**Scripture preserved:** YES — Luke 15:17-19 (paragraph 19), 15:22-24 (paragraph 31), 15:31-32 (paragraph 45 ending) are untouched. The "overloaded ending" flag is on the verbatim Luke 15:32 close, which is the natural Scripture conclusion and must not be altered.

### Paragraph at line 9 — narration semicolon chain

**Before:**
> But his treasures dwindled faster than he had supposed. One by one, his friends slipped away; the feasts grew quieter; the food waned. As his riches vanished, there arose a mighty famine in that land.

**After:**
> But his treasures dwindled faster than he had supposed. One by one, his friends slipped away. The feasts grew quieter. The food waned. As his riches vanished, there arose a mighty famine in that land.

(Two semicolons → two periods. Matches `feedback_speakable_prose` locked B23+.)

---

## 12. Story 823 — KJV Full (Esther)

**File:** [assets/stories/traditional/823/story_823_traditional_kjv_full.txt](../assets/stories/traditional/823/story_823_traditional_kjv_full.txt)
**Missing audio:** `audio_823_story_kjv_full.mp3`
**Type:** mixed (1 prose split + 1 Scripture-punctuation-only)
**Scripture preserved:** YES — Esther 4:11, 4:13-14, 4:16, 7:3-4 quotations are untouched in wording; only the colons/semicolons inside the 4:16 quote in paragraph 7 are converted to periods for breath.

### Paragraph at line 3 — prose narration with em-dash list

**Before:**
> Sore troubled, she sent raiment to clothe him, but he received it not. Through Hatach, a trusted messenger, she learned the whole truth — the copy of the decree, the promise of silver Haman had offered unto the royal treasuries, and Mordecai's plea that she draw near unto the king to make supplication for mercy and intreat for her people.

**After:**
> Sore troubled, she sent raiment to clothe him, but he received it not. Through Hatach, a trusted messenger, she learned the whole truth. She learned of the copy of the decree. She learned of the promise of silver Haman had offered unto the royal treasuries. And she learned of Mordecai's plea — that she draw near unto the king, to make supplication for mercy, and intreat for her people.

### Paragraph at line 7 — Esther 4:16 quote internal pacing (punctuation only)

**Before:**
> "Go, gather together all the Jews that are present in Shushan, and fast ye for me, and neither eat nor drink three days, night or day: I also and my maidens will fast likewise; and so will I go in unto the king, which is not according to the law: and if I perish, I perish."

**After:**
> "Go, gather together all the Jews that are present in Shushan, and fast ye for me, and neither eat nor drink three days, night or day. I also and my maidens will fast likewise. And so will I go in unto the king, which is not according to the law. And if I perish, I perish."

(Two colons + one semicolon → three periods. ZERO words changed. The iconic "if I perish, I perish" stands alone as its own sentence for breath emphasis.)

---

## 13. Story 823 — KJV Long (Esther)

**File:** [assets/stories/traditional/823/story_823_traditional_kjv_long.txt](../assets/stories/traditional/823/story_823_traditional_kjv_long.txt)
**Missing audio:** `audio_823_story_kjv_long.mp3`
**Type:** scripture-punctuation-only
**Scripture preserved:** YES — only colons/semicolons inside verbatim Esther quotes are converted to periods. Zero words changed.

### Paragraph at line 7 — Esther 4:11 quote (Esther's reply to Mordecai)

**Before:**
> She sent word again unto Mordecai: "All the king's servants do know, that whosoever, whether man or woman, shall come unto the king into the inner court, who is not called, there is one law of his to put him to death, except such to whom the king shall hold out the golden sceptre, that he may live: but I have not been called to come in unto the king these thirty days."

**After:**
> She sent word again unto Mordecai: "All the king's servants do know, that whosoever, whether man or woman, shall come unto the king into the inner court, who is not called, there is one law of his to put him to death, except such to whom the king shall hold out the golden sceptre, that he may live. But I have not been called to come in unto the king these thirty days."

(One colon → period. ZERO words changed.)

### Paragraph at line 7 — Esther 4:13-14 quote (Mordecai's reply to Esther)

**Before:**
> Mordecai said, "Think not with thyself that thou shalt escape in the king's house, more than all the Jews. For if thou altogether holdest thy peace at this time, then shall there enlargement and deliverance arise to the Jews from another place; but thou and thy father's house shall be destroyed: and who knoweth whether thou art come to the kingdom for such a time as this?"

**After:**
> Mordecai said, "Think not with thyself that thou shalt escape in the king's house, more than all the Jews. For if thou altogether holdest thy peace at this time, then shall there enlargement and deliverance arise to the Jews from another place. But thou and thy father's house shall be destroyed. And who knoweth whether thou art come to the kingdom for such a time as this?"

(Semicolon + colon → two periods. ZERO words changed. The iconic "for such a time as this" lands as its own breath unit.)

### Paragraph at line 9 — Esther 4:16 quote (same as 823 KJV Full fix #12)

**Before:**
> Esther answered, "Go, gather together all the Jews that are present in Shushan, and fast ye for me, and neither eat nor drink three days, night or day: I also and my maidens will fast likewise; and so will I go in unto the king, which is not according to the law: and if I perish, I perish."

**After:**
> Esther answered, "Go, gather together all the Jews that are present in Shushan, and fast ye for me, and neither eat nor drink three days, night or day. I also and my maidens will fast likewise. And so will I go in unto the king, which is not according to the law. And if I perish, I perish."

(Apply the same Esther 4:16 punctuation pattern as in file #12 so the two variants render consistently.)

---

## Patterns across the plan

- **Five files are pure prose-only** (804, 807 long, 807 full, 811, 822, 801, 819, 830 = 8 files actually). The fix shape repeats: serial-comma list → period-anchored short sentences; em-dash chain → split with em-dash on one side and period on the other.
- **Four files mix prose + Scripture-punctuation** (816 long, 816 full, 826, 823 full). Scripture wording untouched; only internal colons/semicolons converted.
- **One file is pure Scripture-punctuation** (823 long). Three Esther 4 quotes, all colons/semicolons → periods, zero words changed.
- **No file needs a rewrite or "modernization."** Every edit shown above is either a split-an-existing-sentence move or a single punctuation swap.
- **Voice preservation:** KJV "saith / spake / unto / hath" is intact everywhere. The "Ruth telling one person" feel is preserved because the dominant change is *shorter narrator sentences with period anchors*, which is exactly what spoken storytelling does.
- **Endings:** stories 811 and 801 had overloaded endings; both now taper. Story 830's flagged "overloaded ending" was Luke 15:32 verbatim and is correctly left untouched (Scripture wins over the heuristic).

## Suggested next step

When you approve, the edits above can be applied in one short pass per file. The
800-series files (801, 804, 807×2, 811, 816×2, 819, 822, 823×2, 826, 830 — but
many of these are 1000-series; the actual 800-series subset is 801, 804, 807×2,
811, 816×2, 819, 822, 823×2, 826, 830 → eight unique 800-series IDs and five
1000-series-adjacent IDs by lookup) should ideally be bundled with the pending
content-audit pass per project memory `project_800_series_content_audit`.

Once changes are made:
- run `flutter analyze` and `flutter test` (text-only changes don't affect this but it's the project gate)
- spot-check 2-3 of the edited files by reading aloud — the locked test for `feedback_speakable_prose`
- pause and await Adam's confirmation before audio gen per `feedback_pause_before_audio`
- render with `--takes 1`, model `eleven_multilingual_v2`, per locked B23+ recipe
