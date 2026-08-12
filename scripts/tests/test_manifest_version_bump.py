#!/usr/bin/env python3
"""Tests for scripts/check_manifest_version_bump.py.

Covers the PR-time Catalog Currency bump contract:
semantic-change detection, formatting immunity, array-order sensitivity,
positive-integer version validation (bool excluded), the >=/> split, and
the initial no-version -> 6 migration.

Run:
    python3 -m unittest scripts.tests.test_manifest_version_bump -v
"""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import check_manifest_version_bump as bump  # noqa: E402


def _manifest(version=None, parables=None, extra=None):
    m = {}
    if version is not None:
        m["version"] = version
    m["parables"] = parables if parables is not None else [{"storyId": "a"}]
    if extra:
        m.update(extra)
    return m


class CheckFunctionTests(unittest.TestCase):
    def test_content_change_without_bump_fails(self):
        base = _manifest(version=6, parables=[{"storyId": "a"}])
        current = _manifest(version=6,
                            parables=[{"storyId": "a"}, {"storyId": "b"}])
        ok, msg = bump.check(base, current)
        self.assertFalse(ok)
        self.assertIn("not bumped", msg)

    def test_content_change_with_bump_passes(self):
        base = _manifest(version=6, parables=[{"storyId": "a"}])
        current = _manifest(version=7,
                            parables=[{"storyId": "a"}, {"storyId": "b"}])
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_formatting_only_change_requires_no_bump(self):
        # check() receives parsed JSON, so formatting differences are
        # invisible by construction — identical parsed content passes.
        base = _manifest(version=6)
        current = _manifest(version=6)
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_version_only_bump_passes(self):
        base = _manifest(version=6)
        current = _manifest(version=9)
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_version_decrease_without_content_change_fails(self):
        base = _manifest(version=6)
        current = _manifest(version=3)
        ok, msg = bump.check(base, current)
        self.assertFalse(ok)
        self.assertIn("never decrease", msg)

    def test_initial_migration_no_version_to_6_passes(self):
        base = _manifest()  # no version, pre-migration
        current = _manifest(version=6)
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_initial_migration_with_content_change_passes(self):
        base = _manifest(parables=[{"storyId": "a"}])
        current = _manifest(version=6,
                            parables=[{"storyId": "a"}, {"storyId": "b"}])
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_array_order_is_semantic(self):
        base = _manifest(version=6,
                         parables=[{"storyId": "a"}, {"storyId": "b"}])
        current = _manifest(version=6,
                            parables=[{"storyId": "b"}, {"storyId": "a"}])
        ok, msg = bump.check(base, current)
        self.assertFalse(ok, "reordering parables is a semantic change")
        self.assertIn("not bumped", msg)

    def test_non_version_root_metadata_is_semantic(self):
        base = _manifest(version=6)
        current = _manifest(version=6, extra={"note": "new root field"})
        ok, _ = bump.check(base, current)
        self.assertFalse(ok, "adding root metadata is a semantic change")

    def test_current_version_missing_fails(self):
        ok, msg = bump.check(_manifest(version=6), _manifest())
        self.assertFalse(ok)
        self.assertIn("positive integer", msg)

    def test_current_version_bool_fails(self):
        ok, msg = bump.check(_manifest(version=6), _manifest(version=True))
        self.assertFalse(ok)
        self.assertIn("positive integer", msg)

    def test_current_version_string_fails(self):
        ok, _ = bump.check(_manifest(version=6), _manifest(version="7"))
        self.assertFalse(ok)

    def test_current_version_zero_or_negative_fails(self):
        for bad in (0, -1):
            ok, _ = bump.check(_manifest(version=6), _manifest(version=bad))
            self.assertFalse(ok, f"version {bad} must be rejected")

    def test_base_version_present_but_invalid_fails_closed(self):
        # Only a base with NO version key is the generation-0 migration
        # shape. A PRESENT-but-invalid base version must fail closed — it
        # can never be laundered into a fresh migration.
        # None is exercised separately below: _manifest(version=None) omits
        # the key entirely, which is the ALLOWED migration shape.
        for bad in ("corrupt", "6", True, False, 6.0, 0, -3):
            with self.subTest(base_version=bad):
                ok, msg = bump.check(
                    _manifest(version=bad), _manifest(version=99))
                self.assertFalse(
                    ok, f"present invalid base version {bad!r} must fail")
                self.assertIn("invalid", msg)

    def test_base_version_null_is_present_and_fails(self):
        # json.loads('{"version": null}') yields {"version": None} — the
        # key IS present, so this is corrupt, not pre-migration.
        base = json.loads('{"version": null, "parables": [{"storyId": "a"}]}')
        ok, msg = bump.check(base, _manifest(version=6))
        self.assertFalse(ok)
        self.assertIn("invalid", msg)

    def test_json_type_changes_are_semantic(self):
        # Python container equality collapses True == 1 == 1.0; the
        # canonical-serialization comparison must NOT. Every type flip is
        # a semantic change: same version fails, bumped version passes.
        pairs = [
            (True, 1), (1, True),
            (False, 0), (0, False),
            (1, 1.0), (1.0, 1),
        ]
        for a, b in pairs:
            with self.subTest(change=f"{a!r}->{b!r}"):
                base = _manifest(
                    version=6, parables=[{"storyId": "a", "flag": a}])
                same_version = _manifest(
                    version=6, parables=[{"storyId": "a", "flag": b}])
                ok, msg = bump.check(base, same_version)
                self.assertFalse(
                    ok, f"type change {a!r}->{b!r} must require a bump")
                self.assertIn("not bumped", msg)

                bumped = _manifest(
                    version=7, parables=[{"storyId": "a", "flag": b}])
                ok, _ = bump.check(base, bumped)
                self.assertTrue(ok)

    def test_identical_typed_content_is_unchanged(self):
        base = _manifest(version=6,
                         parables=[{"storyId": "a", "flag": True}])
        current = _manifest(version=6,
                            parables=[{"storyId": "a", "flag": True}])
        ok, _ = bump.check(base, current)
        self.assertTrue(ok)

    def test_is_valid_version_rejects_bool_true(self):
        self.assertFalse(bump.is_valid_version(True))
        self.assertFalse(bump.is_valid_version(False))
        self.assertTrue(bump.is_valid_version(6))
        self.assertFalse(bump.is_valid_version(0))
        self.assertFalse(bump.is_valid_version(-5))
        self.assertFalse(bump.is_valid_version("6"))
        self.assertFalse(bump.is_valid_version(6.0))


