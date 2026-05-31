# Backlog — Reflection Drift in 6 Stories

**Discovered:** 2026-05-30 during CI repair (`fix(test): reflection_consistency lane-aware + typography normalization`).
**Status:** Editorial review needed. Per Adam's standing rule "do not modify story/meta data without explicit approval", these are surfaced rather than auto-fixed.
**Test failing:** `test/core/reflection_consistency_test.dart::reflection .txt content exactly matches meta.reflectionText`.

## Background

The reflection_consistency test was lane-unaware and typography-strict; it failed on 99 stories that were actually fine (dual-lane setups where `meta.reflectionText` matches `reflection_*_web.txt` while the test was checking against `reflection_*_kjv.txt` alphabetical-first). The test was repaired to:

1. Pass if `meta.reflectionText` matches **any** reflection_*.txt file in the story dir.
2. Normalize typography (curly quotes, em-dash spacing, NBSP).
3. Collapse whitespace runs so JSON-single-line and .txt-paragraph-broken forms compare equal.

After the repair, **6 stories remain failing** — these are real content drift that the new test correctly catches.

## The 6 drifted stories

### Pattern A — `meta.reflectionText` contains scripture paraphrase instead of reflection prose (5 stories)

At some point in story creation these stories got the scripture *summary* written into the `reflectionText` field instead of a reflection. The reflection_*.txt files in those dirs contain the **actual reflection** — they are the truth.

| Story | `meta.reflectionText` (first 80 chars) | File reflection_*.txt (first 80 chars) |
|-------|----------------------------------------|----------------------------------------|
| **1096** | `Jesus asked the man a question: "Do you want to be made well?" The man did not…` | `Thirty-eight years is a long time to wait for something that never comes…` |
| **1097** | `Jehoshaphat stood before the people and said, "We have no might against this g…` | `There is a kind of courage that does not look like courage. It looks like sing…` |
| **1098** | `The scribes and Pharisees brought a woman taken in adultery. They set her in t…` | `The accusers came with stones and certainty. They had the law…` |
| **1099** | `Jesus took Peter, James, and John up a high mountain. He was transfigured befo…` | `For a few minutes on a mountaintop, three ordinary men saw something they…` |
| **1100** | `Yahweh's word came to Jonah the second time. It said, "Arise, go to Nineveh…` | `The most powerful city on earth heard eight words from a stranger and changed…` |

**Recommended fix:** Copy the contents of `reflection_<id>_traditional_web.txt` into `meta.reflectionText` for each of these 5 stories. The file is canonical; the meta has stale or schema-confused content.

### Pattern B — Word-level prose drift inside the reflection (1 story)

#### Story 1515
- `meta.reflectionText`: "...in a single night, every kingdom that shall ever..."
- `reflection_1515_traditional_kjv.txt`: "...in a single night, the kingdoms shown in the dream..."

Both start identically for ~265 characters then diverge. Real word-level edit-without-sync drift.

**Recommended fix:** Editorial judgment — pick one side as canonical (likely the file, since `reflection_*.txt` is the user-facing artifact) and sync the other.

## Scope of the cleanup

- 6 stories total.
- For 5 (Pattern A): mechanical sync `reflection_*_web.txt` → `meta.reflectionText`.
- For 1 (Pattern B): 1-minute editorial decision then sync.
- Total estimated effort: 15-20 minutes.

## Why this wasn't auto-fixed

Adam's standing rule during the CI-repair pass was "do not modify story/meta data." These drift-fixes are content edits, not test/script edits, so they belong in a separate editorial commit with explicit approval.

## Related still-open CI failures (separate backlog)

- 149 stories have `meta.reflectionText` field missing.
- 144 stories have no `reflection_*.txt` file in dir at all.

These are the known "364 stories missing reflections" retrofit project flagged on 2026-05-25 (see memory: `feedback_every_story_needs_reflection`). They remain deferred.
