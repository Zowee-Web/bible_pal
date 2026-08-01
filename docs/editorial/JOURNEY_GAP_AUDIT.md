# Bible PAL — Journey Gap Audit

> **Status:** Approved planning baseline (Adam, 2026-07-16) — **G1–G11 authored (2026-07-31); G13–G16 authored as 1611–1614 (2026-08-01); only G12 remains open**
> **Audit date:** 2026-07-16
> **Scope:** Full traditional story corpus (591 stories, 137 primary-character labels)
> **Task type:** AUDIT + PLANNING ONLY — no beats authored, no ledger/arc-JSON/audio/app-code changed.
> **Companion machine-readable file:** [`assets/stories/journey_gap_backlog.json`](../../assets/stories/journey_gap_backlog.json)

This document is the durable source of truth for where Bible PAL's Journey Beat system can build safely against today's corpus, and the short, verified list of missing stories whose absence would otherwise force a future beat rewrite. It supersedes the rendered HTML artifact produced during the audit session.

---

## 0. Status refresh — 2026-07-31

> **G1–G11 HAVE BEEN AUTHORED. DO NOT RE-ISSUE THEM FOR PRODUCTION.**

Until this refresh G1–G10 still read `status: planned` and G11 still read `status: intentionally_deferred`, although all eleven stories had been written and registered. Consuming the backlog as-is would have instructed duplicate production.

| G | Authored as | Anchor | Was |
|---|---|---|---|
| G1 · The Passover and the Plagues | **1576** | Exodus 7-12 | planned |
| G2 · Jacob and Esau Reconcile | **1573** "Esau Ran to Meet Him" | Genesis 33 | planned |
| G3 · Bathsheba and Uriah | **1581** | 2 Samuel 11 | planned |
| G4 · Delilah and Samson's Capture | **1574** "He Told Her All His Heart" | Judges 16:4-22 | planned |
| G5 · The Gibeonite Covenant | **1578** | Joshua 9 | planned |
| G6 · Achan's Judgment and the Capture of Ai | **1577** | Joshua 7:13-8:29 | planned |
| G7 · Absalom's Death | **1582** "O My Son Absalom" | 2 Samuel 18 | planned |
| G8 · Moses Flees to Midian | **1583** | Exodus 2:11-22 | planned |
| G9 · The Stolen Blessing | **1572** | Genesis 27 | planned |
| G10 · The Flood | **1571** | Genesis 7-8 | planned |
| G11 · Korah's Rebellion | **1596** "Korah's Rebellion: The Earth Opens" | Numbers 16:1-35 | intentionally_deferred |

Every mapping was derived from — not assumed against — the corpus at master `fe09b63808c0ab4a798cae9a3087955b9a1320cb`: `meta_<id>.json` **and** `manifest.json` agree on title, anchor and `bibleStoryKey` for all eleven.

**They are `authored`, NOT `integrated`.** Per this document's own status vocabulary, `integrated` means *authored AND wired into its arc/journey; gap closed*. None of the eleven appears in `outgoing_beats.json` (31 entries) or in any of the 18 `assets/stories/journeys/*.json` arc files. **The stories exist; the journey wiring does not.** That wiring is the outstanding work — §4's tiers below now describe an authoring state that has passed, not the beats.

