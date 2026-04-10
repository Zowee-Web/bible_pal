# R2 Android Verification — Cloud Foundation v1 + Smart Offline Library v1

This document is the go-live checklist for connecting Bible PAL Android to a
Cloudflare R2 bucket and proving end-to-end cloud-audio delivery on a real
device. It is the field guide that pairs with [SPEC.md](SPEC.md) Feature 27
and the Favorited Audio Protection Invariant in [INVARIANTS.md](INVARIANTS.md).

**Status preconditions:**
- `5ec4523` android: prep for Google Play Store release ✅ pushed
- `c281edf` Cloud Foundation v1 (R2 audio delivery + cache) ✅ pushed
- `d5f26de` Smart Offline Library v1 (silent favorite caching + soft eviction) ✅ pushed

---

## 1. Object-key contract (what the app expects from R2)

The Android resolver builds its R2 URL like this
([lib/services/parable_service.dart:814](../lib/services/parable_service.dart#L814)):

```dart
final url = Uri.parse('$baseUrl/$relativePath');
```

Where `relativePath` is `parable.audioFilePath` directly from
[assets/stories/manifest.json](../assets/stories/manifest.json). Manifest
paths look like:

```
creative/2000/audio_2000_story_short.mp3
creative/2000/audio_2000_story_full.mp3
creative/2000/audio_2000_story_long.mp3
traditional/1000/audio_1000_story_short.mp3
traditional/1000/audio_1000_story_full.mp3
traditional/1000/audio_1000_story_long.mp3
```

**Therefore the R2 bucket layout MUST mirror these paths exactly.** With
`AUDIO_BASE_URL=https://<host>[/<prefix>]` (no trailing slash), the resolved
URL for the first manifest entry is:

```
<host>[/<prefix>]/creative/2000/audio_2000_story_short.mp3
```

### Hard rules

| Rule | Reason |
|------|--------|
| Object keys are case-sensitive on R2; use lowercase exactly as in manifest | Manifest is canonical. Mismatch = 404 = `story_download_failed{error_type: http_404}` |
| `.mp3` extension preserved | The cache file path mirrors the manifest path; just_audio infers format from extension |
| `audio_NNNN_story_{short,full,long}.mp3` filename pattern | Hard-coded in the manifest. Don't rename. |
| `creative/NNNN/...` and `traditional/NNNN/...` directory layout | Hard-coded in the manifest |
| `AUDIO_BASE_URL` does NOT end with `/` | Code does naive `'$baseUrl/$relativePath'` concat (parable_service.dart:814) — trailing slash → `//` in URL. Most R2 endpoints tolerate this but it's a footgun |
| Files are publicly readable (no auth) | The app uses an unauthenticated `http.Client.send()` (parable_service.dart:835). Signed URLs are NOT supported in v1. |

### What does NOT need to be on R2

- **Story text files** (`*.txt`) — bundled in the AAB on both platforms
- **Scripture text files** (`scripture_*.txt`) — bundled in the AAB
- **Manifest** (`manifest.json`) — bundled
- **Reflection audio** (`audio_*_reflection.mp3`) — currently loaded by a
  separate code path that does NOT route through `getAudioFile`. R2-hosting
  reflections is reserved for a later sub-feature.

---

## 2. R2 deployment checklist

### Bucket setup
- [ ] Create an R2 bucket named e.g. `bible-pal-audio`
- [ ] Enable **public access** for the bucket
  - Either: enable the public r2.dev URL on the bucket
  - Or: attach a custom domain (e.g. `audio.biblepal.app`) via Cloudflare DNS
- [ ] Test public access in a browser BEFORE uploading anything: visit the
  bucket root URL — you should get an XML listing or `AccessDenied` (if listing
  is off) but NOT a DNS failure

### CORS
- **CORS is NOT required for v1.** The Android app uses native `package:http`
  which is not subject to CORS. Only set CORS if you ever access the same R2
  bucket from a web build of the app or a browser-embedded preview.

### URL format
- `AUDIO_BASE_URL` must be exactly: `https://<host>[/<optional-prefix>]`
- **No trailing slash.** Example: `https://pub-abc123.r2.dev` (not
  `https://pub-abc123.r2.dev/`)
- Optional prefix is fine if you scope the bucket: e.g.
  `https://pub-abc123.r2.dev/v1` would expect objects at
  `v1/creative/2000/audio_2000_story_short.mp3`
- For a flat layout (no prefix), upload directly under `creative/...` and
  `traditional/...`

### Manual browser smoke test (do this BEFORE building the Android app)

After uploading even a single canary file, paste this URL into a browser:

```
<AUDIO_BASE_URL>/creative/2016/audio_2016_story_short.mp3
```

Expected: the browser downloads or plays the MP3. If you see XML, JSON,
HTML, or any HTTP error, **stop and fix R2 access before touching the app**.

---

## 3. Canary upload set (smallest meaningful)

Upload exactly these files first. Do not upload the whole library yet.

| # | R2 object key | Why |
|---|---|---|
| 1 | `traditional/1016/audio_1016_story_short.mp3` | Non-seed traditional story → exercises the Tier 3 R2 download path |
| 2 | `creative/2016/audio_2016_story_short.mp3` | Non-seed creative story → exercises the other mode subdir |
| 3 | `traditional/1000/audio_1000_story_full.mp3` | A SEED story's FULL length — these are stripped from the AAB by `scripts/build_android.sh` even though the seed dir is bundled. Proves stripped files recover from R2. |

**Total: 3 files, ~9 MB.** Source files live at:
- `assets/stories/traditional/1016/audio_1016_story_short.mp3`
- `assets/stories/creative/2016/audio_2016_story_short.mp3`
- `assets/stories/traditional/1000/audio_1000_story_full.mp3`

### Why these specific stories
- **1016 / 2016**: First non-seed IDs (seed range is 1000-1015 / 2000-2015).
  Guaranteed to NOT be in the bundled AAB regardless of which seed strategy
  the build script uses.
- **1000 full**: Tests the build-script-stripped case — file is in the seed
  dir on disk during dev, but the build script moves it aside so the AAB
  doesn't ship it. R2 must be able to serve it.

### Why NOT to test with a seed-short canary

If you upload `traditional/1000/audio_1000_story_short.mp3` and then test
that story on Android, the resolver will hit Tier 2 (bundled asset) and
short-circuit before ever reaching R2. You'll think R2 is working when
nothing was actually fetched. **Always pick a non-seed story or a non-short
length of a seed story for canary tests.**

---

## 4. Step-by-step execution plan

### Step 1 — R2 setup
1. Create the R2 bucket
2. Enable public access (r2.dev URL or custom domain)
3. Note the public base URL — this becomes `AUDIO_BASE_URL`

### Step 2 — Upload canary files
1. Upload the 3 files from §3 with the exact object keys shown
2. Browser smoke test: open one of the URLs directly in a browser
3. Confirm the browser downloads/plays MP3 audio

### Step 3 — Update `.env`
1. Open [.env](../.env)
2. Replace `AUDIO_BASE_URL=https://REPLACE_WITH_R2_URL` with the real URL
3. **No trailing slash.** Save.
4. `.env` is git-ignored — this is a local-only change

### Step 4 — Build & install Android
```bash
./scripts/build_android.sh
xcrun devicectl device install app --device <device> \
  build/app/outputs/bundle/release/app-release.aab
```
(Or use Android Studio / `adb install` of an APK extracted from the AAB.)

### Step 5 — First playback test (Flow A: cloud download)
1. Launch the app, complete onboarding
2. With **Wi-Fi ON**, browse to `traditional/1016` (e.g. via mood selection
   that surfaces it; or via debug build's story picker if you have one)
3. Tap play
4. **Expected:** circular download progress indicator appears briefly,
   then audio plays
5. **If it fails:** see §6 debug paths

### Step 6 — Favorite + offline replay test (Flow B: silent caching)
1. Stop playback, tap the favorite icon
2. **Expected:** no new UI. Favorite icon toggles. Done.
3. Force-quit the app
4. **Switch to airplane mode** (Wi-Fi off, cellular off)
5. Reopen app, navigate to Favorites
6. Tap the favorited story
7. **Expected:** plays immediately, no download indicator, no error
8. As a control: try a non-favorited non-seed story → expected to fail
   ("Audio file not found"). Proves the favorite was actually cached.

### Step 7 — Cache sanity (optional, quick)
```bash
adb shell run-as com.zaiwietech.biblepal ls -la files/audio_cache/traditional
adb shell run-as com.zaiwietech.biblepal ls -la files/audio_cache/creative
adb logcat | grep -E "story_download_(started|completed|failed)|cache_eviction|story_cache_hit"
```
- Confirm files appear under `files/audio_cache/` mirroring the manifest
  path structure
- Watch logs during a fresh play of `traditional/1000/audio_1000_story_full.mp3`
  (a stripped seed-dir file): you should see `story_download_started` →
  `story_download_completed`, NOT `cache_hit` or `audio_asset_missing`

### Step 8 — Rollback / debug paths

**If Step 5 (first playback) fails:**

| Symptom | Likely cause | Fix |
|---|---|---|
| `story_download_failed{error_type: missing_base_url}` in logs | `.env` not loaded or `AUDIO_BASE_URL` empty | Check `.env`, rebuild |
| `story_download_failed{error_type: http_404}` | R2 object key doesn't match manifest path | Use exact lowercase path from manifest, check for typos in folder/filename |
| `story_download_failed{error_type: http_403}` | Bucket not public, or path requires auth | Re-verify R2 public access setting |
| `story_download_failed{error_type: SocketException}` | DNS/network issue, wrong host | Test the URL in a browser from the same network |
| `story_download_failed{error_type: TimeoutException}` | R2 too slow on first byte (>30s) | Unlikely on R2; check device network |
| Plays instantly with no download indicator | Hit Tier 2 (bundled asset) — not actually testing R2 | You picked a seed story; switch to a non-seed story or a stripped length |

**If Step 6 (offline replay) fails:**

| Symptom | Likely cause | Fix |
|---|---|---|
| Download indicator appears in airplane mode | Favorite-trigger-cache hook didn't fire OR didn't complete before airplane mode | Check `app_state_notifier.dart:241-245` is intact; favorite the story while online and wait ~5s before airplane mode |
| "Audio file not found" error | The favorited audio was never downloaded | Check logs from when you favorited; look for `story_download_completed` event with the right `story_id` |
| Story plays but logs show `story_cache_hit` from wrong story | Path mismatch in `_getProtectedAudioPaths` | Verify the manifest entry's `audioFilePath` field exactly equals the R2 object key |

**Rollback (worst case):**
- Set `AUDIO_BASE_URL=` (empty) in `.env` and rebuild — the app falls back
  to bundled-only behavior. Non-seed stories will fail to load with
  `missing_base_url` but seed stories continue to work.

---

## 5. Audit findings (current code state, no fixes applied)

These are observations from auditing the live code. None are blockers; they
are sharp edges you should be aware of.

### A. Placeholder still in `.env` — BLOCKER
[.env line 2](../.env): `AUDIO_BASE_URL=https://REPLACE_WITH_R2_URL`
**Action:** must replace with live URL before any device test.

### B. Naive URL join — minor footgun
[parable_service.dart:814](../lib/services/parable_service.dart#L814):
`Uri.parse('$baseUrl/$relativePath')`. If `AUDIO_BASE_URL` ends with a
trailing slash, you get `https://host//creative/...`. Most R2 / Cloudflare
endpoints handle this gracefully but it's not RFC-strict.
**Mitigation:** enforce no trailing slash in §2 of this checklist; consider
hardening with `baseUrl.replaceAll(RegExp(r'/$'), '')` if it ever bites.

### C. Reflection audio is NOT routed through R2
The R2 download path only handles `parable.audioFilePath`, not
`parable.reflectionAudioPath`. Reflections are loaded via a separate code
path. For seed stories on Android, reflections are bundled and work. For
non-seed stories on Android, reflections may not load correctly until a
follow-up wires them through the same resolver. **Track as a known limitation.**

### D. Seed-short stories will never exercise R2 in testing
This is by design (Tier 2 short-circuit) but it's the most likely tester
mistake. The canary set in §3 specifically avoids this trap.

### E. Cache directory is shared across all platforms
[parable_service.dart:636-643](../lib/services/parable_service.dart#L636-L643):
`audio_cache/` is created under `getApplicationDocumentsDirectory()` on
every platform that calls `_getAudioCacheDir()`. Currently that's only
Android (the iOS branch never calls it). If a future change accidentally
calls cache helpers on iOS, it would create a stray directory. Low risk.

### F. URL-encoding is implicit
`Uri.parse` does NOT percent-encode path segments — it parses them as-is.
All current manifest paths are ASCII alphanumerics + `_` + `/` + `.`, so no
encoding is needed. **If a future story ever has a space, hash, or non-ASCII
character in its filename, this will break silently.** The pattern enforced
by `audio_NNNN_story_{short,full,long}.mp3` keeps us safe today.

### G. `AUDIO_BASE_URL` is read on every download, not cached
[parable_service.dart:804](../lib/services/parable_service.dart#L804):
`dotenv.maybeGet('AUDIO_BASE_URL')` runs on every download. This is fine
(it's a hashmap lookup) but means you can't change the URL at runtime. To
change it: edit `.env`, rebuild.

---

## 6. Top 5 likely failure causes (ranked most → least likely)

1. **Placeholder still in `.env`** — `https://REPLACE_WITH_R2_URL` is the
   current value. Highest probability cause of "first try doesn't work."
   Symptom: `story_download_failed{error_type: SocketException}` or DNS
   resolution failure in logs.

2. **R2 bucket not publicly accessible** — first-time R2 setup commonly
   leaves the bucket private. Symptom: `http_403` in download logs, OR
   the browser smoke test from §2 returns AccessDenied XML.

3. **Object key path mismatch** — uploading `2016.mp3` instead of
   `creative/2016/audio_2016_story_short.mp3`, or accidentally adding/
   omitting the `audio_` prefix, or wrong directory case. Symptom:
   `http_404` in logs. **Always copy paths from the manifest, never hand-type.**

4. **Testing with a seed-short story** — story plays instantly with no
   network activity. Tester believes R2 works but it was never hit. Use
   the canary set in §3 to avoid this.

5. **`AUDIO_BASE_URL` has a trailing slash** — produces `//` in the URL.
   R2 r2.dev endpoints handle this but custom domains via certain CDNs
   may not. Low probability of breakage but non-zero. Check by visually
   inspecting `.env` after edit.

---

## Done conditions

You can declare R2 cloud audio delivery verified for Bible PAL Android when
ALL of the following are true:

- [ ] Browser smoke test (§2) succeeds for at least one canary file
- [ ] Step 5 (first playback test) plays a non-seed story successfully
- [ ] Step 6 (offline replay) plays a favorited non-seed story in airplane mode
- [ ] Step 7 logs show `story_download_completed` events with matching
      `story_id`s, and no unexpected `story_download_failed` events
- [ ] iOS regression pass (separate doc / manual checklist) confirms no
      iOS playback regression

Once verified, the next step is uploading the full audio library to R2
(not covered in this doc).
