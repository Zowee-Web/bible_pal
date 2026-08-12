#!/usr/bin/env python3
"""Publisher regression tests for the Catalog Currency invariant.

Four layers, no R2 contact and no Cloudflare authentication anywhere:

1. The comprehensive validator (scripts/validate_catalog_manifest.py) —
   the publisher's single validation path — is driven directly across the
   ACTIVE CATALOG CONTRACT: the runtime-acceptance matrix derived from
   CatalogService + Parable.fromJson (lib/models/parable.dart), plus
   identity/uniqueness, exact (never normalized) translation values,
   active storytelling mode, supported length buckets and safe relative
   asset paths.
2. Contract parity: the Dart and Python halves of that contract are
   compared directly, so neither can drift without the other.
3. The real scripts/upload_r2_catalog.sh is executed against a STUB
   wrangler executable, proving that every failed or indeterminate remote
   read is classified UNKNOWN — absence is NEVER inferred from stderr —
   and that none of them can reach an object put.
4. The full stateful push path against a stub remote: successful PUT,
   PUT failure, remote changed during the pre-PUT recheck, post-PUT
   mismatch, and UNKNOWN state.

Run:
    python3 -m unittest scripts.tests.test_upload_r2_catalog_publisher -v
"""

import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "tests"))

import hermetic_env as henv  # noqa: E402
import validate_catalog_manifest as vcm  # noqa: E402

PUBLISHER = REPO_ROOT / "scripts" / "upload_r2_catalog.sh"


class HermeticPublisherHarness:
    """Shared, structurally hermetic way to run the real publisher.

    PATH is exactly one scenario-owned directory, so `wrangler` resolves to
    the test stub or to nothing at all. A genuinely installed and
    authenticated wrangler in /usr/local/bin, /opt/homebrew/bin or an
    npm/nvm shim directory is unreachable BY CONSTRUCTION, not by
    filtering — and no cloud credentials are inherited.
    """

    def _make_harness(self, tmp: pathlib.Path) -> dict:
        bin_dir = henv.make_bin(tmp / "bin", henv.PUBLISHER_TOOLS)
        env = henv.hermetic_env(bin_dir, tmp / "home", tmp / "tmp")
        henv.assert_path_is_hermetic(self, env, bin_dir)
        henv.assert_no_cloud_credentials(self, env)
        return {"bin": bin_dir, "env": env, "stub": bin_dir / "wrangler"}

    def _run_hermetic(self, harness: dict, *args: str,
                      expect_stub: bool = True):
        # Asserted on EVERY run that can reach a push-capable path: the
        # wrangler about to be executed is the stub, or none exists.
        if expect_stub:
            henv.assert_wrangler_is_stub(self, harness["env"],
                                         harness["stub"])
        else:
            henv.assert_no_wrangler_resolvable(self, harness["env"])
        return subprocess.run(
            [str(PUBLISHER), *args],
            env=harness["env"], capture_output=True, text=True, check=False,
            timeout=300, cwd=str(REPO_ROOT))

# Minimal entry satisfying the full ACTIVE CATALOG CONTRACT — not merely
# Parable.fromJson.
def _entry(**overrides):
    base = {
        "storyId": "story_pub_test_001",
        "title": "Publisher Test Story",
        "mood": "joyful",
        "storytellingMode": "traditional",
        "translationId": "WEB",
        "languageStyle": "WEB",
        "kidFriendly": False,
        "storyLength": "short",
        "textFilePath": "traditional/9999/story_9999_traditional_web_short.txt",
        "audioFilePath": "traditional/9999/audio_9999_story_short.mp3",
    }
    base.update(overrides)
    # Allow removing a key by passing <key>=None with _remove semantics
    # handled explicitly by callers via dict operations instead.
    return base


def _catalog(version=5, parables=None, **root_extra):
    m = {"version": version,
         "parables": parables if parables is not None else [_entry()]}
    m.update(root_extra)
    return m


def _errors(manifest, body_bytes=1000, max_bytes=None, max_entries=None):
    kwargs = {}
    if max_bytes is not None:
        kwargs["max_bytes"] = max_bytes
    if max_entries is not None:
        kwargs["max_entries"] = max_entries
    return vcm.validate_catalog(manifest, body_bytes, **kwargs)


