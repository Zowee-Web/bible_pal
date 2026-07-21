#!/usr/bin/env python3
"""Real integration tests: run the actual pre-commit hook in temporary Git repos.

These do NOT reimplement the hook's regexes or inspect source strings. Each test
builds a throwaway Git repository, stages real content, invokes
`scripts/git_hooks/pre-commit` as a subprocess, and asserts on its actual stdout
and exit code.

The temp repo gets a real copy of scripts/ (small) so REPO_ROOT resolves inside
it, plus symlinks to the canonical Bible JSON and the meta schema, which are
read-only reference data.

Run:
    python3 -m unittest scripts.tests.test_reconstruction_hook_integration -v
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
HOOK_SRC = REPO_ROOT / "scripts" / "git_hooks" / "pre-commit"
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from lib.bible_ref_parser import parse_bible_refs, extract_verses  # noqa: E402


def canonical_text(anchor, lane="kjv"):
    with (REPO_ROOT / "server" / "data" / f"bible_{lane}.json").open() as f:
        data = json.load(f)
    out = []
    for ref in parse_bible_refs(anchor):
        out.extend(extract_verses(data, ref))
    return " ".join(t for _, _, t in out)


class TempGitRepo:
    """A throwaway Git repo wired to run the real hook."""

    def __init__(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name) / "repo"
        self.root.mkdir()
        self._git("init", "-q")
        self._git("config", "user.email", "t@example.com")
        self._git("config", "user.name", "T")
        # Real scripts tree so REPO_ROOT resolves to THIS repo.
        shutil.copytree(REPO_ROOT / "scripts" / "lib", self.root / "scripts" / "lib")
        shutil.copy2(REPO_ROOT / "scripts" / "validate_corpus.py",
                     self.root / "scripts" / "validate_corpus.py")
        # The kid gate imports and drives this module; without it the gate can
        # only ever fail to import, so kid tests would prove nothing.
        shutil.copy2(REPO_ROOT / "scripts" / "validate_kids.py",
                     self.root / "scripts" / "validate_kids.py")
        (self.root / "scripts" / "git_hooks").mkdir(parents=True)
        shutil.copy2(HOOK_SRC, self.root / "scripts" / "git_hooks" / "pre-commit")
        os.chmod(self.root / "scripts" / "git_hooks" / "pre-commit", 0o755)
        # Read-only reference data, symlinked to avoid copying ~9 MB.
        (self.root / "server").mkdir()
        (self.root / "server" / "data").symlink_to(REPO_ROOT / "server" / "data")
        (self.root / "assets" / "stories").mkdir(parents=True)
        shutil.copy2(REPO_ROOT / "assets" / "stories" / "meta.schema.json",
                     self.root / "assets" / "stories" / "meta.schema.json")
        # Baseline commit. In the real repository meta.schema.json is a tracked
        # file, so it is always present in the index; a temp repo that merely
        # copied it into the worktree would make every partial-stage test hit
        # "schema unavailable" instead of exercising its actual subject.
        self._git("add", "-A")
        self._git("commit", "-qm", "baseline")

    def cleanup(self):
        self._tmp.cleanup()

    def _git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=str(self.root),
                              capture_output=True, text=True, check=check)

    def git(self, *args, check=True):
        return self._git(*args, check=check)

    def story_dir(self, sid):
        d = self.root / "assets" / "stories" / "traditional" / str(sid)
        d.mkdir(parents=True, exist_ok=True)
        return d

    def write(self, rel, content):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            p.write_bytes(content)
        else:
            p.write_text(content, encoding="utf-8")
        return p

    def write_meta(self, sid, anchor="1 Samuel 24", files=None, extra=None):
        meta = {
            "schemaVersion": 2, "storyId": int(sid), "mode": "traditional",
            "kidFriendly": False, "languageStyle": "WEB", "mood": "hurting",
            "lengths": ["short"], "createdByModel": "claude-opus-4-8",
            "generationBatch": "TEST", "title": "T",
            "scriptureAnchor": anchor, "bibleStoryKey": "t",
            # Must satisfy the real meta.schema.json enum, or every fixture
            # would trip a schema FAIL and mask what the test is checking.
            "storyVoiceKey": "VOICE_DAVID_SHEPHERD", "timelineEra": "kingdom",
            "primaryCharacterId": "x", "primaryCharacterDisplayName": "X",
            "files": files if files is not None else {},
        }
        if extra:
            meta.update(extra)
        self.write(f"assets/stories/traditional/{sid}/meta_{sid}.json",
                   json.dumps(meta, indent=2))
        return meta

    def cached_status(self, rel):
        """The Git status letter(s) actually recorded for `rel`, or None."""
        out = self._git("diff", "--cached", "--name-status",
                        "--diff-filter=ACMRDT").stdout
        for line in out.splitlines():
            if not line.strip():
                continue
            parts = line.split("\t")
            if rel in parts[1:]:
                return parts[0]
        return None

    def stage_symlink_over(self, rel, target="/etc/passwd"):
        """Replace a tracked regular file with a symlink and stage it."""
        p = self.root / rel
        if p.exists() or p.is_symlink():
            p.unlink()
        os.symlink(target, p)
        self._git("--literal-pathspecs", "add", rel)
        return rel

    def stage_gitlink_over(self, rel):
        """Force a gitlink (mode 160000) index entry for `rel`."""
        sha = self._git("rev-parse", "HEAD").stdout.strip()
        self._git("rm", "-q", "--cached", rel)
        self._git("update-index", "--add", "--cacheinfo",
                  f"160000,{sha},{rel}")
        return rel

    def stage_executable(self, rel, content):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        os.chmod(p, 0o755)
        self._git("--literal-pathspecs", "add", rel)
        return rel

    def run_hook(self):
        """Invoke the REAL hook script; return (exit_code, stdout+stderr)."""
        proc = subprocess.run(
            ["bash", "scripts/git_hooks/pre-commit"],
            cwd=str(self.root), capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr


class HookIntegrationTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    # ---------------------------------------------------------- 1. added

    def test_1_added_canonical_story_is_analyzed(self):
        r = self.repo
        r.write_meta(100, files={"short_kjv": {
            "storyText": "story_100_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/100/story_100_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertIn("story_100_traditional_kjv_short.txt", out)
        # A valid declaration must be analyzed THROUGH the metadata route. If
        # the declaration were rejected, the staged file would still surface via
        # the explicit-path route and this test would pass for the wrong reason.
        # Post-dedupe the survivor is counted as explicit, so the proof that the
        # metadata route resolved the same path is the collapse itself.
        self.assertRegex(out, r"duplicates collapsed:\s+1")
        self.assertNotIn("rejected", out)
        self.assertEqual(code, 0)

    # ---------------------------------------------------------- 2. modified

    def test_2_modified_canonical_story_is_analyzed(self):
        r = self.repo
        r.write_meta(101, files={"short_kjv": {
            "storyText": "story_101_traditional_kjv_short.txt"}})
        p = "assets/stories/traditional/101/story_101_traditional_kjv_short.txt"
        r.write(p, "A genuine short retelling in plain words.")
        r.git("add", "-A"); r.git("commit", "-qm", "init")
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", p)
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    # ---------------------------------------------------------- 3. R100 rename

    def test_3_rename_destination_is_analyzed(self):
        r = self.repo
        r.write_meta(102, files={})
        old = "assets/stories/traditional/102/story_102_traditional_web_short.txt"
        new = "assets/stories/traditional/102/story_102_traditional_kjv_short.txt"
        r.write(old, canonical_text("1 Samuel 24", "kjv"))
        r.git("add", "-A"); r.git("commit", "-qm", "init")
        r.git("mv", old, new)
        status = r.git("diff", "--cached", "--name-status", "-M").stdout
        self.assertTrue(status.startswith("R"), f"expected a rename, got: {status!r}")
        code, out = r.run_hook()
        self.assertIn("story_102_traditional_kjv_short.txt", out,
                      "rename DESTINATION must be analyzed")
        self.assertEqual(code, 0)

    # ------------------------------------------- 4. no sibling metadata

    def test_4_story_without_sibling_metadata_is_unresolved(self):
        r = self.repo
        r.write("assets/stories/traditional/103/story_103_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[UNRESOLVED]", out)
        self.assertIn("sibling metadata not found", out)
        self.assertEqual(code, 0, "missing metadata must not block")

    # ------------------------------------------- 5. absent from meta.files

    def test_5_story_absent_from_meta_files_is_analyzed(self):
        r = self.repo
        r.write_meta(104, files={"short": {
            "storyText": "story_104_traditional_web_short.txt"}})
        r.write("assets/stories/traditional/104/story_104_traditional_web_short.txt",
                "A short retelling.")
        undeclared = ("assets/stories/traditional/104/"
                      "story_104_traditional_kjv_full.txt")
        r.write(undeclared, canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("story_104_traditional_kjv_full.txt", out,
                      "undeclared staged story must still be analyzed")
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    # ------------------------------- 6. staged blob, working tree deleted

    def test_6_staged_blob_analyzed_when_worktree_file_deleted(self):
        r = self.repo
        r.write_meta(105, files={})
        p = "assets/stories/traditional/105/story_105_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        (r.root / p).unlink()          # stage it, then delete from working tree
        self.assertFalse((r.root / p).exists())
        code, out = r.run_hook()
        self.assertIn("story_105_traditional_kjv_short.txt", out)
        self.assertIn("[RECONSTRUCTION] assets/", out,
                      "the staged blob must still be analyzed")
        self.assertEqual(code, 0)

    # ------------------------------- 7. partial staging -> index bytes win

    def test_7_partial_staging_analyzes_index_bytes_not_worktree(self):
        r = self.repo
        r.write_meta(106, files={})
        p = "assets/stories/traditional/106/story_106_traditional_kjv_short.txt"
        r.write(p, "placeholder")
        r.git("add", "-A"); r.git("commit", "-qm", "init")
        # Stage an exact reproduction...
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", p)
        # ...then make the WORKING TREE a harmless retelling.
        r.write(p, "A completely different short retelling with original words.")
        code, out = r.run_hook()
        self.assertIn("content source: git-index", out)
        self.assertIn("[RECONSTRUCTION] assets/", out,
                      "must flag the STAGED reproduction, not the clean worktree")
        self.assertEqual(code, 0)

    def test_7b_inverse_clean_index_dirty_worktree_not_flagged(self):
        """The mirror case: a clean staged blob must not be flagged because the
        working tree happens to contain a reproduction."""
        r = self.repo
        r.write_meta(107, files={})
        p = "assets/stories/traditional/107/story_107_traditional_kjv_short.txt"
        r.write(p, "placeholder")
        r.git("add", "-A"); r.git("commit", "-qm", "init")
        r.write(p, "A completely different short retelling with original words.")
        r.git("add", p)
        r.write(p, canonical_text("1 Samuel 24"))   # worktree is a copy
        code, out = r.run_hook()
        self.assertNotIn("[RECONSTRUCTION] assets/", out,
                         "worktree content must not drive the verdict")
        self.assertEqual(code, 0)

    # ------------------------------- 8. staged metadata -> declared traversal

    def test_8_staged_metadata_triggers_declared_story_analysis(self):
        r = self.repo
        p = "assets/stories/traditional/108/story_108_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.write_meta(108, files={})
        r.git("add", "-A"); r.git("commit", "-qm", "init")
        # Only the META changes now; the story is untouched but declared.
        r.write_meta(108, files={"short_kjv": {
            "storyText": "story_108_traditional_kjv_short.txt"}})
        r.git("add", f"assets/stories/traditional/108/meta_108.json")
        code, out = r.run_hook()
        self.assertIn("story_108_traditional_kjv_short.txt", out)
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    # ------------------------------- 9/10/11. metadata path safety

    def test_9_absolute_metadata_story_path_rejected(self):
        r = self.repo
        r.write_meta(109, files={"short": {"storyText": "/etc/passwd"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("metadata storyText rejected", out)
        self.assertIn("must be a bare filename", out)
        self.assertEqual(code, 0)

    def test_10_traversal_metadata_story_path_rejected(self):
        r = self.repo
        r.write_meta(110, files={"short": {
            "storyText": "../109/story_109_traditional_kjv_short.txt"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("metadata storyText rejected", out)
        self.assertEqual(code, 0)

    def test_11_story_id_disagreement_rejected(self):
        r = self.repo
        r.write_meta(111, files={"short": {
            "storyText": "story_999_traditional_kjv_short.txt"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("story id disagreement", out)
        self.assertEqual(code, 0)

    # ------------------------------- 12. malformed story-like filename

    def test_12_malformed_story_like_filename_does_not_vanish(self):
        r = self.repo
        r.write_meta(112, files={})
        r.write("assets/stories/traditional/112/story_112_traditional_greek_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("story_112_traditional_greek_short.txt", out,
                      "a story-like path must be explicitly reported, not dropped")
        self.assertIn("[UNRESOLVED]", out)
        self.assertEqual(code, 0)

    # ------------------------------- 13. invalid UTF-8

    def test_13_invalid_utf8_staged_story_cannot_block(self):
        r = self.repo
        r.write_meta(113, files={})
        r.write("assets/stories/traditional/113/story_113_traditional_kjv_short.txt",
                b"\xff\xfe\x00 invalid utf-8 bytes \xc3\x28")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[UNRESOLVED]", out)
        self.assertIn("not valid UTF-8", out)
        self.assertEqual(code, 0, "invalid UTF-8 must not block a commit")

    # ------------------------------- 14/15. advisory exits zero

    def test_14_reconstruction_finding_exits_zero(self):
        r = self.repo
        r.write_meta(114, files={"short_kjv": {
            "storyText": "story_114_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/114/story_114_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    def test_15_reconstruction_input_error_exits_zero(self):
        r = self.repo
        r.write_meta(115, anchor="Nonexistent Book 9:9", files={"short_kjv": {
            "storyText": "story_115_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/115/story_115_traditional_kjv_short.txt",
                "some prose")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[UNRESOLVED]", out)
        self.assertEqual(code, 0)

    # ------------------------------- 16/17. blocking preserved

    def test_16_schema_failure_still_blocks(self):
        r = self.repo
        r.write("assets/stories/traditional/116/meta_116.json",
                json.dumps({"storyId": 116, "bogusField": True}))
        r.write("assets/stories/traditional/116/story_116_traditional_kjv_short.txt",
                "prose")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("[FAIL]", out)
        self.assertNotEqual(code, 0, "schema failure must still block")

    def test_17_strict_bucket_failure_still_blocks(self):
        """--strict-bucket is not used by the hook; assert the CLI directly."""
        r = self.repo
        r.write_meta(117, files={"short_kjv": {
            "storyText": "story_117_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/117/story_117_traditional_kjv_short.txt",
                "far too short to satisfy the bucket floor")
        proc = subprocess.run(
            [sys.executable, "scripts/validate_corpus.py", "--reconstruction",
             "--strict-bucket", "--paths",
             "assets/stories/traditional/117/meta_117.json"],
            cwd=str(r.root), capture_output=True, text=True)
        self.assertIn("[FAIL]", proc.stdout)
        self.assertNotEqual(proc.returncode, 0,
                            "strict bucket failure must still block")

    # ------------------------------- extra: nothing staged

    def test_18_no_relevant_staged_files_exits_zero_quietly(self):
        r = self.repo
        r.write("README.md", "hello")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertEqual(code, 0)
        self.assertNotIn("[RECONSTRUCTION]", out)


if __name__ == "__main__":
    unittest.main()


class IndexAuthorityTestCase(unittest.TestCase):
    """Staged (index) metadata and prose must win over working-tree copies."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def _seed(self, sid, files=None, anchor="1 Samuel 24"):
        r = self.repo
        r.write_meta(sid, anchor=anchor, files=files or {})
        r.git("add", "-A")
        r.git("commit", "-qm", "seed")

    # 1/2. staged valid metadata, malformed working copy -> staged wins
    def test_i1_staged_valid_meta_beats_malformed_worktree_meta(self):
        r = self.repo
        self._seed(200, files={})
        mp = "assets/stories/traditional/200/meta_200.json"
        r.write_meta(200, files={"short_kjv": {
            "storyText": "story_200_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/200/story_200_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        r.write(mp, "{ this is not json")      # corrupt the WORKING copy only
        code, out = r.run_hook()
        self.assertNotIn("invalid JSON", out, "staged metadata must be used")
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    # 3. staged malformed metadata, valid working copy -> schema failure
    def test_i2_staged_malformed_meta_fails_even_if_worktree_valid(self):
        r = self.repo
        self._seed(201, files={})
        mp = "assets/stories/traditional/201/meta_201.json"
        r.write(mp, "{ not json at all")
        r.git("add", mp)
        r.write_meta(201, files={})            # working copy is valid again
        code, out = r.run_hook()
        self.assertIn("[FAIL]", out)
        self.assertIn("invalid JSON", out)
        self.assertNotEqual(code, 0, "staged malformed metadata must block")

    # 4. staged metadata deleted from the working tree
    def test_i3_staged_meta_validated_with_no_worktree_copy(self):
        r = self.repo
        r.write_meta(202, files={"short_kjv": {
            "storyText": "story_202_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/202/story_202_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        (r.root / "assets/stories/traditional/202/meta_202.json").unlink()
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out,
                      "staged metadata must still drive traversal")
        self.assertEqual(code, 0)

    # 5. staged metadata selects KJV while working metadata selects WEB
    def test_i4_staged_meta_lane_selection_wins(self):
        r = self.repo
        d = "assets/stories/traditional/203"
        r.write_meta(203, files={})
        r.write(f"{d}/story_203_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24", "kjv"))
        r.write(f"{d}/story_203_traditional_web_short.txt",
                "A clean original retelling in modern words with no copying.")
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        # STAGED metadata declares the KJV (reproduction) file...
        r.write_meta(203, files={"short_kjv": {
            "storyText": "story_203_traditional_kjv_short.txt"}})
        r.git("add", f"{d}/meta_203.json")
        # ...while the WORKING copy declares the clean WEB file.
        r.write_meta(203, files={"short": {
            "storyText": "story_203_traditional_web_short.txt"}})
        code, out = r.run_hook()
        self.assertIn("story_203_traditional_kjv_short.txt", out,
                      "staged KJV declaration must be followed")
        self.assertNotIn("story_203_traditional_web_short.txt", out,
                         "working-tree WEB declaration must be ignored")
        self.assertEqual(code, 0)

    # 6. metadata-only staged change with a partially staged declared story
    def test_i5_meta_only_change_uses_index_story_bytes(self):
        r = self.repo
        d = "assets/stories/traditional/204"
        p = f"{d}/story_204_traditional_kjv_short.txt"
        r.write_meta(204, files={"short_kjv": {
            "storyText": "story_204_traditional_kjv_short.txt"}})
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.write_meta(204, anchor="1 Samuel 24", files={"short_kjv": {
            "storyText": "story_204_traditional_kjv_short.txt"}},
            extra={"mood": "calm_peaceful"})
        r.git("add", f"{d}/meta_204.json")
        r.write(p, "Working-tree clean retelling that must NOT be consulted.")
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out,
                      "index story bytes must be used, not the clean worktree")
        self.assertEqual(code, 0)

    # 7. declared story absent from working tree
    def test_i6_declared_story_absent_from_worktree_still_analyzed(self):
        r = self.repo
        d = "assets/stories/traditional/205"
        p = f"{d}/story_205_traditional_kjv_short.txt"
        r.write_meta(205, files={"short_kjv": {
            "storyText": "story_205_traditional_kjv_short.txt"}})
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        (r.root / p).unlink()
        code, out = r.run_hook()
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    # 15/16. staged vs working story validity
    def test_i7_staged_valid_story_invalid_worktree(self):
        r = self.repo
        d = "assets/stories/traditional/206"
        p = f"{d}/story_206_traditional_kjv_short.txt"
        r.write_meta(206, files={})
        r.write(p, "clean")
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.write(p, "A clean original retelling staged for commit.")
        r.git("add", p)
        r.write(p, b"\xff\xfe invalid working copy")
        code, out = r.run_hook()
        self.assertNotIn("not valid UTF-8", out,
                         "invalid WORKING copy must not be read")
        self.assertEqual(code, 0)

    def test_i8_staged_invalid_story_valid_worktree(self):
        r = self.repo
        d = "assets/stories/traditional/207"
        p = f"{d}/story_207_traditional_kjv_short.txt"
        r.write_meta(207, files={})
        r.write(p, "clean")
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.write(p, b"\xff\xfe invalid staged bytes")
        r.git("add", p)
        r.write(p, "A perfectly valid working copy.")
        code, out = r.run_hook()
        self.assertIn("not valid UTF-8", out,
                      "the STAGED invalid bytes must be reported")
        self.assertEqual(code, 0, "invalid UTF-8 is advisory")

    # 14. declared invalid UTF-8 must not crash bucket validation
    def test_i9_declared_invalid_utf8_does_not_crash_bucket_check(self):
        r = self.repo
        d = "assets/stories/traditional/208"
        r.write_meta(208, files={"short_kjv": {
            "storyText": "story_208_traditional_kjv_short.txt"}})
        r.write(f"{d}/story_208_traditional_kjv_short.txt",
                b"\xff\xfe\x00 not utf-8")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertNotIn("Traceback", out)
        self.assertIn("unreadable", out)
        self.assertEqual(code, 0)


class PathAtomicityTestCase(unittest.TestCase):
    """Exotic filenames must survive enumeration -> Python argv intact."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def _stage_named(self, sid, filename):
        r = self.repo
        r.write_meta(sid, files={})
        r.write(f"assets/stories/traditional/{sid}/{filename}", "content here")
        r.git("add", "-A")
        return r.run_hook()

    def test_p1_space_in_malformed_story_filename(self):
        code, out = self._stage_named(300, "story_300 traditional_kjv_short.txt")
        self.assertIn("story_300 traditional_kjv_short.txt", out)
        self.assertEqual(code, 0)

    def test_p2_tab_in_malformed_story_filename(self):
        code, out = self._stage_named(301, "story_301\ttraditional_kjv_short.txt")
        self.assertIn("story_301", out)
        self.assertEqual(code, 0)

    def test_p3_newline_in_malformed_story_filename(self):
        code, out = self._stage_named(302, "story_302\nweird.txt")
        self.assertIn("story_302", out)
        self.assertEqual(code, 0)

    def test_p4_glob_chars_do_not_expand_to_unstaged_files(self):
        r = self.repo
        d = "assets/stories/traditional/303"
        r.write_meta(303, files={})
        r.write(f"{d}/story_303_*.txt", "globby staged file")
        r.git("--literal-pathspecs", "add", f"{d}/story_303_*.txt")
        r.write_meta(303, files={})
        r.git("--literal-pathspecs", "add", f"{d}/meta_303.json")
        r.git("commit", "-qm", "seed")
        # An UNSTAGED neighbour that a glob would match if the HOOK expanded.
        r.write(f"{d}/story_303_unstaged_neighbour.txt", "must not be pulled in")
        r.write(f"{d}/story_303_*.txt", "globby staged file, modified")
        r.git("--literal-pathspecs", "add", f"{d}/story_303_*.txt")
        code, out = r.run_hook()
        self.assertNotIn("story_303_unstaged_neighbour.txt", out,
                         "glob expansion must never add an unstaged file")
        self.assertEqual(code, 0)

    def test_p5_backslash_and_bracket_filenames(self):
        code, out = self._stage_named(304, "story_304_[a-z]_kjv_short.txt")
        self.assertIn("story_304_", out)
        self.assertEqual(code, 0)


class GitInfrastructureFailureTestCase(unittest.TestCase):
    """Machinery failures must BLOCK, never look like a clean advisory pass."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_g1_corrupt_index_blocks(self):
        r = self.repo
        r.write_meta(400, files={})
        r.write("assets/stories/traditional/400/story_400_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        # Corrupt the index AFTER staging.
        (r.root / ".git" / "index").write_bytes(b"NOT A GIT INDEX")
        proc = subprocess.run(["bash", "scripts/git_hooks/pre-commit"],
                              cwd=str(r.root), capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0,
                            "a corrupt index must block, not pass")

    def test_g2_missing_blob_blocks(self):
        r = self.repo
        r.write_meta(401, files={"short_kjv": {
            "storyText": "story_401_traditional_kjv_short.txt"}})
        p = "assets/stories/traditional/401/story_401_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        sha = r.git("rev-parse", f":{p}").stdout.strip()
        obj = r.root / ".git" / "objects" / sha[:2] / sha[2:]
        self.assertTrue(obj.exists(), "expected a loose object to remove")
        obj.unlink()
        code, out = r.run_hook()
        self.assertNotEqual(code, 0, "a missing Git object must block")
        self.assertIn("INFRASTRUCTURE-FAILURE", out)

    def test_g3_enumeration_failure_blocks(self):
        r = self.repo
        r.write_meta(402, files={})
        r.git("add", "-A")
        bad_index = r.root.parent / "corrupt_index"
        bad_index.write_bytes(b"DIRC\x00\x00\x00\x99 garbage that is not an index")
        env = dict(os.environ, GIT_INDEX_FILE=str(bad_index))
        proc = subprocess.run(["bash", "scripts/git_hooks/pre-commit"],
                              cwd=str(r.root), capture_output=True, text=True,
                              env=env)
        self.assertNotEqual(proc.returncode, 0,
                            "git enumeration failure must block")


class SymlinkAndModeTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_s1_mode_120000_story_is_rejected(self):
        r = self.repo
        d = "assets/stories/traditional/500"
        r.write_meta(500, files={})
        r.write(f"{d}/real_target.txt", canonical_text("1 Samuel 24"))
        link = r.root / d / "story_500_traditional_kjv_short.txt"
        link.symlink_to("real_target.txt")
        r.git("add", "-A")
        modes = r.git("ls-files", "-s", "--", f"{d}/story_500_traditional_kjv_short.txt").stdout
        self.assertTrue(modes.startswith("120000"), f"expected symlink mode: {modes!r}")
        code, out = r.run_hook()
        self.assertIn("symlink", out.lower())
        self.assertNotIn("[RECONSTRUCTION] assets/", out,
                         "a symlink target must never be decoded as prose")
        self.assertEqual(code, 0)

    def test_s2_distinct_paths_not_merged_via_symlinks(self):
        r = self.repo
        d = "assets/stories/traditional/501"
        r.write_meta(501, files={})
        r.write(f"{d}/story_501_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.write(f"{d}/story_501_traditional_web_short.txt",
                canonical_text("1 Samuel 24", "web"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("story_501_traditional_kjv_short.txt", out)
        self.assertIn("story_501_traditional_web_short.txt", out)
        self.assertEqual(code, 0)


class IdentityRuleTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_r1_key_length_mismatch_rejected(self):
        r = self.repo
        r.write_meta(600, files={"short": {
            "storyText": "story_600_traditional_kjv_full.txt"}})
        r.write("assets/stories/traditional/600/story_600_traditional_kjv_full.txt",
                "text")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("declares length", out)
        self.assertEqual(code, 0)

    def test_r2_kjv_key_pointing_at_web_file_rejected(self):
        r = self.repo
        r.write_meta(601, files={"short_kjv": {
            "storyText": "story_601_traditional_web_short.txt"}})
        r.write("assets/stories/traditional/601/story_601_traditional_web_short.txt",
                "text")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("KJV key but the filename is WEB", out)
        self.assertEqual(code, 0)

    def test_r3_non_allowlisted_unsuffixed_kjv_is_rejected(self):
        """A 25th unsuffixed-key/KJV declaration must NOT inherit the exception."""
        r = self.repo
        r.write_meta(602, files={"short": {
            "storyText": "story_602_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/602/story_602_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("only permitted for the 24 enumerated legacy declarations",
                      out)
        self.assertEqual(code, 0, "rejection is advisory, not blocking")

    def test_r3b_allowlisted_legacy_declaration_is_accepted(self):
        """One of the exact 24 (storyId 1000, key 'short') still validates."""
        r = self.repo
        r.write_meta(1000, files={"short": {
            "storyText": "story_1000_traditional_kjv_short.txt"}})
        r.write("assets/stories/traditional/1000/story_1000_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertNotIn("only permitted for the 24", out)
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertIn("lane KJV", out, "lane must come from the filename")
        self.assertEqual(code, 0)

    def test_r4_external_absolute_explicit_path_rejected_and_not_read(self):
        r = self.repo
        outside = pathlib.Path(tempfile.mkdtemp()) / "assets" / "stories" \
            / "traditional" / "700"
        outside.mkdir(parents=True)
        secret = outside / "story_700_traditional_kjv_short.txt"
        secret.write_text("SENTINEL_EXTERNAL_CONTENT", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, "scripts/validate_corpus.py", "--reconstruction",
             "--reconstruction-from-index",
             "--reconstruction-story-paths", str(secret)],
            cwd=str(r.root), capture_output=True, text=True)
        self.assertIn("not inside the approved repository root", proc.stdout)
        self.assertNotIn("SENTINEL_EXTERNAL_CONTENT", proc.stdout)
        self.assertEqual(proc.returncode, 0)
        shutil.rmtree(outside.parents[3], ignore_errors=True)


class RenameAndCopyTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_n1_lower_similarity_rename_destination_analyzed(self):
        r = self.repo
        d = "assets/stories/traditional/800"
        old = f"{d}/story_800_traditional_web_short.txt"
        new = f"{d}/story_800_traditional_kjv_short.txt"
        r.write_meta(800, files={})
        r.write(old, "Some original prose that will be largely replaced later on.")
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("mv", old, new)
        r.write(new, canonical_text("1 Samuel 24"))   # heavy edit -> lower similarity
        r.git("add", new)
        code, out = r.run_hook()
        self.assertIn("story_800_traditional_kjv_short.txt", out)
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    def test_n2_renamed_meta_and_story_together(self):
        r = self.repo
        d1 = "assets/stories/traditional/801"
        d2 = "assets/stories/traditional/802"
        r.write_meta(801, files={"short_kjv": {
            "storyText": "story_801_traditional_kjv_short.txt"}})
        r.write(f"{d1}/story_801_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        (r.root / d2).mkdir(parents=True)
        r.git("mv", f"{d1}/story_801_traditional_kjv_short.txt",
              f"{d2}/story_802_traditional_kjv_short.txt")
        r.git("mv", f"{d1}/meta_801.json", f"{d2}/meta_802.json")
        code, out = r.run_hook()
        # Identity disagreement is expected: meta_802.json still says storyId 801.
        self.assertIn("802", out)
        self.assertEqual(code, 0)


class CountReconciliationTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_c1_duplicate_metadata_and_explicit_reconcile(self):
        r = self.repo
        d = "assets/stories/traditional/900"
        p = f"{d}/story_900_traditional_kjv_short.txt"
        r.write_meta(900, files={"short_kjv": {
            "storyText": "story_900_traditional_kjv_short.txt"}})
        r.write(p, canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        meta_n = int(re.search(r"metadata-derived evaluated:\s+(\d+)", out).group(1))
        expl_n = int(re.search(r"explicit staged paths evaluated:\s+(\d+)", out).group(1))
        dupes = int(re.search(r"duplicates collapsed:\s+(\d+)", out).group(1))
        total = int(re.search(r"total story files evaluated:\s+(\d+)", out).group(1))
        self.assertEqual(meta_n + expl_n, total,
                         "metadata + explicit must not exceed total after dedupe")
        self.assertEqual(dupes, 1, "the same path arrived twice")
        self.assertEqual(code, 0)


class DeletionClassificationTestCase(unittest.TestCase):
    """Deletions are OBSERVED and classified, and never block.

    Whether any class should block is deferred to ADR-032; these tests pin the
    observation behaviour only, so a future policy change is a deliberate edit.
    """

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def _seed(self, sid, files=None):
        r = self.repo
        d = f"assets/stories/traditional/{sid}"
        r.write(f"{d}/story_{sid}_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.write_meta(sid, files=files if files is not None else {
            "short_kjv": {"storyText": f"story_{sid}_traditional_kjv_short.txt"}})
        r.git("add", "-A")
        r.git("commit", "-qm", f"seed {sid}")
        return d

    def test_d1_declared_story_deleted_while_metadata_still_declares_it(self):
        r = self.repo
        d = self._seed(1010)
        r.git("rm", "-q", f"{d}/story_1010_traditional_kjv_short.txt")
        code, out = r.run_hook()
        self.assertIn("[DELETION-REVIEW]", out)
        self.assertIn("category: declared-story-deleted", out)
        self.assertEqual(code, 0, "deletion review is advisory under ADR-031")

    def test_d2_declaration_removed_consistently(self):
        r = self.repo
        d = self._seed(1011)
        r.git("rm", "-q", f"{d}/story_1011_traditional_kjv_short.txt")
        r.write_meta(1011, files={})           # declaration withdrawn too
        r.git("add", f"{d}/meta_1011.json")
        code, out = r.run_hook()
        self.assertIn("category: declaration-removed-consistently", out)
        self.assertEqual(code, 0)

    def test_d3_metadata_deleted_while_stories_remain(self):
        r = self.repo
        d = self._seed(1012)
        r.git("rm", "-q", f"{d}/meta_1012.json")
        code, out = r.run_hook()
        self.assertIn("category: metadata-deleted-stories-remain", out)
        self.assertIn("story_1012_traditional_kjv_short.txt", out)
        self.assertEqual(code, 0)

    def test_d4_complete_directory_removal(self):
        r = self.repo
        d = self._seed(1013)
        r.git("rm", "-q", "-r", d)
        code, out = r.run_hook()
        self.assertIn("category: complete-directory-removal", out)
        self.assertIn("category: story-deleted-with-metadata", out)
        self.assertEqual(code, 0)

    def test_d5_kid_manifest_deletion_is_classified(self):
        r = self.repo
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")
        r.git("rm", "-q", "assets/stories/kids_manifest.json")
        code, out = r.run_hook()
        self.assertIn("category: kid-manifest-deleted", out)

    def test_d6_deletion_review_states_it_does_not_block(self):
        r = self.repo
        d = self._seed(1014)
        r.git("rm", "-q", f"{d}/story_1014_traditional_kjv_short.txt")
        code, out = r.run_hook()
        self.assertIn("ADVISORY under current policy", out)
        self.assertIn("deferred to ADR-032", out)
        self.assertEqual(code, 0)


class HookModeIsolationTestCase(unittest.TestCase):
    """Hook mode must classify only the snapshot -- never sweep the corpus."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_h1_unstaged_committed_stories_are_not_scanned(self):
        r = self.repo
        for sid in (1100, 1101, 1102):
            # 1100 and 1102 are verbatim copies; if the scan ever widened past
            # the snapshot they would produce loud findings of their own.
            body = (canonical_text("1 Samuel 24") if sid != 1101
                    else "An original retelling in the narrator's own words.")
            r.write(f"assets/stories/traditional/{sid}/story_{sid}_traditional_kjv_short.txt",
                    body)
            r.write_meta(sid, files={"short_kjv": {
                "storyText": f"story_{sid}_traditional_kjv_short.txt"}})
        r.git("add", "-A"); r.git("commit", "-qm", "three stories")
        # Touch exactly ONE of them, making it verbatim.
        r.write("assets/stories/traditional/1101/story_1101_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.git("add", "assets/stories/traditional/1101/story_1101_traditional_kjv_short.txt")
        code, out = r.run_hook()
        self.assertIn("story_1101", out)
        self.assertNotIn("story_1100", out, "unstaged story must not be scanned")
        self.assertNotIn("story_1102", out, "unstaged story must not be scanned")
        self.assertRegex(out, r"Checked: 1 metas")
        self.assertEqual(code, 0)

    def test_h2_schema_absent_from_index_blocks(self):
        r = self.repo
        r.git("rm", "-q", "--cached", "assets/stories/meta.schema.json")
        r.write_meta(1103, files={})
        r.git("add", "assets/stories/traditional/1103/meta_1103.json")
        code, out = r.run_hook()
        self.assertIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertIn("schema unavailable", out)
        self.assertEqual(code, 1, "no schema to validate against must block")

    def test_h3_unmerged_index_stage_blocks(self):
        r = self.repo
        d = "assets/stories/traditional/1104"
        p = f"{d}/story_1104_traditional_kjv_short.txt"
        r.write_meta(1104, files={"short_kjv": {
            "storyText": "story_1104_traditional_kjv_short.txt"}})
        r.write(p, "base\n")
        r.git("add", "-A"); r.git("commit", "-qm", "base")
        r.git("checkout", "-q", "-b", "other")
        r.write(p, "other side\n"); r.git("add", p)
        r.git("commit", "-qm", "other")
        r.git("checkout", "-q", "master", check=False)
        r.git("checkout", "-q", "-", check=False)
        head = r.git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        if head == "other":                      # fall back to the first branch
            r.git("checkout", "-q", "@{-1}", check=False)
        r.write(p, "this side\n"); r.git("add", p)
        r.git("commit", "-qm", "this")
        merged = r.git("merge", "other", check=False)
        self.assertNotEqual(merged.returncode, 0, "fixture must create a conflict")
        # Stage an unrelated valid path so the snapshot is non-empty: status "U"
        # is not in --diff-filter=ACMRDT, and Git independently refuses to commit
        # with unmerged entries, so the conflict alone never reaches the hook.
        r.write_meta(1105, files={})
        r.git("add", "assets/stories/traditional/1105/meta_1105.json")
        code, out = r.run_hook()
        self.assertIn("unresolved merge conflict", out)
        self.assertIn("the Git index could not be read", out,
                      "an index failure must not be reported as a schema failure")
        self.assertEqual(code, 1, "an unmerged index must block, not be ignored")


class StagedVersusWorkingAuthorityTestCase(unittest.TestCase):
    """Staged bytes decide. A dirty worktree can never change the verdict."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_s1_staged_schema_is_used_not_the_worktree_schema(self):
        r = self.repo
        schema = json.loads(
            (r.root / "assets/stories/meta.schema.json").read_text())
        schema.setdefault("required", []).append("aRequiredFieldNoMetaHas")
        r.write("assets/stories/meta.schema.json", json.dumps(schema))
        r.git("add", "assets/stories/meta.schema.json")
        r.write_meta(1200, files={})
        r.git("add", "assets/stories/traditional/1200/meta_1200.json")
        # Working tree gets the ORIGINAL permissive schema back.
        shutil.copy2(REPO_ROOT / "assets" / "stories" / "meta.schema.json",
                     r.root / "assets" / "stories" / "meta.schema.json")
        code, out = r.run_hook()
        self.assertIn("aRequiredFieldNoMetaHas", out,
                      "the STAGED schema must be the one enforced")
        self.assertEqual(code, 1, "staged schema failure blocks")

    def test_s2_staged_kid_manifest_is_used_not_the_worktree_copy(self):
        r = self.repo
        # Both kid inputs must exist, as they do in the real repository: the
        # gate deliberately returns 0 when either is absent from the commit.
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")
        r.write("assets/stories/kids_manifest.json", "{ not valid json")
        r.git("add", "assets/stories/kids_manifest.json")
        r.write("assets/stories/kids_manifest.json",
                json.dumps({"stories": []}))     # clean worktree copy
        code, out = r.run_hook()
        self.assertNotIn("Traceback", out)
        # validate_kids.py exits 2 on unreadable input; its own exit semantics
        # are propagated unchanged, so assert "blocks", not a specific code.
        self.assertNotEqual(code, 0,
                            "the STAGED malformed kid manifest must fail the gate")
        self.assertEqual(code, 2, "validate_kids' own exit code is preserved")


class InventoryAndModeTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_v1_symlinked_story_dir_is_not_inventoried(self):
        r = self.repo
        real = r.root / "assets/stories/traditional/1300"
        real.mkdir(parents=True)
        (real / "story_1300_traditional_kjv_short.txt").write_text(
            canonical_text("1 Samuel 24"), encoding="utf-8")
        link = r.root / "assets/stories/traditional/1301"
        link.symlink_to(real)
        r.write_meta(1302, files={})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertNotIn("1301", out,
                         "a symlinked story directory must never be walked")
        self.assertNotIn("Traceback", out)

    def test_v2_symlinked_story_blob_in_index_is_unresolved_not_read(self):
        r = self.repo
        d = "assets/stories/traditional/1303"
        r.story_dir(1303)
        os.symlink("/etc/passwd", r.root / d / "story_1303_traditional_kjv_short.txt")
        r.write_meta(1303, files={"short_kjv": {
            "storyText": "story_1303_traditional_kjv_short.txt"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("symlink", out)
        self.assertNotIn("root:", out, "a symlink target must never be read")
        self.assertEqual(code, 0, "an unreadable input is advisory")

    def test_v3_executable_story_blob_is_noted(self):
        r = self.repo
        d = "assets/stories/traditional/1304"
        p = r.root / d / "story_1304_traditional_kjv_short.txt"
        r.story_dir(1304)
        p.write_text(canonical_text("1 Samuel 24"), encoding="utf-8")
        os.chmod(p, 0o755)
        r.write_meta(1304, files={"short_kjv": {
            "storyText": "story_1304_traditional_kjv_short.txt"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("executable mode", out)
        self.assertEqual(code, 0)

    def test_v4_malformed_metadata_filename_is_not_treated_as_canonical(self):
        r = self.repo
        d = "assets/stories/traditional/1305"
        r.story_dir(1305)
        r.write(f"{d}/meta_9999.json", json.dumps({"storyId": 1305}))
        r.write(f"{d}/metadata.json", json.dumps({"storyId": 1305}))
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertNotIn("Traceback", out)
        self.assertRegex(out, r"Checked: 0 metas")

    def test_v5_two_lanes_in_one_run_do_not_share_a_cache(self):
        r = self.repo
        d = "assets/stories/traditional/1306"
        r.write(f"{d}/story_1306_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24", lane="kjv"))
        r.write(f"{d}/story_1306_traditional_web_short.txt",
                canonical_text("1 Samuel 24", lane="web"))
        r.write_meta(1306, files={
            "short_kjv": {"storyText": "story_1306_traditional_kjv_short.txt"},
            "short": {"storyText": "story_1306_traditional_web_short.txt"}})
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("lane KJV", out)
        self.assertIn("lane WEB", out)
        # Both are verbatim copies of their OWN lane's text. If one lane's Bible
        # were reused for the other, the cross-lane comparison would not report
        # a full-length contiguous match for both.
        self.assertEqual(out.count("reconstructible: YES"), 2,
                         "each lane must be compared against its own Bible")
        self.assertEqual(code, 0)


class KidGateBoundaryTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_k1_unexpected_kid_gate_failure_is_labelled_not_a_raw_traceback(self):
        r = self.repo
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")
        # Break the module the gate drives, simulating a missing/changed API.
        (r.root / "scripts" / "validate_kids.py").unlink()
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": [1]}))
        r.git("add", "assets/stories/kids_manifest.json")
        code, out = r.run_hook()
        self.assertIn("[INTERNAL-ERROR]", out)
        self.assertIn("kid gate failed unexpectedly", out)
        self.assertEqual(code, 1, "an unexplained gate failure must block")


def assert_hook_actually_ran(case, out):
    """No test may pass because a dependency failed before validation."""
    case.assertNotIn("Missing dependency", out)
    case.assertNotIn("ModuleNotFoundError", out)


class TypeChangeTestCase(unittest.TestCase):
    """Git status T. A regular file becoming a symlink/gitlink is a change.

    Mode policy: story prose -> advisory [UNRESOLVED]; metadata, schema and kid
    inputs -> blocking. The symlink target is never followed.
    """

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def _seed_story(self, sid):
        r = self.repo
        d = f"assets/stories/traditional/{sid}"
        p = f"{d}/story_{sid}_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.write_meta(sid, files={"short_kjv": {
            "storyText": f"story_{sid}_traditional_kjv_short.txt"}})
        r.git("add", "-A"); r.git("commit", "-qm", f"seed {sid}")
        return d, p

    def _seed_kid(self):
        r = self.repo
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")

    def test_t1_story_type_change_to_symlink_is_advisory(self):
        r = self.repo
        _, p = self._seed_story(2200)
        r.stage_symlink_over(p, "/etc/passwd")
        self.assertEqual(r.cached_status(p), "T", "fixture must produce T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[UNRESOLVED] assets/stories/traditional/2200/", out)
        self.assertIn("symlink", out)
        self.assertNotIn("root:", out, "the symlink target must never be read")
        self.assertEqual(code, 0, "a story input problem is advisory")

    def test_t2_story_type_change_to_gitlink_is_advisory(self):
        r = self.repo
        _, p = self._seed_story(2201)
        r.stage_gitlink_over(p)
        self.assertEqual(r.cached_status(p), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[UNRESOLVED] assets/stories/traditional/2201/", out)
        self.assertIn("gitlink", out)
        self.assertEqual(code, 0)

    def test_t3_metadata_type_change_blocks(self):
        r = self.repo
        d, _ = self._seed_story(2202)
        meta = f"{d}/meta_2202.json"
        r.stage_symlink_over(meta)
        self.assertEqual(r.cached_status(meta), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[FAIL]", out)
        self.assertIn("symlink", out)
        self.assertNotIn("root:", out)
        self.assertEqual(code, 1, "metadata is not ordinary content")

    def test_t4_schema_type_change_blocks(self):
        r = self.repo
        r.stage_symlink_over("assets/stories/meta.schema.json")
        self.assertEqual(r.cached_status("assets/stories/meta.schema.json"), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertIn("symlink", out)
        self.assertEqual(code, 1)

    def test_t5_kid_manifest_type_change_blocks(self):
        r = self.repo
        self._seed_kid()
        r.stage_symlink_over("assets/stories/kids_manifest.json")
        self.assertEqual(r.cached_status("assets/stories/kids_manifest.json"), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("kid input is not ordinary data", out)
        self.assertEqual(code, 1)

    def test_t6_kid_registry_type_change_blocks(self):
        r = self.repo
        self._seed_kid()
        r.stage_symlink_over("assets/stories/kid_anchor_registry.json")
        self.assertEqual(
            r.cached_status("assets/stories/kid_anchor_registry.json"), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("kid input is not ordinary data", out)
        self.assertEqual(code, 1)

    def test_t7_kid_gitlink_type_change_blocks(self):
        r = self.repo
        self._seed_kid()
        r.stage_gitlink_over("assets/stories/kids_manifest.json")
        self.assertEqual(r.cached_status("assets/stories/kids_manifest.json"), "T")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("gitlink", out)
        self.assertEqual(code, 1)

    def test_t8_type_change_is_not_dropped_from_the_snapshot(self):
        """The whole point of ACMRDT: a T-only commit must still be validated."""
        r = self.repo
        _, p = self._seed_story(2203)
        r.stage_symlink_over(p)
        snap = r.git("diff", "--cached", "--name-status",
                     "--diff-filter=ACMRDT").stdout
        self.assertTrue(snap.strip().startswith("T"))
        code, out = r.run_hook()
        self.assertIn("Running validate_corpus.py", out,
                      "a T-only change must not be filtered out as irrelevant")


class SchemaValidityTestCase(unittest.TestCase):
    """The schema must itself be a valid Draft 2020-12 schema."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    INVALID = json.dumps({"type": 7})

    def test_s1_staged_invalid_schema_alone_blocks(self):
        r = self.repo
        r.write("assets/stories/meta.schema.json", self.INVALID)
        r.git("add", "assets/stories/meta.schema.json")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[INFRASTRUCTURE-FAILURE] staged metadata schema is invalid",
                      out)
        self.assertNotIn("Traceback", out)
        self.assertEqual(code, 1, "no metadata staged must not excuse it")

    def test_s2_staged_valid_beats_dirty_invalid_worktree(self):
        r = self.repo
        r.write_meta(2300, files={})
        r.git("add", "assets/stories/traditional/2300/meta_2300.json")
        r.write("assets/stories/meta.schema.json", self.INVALID)  # unstaged
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotIn("staged metadata schema is invalid", out)
        self.assertEqual(code, 0)

    def test_s3_staged_invalid_beats_clean_worktree(self):
        r = self.repo
        r.write("assets/stories/meta.schema.json", self.INVALID)
        r.git("add", "assets/stories/meta.schema.json")
        shutil.copy2(REPO_ROOT / "assets" / "stories" / "meta.schema.json",
                     r.root / "assets" / "stories" / "meta.schema.json")
        code, out = r.run_hook()
        self.assertIn("staged metadata schema is invalid", out)
        self.assertEqual(code, 1)

    def test_s4_malformed_json_schema_blocks(self):
        r = self.repo
        r.write("assets/stories/meta.schema.json", "{ not json")
        r.git("add", "assets/stories/meta.schema.json")
        code, out = r.run_hook()
        self.assertIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertNotIn("Traceback", out)
        self.assertEqual(code, 1)

    def test_s5_invalid_utf8_schema_blocks(self):
        r = self.repo
        r.write("assets/stories/meta.schema.json", b"\xff\xfe{}")
        r.git("add", "assets/stories/meta.schema.json")
        code, out = r.run_hook()
        self.assertIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertNotIn("Traceback", out)
        self.assertEqual(code, 1)

    def test_s6_unchanged_valid_schema_still_passes(self):
        r = self.repo
        r.write_meta(2301, files={})
        r.git("add", "assets/stories/traditional/2301/meta_2301.json")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertEqual(code, 0)


class RenameCopyDeleteTestCase(unittest.TestCase):
    """Only current content is validated; sources and deletions are history."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_r1_renamed_story_source_never_appears(self):
        r = self.repo
        d = "assets/stories/traditional/2400"
        old = f"{d}/story_2400_traditional_web_short.txt"
        new = f"{d}/story_2400_traditional_kjv_short.txt"
        r.write(old, canonical_text("1 Samuel 24"))
        r.write_meta(2400, files={})
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("mv", old, new)
        self.assertEqual(r.cached_status(new), "R100")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("story_2400_traditional_kjv_short.txt", out)
        self.assertNotIn("story_2400_traditional_web_short.txt", out,
                         "the rename SOURCE is history, not current content")
        self.assertEqual(code, 0)

    def test_r2_renamed_metadata_source_is_not_validated(self):
        r = self.repo
        d = "assets/stories/traditional/2401"
        r.write(f"{d}/meta_old.json", json.dumps({"storyId": 2401}))
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("mv", f"{d}/meta_old.json", f"{d}/meta_2401.json")
        self.assertEqual(r.cached_status(f"{d}/meta_2401.json"), "R100")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotIn("meta_old.json", out,
                         "the source must not raise a metadata path review")
        self.assertIn("meta_2401.json", out)

    def test_r3_copy_destination_only(self):
        r = self.repo
        d = "assets/stories/traditional/2402"
        a = f"{d}/story_2402_traditional_kjv_short.txt"
        b = f"{d}/story_2402_traditional_kjv_full.txt"
        r.write(a, canonical_text("1 Samuel 24"))
        r.write_meta(2402, files={})
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.write(b, canonical_text("1 Samuel 24"))
        r.git("add", b)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("story_2402_traditional_kjv_full.txt", out)
        self.assertEqual(out.count("story_2402_traditional_kjv_short.txt"), 0,
                         "the untouched original must not be re-reported")

    def test_r4_deleted_story_gets_one_deletion_diagnostic_only(self):
        r = self.repo
        d = "assets/stories/traditional/2403"
        p = f"{d}/story_2403_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.write_meta(2403, files={"short_kjv": {
            "storyText": "story_2403_traditional_kjv_short.txt"}})
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("rm", "-q", p)
        self.assertEqual(r.cached_status(p), "D")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 1)
        self.assertNotIn("[UNRESOLVED] assets/", out,
                         "a deletion must not also be an unresolved input")
        self.assertRegex(out, r"\[UNRESOLVED\]:\s+0")
        self.assertNotIn("[RECONSTRUCTION] assets/", out)
        self.assertEqual(code, 0)

    def test_r5_deleted_metadata_gets_one_deletion_diagnostic_only(self):
        r = self.repo
        d = "assets/stories/traditional/2404"
        r.write(f"{d}/story_2404_traditional_kjv_short.txt", "prose")
        r.write_meta(2404, files={})
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("rm", "-q", f"{d}/meta_2404.json")
        self.assertEqual(r.cached_status(f"{d}/meta_2404.json"), "D")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 1)
        self.assertNotIn("[FAIL]", out,
                         "a deleted meta must not be reported as unreadable")
        self.assertRegex(out, r"Checked: 0 metas")
        self.assertEqual(code, 0)

    def test_r6_low_similarity_delete_plus_add(self):
        r = self.repo
        d = "assets/stories/traditional/2405"
        old = f"{d}/story_2405_traditional_web_short.txt"
        new = f"{d}/story_2405_traditional_kjv_short.txt"
        r.write(old, "Entirely unrelated placeholder prose about nothing.")
        r.write_meta(2405, files={})
        r.git("add", "-A"); r.git("commit", "-qm", "seed")
        r.git("rm", "-q", old)
        r.write(new, canonical_text("1 Samuel 24"))
        r.git("add", new)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[DELETION-REVIEW]", out)
        self.assertIn("[RECONSTRUCTION] assets/", out)
        self.assertIn("story_2405_traditional_kjv_short.txt", out)
        self.assertEqual(code, 0)


class HookInventoryIsolationTestCase(unittest.TestCase):
    """Hook mode must never walk the working-tree corpus."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_n1_hook_prints_no_undeclared_inventory(self):
        r = self.repo
        d = "assets/stories/traditional/2500"
        r.write(f"{d}/story_2500_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        r.write_meta(2500, files={})       # declares nothing
        r.git("add", "-A")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotIn("INVENTORY", out)
        self.assertNotIn("undeclared on disk", out)
        self.assertEqual(code, 0)

    def test_n2_unstaged_undeclared_story_does_not_change_output(self):
        r = self.repo
        d = "assets/stories/traditional/2501"
        r.write_meta(2501, files={})
        r.git("add", "-A")
        before_code, before = r.run_hook()
        # An UNSTAGED undeclared story appears on disk elsewhere.
        r.write("assets/stories/traditional/2502/story_2502_traditional_kjv_short.txt",
                canonical_text("1 Samuel 24"))
        after_code, after = r.run_hook()
        self.assertEqual(before, after,
                         "an unstaged working-tree file must not alter the hook")
        self.assertEqual(before_code, after_code)
        self.assertNotIn("2502", after)


class ExecutableModeTestCase(unittest.TestCase):
    """One policy: data inputs block, story prose is advisory."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_x1_executable_metadata_blocks(self):
        r = self.repo
        d = "assets/stories/traditional/2600"
        r.story_dir(2600)
        meta = r.write_meta(2600, files={})
        r.stage_executable(f"{d}/meta_2600.json", json.dumps(meta))
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("executable mode 100755", out)
        self.assertEqual(code, 1)

    def test_x2_executable_schema_blocks(self):
        r = self.repo
        schema = (r.root / "assets/stories/meta.schema.json").read_text()
        r.stage_executable("assets/stories/meta.schema.json", schema)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertIn("executable mode 100755", out)
        self.assertEqual(code, 1)

    def test_x3_executable_kid_inputs_block(self):
        r = self.repo
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.stage_executable("assets/stories/kids_manifest.json",
                           json.dumps({"stories": []}))
        r.git("add", "assets/stories/kid_anchor_registry.json")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("kid input is not ordinary data", out)
        self.assertIn("executable mode 100755", out)
        self.assertEqual(code, 1)

    def test_x4_declared_executable_story_is_one_advisory(self):
        r = self.repo
        d = "assets/stories/traditional/2601"
        r.write_meta(2601, files={"short_kjv": {
            "storyText": "story_2601_traditional_kjv_short.txt"}})
        r.stage_executable(f"{d}/story_2601_traditional_kjv_short.txt",
                           canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[UNRESOLVED] assets/"), 1)
        self.assertIn("executable mode 100755", out)
        self.assertIn("must be 100644", out)
        self.assertNotIn("[RECONSTRUCTION] assets/", out,
                         "an executable blob is not analyzed as ordinary prose")
        self.assertEqual(code, 0)

    def test_x5_undeclared_executable_story_is_one_advisory(self):
        r = self.repo
        d = "assets/stories/traditional/2602"
        r.write_meta(2602, files={})          # declares nothing
        r.stage_executable(f"{d}/story_2602_traditional_kjv_short.txt",
                           canonical_text("1 Samuel 24"))
        r.git("add", "-A")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[UNRESOLVED] assets/"), 1)
        self.assertIn("executable mode 100755", out)
        self.assertEqual(code, 0)

    def test_x6_non_reconstructible_executable_story_still_reports_mode(self):
        r = self.repo
        d = "assets/stories/traditional/2603"
        r.write_meta(2603, files={"short_kjv": {
            "storyText": "story_2603_traditional_kjv_short.txt"}})
        r.stage_executable(f"{d}/story_2603_traditional_kjv_short.txt",
                           "An original retelling that reproduces nothing.")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertIn("executable mode 100755", out)
        self.assertEqual(code, 0)

    def test_x7_story_mode_report_does_not_depend_on_bucket_output(self):
        r = self.repo
        d = "assets/stories/traditional/2604"
        # shortScripture waives the band check, so no bucket line is produced.
        r.write_meta(2604, files={"short_kjv": {
            "storyText": "story_2604_traditional_kjv_short.txt"}},
            extra={"shortScripture": True})
        r.stage_executable(f"{d}/story_2604_traditional_kjv_short.txt", "tiny")
        r.git("add", "-A")
        code, out = r.run_hook()
        self.assertNotIn("  bucket:", out, "fixture must produce no bucket line")
        self.assertIn("executable mode 100755", out,
                      "the mode advisory must stand on its own")
        self.assertEqual(code, 0)


class RelevanceHookTestCase(unittest.TestCase):
    """NUL-safe relevance, exercised through the real hook."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_q1_forged_newline_path_stays_irrelevant(self):
        r = self.repo
        name = "docs/nope\nassets/stories/meta.schema.json"
        (r.root / "docs").mkdir(parents=True, exist_ok=True)
        r.write(name, "irrelevant")
        r.git("--literal-pathspecs", "add", name)
        code, out = r.run_hook()
        self.assertEqual(out.strip(), "",
                         "a newline inside an irrelevant path must not forge "
                         "a relevant record")
        self.assertEqual(code, 0)

    def test_q2_relevant_path_containing_a_newline_is_classified(self):
        r = self.repo
        name = "assets/stories/traditional/2700/story_2700\nweird.txt"
        r.story_dir(2700)
        r.write(name, "prose")
        r.git("--literal-pathspecs", "add", name)
        code, out = r.run_hook()
        self.assertIn("Running validate_corpus.py", out)
        self.assertEqual(code, 0)

    def test_q3_exotic_filenames_remain_atomic(self):
        r = self.repo
        r.story_dir(2701)
        for name in ("story_2701 space.txt", "story_2701\ttab.txt",
                     "story_2701_*.txt", "story_2701_[a-z].txt",
                     "story_2701_back\\slash.txt"):
            rel = f"assets/stories/traditional/2701/{name}"
            r.write(rel, "prose")
            r.git("--literal-pathspecs", "add", rel)
        r.write("assets/stories/traditional/2702/story_2702_unstaged.txt", "x")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotIn("2702", out, "no glob may reach an unstaged file")
        self.assertEqual(code, 0)

    def test_q4_hook_makes_no_second_git_enumeration(self):
        hook = (REPO_ROOT / "scripts" / "git_hooks" / "pre-commit").read_text()
        code_lines = [ln for ln in hook.splitlines()
                      if not ln.lstrip().startswith("#")]
        self.assertEqual(
            sum("git diff --cached --name-status" in ln for ln in code_lines), 1)
        self.assertFalse(any("git ls-files" in ln for ln in code_lines))
        self.assertFalse(any("tr '\\0'" in ln for ln in code_lines),
                         "the newline-forgeable pipeline must be gone from code")
        self.assertTrue(any("--relevance-check" in ln for ln in code_lines),
                        "relevance must come from the NUL-aware parser")


class KidCounterpartTestCase(unittest.TestCase):
    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def test_y1_counterpart_deleted_by_this_commit_stays_advisory(self):
        r = self.repo
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.write("assets/stories/kid_anchor_registry.json", json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")
        r.git("rm", "-q", "assets/stories/kid_anchor_registry.json")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[DELETION-REVIEW]", out)
        self.assertIn("kid-registry-deleted", out)
        self.assertNotIn("unexpectedly absent", out)
        self.assertEqual(code, 0, "deletion policy stays advisory")

    def test_y2_counterpart_absent_without_a_deletion_blocks(self):
        r = self.repo
        # Baseline never had the registry; only the manifest is committed.
        r.write("assets/stories/kids_manifest.json", json.dumps({"stories": []}))
        r.git("add", "-A"); r.git("commit", "-qm", "manifest only")
        r.write("assets/stories/kids_manifest.json",
                json.dumps({"stories": [], "note": "edited"}))
        r.git("add", "assets/stories/kids_manifest.json")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("required kid input unexpectedly absent", out)
        self.assertIn("does not delete it", out)
        self.assertEqual(code, 1, "an unverifiable kid baseline must block")


class KidDeletionSurvivingInputTestCase(unittest.TestCase):
    """A recognized deletion must never suppress a defect in the survivor.

    The deletion stays ADVISORY (ADR-032 deferred); an independent structural
    problem in the input that remains still blocks.
    """

    MANIFEST = "assets/stories/kids_manifest.json"
    REGISTRY = "assets/stories/kid_anchor_registry.json"

    def setUp(self):
        self.repo = TempGitRepo()
        r = self.repo
        r.write(self.MANIFEST, json.dumps({"stories": []}))
        r.write(self.REGISTRY, json.dumps({}))
        r.git("add", "-A"); r.git("commit", "-qm", "kid seed")

    def tearDown(self):
        self.repo.cleanup()

    def test_kd_a_delete_manifest_valid_registry_is_advisory(self):
        r = self.repo
        r.git("rm", "-q", self.MANIFEST)
        self.assertEqual(r.cached_status(self.MANIFEST), "D")
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 1)
        self.assertIn("kid-manifest-deleted", out)
        self.assertEqual(code, 0)

    def test_kd_b_delete_manifest_executable_registry_blocks(self):
        r = self.repo
        r.git("rm", "-q", self.MANIFEST)
        r.stage_executable(self.REGISTRY, json.dumps({}))
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[DELETION-REVIEW]", out, "deletion advisory still printed")
        self.assertIn("kid-manifest-deleted", out)
        self.assertIn("executable mode 100755", out)
        self.assertNotEqual(code, 0,
                            "an executable surviving input is an independent "
                            "blocking defect the deletion must not suppress")

    def test_kd_c_delete_manifest_malformed_registry_blocks(self):
        r = self.repo
        r.git("rm", "-q", self.MANIFEST)
        r.write(self.REGISTRY, "{ not valid json")
        r.git("add", self.REGISTRY)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[DELETION-REVIEW]", out)
        self.assertIn("invalid JSON", out)
        self.assertNotEqual(code, 0)

    def test_kd_d_delete_manifest_invalid_utf8_registry_blocks(self):
        r = self.repo
        r.git("rm", "-q", self.MANIFEST)
        r.write(self.REGISTRY, b"\xff\xfe{}")
        r.git("add", self.REGISTRY)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("[DELETION-REVIEW]", out)
        self.assertIn("not valid UTF-8", out)
        self.assertNotEqual(code, 0)

    def test_kd_e_delete_registry_executable_manifest_blocks(self):
        """Symmetric: neither input is privileged."""
        r = self.repo
        r.git("rm", "-q", self.REGISTRY)
        r.stage_executable(self.MANIFEST, json.dumps({"stories": []}))
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("kid-registry-deleted", out)
        self.assertIn("executable mode 100755", out)
        self.assertNotEqual(code, 0)

    def test_kd_f_delete_both_is_advisory(self):
        r = self.repo
        r.git("rm", "-q", self.MANIFEST, self.REGISTRY)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 2)
        self.assertEqual(out.count("kid-manifest-deleted"), 1)
        self.assertEqual(out.count("kid-registry-deleted"), 1)
        self.assertEqual(code, 0, "deletion policy remains advisory")

    def test_kd_g_both_surviving_still_uses_validate_kids_exit_code(self):
        """No deletion: the pair runs and its own semantics are preserved."""
        r = self.repo
        r.write(self.MANIFEST, "{ not valid json")
        r.git("add", self.MANIFEST)
        r.write(self.MANIFEST, json.dumps({"stories": []}))  # clean worktree
        code, out = r.run_hook()
        self.assertEqual(code, 2, "validate_kids' own exit code is preserved")


class DeletionReviewMetadataModeTestCase(unittest.TestCase):
    """Classifying a deletion must not parse non-ordinary metadata."""

    def setUp(self):
        self.repo = TempGitRepo()

    def tearDown(self):
        self.repo.cleanup()

    def _seed(self, sid):
        r = self.repo
        d = f"assets/stories/traditional/{sid}"
        p = f"{d}/story_{sid}_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.write_meta(sid, files={"short_kjv": {
            "storyText": f"story_{sid}_traditional_kjv_short.txt"}})
        r.git("add", "-A"); r.git("commit", "-qm", f"seed {sid}")
        return d, p

    def test_dm_a_deleted_story_with_executable_metadata_blocks(self):
        r = self.repo
        d, p = self._seed(2800)
        meta = f"{d}/meta_2800.json"
        r.stage_executable(meta, (r.root / meta).read_text())
        r.git("rm", "-q", p)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 1,
                         "the story deletion is still classified")
        self.assertIn("executable mode 100755", out)
        self.assertIn("not ordinary data", out)
        self.assertNotIn("declared-story-deleted", out,
                         "metadata must not be parsed to classify the deletion")
        self.assertNotEqual(code, 0)

    def test_dm_b_deleted_story_with_symlink_metadata_blocks(self):
        r = self.repo
        d, p = self._seed(2801)
        meta = f"{d}/meta_2801.json"
        r.stage_symlink_over(meta, "/etc/passwd")
        r.git("rm", "-q", p)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertIn("symlink", out)
        self.assertNotIn("root:", out, "the target must never be followed")
        self.assertNotEqual(code, 0)

    def test_dm_c_deleted_story_with_ordinary_metadata_is_unchanged(self):
        r = self.repo
        d, p = self._seed(2802)
        r.git("rm", "-q", p)
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertEqual(out.count("[DELETION-REVIEW]"), 1)
        self.assertIn("declared-story-deleted", out)
        self.assertNotIn("[INFRASTRUCTURE-FAILURE]", out)
        self.assertEqual(code, 0, "the deletion alone remains advisory")

    def test_dm_d_preexisting_executable_metadata_cannot_exit_zero(self):
        """The metadata is NOT staged; only the story deletion is."""
        r = self.repo
        d = "assets/stories/traditional/2803"
        p = f"{d}/story_2803_traditional_kjv_short.txt"
        r.write(p, canonical_text("1 Samuel 24"))
        r.story_dir(2803)
        meta_body = json.dumps(r.write_meta(2803, files={"short_kjv": {
            "storyText": "story_2803_traditional_kjv_short.txt"}}))
        r.stage_executable(f"{d}/meta_2803.json", meta_body)
        r.git("add", "-A"); r.git("commit", "-qm", "seed with exec meta")
        r.git("rm", "-q", p)
        # Only the story deletion is staged; the executable meta is pre-existing.
        self.assertIsNone(r.cached_status(f"{d}/meta_2803.json"))
        code, out = r.run_hook()
        assert_hook_actually_ran(self, out)
        self.assertNotEqual(code, 0,
                            "a pre-existing non-ordinary metadata blob must not "
                            "pass silently just because it was not staged")
