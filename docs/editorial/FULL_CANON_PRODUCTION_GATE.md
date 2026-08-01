# Bible PAL — Full-Canon Production Gate

> **Status:** Approved planning gate (pending Adam's sign-off), 2026-07-16 — **all 22 candidates produced (status-refreshed 2026-07-31); CG23 added and authored as 1615 on 2026-08-01, text-approved and `approved_for_audio` — audio not yet rendered**
> **Model:** Claude Opus 4.8, high effort
> **Companion machine-readable file:** [`assets/stories/canon_production_gate.json`](../../assets/stories/canon_production_gate.json)
>
> **Authority:** This document is **authoritative for near-term story production.** For Journey Beat *continuity* the authority is [`JOURNEY_GAP_AUDIT.md`](JOURNEY_GAP_AUDIT.md) + [`journey_gap_backlog.json`](../../assets/stories/journey_gap_backlog.json). The [`FULL_CANON_GAP_AUDIT_REFERENCE.md`](FULL_CANON_GAP_AUDIT_REFERENCE.md) is a maximalist reference inventory only and authorizes nothing.

This gate is the smallest near-term set of stories that fills the most conspicuous holes in the corpus, protects Journey Beat continuity, and takes the cheap adult-parity wins — without redoing what the approved Journey Gap Audit already settled. It supersedes the rendered artifact produced during the gate session.

---

## 0. Status refresh — 2026-07-31

> **THIS GATE IS SPENT. DO NOT RE-ISSUE ANY OF THE 22 CANDIDATES FOR PRODUCTION.**

All 22 approved candidates have been produced and registered in `manifest.json`. Until this refresh every record still read `productionStatus: not_started`, so consuming the gate as-is would have authored ~22 duplicate stories. Each candidate now carries `productionStatus: integrated` plus `productionId` / `productionAnchor` / `productionBibleStoryKey` in the companion JSON.

Every mapping below was derived from — not assumed against — the corpus at master `fe09b63808c0ab4a798cae9a3087955b9a1320cb`: `meta_<id>.json` **and** `manifest.json` agree on title, anchor and `bibleStoryKey` for all 22.

**What is preserved unchanged:** `gateDate`, every `coverageStatus` value (these record the *2026-07-16 gate-time* finding, not today's coverage), all rationale, cautions, priorities, difficulty ratings, the three overturned findings, and the CG08 / CG19 scope decisions.

**What still remains open from this document:** only the **Enrichment adjunct** — Isaiah 9:2-7 and Psalm 1, both re-verified absent on 2026-07-31.

**Journey items (§4):** G1–G10 and G11 have all been authored — see [`JOURNEY_GAP_AUDIT.md`](JOURNEY_GAP_AUDIT.md) §0. As of this refresh `fillNow` and `stronglyConsider` were empty and only G12–G16 remained open; the eleven authored items are **authored, not integrated** — none is wired into an arc yet. *(SUPERSEDED by §0.1: G13–G16 were authored on 2026-08-01 as 1611–1614, leaving G12 alone open.)*

---

## 0.1 Gate addition and outcome — 2026-08-01

> **CG23 · Genesis 17 — approved by Adam and added as a 23rd candidate.** Added at `productionStatus: drafting` with no `productionId`, recorded **before any prose existed**; later the same day authored as story **1615** and set to `awaiting_approval`. *(Superseded by §0.2: text-approved the same day and now `approved_for_audio`.)*

Genesis 17 was **not** gate-approved before today. Its only prior provenance was [`FULL_CANON_GAP_AUDIT_REFERENCE.md`](FULL_CANON_GAP_AUDIT_REFERENCE.md), which is reference-only and **authorizes nothing**. Adam approved it on 2026-08-01 on two grounds:

1. **Coverage.** Verified absent — 0 meta hits for Genesis 17 across `scriptureAnchor`, `bibleStoryKey`, `title`, `bibleSourceRef` and `scriptureAnchorId` in either lane, and absent from `scripture_anchor_registry.json`, `anchor_coverage.json` and `kid_anchor_registry.json`. The corpus holds Genesis 16 (`1269`, `1405`) and Genesis 18 (`1487` + the Genesis 18 pair) but not the covenant chapter between them.
2. **Data hygiene.** [`JOURNEY_GAP_AUDIT.md`](JOURNEY_GAP_AUDIT.md) §7 finding **#4** records that `Abram` / `Abraham` are the same man split at the **Genesis 17 rename seam**, to be audited and curated as one arc. The corpus holds both sides of that seam and no story of the seam itself.

`_meta.counts.approvedCandidates` moves **22 → 23**; `integratedCandidates` **stays 22** because CG23 is not integrated. Nothing about the original 22 changed. `productionWave` is `null` — CG23 belongs to none of the six recorded waves and no new wave was invented for it.

**Outcome (same day):** authored as **1615 "God's Covenant with Abraham"** [Genesis 17, whole chapter, no verses excluded], batch `PAL_DAILY_2026-08-01_BATCH_I`, registered in `manifest.json` **text-first** — WEB + KJV, `audioFilePath` and `reflectionAudioPath` blank. `productionStatus` `drafting → awaiting_approval`, with `productionId: 1615`, `productionAnchor: "Genesis 17"` and `productionBibleStoryKey: "covenant_of_circumcision_abram_becomes_abraham"`, all verified against `meta_1615.json` **and** `manifest.json`.

Chronological placement is load-bearing and was preserved: 1615 sits after the Genesis 16 stories (`1269`, `1405`) and before the Genesis 18 material (`1487`), because the chapter *is* the rename seam of §7 finding #4.

**Journey items (§4) — 2026-08-01:** G13–G16 were queued as `planned` in `fillNow` with owner-approved **narrowed** anchors, then authored the same day as stories **1611–1614**. They now read `authored`, carry their `productionId`, and appear in **none** of the three fill lists. `fillNow []` · `stronglyConsider []` · `deferUntilArcApproached [G12]`; `_meta.journeyBacklogReference` mirrors that exactly. **G12 is the only open backlog item left.** Their texts were owner-approved on 2026-08-01; they stay `authored`, not `integrated`, because no journey beat has been written.

---

## 0.2 Text lock — 2026-08-01

> **CG23 · `awaiting_approval` → `approved_for_audio`.** Adam and ChatGPT approved the text of story **1615** on 2026-08-01.

This is **eligibility bookkeeping only.** `approved_for_audio` records that 1615 may enter a *later* audio operation. It does **not** mean audio exists:

- no audio was rendered and **no ElevenLabs call was made**;
- `audioFilePath` and `reflectionAudioPath` are still `""` on both manifest entries;
- CG23 is deliberately **NOT** `integrated`, so `_meta.counts.integratedCandidates` **stays 22**;
- `productionId: 1615`, `productionAnchor: "Genesis 17"`, `productionBibleStoryKey: "covenant_of_circumcision_abram_becomes_abraham"` and `productionWave: null` are all unchanged;
- `_meta.counts.approvedCandidates` stays **23**.

The same lock applies to the four journey items — see [`JOURNEY_GAP_AUDIT.md`](JOURNEY_GAP_AUDIT.md) §0.2. Their texts are approved, but they remain `authored`: the backlog's `statusVocabulary` has no `approved_for_audio` value and none was invented for it.

---

## 1. Executive decision

**The shortlist is ready.** 22 stories passed the gate; 8 candidate groups were rejected or deferred; **three prior Full-Canon Gap Audit findings were overturned** during verification.

**Overturned findings** (exactly the false positives the manual-salvage caveat warned about):
- **Mary & Martha** — already in the adult lane (story **827**) plus kid **1863**. Not a parity gap. **Closed.** Story 827 is present, correctly anchored, passed the 800-series audit, and remains the canonical adult implementation.
- **Widow's Mite** — already in the adult lane (story **1444**) plus kid **1872**. Not a parity gap. Closed.
- **Appearance to the Ten** — downgraded from Essential to partial/sufficient: Emmaus (1115) and the Thomas appearance (adult **1122** + kid **1871**) already bracket that room. Deferred.

**Verification wins:** the salvaged-division essentials all hold — Bronze Serpent, Peter's Confession, and David-at-En-gedi are confirmed genuinely absent from both lanes (0 meta hits across title, bibleStoryKey, anchor, and sceneBeats). The Rich-Man-&-Lazarus / OT-Joseph / Cave-of-Adullam name-collisions were cleared, not accepted.

---

## 2. The production-gate shortlist

Ranked by conspicuousness of the hole, then journey/arc leverage, then production leverage. Every "absent" verdict was verified against both lanes and all meta fields during this gate.

| # | Story | Reference | Source | Coverage | Lane | Priority | Difficulty | Wave | Must precede beats | Produced |
|---|-------|-----------|--------|----------|------|----------|-----------|------|--------------------|--------|
| 01 | The Fall | Genesis 3:1-24 | net new essential | absent both lanes | both | high | very heavy | Wave 1 | — | **1566** |
| 02 | Cain and Abel | Genesis 4:1-16 | net new essential | absent both lanes | adult | high | heavy | Wave 1 | — | **1567** |
| 03 | Peter's Denial and the Rooster | Luke 22:54-62 / John 18:15-27 | net new essential | absent both lanes | both | high | heavy | Wave 1 | yes | **1565** |
| 04 | Peter's Confession at Caesarea Philippi | Matthew 16:13-20 | salvaged division verification | absent both lanes | both | high | standard | Wave 1 | yes | **1563** |
| 05 | John 1 Prologue — The Word Became Flesh | John 1:1-18 | net new essential | absent both lanes | both | high | standard | Wave 1 | — | **1562** |
| 06 | David Spares Saul at En-gedi | 1 Samuel 24 | salvaged division verification | absent both lanes | both | high | standard | Wave 1 | — | **1564** |
| 07 | The Bronze Serpent | Numbers 21:4-9 | salvaged division verification | absent both lanes | both | medium | heavy | Wave 1 | — | **1568** |
| 08 | Jesus Before Pilate — 'What Is Truth?' | John 18:28-19:16 / Luke 23:1-25 | net new essential | absent both lanes | adult | high | heavy | Wave 4 | yes | **1586** (re-scoped) |
| 09 | Barabbas and the Crowd's Choice | Matthew 27:15-26 / Mark 15:6-15 | net new essential | absent both lanes | adult | high | heavy | Wave 4 | yes | **1587** |
| 10 | Joseph's Dream — the Angel Appears to Joseph | Matthew 1:18-25 | net new essential | absent both lanes | both | medium | standard | Wave 1 | — | **1569** |
| 11 | Rehoboam — the Kingdom Splits | 1 Kings 12 | net new essential | absent both lanes | adult | medium | standard | Wave 4 | — | **1590** |
| 12 | The Flight to Egypt & Herod's Massacre | Matthew 2:13-18 | net new essential | adult missing partial coverage | adult | medium | heavy | Wave 4 | — | **1588** |
| 13 | The Rich Man and Lazarus | Luke 16:19-31 | net new essential | absent both lanes | adult | medium | heavy | Wave 4 | — | **1585** |
| 14 | The Rich Fool | Luke 12:13-21 | net new essential | adult missing partial coverage | adult | medium | standard | Wave 5 | — | **1580** |
| 15 | The Ten Virgins | Matthew 25:1-13 | net new essential | absent both lanes | both | medium | standard | Wave 5 | — | **1575** |
| 16 | The Sheep and the Goats | Matthew 25:31-46 | net new essential | absent both lanes | both | medium | standard | Wave 5 | — | **1589** |
| 17 | The Sower | Mark 4:1-9 / Matthew 13:1-23 | adult parity | adult missing kid exists | adult | high | standard | Wave 3 | — | **1570** |
| 18 | The Persistent Widow | Luke 18:1-8 | adult parity | adult missing kid exists | adult | medium | standard | Wave 3 | — | **1584** |
| 19 | Joseph in Egypt — Potiphar's House & Prison | Genesis 39-40 | adult parity | adult missing kid exists | adult | medium | heavy | Wave 3 | yes | **1579** (+1178/1389) |
| 20 | The Workers in the Vineyard | Matthew 20:1-16 | net new essential | absent both lanes | both | low | standard | Wave 5 | — | **1605** |
| 21 | The Weeds (Tares) Among the Wheat | Matthew 13:24-30, 36-43 | net new essential | absent both lanes | both | low | standard | Wave 5 | — | **1606** |
| 22 | The Pearl of Great Price | Matthew 13:45-46 | net new essential | absent both lanes | both | low | standard | Wave 5 | — | **1610** |
| 23 | God's Covenant with Abraham — Abram Becomes Abraham | Genesis 17 | net new essential | absent both lanes | adult | high | heavy | — | — | **1615** _(approved_for_audio — text-first, no audio rendered)_ |

_Rationale and cautions for each item are in `canon_production_gate.json`._

### The Peter arc — special finding

The charcoal-fire seam is real and unusually strong: the **restoration already exists** (story **1130** "Three Times by the Sea," John 21:15-19, and "Breakfast on the Shore of Broken Hearts," John 21:1-14). The corpus holds the healing without the wound it heals — the three-fold "do you love me" answers three denials the listener never hears.

```
Call (1175)  →  Water (1124)  →  Confession (1563)  →  Denial (1565)  →  Restoration (1130, exists)
```
Recommended arc: **Call → Water → Confession → Denial → Restoration.** The two new stories slot into an arc whose bookends are already built; authoring the denial retroactively charges the existing restoration. No beats written — this is the recorded arc consequence only.

_2026-07-31: both new stories now exist — Confession = **1563** "You Are the Christ," Denial = **1565** "The Rooster and the Fire." The arc is authorable; the beats themselves are still unwritten (neither ID appears in `outgoing_beats.json`)._

---

## 3. Rejected & deferred candidates

| Candidate | Reference | Reason |
|-----------|-----------|--------|
| Mary and Martha | Luke 10:38-42 | **ALREADY COVERED** — Adult story 827 (key mary_and_martha) AND kid 1863 both exist. My full-canon audit wrongly listed this as an adult-parity gap — overturned. Closed: 827 passed the 800-series audit (rated OK), is correctly anchored, uses an approved narrator, and remains the canonical adult implementation. |
| The Widow's Mite | Mark 12:41-44 / Luke 21:1-4 | **ALREADY COVERED** — Adult story 1444 (Two Small Coins, Luke 21 parallel) AND kid 1872 both exist. Wrongly listed as a parity gap — overturned. |
| Appearance to the Ten — 'Peace Be With You' | John 20:19-23 / Luke 24:36-49 | **PARTIAL, SUFFICIENT FOR NOW** — Bracketed by Emmaus (1115) and the Thomas appearance (adult 1122 + kid 1871), which covers the same room a week later. Downgraded from Essential to important/partial. The genuine remainder is the commissioning / 'receive the Holy Spirit' content — worth a later story, not a near-term hole. |
| Unto Us a Child Is Born | Isaiah 9:2-7 | **ENRICHMENT, NOT NARRATIVE** — A prophetic oracle, not a story. Strong Advent contemplative piece — route to an enrichment batch, don't gate it as a narrative omission. |
| Psalm 1 — The Two Ways | Psalm 1 | **ENRICHMENT** — The gateway psalm; contemplative, not narrative. Enrichment batch. |
| 'Give Us a King' | 1 Samuel 8 | **SUPERSEDED 2026-07-31 — produced as story 1599** "Israel Demands a King" (1 Samuel 8:1-22), registered in `manifest.json`. _Original deferral: LOW IMMEDIATE VALUE — verified absent at gate time, important-supporting, but not conspicuous to an ordinary user and no journey pressure. Near-term-eligible, not gating._ |
| Jonathan's Arrows / Farewell | 1 Samuel 20 | **PARTIAL / DUPLICATE-ADJACENT** — Kid 1846 bundles 1 Sam 18-20; adult covenant stories 1052/1060 cover the initial covenant (18:1-4). The farewell itself is a thin remainder — defer. |
| The remaining ~600 gaps | various | **DEFER — DO NOT GATE JOURNEYS** — Minor episodes, enrichment passages, mood additions, completionist material. None threatens journey continuity; hold per JOURNEY_DOCTRINE. |

---

## 4. Already-verified Journey items (carry forward, no re-gate)

The approved G1-G16 backlog enters production on its existing verification. **Authoritative records: [`journey_gap_backlog.json`](../../assets/stories/journey_gap_backlog.json) — not duplicated here.** Grouped by Adam's approved fill order.

> **2026-07-31 status refresh — G1-G11 are AUTHORED. Do not re-issue them.** The `fillNow` and `stronglyConsider` lists are now empty and G11 has left `deferUntilArcApproached`. Only **G12-G16** remain open. Every G-item below carries its produced story ID; "authored" means the story exists and is registered, **not** that the gap is closed — none of the eleven is wired into an arc yet (no `outgoing_beats.json` entry, no `assets/stories/journeys/*.json` reference), so the journey-build work remains.

**Fill now — G1-G7** — _all authored (2026-07-31); list now empty_

| G | Story | Reference | Character / arc | Note |
|---|-------|-----------|-----------------|------|
| G1 | Passover & the Plagues | Exodus 7-12 | Moses (moses_arc_1) | Adult lane — kid 1907 already exists. HEAVY (death of the firstborn). **AUTHORED as 1576** "The Passover and the Plagues" (not yet arc-wired). |
| G2 | Jacob & Esau Reconcile | Genesis 33 | Jacob (jacob_full_arc) | Pairs with G9. STANDARD. **AUTHORED as 1573** "Esau Ran to Meet Him" (not yet arc-wired). |
| G3 | Bathsheba & Uriah | 2 Samuel 11 | David (david_arc_7) | Pairs with G7. VERY HEAVY (adultery/murder) — adult only. **AUTHORED as 1581** "Bathsheba and Uriah" (not yet arc-wired). |
| G4 | Delilah & Samson's Capture | Judges 16:4-22 | Samson (samson_arc) | HEAVY (betrayal/blinding) — adult; kid subtraction very hard. **AUTHORED as 1574** "He Told Her All His Heart" (not yet arc-wired). |
| G5 | The Gibeonite Covenant | Joshua 9 | Joshua (joshua_conquest_arc) | Pairs with G6. STANDARD. **AUTHORED as 1578** "The Gibeonite Covenant" (not yet arc-wired). |
| G6 | Achan's Judgment & the Capture of Ai | Joshua 7:16-8:29 | Joshua (joshua_conquest_arc) | HEAVY (divine judgment). Resolves the 1294 cliffhanger. **AUTHORED as 1577** "Achan's Judgment and the Capture of Ai" (not yet arc-wired). |
| G7 | Absalom's Death — 'O my son' | 2 Samuel 18 | David (david_rebellion_arc) | Terminal grief beat. HEAVY. Pairs with G3. **AUTHORED as 1582** "O My Son Absalom" (not yet arc-wired). |

**Strongly consider — G8-G10** — _all authored (2026-07-31); list now empty_

| G | Story | Reference | Character / arc | Note |
|---|-------|-----------|-----------------|------|
| G8 | Moses Flees to Midian | Exodus 2:11-25 | Moses (moses_arc_1) | Opening seam of the Deliverance arc. **AUTHORED as 1583** "Moses Flees to Midian" (not yet arc-wired). |
| G9 | The Stolen Blessing | Genesis 27 | Jacob (jacob_full_arc) | Origin of the Jacob-Esau conflict. Pairs with G2. **AUTHORED as 1572** "The Stolen Blessing" (not yet arc-wired). |
| G10 | The Flood | Genesis 7-8 | Noah (noah_arc) | Also the primeval-arc turning point (connects to Fall/Cain above). **AUTHORED as 1571** "The Flood" (not yet arc-wired). |

**Defer until arc approached — G11-G16** — _G11 authored (2026-07-31); **G13-G16 authored 2026-08-01 as 1611-1614**; G12 alone still deferred_

| G | Story | Reference | Character / arc | Note |
|---|-------|-----------|-----------------|------|
| G11 | Korah's Rebellion | Numbers 16 | Moses back-half | Until the Moses wilderness back-half arc is approached. **AUTHORED as 1596** "Korah's Rebellion: The Earth Opens" (not yet arc-wired). |
| G12 | The Spies (Moses POV) | Numbers 13-14 | Moses | Event covered cross-character — use Caleb's 1049 as a guest beat. **Still deferred** — the only item left in `deferUntilArcApproached`. |
| G13 | Hezekiah's Illness | 2 Kings 20 | Hezekiah | Thin-pool fill; lifts Hezekiah to a buildable three. **AUTHORED as 1611** "Hezekiah's Illness and the Shadow Turned Back" (2026-08-01, text-first, not yet arc-wired) · anchor narrowed to **2 Kings 20:1-11**; **20:12-21 (Babylonian envoys, Isaiah's prophecy) stays uncovered by design**. |
| G14 | Josiah's Great Passover | 2 Chronicles 35 | Josiah | Thin-pool fill. **AUTHORED as 1612** "Josiah's Great Passover" (2026-08-01, text-first, not yet arc-wired) · anchor narrowed to **2 Chronicles 35:1-19**; **35:20-27 (Josiah's battle and death) stays uncovered by design**. |
| G15 | Sodom & Lot's Rescue | Genesis 19 | Abraham/Lot | **AUTHORED as 1613** "Sodom's Destruction and Lot's Rescue" (2026-08-01, text-first, not yet arc-wired) · anchor narrowed to **Genesis 19:1-29**, adult lane only; **19:30-38 (the cave; Moab and Ammon) stays uncovered by design**. 1487 can now be placed in sequence rather than held standalone — that placement is beat work, still undone. |
| G16 | Jonah and the Plant | Jonah 4 | Jonah | Missing capstone; doesn't block the safe Jonah arc. **AUTHORED as 1614** "Jonah and the Plant" (2026-08-01, text-first, not yet arc-wired) · **Jonah 4 whole chapter**, nothing excluded. |

---

## 5. Adult-parity mini-batch

Kid-first stories that should receive an adult traditional version — the anchor and kid editorial work already exist, so these are the cheapest per-story wins. Ranked by canonical expectation / leverage.

> **2026-07-31: this mini-batch is COMPLETE.** All three adult versions exist and are registered.

1. **The Sower** (Mark 4:1-9 / Matt 13) — kid 1912 exists; the flagship parable, adult lane empty. **→ produced as adult 1570** (Matthew 13:1-23).
2. **The Persistent Widow** (Luke 18:1-8) — kid 1905 exists; adult 1539 is the adjacent parable, not this one. **→ produced as adult 1584.**
3. **Joseph in Egypt / Potiphar's House** (Gen 39-40) — kid 1906 bundles it; fills the Joseph adult-arc middle (coat 1037 → reveal 1003). **→ produced as adult 1579** (Genesis 39); the Genesis 40 half was already covered by existing 1178 / 1389, so the item was deliberately split and is complete.

_Removed from the parity batch during the gate: **Mary & Martha** (adult 827 exists) and **Widow's Mite** (adult 1444 exists)._

---

## 6. Recommended production waves

> **2026-07-31: Waves 1-5 are all complete.** Only the Enrichment adjunct remains open. Retained below as the production record.

### Wave 1 — Foundational omissions ✅ COMPLETE
*Batch size:* 2–3 per sub-batch (heavy content)

Fall · Cain · John 1 Prologue · Peter's Confession · Peter's Denial · Bronze Serpent · David at En-gedi

The most conspicuous holes. Split by weight: (1a) John 1 + Peter's Confession + En-gedi [3 standard]; (1b) Fall + Cain [2, very heavy — extra review]; (1c) Peter's Denial + Bronze Serpent [2 heavy].

### Wave 2 — Journey blockers ✅ COMPLETE (authored, not yet arc-wired)
*Batch size:* 1–2 per arc

G1–G7 (fillNow), grouped by character: Moses (G1) · Jacob (G2+G9) · David (G3+G7) · Joshua (G5+G6) · Samson (G4)

Straight from the approved backlog — no re-gating. Several are heavy (G3, G4, G7) → keep arc batches to 1–2.

### Wave 3 — Adult parity ✅ COMPLETE
*Batch size:* 3 (cheap — anchors + kid editorial exist)

The Sower · The Persistent Widow · Joseph in Egypt

Highest production-leverage per story: the scripture is already extracted and a kid cut is a working reference. Joseph is the only heavy one here.

### Wave 4 — Heavy adult-only & Passion ✅ COMPLETE
*Batch size:* 2–3 per batch

Pilate + Barabbas (Passion pair) · Rich Man & Lazarus · Rehoboam · Flight/massacre · [+ G3/G4/G7 land here in practice]

Deliberately small batches. Pilate+Barabbas fill the arrest→cross seam together.

### Wave 5 (optional) — Teaching & parable completion ✅ COMPLETE
*Batch size:* 5 (standard)

Ten Virgins · Sheep & Goats · Rich Fool · Workers in the Vineyard · Weeds · Pearl

Standalone parables, no journey effect. Can run in parallel with Journey work once Waves 1–2 land.

### Enrichment adjunct — Contemplative, low-risk ⬜ STILL OPEN
*Batch size:* anytime

Isaiah 9 (Advent) · Psalm 1

Non-narrative; route separately from the story batches. **2026-07-31: the only part of §6 still open** — Isaiah 9:2-7 and Psalm 1 are both re-verified absent from the corpus.

---

## 7. Journey impact map

What changes when each new story lands. No beats are written; this records the arc consequence only.

> **2026-07-31: every story named below now exists** (see §2 for IDs), but **no beats have been written for any of them** — none appears in `outgoing_beats.json` or in any `assets/stories/journeys/*.json` arc file. This map is now the *to-do list for journey wiring*, not for authoring.

- **Peter's Confession + Denial** — Insert into the Peter Gospel arc between existing Call/Water and existing Restoration (1130). New arc becomes buildable; the restoration ceases to be an orphan. No existing outgoing edge replaced. Terminal beat = Restoration (1130).
- **The Fall + Cain** — Seed the opening of a new primeval arc (Creation 1805/1834 → Fall → Cain → … → Flood G10). No existing edge replaced.
- **Pilate + Barabbas** — Fill the Passion arc's arrest→cross seam; currently arrest jumps straight to the crucifixion (1109). Interior beats when a Passion journey is built.
- **David at En-gedi** — Strengthens the David-and-Saul pre-kingship pool; feeds a future mercy beat. No edge replaced.
- **Bronze Serpent** — Standalone Moses-wilderness beat and a foreshadow for a Nicodemus/John 3 thread ('lifted up'). No edge replaced.
- **Rehoboam** — Opens the divided-monarchy era (new arc seed: Solomon → Rehoboam → the two kingdoms). No edge replaced.
- **Joseph in Egypt** — Fills the Joseph adult-arc middle that currently jumps from the coat (1037) to the reveal (1003).
- **Flight to Egypt** — Nativity arc tail (magi 1070 → flight → Nazareth). Interior beat.
- **Sower · Persistent Widow · the parables** — Standalone; no arc effect.
- **G-items** — Arc effects per journey_gap_backlog.json (Moses, Jacob, David, Joshua, Samson arcs). G7 Absalom is terminal (no right story).

---

## 8. Confidence & caveats

- **Full-corpus automated verification** (workflow verify stage): net-new essentials from non-salvaged divisions — Fall, Cain, John 1, Pilate, Barabbas, Rehoboam, Rich Fool, Rich Man & Lazarus, Ten Virgins, Sheep & Goats, Workers, Weeds, Pearl, Flight, Joseph's Dream.
- **This targeted Opus verification** (meta-grep across both lanes and all fields + directory ground-truth): the salvaged-division items (Bronze Serpent, Peter's Confession, En-gedi), all parity items (Sower, Persistent Widow, Joseph-in-Egypt), the three overturned findings, and the Peter arc mapping. Every "absent" claim was confirmed at 0 meta hits.
- **Approved G1-G16 baseline:** relied upon as adversarially verified on 2026-07-16; not re-verified, except kid 1907 was confirmed to exist (so G1's fill is adult-lane).
- **Unresolved uncertainty:** (1) Kingdom-parable scoping — Weeds may merge with its explanation; the Fall may need splitting into temptation vs. consequence for kid-safety. (2) Exact adult/kid split and hard-anchor handling for the Fall, Cain, Bathsheba (G3), and Samson's capture (G4) is an authoring-time editorial call, not settled here.
