#!/usr/bin/env python3
"""Tests for scripts/step4a_bible_order_backfill.py --ids scoping.

Every test builds a synthetic manifest + meta tree inside a
tempfile.TemporaryDirectory and patches the module's MANIFEST_PATH /
TRADITIONAL_DIR at it. The real corpus is never read or written.

Run:
    python3 -m unittest scripts.tests.test_step4a_bible_order_backfill -v
"""

import io
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import step4a_bible_order_backfill as backfill  # noqa: E402


def _entry(sid, ref, idx=None, lane=""):
    """One synthetic manifest entry for a story id."""
    suffix = f"_{lane}" if lane else ""
    return {
        "storyId": f"story_{sid}_hurting_short_traditional{suffix}",
        "textFilePath": f"traditional/{sid}/story_{sid}_traditional_web_short.txt",
        "bibleSourceRef": ref,
        "bibleOrderIndex": idx,
    }


class ScopedBackfillTestCase(unittest.TestCase):
    """Builds a synthetic corpus: 1565 (Luke, unindexed), 801 + 802 (Luke/John,
    unindexed), and 900 (Luke, already indexed -> supplies the per-book max)."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self._tmp.name)
        self.trad = root / "traditional"
        self.manifest_path = root / "manifest.json"

        self.parables = [
            _entry("900", "Luke 5:1-11", idx=25045),          # curated, indexed
            _entry("1565", "Luke 22:54-62"),                  # target
            _entry("1565", "Luke 22:54-62", lane="kjv"),      # target, 2nd lane
            _entry("801", "Luke 15:11-32"),                   # unrelated
            _entry("802", "John 3:1-21"),                     # unrelated
        ]
        self._write_manifest()

        for sid in ("900", "1565", "801", "802"):
            d = self.trad / sid
            d.mkdir(parents=True)
            meta = {"storyId": int(sid), "title": f"Story {sid}"}
            if sid == "900":
                meta["bibleOrderIndex"] = 25045
            (d / f"meta_{sid}.json").write_text(json.dumps(meta, indent=2) + "\n")

        self.patches = [
            mock.patch.object(backfill, "MANIFEST_PATH", self.manifest_path),
            mock.patch.object(backfill, "TRADITIONAL_DIR", self.trad),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self._tmp.cleanup()

    # -- helpers ---------------------------------------------------------

    def _write_manifest(self):
        self.manifest_path.write_text(
            json.dumps({"parables": self.parables}, indent=2) + "\n"
        )

    def run_cli(self, *argv):
        """Run main() with patched sys.argv; return (exit_code, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", ["step4a", *argv]):
            with redirect_stdout(out), redirect_stderr(err):
                code = backfill.main()
        return code, out.getvalue(), err.getvalue()

    def manifest_now(self):
        return json.loads(self.manifest_path.read_text())["parables"]

    def meta_now(self, sid):
        return json.loads((self.trad / sid / f"meta_{sid}.json").read_text())

    def index_of(self, sid):
        vals = [
            p["bibleOrderIndex"]
            for p in self.manifest_now()
            if p["storyId"].startswith(f"story_{sid}_")
        ]
        return vals

    # -- unscoped compatibility ------------------------------------------

    def test_unscoped_dry_run_writes_nothing(self):
        before = self.manifest_path.read_text()
        code, out, _ = self.run_cli()
        self.assertEqual(code, 0)
        self.assertIn("DRY-RUN", out)
        self.assertEqual(self.manifest_path.read_text(), before)

    def test_unscoped_write_backfills_every_eligible_sid(self):
        code, _, _ = self.run_cli("--write")
        self.assertEqual(code, 0)
        for sid in ("1565", "801", "802"):
            self.assertTrue(
                all(v is not None for v in self.index_of(sid)),
                f"sid {sid} should have been backfilled unscoped",
            )

    # -- scoped ----------------------------------------------------------

    def test_scoped_dry_run_writes_nothing(self):
        before = self.manifest_path.read_text()
        code, out, _ = self.run_cli("--ids", "1565")
        self.assertEqual(code, 0)
        self.assertIn("Scoped to --ids: 1 sid(s) in scope", out)
        self.assertIn("DRY-RUN", out)
        self.assertEqual(self.manifest_path.read_text(), before)

    def test_scoped_write_changes_only_requested_story(self):
        before_801 = self.meta_now("801")
        before_802 = self.meta_now("802")

        code, _, _ = self.run_cli("--ids", "1565", "--write")
        self.assertEqual(code, 0)

        # both 1565 lanes updated, to the same value
        vals = self.index_of("1565")
        self.assertEqual(len(vals), 2)
        self.assertTrue(all(v is not None for v in vals))
        self.assertEqual(len(set(vals)), 1)
        self.assertEqual(self.meta_now("1565")["bibleOrderIndex"], vals[0])

        # unrelated stories untouched, in manifest and on disk
        self.assertEqual(self.index_of("801"), [None])
        self.assertEqual(self.index_of("802"), [None])
        self.assertEqual(self.meta_now("801"), before_801)
        self.assertEqual(self.meta_now("802"), before_802)

    def test_scoped_index_uses_full_manifest_book_max(self):
        """Per-book max must come from the whole manifest (900 -> 25045),
        not just the scoped subset."""
        self.run_cli("--ids", "1565", "--write")
        # base = 25045 + 1000; index = base + 22*1000 + 54
        self.assertEqual(self.index_of("1565")[0], 25045 + 1000 + 22 * 1000 + 54)

    # -- failure modes ---------------------------------------------------

    def test_malformed_ids_exit_2_without_writing(self):
        before = self.manifest_path.read_text()
        for bad in ("15a6", "1565,abc", "-1"):
            with self.subTest(bad=bad):
                code, _, err = self.run_cli("--ids", bad, "--write")
                self.assertEqual(code, 2)
                self.assertIn("malformed story id", err)
                self.assertEqual(self.manifest_path.read_text(), before)

    def test_empty_ids_exit_2_without_writing(self):
        before = self.manifest_path.read_text()
        code, _, err = self.run_cli("--ids", " , ", "--write")
        self.assertEqual(code, 2)
        self.assertIn("no ids parsed", err)
        self.assertEqual(self.manifest_path.read_text(), before)

    def test_unknown_ids_exit_2_without_writing(self):
        before = self.manifest_path.read_text()
        code, _, err = self.run_cli("--ids", "9999", "--write")
        self.assertEqual(code, 2)
        self.assertIn("unknown story id", err)
        self.assertIn("9999", err)
        self.assertEqual(self.manifest_path.read_text(), before)

    # -- no-op and idempotency -------------------------------------------

    def test_already_indexed_id_is_clean_noop(self):
        before = self.manifest_path.read_text()
        code, out, _ = self.run_cli("--ids", "900", "--write")
        self.assertEqual(code, 0)
        self.assertIn("No-op", out)
        self.assertIn("900", out)
        self.assertEqual(self.manifest_path.read_text(), before)

    def test_scoped_write_is_idempotent(self):
        self.run_cli("--ids", "1565", "--write")
        after_first = self.manifest_path.read_text()
        first_meta = self.meta_now("1565")

        code, out, _ = self.run_cli("--ids", "1565", "--write")
        self.assertEqual(code, 0)
        self.assertIn("No-op", out)
        self.assertEqual(self.manifest_path.read_text(), after_first)
        self.assertEqual(self.meta_now("1565"), first_meta)


if __name__ == "__main__":
    unittest.main()