class ValidatorMatrixTests(unittest.TestCase):
    """The single validation path must mirror runtime acceptance."""

    def test_valid_catalog_passes(self):
        self.assertEqual(_errors(_catalog()), [])

    def test_valid_catalog_with_optional_fields_passes(self):
        entry = _entry(
            emotionalTags=["hopeful"], length=10, bibleOrderIndex=3,
            characterPathOrder=1, shortScripture=True, kidFriendly=True,
            scriptureSources=["John 3:16"], characterIds=["david"],
            characterDisplayNames=["David"], themeTags=["trust"],
            scriptureKeyVerse={"ref": "John 3:16", "text": "…"},
            generatedAt="2026-08-11T12:00:00", bibleSourceRef="John 3",
            bibleStoryKey="john_3", narratorVoiceKey="VOICE_BRADFORD",
        )
        self.assertEqual(_errors(_catalog(parables=[entry])), [])

    def test_empty_parables_rejected(self):
        errs = _errors(_catalog(parables=[]))
        self.assertTrue(any("EMPTY" in e for e in errs), errs)

    def test_empty_object_entry_rejected(self):
        errs = _errors(_catalog(parables=[{}]))
        self.assertTrue(any("storyId" in e for e in errs), errs)
        self.assertTrue(any("required" in e for e in errs), errs)

    def test_missing_required_field_rejected(self):
        entry = _entry()
        del entry["title"]
        errs = _errors(_catalog(parables=[entry]))
        self.assertTrue(any(".title" in e for e in errs), errs)

    def test_wrong_required_type_rejected(self):
        errs = _errors(_catalog(parables=[_entry(mood=3)]))
        self.assertTrue(any(".mood" in e for e in errs), errs)

    def test_wrong_optional_types_rejected(self):
        # Every shape here makes the corresponding Dart `as` cast in
        # Parable.fromJson throw at runtime.
        cases = [
            ({"kidFriendly": "yes"}, ".kidFriendly"),
            ({"shortScripture": 1}, ".shortScripture"),
            ({"length": 6.5}, ".length"),
            ({"length": True}, ".length"),          # bool is not int
            ({"bibleOrderIndex": 2.0}, ".bibleOrderIndex"),
            ({"emotionalTags": "alone"}, ".emotionalTags"),
            ({"characterIds": [1, 2]}, ".characterIds"),
            ({"scriptureKeyVerse": ["ref"]}, ".scriptureKeyVerse"),
            ({"generatedAt": 12345}, ".generatedAt"),
            ({"generatedAt": "not-a-date"}, ".generatedAt"),
            ({"narratorVoiceKey": 7}, ".narratorVoiceKey"),
        ]
        for overrides, needle in cases:
            with self.subTest(overrides=overrides):
                errs = _errors(_catalog(parables=[_entry(**overrides)]))
                self.assertTrue(any(needle in e for e in errs),
                                f"{overrides} → {errs}")

    def test_non_allowlisted_translation_rejected(self):
        # The allowlist gate rejects ANY id outside {WEB, KJV, ASV, YLT,
        # DRA} — banned copyrighted ids and unknown ids alike take this
        # exact branch. A neutral unknown id is used so no banned
        # translation literal ever enters the repo.
        for key in ("translationId", "languageStyle"):
            with self.subTest(field=key):
                errs = _errors(_catalog(parables=[_entry(**{key: "XYZ"})]))
                self.assertTrue(
                    any(key in e and "banned/unknown" in e for e in errs),
                    errs)

    def test_excessive_entries_rejected(self):
        parables = [
            _entry(storyId=f"story_pub_test_{i:03d}") for i in range(3)
        ]
        errs = _errors(_catalog(parables=parables), max_entries=2)
        self.assertTrue(any("entry_count" in e for e in errs), errs)

    def test_oversized_body_rejected(self):
        errs = _errors(_catalog(), body_bytes=10_000, max_bytes=1_000)
        self.assertTrue(any("size" in e for e in errs), errs)

    def test_invalid_version_shapes_rejected(self):
        for bad in (None, True, False, "5", 0, -1, 5.5):
            with self.subTest(version=bad):
                m = _catalog()
                if bad is None:
                    del m["version"]
                else:
                    m["version"] = bad
                errs = _errors(m)
                self.assertTrue(any("version" in e for e in errs), errs)

    def test_root_must_be_object(self):
        self.assertTrue(_errors([_entry()]))
        self.assertTrue(_errors("nope"))

    def test_int64_range_boundaries(self):
        # Dart ints are signed 64-bit; a JSON integer outside that range
        # decodes as double in the Dart VM and the runtime `as int` cast
        # throws — so the publisher must reject it.
        int64_max = 2 ** 63 - 1
        int64_min = -(2 ** 63)

        # version: valid max passes; 2^63 is rejected long before any
        # shell arithmetic could see it.
        self.assertEqual(_errors(_catalog(version=int64_max)), [])
        errs = _errors(_catalog(version=2 ** 63))
        self.assertTrue(any("version" in e for e in errs), errs)

        # Optional int fields: the full signed-64 range is structurally
        # valid; one-past either bound is rejected.
        self.assertEqual(
            _errors(_catalog(parables=[_entry(length=int64_min)])), [])
        self.assertEqual(
            _errors(_catalog(parables=[_entry(length=int64_max)])), [])
        self.assertEqual(
            _errors(_catalog(
                parables=[_entry(characterPathOrder=int64_max)])), [])
        for overrides, needle in (
            ({"length": 2 ** 63}, ".length"),
            ({"length": int64_min - 1}, ".length"),
            ({"bibleOrderIndex": 2 ** 63}, ".bibleOrderIndex"),
            ({"characterPathOrder": int64_min - 1}, ".characterPathOrder"),
        ):
            with self.subTest(overrides=overrides):
                errs = _errors(_catalog(parables=[_entry(**overrides)]))
                self.assertTrue(any(needle in e for e in errs), errs)

    def test_nonstandard_json_constants_rejected(self):
        # Python's json.loads accepts NaN/Infinity/-Infinity; Dart's
        # jsonDecode does not. loads_strict must fail closed on all three,
        # even inside unknown/ignored fields, and the CLI must reject the
        # whole catalog.
        valid_entry = json.dumps(_entry())
        bodies = [
            '{"version":6,"parables":[' + valid_entry + '],"x":NaN}',
            '{"version":6,"parables":[' + valid_entry + '],"x":Infinity}',
            '{"version":6,"parables":[' + valid_entry + '],"x":-Infinity}',
            # Inside an unknown ENTRY field too.
            ('{"version":6,"parables":[' +
             valid_entry[:-1] + ',"unknownExtra":NaN}]}'),
        ]
        for body in bodies:
            with self.subTest(body=body[-30:]):
                with self.assertRaises(ValueError):
                    vcm.loads_strict(body)
                with tempfile.TemporaryDirectory() as tmpdir:
                    path = pathlib.Path(tmpdir) / "catalog.json"
                    path.write_text(body)
                    result = subprocess.run(
                        [sys.executable,
                         str(REPO_ROOT / "scripts" /
                             "validate_catalog_manifest.py"),
                         str(path)],
                        capture_output=True, text=True, check=False)
                    self.assertEqual(result.returncode, 1, result.stdout)
                    self.assertIn("parse failed", result.stderr)

    def test_generated_at_publisher_grammar(self):
        # Canonical ISO instants (what Dart's toIso8601String produces and
        # DateTime.parse accepts) pass.
        accepted = [
            "2026-08-11T12:00:00",
            "2026-08-11T12:00:00.123",
            "2026-08-11T12:00:00.123456",
            "2026-08-11T12:00:00Z",
            "2026-08-11T12:00:00.123456Z",
            "2026-08-11T12:00:00+05:30",
            "2026-08-11T12:00:00+04:00",
            "2026-08-11T12:00:00-08:00",
        ]
        for ts in accepted:
            with self.subTest(ts=ts):
                self.assertEqual(
                    _errors(_catalog(parables=[_entry(generatedAt=ts)])),
                    [])
        # Forms broader Python parsers may accept but the publisher grammar
        # must reject — including every Codex-discovered Python-only form.
        rejected = [
            "2026-W33-1",                    # ISO week date
            "2026-08-11x12:00:00",           # arbitrary separator
            "2026-08-11T12:00:00+01:02:03",  # tz offset with seconds
            "2026-08-11 12:00:00",           # space separator (narrower than Dart)
            "2026-08-11",                    # date-only (narrower than Dart)
            "20260811T120000",               # basic (undelimited) form
            "2026-13-40T00:00:00",           # impossible calendar date
            "2026-08-11T25:00:00",           # impossible clock time
            # Unicode-digit parity: Python \d matches these, Dart's parser
            # does not — the grammar is explicitly [0-9]-only.
            "٢٠٢٦-٠٨-١١T١٢:٠٠:٠٠",           # Arabic-Indic core date/time
            "2026-08-11T12:00:00.１２３",     # fullwidth digits in fraction
            "2026-08-11T12:00:00+٠٥:٠٠",     # Arabic-Indic digits in offset
            "2026-08-11T12:00:00+05:３０",    # fullwidth digit in offset min
            # Full-string consumption: $ can match before a trailing
            # newline — fullmatch() must reject any trailing bytes.
            "2026-08-11T12:00:00\n",         # trailing LF
            "2026-08-11T12:00:00Z\n",        # trailing LF after Z
            "2026-08-11T12:00:00.123456\n",  # trailing LF after fraction
            "\n2026-08-11T12:00:00",         # leading LF
            "2026-08-11T12:00:00 ",          # trailing space
        ]
        for ts in rejected:
            with self.subTest(ts=ts):
                errs = _errors(_catalog(parables=[_entry(generatedAt=ts)]))
                self.assertTrue(any(".generatedAt" in e for e in errs),
                                f"{ts!r} must be rejected → {errs}")

    def test_translation_values_are_exact_never_normalized(self):
        # EXACT canonical match. Nothing is upper-cased, nothing is trimmed.
        #
        # Case folding is not a harmless convenience here: Parable.fromJson
        # maps any languageStyle that is not literally "KJV" to "WEB", so a
        # lowercase "kjv" that survives validation is silently converted
        # into a DIFFERENT translation and a KJV story is served with WEB
        # diction. A non-canonical value is a defect to reject, never
        # something to normalize.
        for ok in ("WEB", "KJV"):
            with self.subTest(value=ok):
                self.assertEqual(
                    _errors(_catalog(
                        parables=[_entry(translationId=ok,
                                         languageStyle=ok)])),
                    [])
        # translationId may carry any canonical registry id.
        for ok in ("ASV", "YLT", "DRA"):
            with self.subTest(translationId=ok):
                self.assertEqual(
                    _errors(_catalog(
                        parables=[_entry(translationId=ok,
                                         languageStyle="WEB")])),
                    [])
        # Case variants are REJECTED, not folded.
        for bad in ("web", "kjv", "Kjv", "Asv", "ylt", "dra", "wEb"):
            for key in ("translationId", "languageStyle"):
                with self.subTest(value=bad, field=key):
                    errs = _errors(
                        _catalog(parables=[_entry(**{key: bad})]))
                    self.assertTrue(
                        any(key in e for e in errs),
                        f"{bad!r} in {key} must be rejected, never "
                        f"normalized -> {errs}")
        # Wrapped / non-ASCII values stay rejected too.
        for bad in (" WEB ", "\u001cWEB\u001c", "WEB\n", "\tKJV", "W\u00c9B"):
            for key in ("translationId", "languageStyle"):
                with self.subTest(value=bad, field=key):
                    errs = _errors(
                        _catalog(parables=[_entry(**{key: bad})]))
                    self.assertTrue(
                        any(key in e for e in errs),
                        f"{bad!r} in {key} must be rejected -> {errs}")
        # languageStyle is narrower than the registry: the app can only
        # represent WEB and KJV diction.
        for bad in ("ASV", "YLT", "DRA"):
            with self.subTest(languageStyle=bad):
                errs = _errors(
                    _catalog(parables=[_entry(languageStyle=bad)]))
                self.assertTrue(
                    any("languageStyle" in e for e in errs), errs)

    def test_storytelling_mode_must_be_active(self):
        for bad in ("creative", "Traditional", "micro", "", "TRADITIONAL"):
            with self.subTest(mode=bad):
                errs = _errors(
                    _catalog(parables=[_entry(storytellingMode=bad)]))
                self.assertTrue(
                    any("storytellingMode" in e for e in errs), errs)

    def test_blank_identity_fields_rejected(self):
        for key in ("storyId", "title", "mood", "storytellingMode"):
            for blank in ("", "   ", "\t", "\n"):
                with self.subTest(field=key, blank=repr(blank)):
                    errs = _errors(_catalog(parables=[_entry(**{key: blank})]))
                    self.assertTrue(
                        any(key in e for e in errs),
                        f"blank {key}={blank!r} must be rejected -> {errs}")

    def test_duplicate_story_ids_rejected(self):
        errs = _errors(_catalog(parables=[
            _entry(storyId="story_dupe"),
            _entry(storyId="story_dupe"),
        ]))
        self.assertTrue(any("duplicate story id" in e for e in errs), errs)
        self.assertEqual(_errors(_catalog(parables=[
            _entry(storyId="story_a"),
            _entry(storyId="story_b"),
        ])), [])

    def test_story_length_must_be_supported_bucket(self):
        for bad in ("medium", "SHORT", "micro", "Full"):
            with self.subTest(storyLength=bad):
                errs = _errors(_catalog(parables=[_entry(storyLength=bad)]))
                self.assertTrue(any("storyLength" in e for e in errs), errs)
        for ok in ("short", "full", "long"):
            with self.subTest(storyLength=ok):
                self.assertEqual(
                    _errors(_catalog(parables=[_entry(storyLength=ok)])), [])

    def test_required_serving_anchor_text_file_path(self):
        entry = _entry()
        del entry["textFilePath"]
        errs = _errors(_catalog(parables=[entry]))
        self.assertTrue(any("textFilePath" in e for e in errs), errs)
        errs = _errors(_catalog(parables=[_entry(textFilePath="")]))
        self.assertTrue(any("textFilePath" in e for e in errs), errs)

    def test_unsafe_asset_paths_rejected(self):
        unsafe = [
            "/etc/passwd",                        # absolute
            "../../etc/passwd",                   # parent traversal
            "traditional/../../secrets.txt",      # traversal mid-path
            "traditional/./story.txt",            # non-normalized
            "traditional//story.txt",             # empty segment
            "traditional\\9999\\story.txt",       # windows separator
            "traditional/9999/story .txt",        # embedded whitespace
            " traditional/9999/story.txt",        # leading whitespace
            "traditional/9999/story.txt\n",       # trailing control char
            "~/story.txt",
            "C:/story.txt",
            "traditional/9999/story.txt/..",
        ]
        for path in unsafe:
            for key in ("textFilePath", "audioFilePath",
                        "scriptureTextFilePath", "reflectionAudioPath"):
                with self.subTest(path=path, field=key):
                    errs = _errors(_catalog(parables=[_entry(**{key: path})]))
                    self.assertTrue(
                        any(key in e for e in errs),
                        f"{key}={path!r} must be rejected -> {errs}")

    def test_empty_optional_media_paths_allowed(self):
        # The real corpus carries empty audio/reflection paths for lane
        # entries whose media is not rendered yet.
        self.assertEqual(
            _errors(_catalog(parables=[
                _entry(audioFilePath="", reflectionAudioPath="")])),
            [])

    def test_semantic_sha_is_formatting_independent(self):
        m = _catalog()
        reordered = json.loads(json.dumps(m, sort_keys=True))
        self.assertEqual(vcm.semantic_sha256(m),
                         vcm.semantic_sha256(reordered))
        changed = _catalog(parables=[_entry(storyId="story_other")])
        self.assertNotEqual(vcm.semantic_sha256(m),
                            vcm.semantic_sha256(changed))

    def test_real_repo_manifest_passes_via_cli(self):
        result = subprocess.run(
            [sys.executable,
             str(REPO_ROOT / "scripts" / "validate_catalog_manifest.py"),
             str(REPO_ROOT / "assets" / "stories" / "manifest.json")],
            capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        version, count, sha = result.stdout.strip().split()
        self.assertEqual(version, "6")
        self.assertEqual(count, "2006")
        self.assertEqual(len(sha), 64)


class PublisherShellTests(HermeticPublisherHarness, unittest.TestCase):
    """Run the real publisher against a stub wrangler. No network, no R2,
    no authentication — the stub records every invocation."""

    def _write_stub(self, tmp: pathlib.Path, remote_body: str) -> dict:
        harness = self._make_harness(tmp)
        body_file = tmp / "stub_remote_body.json"
        body_file.write_text(remote_body)
        log_file = tmp / "stub_calls.log"
        log_file.write_text("")
        stub = harness["stub"]
        stub.write_text(f"""#!/bin/bash
echo "$@" >> "{log_file}"
case "$1 $2 $3" in
  "r2 bucket list")
    echo "bible-pal-audio"
    exit 0
    ;;
  "r2 object get")
    out=""
    for a in "$@"; do case "$a" in --file=*) out="${{a#--file=}}";; esac; done
    cp "{body_file}" "$out"
    exit 0
    ;;
  "r2 object put")
    exit 0
    ;;
esac
exit 1
""")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        harness["log"] = log_file
        return harness

    def _run_publisher(self, harness: dict, *args: str):
        return self._run_hermetic(harness, *args)

    def test_runtime_invalid_remote_classified_corrupt_in_dry_run(self):
        # Codex's exact example: positive version, EMPTY parables. The app
        # would reject this catalog, so the publisher must classify it
        # UNKNOWN/CORRUPT and refuse to use its version as a watermark.
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir),
                                    '{"version":5,"parables":[]}')
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 0,
                             f"dry-run must continue:\n{result.stdout}\n"
                             f"{result.stderr}")
            self.assertIn("UNKNOWN/CORRUPT", result.stdout)
            self.assertIn("PUSH BLOCKED", result.stdout)
            self.assertIn("BLOCKED for push (dry-run continues)",
                          result.stdout)
            log = stub["log"].read_text()
            self.assertIn("r2 object get", log)
            self.assertNotIn("r2 object put", log)

    def test_runtime_invalid_remote_blocks_push(self):
        # Same corrupt remote, --push mode: hard refusal, and the stub
        # proves no object put was ever attempted.
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir),
                                    '{"version":5,"parables":[{}]}')
            result = self._run_publisher(stub, "--push")
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("UNKNOWN/CORRUPT", result.stderr + result.stdout)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log,
                             "a corrupt remote must block the PUT entirely")

    def test_huge_version_remote_classified_corrupt_before_arithmetic(self):
        # version = 2^63 exceeds the Dart int64 range: the validator must
        # classify the object corrupt so the (bash-arithmetic) monotonicity
        # comparison never sees it as a confirmed version.
        remote = ('{"version":9223372036854775808,"parables":['
                  + json.dumps(_entry()) + ']}')
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir), remote)
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 0,
                             f"{result.stdout}\n{result.stderr}")
            self.assertIn("UNKNOWN/CORRUPT", result.stdout)
            self.assertIn("BLOCKED for push (dry-run continues)",
                          result.stdout)
            self.assertNotIn("(confirmed)", result.stdout)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log)

    def test_nan_remote_classified_corrupt(self):
        # Raw NaN parses fine under Python's default json.loads but is not
        # JSON — the strict validator must classify the object corrupt.
        remote = ('{"version":5,"parables":['
                  + json.dumps(_entry()) + '],"x":NaN}')
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir), remote)
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 0,
                             f"{result.stdout}\n{result.stderr}")
            self.assertIn("UNKNOWN/CORRUPT", result.stdout)
            self.assertNotIn("(confirmed)", result.stdout)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log)

    def test_equal_version_remote_is_a_collision_and_blocks(self):
        # Runtime-VALID v6 remote with different content: confirmed, then
        # the strict monotonicity gate refuses (equality is never an
        # update) — even the dry run fails loudly.
        remote = json.dumps({
            "version": 6,
            "parables": [_entry(storyId="story_remote_collision")],
        })
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir), remote)
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("v6, 1 entries (confirmed)", result.stdout)
            combined = result.stdout + result.stderr
            self.assertIn("Equal versions are NEVER an update", combined)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log)

    def test_higher_remote_version_blocks_local(self):
        # Runtime-VALID v7 remote: local v6 is not greater — publishing
        # would move the generation backwards, so the gate refuses.
        remote = json.dumps({
            "version": 7,
            "parables": [_entry(storyId="story_remote_newer")],
        })
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir), remote)
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("v7, 1 entries (confirmed)", result.stdout)
            combined = result.stdout + result.stderr
            self.assertIn("not greater", combined)
            self.assertIn("backwards", combined)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log)

    def test_valid_lower_version_remote_confirmed_and_gate_passes(self):
        # A runtime-VALID v5 remote is confirmed; local v6 passes the
        # strict monotonicity gate and the delta is reported.
        remote = json.dumps({
            "version": 5,
            "parables": [_entry(storyId="story_remote_001",
                                title="Remote Story")],
        })
        with tempfile.TemporaryDirectory() as tmpdir:
            stub = self._write_stub(pathlib.Path(tmpdir), remote)
            result = self._run_publisher(stub)
            self.assertEqual(result.returncode, 0,
                             f"{result.stdout}\n{result.stderr}")
            self.assertIn("v5, 1 entries (confirmed)", result.stdout)
            self.assertIn("OK: 6 > 5", result.stdout)
            self.assertIn("INCREASED by 2005", result.stdout)
            self.assertIn("DRY RUN: no upload performed.", result.stdout)
            log = stub["log"].read_text()
            self.assertNotIn("r2 object put", log)


