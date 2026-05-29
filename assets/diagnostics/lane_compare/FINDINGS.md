# Lane Diagnostic Findings — Phase 2 Baseline

**Date:** 2026-05-26
**Backend:** Claude Opus 4.7 (active production backend, matches B26–B28)
**Length tier:** short (300–500 words)
**Word counts:** all 10 outputs landed 408–455 words — well within range
**Prompts:** post-Phase-1 consolidation (`story_prompts.py SYSTEM_PROMPTS_STORY_TRADITIONAL`), no Phase 3 / 4 / 5 changes

## Headline

The consolidated prompts ALREADY produce visibly distinct KJV/WEB lanes across all 5 literary registers. Phase 3's job is not to *create* differentiation — it's to (a) sharpen the conceptual identity ("sacred proclamation" / "sacred witnessing"), (b) stop one specific KJV drift pattern, and (c) defer rules the evidence doesn't justify.

## Per-anchor observations

### Psalm 23 (lyric)
- **KJV:** Strong narrative retelling. Verb-subject inversion ("Then came the voice…"). Hebraic parallelism ("Where one had wandered, he went after it and brought it again"). Archaic markers limited but present: "spake unto", "by and by", "unto a table of pasture". Soft endings, audio-friendly. Does NOT quote Psalm text — fully narrated.
- **WEB:** Witnessing-style. Names David explicitly. QUOTES Psalm verses as David sings them — clever scripture handling, modern syntax throughout. Visual immediacy ("his staff tapping the stones").
- **Distinction:** STRONG. Two distinct approaches to the same lyric.

### Ezra 3:10–13 (procedural narrative)
- **KJV:** Ceremonial historical voice. "Then sounded the first blast", "Voice was added to voice", "Labourers set down their tools". Some near-verbatim KJV: "for the people shouted with a loud shout, and the noise was heard afar off". Hebraic parallelism in mood and rhythm.
- **WEB:** Cinematic reportage. "The two sounds met in the courtyard and became one — the weeping of the old and the shouting of the young." Slightly literary in places ("became one") but stays grounded. Travelers-on-the-roads coda is a nice external camera pull-back.
- **Distinction:** STRONG.

### Isaiah 6:1–8 (apocalyptic vision)
- **KJV:** Powerful archaic cadence. "with twain he covered his face, and with twain he covered his feet, and with twain he did fly" — verbatim KJV (Isaiah 6:2). "Here am I. Send me." — verbatim. Strong Hebraic anaphora.
- **WEB:** Excellent witnessing. "The ceiling seemed to lift away. Above him rose a throne, high and lifted up." Modern syntax, lifted register. Dialogue cleanly rendered with WEB's "Lord of Armies".
- **Distinction:** STRONG, **but KJV drifts toward reproduction** (the "with twain" line is essentially KJV text, not a retelling).

### Mark 4:35–41 (gospel narrative)
- **KJV:** **WORST OFFENDER for reproduction drift.** Multiple verbatim KJV phrases: "Let us pass over unto the other side", "took him even as he was into the ship", "the hinder part of the ship, asleep upon a pillow", "carest thou not that we perish?", "Peace, be still", "What manner of man is this, that even the wind and the sea obey him?", "Why are ye so fearful?" This is paraphrase-with-KJV-quotes rather than KJV-style retelling.
- **WEB:** Excellent witnessing register. Physical concreteness ("Water rose around their ankles, then their shins. The wooden hull groaned. The sail snapped and pulled."). Modern syntax, no scripture-paraphrase reliance.
- **Distinction:** STRONG, but KJV violates `_KJV_AUDIO_RULES` rule #1.

### Matthew 5:3–12 (patterned list / Beatitudes)
- **KJV:** Beautiful narrative framing around the Beatitudes themselves. "Then he stretched forth his words unto them as a man speaketh unto his own." Beatitudes verbatim from KJV (defensible — they ARE the anchor, hard to retell a numbered list).
- **WEB:** Beatitudes verbatim from WEB. Crowd-detail framing ("Fishermen with salt still on their hands, mothers carrying small children"). Modern narration around them.
- **Distinction:** STRONG.

## Cross-anchor patterns

### What's working

1. **Lane behavior is consistent across all 5 genres.** Even procedural narrative (Ezra) produces distinct KJV vs WEB voices. No collapse on any register.
2. **WEB does NOT drift to casual or essay register.** Stays reverent and modern. None of the "friend over coffee" failure mode is appearing.
3. **WEB consistently delivers witnessing-style:** visual immediacy, present-tense physicality.
4. **KJV consistently delivers parallelism + verb-subject inversion + Hebraic rhythm.**
5. **Word counts hit tightly** (408–455 for a 300–500 target). Length discipline is solid.
6. **Cadence variety holds.** Short declaratives mixed with longer flowing sentences. No drone.
7. **No contractions in either lane.** The deferred-numeric `_NO_CONTRACTIONS_` rule from the plan would never have fired.
8. **No "and"-chain overflow.** Both lanes use polysyndeton naturally but vary. The deferred "2-and cap" was correctly deferred.

