#!/usr/bin/env python3
"""Tests for scripts/backfill_existing_audio_paths.py.

Every test builds a synthetic manifest + asset tree inside a
tempfile.TemporaryDirectory and patches the module's MANIFEST_PATH /
ASSETS_DIR / REPO_ROOT at it. The real corpus is never read or written.
git and ffmpeg are stubbed so the suite stays hermetic and fast.

Run:
    python3 -m unittest scripts.tests.test_backfill_existing_audio_paths -v
"""

import io
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import backfill_existing_audio_paths as backfill  # noqa: E402


def entry(sid, length, style="WEB", kid_text=False, audio="", reflection=""):
    """One synthetic manifest entry."""
    lane = "kjv" if style == "KJV" else "web"
    suffix = "_kid" if kid_text else ""
    return {
        "storyId": f"story_{sid}_joyful_{length}{'_kid' if kid_text else ''}_traditional"
                   + ("_kjv" if style == "KJV" else ""),
        "title": f"Story {sid}",
        "storytellingMode": "traditional",
        "languageStyle": style,
        "storyLength": length,
        "textFilePath": f"traditional/{sid}/story_{sid}_traditional_{lane}_{length}{suffix}.txt",
        "audioFilePath": audio,
        "reflectionAudioPath": reflection,
        "narratorVoiceKey": "VOICE_ARCHER",
    }


class BackfillTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.assets = self.root / "assets" / "stories"
        self.assets.mkdir(parents=True)
        self.manifest_path = self.assets / "manifest.json"

        patcher = mock.patch.multiple(
            backfill,
            REPO_ROOT=self.root,
            ASSETS_DIR=self.assets,
            MANIFEST_PATH=self.manifest_path,
        )
        patcher.start()
        self.addCleanup(patcher.stop)

        # every file we create is "tracked" and decodes, unless a test says otherwise
        self._tracked = set()
        self._undecodable = set()
        t = mock.patch.object(backfill, "tracked_files", lambda root: set(self._tracked))
        t.start(); self.addCleanup(t.stop)
        d = mock.patch.object(backfill, "decodes",
                              lambda p: pathlib.Path(p).name not in self._undecodable)
        d.start(); self.addCleanup(d.stop)
        self.addCleanup(self.tmp.cleanup)

    # -- helpers ---------------------------------------------------------
    def write_manifest(self, parables):
        self.manifest_path.write_text(
            json.dumps({"version": 2, "parables": parables}, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8")

    def make_audio(self, sid, name, size=2048, tracked=True):
        d = self.assets / "traditional" / sid
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_bytes(b"\0" * size)
        if tracked:
            self._tracked.add(f"assets/stories/traditional/{sid}/{name}")

    def run_tool(self, argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = backfill.main(argv)
        return code, buf.getvalue()

    def manifest(self):
        return json.loads(self.manifest_path.read_text(encoding="utf-8"))

    # -- tests -----------------------------------------------------------
    def test_web_and_kjv_relink_across_all_lengths(self):
        parables = [entry("1019", ln, style)
                    for ln in ("short", "full", "long")
                    for style in ("WEB", "KJV")]
        self.write_manifest(parables)
        for ln in ("short", "full", "long"):
            self.make_audio("1019", f"audio_1019_story_{ln}.mp3")
            self.make_audio("1019", f"audio_1019_story_kjv_{ln}.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")
        self.make_audio("1019", "audio_1019_reflection_kjv.mp3")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 0)
        got = self.manifest()["parables"]
        self.assertEqual(got[0]["audioFilePath"], "traditional/1019/audio_1019_story_short.mp3")
        self.assertEqual(got[1]["audioFilePath"], "traditional/1019/audio_1019_story_kjv_short.mp3")
        self.assertEqual(got[2]["audioFilePath"], "traditional/1019/audio_1019_story_full.mp3")
        self.assertEqual(got[5]["audioFilePath"], "traditional/1019/audio_1019_story_kjv_long.mp3")
        # reflection convention: per lane, not per length
        self.assertEqual(got[0]["reflectionAudioPath"], "traditional/1019/audio_1019_reflection.mp3")
        self.assertEqual(got[1]["reflectionAudioPath"], "traditional/1019/audio_1019_reflection_kjv.mp3")
        self.assertIn("fields to populate       : 12", out)

    def test_dry_run_does_not_touch_the_manifest(self):
        self.write_manifest([entry("1019", "full")])
        self.make_audio("1019", "audio_1019_story_full.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")
        before = self.manifest_path.read_text(encoding="utf-8")

        code, out = self.run_tool([])
        self.assertEqual(code, 0)
        self.assertIn("DRY RUN", out)
        self.assertEqual(self.manifest_path.read_text(encoding="utf-8"), before)

    def test_never_overwrites_a_populated_path(self):
        """An entry with story audio already linked is left entirely alone."""
        existing = "traditional/1019/SOMETHING_ELSE.mp3"
        self.write_manifest([entry("1019", "full", audio=existing)])
        self.make_audio("1019", "audio_1019_story_full.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")
        before = self.manifest()["parables"][0]

        code, _ = self.run_tool(["--write"])
        self.assertEqual(code, 0)
        self.assertEqual(self.manifest()["parables"][0], before)

    def test_scope_is_blank_audio_path_only(self):
        """A blank reflection path alone does not make an entry eligible."""
        linked = entry("1019", "full", audio="traditional/1019/audio_1019_story_full.mp3")
        self.write_manifest([linked, entry("1032", "full")])
        for sid in ("1019", "1032"):
            self.make_audio(sid, f"audio_{sid}_story_full.mp3")
            self.make_audio(sid, f"audio_{sid}_reflection.mp3")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 0)
        self.assertIn("entries to relink        : 1", out)
        got = self.manifest()["parables"]
        self.assertEqual(got[0]["reflectionAudioPath"], "")        # out of scope, untouched
        self.assertEqual(got[1]["reflectionAudioPath"],
                         "traditional/1032/audio_1032_reflection.mp3")

    def test_populates_reflection_alongside_story_when_both_blank(self):
        self.write_manifest([entry("1019", "full")])
        self.make_audio("1019", "audio_1019_story_full.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 0)
        got = self.manifest()["parables"][0]
        self.assertEqual(got["audioFilePath"], "traditional/1019/audio_1019_story_full.mp3")
        self.assertEqual(got["reflectionAudioPath"], "traditional/1019/audio_1019_reflection.mp3")
        self.assertIn("fields to populate       : 2", out)

    def test_idempotent_second_write_changes_nothing(self):
        self.write_manifest([entry("1019", "full")])
        self.make_audio("1019", "audio_1019_story_full.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")

        self.run_tool(["--write"])
        after_first = self.manifest_path.read_text(encoding="utf-8")
        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 0)
        self.assertIn("No-op", out)
        self.assertEqual(self.manifest_path.read_text(encoding="utf-8"), after_first)

    def test_missing_file_is_a_blocking_error_and_writes_nothing(self):
        self.write_manifest([entry("1019", "full")])
        self.make_audio("1019", "audio_1019_reflection.mp3")   # story audio absent
        before = self.manifest_path.read_text(encoding="utf-8")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 1)
        self.assertIn("missing:", out)
        self.assertEqual(self.manifest_path.read_text(encoding="utf-8"), before)

    def test_undecodable_file_is_a_blocking_error(self):
        self.write_manifest([entry("1019", "full")])
        self.make_audio("1019", "audio_1019_story_full.mp3")
        self.make_audio("1019", "audio_1019_reflection.mp3")
        self._undecodable.add("audio_1019_story_full.mp3")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 1)
        self.assertIn("undecodable:", out)

    def test_untracked_and_empty_files_are_blocking_errors(self):
        self.write_manifest([entry("1019", "full"), entry("1020", "full")])
        self.make_audio("1019", "audio_1019_story_full.mp3", tracked=False)
        self.make_audio("1019", "audio_1019_reflection.mp3")
        self.make_audio("1020", "audio_1020_story_full.mp3", size=0)
        self.make_audio("1020", "audio_1020_reflection.mp3")

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 1)
        self.assertIn("untracked:", out)
        self.assertIn("empty:", out)

    def test_kid_text_with_adult_audio_is_skipped_and_left_unchanged(self):
        parables = [entry("1091", "full", kid_text=True), entry("1091", "short")]
        self.write_manifest(parables)
        self.make_audio("1091", "audio_1091_story_full.mp3")     # adult narration only
        self.make_audio("1091", "audio_1091_story_short.mp3")
        self.make_audio("1091", "audio_1091_reflection.mp3")
        before = self.manifest()["parables"][0]

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 0)                                # a skip is not an error
        self.assertIn(backfill.SKIP_KID, out)
        after = self.manifest()["parables"][0]
        self.assertEqual(after, before)                          # byte-for-byte unchanged
        self.assertEqual(after["audioFilePath"], "")
        self.assertEqual(after["reflectionAudioPath"], "")
        # the sibling non-kid entry was still repaired
        self.assertEqual(self.manifest()["parables"][1]["audioFilePath"],
                         "traditional/1091/audio_1091_story_short.mp3")

    def test_kid_text_is_skipped_even_when_kid_named_audio_exists(self):
        """The guard is unconditional: no filename on disk can bypass it.

        This tool only knows the adult-style path convention, so "detecting"
        kid narration could not change which file it links — it would still
        write the adult path. Speculative kid-named MP3s are laid down here in
        several plausible spellings to prove none of them opens a bypass.
        """
        self.write_manifest([entry("1091", "full", kid_text=True)])
        # adult narration, which the tool would otherwise link
        self.make_audio("1091", "audio_1091_story_full.mp3")
        self.make_audio("1091", "audio_1091_reflection.mp3")
        # speculative kid-named files in every naming a future convention might use
        for name in ("audio_1091_story_full_kid.mp3",
                     "audio_1091_story_kid_full.mp3",
                     "audio_1091_kid_story_full.mp3",
                     "audio_1091_reflection_kid.mp3",
                     "audio_1091_kid_reflection.mp3"):
            self.make_audio("1091", name)
        before = self.manifest()["parables"][0]

        code, out = self.run_tool(["--write"])

        self.assertEqual(code, 0)                       # a skip is not an error
        self.assertIn(backfill.SKIP_KID, out)
        self.assertIn("SKIPPED_KID_TEXT_AUDIO_MISMATCH: 1", out)
        after = self.manifest()["parables"][0]
        self.assertEqual(after["audioFilePath"], "")            # unchanged
        self.assertEqual(after["reflectionAudioPath"], "")      # unchanged
        self.assertEqual(after, before)                         # entry untouched entirely
        self.assertIn("entries to relink        : 0", out)
        # the module exposes no kid-audio discovery surface at all
        self.assertFalse(hasattr(backfill, "kid_audio_exists"))
        self.assertFalse(hasattr(backfill, "KID_AUDIO_PATTERNS"))

    def test_ids_filter_limits_scope(self):
        self.write_manifest([entry("1019", "full"), entry("1032", "full")])
        for sid in ("1019", "1032"):
            self.make_audio(sid, f"audio_{sid}_story_full.mp3")
            self.make_audio(sid, f"audio_{sid}_reflection.mp3")

        code, _ = self.run_tool(["--write", "--ids", "1019"])
        self.assertEqual(code, 0)
        got = self.manifest()["parables"]
        self.assertNotEqual(got[0]["audioFilePath"], "")
        self.assertEqual(got[1]["audioFilePath"], "")

    def test_entry_order_and_unrelated_fields_are_preserved(self):
        parables = [entry("1019", "full"), entry("1032", "short"), entry("1045", "long")]
        self.write_manifest(parables)
        for sid, ln in (("1019", "full"), ("1032", "short"), ("1045", "long")):
            self.make_audio(sid, f"audio_{sid}_story_{ln}.mp3")
            self.make_audio(sid, f"audio_{sid}_reflection.mp3")

        self.run_tool(["--write"])
        got = self.manifest()["parables"]
        self.assertEqual([p["storyId"] for p in got], [p["storyId"] for p in parables])
        for before, after in zip(parables, got):
            for key in ("title", "storytellingMode", "languageStyle", "storyLength",
                        "textFilePath", "narratorVoiceKey"):
                self.assertEqual(after[key], before[key])
            self.assertEqual(list(after.keys()), list(before.keys()))   # key order intact

    def test_ambiguous_variant_is_a_blocking_error(self):
        bad = entry("1019", "full")
        bad["storyLength"] = "medium"          # not a real bucket
        self.write_manifest([bad])

        code, out = self.run_tool(["--write"])
        self.assertEqual(code, 1)
        self.assertIn("ambiguous variant", out)


if __name__ == "__main__":
    unittest.main()
