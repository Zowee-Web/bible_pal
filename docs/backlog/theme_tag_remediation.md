# Backlog — themeTags Vocabulary Remediation

**Discovered:** 2026-05-30 during CI repair triage (`chore(ci): backfill biblical_figure_registry stubs` follow-up).
**Status:** Deferred. Requires dedicated session with mapping table + review pass.
**Affected:** 219 traditional stories, 1001 unique drifted "tag" values.

## What's wrong

`test/features/paths/manifest_annotation_integrity_test.dart::themeTags integrity` expects every `themeTags` value to belong to a locked ~50-tag vocabulary (faith, hope, mercy, courage, obedience, ..., devotion). But 219 stories (predominantly 1300-series) contain scene-descriptive phrases in `themeTags` instead, e.g.:

- `aaron_and_hur_held_up_moses_hands`
- `abigail_loaded_donkeys_with_loaves_wine_sheep`
- `after_the_assembly_of_repentance`
- `angel_shut_the_lions_mouths`
- `altar_named_ed`

These are NOT taxonomy values. They identify a specific dramatic beat of the story — useful editorial data — but the wrong field.

## Why not "just delete them"

The drifted values are editorially valuable:
- They name the scene's load-bearing image
- They could power similar-scene discovery / Paths construction / search
- They reflect curatorial judgment baked into the catalog

Bulk-stripping loses this signal forever.

## Recommended remediation (per Adam, 2026-05-30)

1. **Add a `sceneTags` (or `specificEventTags`) field** to the manifest entry schema for storing the drifted scene-descriptive phrases as first-class data.
2. **Migrate the existing drifted values** out of `themeTags` and into `sceneTags`.
3. **Map only approved broad concepts back into `themeTags`** from the locked vocabulary, based on the scene phrase + scripture anchor + mood.
   - Example: a story tagged `aaron_and_hur_held_up_moses_hands` could land in `themeTags: [perseverance, loyalty]` and stay in `sceneTags: [aaron_and_hur_held_up_moses_hands]`.
4. **Do NOT delete** the detailed tags unless they duplicate something already present in the new structure.

## Scope estimate

- 1001 unique drifted values, but many cluster (e.g., variations on "after_X"). Real editorial decisions probably 200-400 distinct mappings.
- Per-story themeTags assignment from {mood, anchor, scene} is mechanical once the mapping table exists.
- Estimated effort: 4-8 hours focused editorial work + automation.

## What is blocked until this is done

- `manifest_annotation_integrity_test::themeTags integrity` — stays red in CI.
- This test failure does NOT block content commits (it's a WARN-like signal on master), but it muddies CI signal for actual regressions.

## Related drift to address in same pass

`manifest_annotation_integrity_test` also has failures for:
- `timelineEra` — values like `early_monarchy`, `divided_monarchy`, `pre_exile`, `babylonian_exile`, `persian_exile` need mapping to the locked era list (`creation, patriarchs, exodus, conquest, judges, kingdom, prophets, wisdom, exile, return, jesus_ministry, early_church`). Smaller scope than theme tags; do in the same session.
- `primaryCharacterId` — some annotated stories reference IDs not in the registry. Likely auto-fixable once registry curation catches up.

## Suggested workflow when picking this up

1. Dump all 1001 unique drifted theme tag values → CSV with sample story id + bibleSourceRef + mood.
2. Adam writes the mapping table (drifted → {sceneTags, themeTags}).
3. Script applies the mapping, runs the test, iterates.
4. Single PR with: schema change, manifest migration, test passing.