class ContractParityTests(unittest.TestCase):
    """The active catalog contract exists twice — once in Dart, once here.

    Equivalent semantics are only real if the two halves stay in step, so
    the value sets are compared directly against the Dart source. If this
    fails, one side was changed without the other.
    """

    DART = REPO_ROOT / "lib" / "services" / "catalog_service.dart"

    def _dart_set(self, name: str) -> set:
        source = self.DART.read_text()
        match = re.search(
            rf"Set<String>\s+{name}\s*=\s*\{{(.*?)\}}\s*;",
            source, re.DOTALL)
        self.assertIsNotNone(match, f"{name} not found in {self.DART.name}")
        return set(re.findall(r"'([^']*)'", match.group(1)))

    def _dart_list(self, name: str) -> list:
        source = self.DART.read_text()
        match = re.search(
            rf"List<String>\s+{name}\s*=\s*\[(.*?)\]\s*;",
            source, re.DOTALL)
        self.assertIsNotNone(match, f"{name} not found in {self.DART.name}")
        return re.findall(r"'([^']*)'", match.group(1))

    def test_storytelling_modes_match(self):
        self.assertEqual(self._dart_set("activeStorytellingModes"),
                         vcm.ACTIVE_STORYTELLING_MODES)

    def test_language_styles_match(self):
        self.assertEqual(self._dart_set("activeLanguageStyles"),
                         vcm.ACTIVE_LANGUAGE_STYLES)

    def test_story_lengths_match(self):
        self.assertEqual(self._dart_set("activeStoryLengths"),
                         vcm.ACTIVE_STORY_LENGTHS)

    def test_required_nonblank_fields_match(self):
        self.assertEqual(set(self._dart_list("_requiredNonBlankFields")),
                         set(vcm._REQUIRED_NONBLANK))

    def test_optional_path_fields_match(self):
        self.assertEqual(set(self._dart_list("_optionalPathFields")),
                         set(vcm._OPTIONAL_PATHS))

    def test_translation_allowlist_matches_the_registry(self):
        registry = (REPO_ROOT / "lib" / "core" /
                    "bible_translation_registry.dart").read_text()
        ids = set(re.findall(r"id:\s*'([A-Z]+)'", registry))
        # The registry file also lists BANNED ids; the allowlist must be a
        # subset of everything declared there, and every allowed id must
        # actually appear in it.
        self.assertTrue(vcm.ALLOWED_TRANSLATIONS.issubset(ids),
                        f"{vcm.ALLOWED_TRANSLATIONS - ids} not in registry")
        self.assertTrue(
            vcm.ACTIVE_LANGUAGE_STYLES.issubset(vcm.ALLOWED_TRANSLATIONS))

    def test_identity_blank_code_points_match(self):
        source = self.DART.read_text()
        match = re.search(
            r"Set<int>\s+identityBlankCodePoints\s*=\s*\{(.*?)\}\s*;",
            source, re.DOTALL)
        self.assertIsNotNone(match, "identityBlankCodePoints not found")
        dart_points = {int(v, 16)
                       for v in re.findall(r"0x([0-9A-Fa-f]{4})",
                                           match.group(1))}
        self.assertEqual(dart_points, set(vcm.IDENTITY_BLANK_CODE_POINTS))

    def test_blank_contract_does_not_defer_to_language_defaults(self):
        # The whole point: str.strip() and Dart's trim() disagree, so the
        # contract must be an explicit code-point set rather than either
        # default. These two characters are exactly where they diverge.
        self.assertTrue(
            "\ufeff".strip(),
            "premise: Python strip() does NOT treat U+FEFF as whitespace")
        self.assertFalse(
            "\u001c".strip(),
            "premise: Python strip() DOES treat U+001C as whitespace")
        # Both are blank under the shared contract regardless.
        for ch in ("\ufeff", "\u001c"):
            with self.subTest(char=hex(ord(ch))):
                self.assertTrue(vcm.is_blank_identity(ch))

    def test_blank_identity_bilateral_cases(self):
        blank = [
            "", " ", "   ", "\t", "\n", "\r\n", "\x0b", "\x0c",
            "\u001c", "\u001d", "\u001e", "\u001f",
            "\u0085", "\u00a0", "\u1680", "\u2000", "\u2009",
            "\u200b", "\u200c", "\u200d", "\u2028", "\u2029",
            "\u202f", "\u205f", "\u2060", "\u3000", "\u180e",
            "\ufeff",
            "\ufeff\ufeff", " \t\ufeff ", "\u001c\u2060",
        ]
        not_blank = ["a", " a ", "\ufeffa", "a\u001c", "0", "-", "\u3002"]
        for value in blank:
            with self.subTest(blank=repr(value)):
                self.assertTrue(vcm.is_blank_identity(value))
                errs = _errors(_catalog(parables=[_entry(title=value)]))
                self.assertTrue(any(".title" in e for e in errs),
                                f"{value!r} must be rejected -> {errs}")
        for value in not_blank:
            with self.subTest(not_blank=repr(value)):
                self.assertFalse(vcm.is_blank_identity(value))

    def test_dart_suite_exercises_the_same_divergent_code_points(self):
        # The Dart half must assert the SAME strings, especially the two
        # where the language defaults disagree. If either side stops
        # exercising them, the parity claim is unverified.
        dart_source = (REPO_ROOT / "test" / "services" /
                       "catalog_service_test.dart").read_text()
        for code_point in (0xFEFF, 0x001C, 0x2060, 0x00A0, 0x200B):
            escape = "\\u{%04X}" % code_point
            with self.subTest(code_point=hex(code_point)):
                self.assertIn(
                    escape, dart_source,
                    f"the Dart contract suite must exercise {escape} too")
        self.assertIn("isBlankIdentity", dart_source,
                      "the Dart suite must assert the shared contract "
                      "helper, not Dart's trim()")

    def test_utf8_bom_policy_matches_dart(self):
        # One explicit policy: REJECT. Never left to the runtimes'
        # defaults, which disagree — Dart's utf8.decode discards a leading
        # BOM, Python keeps U+FEFF and json.loads then fails.
        source = self.DART.read_text()
        match = re.search(r"List<int>\s+utf8Bom\s*=\s*\[(.*?)\]\s*;",
                          source, re.DOTALL)
        self.assertIsNotNone(match, "utf8Bom not found in the Dart contract")
        dart_bom = bytes(int(v, 16)
                         for v in re.findall(r"0x([0-9A-Fa-f]{2})",
                                             match.group(1)))
        self.assertEqual(dart_bom, vcm.UTF8_BOM)
        self.assertIn("startsWithUtf8Bom(bodyBytes)", source,
                      "the remote lane must check the BOM at the BYTE level "
                      "— after decoding it is already gone")
        self.assertIn("startsWithUtf8Bom(bytes)", source,
                      "the cache lane must apply the identical byte check")

    def test_bom_premise_python_side(self):
        # Documents the asymmetry this policy exists to close.
        raw = vcm.UTF8_BOM + b'{"a":1}'
        self.assertEqual(ord(raw.decode("utf-8")[0]), 0xFEFF,
                         "premise: Python keeps the BOM as U+FEFF")
        with self.assertRaises(ValueError):
            vcm.loads_strict(raw.decode("utf-8"))
        self.assertTrue(vcm.starts_with_utf8_bom(raw))
        self.assertFalse(vcm.starts_with_utf8_bom(b'{"a":1}'))

    def test_validator_cli_rejects_a_bom_prefixed_catalog(self):
        body = json.dumps(_catalog(version=6)).encode("utf-8")
        with tempfile.TemporaryDirectory() as tmpdir:
            clean = pathlib.Path(tmpdir) / "clean.json"
            clean.write_bytes(body)
            bom = pathlib.Path(tmpdir) / "bom.json"
            bom.write_bytes(vcm.UTF8_BOM + body)

            ok = subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "validate_catalog_manifest.py"),
                 str(clean)],
                capture_output=True, text=True, check=False)
            self.assertEqual(ok.returncode, 0, ok.stderr)

            bad = subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "validate_catalog_manifest.py"),
                 str(bom)],
                capture_output=True, text=True, check=False)
            self.assertEqual(bad.returncode, 1, bad.stdout)
            self.assertIn("must not begin with a UTF-8 BOM", bad.stderr)

    def test_shipped_manifest_has_no_bom(self):
        raw = (REPO_ROOT / "assets" / "stories" /
               "manifest.json").read_bytes()
        self.assertFalse(vcm.starts_with_utf8_bom(raw))

    def test_dart_suite_exercises_the_bom_policy_too(self):
        dart_source = (REPO_ROOT / "test" / "services" /
                       "catalog_service_test.dart").read_text()
        self.assertIn("utf8Bom", dart_source)
        self.assertIn("utf8_bom", dart_source,
                      "the Dart suite must assert the rejection reason")

    def test_safe_path_rule_agrees_with_dart_on_the_same_inputs(self):
        # Both sides implement the same rule; check the Python half against
        # the cases the Dart suite also asserts on.
        safe = [
            "traditional/1000/audio_1000_story_short.mp3",
            "kids/1080/story.txt",
            "a",
            "a/b/c-d_e.f",
        ]
        unsafe = [
            "", "/etc/passwd", "../x", "a/../b", "a/./b", "a//b",
            "a\\b", " a", "a ", "a\n", "~/a", "C:/a", "a/..",
        ]
        for value in safe:
            with self.subTest(safe=value):
                self.assertTrue(vcm.is_safe_relative_asset_path(value))
        for value in unsafe:
            with self.subTest(unsafe=value):
                self.assertFalse(vcm.is_safe_relative_asset_path(value))


