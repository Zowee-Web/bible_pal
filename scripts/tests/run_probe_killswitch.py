"""Run the offline R2 CAS probe suite under a process-wide network kill
switch, with a mandatory positive control.

Phase 0 (import time): every representative network mechanism is replaced
with a raiser BEFORE anything else is imported. The exception derives from
BaseException so no ``except Exception`` in code under test can swallow it.

Phase 1 (positive control): each patched mechanism is exercised directly.
If ANY of them completes instead of raising, the switch is vacuous — the
runner prints which mechanism escaped and exits non-zero WITHOUT running
the suite, so a green suite result can never be mistaken for a proof of
network isolation.

Phase 2: only after the control passes, the repository root (derived from
this file's own location — no reliance on CWD or PYTHONPATH) is placed on
sys.path and the full probe suite runs in-process, so the suite module is
imported with the switch already live.

CI invokes this as a plain file:

    python3 scripts/tests/run_probe_killswitch.py
"""

import http.client
import pathlib
import socket
import ssl
import sys
import unittest


class NetworkAttempted(BaseException):
    """Raised by every neutered network entry point."""


def _boom(*args, **kwargs):
    raise NetworkAttempted("network was attempted under the kill switch")


class _DeadSocket:
    def __init__(self, *args, **kwargs):
        _boom()


# ── Phase 0: install the switch before anything else happens ─────────────
socket.socket = _DeadSocket
socket.create_connection = _boom
socket.getaddrinfo = _boom
socket.gethostbyname = _boom
socket.gethostbyname_ex = _boom
socket.getnameinfo = _boom
socket.socketpair = _boom
ssl.SSLContext.wrap_socket = _boom
ssl.create_default_context = _boom
http.client.HTTPSConnection.connect = _boom
http.client.HTTPConnection.connect = _boom


def _positive_control() -> None:
    """Prove the switch actually blocks each representative mechanism."""
    checks = (
        ("socket.socket", lambda: socket.socket()),
        ("socket.create_connection",
         lambda: socket.create_connection(("127.0.0.1", 9))),
        ("socket.getaddrinfo", lambda: socket.getaddrinfo("localhost", 80)),
        ("socket.gethostbyname", lambda: socket.gethostbyname("localhost")),
        ("ssl.create_default_context",
         lambda: ssl.create_default_context()),
        ("http.client.HTTPSConnection.connect",
         lambda: http.client.HTTPSConnection("localhost").connect()),
        ("http.client.HTTPConnection.connect",
         lambda: http.client.HTTPConnection("localhost").connect()),
    )
    vacuous = []
    for name, attempt in checks:
        try:
            attempt()
        except NetworkAttempted:
            print(f"kill-switch control: {name}: BLOCKED")
        except BaseException as exc:  # noqa: BLE001 — must not be reached
            vacuous.append(f"{name} raised {type(exc).__name__}, "
                           "not NetworkAttempted")
        else:
            vacuous.append(f"{name} completed without raising")
    if vacuous:
        for line in vacuous:
            print(f"kill-switch control FAILED: {line}", file=sys.stderr)
        print("kill switch is vacuous — refusing to run the suite",
              file=sys.stderr)
        sys.exit(1)
    print("kill-switch positive control: all mechanisms blocked")


def main() -> None:
    _positive_control()
    # Repo root = two levels above this file (scripts/tests/ -> repo).
    repo_root = pathlib.Path(__file__).resolve().parent.parent.parent
    sys.path.insert(0, str(repo_root))
    # The suite module is imported HERE, after the switch went live.
    unittest.main(
        module=None,
        argv=["run_probe_killswitch", "-v",
              "scripts.tests.test_probe_r2_cas"],
        exit=True)


if __name__ == "__main__":
    main()
