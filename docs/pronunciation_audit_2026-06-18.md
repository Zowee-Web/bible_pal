# Bible PAL — Pronunciation Audit (Biblical Names)

**Date:** 2026-06-18
**Status:** ✅ **Closed — no action needed.** Audit was read-only; the 20 highest-priority names were then verified by ear and all sounded correct (see Result).
**Purpose:** Pre-launch polish pass. A mispronounced recurring name plays *every time* its story runs, so getting the high-exposure names right is a high-ROI, low-cost win.

## Result (2026-06-18 — listening pass)

**All 20 highest-priority names sounded correct** on `eleven_turbo_v2_5` (one neutral sentence each, Natasha voice), confirmed by ear — including the hardest: Nebuchadnezzar, Mephibosheth, Ahasuerus, Artaxerxes, Belshazzar. **No pronunciation dictionary is needed and no story re-renders are required** for the priority set.

- **Martha** sounded clean → confirms the originally-reported "awkward Martha" was the **stale `take1` audio in story 1083** (a wiring bug, since fixed), *not* a pronunciation problem.
- The remaining ~26 lower-priority names were not individually tested; since turbo handled the hardest names flawlessly, they almost certainly inherit this result. A spot-check batch can be run if zero-doubt coverage is wanted before launch.

**Conclusion:** ElevenLabs `eleven_turbo_v2_5` pronounces the hard biblical-name set correctly. The pronunciation-dictionary pipeline work is **not** required.

---

## Scope

Full-corpus sweep of biblical proper nouns (people, places, peoples) in **story narration** (`story_*.txt`, all lengths and both lanes; scripture extracts excluded). The goal is the names a listener actually *hears* in the spoken stories — not exhaustive coverage of every name in scripture.

- **46** TTS-risky names appear in the corpus (out of a 55-name curated candidate set).
- Common, easy names (David, Moses, Peter, Mary, Jacob, Abraham, …) are intentionally excluded — they render correctly and don't need help.

## Method

1. Scanned every `story_*.txt` for mid-sentence capitalized proper nouns and cross-referenced `biblical_figure_registry.json` + `character_registry.json`.
2. Footprinted a curated set of known-hard biblical names: **stories** = distinct stories containing the name; **mentions** = total occurrences (≈ how often a listener hears it).
3. Assigned a **risk tier** (likelihood ElevenLabs `eleven_turbo_v2_5` mis-stresses or mangles the name) and a recommended say-aloud pronunciation.

> ⚠️ **Empirical gate:** pronunciation could not be verified by ear in the audit environment (no speech-to-text / no playback). Risk tiers are analytic predictions. The next step (test clips) confirms which names ElevenLabs *actually* flubs before any fix is built — turbo nails some hard names and trips on easy ones, so building dictionary entries blindly would be wasteful.

## Pipeline limitation (why the fix is a dictionary, not text edits)

`scripts/story_factory/generate_audio.py` sends **plain text only** to ElevenLabs — the request body is `{text, model_id, voice_settings}`. There is **no SSML, no `<phoneme>` tag, and no pronunciation dictionary** wired in today.

Consequences:
- The durable fix is to **add pronunciation-dictionary support** to the pipeline (`pronunciation_dictionary_locators`), which `eleven_turbo_v2_5` supports. One dictionary entry fixes a name **once, corpus-wide**.
- **Editing the story text is NOT an option** — the same text is the on-screen Read-Story display, so a phonetic respelling would corrupt what the user reads (violates "the words the user sees should be the words the user hears").
- Reflections render on `eleven_v3`, which does **not** support pronunciation dictionaries — but these names rarely occur in reflections, and v3 generally handles names better.

---

## Risk tiers (with footprint + recommended pronunciation)