# ── Scriptable stub wrangler ────────────────────────────────────────────
#
# Drives the REAL publisher through a fake `wrangler` whose behaviour is
# controlled by files in a scenario directory. Still no network, no R2 and
# no Cloudflare authentication anywhere.
#
#   state.json        present  -> the remote object exists with these bytes
#                     absent   -> `r2 object get` fails like a missing key
#   get_<n>.sh        bash sourced for the Nth `r2 object get` (1-based),
#                     letting a single run answer each phase differently:
#                       call 1 = initial observation
#                       call 2 = pre-PUT recheck
#                       call 3 = post-PUT verification
#   get_all.sh        fallback for every get with no per-call script
#   put_fail          `r2 object put` exits 1
#   put_noop          put "succeeds" without changing the remote state
#   bucket_list_fail  the push-mode auth preflight fails
#   calls.log         every invocation, argv joined
#   last_put_body.json  the exact bytes handed to the last put
_STUB_TEMPLATE = r"""#!/bin/bash
DIR="{scenario}"
echo "$@" >> "$DIR/calls.log"
target_file() {{
  local a
  for a in "$@"; do case "$a" in --file=*) printf '%s' "${{a#--file=}}"; return;; esac; done
}}
case "$1 $2 $3" in
  "r2 bucket list")
    if [ -f "$DIR/bucket_list_fail" ]; then
      echo "Authentication error [code: 10000]" >&2
      exit 1
    fi
    echo "bible-pal-audio"
    exit 0
    ;;
  "r2 object get")
    n=$(cat "$DIR/get_count" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$DIR/get_count"
    OUT="$(target_file "$@")"
    if [ -f "$DIR/get_$n.sh" ]; then
      . "$DIR/get_$n.sh"
      exit $?
    fi
    if [ -f "$DIR/get_all.sh" ]; then
      . "$DIR/get_all.sh"
      exit $?
    fi
    if [ -f "$DIR/state.json" ]; then
      cp "$DIR/state.json" "$OUT"
      exit 0
    fi
    echo "The specified key does not exist." >&2
    exit 1
    ;;
  "r2 object put")
    SRC="$(target_file "$@")"
    cp "$SRC" "$DIR/last_put_body.json"
    printf '%s' "$SRC" > "$DIR/last_put_path"
    if [ -f "$DIR/put_fail" ]; then
      echo "Upload failed: 500 Internal Server Error" >&2
      exit 1
    fi
    if [ ! -f "$DIR/put_noop" ]; then
      cp "$SRC" "$DIR/state.json"
    fi
    exit 0
    ;;
esac
exit 1
"""


