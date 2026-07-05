# Slate v2 — Journey Transition Beat Review (ENRICHED REGISTER)

**STATUS: DRAFT v2 — ENRICHED REGISTER (Production Invitation Families, ratified 2026-07-04) — FOR ADAM'S EDITORIAL MARKUP.**
Supersedes slate_v1 (floor register, retained as provenance at [slate_v1_beat_review.md](slate_v1_beat_review.md)). **20 beats across 6 journeys INCLUDING daniel_arc (floor clips to be replaced).** Render gated on: **Daniel smoke test + Adam's markup of these texts.**

2026-07-05 · Assembled from Draft + Verify phase output

- **Register:** ENRICHED. Every beat = frozen look-back + one invitation-family doorway + locked tail. Look-backs are byte-identical to slate_v1 / shipped daniel_arc (hexdump-verified). Doorways name the next story's *premise* only — never the payoff (one-question rule).
- **Locked tails (standalone closing sentence, straight ASCII apostrophe):** adult `Or, tell me what's on your heart today.` · kid `Or, what's on your mind?`
- **Verdicts:** 6/6 journeys PASS. **7 beats corrected in verify** (joseph ×4, ruth ×1, elijah ×2) — ALL corrections were byte-drift fixes (curly apostrophe U+2019 → straight 0x27 in frozen look-backs and/or tails). **Zero wording changes anywhere.** Daniel and both kid arcs passed as drafted.
- **Length band:** all 20 beats inside ~150–260 chars (max: ruth_arc_offer_2 at 258).
- **Scope:** BEAT TEXT only. Journey JSONs, registry entries, and render-script wiring land separately.

---

## 1. daniel_arc — Adult · 4 stories · 3 beats · PASS *(replaces shipped floor clips)*

**Arc:** 1486 Daniel at the King's Table → 1002 Standing Tall in the Flames → 1114 Daniel in the Lions' Den → 1506 The Ancient of Days *(final — no beat)*

### daniel_arc_offer_0 — F1 · after 1486 → offers 1002 · 205 chars
> Last time, we sat with young Daniel as he chose what was true… Would you like to hear what happened when his three friends would not bow to the king's golden image?… Or, tell me what's on your heart today.

