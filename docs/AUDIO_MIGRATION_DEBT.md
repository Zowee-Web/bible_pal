# Audio Migration Debt

## Why this document exists

Some manifest entries reference legacy narrator voices (`VOICE_JOHN_DOE`,
`VOICE_CHRIS_DEFAULT`) that have been removed from the active narrator pool.
The audio assets attached to those entries were already generated with those
voices; **regenerating audio for stories that already sound right would burn
ElevenLabs credits with no user-facing benefit**.

The legacy voices stay valid for *manifest membership* via the
`_legacyAudioOnlyVoices` section of [`server/voices.json`](../server/voices.json),
but they are banned for *new content authoring* via
[`scripts/story_factory/story_voice_registry.py`](../scripts/story_factory/story_voice_registry.py)'s
`BANNED_VOICES` set. Two separate concerns, two separate enforcement points.

## Operating rule

**Manifest `narratorVoiceKey` MUST match the voice that recorded the audio.**
Updating the metadata without regenerating the audio (or vice versa) creates
drift: the app claims one voice, the user hears another.

To migrate a story off a legacy voice:

1. Move existing audio files to `assets/stories/audio_archive/<date>_<reason>/`
   (the project rule is "never delete audio; move and document").
2. Update `voiceKey` / `storyVoiceKey` / `reflectionVoiceKey` in
   `assets/stories/traditional/<id>/meta_<id>.json`.
3. Run `bash scripts/generate_opus_audio.sh --story <id>` to produce fresh audio
   in the new voice (script reads `voiceKey` from the meta file).
4. Update `narratorVoiceKey` in `assets/stories/manifest.json` for every variant
   row of that base story.
5. Verify `flutter test test/critical/narrator_voice_validation_test.dart` still
   passes.
6. Commit metadata changes alongside the regenerated audio in a single commit
   so the asset and the metadata move together.

## Stories already migrated

PR γ ("voice allowlist + targeted audio re-record") regenerated audio for 3
base stories selected by quality review. All voices in this batch moved from
`VOICE_JOHN_DOE` to `VOICE_JAMES_HUSKY` (warm pastoral male — fits calm and
anxious-relief moods).

| Base | Mood | Old voice | New voice | Variants regenerated |
|---|---|---|---|---|
| story_1034 | calm_peaceful | VOICE_JOHN_DOE | VOICE_JAMES_HUSKY | 6 (short, full × WEB + KJV; reflection × WEB + KJV) |
| story_1066 | calm_peaceful | VOICE_JOHN_DOE | VOICE_JAMES_HUSKY | 6 |
| story_1097 | anxious | VOICE_JOHN_DOE | VOICE_JAMES_HUSKY | 6 |

Archived legacy audio (preserved, not deleted):
`assets/stories/audio_archive/2026-05-05_pr_gamma/`.

## Stories intentionally NOT migrated

Most legacy-voice stories are intentionally preserved because the existing
audio sounds right under quality review. Regenerating would burn credits
without improving user experience.

The following 19 base stories continue to reference legacy voices in
`narratorVoiceKey` and will keep doing so until either:

- A specific quality issue is identified and the story joins a future
  migration batch, OR
- The Creative-mode legacy is formally retired (would archive these via
  `_ARCHIVED_IDS.json` instead of regenerating).

### `VOICE_JOHN_DOE` retained (11 base stories, ~36 manifest entries)

Recommended replacement when migrated: `VOICE_JAMES_HUSKY`.

| Base | Mood | Mode | Variants in manifest |
|---|---|---|---|
| story_832 | weary | traditional | 3 |
| story_1003 | hurting | traditional | 6 |
| story_1021 | hurting | traditional | 5 |
| story_1053 | hurting | traditional | 4 |
| story_1091 | brave_courage | traditional | 9 |
| story_1104 | brave_courage | traditional | 4 |
| story_2008 | calm_peaceful | creative | 3 |
| story_2023 | weary | creative | 2 |
| story_2037 | hurting | creative | 2 |
| story_2052 | grateful | creative | 2 |
| story_2069 | hurting | creative | 2 |

### `VOICE_CHRIS_DEFAULT` retained (7 base stories, ~28 manifest entries)

Recommended replacement when migrated: `VOICE_BRADFORD`.

| Base | Mood | Mode | Variants in manifest |
|---|---|---|---|
| story_826 | brave_courage | traditional | 3 |
| story_1005 | joyful | traditional | 6 |
| story_1038 | joyful | traditional | 4 |
| story_1049 | brave_courage | traditional | 4 |
| story_1070 | joyful | traditional | 4 |
| story_1090 | anxious | traditional | 7 |
| story_1108 | hurting | traditional | 4 |
| story_2019 | encouraging | creative | 2 |

## Why `VOICE_CHARLOTTE_V3` is in `voices` (not `_legacyAudioOnlyVoices`)

`VOICE_CHARLOTTE_V3` was missing from the active allowlist purely as a registry
oversight — she's an active production narrator covering 113+ manifest entries
across the corpus. PR γ adds her to the active `voices` array. Future content
authoring can use her freely. (Her ElevenLabs ID is loaded from the `.env`
file rather than committed to `voices.json`; the entry uses a placeholder ID
that's superseded at runtime.)