class _ScenarioMixin(HermeticPublisherHarness):
    """Builds a scenario dir + stub wrangler and runs the real publisher
    inside a structurally hermetic environment (see hermetic_env.py)."""

    def _scenario(self, tmp: pathlib.Path) -> pathlib.Path:
        scenario = tmp / "scenario"
        scenario.mkdir(parents=True, exist_ok=True)
        (scenario / "calls.log").write_text("")
        harness = self._make_harness(tmp)
        stub = harness["stub"]
        stub.write_text(_STUB_TEMPLATE.format(scenario=scenario))
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        self._harnesses[scenario] = harness
        return scenario

    def setUp(self):
        super().setUp()
        self._harnesses = {}

    def _run(self, scenario: pathlib.Path, *args: str,
             expect_stub: bool = True):
        return self._run_hermetic(self._harnesses[scenario], *args,
                                  expect_stub=expect_stub)

    def _env(self, scenario: pathlib.Path) -> dict:
        return self._harnesses[scenario]["env"]

    def _calls(self, scenario: pathlib.Path) -> str:
        return (scenario / "calls.log").read_text()

    def _assert_no_put(self, scenario: pathlib.Path, why: str):
        self.assertNotIn("r2 object put", self._calls(scenario), why)
        self.assertFalse((scenario / "last_put_body.json").exists(), why)


