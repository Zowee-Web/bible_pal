#!/usr/bin/env python3
"""Root-metadata preservation test for server/tools/backfill_story_length.sh.

The writer historically reconstructed the manifest root as
{"parables": [...]}, silently dropping every other top-level key — including
the catalog "version" required by the Catalog Currency invariant
(docs/INVARIANTS.md). This suite runs the real script against a fixture tree
(via MANIFEST_FILE_OVERRIDE / STORIES_DIR_OVERRIDE) and proves root metadata
survives a rewrite. The real corpus is never touched.

Run:
    python3 -m unittest scripts.tests.test_backfill_story_length_writer -v
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts" / "tests"))

import hermetic_env as henv  # noqa: E402

SCRIPT = REPO_ROOT / "server" / "tools" / "backfill_story_length.sh"


def _entry(**overrides):
    """An entry that genuinely satisfies the ACTIVE CATALOG CONTRACT.

    The old fixture carried only storyId + textFilePath, so it could not
    have detected the writer shipping a manifest the app would reject.
    """
    base = {
        "storyId": "story_9001_test",
        "title": "Backfill Test Story",
        "mood": "joyful",
        "storytellingMode": "traditional",
        "translationId": "WEB",
        "languageStyle": "WEB",
        "kidFriendly": False,
        "textFilePath": "traditional/9001/story_9001.txt",
        "audioFilePath": "traditional/9001/audio_9001_story_short.mp3",
    }
    base.update(overrides)
    return base


@unittest.skipUnless(shutil.which("jq"), "jq is required by the script under test")
class BackfillStoryLengthWriterTests(unittest.TestCase):
    def _build_fixture(self, tmp: pathlib.Path,
                       parables=None) -> pathlib.Path:
        stories = tmp / "stories" / "traditional" / "9001"
        stories.mkdir(parents=True, exist_ok=True)
        (stories / "story_9001.txt").write_text("one two three four five\n")
        manifest = {
            "version": 6,
            "parables": parables if parables is not None else [
                # No storyLength -> gets backfilled from the word count.
                _entry(),
                # Already has storyLength -> SKIP branch, not an error.
                _entry(storyId="story_9002_test",
                       textFilePath="traditional/9002/missing.txt",
                       storyLength="short"),
            ],
        }
        manifest_path = tmp / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2))
        return manifest_path

    def _run_script(self, tmp: pathlib.Path, manifest_path: pathlib.Path,
                    *args: str) -> subprocess.CompletedProcess:
        # Hermetic: PATH is exactly a scenario-owned bin of named symlinks,
        # so no globally installed tool can be reached implicitly and no
        # cloud credentials are inherited (see hermetic_env.py).
        bin_dir = henv.make_bin(tmp / "bin", henv.BACKFILL_TOOLS)
        env = henv.hermetic_env(
            bin_dir, tmp / "home", tmp / "tmp",
            MANIFEST_FILE_OVERRIDE=str(manifest_path),
            STORIES_DIR_OVERRIDE=str(tmp / "stories"),
        )
        henv.assert_path_is_hermetic(self, env, bin_dir)
        henv.assert_no_wrangler_resolvable(self, env)
        return subprocess.run(
            [str(SCRIPT), *args],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_rewrite_preserves_root_version_and_updates_entries(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)

            result = self._run_script(tmp, manifest_path)
            self.assertEqual(result.returncode, 0,
                             f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")

            written = json.loads(manifest_path.read_text())
            self.assertEqual(
                written.get("version"), 6,
                "the rewrite must preserve the top-level catalog version")
            self.assertEqual(len(written["parables"]), 2)
            self.assertEqual(written["parables"][0]["storyLength"], "short",
                             "5-word story must be classified short")
            self.assertEqual(written["parables"][0]["storyId"],
                             "story_9001_test",
                             "entry order must be preserved")
            self.assertTrue((tmp / "manifest.json.bak").exists(),
                            "a backup of the original must be written")

    def test_dry_run_leaves_manifest_untouched(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)
            before = manifest_path.read_text()

            result = self._run_script(tmp, manifest_path, "--dry-run")
            self.assertEqual(result.returncode, 0,
                             f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
            self.assertEqual(manifest_path.read_text(), before)

    def test_processing_error_leaves_the_manifest_completely_unchanged(self):
        # A story that needs a storyLength but whose text file is missing
        # is a processing ERROR. The writer used to rewrite the manifest
        # anyway and only then exit nonzero, leaving the catalog silently
        # mutated by a run the operator was told had failed.
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)
            manifest = json.loads(manifest_path.read_text())
            manifest["parables"].append({
                "storyId": "story_9003_broken",
                "textFilePath": "traditional/9003/does_not_exist.txt",
            })
            manifest_path.write_text(json.dumps(manifest, indent=2))
            before = manifest_path.read_text()

            result = self._run_script(tmp, manifest_path)

            self.assertEqual(result.returncode, 1,
                             "a processing error must fail the run")
            self.assertEqual(
                manifest_path.read_text(), before,
                "the manifest must be byte-identical after a failed run")
            self.assertFalse(
                (tmp / "manifest.json.bak").exists(),
                "no backup should be written when nothing is replaced")

    def test_successful_run_leaves_no_temp_residue(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)

            result = self._run_script(tmp, manifest_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            residue = [p.name for p in manifest_path.parent.iterdir()
                       if ".staged." in p.name]
            self.assertEqual(residue, [],
                             "the same-directory staging file must be "
                             "renamed away, never left behind")

    def test_replacement_preserves_file_mode(self):
        # mktemp creates 0600; the swap must not silently tighten the
        # manifest's permissions.
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)
            manifest_path.chmod(0o644)

            result = self._run_script(tmp, manifest_path)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(manifest_path.stat().st_mode & 0o777, 0o644)

    def test_semantic_validation_failures_leave_the_manifest_untouched(self):
        # The structural checks (valid JSON, entry count, root keys) cannot
        # see any of these. Each one would be rejected by the app and by
        # the publisher, so the writer must refuse to install it — with the
        # original left byte-identical and NO backup written.
        cases = {
            "invalid version": {
                "version": 0,
                "parables": [_entry(storyLength="short")],
            },
            "duplicate storyId": {
                "version": 6,
                "parables": [_entry(storyId="story_dupe", storyLength="short"),
                             _entry(storyId="story_dupe", storyLength="short")],
            },
            "unsafe parent-traversal path": {
                "version": 6,
                "parables": [_entry(
                    storyLength="short",
                    textFilePath="traditional/../../etc/passwd")],
            },
            "invalid storytellingMode": {
                "version": 6,
                "parables": [_entry(storyLength="short",
                                    storytellingMode="creative")],
            },
            "non-canonical languageStyle": {
                "version": 6,
                "parables": [_entry(storyLength="short",
                                    languageStyle="kjv")],
            },
        }
        for label, manifest in cases.items():
            with self.subTest(case=label):
                with tempfile.TemporaryDirectory() as tmpdir:
                    tmp = pathlib.Path(tmpdir)
                    stories = tmp / "stories" / "traditional" / "9001"
                    stories.mkdir(parents=True)
                    # Present so processing SUCCEEDS and the run reaches
                    # the semantic gate rather than failing earlier.
                    (stories / "story_9001.txt").write_text("one two three\n")
                    manifest_path = tmp / "manifest.json"
                    manifest_path.write_text(json.dumps(manifest, indent=2))
                    before = manifest_path.read_bytes()

                    result = self._run_script(tmp, manifest_path)

                    self.assertNotEqual(
                        result.returncode, 0,
                        f"{label}: the run must fail\n{result.stdout}")
                    self.assertIn("FAILS catalog validation",
                                  result.stdout + result.stderr,
                                  f"{label}: must fail SEMANTIC validation")
                    self.assertEqual(
                        manifest_path.read_bytes(), before,
                        f"{label}: the original must be byte-identical")
                    self.assertFalse(
                        (tmp / "manifest.json.bak").exists(),
                        f"{label}: no backup may be written on failure")
                    residue = [p.name for p in tmp.iterdir()
                               if ".staged." in p.name]
                    self.assertEqual(residue, [],
                                     f"{label}: no staging residue")

    def test_valid_fixture_actually_passes_the_catalog_validator(self):
        # Guards the guard: if the positive fixture were not genuinely
        # valid, the negative tests above would prove nothing.
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)
            result = subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "validate_catalog_manifest.py"),
                 str(manifest_path)],
                capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_arbitrary_root_metadata_survives(self):
        # Not just "version": ANY unknown top-level key must survive, so a
        # future root field cannot be silently destroyed by this writer.
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            manifest_path = self._build_fixture(tmp)
            manifest = json.loads(manifest_path.read_text())
            manifest["futureRootField"] = {"kept": True}
            manifest_path.write_text(json.dumps(manifest, indent=2))

            result = self._run_script(tmp, manifest_path)
            self.assertEqual(result.returncode, 0,
                             f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")

            written = json.loads(manifest_path.read_text())
            self.assertEqual(written.get("version"), 6)
            self.assertEqual(written.get("futureRootField"), {"kept": True})


def _modern_bash():
    """A bash >= 4 if this host has one, else None.

    macOS ships bash 3.2, where `set -e` happens not to abort on a failing
    top-level `((X++))`. Newer bash is stricter, so counter bugs are
    version-dependent — the static guard below is the portable check and
    this is the belt-and-braces dynamic one.
    """
    seen = set()
    for candidate in (shutil.which("bash"), "/opt/homebrew/bin/bash",
                      "/usr/local/bin/bash", "/bin/bash"):
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            out = subprocess.run([candidate, "-c", "echo $BASH_VERSINFO"],
                                 capture_output=True, text=True, check=False)
        except OSError:
            continue
        major = out.stdout.strip()
        if major.isdigit() and int(major) >= 4:
            return candidate
    return None


class ErrexitSafeCounterTests(unittest.TestCase):
    """`((X++))` returns status 1 when X was 0.

    Under `set -e` that can abort the run mid-way — in this very bash 3.2
    it aborts when the increment is the last command of a function, and
    newer bash is stricter still. Counters must use an assignment form
    whose status is always 0.
    """

    SHELL_SCRIPTS = (
        REPO_ROOT / "server" / "tools" / "backfill_story_length.sh",
        REPO_ROOT / "scripts" / "upload_r2_catalog.sh",
        REPO_ROOT / "scripts" / "ci" / "enforce_manifest_version_bump.sh",
    )

    def test_no_errexit_unsafe_increments_remain(self):
        pattern = re.compile(r"\(\(\s*[A-Za-z_][A-Za-z0-9_]*\s*(\+\+|--)\s*\)\)")
        for script in self.SHELL_SCRIPTS:
            with self.subTest(script=script.name):
                offenders = [
                    f"{i}: {line.strip()}"
                    for i, line in enumerate(
                        script.read_text().split("\n"), start=1)
                    if pattern.search(line.split("#", 1)[0])
                ]
                self.assertEqual(
                    offenders, [],
                    f"{script.name}: use VAR=$((VAR + 1)); a bare "
                    f"((VAR++)) returns status 1 on the first increment")

    def test_the_hazard_is_real_in_this_bash(self):
        # Documents WHY the pattern is banned rather than trusting folklore.
        probe = ("set -euo pipefail\n"
                 "bump() { local n=0; ((n++)); }\n"
                 "bump\n"
                 "echo SURVIVED\n")
        result = subprocess.run(["/bin/bash", "-c", probe],
                                capture_output=True, text=True, check=False)
        self.assertNotEqual(
            result.returncode, 0,
            "expected ((n++)) to abort under set -e; if this host no longer "
            "reproduces it the ban still stands for other bash versions")
        self.assertNotIn("SURVIVED", result.stdout)

        safe = ("set -euo pipefail\n"
                "bump() { local n=0; n=$((n + 1)); }\n"
                "bump\n"
                "echo SURVIVED\n")
        result = subprocess.run(["/bin/bash", "-c", safe],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SURVIVED", result.stdout)

    @unittest.skipUnless(shutil.which("jq"), "jq is required")
    def test_writer_completes_under_modern_bash(self):
        bash = _modern_bash()
        if bash is None:
            self.skipTest(
                "no bash >= 4 on this host (macOS ships 3.2); the static "
                "guard above is the portable check and CI covers the rest")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = pathlib.Path(tmpdir)
            helper = BackfillStoryLengthWriterTests()
            manifest_path = helper._build_fixture(tmp)
            bin_dir = henv.make_bin(tmp / "bin", henv.BACKFILL_TOOLS)
            env = henv.hermetic_env(
                bin_dir, tmp / "home", tmp / "tmp",
                MANIFEST_FILE_OVERRIDE=str(manifest_path),
                STORIES_DIR_OVERRIDE=str(tmp / "stories"),
            )
            result = subprocess.run([bash, str(SCRIPT)], env=env,
                                    capture_output=True, text=True,
                                    check=False)
            self.assertEqual(result.returncode, 0,
                             f"{bash}:\n{result.stdout}\n{result.stderr}")
            written = json.loads(manifest_path.read_text())
            self.assertEqual(written["parables"][0]["storyLength"], "short")


if __name__ == "__main__":
    unittest.main()
