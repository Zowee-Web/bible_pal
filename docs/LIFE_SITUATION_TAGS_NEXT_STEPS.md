# Life Situation Tags — Status and Next Steps

> Snapshot as of commit `fa069d4` (squash-merge of v1, 2026-05-19). Living document — update when material shifts.

This document captures (1) what shipped in v1, (2) the guardrails protecting the vocabulary, (3) the known v1 limits, (4) findings from the pre-merge blind-probe pressure test, (5) the allowed v1.1 work, and (6) the v2 trigger conditions. For the deeper specification and editorial rules, see the *Life Situation Tags v1 (Metadata-Only)* section in [SPEC.md](SPEC.md).

---

## v1 shipped (metadata + research only)

Life Situation Tags v1 introduces a controlled vocabulary mapping real-life events (e.g. "a friend borrowed something and lost it") to scripture-grounded stories. **v1 is metadata + offline CLI only. PAL routing is unchanged and remains so until v2 is explicitly triggered.**

Shipped artifacts:

- **45 controlled tags** in [assets/stories/life_situation_tags_registry.json](../assets/stories/life_situation_tags_registry.json), organized into 10 categories, each with a one-sentence disambiguating description.
- **53 seeded stories** with `primaryLifeSituationTags` (≤2) and `secondaryLifeSituationTags` (≤3) fields added additively to their meta files. Seed map source-of-truth: [scripts/life_situation_seed_map.json](../scripts/life_situation_seed_map.json).
- **Two-mode CLI** at [scripts/query_life_situation_tags.py](../scripts/query_life_situation_tags.py):
  - Mode A — exact tag lookup (`--tags` AND / `--any` OR), pooled across primary+secondary, ranked by primary hits
  - Mode B — deterministic keyword-overlap probe (`--probe`) against tagId + displayName + description tokens
- **17 probe regression fixtures** in [scripts/probe_smoke_tests.txt](../scripts/probe_smoke_tests.txt) with a non-zero-exit runner at [scripts/run_probe_smoke_tests.py](../scripts/run_probe_smoke_tests.py).
- **9-assertion compliance test** at [test/services/life_situation_tag_compliance_test.dart](../test/services/life_situation_tag_compliance_test.dart).
- **Drafts holding pen** at [scripts/life_situation_tags_drafts.json](../scripts/life_situation_tags_drafts.json) — 11 single-anchor candidates including `borrowed_item_lost` (the v1 motivating motif, awaiting a second strong anchor).
- **Patch-only backfill** at [scripts/backfill_life_situation_tags.py](../scripts/backfill_life_situation_tags.py) — idempotent, refuses to write tags absent from the registry.
- **SPEC.md** new section: *Life Situation Tags v1 (Metadata-Only)* with sub-sections on Vocabulary Rules, Secondary Tag Discipline, Probe Regression Fixtures, and Lexical Brittleness as Intentional v1 Limitation.

PAL-untouched invariant verified:

- `lib/**` — no routing, no model changes
- `assets/stories/manifest.json` — runtime bundle untouched
- `pubspec.yaml` / `pubspec.lock` — no dependencies added
- `Parable` model — `fromJson` tolerates the new fields without parsing them; no field added in v1

---

## Current guardrails

These are baked into the v1 system. They protect against vocabulary rot, semantic drift, and false confidence:

1. **Anti-bloat: ≥2 strong stories per registry tag** — test-enforced. Tags with only one strong anchor go to the drafts file, not the registry. Stretched matches added just to satisfy the count are explicitly disallowed.
2. **Cardinality caps: ≤2 primary, ≤3 secondary per story** — test-enforced. Prevents tag stuffing.
3. **Secondary Tag Discipline** — editorial invariant, **NOT** test-enforceable. Secondary tags must still feel emotionally central, not merely adjacent. "Technically true but emotionally weak" secondary tags create silent semantic drift. Reviewer asks: *"Would a user reaching for this tag be served by this story?"*
4. **15% soft warning** — compliance test prints (does not fail) when any single tag exceeds 15% of currently-tagged-story count. Watches for "comfortable defaults" creeping into secondary slots. Re-evaluate the threshold at ~200 tagged stories.
5. **Banned generics** — `restoration`, `waiting_on_god`, `comfort`, `hope`, `mercy`, `faith`, `love` cannot be primary tags. If a tag could be the title of a sermon series, it's too broad.
6. **Probe regression fixtures** — the runner exits non-zero on any expectation violation. New probes must be written **blind** (predictions locked before execution). Probes tuned after seeing results are confirmation bias and contaminate the suite.

---

## Known v1 limits (intentional design tradeoffs)

- **Lexical brittleness** — Mode B requires meaningful token overlap with tagId, displayName, or description. No stemming, no synonyms, no embeddings, no LLM. *False absence is safer than false confidence.*
- **Stemming holes** — `persecuted` ≠ `persecution`, `failed` ≠ `failure`, `come` ≠ `coming`, `prayers` ≠ `prayer`. A direct-description query can return nothing even when the perfect tag exists.
- **Idiom blindness** — "I am at the end of my rope" returns nothing despite `burnout` existing. Idioms don't surface without phrase dictionaries.
- **Synonym gaps** — vocab uses "depleted/wearing-out" for burnout; queries using "carrying" or "exhausted" won't surface.

