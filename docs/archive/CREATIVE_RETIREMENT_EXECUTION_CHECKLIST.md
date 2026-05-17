# Creative Retirement — Stage 2 Execution Checklist

> **DO NOT RUN any command in this document during Stage 1.** This is the runbook for Stage 2, executed later on 2026-05-13 once the T9 SSD is connected.

## Stage 1 completion (auto-marked by prep session)

- [x] Prep branch `fix/creative-retirement-stage1-prep` created
- [x] `docs/archive/CREATIVE_RETIREMENT_2026_05_13.md` written
- [x] `docs/archive/CREATIVE_RETIREMENT_EXECUTION_CHECKLIST.md` written (this file)
- [x] `docs/archive/CREATIVE_RETIREMENT_GIT_SAFETY_REPORT.md` written
- [x] `scripts/archive_creative_to_t9.sh` created (NOT executed)
- [x] `scripts/verify_creative_archive.sh` created (NOT executed)
- [x] `scripts/remove_creative_after_verification.sh` created (NOT executed)
- [x] `TODO(creative-retirement)` comments added to 10 source files (no logic changes)
- [x] `flutter analyze` run post-comment-additions — must show no NEW issues

---

## Stage 2 execution order

### Step 0 — Confirm T9 is connected

```bash
[ -d /Volumes/T9-Archive ] && echo "T9 OK" || echo "T9 NOT MOUNTED — ABORT"
```

**STOP if T9 not mounted.** Do not proceed under any condition.

### Step 1 — Confirm working tree is clean and on the prep branch

```bash
git status --porcelain    # must be empty (or only contain untracked non-Creative items)
git branch --show-current # must be fix/creative-retirement-stage1-prep (or successor)
```

**STOP if tree is dirty with Creative-related changes** — those would conflict with deletion.

### Step 2 — Run the archive script

```bash
# Optional dry-run first
DRY_RUN=1 bash scripts/archive_creative_to_t9.sh

# Real run
bash scripts/archive_creative_to_t9.sh
```

Expected output:
- Pre-archive sha256 manifest written to `/tmp/pre_archive_creative_tree.sha256`
- rsync copies of every Creative subtree to `/Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/`
- `ARCHIVE_COMPLETE.txt` written at destination on success

Expected baseline counts:
- `assets/stories/creative/` — **804 files**, **~508 MB** (~532,402,176 bytes)
- `assets/pal/audio_archive_grace_2026_04_23/` — **24** Creative files
- `assets/pal/audio_archive_ruth_v1_2026_04_25/` — **24** Creative files

**STOP if rsync reports any errors or `ARCHIVE_COMPLETE.txt` is not written.**

### Step 3 — Run the verification script

```bash
bash scripts/verify_creative_archive.sh
```

Expected:
- File count match between source and destination
- Byte count match
- sha256 manifest match (every file)
- Writes `/tmp/verify_creative_archive.PASS` on success

**STOP if any check fails.** Do not proceed to deletion. Investigate the mismatch first.

### Step 4 — Create the git tag

```bash
git tag -a pre-creative-retirement-2026-05-13 \
  -m "Last commit before Creative mode retirement. Archive at /Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/. See docs/archive/CREATIVE_RETIREMENT_2026_05_13.md for restoration."

git tag -l pre-creative-retirement-2026-05-13  # confirm tag exists
```

The tag is local-only until pushed. Push after the retirement PR is merged:

```bash
# Run AFTER PR merge, not before
git push origin pre-creative-retirement-2026-05-13
```

### Step 5 — Run the deletion script

```bash
# Default invocation prints what would happen but does nothing destructive
bash scripts/remove_creative_after_verification.sh

# Real run requires explicit confirmation
CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP \
  bash scripts/remove_creative_after_verification.sh
```

The script will:
- Refuse to run unless `/tmp/verify_creative_archive.PASS` exists
- Refuse to run unless on a `fix/creative-retirement-stage*` branch
- Refuse to run unless working tree is clean
- Print every path it will remove BEFORE doing anything
- Use `git rm -r` so deletions show up cleanly in `git diff`
- NOT touch R2
- NOT touch `assets/stories/manifest_full_backup.json` (deferred decision)

### Step 6 — Strip Creative entries from manifests

This is a separate, focused operation. Use `jq` to filter:

```bash
# manifest.json
jq '[.[] | select(.storytellingMode != "creative")]' \
  assets/stories/manifest.json > assets/stories/manifest.json.tmp
mv assets/stories/manifest.json.tmp assets/stories/manifest.json

# manifest_opus.json
jq '[.[] | select(.storytellingMode != "creative")]' \
  assets/stories/manifest_opus.json > assets/stories/manifest_opus.json.tmp
mv assets/stories/manifest_opus.json.tmp assets/stories/manifest_opus.json

# unused_pal_stories.json
jq '[.[] | select(.storytellingMode != "creative")]' \
  assets/stories/unused_pal_stories.json > assets/stories/unused_pal_stories.json.tmp
mv assets/stories/unused_pal_stories.json.tmp assets/stories/unused_pal_stories.json

# Verify counts
echo "manifest.json:   $(jq 'length' assets/stories/manifest.json) entries"
echo "manifest_opus:   $(jq 'length' assets/stories/manifest_opus.json) entries"
echo "unused_pal:      $(jq 'length' assets/stories/unused_pal_stories.json) entries"
```

