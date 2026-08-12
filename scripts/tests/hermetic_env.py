#!/usr/bin/env python3
"""Hermetic subprocess environments for shell-script tests.

WHY THIS EXISTS
---------------
scripts/upload_r2_catalog.sh publishes the production story catalog to R2.
Its tests drive the REAL script against a stub `wrangler`. If the stub can
ever be bypassed — because PATH still contains /usr/local/bin,
/opt/homebrew/bin, an npm/nvm/volta shim directory, or any other place a
genuinely installed and AUTHENTICATED wrangler lives — a test could reach
the production PUT path with the owner's real credentials.

The defence here is structural, not a filter:

  PATH contains EXACTLY ONE directory, and that directory contains ONLY
  the symlinks this module put there.

There is no allowlist of "safe" system directories to get wrong, and no
ordering assumption that a later PATH entry cannot win. `wrangler` is
resolvable if and only if a test explicitly placed a stub in the scenario
bin. Nothing is inherited from the ambient environment: the child gets a
freshly built env dict, so CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID,
WRANGLER_* and friends cannot leak in, and HOME points at an empty
scenario-owned directory so ~/.wrangler and ~/.config credentials are not
readable either.

System tools are exposed by NAME, one symlink at a time. Where the real
binary lives is irrelevant to hermeticity — a symlink called `jq` cannot
resolve to wrangler — so tools may be resolved from anywhere on the host,
while the *directory* they live in is never exposed.
"""

from __future__ import annotations

import os
import pathlib
import shutil
import sys

# Resolved first, so the ordinary system tool is preferred over any
# shadowing copy a developer happens to have installed.
_PREFERRED_TOOL_DIRS = ("/usr/bin", "/bin", "/usr/sbin", "/sbin")

# The single name that must NEVER be auto-resolved from the host. Tests
# place their own stub; anything else is a bug in the harness.
FORBIDDEN_AUTO_TOOLS = frozenset({"wrangler", "npx", "npm", "node"})

# Tools scripts/upload_r2_catalog.sh actually invokes (`command`, `read`
# and `echo` are bash builtins; the #! line resolves bash absolutely).
PUBLISHER_TOOLS = (
    "python3", "git", "sed", "grep", "cmp", "cut", "wc", "du", "mkdir",
    "mktemp", "cp", "rm", "tr", "chmod", "cat", "tail", "head",
    "dirname", "basename",
)

# Tools server/tools/backfill_story_length.sh actually invokes. python3 is
# required because the writer now runs the full catalog validator against
# the staged manifest before any replacement.
BACKFILL_TOOLS = (
    "python3", "jq", "mkdir", "mktemp", "stat", "chmod", "cp", "mv", "rm",
    "wc", "seq", "tr", "cat", "dirname", "basename",
)


class ToolUnavailable(RuntimeError):
    """A required system tool could not be resolved on this host."""


def _resolve(tool: str) -> str | None:
    if tool in FORBIDDEN_AUTO_TOOLS:
        raise AssertionError(
            f"{tool!r} must never be auto-resolved from the host — tests "
            f"must install their own stub")
    if tool == "python3":
        # Pin the exact interpreter running the tests rather than whatever
        # happens to be first on the host PATH.
        return sys.executable
    for directory in _PREFERRED_TOOL_DIRS:
        candidate = pathlib.Path(directory) / tool
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return shutil.which(tool)


def make_bin(bin_dir: pathlib.Path, tools) -> pathlib.Path:
    """Populate `bin_dir` with symlinks to the named tools and nothing else.

    The caller owns the directory; anything already in it (e.g. a stub
    wrangler) is left alone.
    """
    bin_dir.mkdir(parents=True, exist_ok=True)
    missing = []
    for tool in tools:
        target = _resolve(tool)
        if target is None:
            missing.append(tool)
            continue
        link = bin_dir / tool
        if link.is_symlink() or link.exists():
            continue
        link.symlink_to(target)
    if missing:
        raise ToolUnavailable(
            f"required system tools not found on this host: {missing}")
    return bin_dir


def hermetic_env(bin_dir: pathlib.Path, home: pathlib.Path,
                 tmpdir: pathlib.Path, **extra: str) -> dict:
    """A from-scratch environment whose PATH is exactly `bin_dir`.

    Nothing is inherited from os.environ — no cloud credentials, no shim
    directories, no wrangler configuration.
    """
    home.mkdir(parents=True, exist_ok=True)
    tmpdir.mkdir(parents=True, exist_ok=True)
    env = {
        "PATH": str(bin_dir),
        "HOME": str(home),
        "TMPDIR": str(tmpdir),
        "LANG": "C",
        "LC_ALL": "C",
    }
    env.update(extra)
    return env


def assert_path_is_hermetic(testcase, env: dict, bin_dir: pathlib.Path):
    """PATH must be exactly the scenario bin — one entry, no extras."""
    entries = env["PATH"].split(os.pathsep)
    testcase.assertEqual(
        entries, [str(bin_dir)],
        f"PATH must contain exactly the scenario bin, got {entries!r}")
    # Belt and braces: name the directories that historically leaked in.
    for fragment in ("/usr/local", "/opt/homebrew", "/opt/local",
                     "node_modules", ".npm", ".nvm", ".volta", ".yarn"):
        testcase.assertNotIn(fragment, env["PATH"])


def assert_wrangler_is_stub(testcase, env: dict, stub: pathlib.Path):
    """The `wrangler` that command resolution finds must BE the stub."""
    resolved = shutil.which("wrangler", path=env["PATH"])
    testcase.assertIsNotNone(
        resolved, "no wrangler resolvable — the stub was not installed")
    testcase.assertEqual(
        pathlib.Path(resolved).resolve(), stub.resolve(),
        "the resolved wrangler is NOT the test stub — a real wrangler "
        "could be reached")


def assert_no_wrangler_resolvable(testcase, env: dict):
    """For 'missing wrangler' tests: nothing named wrangler may resolve."""
    resolved = shutil.which("wrangler", path=env["PATH"])
    testcase.assertIsNone(
        resolved,
        f"a wrangler is still resolvable at {resolved!r} — the 'missing "
        f"wrangler' scenario would exercise a real binary")


def assert_no_cloud_credentials(testcase, env: dict):
    """No credential-bearing variable may reach the child process."""
    for key in env:
        upper = key.upper()
        testcase.assertFalse(
            upper.startswith(("CLOUDFLARE", "CF_", "WRANGLER", "AWS_", "R2_")),
            f"credential-shaped variable {key} must not be passed to a "
            f"publisher subprocess")