class CliTests(unittest.TestCase):
    """End-to-end: formatting differences on disk are ignored; exit codes."""

    def _run(self, base_obj, current_obj, base_text=None, current_text=None):
        with tempfile.TemporaryDirectory() as tmp:
            base_path = pathlib.Path(tmp) / "base.json"
            current_path = pathlib.Path(tmp) / "current.json"
            base_path.write_text(
                base_text if base_text is not None else json.dumps(base_obj))
            current_path.write_text(
                current_text if current_text is not None
                else json.dumps(current_obj))
            return subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "check_manifest_version_bump.py"),
                    "--base", str(base_path),
                    "--current", str(current_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_cli_formatting_only_change_passes_without_bump(self):
        obj = _manifest(version=6)
        pretty = json.dumps(obj, indent=4, sort_keys=True)
        compact = json.dumps(obj, separators=(",", ":"))
        result = self._run(None, None, base_text=pretty, current_text=compact)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cli_content_change_without_bump_exits_1(self):
        result = self._run(
            _manifest(version=6, parables=[{"storyId": "a"}]),
            _manifest(version=6, parables=[{"storyId": "z"}]),
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stderr)

    def test_cli_initial_migration_passes(self):
        result = self._run(_manifest(), _manifest(version=6))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cli_unparseable_base_exits_1(self):
        result = self._run(None, _manifest(version=6),
                           base_text="not json {{{")
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot load base", result.stderr)

    def test_cli_type_change_requires_bump(self):
        # Raw JSON text so the on-disk types are exact: true -> 1 with the
        # same version must fail; with a bump it must pass.
        base_text = '{"version": 6, "parables": [{"storyId": "a", "flag": true}]}'
        same_text = '{"version": 6, "parables": [{"storyId": "a", "flag": 1}]}'
        bumped_text = '{"version": 7, "parables": [{"storyId": "a", "flag": 1}]}'
        result = self._run(None, None,
                           base_text=base_text, current_text=same_text)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("not bumped", result.stderr)
        result = self._run(None, None,
                           base_text=base_text, current_text=bumped_text)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cli_nonstandard_json_constant_rejected(self):
        # NaN parses under permissive json.loads but is not JSON; the bump
        # validator must refuse to load it rather than admit it into the
        # semantic comparison.
        base_text = '{"version": 6, "parables": [{"storyId": NaN}]}'
        result = self._run(None, _manifest(version=6), base_text=base_text)
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot load base", result.stderr)

    def test_cli_real_repo_manifest_passes_against_unversioned_base(self):
        # The actual initial-migration shape: pre-migration base (identical
        # semantic content, no version) vs the real bundled manifest v6.
        real = json.loads(
            (REPO_ROOT / "assets" / "stories" / "manifest.json")
            .read_text(encoding="utf-8"))
        self.assertEqual(real.get("version"), 6)
        base = dict(real)
        base.pop("version")
        result = self._run(base, real)
        self.assertEqual(result.returncode, 0, result.stderr)


class NoBaseModeTests(unittest.TestCase):
    """--no-base: the base revision genuinely has no manifest."""

    def _run_no_base(self, current_obj, extra_args=()):
        with tempfile.TemporaryDirectory() as tmp:
            current_path = pathlib.Path(tmp) / "current.json"
            current_path.write_text(json.dumps(current_obj))
            return subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "check_manifest_version_bump.py"),
                 "--no-base", "--current", str(current_path), *extra_args],
                capture_output=True, text=True, check=False)

    def test_new_manifest_with_positive_version_passes(self):
        result = self._run_no_base(_manifest(version=6))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("catalog generation 6", result.stdout)

    def test_new_manifest_without_valid_version_fails(self):
        for bad in (None, 0, -1, True, "6", 6.0):
            with self.subTest(version=bad):
                m = _manifest(version=bad) if bad is not None else _manifest()
                result = self._run_no_base(m)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn("positive integer", result.stderr)

    def test_base_and_no_base_are_mutually_exclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "m.json"
            path.write_text(json.dumps(_manifest(version=6)))
            both = subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "check_manifest_version_bump.py"),
                 "--no-base", "--base", str(path), "--current", str(path)],
                capture_output=True, text=True, check=False)
            self.assertEqual(both.returncode, 1)
            self.assertIn("exactly one of --base or --no-base", both.stderr)

            neither = subprocess.run(
                [sys.executable,
                 str(REPO_ROOT / "scripts" / "check_manifest_version_bump.py"),
                 "--current", str(path)],
                capture_output=True, text=True, check=False)
            self.assertEqual(neither.returncode, 1)
            self.assertIn("exactly one of --base or --no-base",
                          neither.stderr)