**Still open as of 2026-07-31 — G12–G16** *(G13–G16 SUPERSEDED by §0.1: authored 2026-08-01 as 1611–1614. This paragraph records the 2026-07-31 state, not today's.)*
- **G12** — partially covered. Story 1049 (Numbers 13:25-33, Caleb POV) still the only coverage; the Moses-POV unit including the Numbers 14 rebellion/intercession is still absent. Remains `intentionally_deferred`; guest-beat-solvable per Audit Decision 3. **Still true today.**
- **G13** (2 Kings 20) · **G14** (2 Chronicles 35) · **G15** (Genesis 19) · **G16** (Jonah 4) — all four re-confirmed absent from the entire corpus at that date. **True, deliberately parked gaps.** Then `intentionally_deferred`; **now authored — see §0.1.**

As of the 2026-07-31 refresh, `fillPriority.fillNow` and `fillPriority.stronglyConsider` were empty and `deferUntilArcApproached` was G12–G16; **§0.1 supersedes this — the lists are now empty except for G12.** `auditDate`, rationale, seams, ordering, severities, gapTypes and `verificationStatus` are preserved — `verificationStatus: confirmed_absent` records the **2026-07-16** corpus, not today's.

---

## 0.1 Production queue and outcome — 2026-08-01

Adam approved the four remaining true gaps for production on 2026-08-01, **the decision recorded before any prose existed** (`status: planned`, `fillPriority.fillNow = [G13, G14, G15, G16]`, no `productionId`). Later the same day all four were authored.

> **G13–G16 ARE NOW AUTHORED as stories 1611–1614. DO NOT RE-ISSUE THEM FOR PRODUCTION.**

**Each approval was a NARROWED anchor, not the whole gap reference.** The excluded verses stay uncovered by design and must not be silently claimed as covered by a later refresh:

| G | Gap reference | **Owner-approved anchor** | Authored as | Deliberately excluded — still uncovered |
|---|---|---|---|---|
| G13 | 2 Kings 20 | **2 Kings 20:1-11** — illness, healing, the shadow sign | **1611** "Hezekiah's Illness and the Shadow Turned Back" | **20:12-21** — the Babylonian envoys and Isaiah's prophecy |
| G14 | 2 Chronicles 35 | **2 Chronicles 35:1-19** — the Passover itself | **1612** "Josiah's Great Passover" | **35:20-27** — Josiah's battle at Megiddo and his death |
| G15 | Genesis 19 | **Genesis 19:1-29** — the visitors at the gate, the rescue, the destruction (adult lane only) | **1613** "Sodom's Destruction and Lot's Rescue" | **19:30-38** — Lot and his daughters in the cave; the origins of Moab and Ammon |
| G16 | Jonah 4 | **Jonah 4** — whole chapter | **1614** "Jonah and the Plant" | *(none)* |

Every mapping was derived from — not assumed against — the corpus: `meta_<id>.json` **and** `manifest.json` agree on title, anchor and `bibleStoryKey` for all four.

**They are `authored`, NOT `integrated`.** They are also **text-first**: registered WEB + KJV with `audioFilePath` and `reflectionAudioPath` blank, awaiting owner text review before any audio. None of 1611–1614 appears in `outgoing_beats.json` or in any `assets/stories/journeys/*.json` arc file — the stories exist; the journey wiring does not.

`fillPriority` is now **fillNow `[]` · stronglyConsider `[]` · deferUntilArcApproached `[G12]`** — no item carrying a `productionId` remains queued. `auditDate`, rationale, seams, severities, `gapType`, `verificationStatus` and ordering are all preserved unchanged. **G12 is untouched** and remains `intentionally_deferred` — the Moses-POV spies unit is still guest-beat-solvable via story `1049`, and is now the *only* open item in this backlog.

---

## 1. Scope, methodology, and date

- **Date:** 2026-07-16.
- **Corpus surveyed:** every `primaryCharacterDisplayName` with ≥2 stories (46 characters with ≥3 = "arc-capable"), plus a full sweep of the 67 single-story satellite characters.
- **Method:**
  1. Built a character roster and a full-corpus scripture-anchor index from every `meta_<id>.json`.
  2. Ran **ten parallel era-audits** (Patriarchs; Exodus–Conquest; Judges & Ruth; Rise of the Monarchy; Elijah/Elisha; Southern Kings & Prophets; Exile & Return; Gospels non-Jesus; Acts & Epistles; Poetry & Wisdom). Every audit **read the actual story prose on both sides of each candidate seam** — a gap judgment made without reading the flanking stories was rejected.
  3. **Full-corpus verification pass:** every flagged "missing" story was checked against the complete anchor index and, where a match existed under any character, the prose was read to confirm ownership. This caught five false positives (see §8).
  4. Jesus (74 stories) mapped separately against the doctrine's 14-point Life-of-Jesus arc.
- **Editorial posture:** *an editor of a published chronological Bible, not a completionist.* A missing story is flagged only where its absence forces invented context or a future beat rewrite. Where a seam can be bridged honestly, the current corpus is preferred. Conservative throughout — the backlog is deliberately short.

---

## 2. Corpus-health summary

The library is in **strong editorial health**. Two findings dominate:

1. **Duplication, not missing stories, is the larger concern.** The same scripture anchor is frequently rendered many ways (see §6). Curation/dedupe is a bigger task than authoring.
2. **Most apparent gaps are not gaps.** An apparent chapter-jump is almost always honest, for one of two reasons:
   - **Narratable-over:** the *next* story's own opening frame explicitly re-grounds the skipped material (Samuel's Ebenezer recaps the ark; David's lament recaps Gilboa's deaths; Joseph's every chapter opens with a summary of the last).
   - **Cross-character ownership:** the "missing" scene exists under a *different* `primaryCharacterDisplayName` and was invisible to a character-scoped search (Ruth's redemption-at-the-gate is filed under **Boaz**; Isaac's birth under **Sarah**; Paul's arrest recap inside **his sister's son's** story).

Genuine **force-invention** gaps — where a beat could only bridge a seam by inventing an untold central event — are **few**: five hard blockers and a handful of paired/secondary gaps.

**Headline counts (2026-07-16):** 591 stories · 137 character labels · 46 arc-capable (≥3) · ~30 arcs buildable now · **5 hard blockers**. _As of 2026-07-31 all five hard blockers (G1–G5) have been authored; see §0._

---

## 3. Verified gap backlog

Ranked by production value. Fields per item: **scripture reference · severity · affected character/arc · exact existing seam (left → right story IDs) · can beats safely ignore it? · what it unlocks.** Every item was verified absent from the entire corpus.

Severity key: **HIGH** = blocks an arc; no honest beat can bridge it. **MED** = weakens an arc or is needed to reach its terminus. **LOW** = real absence but bridgeable / enrichment.

### Hard blockers (author before the affected arc)

> _2026-07-31: G1-G5 are all authored. The prose below is the preserved 2026-07-16 rationale for why each was needed._

**AUTHORED as 1576 (not yet arc-wired)** · **G1 · The Passover & the Plagues — Exodus 7–12 — HIGH**
- Affected: Moses / `moses_arc_1` (Deliverance).
- Seam: `1019` (Burning Bush, Ex 3) → `1117` (Red Sea, Ex 14).
- Ignore? **NO.** The central Exodus drama — "let my people go," the ten plagues, the blood on the doorposts — is entirely off-screen. A beat across this seam would have to compress the whole turning point into a summary sentence.
- Unlocks: the core seam of the Moses Deliverance arc (already flagged inside the `moses_arc_1` ledger note). Highest-priority continuity blocker for the Moses Deliverance arc.

**AUTHORED as 1573 (not yet arc-wired)** · **G2 · Jacob & Esau Reconcile — Genesis 33 — HIGH**
- Affected: Jacob / full Jacob life-arc.
- Seam: `1021` (Wrestles at the Jabbok, Gen 32) → `1382` (El Beth El, Gen 35).
- Ignore? **NO.** Two existing stories (the Jabbok prayer `1345` and the wrestling `1021`) build sustained dread of Esau and his four hundred men; the payoff — the run, the embrace, the weeping — exists nowhere, and `1382` opens already past the meeting. Highest-impact single gap for a full Jacob arc.
- Unlocks: the full Jacob life-arc (today buildable only as the shorter "Encounter" sub-arc `1018→1345→1021`).

**AUTHORED as 1581 (not yet arc-wired)** · **G3 · Bathsheba & Uriah — 2 Samuel 11 — HIGH**
- Affected: David / David fall arc (`david_arc_7`).
- Seam: settled reign (`1062`, 2 Sam 9) → `1553` (Nathan and the Lamb, 2 Sam 12).
- Ignore? **NO.** Nathan's parable (`1553`) and the child's death (`1342`) both structurally depend on an act the corpus never depicts; a fall→grief arc must otherwise open on a rebuke for a deed the listener never saw.
- Unlocks: the David fall arc as a true arc (currently a single edge `1553→1342`).

**AUTHORED as 1574 (not yet arc-wired)** · **G4 · Delilah & the Capture — Judges 16:4–22 — HIGH**
- Affected: Samson / any Samson arc.
- Seam: `1142` (An Angel at Zorah — birth, Judges 13) → `1193` (Let Me Die with the Philistines — death, Judges 16:23–31).
- Ignore? **NO.** Samson has only two stories; `1193`'s opening already assumes a blind, shorn prisoner. Who Delilah is, why he cannot see, why he is in chains: untold. No beat can bridge a birth announcement to a blinding.
- Unlocks: any Samson arc at all (the character is otherwise unbuildable).

**AUTHORED as 1578 (not yet arc-wired)** · **G5 · The Gibeonite Covenant — Joshua 9 — HIGH**
- Affected: Joshua / continuous Conquest arc.
- Seam: `1294` (Ai defeat & Joshua's prayer, Josh 7) → `1151` (Sun, Stand Still, Josh 10).
- Ignore? **NO.** `1151` opens *"…heard that Gibeon had made peace with Israel"* — and Gibeon is introduced nowhere. The battle (and the sun miracle) happens *because* of a treaty the listener never witnessed.
- Unlocks: Joshua's continuous Conquest arc (`1151` cannot sit mid-arc without it). Joshua's two *flanking* sub-arcs — Entering-the-Land and Rest/Farewell — are already safe.

### Paired resolution / secondary (author with the blockers for the same arcs)

> _2026-07-31: G6-G10 are all authored. The prose below is the preserved 2026-07-16 rationale._

**AUTHORED as 1577 (not yet arc-wired)** · **G6 · Achan's Judgment & the Capture of Ai — Joshua 7:16–8:29 — MED**
- Affected: Joshua / Conquest arc (pairs with G5).
- Seam: `1294` (Josh 7 defeat, dead-ends on God's rebuke *"I will not be with you… unless you destroy the devoted things"*) → `1151` (Josh 10).
- Ignore? **NO for a continuous arc.** `1294` currently dead-ends on a divine cliffhanger with no payoff clip; `1151` then assumes *"Joshua had taken Ai."* Authoring this resolves `1294` and, with G5, makes the Conquest middle continuous.
- Unlocks (with G5): the whole Joshua Conquest middle.

**AUTHORED as 1582 (not yet arc-wired)** · **G7 · Absalom's Death — "O Absalom, my son" — 2 Samuel 18 — MED**
- Affected: David / rebellion→grief arc (pairs with G3).
- Seam: `1323` (The People Are Weary in the Wilderness, 2 Sam 17) → *(no right story — terminal grief)*.
- Ignore? **NO for a rebellion arc.** Only the flight (`1323`) touches the rebellion; the death and the lament at the gate are absent, so a rebellion→grief arc has no climax to reach.
- Unlocks (with G3): the complete David fall/rebellion material.

**AUTHORED as 1583 (not yet arc-wired)** · **G8 · Moses Flees to Midian — Exodus 2:11–25 — MED** *(new finding this audit)*
- Affected: Moses / `moses_arc_1` opening seam.
- Seam: `1033` (Baby Moses, Ex 2:1–10) → `1019` (Burning Bush, Ex 3 — already a grown Midianite shepherd).
- Ignore? **NO.** The killing of the Egyptian and the flight — the hinge that turns the prince into a fugitive — is untold (it survives only inside Stephen's Acts 7 sermon, `1164`).
- Unlocks: an honest opening seam for the Moses Deliverance arc.

**AUTHORED as 1572 (not yet arc-wired)** · **G9 · The Stolen Blessing — Genesis 27 — MED**
- Affected: Jacob / full Jacob arc origin (pairs with G2).
- Seam: `1428` (Isaac in the field, Gen 24) → `1018` (Jacob's Ladder / the flight, Gen 28).
- Ignore? **NO for a full arc.** The *origin* of the Jacob–Esau conflict; without it the fear driving the Jabbok prayer and the "deceiver renamed Israel" weight has no cause.
- Unlocks (with G2): an honest opening for the full Jacob arc.

**AUTHORED as 1571 (not yet arc-wired)** · **G10 · The Flood — Genesis 7–8 — MED**
- Affected: Noah / any Noah arc.
- Seam: `1017` (Noah Builds the Ark, Gen 6) → `1213` (I Set My Rainbow, Gen 9).
- Ignore? **NO.** Noah has only two stories, and the arc's entire turning point (the judgment, the year afloat, the dove, Ararat) happens between them with no story of its own.
- Unlocks: a real Noah arc instead of a two-beat ark→rainbow jump.

### Deferred until their specific arc is approached

> _2026-07-31: G11 has since been authored as **1596** (ahead of its arc). G12-G16 re-verified and still open._
> _2026-08-01: G13-G16 have been **authored** as stories **1611-1614** (text-first, not yet arc-wired) with narrowed anchors — see §0.1. **G12 is now the only open item in this backlog**, and the tier name below describes G12 alone._

**G11 · Korah's Rebellion — Numbers 16 — MED (AUTHORED 2026-07 as 1596, not yet arc-wired)** — Moses back-half; genuinely absent. Seam `1316` (Too Heavy, Num 11) → `1364` (Meribah, Num 20).
**G12 · The Spies from Moses' POV — Numbers 13–14 — LOW (deferred)** — the **event exists** as Caleb's `1049` (Num 13:25–33) and can serve as a **guest beat** in a Moses arc; a dedicated Moses-POV render is optional enrichment, not a blocker.
**G13 · Hezekiah's Illness & the Shadow Turned Back — 2 Kings 20 — MED (AUTHORED 2026-08-01 as 1611, not yet arc-wired · anchor narrowed to 2 Kings 20:1-11; 20:12-21 stays uncovered)** — needed only to lift thin Hezekiah (2 episodes) to a buildable three. Seam `1511` (Sennacherib) → `1611`.
**G14 · Josiah's Great Passover — 2 Chronicles 35 — MED (AUTHORED 2026-08-01 as 1612, not yet arc-wired · anchor narrowed to 2 Chronicles 35:1-19; 35:20-27 stays uncovered)** — needed only to lift thin Josiah (2 episodes) to three. (Huldah's prophecy `1475` already offers a possible third.) Seam `1512` (Book Found) → `1612`.
**G15 · Sodom's Destruction & Lot's Rescue — Genesis 19 — LOW (AUTHORED 2026-08-01 as 1613, not yet arc-wired · anchor narrowed to Genesis 19:1-29; 19:30-38 stays uncovered; adult lane only)** — `1487` (Abraham's intercession) no longer has to be held standalone: `1613` is the resolution it was waiting for, so it can now be placed in sequence. **That placement is beat work and has not been done.**
**G16 · Jonah 4 — Jonah 4 — LOW (AUTHORED 2026-08-01 as 1614, not yet arc-wired · whole chapter, nothing excluded)** — the missing **capstone** now exists; the `1094→1167→1100` arc can close on `1614` instead of ending at resolution without its ironic coda.

*(Also enrichment-only, not scheduled: Numbers 21 bronze serpent; Jeremiah 36 the burned scroll — the siege stories re-ground themselves.)*

---

## 4. Production tiers

> **2026-07-31:** the tiers below were written against the 2026-07-16 corpus. G1-G11 have since been authored, so the "Build after targeted gap completion" and "Wait" tiers have largely cleared — but **no beats have been written for any of the new stories**. Arcs that are now *buildable* are not yet *built*.

> **Tier renamed per Adam (2026-07-16):** the "one seam away / build after 1–2 stories" tier is now **"Build after targeted gap completion,"** because several of these arcs need **two or more** stories, not one. Accurate naming matters — this doc guides future sessions.

### Build now — no authoring needed
Continuity-complete narrative spines. Beats can be written against today's corpus without future rework.
- **Peter** — the two Acts arcs are clean (the gospel arc carries a minor denial caveat; see below).
- **Esther + Mordecai** (fullest single scroll, 7 beats) · **Ezra + Nehemiah** (Return/Rebuild; dedupe first) · **Jeremiah** (5 self-grounding episodes) · **Elijah + Elisha** (mantle seam complete both sides).
- **Solomon · Gideon · Samuel · Hannah · Saul · Jonah · Mary · John the Baptist · Job** (narrative frame).
- **Paul** — as **two split sub-arcs** (*Missionary Journeys* / *Prisoner to Rome*), not one chain (see §10).
- Already shipped & verified: **Daniel · Joseph · Ruth · David (arcs 1–7)**.

### Build after targeted gap completion → **GAPS NOW FILLED (2026-07-31)**
High-value arcs blocked by specific missing stories (often **more than one**). _Every blocking story listed here has since been authored — these arcs are now buildable, and building them (writing the beats) is the outstanding work._
- **Moses (full)** ← Passover (Ex 7–12, G1 → **1576**) **and** flight to Midian (Ex 2:11–25, G8 → **1583**); later spies-guest/Korah (G11 → **1596**) for the back-half. **Buildable.**
- **David fall/rebellion** ← Bathsheba (2 Sam 11, G3 → **1581**) **and** Absalom (2 Sam 18, G7 → **1582**). **Buildable.**
- **Jacob (full life)** ← reconciliation (Gen 33, G2 → **1573**) **and** stolen blessing (Gen 27, G9 → **1572**). **Buildable.**
- **Joshua Conquest** ← the Gibeonite covenant (Josh 9, G5 → **1578**), with the Achan/Ai resolution (Josh 7:16–8:29, G6 → **1577**). **Buildable.**
- **Abraham** — Gen 19 (G15) has been **authored as 1613** (2026-08-01), so `1487` no longer has to be held standalone and can be placed in sequence. **Buildable.**

### Wait — not viable yet → **CLEARED (2026-08-01)**
- **Samson** — needed Delilah/capture (G4); **authored as 1574**. Now buildable.
- **Noah** — needed the Flood itself (G10); **authored as 1571**. Now buildable.
- **Hezekiah · Josiah** — **no longer waiting (2026-08-01).** Each has its third beat: Hezekiah's illness (G13 → **1611**, 2 Kings 20:1-11) and Josiah's great Passover (G14 → **1612**, 2 Chronicles 35:1-19). Both arcs clear the 3-story floor and are **buildable**; the beats themselves are still unwritten. Note the narrowed anchors: 2 Kings 20:12-21 and 2 Chronicles 35:20-27 remain absent from the corpus.

### Thematic track — different voice, not narrative beats
No chronological spine. Theme/Teaching journeys; wisdom literature remains an unsolved transition-voice open cell.
- **Psalms** (Comfort · Praise · lament→trust movements) · **Isaiah · Hosea · Amos · Habakkuk** (oracle) · **James · Hebrews · Paul's epistles** (teaching) · **Ecclesiastes** (wisdom — open cell).
- **Jesus** — the flagship, and a **curation** pass (74 → ~30, one render per beat, cross-gospel ordering), **not** a gap problem. All 14 arc phases are covered.

---

## 5. Master character table

Stories column = total → distinct after dedupe. Verdict reflects the **corrected** full-corpus conclusion.

> **2026-07-31:** struck-through gaps have been authored; the produced story ID follows. "Buildable" means the blocking story now exists — the beats themselves are still unwritten.
>
> **2026-08-01:** G13-G16 have since been authored as **1611-1614**, so no row reads "still absent" any more. The narrowed-anchor remainders (2 Kings 20:12-21, 2 Chronicles 35:20-27, Genesis 19:30-38) ARE still absent and are noted in the affected rows.

| Character | Stories | Dominant duplicate clusters | True gap (verified) | Sev. | Verdict |
|---|---|---|---|---|---|
| **Patriarchs — Genesis** ||||||
| Joseph | 9 → 6 | Gen 37 ×3, Gen 40 ×2 | none — every chapter self-recaps | — | Build now |
| Abraham/Abram | 12 → 7 | Gen 12 ×2, Gen 18 ×2, Gen 22 ×3 | ~~Sodom (Gen 19, G15)~~ → **1613** (Gen 19:1-29; **19:30-38 still absent**). Covenant chapter → **1615** (Gen 17). `1487` can now be placed in sequence | — | Buildable (2026-08-01) |
| Jacob | 9 → 6 | Gen 28 ×2, Gen 32 ×3 | ~~Esau reconcile (Gen 33) + blessing (Gen 27)~~ → **1573 + 1572** | — | Buildable (2026-07-31) |
| Hagar | 4 → 2 | Gen 16 ×2, Gen 21 ×2 | none (thin 2-beat pair) | — | Build now (thin) |
| Noah | 3 → 2 | Gen 6 ×2 | ~~the Flood itself (Gen 7–8)~~ → **1571** | — | Buildable (2026-07-31) |
| Isaac | 2 | none (birth filed under Sarah `1312`) | thin pair (`1312` birth + `1428` Rebekah) | LOW | Thin |
| **Exodus — Conquest** ||||||
| Moses | 24 → 18 | Red Sea ×4, Bush ×2, Manna ×2 | ~~Passover (Ex 7–12) · flight (Ex 2) · Korah~~ → **1576 · 1583 · 1596**; spies = guest beat `1049` | — | Buildable (2026-07-31) |
| Joshua | 18 → 11 | Jericho ×4, Josh 24 ×3, Josh 1/3 ×2 | ~~Gibeonites (Josh 9) + Achan/Ai (Josh 7:16–8:29)~~ → **1578 + 1577** | — | Buildable (2026-07-31) |
| Caleb | 3 → 2 | Num 13 ×2 | none — `1173` self-recaps Num 14 | — | Build now |
| Aaron · Phinehas | 2 · 2 | none | none — thematic pairs, self-contained | — | Build now (thin) |
| Rahab | 2 → 1 | Josh 2 ×2 | collapses to a single node | — | Single node |
| **Judges — Rise of the Monarchy** ||||||
| Gideon | 6 → 3 | Call ×2, Battle ×2 | none — call→fleece→battle clean | — | Build now |
| Deborah | 2 | none (Judges 4 + 5) | none — thin; combine with Gideon | — | Build now (thin) |
| Samson | 2 → 3 | none | ~~Delilah & capture (Judges 16:4–22)~~ → **1574** | — | Buildable (2026-07-31) |
| Ruth | 9 → 4 | each chapter ×2–3 | none — gate scene exists (Boaz `1418`) | — | Build now (shipped) |
| Samuel | 7 → 4 | Call ×4, Ebenezer ×2 | none — Ebenezer recaps the ark | — | Build now |
| Saul | 4 | none | none — death carried by David's lament | — | Build now |
| Hannah | 4 → 3 | Song ×2 | none — clean within 1 Sam 1–2 | — | Build now |
| David | 42 → arcs | many (per-arc) | ~~Bathsheba (2 Sam 11) · Absalom (2 Sam 18)~~ → **1581 · 1582** | — | Arcs 1–7 shipped · fall now buildable |
| Solomon | 10 → 9 | Wisdom ×2, Dedication parallels | none — ends on temple glory | — | Build now |
| **Divided Kingdom — Prophets** ||||||
| Elijah | 10 → 5 | Zarephath ×3, Carmel ×3, Horeb ×2 | none — call of Elisha bridgeable | — | Build now (shipped) |
| Elisha | 8 → 5 | Army of Fire ×3 | none — spine self-bridges both jumps | — | Build now |
| Naaman · Micaiah | 4→1 · 2→1 | ×4 · parallel ×2 | single-scene satellite beats | — | Guest beat |
| Jeremiah | 16 → 11 | Potter ×2, Letter ×2 | scroll (Jer 36) — enrichment only | LOW | Build now |
| Hezekiah | 3 → 2 | Letter ×2 | ~~illness (2 Kings 20, G13)~~ → **1611** (2 Kgs 20:1-11; **20:12-21 still absent**) | — | Buildable (2026-08-01) |
| Josiah | 3 → 2 | Book found ×2 | ~~Passover (2 Chr 35, G14)~~ → **1612** (2 Chr 35:1-19; **35:20-27 still absent**) | — | Buildable (2026-08-01) |
| Isaiah | 17 → 9 | "Wings" ×3, +4 pairs | 1 narrative (the call); rest oracle | — | Thematic |
| Jehoshaphat | 4 → 1 | 2 Chr 20 ×4 | one event, four renders | — | Single event |
| Hosea · Amos · Habakkuk | 3 · 2→1 · 3→2 | oracle overlaps | pure oracle — no spine | — | Thematic |
| **Exile — Return** ||||||
| Daniel | 16 → 9 | Lions' den ×6, Wall ×2 | none — spine complete end to end | — | Build now (shipped) |
| Esther + Mordecai | 10 → 8 | "If I Perish" ×3 | none — decree self-supplied in prose | — | Build now |
| Ezra + Nehemiah | 19 → 13 | Foundation ×3, Neh 8 cross-file | none — Ezra→Nehemiah intact | — | Build now |
| Jonah | 4 → 3 | Jonah 1 ×2 | ~~Jonah 4 (G16)~~ → **1614** (whole chapter); the capstone now exists | — | Build now |
| Shadrach+ · Nebuchadnezzar | 4→3 · 3→2 | Dan 3 · Dan 4 | single-chapter guest clusters | — | Guest beat |
| Ezekiel · Haggai · Zechariah | 5 · 2 · 2 | Zech = 2 people! | oracle/vision — no spine | — | Thematic |
| **Gospels — Acts — Epistles** ||||||
| Peter | 16 → 10 | Acts 12 ×4, Cornelius ×2 | ~~no denial story~~ → **1565** (+ confession **1563**) | — | Build now (2 Acts arcs + gospel arc) |
| Jesus | 74 → ~30 | massive (×4/×3 across) | none material — a curation problem | — | Flagship / curate |
| Mary | 5 → 3 | Annunciation ×2 | none — Nativity borrowable (`1004`) | — | Build now |
| John the Baptist | 3 | none | none — complete rise-to-death arc | — | Build now |
| Paul | 36 → 8 narr. | Conversion ×2, Shipwreck ×3 | arrest recapped in `1344` — split the arc | MED | Build now (split) |
| Stephen · Philip · Early Church | 2 · 2 · 2 | none | none — form an Acts 7–8 chain together | — | Build now (thin) |
| John (apostle) · James · Hebrews | 6→5 · 3 · 4→3 | Rev 21 ×2, Heb 12 ×2 | all writings — no biographical spine | — | Thematic |

\* Abraham is Build-now provided `1487` (Sodom intercession) is held as a standalone rather than placed mid-arc.

*Omitted for space (all continuity-safe, none arc-length): Thomas & Mary Magdalene (cross→resurrection diptychs), Jairus (single event). The 67 single-story satellite characters (Sarah, Boaz, Isaac, Agabus, Miriam, Jethro, Zedekiah, Cornelius, Huldah, Simeon, Elizabeth…) are gap-fillers and guest beats, not standalone arcs.*

---

## 6. Duplicate-anchor clusters (dedupe before building)

The heaviest alternate-render clusters, with the recommended keeper where the audit named one:

| Anchor / event | Renders | Keep |
|---|---|---|
| Daniel — lions' den (Dan 6) | `816` `817` `1114` + subsets `1492` `1378` `1461` (×6) | `1114` |
| Jesus — "Rest for the Weary" (Matt 11:28–30) | `801` `821` `824` `1000` (×4) | curate to 1 |
| Jesus — Woman at the Well (John 4) | `810` `814` `1113` `1537` (×4) | curate to 1 |
| Naaman (2 Kings 5:1–14) | `1053` `1061` `1119` `1510` (×4) | `1510` |
| Jehoshaphat (2 Chr 20 — one battle) | `1097` `1198` `1547` `1377` (×4) | `1097` |
| Moses — Red Sea (Ex 14) | `1048` `1056` `1117` `1527` (×4) | `1117` (`1527` = B29 ref) |
| Joshua — Jericho (Josh 6) | `1118` `1455` `1507` `1532` (×4) | `1507` |
| Isaiah — "Wings Like Eagles" (Isa 40:28–31) | `806` `1071` `1079` (×3) | `806` |
| Ezra — foundation laid (Ezra 3:10–13) | `1182` `1366` `1459` (×3) | `1182` |
| Jesus — feeding of 5,000 | `1081` `1289` `1538` (×3, diff. gospels) | curate to 1 |
| Abraham — Binding of Isaac (Gen 22) | `1032` `1040` `1116` (×3) | `1032` |
| Elijah — Zarephath / Carmel / Horeb | ×3 / ×3 / ×2 | `1039`/`1534` · `1065`/`1073` · `825` |
| Samuel — call (1 Sam 3) | `818` `822` `1216` `1495` (×4) | `1216` |

*(Full per-character dedupe picks are recorded in the era-audit findings; this table lists the highest-count clusters. `outgoing_beats.json` already keys beats per-EDGE/per-anchor, so dedupe affects which single render an arc references — one canonical asset per anchor.)*

---

## 7. Data-hygiene findings

Label splits and mis-filings that fragment thematic pools, double-count, or hide stories from character-scoped searches. **Fix before building the affected pools.**

1. **`Psalmist` vs `The Psalmist`** — same anonymous psalm-writer under two labels; already yields cross-label duplicate coverage of Psalm 100 (`1306`/`805`) and Psalm 121 (`1549`/`1010`). Merge into `Psalmist`. (Also Psalm 91 is triple-covered within `Psalmist`: `1285`/`1287`/`1536`.)
2. **`Zechariah` conflates two different people** — `1238` (Zech 9, the post-exilic **prophet**) and `1368` (Luke 1, **John the Baptist's father**, the priest). Split; `1368` belongs to the Nativity/John-the-Baptist thread.
3. **Ecclesiastes split across `The Preacher` and `Solomon`** — `1324`/`1476` under The Preacher, `1225`/`1226` under Solomon. Consolidate before any wisdom-theme pool.
4. **`Abram` / `Abraham`** — the same man, split at the Gen 17 rename seam. Audit and curate as one arc.
5. **Mary-of-Bethany mis-filed under Mary the mother** — `827` "Mary and Martha" (Luke 10) is Mary **of Bethany**; exclude it from the mother-of-Jesus spine.

---

## 8. False positives discovered during full-corpus verification

Gaps flagged by character-scoped era-audits that the full-corpus verification **overturned**. These are **NOT gaps** and must not resurface in future planning:

| Flagged as missing | Reality | Evidence |
|---|---|---|
| "No Isaac character at all" (Patriarchs audit) | **Isaac exists** — 2 stories | `1428` (In the Field at Evening, Gen 24) + birth via `1312` |
| Isaac's birth (Gen 21) | **Exists**, filed under **Sarah** | `1312` "God Has Made Me Laugh" (Gen 21:1–7) |
| Ruth 4:1–12 redemption at the gate | **Exists**, filed under **Boaz** | `1418` "Boaz at the Gate" (Ruth 4:1–12) |
| Paul's arrest / how a free preacher became a prisoner | **Narratable-over** — recapped in prose | `1344` opens "brought up from the temple courts to the Roman barracks…"; also `1403` (Agabus foretells the binding, Acts 21) |
| The spies event (for Moses) | **Event exists** (Caleb POV) — usable as a guest beat | `1049` "The Report of the Spies" (Num 13:25–33) |

**Lesson:** a character-scoped search is a discovery aid, not a completeness check. See §10.

---

## 9. Definitions — five distinct findings this audit keeps separate

These are deliberately **not** the same thing, and conflating them corrupts planning:

1. **Missing story** — a canonical event genuinely absent from the *entire* corpus under any character (e.g. Gen 33 Esau reconciliation, Ex 7–12 Passover). Only these enter the gap backlog.
2. **Duplicate render** — the same scripture anchor authored more than once (e.g. lions' den ×6). A curation/dedupe concern, never a gap. One asset stays canonical.
3. **Cross-character story ownership** — the story exists, but under a *different* `primaryCharacterDisplayName` (e.g. Ruth's gate scene under Boaz `1418`). Not a gap; a search-scope artifact.
4. **Thin character pool** — the character has too few *distinct* stories to form a 3–6-story arc (e.g. Samson 2, Hezekiah 2, Deborah 2). Not necessarily a continuity gap; may just need one more beat, or fold into a broader journey.
5. **Thematic rather than narrative material** — oracle / psalm / epistle / parable with no chronological spine (e.g. Isaiah oracles, the Psalms, James). A Theme/Teaching journey surface, not a narrative-gap surface.

---

## 10. Audit Decisions (ratified)

Durable rulings recorded so future sessions inherit them:

1. **Story ownership is not limited to `primaryCharacterDisplayName`.** A pivotal scene may be filed under another figure.
2. **Character-scoped searches are discovery aids only.** Arc curation MUST perform a **full-corpus scripture-anchor and participant search** before declaring a gap. (Five false positives in §8 came from skipping this.)
3. **A story may appear in another character's journey** when that character is a *central participant* (e.g. Naaman `1510` as a guest beat in an Elisha arc; Caleb's spies `1049` in a Moses arc).
4. **One story asset remains canonical.** Journeys **reference** the existing asset; they never create a duplicate story version to "own" a beat.
5. **Terminal stories receive no outgoing beat.** The final story of an arc is deliberately absent from `outgoing_beats.json` (absence = open, not overlooked).
6. **Missing tail/capstone stories do not block earlier safe beats.** A missing *end* (e.g. Jonah 4) never invalidates the safe beats before it.
7. **A story that ends unresolved must either lead to its resolution or stay outside the arc.** (e.g. Abraham's Sodom intercession `1487` — held standalone until Gen 19 exists; Joshua's Ai defeat `1294` — kept out of a continuous arc until Josh 7:16–8:29 resolves it.)
8. **Existing prose may carry a skipped event only when the next story explicitly and honestly re-grounds it** (the "narratable-over" test — verified in prose, not assumed).
9. **Transition beats must never summarize an entire missing central event merely to manufacture continuity.** If bridging a seam requires narrating an untold central event, the story must be authored first — the beat may not paper over it.

---

## Appendix — provenance

Ten parallel era-audits (each reading story prose on both sides of every seam) → a full-corpus scripture-anchor verification pass → Jesus mapped separately against the 14-point arc. Posture: editor of a published chronological Bible.

**Companion machine-readable backlog:** [`assets/stories/journey_gap_backlog.json`](../../assets/stories/journey_gap_backlog.json). Each entry carries tooling-queryable classification fields alongside the prose rationale — `gapType` (continuity_blocker · paired_resolution · thin_pool_fill · guest_beat_available · standalone_hold · capstone), `blocksJourneyBuild` (bool), and `estimatedStoriesRequired` (int) — so questions like "which gaps block an active arc?" or "which are guest-beat-solvable?" can be answered without parsing English.

Related: `docs/JOURNEY_DOCTRINE.md`, `docs/JOURNEY_TRANSITION_VOICE.md`, `assets/stories/outgoing_beats.json`.
