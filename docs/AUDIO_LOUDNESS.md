# Audio Loudness Pipeline

Bible PAL ships every story at a consistent loudness so the user does not have
to adjust their phone volume between stories. This document explains where the
raw renders live, where the published normalized audio lives, why the target
is **−18 LUFS**, and how to keep them in sync.

---

## Two audio trees — never confuse them

| Tree | Path | Role | Loudness |
|------|------|------|----------|
| **Raw source** | `assets/stories/traditional/` | Original ElevenLabs render output. Treat as source of truth. **Never modified, never shipped.** | Uneven by design — varies per generation and per voice (~−18 to −28 LUFS). |
| **Published normalized** | `assets_audio_compressed/stories/traditional/` | Compressed mp3s that the iOS bundle, Android AAB, and R2 publish from. | All files normalized to **−18 LUFS** (±1 LU tolerance). |

**Rule:** if you measure the raw source tree and the files look loudness-uneven,
that's expected — it's the input, not the output. Always measure
`assets_audio_compressed/stories/` when validating the published loudness.

---

## Target — −18 LUFS

| Parameter | Value | Reason |
|-----------|-------|--------|
| Integrated loudness (I) | **−18 LUFS** | Calibrated by ear against Adam's preferred stories (1022 / 1154 / 1221) on June 12 2026. −16 (Apple Podcasts) felt too aggressive; −20 felt too quiet relative to the louder good stories. −18 keeps the loud-end stories near unchanged while pulling the quiet outliers (e.g. 1515 Stone-Cut-Without-Hands at −27.5 raw) up by ~9 dB. |
| True peak (TP) | **−1.5 dBTP** | Prevents inter-sample clipping on consumer DACs while leaving full headroom for the boost on the quietest sources. |
| Loudness range (LRA) | **11 LU** | Standard EBU R128 spoken-word target. Wide enough that loudnorm runs in `linear=true` mode for most narration without aggressive limiting. |
| Head pad | **300 ms** | Silence at file start so playback never clips the narrator's first phoneme. |
| Tail pad | **500 ms** | Silence at end. Existing `generate_audio.py` adds a 400 ms tail pad as the v3 clip-bug workaround; total trailing silence on the published file ends up ~900 ms. Acceptable for the contemplative pacing of the app. |
| Fade in / out | **30 ms** | Eliminates any micro-click at file edges. |
| Encoder | **libmp3lame, 64 kbps CBR, mono, 22050 Hz** | Matches the existing bundle quality profile. The smaller files were A/B'd vs 44100/128 and judged equivalent for spoken word on a phone. |

The values are hard-coded into [`scripts/loudnorm_audio.sh`](../scripts/loudnorm_audio.sh).
Change them there only with corresponding doc + memory updates.

---

## The two scripts

### `scripts/loudnorm_audio.sh` — the primitive

One file in, one file out. Two-pass EBU R128 loudnorm with the locked encoder
profile. Idempotent: skip if output exists, `--force` to overwrite.

```
./scripts/loudnorm_audio.sh <input.mp3> <output.mp3> [--force]
```

Use it directly for ad-hoc sweeps, test renders, or any one-off normalization.

### `scripts/compress_audio.sh` — the sweep

Walks every `*.mp3` in `assets/stories/` and produces a mirror in
`assets_audio_compressed/stories/`. Internally delegates per-file encoding to
`loudnorm_audio.sh`, so every output is automatically normalized to −18 LUFS.

```
./scripts/compress_audio.sh             # compress missing + refresh stale
./scripts/compress_audio.sh --verify    # count + stale check, no writes
./scripts/compress_audio.sh --dry-run   # preview, no writes
```

The `compress_audio.sh` script is mtime-aware: it only re-runs the loudnorm
pipeline on a file whose raw source has been re-rendered (`raw_mtime > dst_mtime`)
or has no destination at all. Otherwise it skips.

---

## When to run the sweep

Run `./scripts/compress_audio.sh` before any of:

- A TestFlight or App Store / Play Store release build.
- A R2 audio upload (once R2 normalization is wired up — currently deferred).
- An ad-hoc device install (`build_ios_bundle.sh`).
- After any new story batch is rendered through `generate_audio.py`.

The script is safe to run repeatedly — current files are skipped, only changed
or new files get reprocessed. There is no need to manually backfill.

---

## History — the June 12 2026 backfill

Before June 12 2026, `assets_audio_compressed/stories/` contained re-encoded
copies of the raw source with **no loudness normalization**. Loudness drift
across stories was ~8.5 LU; KJV stories felt noticeably quieter than WEB,
and some Adam-labelled stories (e.g. 1515) were ~10 dB below the median.

On June 12 we:

1. Calibrated against 6 sample stories (1022, 1077, 1154 WEB/KJV, 1221, 1515)
   landing on −18 LUFS as the target after ear-testing −20 and (briefly) −18.
2. Ran a one-shot 8-way parallel sweep of all 2,644 files in the compressed
   mirror through the now-locked two-pass loudnorm pipeline.
3. Atomic-swapped the new normalized mirror into place; preserved the pre-sweep
   mirror at `assets_audio_compressed/stories_pre_loudnorm_2026-06-12/` as a
   safety net.
4. Verified output: mean −18.55 LUFS, max−min spread 0.46 LU, 0 files outside
   the ±1 LU tolerance window.

The backfill is complete. Going forward, `compress_audio.sh` keeps the
published mirror at −18 LUFS automatically — no manual backfill required.

---

## Common pitfalls

- **Measuring the raw tree and concluding loudness is broken.** The raw tree
  is *expected* to be uneven. Measure `assets_audio_compressed/stories/`.
- **Rendering new stories without re-running `compress_audio.sh`.** New raw
  files won't ship until the sweep runs. The script is mtime-aware so a
  one-line invocation is enough; just don't forget it.
- **Tweaking parameters in `loudnorm_audio.sh` without updating this doc.**
  The hard-coded values are the calibration, not arbitrary defaults. Changes
  must be coordinated with a doc update so the calibration story stays clear.
- **Confusing `assets_audio_compressed/stories_pre_loudnorm_2026-06-12/` for
  the live mirror.** The `_pre_loudnorm_*` suffix is the backup; the live
  mirror is the unsuffixed `assets_audio_compressed/stories/`.

---

## R2 audio (deferred)

R2-served audio (KJV variants, _long variants, stories without bundled audio)
is currently **not** normalized. The R2 bucket holds the original
~44100 Hz / 128 kbps renders at their un-normalized loudness. Until that
slice lands, expect:

- KJV stories played through the app to sound noticeably quieter than the
  bundled WEB stories.
- Long stories fetched from R2 to sound quieter than the bundled short / full.

The fix is to upload the normalized compressed mirror to R2 with the same
relative paths. That work is intentionally separated from the local sweep.
See conversation history of June 12 2026 for the full diagnosis.