- Doorway = 1002's inciting accusation ("you won't worship the golden image I've set up?") — furnace, fourth man, walking-out never named.
- Figure-shift handled: 1002 has no Daniel; grammatical subject is "his three friends" (grounded in 1486's ten-day test) — avoids the archived golden-statue failure (transition_beat_explorations_v1.md line 190) where the event/king became the subject.
- "The king's golden image" is a neutral paraphrase of WEB — translation-safe. Look-back byte-identical to shipped daniel_arc_offer_0.

### daniel_arc_offer_1 — F6 · after 1002 → offers 1114 · 222 chars
> Last time, we stood in the fire with Daniel's friends… Shall we return to Daniel? He has risen high under a new king, and the only fault his enemies can find in him is that he prays… Or, tell me what's on your heart today.

- Doorway = 1114's vv.1-3 setup (Darius sets Daniel high; "could find no occasion or fault… concerning the law of his God"; found kneeling in prayer). Decree, den, sealed stone, shut mouths all left inside the story.
- "Shall we return to Daniel?" carries the friends-to-Daniel figure-shift back. One vivid picture (the praying fault); "risen high under a new king" is the status/time-jump bridge, not a stacked image. Soft pre-tail ending on "prays".

### daniel_arc_offer_2 — F3 · after 1114 → offers 1506 · 216 chars
> Last time, we walked with Daniel into the lions' den… Let's stay with Daniel a little longer. In the night, a dream comes to him — four winds of heaven striving on a great sea… Or, tell me what's on your heart today.

- Doorway = the vision's literal first image ("He had seen the four winds of heaven striving on the great sea") — beasts, Ancient of Days, thrones, Son of Man all stay inside the story.
- Translation check vs scripture_1506 files: WEB "four winds of the sky broke out on the great sea," KJV "four winds of the heaven strove upon the great sea" — beat matches the repo's own PD telling + KJV family; NIV "churning up" / ESV-NASB "stirring up" absent.
- Look-back byte-identical to shipped daniel_arc_offer_2 (the PAL_VOICE.md exemplar). Pre-tail ends on open vowel "sea".

---

## 2. joseph_arc — Adult · 5 stories · 4 beats · PASS *(4 beats corrected: byte-drift only)*

**Arc:** 1037 Joseph Sold by His Brothers → 1178 But the Cupbearer Forgot Him → 831 Joseph Interprets Pharaoh's Dreams → 1003 Tears That Shattered the Silence → 1146 Then Joseph Wept *(final — no beat)*

### joseph_arc_offer_0 — F1 Curious · after 1037 → offers 1178 · 242 chars · CORRECTED (bytes)
> Last time, we watched Joseph's brothers sell him for twenty pieces of silver… Would you like to hear what happened when Joseph, far from home in an Egyptian prison, met two men troubled by their dreams? Or, tell me what's on your heart today.

- Correction: curly apostrophes (U+2019) in frozen look-back ("Joseph's") and tail ("what's") restored to ASCII frozen forms — hexdump-verified against slate_v1.
- Doorway names only the prison meeting and the two men's troubled dreams ("We have dreamed a dream, and there is no one who can interpret it"); interpretation and the cupbearer's forgetting unspoiled.
- **Carried v1 flag — brothers-centered look-back:** frozen look-back centers the **brothers** grammatically (Joseph present as "him"). Precedented by shipped daniel_arc_offer_1 ("Daniel's friends"). "Twenty pieces of silver" is WEB+KJV verbatim (NIV/ESV: "twenty shekels").

### joseph_arc_offer_1 — F4 Gentle curiosity · after 1178 → offers 831 · 229 chars · CORRECTED (bytes)
> Last time, we waited with Joseph in prison, forgotten by the man he had helped… Would you like to see where God leads Joseph when Pharaoh wakes from dreams none of his wise men can explain? Or, tell me what's on your heart today.

- Correction: tail's curly apostrophe only; look-back was already byte-identical.
- Doorway verified against 831's opening ("He called all his magicians and wise men, but none could interpret the dreams for him") — same territory as the doctrine's ✓ exemplar; summons, interpretation, elevation unspoiled.

### joseph_arc_offer_2 — F6 Compound · after 831 → offers 1003 · 241 chars · CORRECTED (bytes)
> Last time, we walked with Joseph from the cold stone of prison into Pharaoh's court… Shall we stay with Joseph a little longer? He is about to send everyone out of the hall — everyone but his brothers. Or, tell me what's on your heart today.

- Correction: curly apostrophe in frozen look-back ("Pharaoh's") + tail restored to ASCII frozen forms.
- Doorway = 1003's literal opening ("Have everyone leave me!" … "No one else remained in the hall except Joseph and his brothers") — reveal/weeping/reconciliation unspoiled. One declarative doorway picture.
- F6→F3 "Shall we…" opener adjacency with beat 3 is family-level-valid (see advisory in Open Items).

### joseph_arc_offer_3 — F3 Walking (signature) · after 1003 → offers 1146 · 251 chars · CORRECTED (bytes)
> Last time, we stood in the emptied hall as Joseph wept and told his brothers who he was… Shall we keep walking with Joseph? Years later, when their father is gone, his brothers grow afraid of him all over again. Or, tell me what's on your heart today.

- Correction: tail's curly apostrophe only; look-back was already byte-identical.
- Doorway = 1146's opening movement (after Jacob's burial: "It may be that Joseph will hate us…") — names only the returning fear; "you meant evil against me, but God meant it for good" and Joseph's comfort left to the full story per the compressed-theology rule. Soft n-ending before the tail.

---

## 3. ruth_arc — Adult · 5 stories · 4 beats · PASS *(1 beat corrected: byte-drift only)*

**Arc:** 828 Ruth and Naomi → 1529 Ruth in the Field → 1150 At the Threshing Floor → 1418 Boaz at the Gate → 1424 A Son Is Born to Naomi *(final — no beat)*