Disposition rule: a *false-positive* (tag surfacing on connector words) is fixed by tightening STOPWORDS (strengthens determinism). A *false-negative* (right tag, wrong phrasing) is left as honest absence and waits for v2.

---

## Blind-probe findings (2026-05-19 pre-merge pressure test)

10 blind probes were written with predictions locked before execution. Result: 9 of 10 confirmed; 1 false-positive caught and fixed via STOPWORDS expansion (`after, again, still, yet, always, ever, ago`).

### Three real vocabulary gaps surfaced

Track these as future draft candidates. Each requires ≥2 strong story matches before promotion — do not invent a tag for a single story.

- **Active betrayal** — *"I betrayed someone I love"* returns nothing. We have `betrayal_by_family` (being betrayed) but no symmetric tag for being the betrayer. `let_someone_down` is close but not the same emotional shape. Future candidates: Judas, Peter denies Christ (already tagged with `bitter_failure` / `let_someone_down`), David's adultery if it surfaces in future batches.
- **Family invisibility / unseen at home** — *"I feel like nobody sees me at home"* returns nothing. We have `secret_shame` (something hidden) and `family_estrangement` (severed) but nothing for "present but unloved." Future candidates: Leah (unloved wife), Joseph in some readings, Hannah taunted by Peninnah.
- **Spiritual silence / felt absence of God** — *"God seems silent to me"* returns nothing. `unmet_longing` and `wavering_faith` touch this but neither names the specific texture. Future candidates: Psalm 22, Job's middle chapters, Habakkuk's complaint.

### Lexical-hole queries (documented v1 behavior, NOT bugs)

Four observed queries where the vocabulary and tagged stories exist but Mode B's lemma-blindness blocks the match. These are the strongest argument for v2 lemmatization or curated synonym maps:

- *"I am being persecuted unjustly"* — `unjust_persecution` exists, 5 stories tagged
- *"I am carrying too much by myself"* — `burnout` exists, 2 stories tagged
- *"I want to come back but I do not know if I would be welcome"* — `coming_home` + `forgiveness_received` exist
- *"I am scared to try again after how badly I failed"* — `second_chance` + `bitter_failure` + `fear_overwhelm` all exist

Direct-description queries that fail are the highest-cost failures because the user is literally naming the tag. They are explicitly **not** fixable in v1 without violating its determinism contract.

---

## Next v1.1 work (pre-v2)

Operating principle: **corpus pressure reveals vocabulary weaknesses, not theoretical probe-tuning.**

### Allowed in v1.1

- **Tag ~20 more stories** — only where the current 45-tag vocabulary strongly fits. If a story needs a tag that doesn't exist, leave the story untagged and note the gap. Do NOT stretch existing tags to fit.
- **Add probe fixtures only when written blind** — write predictions before running. Failed predictions are signal; passing predictions are noise. Tuning a probe after seeing its result invalidates the entire fixture suite.
- **Watch the 15% soft warning** — currently the top tag (`delayed_promise`) sits at 11.3%. If anything crosses 15%, review for "comfortable default" overuse before adding more secondary uses of that tag.
- **Fix new false-positives** by tightening STOPWORDS as they surface from blind probes.

### Explicitly disallowed in v1.1

- **New registry tags** unless **both freeze gates** are met:
  - (a) ~50 more stories tagged with current vocab AND ≥3 felt genuinely forced (vocab is short something), OR
  - (b) probe fixtures grow to ≥30 entries AND ≥3 have no resonant match (vocab is missing situational coverage)
- **PAL routing changes** — the whole point of v1 is to prove the vocabulary before it touches user-visible behavior
- **Mode B "improvements"** that introduce stemming, synonyms, embeddings, or LLM logic — these are v2 territory; introducing them in v1.1 silently changes what the fixture suite is testing

---

## v2 trigger

Move to v2 only when **all three** hold:

1. **~70–80 tagged stories** with the current vocabulary, without the vocab feeling cramped or routinely stretched
2. **Stable probe results** across the regression fixture suite — no flakiness, no surprises that turn out to be retrieval bugs after investigation
3. **Corpus pressure evidence** that the current vocabulary is too narrow — concrete examples (≥3) of resonant stories that current tags can't capture without distortion, AND probe queries that should land but don't where the gap is genuinely vocabulary, not just lexical brittleness

When triggered, v2 scope to evaluate (each is a separate decision):

- Promote `lifeSituationTags` fields onto the `Parable` model + regenerate `manifest.json`
- Decide whether Mode B grows lemmatization / curated synonyms, OR retrieval becomes a separate system altogether
- Wire situational retrieval into PAL routing as a *new* selection path (not a replacement for mood routing)
- UI: surface situational tags to the user? Or keep retrieval invisible and route silently?

v2 is a conversation, not a sprint. The point of v1's discipline is to make sure the conversation starts from real evidence, not from optimism about how the system *should* work.