### What's NOT working

1. **KJV-reproduction drift** (the only major failure mode observed). Familiar passages (Mark 4, Isaiah 6, Beatitudes) trigger near-verbatim KJV text rather than KJV-style retelling. `_KJV_AUDIO_RULES` rule #1 exists but is too weak. Phase 3 must STRENGTHEN anti-reproduction.
2. **Archaic markers are "borrowed not freshly applied."** When KJV does use thou/-eth/spake/unto, it tends to be in lines lifted from the source text. The KJV-style register doesn't feel *generated* — it feels *quoted*. Phase 3 should encourage fresh archaic-register prose, not just retention of source phrasing.
3. **WEB has no explicit positive aesthetic identity in the prompt.** It performs well because the model fills the gap with reasonable defaults. A "sacred witnessing" anchor would lock that in and prevent drift on harder passages.
4. **KJV's narrator stance is implicitly "historian writing in archaic English" rather than "oral-tradition voice proclaiming a sacred event."** Phase 3's "sacred proclamation" framing should clarify the voice and may help with anti-reproduction by changing the *purpose* of the voice (proclaiming, not reproducing).

## Phase 3 priorities (informed by evidence)

1. **STRENGTHEN anti-reproduction in KJV lane.** Promote `_KJV_AUDIO_RULES` rule #1 from a single bullet into a top-line constraint with stronger language and a concrete example contrast.
2. **ADD positive WEB identity** ("sacred witnessing" block). Visual immediacy + breath-friendly audio cadence + ban on literary flourish + ban on essay register.
3. **REFRAME KJV identity** from "elevated/reverent" → "sacred proclamation" (oral tradition voice, ceremonial weight). Goal: change *what kind of voice* the lane is, not just adjectives.
4. **DEFER numeric rules** that the diagnostic shows aren't needed:
   - No "max 2 ands per sentence" — natural variation is already happening.
   - No "no contractions" rule — neither lane uses them.
   - No "verb-subject inversion required" — happens naturally where appropriate.
5. **KEEP** Hebraic parallelism encouragement (clear positive signal in KJV outputs).
6. **DO NOT** add explicit "thou/thee" mandates yet. The current outputs lack them mostly, but the cadence is right. A mandate would risk pastiche. Better: let Phase 4 (scripture exemplar) anchor the register, and re-measure.

## Phase 1 verification (passed via this diagnostic)

10 stories generated via the consolidated module against the active Claude backend, all clean (no meta-text, no compliance violations, all in word range). Phase 1 consolidation confirmed working end-to-end.

---

## Phase 3 verification (after structural lane rewrites)

After adding `_CLASSIC_LANE_STRUCTURE` (sacred proclamation) and `_MODERN_LANE_STRUCTURE` (sacred witnessing) blocks, the diagnostic was re-run. Outputs archived at `_baseline_phase3/`.

**Improvements observed:**

- **Isaiah 6 KJV** went from a near-verbatim KJV reproduction ("with twain he covered his face, and with twain he covered his feet") to a NEW formulation that preserves Hebraic parallelism ("with two they shielded their faces, with two they covered their feet, and with two they held themselves aloft"). Anti-reproduction discipline working.
- **Mark 4 KJV** retained iconic KJV phrasings ("carest thou not", "What manner of man is this") but added significant fresh KJV-register prose around them ("Soft was the wind at the first", "Rain drave sideways across the deck", "as storms upon that sea are wont to fall"). Net improvement.
- **Psalm 23 KJV** picked up more archaic-register prose ("He sat him down, and he brake bread", "stayed his steps", "spake unto them in a low voice", "the shepherd was wont to take his meal"). The sacred-proclamation framing landed.
- **Matthew 5 KJV** added interstitial narration between Beatitudes ("Jesus spake yet further unto them", "his words grew weightier still") — the patterned-list format wasn't broken, just contextualized.
- **WEB lanes** remained clean (no contractions, no archaic bleed, no literary flourish) and gained explicit witnessing-style visual immediacy across all 5 anchors.

**Word count discipline:** all 10 outputs landed 413–437 (KJV) and 408–431 (WEB) — same tight calibration as Phase 2.

## Phase 4 verification (after scripture excerpt anchors)

After adding `_KJV_VOICE_EXEMPLAR` and `_WEB_VOICE_EXEMPLAR` (Luke 2:8–14 in each translation) prepended after `_KJV_AUDIO_RULES`. Outputs archived at `_baseline_phase3/` were swapped for the Phase 4 set in the live directory.

**Effect:**

- **Mark 4 KJV** improved further: "as the winds of that country are wont to come, sweeping from the heights and falling upon the waters" — fresh KJV-cadence prose without verbatim copying.
- KJV outputs across all 5 anchors became *more confident* in their register — fewer hedging modern constructions slipping in.
- WEB outputs remained tight; no observable drift toward exemplar-copying. The "do NOT copy these words" instruction in the exemplar block did its job.
- No regression vs Phase 3 baseline on any anchor.