### ruth_arc_offer_0 — F3 · after 828 → offers 1529 · 248 chars
> Last time, we stood on the road with Ruth as she clung to Naomi, refusing to turn back… Let's stay with Ruth a little longer. She goes out to gather barley in a stranger's field, not knowing whose land it is… Or, tell me what's on your heart today.

- Doorway grounded in 1529's own opening (Ruth asks to glean, walks to the barley fields, "She did not know it, but the field belonged to Boaz") — dramatic-irony doorway; Boaz's notice and kindness speech unspoiled.
- **Carried v1 flag — "clung" (NIV-adjacent verb) in the frozen look-back:** NOT WEB Ruth 1:14 (WEB: "Ruth stayed with her"); NIV/ESV/NRSV render "clung to her." Cleared because the 828 corpus telling itself says "Ruth clung to Naomi tightly," look-back rule mandates corpus grounding, it's a single common verb (not a signature phrase), and the registry fingerprint scan is clean. Overrule if you want zero NIV-adjacent vocabulary.

### ruth_arc_offer_1 — F1 · after 1529 → offers 1150 · 223 chars
> Last time, we watched Ruth gather barley behind the reapers, the day Boaz first noticed her… Would you like to hear what happened when Naomi sent Ruth by night to the threshing floor? Or, tell me what's on your heart today.

- Doorway names only 1150's situation (Naomi's plan: "he winnows barley tonight at the threshing floor… go down"; Ruth going by night) — Boaz's midnight response and kinsman pledge unspoiled. "Threshing floor" is WEB/KJV wording.

### ruth_arc_offer_2 — F4 · after 1150 → offers 1418 · 258 chars · CORRECTED (bytes)
> Last time, we waited at the threshing floor as Ruth came softly through the dark to Boaz's feet… Would you like to see where God leads Boaz next — to the gate of Bethlehem, where a nearer kinsman holds the first claim? Or, tell me what's on your heart today.

- Correction: frozen look-back had drifted — curly apostrophe U+2019 in "Boaz's" where slate_v1 (line 60) has straight ASCII 0x27 (hexdump-verified). Restored byte-identical.
- Doorway names the obstacle/question (nearer kinsman's prior claim — 1418 line 1, and already introduced by 1150's own ending), never the resolution (shoe, decline, marriage unspoiled). "Nearer kinsman" is WEB Ruth 3:12 wording (no NIV/ESV redeemer signatures). One image (the gate of Bethlehem). Longest beat in the slate — inside the band, at the top.

### ruth_arc_offer_3 — F6 · after 1418 → offers 1424 · 257 chars
> Last time, we sat at the gate of Bethlehem as Boaz stood before the elders and spoke for Ruth… Shall we keep walking with Ruth and Naomi? The neighbor women are coming up the road to Naomi's door, carrying a blessing… Or, tell me what's on your heart today.

- Doorway = 1424's literal opening (women of the neighborhood coming up the road to Naomi's house to speak the blessings); final/rest beat, so the fulfillment clause sanctions the rest-toned glimpse — the child, the name Obed, and the David lineage remain unspoiled. "Neighbor women" mirrors WEB "the women, her neighbors."
- **Carried v1 flag — Boaz-centered look-back:** 1418's primaryCharacterId is **boaz** (manifest-confirmed); frozen look-back keeps Ruth the relational center per JOURNEY_TRANSITION_VOICE.md's different-figures note.

---

## 4. elijah_arc — Adult · 5 stories · 4 beats · PASS *(2 beats corrected: byte-drift only)*

**Arc:** 1039 Elijah and the Widow of Zarephath → 1065 Elijah on Mount Carmel → 1144 Under the Juniper Tree → 825 Elijah at Horeb → 1138 The Chariot of Fire *(final — no beat)*

### elijah_arc_offer_0 — F4 · after 1039 → offers 1065 · 256 chars · CORRECTED (bytes)
> Last time, we stood with Elijah at the gate of Zarephath, where a widow's last handful of meal became enough… Would you like to see where God leads Elijah next — to Carmel, before all Israel and the prophets of Baal? Or, tell me what's on your heart today.