Expected reductions:
- `manifest.json`: −173 Creative entries
- `manifest_opus.json`: −203 entries
- `unused_pal_stories.json`: −44 entries

(`manifest_full_backup.json` left untouched — separate decision.)

### Step 7 — pubspec.yaml cleanup

Remove lines 401–480 (80 Creative directory declarations) and line 490 (`creative_opening_lines.json`). Use `Edit` tool with explicit context, NOT blind sed.

### Step 8 — Code simplification

Working through files in dependency order:

1. **Delete** `lib/core/creative_opening_lines.dart` + `test/core/creative_opening_lines_test.dart`
2. **Simplify** `lib/safety/story_mode_validator.dart` — drop `validateCreative()`, collapse dispatcher
3. **Simplify** `lib/services/parable_service.dart` — drop Creative validation branch
4. **Simplify** `lib/providers/app_state_notifier.dart` — drop `updateStorytellingMode()`
5. **Simplify** `lib/features/main_menu/main_menu_screen.dart` — drop `_buildStoryModeToggle()`, `_StoryModeTab`, Creative opening-line block
6. **Simplify** `lib/features/pals_parables/pals_parables_screen.dart` — drop L607 mode check (always show framing)
7. **Simplify** `lib/models/user_preferences.dart` — coerce-on-load: keep field, but `fromJson` coerces `'creative'` → `'traditional'`
8. **Simplify** `lib/models/parable.dart` — keep field for backward parse of legacy data; remove Creative-only comments

### Step 9 — Test changes

Per Type A/B/C classification in inventory report:

- **Delete:** `creative_opening_lines_test.dart`, `storytelling_mode_toggle_test.dart`, `mode_persistence_test.dart`, `story_mode_contracts_test.dart` (Creative half), `story_dna_metadata_test.dart`
- **Tighten:** `path_service_test.dart`, `search_service_test.dart`, `manifest_annotation_integrity_test.dart` — assertions become "Creative cannot exist in manifest" instead of "Creative excluded"
- **Migrate fixtures:** Tests using Creative IDs as incidental fixtures (mood_expansion_serving, story_length, kid_friendly_toggle_safety, story_translation_filter, daily_bread_service, parable_service_offline_library, reflection_audio) — replace with Traditional IDs
- **Add:** `test/critical/creative_retirement_test.dart` asserting:
  - No `assets/stories/creative/` directory exists
  - All active manifests have zero `storytellingMode: 'creative'` entries
  - Default `storytellingMode` is `'traditional'`
  - Legacy `'creative'` SharedPreferences value coerces to Traditional on load
  - Favorites/history with orphan Creative IDs are skipped without crash

### Step 10 — SPEC + INVARIANTS rewrite

Replace dual-mode framing in:
- `docs/SPEC.md` (Features 13 + 22, L475–512 contract, L514–528 DNA, L1265+ search/path scope)
- `docs/INVARIANTS.md` (L1055–1180 Non-Blur + Creative requirements, L1492 two-modes invariant)
- `docs/STORY_FACTORY.md` (PART B sections 12–22)
- `docs/DECISIONS.md` ADR-014 + ADR-020 — keep with "Superseded by Creative Retirement 2026-05-13" header
- `docs/ARCHITECTURE.md` L117, L146, L179 — collapse to Traditional-only
- `CLAUDE.md` L126 — remove

New SPEC section text drafted in original inventory report (see plan file at `/Users/adamlipps/.claude/plans/yes-proceed-with-soft-scone.md`).

### Step 11 — Server-side script cleanup

Each Creative-aware script: remove Creative branches surgically (preferred for git diff readability) OR replace with Traditional-only rewrite. Files affected:

- `scripts/story_factory/claude_prompts.py` (L42–87, L253–310, L410–454)
- `scripts/story_factory/claude_validator.py` (L199–360)
- `scripts/story_factory/generate_audio.py` (L10, L97)
- `scripts/generate_story_opus.py` (multiple)
- `scripts/generate_opus_audio.sh`
- `scripts/build_android.sh`
- `scripts/build_play_bundle.sh`
- `scripts/run_opus_batch.py`
- `scripts/upload_r2_audio.sh` — KEEP R2 logic intact; only drop `creative/*` paths from samples
- `scripts/ai_health_check.sh`
- `server/generate_v2_batch.sh` (extensive)
- `server/generate_pal_framing_audio_batch.sh`
- `server/story_calibration.sh`
- `server/generate_batch_parables.sh`
- `server/generate_reflection_audio.sh`
- `server/tools/backfill_story_mode.sh`
- `server/tools/validate_story_text.sh`
- `server/model_router/*` — drop `creative_story` task from registry + tests

