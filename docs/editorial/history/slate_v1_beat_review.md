# Slate v1 — Journey Transition Beat Review

**Status: DRAFT — FOR ADAM'S EDITORIAL REVIEW**
2026-07-04 · Assembled from Draft + Verify phase output

- **Register:** FLOOR only. Adult tail locked byte-identical to shipped daniel_arc: `…or, tell me what's on your heart today.` Kid tail locked: `…or, what's on your mind?` All glimpses are generic floor glimpses — no enriched glimpses anywhere in this slate.
- **Render gate:** NOTHING renders until BOTH (a) the Daniel smoke test passes, and (b) Adam explicitly approves the texts below. This document is that approval surface — mark up wording directly.
- **Budget when rendered:** ~22 clips ≈ ~5.5K ElevenLabs credits (eleven_v3, per PAL-voice-audio rule).
- **Scope:** This document reviews BEAT TEXT only. The journey JSON files (story lists, editorial notes, status fields) are written separately; JSON-level fixes flagged below land in that lane.
- **Slate:** 5 journeys (3 adult, 2 kid) · 17 offer beats · verifier verdicts: 4 PASS, 1 FAIL (ruth_arc — all four beat texts clean; the fail is two factual errors in the journey JSON's editorial notes, fix-before-landing).
- **Verifier corrections to beat text: ZERO.** All 17 beats passed as drafted (`was_corrected: false` across the slate). Notes below are the judgment calls the verifiers cleared — surfaced so you can overrule.

---

## 1. joseph_arc — Adult · 5 stories · 4 beats · Verifier: PASS

**Arc:** 1037 Joseph Sold by His Brothers → 1178 But the Cupbearer Forgot Him → 831 Joseph Interprets Pharaoh's Dreams → 1003 Tears That Shattered the Silence → 1146 Then Joseph Wept *(final — no beat, per strict-newest rule)*

### joseph_arc_offer_0 — after 1037 → offers 1178 · 169 chars
> Last time, we watched Joseph's brothers sell him for twenty pieces of silver… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- Judgment call: look-back centers the **brothers** grammatically (Joseph present as "him"). Precedented by shipped daniel_arc_offer_1 ("Daniel's friends").
- Follows the corpus telling (brothers sell him) over WEB's Midianite detail — per the grounded-in-this-corpus rule. "Twenty pieces of silver" is WEB+KJV verbatim; NIV/ESV signature is "twenty shekels" — translation-safe.

### joseph_arc_offer_1 — after 1178 → offers 831 · 171 chars
> Last time, we waited with Joseph in prison, forgotten by the man he had helped… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- "Forgotten by the man he had helped" is a paraphrase of 1178's closing line, not a scripture quote; verified against no banned-translation signature.

### joseph_arc_offer_2 — after 831 → offers 1003 · 176 chars
> Last time, we walked with Joseph from the cold stone of prison into Pharaoh's court… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- "Cold stone into Pharaoh's court" is 831's own pivot image and the scene happens INSIDE 831 — next-chapter integrity verified (not borrowed from 1178).

### joseph_arc_offer_3 — after 1003 → offers 1146 · 180 chars
> Last time, we stood in the emptied hall as Joseph wept and told his brothers who he was… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- Grounded in 1003's opening ("No one else remained in the hall", "I am Joseph"). 1146 (final) correctly gets no beat.

---

## 2. ruth_arc — Adult · 5 stories · 4 beats · Verifier: FAIL (journey-JSON notes only — beat texts clean)

**Arc:** 828 Ruth and Naomi → 1529 Ruth in the Field → 1150 At the Threshing Floor → 1418 Boaz at the Gate → 1424 A Son Is Born to Naomi *(final — no beat)*

**Why FAIL:** two factual coverage claims in the journey JSON's editorialNotes are wrong (see Open Items). The verifier's own words: "Once the two editorial-note coverage claims are corrected, this draft is sound to land." All four beats below verified clean.

### ruth_arc_offer_0 — after 828 → offers 1529 · 179 chars
> Last time, we stood on the road with Ruth as she clung to Naomi, refusing to turn back… There's more to her story if you'd like to hear it… or, tell me what's on your heart today.

- **Worth your eye — "clung":** NOT WEB Ruth 1:14 (WEB reads "Ruth stayed with her"); NIV/ESV/NRSV do render "clung to her." Cleared because the 828 corpus telling itself says "Ruth clung to Naomi tightly," look-back rule mandates corpus grounding, it's a single common verb (not a signature phrase), and the registry fingerprint scan is clean. Overrule if you want zero NIV-adjacent vocabulary.
- "Her story" after naming both women resolves to Ruth (clause subject); precedented by shipped daniel_arc_offer_1's pronoun form.

### ruth_arc_offer_1 — after 1529 → offers 1150 · 184 chars
> Last time, we watched Ruth gather barley behind the reapers, the day Boaz first noticed her… There's more to her story if you'd like to hear it… or, tell me what's on your heart today.

- "The day Boaz first noticed her" happens IN 1529 — look-back, not a forward glimpse; the threshing floor (1150) is untouched. "Reapers"/"glean" is WEB vocabulary.

### ruth_arc_offer_2 — after 1150 → offers 1418 · 188 chars
> Last time, we waited at the threshing floor as Ruth came softly through the dark to Boaz's feet… There's more to her story if you'd like to hear it… or, tell me what's on your heart today.

- "Came softly" is verbatim WEB Ruth 3:7 — safest possible rendering. Gate scene (1418) untouched.

### ruth_arc_offer_3 — after 1418 → offers 1424 · 186 chars
> Last time, we sat at the gate of Bethlehem as Boaz stood before the elders and spoke for Ruth… There's more to her story if you'd like to hear it… or, tell me what's on your heart today.

- 1418's primaryCharacterId is **boaz** (manifest-confirmed); beat keeps Ruth the relational center per JOURNEY_TRANSITION_VOICE.md's different-figures note. Obed's birth (1424) untouched.

---

## 3. elijah_arc — Adult · 5 stories · 4 beats · Verifier: PASS

**Arc:** 1039 Elijah and the Widow of Zarephath → 1065 Elijah on Mount Carmel → 1144 Under the Juniper Tree → 825 Elijah at Horeb → 1138 The Chariot of Fire *(final — no beat)*

### elijah_arc_offer_0 — after 1039 → offers 1065 · 201 chars
> Last time, we stood with Elijah at the gate of Zarephath, where a widow's last handful of meal became enough… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- Longest beat in the slate — inside the 150–220 band, but at the top. "Handful of meal" is WEB verbatim (NIV: "flour"); "became enough" mirrors 1039's own close ("Not more than enough. But enough.").

### elijah_arc_offer_1 — after 1065 → offers 1144 · 161 chars
> Last time, we watched fire fall on Elijah's drenched altar at Carmel… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- "Drenched altar" is 1065's signature scene (twelve jars, trench filled); paste-test unique.

### elijah_arc_offer_2 — after 1144 → offers 825 · 199 chars
> Last time, we sat with Elijah under the juniper tree, where an angel woke him to a cake baked on the coals… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- "Cake baked on the coals" is WEB/KJV wording; NIV's "bread baked over hot coals" correctly avoided.

### elijah_arc_offer_3 — after 825 → offers 1138 · 185 chars
> Last time, we waited with Elijah in the cave on Horeb, where God came in a still small voice… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.

- "Still small voice" is KJV/WEB/ASV. The beat correctly avoids NIV's "gentle whisper" — **but that phrase IS present in all five shipped 825 story variants** (see Open Items, compliance flag). 1138 (final) correctly gets no beat.

---

## 4. kid_moses_arc — Kid · 3 stories · 2 beats · Verifier: PASS

**Arc:** 1810 Baby Moses → 1811 The Burning Bush → 1813 Crossing the Red Sea *(final — no beat; 3 stories → beats 0..1 correct)*

### kid_moses_arc_offer_0 — after 1810 → offers 1811 · 157 chars
> Last time, we watched a baby float snug in his little basket among the reeds… There's more to Moses' story if you'd like to hear it… or, what's on your mind?

- Naming shape (unnamed baby in look-back → "Moses'" in glimpse) exactly mirrors shipped kid_david_arc_offer_0's shepherd-boy → David reveal.
- **Render-time ear check:** if eleven_v3 reads "Moses'" as bare "Moses story" rather than "Moses-iz," switch to "Moses's" (PAL prose, not scripture — free change).

### kid_moses_arc_offer_1 — after 1811 → offers 1813 · 163 chars
> Last time, we stood with Moses at the bush that burned and burned but never burned up… There's more to his story if you'd like to hear it… or, what's on your mind?

- Verifier adversarially considered "Moses' story" for the glimpse and deliberately kept "his story" — matches shipped daniel_arc pronoun precedent and avoids doubling "Moses" in one breath.
- "Never burned up" resembles NIV Ex 3:2 ("did not burn up") but directly quotes the shipped kid telling, which the look-back rule requires; plain kid English, cleared. WEB comparison done ("was not consumed").

---

## 5. kid_joseph_arc — Kid · 4 stories · 3 beats · Verifier: PASS

**Arc:** 1844 Joseph's Colorful Coat → 1906 Joseph Far From Home → 1860 Joseph and the King's Dreams → 1819 Joseph Forgives His Brothers *(final — no beat)*

### kid_joseph_arc_offer_0 — after 1844 → offers 1906 · 168 chars
> Last time, we watched Joseph wear his beautiful coat, woven in every color you can imagine… There's more to his story if you'd like to hear it… or, what's on your mind?

- "Beautiful coat, woven in every color you can imagine" is 1844's own line. Fingerprint clean: WEB "tunic of many colors," KJV "coat of many colours"; NIV "ornate robe" / NLT "beautiful robe" signatures NOT borrowed.

### kid_joseph_arc_offer_1 — after 1906 → offers 1860 · 155 chars
> Last time, we waited with Joseph in the dark, and God stayed right beside him… There's more to his story if you'd like to hear it… or, what's on your mind?

- The God-beside-him clause is deliberate, not compressed theology: it's 1906's explicit spine and the kid not-alone thread (feedback_kid_god_with_not_cause). Recalling the dark WITHOUT the presence would hand a child the fear minus the comfort.

### kid_joseph_arc_offer_2 — after 1860 → offers 1819 · 168 chars
> Last time, we stood with Joseph before the king, when God showed him what the dreams meant… There's more to his story if you'd like to hear it… or, what's on your mind?

- Naming the dream interpretation is fine in a LOOK-BACK — spoiler rules govern the glimpse, and the child already heard 1860.

---

## Name Registry Needs

Entries that must exist in `assets/pal/memory/display_name_registry.json` (plus rendered name clips) before the affected journey's status flips to `ready`:

| Journey | nameRegistryKey | Registry state (verified) | Action |
|---|---|---|---|
| joseph_arc | `joseph_sold_by_brothers` | Matches 1037's real manifest bibleStoryKey; **ABSENT from registry** | Add entry + render name clip before ready |
| ruth_arc | `ruth_and_naomi` | Matches 828's bibleStoryKey; **ABSENT from registry** | Add entry + render name clip before ready |
| elijah_arc | `null` | No entry needed — monolithic-offer precedent (kid_david_arc / learning_to_wait) | None |
| kid_moses_arc | not flagged | Presumed null per kid_david precedent | Confirm null in journey JSON |
| kid_joseph_arc | not flagged | Presumed null per kid_david precedent | Confirm null in journey JSON |

**Observation (confirm intentional):** the slate mixes keyed adult arcs (joseph, ruth) with a null adult arc (elijah). Registry check confirmed 5 existing entries, none Elijah. Both drafts are internally consistent, but decide whether the adult lane should converge on one pattern before ready flips.

---

## Open Items

### Cross-slate
- [ ] **Render gate (a):** Daniel smoke test must pass first. **Render gate (b):** Adam's explicit sign-off on the 17 texts above.
- [ ] **800-series full-length audit — 831 and 825:** both 800-series stories in this slate need their full-length variants cross-checked against the 800-series content-audit per-variant decision queue before promotion (831 explicitly flagged by the joseph verifier; apply the same check to 825).
- [ ] **825 compliance flag (pre-existing corpus issue, outside these beats):** all five shipped 825 variants (WEB/KJV × short/full/long) contain "a gentle whisper" — NIV's signature 1 Kings 19:12 rendering — alongside the compliant "still small voice." The automated fingerprint scan covers verse text, not story prose. Needs a separate editorial/compliance decision.
- [ ] **Ship dependency:** none of the 17 clips are in `scripts/render_journey_audio.py` CLIPS yet; add + render via eleven_v3 after both gates clear.
- [ ] **Journey JSONs land separately** — this doc does not carry them; the editorial-note fixes below belong in that lane.

### joseph_arc (PASS, with blockers before ready)
- [ ] Exclusion-list gap (non-blocking curator note): `_excludedFromArcWithRationale` omits 1325 (Gen 47:7-10, Jacob blesses Pharaoh) and 1209 (Gen 49:1-33, Jacob blesses his sons). Both Jacob-POV, exclusion editorially consistent — but list them, as daniel_arc listed its POV-break exclusions.
- [ ] 1178: audio only for short WEB — full/long WEB and all three KJV variants have empty audioFilePath; must render before ready.
- [ ] 1146: single-variant story (short WEB, VOICE_JOHN_BELOVED only).
- [ ] 1037: long WEB/KJV are text-only.
- [ ] 831: 800-series audit cross-check (above).
- [ ] `joseph_sold_by_brothers` registry entry + name clip (above). Draft status `draft` is safe — validator confirmed the registry cross-check is ready-only.

### ruth_arc (FAIL — fix journey JSON notes before landing)
- [ ] **FACTUAL ERROR** stories[0].editorialNote: claims 1265 is "short-WEB-only." False — manifest carries SIX 1265 variants (short/full/long × WEB/KJV), equal to 828's coverage. The vow-vs-emptiness register rationale for choosing 828 still stands; correct the coverage claim (e.g. "…over 1265 (same pericope in the hurting register, also fully covered): the arc opens on Ruth's vow, not Naomi's emptiness").
- [ ] **FACTUAL ERROR** stories[1].editorialNote: claims 1036 is "short-WEB-only." False — six variants in manifest. B29-quality rationale for 1529 still stands; correct the note.
- [ ] Informational (fold into `_variantCoverage` before ready): 1150, 1418, 1424 are short-WEB-only IN THE MANIFEST, but KJV-short text AND audio already exist on disk for all three — part of the thinness gap closes via manifest registration alone, no new authoring.
- Everything else verified clean: JSON parses through Journey.fromJson; all storyNumber/scriptureAnchorId pairs match (including the near-duplicate ruth_1_1-22 vs ruth_1_1_22 anchors, correctly disambiguated); mood arc matches manifest; fingerprint scan zero hits.

### elijah_arc (PASS, with blockers before ready)
- [ ] Curator-note inaccuracy: 1065 editorialNote claims "Short/Full/Long × WEB/KJV" — manifest registers only KJV Short+Full; KJV Long text+audio exist on disk UNREGISTERED. Fix note before ready.
- [ ] Coverage gaps (resolve or accept before ready): 1144 and 1138 are WEB-short-only in manifest with KJV short text+audio on disk unregistered; both manifest entries have empty reflectionAudioPath/reflectionQuestion despite reflection assets on disk; 1039 has no Long variant anywhere.
- [ ] Cosmetic: `_excludedFromArcWithRationale` kid-lane line names only 1047 and kidstory_kid_elijah_chariot; kid_elijah_ravens/whisper/carmel and 1073 also exist. Class exclusion covers them; don't treat the named pair as exhaustive.

### kid_moses_arc (PASS — advisories only)
- [ ] Render-time: ear-check "Moses'" possessive (switch to "Moses's" if v3 drops the syllable).
- [ ] Anti-clumping watch: "we watched" now opens 3 of 4 kid beats corpus-wide; next kid arc should lead with a different companion verb.
- [ ] Doc parity follow-up: kid_david_arc.json's `_offerShape` still documents the retired carrier+name pattern.

### kid_joseph_arc (PASS — advisories only)
- [ ] Docs lag: JOURNEY_DOCTRINE.md Kid-Lane Appendix still describes the deprecated carrier+name-clip stitch and names kid_journey_manifest.json; shipped reality is the monolithic `<journeyId>_offer_<idx>` resolver the draft follows. Amend appendix to the 2026-06-28 pivot eventually.
- [ ] Pre-render flag: JOURNEY_TRANSITION_VOICE.md says the kid open-door tail must be reconciled with the kid response affordance (feeling cards vs. STT) before any kid beat renders. Shipped kid_david clips already carry the tail (precedent exists) — surface at render time, don't discover it then.
- [ ] Cosmetic: 1860 editorialNote says "VOICE_JAMES_BRITISH"; manifest key is VOICE_JAMES_BRITISH_PROFESSIONAL. Curator prose only.
- [ ] Ear-check at render: arc spans three narrator voices (JAMES_BRITISH_PROFESSIONAL ×2, DAVID_SHEPHERD, RUTH_COMFORT). No doctrine rule against it; offer clips render in PAL voice, so it affects story-to-story feel only.