- Correction: curly apostrophe in "widow's" restored to straight (U+0027) per slate_v1 bytes.
- Doorway verified against 1065's actual opening (Ahab gathers the people and prophets of Baal to Carmel; Elijah stands before them) — the fire falling is never named, so it answers only "why listen next." "All Israel"/"prophets of Baal" are WEB 1 Kings 18:19 phrasing. Top of band — one breath.

### elijah_arc_offer_1 — F1 · after 1065 → offers 1144 · 213 chars · CORRECTED (bytes)
> Last time, we watched fire fall on Elijah's drenched altar at Carmel… Would you like to hear what happened when Elijah fled from a queen's threat into the wilderness, alone? Or, tell me what's on your heart today.

- Correction: curly apostrophe in "Elijah's" restored to straight; now byte-identical to frozen look-back.
- Doorway verified against 1144's actual opening (Jezebel's threat, "went for his life," a day's journey into the wilderness, "he was alone") — the angel, the cake on the coals, and the death-wish theology stay inside the story. "Fled" is plain English, not NIV's "ran for his life" signature. Soft "alone?" ending.

### elijah_arc_offer_2 — F5 · after 1144 → offers 825 · 213 chars *(the slate's single F5)*
> Last time, we sat with Elijah under the juniper tree, where an angel woke him to a cake baked on the coals… Whenever you're ready, there's another part of the story waiting. Or, tell me what's on your heart today.

- F5 canonical sentence verbatim, used exactly once in the slate per assignment; carries no doorway by design — the frozen look-back's angel-and-food moment is itself the hinge into 825 (1144 closes with Elijah walking in the strength of that food to Horeb; 825 opens at Horeb's cave).
- "Cake baked on the coals" is WEB/KJV wording (NIV's "bread baked over hot coals" avoided). No spoiler of 825's wind/earthquake/fire/still-small-voice sequence. Soft "waiting." ending.

### elijah_arc_offer_3 — F6 · after 825 → offers 1138 · 234 chars
> Last time, we waited with Elijah in the cave on Horeb, where God came in a still small voice… Shall we keep walking with Elijah? He's setting out on one last road, and Elisha will not leave him. Or, tell me what's on your heart today.

- "Still small voice" = KJV/WEB/ASV; NIV's "gentle whisper" correctly absent from the beat (the pre-existing 825 corpus flag is outside this beat — see Open Items).
- Doorway verified against 1138: "one last road" echoes its own first sentence (the Lord about to take Elijah up — premise, not payoff); "Elisha will not leave him" is the opening movement's verbatim refrain ("I will not leave you," WEB). Chariot of fire, whirlwind, double-portion request all unspoiled. One picture (the shared road; the Elisha clause is relational, not a stacked second image). Soft "him." ending.

---

## 5. kid_moses_arc — Kid · 3 stories · 2 beats · PASS *(no corrections)*

**Arc:** 1810 Baby Moses → 1811 The Burning Bush → 1813 Crossing the Red Sea *(final — no beat)*

### kid_moses_arc_offer_0 — F1 · after 1810 → offers 1811 · 227 chars
> Last time, we watched a baby float snug in his little basket among the reeds… Would you like to hear what happened when that baby grew up to be a shepherd, and saw a bush on fire that never burned away? Or, what's on your mind?

- Doorway names only 1811's opening situation (shepherd Moses, the bush ablaze yet unburned) — God's voice, the commission, and the name Yahweh all withheld. Grounded in story_1811_short.txt ("a shepherd named Moses… the bush did not burn up… stayed green").
- "Never burned away" is a plain kid paraphrase, not NIV's signature "did not burn up" (WEB: "was not consumed"). Person is the grammatical subject; "grew up to be a shepherd" is the person-path connector, not a stacked image.

### kid_moses_arc_offer_1 — F3 · after 1811 → offers 1813 · 234 chars
> Last time, we stood with Moses at the bush that burned and burned but never burned up… Shall we keep walking with Moses? He's leading God's people out of Egypt now, all the way to the edge of a great wide sea. Or, what's on your mind?

- Doorway names only 1813's opening situation (out of Egypt, at the sea's edge) — pursuing army, sea splitting, safe crossing all withheld. "Great wide sea" quotes the shipped kid telling's opening line.
- **Carried v1 flag — "never burned up" (NIV-shadow) in the frozen look-back:** resembles NIV Ex 3:2 ("did not burn up") but directly quotes the shipped kid telling, which the look-back rule requires; plain kid English, cleared (WEB comparison done: "was not consumed"). Overrule if you want zero NIV-shadow vocabulary.
- Soft pre-tail ending ("sea.").