`server/legacy/` — recommend archiving whole directory to T9 (it's already dormant).

### Step 12 — Update root-level config artifacts

- `.claude/settings.local.json` — remove lines 67–68 (Creative prompt hooks)
- `configs/opus_batch_04.json` — strip Creative entries L149–254
- `scripts/play_bundle_pick.json` — remove `"creative"` key L19

### Step 13 — Verification gates

```bash
# Static analysis MUST PASS
flutter analyze

# Compliance gates MUST PASS (per CLAUDE.md)
flutter test test/core/bible_translation_compliance_test.dart
flutter test test/core/repo_wide_compliance_scan_test.dart

# Full suite
flutter test

# Diagnostics-gated (per CLAUDE.md)
flutter test --run-skipped --tags=requires_diagnostics_define \
  --dart-define=DIAGNOSTICS_ENABLED=true

# Grep should return only intentional retirement refs (TODO removal markers gone,
# only the new retirement doc + migration code remain)
grep -ril "creative" lib/ test/ scripts/ server/ docs/
```

### Step 14 — Open the retirement PR

```bash
gh pr create --title "Creative mode retirement: Traditional-only" \
  --body "$(cat <<'EOF'
## Summary
- Soft retirement of Creative mode lane
- Archive at /Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/
- Git tag pre-creative-retirement-2026-05-13 preserves recoverable state
- Working tree now Traditional-only

## Test plan
- [ ] flutter analyze (must pass)
- [ ] Compliance tests pass (bible_translation_compliance, repo_wide_compliance_scan)
- [ ] Full test suite passes
- [ ] Manual: launch app, confirm no mode toggle on Main Menu
- [ ] Manual: confirm legacy `'creative'` SharedPreferences coerces to Traditional
- [ ] Manual: confirm orphan Creative favorites do not crash

EOF
)"
```

### Step 15 — After PR merge

```bash
# Push the safety tag
git push origin pre-creative-retirement-2026-05-13

# Optionally compress the T9 archive for long-term cold storage
cd /Volumes/T9-Archive/bible_pal_archives
tar -czf creative_retirement_2026_05_13.tar.gz creative_retirement_2026_05_13/
```

---

## Verification gates summary (STOP triggers)

| Gate | Check | Action on FAIL |
|------|-------|----------------|
| 0 | T9 mounted | **STOP** — abort entire session |
| 1 | Working tree clean | **STOP** — investigate dirty files |
| 2 | rsync clean exit + `ARCHIVE_COMPLETE.txt` | **STOP** — do not proceed to verification |
| 3 | sha256/count/byte match | **STOP** — DO NOT delete; investigate diff |
| 4 | Git tag created | Continue — tag is cheap |
| 5 | Working tree still clean + on prep branch | **STOP** — script will refuse anyway |
| 6 | jq manifest filtering produces valid JSON | **STOP** — restore from `.tmp` if invalid |
| 13 | `flutter analyze` + tests pass | **STOP** — fix before PR |

---

## Rollback plan

### If something fails between Step 2 and Step 5 (after archive, before delete)

Nothing destructive happened yet. Just:

```bash
git status                                          # confirm clean
rm /tmp/pre_archive_creative_tree.sha256
rm /tmp/verify_creative_archive.PASS 2>/dev/null
# Optionally remove the partial archive at T9:
rm -rf /Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13
```

Re-run from Step 2.

### If failure between Step 5 and Step 13 (post-delete, pre-merge)

```bash
# Reset the deletion commit
git reset --hard pre-creative-retirement-2026-05-13

# Or restore selectively from T9
rsync -av "/Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/assets/stories/creative/" \
  assets/stories/creative/
```

### If failure POST-merge (PR already in master)

```bash
# Restore from tag onto a new recovery branch
git checkout -b restore/creative-emergency pre-creative-retirement-2026-05-13
# Cherry-pick or merge as needed
```

---

## Deferred decisions (resolve in Stage 2)

1. **`manifest_full_backup.json`** — strip Creative entries in place OR rename + move whole file to T9 as historical artifact?
2. **`audio_archive_grace_*` / `audio_archive_ruth_*`** — verified Creative-only, or mixed? If mixed, selective archive only.
3. **Creative-aware scripts** — surgical removal vs full rewrite?
4. **`server/legacy/` directory** — whole-dir archive vs surgical Creative removal?
5. **Migration aggressiveness** — coerce-on-load (recommended) vs one-shot wipe of orphan SharedPreferences keys.

---

## Expected end state after Stage 2

- `master` branch contains Traditional-only Bible PAL
- `grep -ri "creative"` returns only retirement docs + migration coercion code
- `assets/stories/creative/` does not exist in working tree
- `pubspec.yaml` has no Creative declarations
- Active manifests have zero Creative entries
- Mode toggle removed from Main Menu UI
- SPEC + INVARIANTS reflect Traditional-only product
- T9 archive present + checksummed
- Git tag `pre-creative-retirement-2026-05-13` pushed to origin
