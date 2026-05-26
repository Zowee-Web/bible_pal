# Known Issue: Bible JSON files are sparse on-demand subsets

**First documented:** 2026-05-26 (during B29 enrichment)
**Status:** unblocked workaround for past batches; B29 exposed it; not yet resolved

## Symptom

`scripts/backfill_scripture_text.py` fails to generate per-story scripture text files for any anchor whose specific book/chapter isn't already loaded in `server/data/bible_{web,kjv}.json`.

For B29:
- 1527 Exodus 14:21–31 — both WEB + KJV OK ✓
- 1528 Acts 27:13–26   — WEB OK, KJV FAIL (Acts 27 not in `bible_kjv.json`)
- 1529 Ruth 2:1–13     — both WEB + KJV OK ✓
- 1530 Job 38:1–11     — both WEB + KJV FAIL (Job 38 not present in either bible JSON; both only have Job 1, 3, 19, 42)
- 1531 Revelation 21:1–7 — WEB OK, KJV FAIL (Revelation entirely absent from `bible_kjv.json`)

## Root cause

`scripts/fetch_bible_json.py` is an on-demand importer that fetches only the books and chapters needed by stories at the time it was last run. New anchors that reference unimported chapters cannot be backfilled until fetch is re-run.

KJV gap is wider — `bible_kjv.json` contains only 26 of 66 books (missing: Leviticus, Deuteronomy, 1-2 Chronicles, Ezra, Proverbs, Song of Solomon, Ezekiel, all 12 Minor Prophets, all of Paul's epistles + general epistles + Revelation). Future KJV-lane stories drawing from any of these will hit the same wall.

## Impact

- `scriptureTextFilePath` in meta + manifest cannot be populated for affected lanes.
- The Scripture Sources feature (SPEC Feature 12) shows nothing for affected stories.
- B29 has 5 missing scripture text files (1528 KJV, 1530 WEB, 1530 KJV, 1531 KJV — and 1531 WEB exists).

## Workarounds in the meantime

- B29 enrichment committed without `scriptureTextFilePath` for affected lanes; metas still pass schema (the field is optional).
- App-side: Scripture Sources panel hides when the file is absent (already its current behavior per `Parable.scriptureTextFilePath` nullability).

## Fix proposal (deferred — DO NOT bundle into B30)

1. Extend `scripts/fetch_bible_json.py` to take a "fetch missing chapters referenced by any meta on disk" mode that scans `assets/stories/traditional/*/meta_*.json`, computes the union of `(book, chapter)` pairs referenced across all `scriptureAnchor` fields, and fetches/merges any missing chapters into the appropriate translation JSON.
2. For KJV's 40 missing books, identify a public-domain KJV JSON source (the existing `bible_kjv.json` source must be re-checked; `bible-api.com` doesn't serve KJV directly so a different source was used).
3. Run the extended fetcher, then re-run `backfill_scripture_text.py` over the full corpus to backfill anywhere a story exists but text files are missing.

This is a single focused PR that touches `scripts/fetch_bible_json.py` + the two `server/data/bible_*.json` files + per-story `scripture_*.txt` files + manifest `scriptureTextFilePath` updates. Keep it scoped to the gap fix; do NOT mix with new batch generation.