---

## 6. kid_joseph_arc — Kid · 4 stories · 3 beats · PASS *(no corrections)*

**Arc:** 1844 Joseph's Colorful Coat → 1906 Joseph Far From Home → 1860 Joseph and the King's Dreams → 1819 Joseph Forgives His Brothers *(final — no beat)*

### kid_joseph_arc_offer_0 — F6 · after 1844 → offers 1906 · 214 chars
> Last time, we watched Joseph wear his beautiful coat, woven in every color you can imagine… Shall we keep walking with Joseph? He's far from home now, in a land where no one knows his name. Or, what's on your mind?

- Doorway grounded in 1906's actual opening ("all the way to Egypt, where the language was strange and no one knew his name") — the next story's entry threshold, not 1844's recap and not the Potiphar/prison/dream arc. One image; soft "name" ending.

### kid_joseph_arc_offer_1 — F1 · after 1906 → offers 1860 · 213 chars
> Last time, we waited with Joseph in the dark, and God stayed right beside him… Would you like to hear what happened when the king of Egypt had two strange dreams that nobody could explain? Or, what's on your mind?

- Doorway matches 1860's actual inciting problem ("two strange dreams that worried him… no one in all of Egypt could tell him"); "strange" is 1860's own adjective, not stakes-inflation. Interpretation, elevation, and famine plan unspoiled — mirrors the doctrine's ratified one-question exemplar. Soft "explain" ending.

### kid_joseph_arc_offer_2 — F3 · after 1860 → offers 1819 · 255 chars
> Last time, we stood with Joseph before the king, when God showed him what the dreams meant… Let's stay with Joseph a little longer. His very own brothers are about to come to Egypt looking for food — and they don't know who he is. Or, what's on your mind?

- Doorway grounded in 1819's actual opening movement ("who should arrive in Egypt one day, looking for food to buy, but Joseph's very own brothers! They did not know…") — names the situation and its irony, never the payoff (forgiveness, the weeping embrace, the reunited family all unspoken). One scene, not stacked images; soft voiced-z ending before the tail.

---

## Family Rotation Summary

| Journey | Beat 0 | Beat 1 | Beat 2 | Beat 3 |
|---|---|---|---|---|
| daniel_arc | F1 | F6 | F3 | — |
| joseph_arc | F1 | F4 | F6 | F3 |
| ruth_arc | F3 | F1 | F4 | F6 |
| elijah_arc | F4 | F1 | **F5** | F6 |
| kid_moses_arc | F1 | F3 | — | — |
| kid_joseph_arc | F6 | F1 | F3 | — |

- **Usage totals:** F1 ×6 · F3 ×5 · F6 ×5 · F4 ×3 · **F5 ×1 (elijah_arc_offer_2 — exactly once, per assignment)** · F2 unused in this slate.
- No consecutive same-family repeats within any journey. Every journey opens with a different family than its neighbor where possible; kid arcs stay in the F1/F3/F6 range (no F4/F5 in kid lane this slate).

---

## Open Items

### Verifier problems (verbatim)

**daniel_arc:** none.

**joseph_arc:**
- "LOOK-BACKS FROZEN violation in draft (beats 0 and 2): curly apostrophes U+2019 ('Joseph’s', 'Pharaoh’s') where the frozen look-backs in docs/editorial/history/slate_v1_beat_review.md use ASCII apostrophes 0x27 (verified via hexdump). Restored byte-identical."
- "TAIL exactness violation in draft (all four beats): 'what’s' (U+2019) instead of the exact locked adult tail \"Or, tell me what's on your heart today.\" (straight apostrophe, matching the doctrine and shipped daniel_arc floor clips). Fixed on all beats."
- "Advisory (cleared, no change): beats 2 and 3 both open 'Shall we…' because F6's canonical exemplar itself uses a walking-flavored invite; rotation operates at the family level (F1→F4→F6→F3, no repeats), and the assignment's own F1→F4 pair shares a 'Would you like…' opener the same way. Flagged for Adam's ear-check at render time only."