**Marginal value note:** Phase 3 alone produced most of the differentiation gain. Phase 4 incrementally tightened KJV cadence but did not transform output quality. If token budget ever becomes a concern, the exemplars are the first thing to consider removing.

## Phase 5 calibration (corpus-wide validator baseline)

Ran `lane_validator_baseline.py` against all 1,052 adult Traditional story files. Full report at [assets/diagnostics/lane_validator_baseline.md](../lane_validator_baseline.md).

**Headline:**

- 322 of 1,052 files (30.6%) have at least one WARN-level violation
- **WEB_CONTRACTION: 430** — many legacy WEB stories use "didn't"/"wouldn't"-style contractions. The Phase 3 _MODERN_LANE_STRUCTURE "no contractions" rule should prevent this drift going forward; existing stories are out of scope.
- **WEB_ARCHAIC_BLEED: 115** — actionable signal of genuine drift in legacy WEB stories.
- **KJV_TOO_FEW_ARCHAIC_MARKERS: 36** — well within tolerance; threshold (≥3) is well-calibrated for KJV after the false-positive purge (dropped `\w+est`, `\w+eth`, "behold").

**Recent batches (B27–B28, story IDs 1510–1529)** show the WEB drift accelerating before Phase 3 (1510–1519: 36 WEB violations / 21 files; 1520–1529: 59 violations / 13 files). The structural prompts landing now should reverse that trajectory; next batch run will be the test.

**Promotion decision:** validator stays WARN-only. Revisit after 3–5 batches generated under the new prompts, using `lane_validator_log.jsonl` as the empirical promotion-or-tune signal.

### Smoke test: validator on Phase 4 diagnostic outputs

Ran `validate_lane_identity()` over the 10 Phase 4 fresh outputs in `lane_compare/`:

- **WEB: 5/5 CLEAN.** No contractions, no archaic bleed. The Modern lane rules hold under the new prompts.
- **KJV: 3/5 CLEAN.** Three fail on `KJV_TOO_FEW_ARCHAIC_MARKERS` despite reading as strongly Classic-register (Hebraic parallelism, verb-subject inversion, ceremonial cadence). Marker counts: Psalm 23 = 2, Matthew 5 = 2, Ezra 3 = 1.

This is consistent with the deliberate Phase 3 decision NOT to mandate thou/thee/-eth and to let KJV register emerge from cadence. The validator is stricter than the prompts — useful as a *signal* that lexical markers are sparse, but the threshold (≥3) may need lowering once batch data accumulates. Holding at WARN-only confirms this was the right call.

### Calibration data point: B30 1532 KJV near-miss (2026-05-26)

User flagged that 1532 (Joshua 6, REVEREND_MICHAEL voice) sounded the same in KJV and WEB audio. Marker audit confirmed:

- 1532 KJV full: 3 marker hits / 3 unique patterns at **0.3/100w density** — outlier vs B30's other KJVs at 2.2–3.7/100w
- 1532 KJV short: 6 marker hits / 4 unique — borderline (also lower than B30 median)
- Validator status: **CLEAN** (passed because exactly 3 unique patterns hits the ≥3 floor)

What the validator missed: the KJV rewrite drifted toward minimal word-swap rather than re-voicing into sacred-proclamation register. Words like "smote", "ceased not", "thereof", "hath given", "lifted up his voice" — clearly KJV-flavored but not in the marker-pattern list — were absent in the original generation. Regen of just KJV short + full restored these (commit 542e5fe amended into B30).

**What this tells us for the eventual promotion-or-tune decision:**

1. **The ≥3 unique-pattern threshold is too lenient on its own.** A story with exactly 3 unique markers (one of each: thou/unto/saith, say) can still be a weak rewrite if those are the only KJV moves.
2. **Marker density (hits / 100w) is a better signal than unique-pattern count.** 1532 KJV full at 0.3/100w stuck out against the batch's 2.2–3.7/100w range. A density floor (e.g. ≥1.5/100w) would have caught this.
3. **But density alone misses the structural axis.** "Smote" / "thereof" / "ceased not" / "hath given" — pure-Anglo archaic verb choices and constructions without thou/-eth — these are the cadence moves that actually create the sacred-proclamation feel and aren't in the marker pattern list at all.
4. **The right next-step before promotion** is to expand `KJV_ARCHAIC_MARKERS` to include those Anglo-archaic constructions (smote, brake, bare, drave, ceased, wrought, thereof, therein, herein, behold-not-already, etc.), THEN re-baseline density across the existing corpus, THEN decide on density-vs-count thresholds. That's bigger than a tuning pass — it's a marker-list expansion.

**Holding the original promotion timeline** (3–5 batches of WARN data before any threshold change). 1532 is logged as the first concrete near-miss; future similar misses go here.