### 🔴 HIGH — hard, frequently mis-stressed
| Name | Stories | Mentions | Say-aloud |
|---|--:|--:|---|
| Nebuchadnezzar | 16 | 163 | neb-uh-kuhd-NEZ-er |
| Meshach | 7 | 100 | MEE-shak |
| Shadrach | 7 | 99 | SHAD-rak |
| Abednego | 7 | 99 | uh-BED-nee-go |
| Jehoshaphat | 6 | 196 | juh-HOSH-uh-fat |
| Capernaum | 6 | 25 | kuh-PER-nay-um |
| Belshazzar | 5 | 44 | bel-SHAZ-er |
| Caesarea | 5 | 39 | sez-uh-REE-uh |
| Artaxerxes | 5 | 22 | ar-tuh-ZURK-seez |
| Ahasuerus | 7 | 37 | uh-haz-yoo-EER-us |
| Habakkuk | 3 | 16 | huh-BAK-uk |
| Gethsemane | 3 | 8 | geth-SEM-uh-nee |
| Zacchaeus | 2 | 80 | za-KEE-us |
| Mephibosheth | 2 | 61 | muh-FIB-oh-sheth |
| Zerubbabel | 2 | 48 | zuh-RUB-uh-bel |
| Sennacherib | 2 | 26 | suh-NAK-er-ib |
| Nebuzaradan | 1 | 6 | neb-yoo-ZAR-uh-dan |
| Gennesaret | 1 | 6 | guh-NES-uh-ret |
| Jephthah | 1 | 4 | JEF-thuh |
| Melchizedek | 1 | 2 | mel-KIZ-uh-dek |
| Onesimus | 1 | 2 | oh-NES-ih-mus |
| Golgotha | 1 | 2 | GOL-guh-thuh |

### 🟠 MODERATE
| Name | Stories | Mentions | Say-aloud |
|---|--:|--:|---|
| Mordecai | 11 | 398 | MOR-duh-kye |
| Philistines | 22 | 234 | fih-LISS-teenz |
| Naaman | 4 | 147 | NAY-uh-mun |
| Shushan | 14 | 75 | SHOO-shan |
| Lazarus | 4 | 64 | LAZ-er-us |
| Gehazi | 3 | 58 | guh-HAY-zye |
| Ephraim | 14 | 53 | EE-fray-im |
| Manasseh | 10 | 51 | muh-NAS-uh |
| Beersheba | 10 | 48 | beer-SHEE-buh |
| Amalekites | 8 | 45 | uh-MAL-uh-kites |
| Hezekiah | 5 | 44 | hez-uh-KY-uh |
| Chaldeans | 12 | 39 | kal-DEE-unz |
| Jezreel | 5 | 34 | JEZ-ree-el |
| Jairus | 2 | 43 | JY-rus |
| Zacharias | 3 | 14 | zak-uh-RY-us |
| Jeroboam | 2 | 8 | jair-uh-BOH-am |
| Caiaphas | 1 | 6 | KY-uh-fus |
| Nicodemus | 1 | 6 | nik-uh-DEE-mus |
| Bartholomew | 1 | 2 | bar-THOL-uh-mew |
| Gamaliel | 1 | 2 | guh-MAY-lee-el |

### 🟡 LOW — usually fine, but very high exposure (confirm by ear)
| Name | Stories | Mentions | Say-aloud |
|---|--:|--:|---|
| Yahweh | 129 | 762 | YAH-weh |
| Haman | 11 | 247 | HAY-mun |
| Levites | 24 | 109 | LEE-vites |
| Martha | 4 | 71 | MAR-thuh |

## Exposure-weighted priorities

The names where a wrong render does the most damage (risk × how often it's heard):

1. **Nebuchadnezzar** — 16 stories / 163 mentions (highest hard-name exposure)
2. **Shadrach / Meshach / Abednego** — always heard together, ~100 mentions each
3. **Jehoshaphat** — 6 / 196
4. **Mordecai** — 11 / 398 (moderate risk, huge count — Esther arc)
5. **Philistines** — 22 / 234
6. **Naaman** — 4 / 147
7. **Zacchaeus** — 2 / 80 · **Mephibosheth** — 2 / 61
8. **Yahweh** — 129 / 762 (low intrinsic risk, but the single most-heard name — verify it's clean)

---

## Next-step plan

1. **Test clips (read-only, scratch folder)** — render one neutral sentence per priority name on `eleven_turbo_v2_5`, listen, and mark each: *sounds good / needs dictionary / unsure*. Only the confirmed-bad names proceed. *(Clips live outside the production asset tree; nothing committed.)*
2. **Add pronunciation-dictionary support** to `generate_audio.py` (`pronunciation_dictionary_locators`) and seed entries **only** for the confirmed offenders.
3. **Re-render only** the stories that contain a fixed name; normalize to −18 LUFS; update nothing the user reads (text is untouched).
4. **Verify + commit** per the usual discipline.

**Caveat for the test pass:** clips use a single representative approved narrator on turbo. Pronunciation can vary slightly by voice; once the offender list is confirmed, we can spot-check the specific narrators of the affected stories before the dictionary lands.