**ruth_arc:**
- "ruth_arc_offer_2 look-back had drifted from the frozen slate v1 text: 'Boaz’s' used a curly apostrophe (U+2019) where the frozen version uses a straight ASCII apostrophe (0x27, hexdump-verified against docs/editorial/history/slate_v1_beat_review.md line 60). Fixed in final_beats — corrected look-back is now byte-identical and the beat is 258 chars, still within the ~150–260 band. No other failures: all doorways verified against the actual next-story text files (1529/1150/1418/1424), no destination/resolution/rescue revealed (beat 3 covered by the fulfillment clause for the final rest beat), family shapes conform with sequence F3→F1→F4→F6 (no consecutive repeats, F5 correctly absent), adult tails exact, one doorway image per beat, no sensational adjectives, no banned-translation signature phrasing."

**elijah_arc:**
- "Beats 0 and 1: draft look-backs were NOT byte-identical to the frozen look-backs — curly apostrophes (U+2019) in \"widow’s\" and \"Elijah’s\" where the frozen texts in docs/editorial/history/slate_v1_beat_review.md use straight apostrophes (U+0027). Restored to byte-identity; no other wording changed (lengths unchanged: 256 and 213 chars)."
- "Advisory (not a failure): beat 3's F6 doorway is a compound sentence ('one last road, and Elisha will not leave him') versus the doctrine's single-clause exemplar ('He's about to be called before Pharaoh'). Judged conformant — one doorway picture (the shared road), with the second clause relational rather than a stacked image — but flagged for Adam's eye."
- "Pre-existing corpus issue re-confirmed while reading 825 (outside these beats, already in slate Open Items): shipped 825 variants contain NIV-signature 'a gentle whisper' alongside compliant 'still small voice'. The WEB short read for this verify shows 'a still small voice' at the beat-relevant line; the beat itself is clean."

**kid_moses_arc:** none.

**kid_joseph_arc:** none.

### Standing 800-series audit note (carried from slate v1)
- [ ] **831 and 825:** both 800-series stories in this slate need their full-length variants cross-checked against the 800-series content-audit per-variant decision queue before promotion (831 explicitly flagged by the joseph verifier; apply the same check to 825).
- [x] **825 compliance flag — RESOLVED 2026-07-04 (commit f43fab1f), before this v2 pass:** "a gentle whisper" was purged from all six 825 texts, the six story mp3s deleted + re-rendered, the three live R2 objects replaced, and Adam ear-approved the new renders. (The elijah verifier's "re-confirmed" note above is stale — its own fresh read of the WEB short found the clean "still small voice" text, which IS the post-purge file. Kid 1839 was purged and retitled in the same commit.)

### Name registry
| Journey | Registry state | Action |
|---|---|---|
| daniel_arc | **Already registered** (shipped journey) | None |
| joseph_arc | `joseph_sold_by_brothers` ABSENT from registry | Add adult entry + render name clip before ready |
| ruth_arc | `ruth_and_naomi` ABSENT from registry | Add adult entry + render name clip before ready |
| elijah_arc | `null` — monolithic-offer precedent | None |
| kid_moses_arc / kid_joseph_arc | null per kid_david precedent | Confirm null in journey JSONs |

### Render gate (restated)
- [ ] (a) Daniel smoke test passes. (b) Adam's markup/sign-off on the 20 texts above.
- [ ] daniel_arc renders REPLACE the shipped floor clips (`daniel_arc_offer_0/1/2`); the floor clips remain archived as provenance.
- [ ] All clips render via eleven_v3 per the PAL-voice-audio rule; none of the 20 are wired into `scripts/render_journey_audio.py` CLIPS yet.
- [ ] Render-time ear-checks carried from advisories: joseph beats 2/3 "Shall we…" adjacency; elijah beat 3 compound doorway; kid tail vs. response-affordance reconciliation (JOURNEY_TRANSITION_VOICE.md) before any kid beat renders.