class HermeticHarnessTests(_ScenarioMixin, unittest.TestCase):
    """The harness itself must be incapable of reaching a real wrangler.

    These tests guard the guard: if PATH ever regains /usr/local/bin,
    /opt/homebrew/bin or an npm/nvm shim directory, a developer machine
    with an installed and AUTHENTICATED wrangler could have a publisher
    test perform a real production PUT.
    """

    def test_path_contains_only_the_scenario_bin(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            env = self._env(scenario)
            self.assertEqual(env["PATH"].count(os.pathsep), 0,
                             f"PATH must be a single entry: {env['PATH']!r}")
            self.assertEqual(pathlib.Path(env["PATH"]),
                             self._harnesses[scenario]["bin"])

    def test_scenario_bin_contains_only_known_names(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            names = sorted(p.name
                           for p in self._harnesses[scenario]["bin"].iterdir())
            allowed = set(henv.PUBLISHER_TOOLS) | {"wrangler"}
            self.assertEqual(set(names) - allowed, set(),
                             f"unexpected executables exposed: {names}")

    def test_no_cloud_credentials_are_inherited(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            env = self._env(scenario)
            henv.assert_no_cloud_credentials(self, env)
            # HOME is scenario-owned and empty, so ~/.wrangler and
            # ~/.config credentials are not readable either.
            home = pathlib.Path(env["HOME"])
            self.assertTrue(home.is_dir())
            self.assertEqual(list(home.iterdir()), [])
            self.assertNotEqual(home, pathlib.Path.home())

    def test_a_globally_installed_wrangler_is_never_invoked(self):
        # Simulates the dangerous machine: a real wrangler IS installed and
        # resolvable on the ambient system PATH. A harness that inherited
        # os.environ (or appended system bin directories) would find it.
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            scenario = self._scenario(tmp)
            self._remote_v5_state(scenario)

            global_bin = tmp / "fake_global_bin"
            global_bin.mkdir()
            marker = tmp / "REAL_WRANGLER_WAS_INVOKED"
            decoy = global_bin / "wrangler"
            decoy.write_text(
                f'#!/bin/bash\ntouch "{marker}"\necho "$@" >> "{marker}"\n'
                'exit 0\n')
            decoy.chmod(decoy.stat().st_mode | stat.S_IEXEC)

            original_path = os.environ["PATH"]
            os.environ["PATH"] = f"{global_bin}{os.pathsep}{original_path}"
            try:
                # Precondition: the decoy really is globally resolvable.
                self.assertEqual(
                    pathlib.Path(shutil.which("wrangler")).resolve(),
                    decoy.resolve(),
                    "test premise failed: the decoy is not on the system PATH")
                push = self._run(scenario, "--push")
            finally:
                os.environ["PATH"] = original_path

            self.assertFalse(
                marker.exists(),
                "the globally installed wrangler was INVOKED — the harness "
                "is not hermetic and a real R2 PUT could have happened")
            # The stub, not the decoy, did the work.
            self.assertIn("r2 object put", self._calls(scenario))
            self.assertEqual(push.returncode, 0, push.stderr)

    def test_no_publisher_test_inherits_the_ambient_environment(self):
        # Structural guard. The needle is assembled at runtime so this
        # test does not match its own source text.
        needle = "dict(os." + "environ)"
        for path in (pathlib.Path(__file__),
                     pathlib.Path(henv.__file__)):
            source = path.read_text()
            self.assertNotIn(
                needle, source,
                f"{path.name}: publisher tests must build env from scratch, "
                f"never inherit the developer's environment")
            # A global bin directory must never appear in a PATH
            # assignment. Prose mentioning those directories is fine —
            # only real assignments are scanned.
            for line in source.split("\n"):
                code = line.split("#", 1)[0]
                if not re.search(r"""["']PATH["']\s*[:=\]]""", code):
                    continue
                for fragment in ("/usr/local/bin", "/opt/homebrew/bin",
                                 "/opt/local/bin"):
                    self.assertNotIn(
                        fragment, code,
                        f"{path.name}: global bin directory reachable via "
                        f"PATH: {line.strip()}")

    def _remote_v5_state(self, scenario):
        (scenario / "state.json").write_text(
            json.dumps({"version": 5,
                        "parables": [_entry(storyId="story_remote_v5")]}))


class FailClosedRemoteStateTests(_ScenarioMixin, unittest.TestCase):
    """PRIORITY 1 — a failed or indeterminate remote read is UNKNOWN.

    Absence is never inferred. Every scenario below previously had, or
    could have had, a stderr string that generic matching ("not found",
    "no such", "404", "does not exist") would have read as confirmed
    absence — which would have authorized a blind PUT over a live,
    possibly NEWER, catalog. None of them may reach a PUT.
    """

    # (label, exit code, stderr text) — the stderr is deliberately full of
    # absence-shaped language.
    FAILURE_MODES = [
        ("transport",
         1, "getaddrinfo ENOTFOUND api.cloudflare.com: host not found"),
        ("missing_helper",
         127, "env: node: No such file or directory"),
        ("auth",
         1, "Authentication error [code: 10000]: route not found"),
        ("network",
         1, "fetch failed: ECONNRESET"),
        ("rate_limit",
         1, "Too many requests [code: 971]"),
        ("ambiguous_not_found",
         1, "not found"),
        ("ambiguous_no_such",
         1, "no such file or directory"),
        ("ambiguous_404",
         1, "A request to the Cloudflare API failed: 404 Not Found"),
        ("ambiguous_does_not_exist",
         1, "The specified key does not exist."),
        ("silent_failure", 1, ""),
    ]

    def _install_failing_get(self, scenario, exit_code, stderr_text):
        (scenario / "get_all.sh").write_text(
            f'printf %s {json.dumps(stderr_text)} >&2\n'
            f'exit {exit_code}\n')

    def test_failed_get_is_unknown_and_blocks_push(self):
        for label, code, stderr_text in self.FAILURE_MODES:
            with self.subTest(mode=label):
                with tempfile.TemporaryDirectory() as tmpdir:
                    scenario = self._scenario(pathlib.Path(tmpdir))
                    self._install_failing_get(scenario, code, stderr_text)

                    push = self._run(scenario, "--push")

                    self.assertEqual(
                        push.returncode, 1,
                        f"{label}: --push must refuse\n{push.stdout}")
                    combined = push.stdout + push.stderr
                    self.assertIn("UNKNOWN", combined, label)
                    self.assertNotIn("confirmed absent", combined.lower(),
                                     f"{label}: absence must never be claimed")
                    self._assert_no_put(
                        scenario,
                        f"{label}: an unreadable remote must never be "
                        f"overwritten")

    def test_failed_get_is_unknown_in_dry_run_too(self):
        for label, code, stderr_text in self.FAILURE_MODES:
            with self.subTest(mode=label):
                with tempfile.TemporaryDirectory() as tmpdir:
                    scenario = self._scenario(pathlib.Path(tmpdir))
                    self._install_failing_get(scenario, code, stderr_text)

                    dry = self._run(scenario)

                    self.assertEqual(dry.returncode, 0, dry.stderr)
                    self.assertIn("remote state is UNKNOWN", dry.stdout, label)
                    self.assertNotIn("(confirmed)", dry.stdout, label)
                    self._assert_no_put(scenario, label)

    def test_missing_object_is_unknown_not_absent(self):
        # The stub's default no-state branch emits the genuine wrangler
        # missing-key message. Even THAT is UNKNOWN: the catalog key is
        # established production state, so a read that returns nothing is
        # a failure to read, never a licence to create.
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("Absence is NEVER inferred",
                          push.stdout + push.stderr)
            self._assert_no_put(scenario, "no first-publish path exists")

    def test_get_succeeds_but_writes_no_body_is_unknown(self):
        # Exit 0 with no object body written: malformed helper output, not
        # evidence of anything about the remote.
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "get_all.sh").write_text("exit 0\n")

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("wrote no object body", push.stdout + push.stderr)
            self._assert_no_put(scenario, "no body means no knowledge")

    def test_get_succeeds_with_empty_body_is_unknown(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "get_all.sh").write_text(': > "$OUT"\nexit 0\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("object body is empty", push.stdout + push.stderr)
            self._assert_no_put(scenario, "an empty body proves nothing")

    def test_get_succeeds_with_garbage_body_is_corrupt_and_blocks(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "state.json").write_text("<html>502 Bad Gateway</html>")

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("UNKNOWN/CORRUPT", push.stdout + push.stderr)
            self._assert_no_put(scenario, "unvalidatable bytes block the PUT")

    def test_stale_body_from_a_previous_call_is_not_reused(self):
        # First get succeeds; the second (pre-PUT recheck) fails. The
        # publisher must NOT fall back to the body left on disk by the
        # first call — the recheck must observe UNKNOWN and stop.
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "state.json").write_text(
                json.dumps({"version": 5,
                            "parables": [_entry(storyId="story_r5")]}))
            (scenario / "get_2.sh").write_text(
                'echo "not found" >&2\nexit 1\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self._assert_no_put(
                scenario,
                "a failed recheck must not inherit the first read's body")

    def test_publisher_is_repeatable_from_a_clean_build_tree(self):
        # Regression: the staged operator copy is created with `cp` from a
        # 0400 snapshot, and `cp` gives a NEW destination the SOURCE's
        # mode. That left build/r2-staging/catalog-pending.json read-only,
        # so the SECOND run of the publisher died with
        # "cp: ...: Permission denied" — on a clean machine the real
        # publisher was single-use.
        #
        # Every other test here re-used whatever build/r2-staging already
        # contained, so a stale writable artifact masked it locally; CI's
        # fresh checkout did not. This test removes the directory first so
        # it reproduces regardless of local state.
        staging = REPO_ROOT / "build" / "r2-staging"
        if staging.exists():
            shutil.rmtree(staging)

        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "state.json").write_text(
                json.dumps({"version": 5,
                            "parables": [_entry(storyId="story_remote_v5")]}))

            first = self._run(scenario)
            self.assertEqual(first.returncode, 0,
                             f"first run:\n{first.stdout}\n{first.stderr}")

            staged = staging / "catalog-pending.json"
            self.assertTrue(staged.exists())
            self.assertTrue(
                os.access(staged, os.W_OK),
                "the staged operator copy must stay writable — it is "
                "inspectable output, not an immutability guard")

            second = self._run(scenario)
            self.assertEqual(
                second.returncode, 0,
                f"the publisher must be repeatable:\n{second.stdout}\n"
                f"{second.stderr}")
            self.assertNotIn("Permission denied", second.stderr + second.stdout)

    def test_missing_wrangler_executable_cannot_reach_put(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._harnesses[scenario]["stub"].unlink()

            # expect_stub=False asserts that NOTHING named wrangler is
            # resolvable — the scenario genuinely has no wrangler, rather
            # than silently falling through to a real installation.
            push = self._run(scenario, "--push", expect_stub=False)

            self.assertEqual(push.returncode, 1)
            self.assertIn("wrangler CLI not found", push.stderr)
            self._assert_no_put(scenario, "no wrangler, no publication")

    def test_auth_preflight_failure_cannot_reach_put(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            (scenario / "bucket_list_fail").write_text("")
            (scenario / "state.json").write_text(
                json.dumps({"version": 5,
                            "parables": [_entry(storyId="story_r5")]}))

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("Cannot access R2 bucket", push.stderr)
            self._assert_no_put(scenario, "auth failure blocks everything")

    def test_publisher_never_classifies_state_from_stderr(self):
        # Structural guard: the classifier must not grep the captured
        # stderr. Absence-shaped words may appear in comments and operator
        # messages, but never inside fetch_remote_state's logic.
        source = PUBLISHER.read_text()
        start = source.index("fetch_remote_state() {")
        end = source.index("\n}", start)
        body = source[start:end]
        for forbidden in ("grep", "not found", "no such", "404",
                          "does not exist"):
            self.assertNotIn(
                forbidden, body,
                f"remote-state classification must never consult stderr "
                f"text ({forbidden!r} found in fetch_remote_state)")


class PushPathStatefulTests(_ScenarioMixin, unittest.TestCase):
    """PRIORITY 3.4/3.5 — the full push path against a stateful remote."""

    def _remote_v5(self, scenario):
        (scenario / "state.json").write_text(
            json.dumps({"version": 5,
                        "parables": [_entry(storyId="story_remote_v5")]}))

    def test_successful_push_publishes_the_exact_snapshot_bytes(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 0,
                             f"{push.stdout}\n{push.stderr}")
            self.assertIn("v5, 1 entries (confirmed)", push.stdout)
            self.assertIn("OK: 6 > 5", push.stdout)
            self.assertIn("Pre-PUT byte integrity check:", push.stdout)
            self.assertIn("OK: remote state unchanged since staging.",
                          push.stdout)
            self.assertIn("Catalog v6 published", push.stdout)
            self.assertIn("r2 object put", self._calls(scenario))

            # Immutable bytes: what landed remotely is byte-identical to
            # the committed manifest.
            manifest_bytes = (REPO_ROOT / "assets" / "stories" /
                              "manifest.json").read_bytes()
            self.assertEqual(
                (scenario / "last_put_body.json").read_bytes(),
                manifest_bytes,
                "the PUT must carry the manifest's exact bytes")
            self.assertEqual(
                (scenario / "state.json").read_bytes(), manifest_bytes)

    def test_put_reads_a_private_snapshot_not_the_shared_staging_file(self):
        # build/r2-staging/ is a predictable, writable path: anything
        # could swap it between validation and upload. The uploaded file
        # must be the run's private snapshot instead.
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 0, push.stderr)
            put_path = (scenario / "last_put_path").read_text()
            self.assertNotIn("build/r2-staging", put_path,
                             "the shared staging copy must never be the "
                             "upload source")
            self.assertTrue(put_path.endswith("catalog-upload.json"),
                            put_path)

    def test_put_failure_is_reported_and_not_treated_as_published(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            (scenario / "put_fail").write_text("")

            push = self._run(scenario, "--push")

            self.assertNotEqual(push.returncode, 0, push.stdout)
            self.assertNotIn("Catalog v6 published", push.stdout)
            # The remote is untouched: still v5.
            self.assertEqual(
                json.loads((scenario / "state.json").read_text())["version"],
                5)

    def test_remote_changed_during_pre_put_recheck_aborts_before_put(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            # Another publisher lands v7 between staging and the PUT.
            newer = json.dumps({"version": 7,
                                "parables": [_entry(storyId="story_other")]})
            (scenario / "get_2.sh").write_text(
                f'cat > "$DIR/state.json" <<\'JSON\'\n{newer}\nJSON\n'
                'cp "$DIR/state.json" "$OUT"\n'
                'exit 0\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            combined = push.stdout + push.stderr
            self.assertIn("remote catalog state CHANGED", combined)
            self.assertIn("Another publisher may be active", combined)
            self._assert_no_put(
                scenario, "a changed remote must abort before the PUT")
            # The concurrent publisher's v7 survives untouched.
            self.assertEqual(
                json.loads((scenario / "state.json").read_text())["version"],
                7)

    def test_recheck_turning_unknown_aborts_before_put(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            (scenario / "get_2.sh").write_text(
                'echo "The specified key does not exist." >&2\nexit 1\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("remote catalog state CHANGED",
                          push.stdout + push.stderr)
            self._assert_no_put(
                scenario,
                "losing visibility of the remote must abort the PUT")

    def test_post_put_mismatch_is_detected_and_fails_loudly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            # The PUT "succeeds" but the remote still serves the old
            # object — e.g. another writer raced it.
            (scenario / "put_noop").write_text("")

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            combined = push.stdout + push.stderr
            self.assertIn("post-PUT verification FAILED", combined)
            self.assertIn("another publisher may have raced", combined)
            self.assertNotIn("Catalog v6 published", push.stdout)
            self.assertIn("r2 object put", self._calls(scenario))

    def test_post_put_verification_unknown_fails_loudly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            (scenario / "get_3.sh").write_text(
                'echo "connection reset" >&2\nexit 1\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self.assertIn("post-PUT verification FAILED",
                          push.stdout + push.stderr)
            self.assertNotIn("Catalog v6 published", push.stdout)

    def test_unknown_remote_state_blocks_push_with_state_intact(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            scenario = self._scenario(pathlib.Path(tmpdir))
            self._remote_v5(scenario)
            before = (scenario / "state.json").read_bytes()
            (scenario / "get_all.sh").write_text(
                'echo "socket hang up" >&2\nexit 1\n')

            push = self._run(scenario, "--push")

            self.assertEqual(push.returncode, 1, push.stdout)
            self._assert_no_put(scenario, "UNKNOWN must never mutate R2")
            self.assertEqual((scenario / "state.json").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