class CiEnforcementScriptTests(unittest.TestCase):
    """scripts/ci/enforce_manifest_version_bump.sh — the shared gate used by
    BOTH the pull_request check and the protected-branch push/merge check.

    A PR-only gate leaves the merge path unprotected, so this script must
    work from any base revision the workflow hands it.
    """

    SCRIPT = REPO_ROOT / "scripts" / "ci" / "enforce_manifest_version_bump.sh"

    def _git(self, repo, *args, check=True):
        return subprocess.run(["git", "-C", str(repo), *args],
                              capture_output=True, text=True, check=check)

    def _repo(self, tmp: pathlib.Path) -> pathlib.Path:
        repo = tmp / "repo"
        (repo / "assets" / "stories").mkdir(parents=True)
        (repo / "scripts" / "ci").mkdir(parents=True)
        shutil.copy(REPO_ROOT / "scripts" / "check_manifest_version_bump.py",
                    repo / "scripts" / "check_manifest_version_bump.py")
        shutil.copy(REPO_ROOT / "scripts" / "validate_catalog_manifest.py",
                    repo / "scripts" / "validate_catalog_manifest.py")
        shutil.copy(self.SCRIPT, repo / "scripts" / "ci" /
                    "enforce_manifest_version_bump.sh")
        (repo / "scripts" / "ci" /
         "enforce_manifest_version_bump.sh").chmod(0o755)
        self._git(repo.parent, "init", "-q", str(repo))
        self._git(repo, "config", "user.email", "test@example.com")
        self._git(repo, "config", "user.name", "Test")
        return repo

    def _write_manifest(self, repo, manifest):
        (repo / "assets" / "stories" / "manifest.json").write_text(
            json.dumps(manifest))

    def _commit(self, repo, message):
        self._git(repo, "add", "-A")
        self._git(repo, "commit", "-q", "-m", message)
        return self._git(repo, "rev-parse", "HEAD").stdout.strip()

    def _enforce(self, repo, base_sha):
        return subprocess.run(
            [str(repo / "scripts" / "ci" /
                 "enforce_manifest_version_bump.sh"), base_sha],
            capture_output=True, text=True, check=False, cwd=str(repo))

    def test_push_path_accepts_a_bumped_manifest(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(pathlib.Path(tmpdir))
            self._write_manifest(repo, _manifest(version=6))
            base = self._commit(repo, "base")
            self._write_manifest(
                repo,
                _manifest(version=7,
                          parables=[{"storyId": "a"}, {"storyId": "b"}]))
            self._commit(repo, "bumped")

            result = self._enforce(repo, base)

            self.assertEqual(result.returncode, 0,
                             f"{result.stdout}\n{result.stderr}")
            self.assertIn("6 -> 7", result.stdout)

    def test_push_path_rejects_a_content_change_without_a_bump(self):
        # THE gap this closes: a merge/push that lands changed content on a
        # protected branch without a generation bump.
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(pathlib.Path(tmpdir))
            self._write_manifest(repo, _manifest(version=6))
            base = self._commit(repo, "base")
            self._write_manifest(
                repo,
                _manifest(version=6,
                          parables=[{"storyId": "a"}, {"storyId": "b"}]))
            self._commit(repo, "unbumped content change")

            result = self._enforce(repo, base)

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("was not bumped", result.stderr)

    def test_push_path_rejects_a_generation_decrease(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(pathlib.Path(tmpdir))
            self._write_manifest(repo, _manifest(version=7))
            base = self._commit(repo, "base")
            self._write_manifest(repo, _manifest(version=6))
            self._commit(repo, "downgrade")

            result = self._enforce(repo, base)

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("never decrease", result.stderr)

    def test_base_without_a_manifest_falls_back_to_no_base_mode(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(pathlib.Path(tmpdir))
            (repo / "README.md").write_text("seed\n")
            base = self._commit(repo, "no manifest yet")
            self._write_manifest(repo, _manifest(version=6))
            self._commit(repo, "add manifest")

            result = self._enforce(repo, base)

            self.assertEqual(result.returncode, 0,
                             f"{result.stdout}\n{result.stderr}")
            self.assertIn("treating as a new file", result.stdout)
            self.assertIn("catalog generation 6", result.stdout)

    def test_missing_base_sha_argument_fails(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(pathlib.Path(tmpdir))
            self._write_manifest(repo, _manifest(version=6))
            self._commit(repo, "base")
            result = subprocess.run(
                [str(repo / "scripts" / "ci" /
                     "enforce_manifest_version_bump.sh")],
                capture_output=True, text=True, check=False, cwd=str(repo))
            self.assertEqual(result.returncode, 1)
            self.assertIn("base revision SHA is required", result.stderr)


class WorkflowWiringTests(unittest.TestCase):
    """The gate is only real if CI actually runs it on both event types.

    Deliberately parsed as text rather than YAML: this suite must run on a
    bare CI runner with no third-party Python packages installed.
    """

    WORKFLOW = REPO_ROOT / ".github" / "workflows" / "flutter.yml"

    def _steps(self):
        """Split the workflow into `- name:` step blocks."""
        text = self.WORKFLOW.read_text()
        blocks, current = [], None
        for line in text.split("\n"):
            if line.lstrip().startswith("- name:"):
                if current is not None:
                    blocks.append("\n".join(current))
                current = [line]
            elif current is not None:
                current.append(line)
        if current is not None:
            blocks.append("\n".join(current))
        return blocks

    def test_both_pull_request_and_push_paths_are_enforced(self):
        gated = [b for b in self._steps()
                 if "enforce_manifest_version_bump.sh" in b
                 or "check_manifest_version_bump.py" in b]
        self.assertTrue(gated, "no manifest bump enforcement step found")
        conditions = " ".join(
            line for b in gated for line in b.split("\n")
            if line.strip().startswith("if:"))
        self.assertIn("pull_request", conditions,
                      "the PR path must be gated")
        self.assertIn("'push'", conditions,
                      "the protected-branch push/merge path must be gated "
                      "too — a PR-only gate leaves merges unprotected")

    def test_push_gate_uses_the_previous_tip_as_base(self):
        push_steps = [b for b in self._steps()
                      if "github.event_name == 'push'" in b
                      and "manifest_version_bump" in b]
        self.assertEqual(len(push_steps), 1, "expected one push-path gate")
        self.assertIn("github.event.before", push_steps[0],
                      "the push gate must compare against the ref's "
                      "previous tip, never a guess")

    def test_workflow_triggers_on_protected_branch_pushes(self):
        text = self.WORKFLOW.read_text()
        header = text[:text.index("jobs:")]
        self.assertRegex(header, r"push:\s*\n\s*branches:.*master")


if __name__ == "__main__":
    unittest.main()
