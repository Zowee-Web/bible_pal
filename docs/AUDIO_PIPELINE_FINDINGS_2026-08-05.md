# Audio Pipeline Findings — 2026-08-05

> **Status:** Durable operational record. Two controlled listening experiments and one
> permanent project rule.
>
> **Owner decisions recorded by:** Adam, 2026-08-04 / 2026-08-05.

These findings exist because both experiments were expensive to run and produced
**negative results**. A negative result is only valuable if it is written down —
otherwise the same investigation gets repeated, at the same cost, by the next
person or session to notice the same symptom.

Read the scope limitations. Neither experiment proves as much as its headline suggests.

---

## Finding A — narration pipeline experiment

### What was tested

A controlled blind comparison on Traditional story **1613** (*Sodom's Destruction and
Lot's Rescue*, Genesis 19:1-29), using the **same approved WEB text** and the **same
narrator** (`VOICE_BRADFORD`) in every arm.

Six arms:

| Arm | Model | Segmentation |
|---|---|---|
| A | `eleven_turbo_v2_5` | whole story, one request |
| B | `eleven_turbo_v2_5` | semantic chunks + Request Stitching |
| C | `eleven_flash_v2_5` | whole story, one request |
| D | `eleven_flash_v2_5` | semantic chunks + Request Stitching |
| E | `eleven_multilingual_v2` | semantic chunks + Request Stitching |
| F | `eleven_v3` | whole story, one request |

Controls held identical across all arms: source text (byte-exact, verified by SHA-256),
voice ID, language, final container and bitrate (MP3 44.1 kHz mono 128 kbps), loudness
(equalised to within 0.10 LUFS using **static gain only**, so pause structure and
dynamics were untouched), and silence treatment (none added or trimmed). No
pronunciation dictionaries, aliases, phoneme rules, audio tags, SSML, break tags or
punctuation changes were used in any arm.

Samples were presented unlabelled and in randomised order, with durations and file
sizes withheld from the listening page.

### Result

**The owner selected the existing production configuration:**

- `eleven_turbo_v2_5`
- whole story in a single request
- no chunking
- no Request Stitching

Every alternative lost, including `eleven_multilingual_v2` — which is ElevenLabs' own
stated recommendation for long-form narration and audiobooks — and `eleven_v3`, which
their documentation lists for audiobook production.

### Operational conclusion

**Do not reopen model migration, paragraph chunking, or Request Stitching for the
current Bible PAL story pipeline without new listening evidence.**

This also retires the specific concern that prompted the experiment: ElevenLabs'
troubleshooting guidance recommends keeping requests under roughly 800–900 characters
to avoid degradation, and Bible PAL sends whole stories (1,400–2,900 characters) in one
request. That guidance is real, but at Bible PAL's lengths and with these voices it did
not produce an audible benefit when tested directly.

### Scope limitation — read this before citing the finding

This was **one controlled story with one narrator**. It does **not** prove that Turbo is
universally superior:

- Not for every narrator in the approved pool.
- Not for every story type. 1613 is dialogue-heavy narrative prose; poetry, epistles,
  oracles and wisdom literature were not tested.
- Not for future ElevenLabs models. Vendor models change; a new release invalidates this
  comparison rather than inheriting its conclusion.
- Not for the KJV lane, reflections, kid-lane content, or PAL/journey audio — only the
  adult Traditional WEB story lane was tested.

The finding is an instruction to **stop re-litigating a settled question**, not a
universal claim about TTS engineering.

---

## Finding B — prose-rhythm experiment

### What prompted it

Stories 1611–1615 measured as outliers against the existing corpus: shorter sentences
(≈11.9 words vs 15.5–19.7 in the 1200s–1400s), lower sentence-length variation
(SD ≈7.0 vs 9.7–13.4), and far more paragraphs (≈18 vs 7.7–12.6). The hypothesis was
that this fragmentation was why the batch sounded different.

### What was tested

Story **1613** was rewritten for rhythm only:

| | Original | Revised |
|---|---|---|
| Paragraphs | 25 | 10 |
| Narration sentence mean | ≈11.2 words | ≈15.1 words |
| Words | 499 | 499 |

Everything else was held identical — the same facts, all 14 quoted spans preserved
verbatim, same title, narrator, mood, bucket, model, voice settings and rendering
pipeline. The two were rendered identically and presented blind.

### Result

**The owner selected the original production text.**

### Operational conclusions

- **Do not rewrite approved stories merely to satisfy sentence-length, paragraph-count,
  or sentence-variation statistics.**
- **Do not build the proposed advisory corpus-rhythm gate.** It would have flagged
  stories the owner judges acceptable. A gate that fires on good content trains people
  to ignore it, and invites prose written to satisfy a validator rather than a listener.
- Rhythm measurements remain useful **diagnostic** information when investigating a
  reported problem. They are not an acceptance criterion.
- **Listening and editorial judgment remain authoritative.**

### Scope limitation — read this before citing the finding

This is a **null result for one specific proposed rewrite of one story**. It is *not*
proof that prose rhythm never matters.

What it does not establish:

- That the rewrite direction is wrong in general — a different rewrite of the same story
  might win.
- That sentence length is irrelevant to how narration sounds.
- That the measured difference between authoring models is unimportant. (For the record:
  `claude-opus-5` writes measurably shorter, more uniform sentences than
  `claude-fable-5` — 11.9 vs 16.0 words, SD 7.0 vs 8.9. That difference is real; this
  experiment merely found it did not degrade the listening experience for this story.)

### What remains valid

**Story-specific defects may and should still be corrected** when a listener identifies
a concrete problem — a bad pause, a stumble, a mispronunciation, a delivery issue.
Two such corrections were made successfully during this work:

- Story **1615** had an audible stumble mid-phrase. Re-rendering the *same text*
  resolved it, because ElevenLabs output is non-deterministic and it was a bad take.
- Story **1611** had an awkward mid-sentence pause. Re-rolling did **not** resolve it —
  the pause reproduced across two narrators and four takes, indicating a structural
  cause (a standalone one-line paragraph between two quoted passages) rather than an
  unlucky roll. The owner accepted a re-rolled take on other grounds.

The distinction is the useful part: **a concrete reported defect is actionable; a
statistical deviation is not.**

---

## Finding C — audio preservation (PERMANENT RULE)

Bible PAL follows a strict **never-delete-audio** rule.

### The rule

- **Never delete audio.** This covers production story audio, production reflection
  audio, narrator comparisons, model and pipeline tests, blind-test samples,
  pronunciation tests, pause rerolls, alternate takes, audio replaced by a later
  approved version, and temporary audio that consumed ElevenLabs credits.
- **Never overwrite an audio file** unless the prior version has first been preserved
  under a unique archival filename or location **and** the owner has explicitly
  authorized the replacement.
- **Storage cleanup means moving or archiving, never erasing.** When storage management
  eventually becomes necessary, audio may be relocated — not removed.
- **Archive the evidence with the audio.** Preserve the related reports, answer keys,
  request information, timestamps, checksums, source-text references and listening
  decisions alongside the files themselves. A recording without its provenance is much
  less useful later.

### Why

Audio produced with paid credits remains part of the project's **evidence and production
history** even when it is not the version shipped in the app. The rejected takes are what
make a finding like A or B verifiable months later; deleting them turns a documented
decision back into an opinion. Superseded renders also record what the narration used to
sound like, which matters for judging whether a later change was an improvement.

### Applies to

Both tracked production audio under `assets/stories/` and untracked experimental audio
under `scratchpad/`. Being untracked by git is **not** a licence to delete — untracked
experimental audio is precisely the material that cannot be recovered from history.

---

## Related records

The experimental artifacts behind Findings A and B — listening pages, answer keys,
per-arm technical measurements, rendered comparison audio, rhythm-revision drafts and
pause-reroll takes — are retained under `scratchpad/`. They are untracked by git and
must not be deleted (see Finding C).
