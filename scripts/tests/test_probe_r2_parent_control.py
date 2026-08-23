#!/usr/bin/env python3
"""Offline tests for the R2 parent-credential control harness.

SYNTHETIC CREDENTIALS ONLY. No test reads the real credential file, and no
test opens a socket: the network-facing tests install a process-wide kill
switch and assert the harness never reaches it.
"""

import hashlib
import json
import os
import socket
import ssl
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import probe_r2_parent_control as pc          # noqa: E402
import probe_r2_cas as probe                  # noqa: E402

ACCOUNT = "b5509d046d2b4e7368b517dd3831670e"
FAKE_AK = "0123456789abcdef0123456789abcdef"
FAKE_SEC = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
AMZ_DATE = "20260822T000000Z"
GOOD_ENV = f"R2_ACCESS_KEY_ID={FAKE_AK}\nR2_SECRET_ACCESS_KEY={FAKE_SEC}\n"
CONFIRM = "PARENT-CREDENTIAL-DISPOSABLE-PUT-ONLY"
REAL_CREDENTIAL_PATH = os.path.expanduser(
    "~/.config/bible-pal/r2-disposable-probe.env")


def synthetic_credential():
    return pc.ParentCredential(access_key_id=FAKE_AK,
                               secret_access_key=FAKE_SEC)


#: The REAL live root, captured ONCE at import before any test
#: redirects HOME. Everything below compares against this, so a test that
#: redirects HOME cannot accidentally re-point the guard at its sandbox.
REAL_LIVE_ROOT = os.path.realpath(pc.canonical_evidence_root())

#: Every attempt to construct evidence at the REAL live root, recorded the
#: INSTANT it happens. A teardown-only existence check was too weak: a
#: test could write and then delete, and the guard would see nothing.
LIVE_ROOT_ATTEMPTS = []

_REAL_OPEN_LIVE_ROOT = pc.open_live_evidence_root


def _guarded_open_live_evidence_root():
    """Refuse — and RECORD — any attempt to open the real live root."""
    if os.path.realpath(pc.canonical_evidence_root()) == REAL_LIVE_ROOT:
        LIVE_ROOT_ATTEMPTS.append(REAL_LIVE_ROOT)
        raise AssertionError(
            "a test tried to open the REAL live parent-control evidence "
            f"root {REAL_LIVE_ROOT!r}; redirect HOME to a sandbox instead")
    return _REAL_OPEN_LIVE_ROOT()


def setUpModule():
    # Installed for the WHOLE suite: with HOME redirected the wrapper
    # delegates, and without it the wrapper refuses and records.
    pc.open_live_evidence_root = _guarded_open_live_evidence_root


def tearDownModule():
    pc.open_live_evidence_root = _REAL_OPEN_LIVE_ROOT
    if LIVE_ROOT_ATTEMPTS:
        raise AssertionError(
            f"{len(LIVE_ROOT_ATTEMPTS)} test(s) attempted to use the REAL "
            f"live evidence root {REAL_LIVE_ROOT!r}")
    if os.path.exists(REAL_LIVE_ROOT):
        raise AssertionError(
            f"the REAL live evidence root {REAL_LIVE_ROOT!r} exists after "
            "the offline suite; it must remain absent")


class SandboxHome:
    """Redirect HOME so `canonical_evidence_root()` resolves inside a
    temporary tree. This is what lets the tests drive the REAL
    `run_control` end to end — exercising the true order — without the
    canonical-root invariant being softened for the live path."""

    def __init__(self, home):
        self.home = home

    def __enter__(self):
        self._saved = os.environ.get("HOME")
        os.environ["HOME"] = self.home
        return self

    def __exit__(self, *exc):
        if self._saved is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self._saved
        return False


def sandbox_run(tmp, conn, *, factory=None, gates_kwargs=None, **kw):
    """Drive the REAL `run_control` with HOME pointed at `tmp`."""
    home = os.path.join(tmp, "home")
    os.makedirs(home, exist_ok=True)
    with SandboxHome(home):
        g = gates(tmp, root=pc.canonical_evidence_root(),
                  **(gates_kwargs or {}))
        return pc.run_control(gates=g,
                              connection_factory=factory or factory_for(conn),
                              **kw)


def sandbox_evidence(tmp, run_id):
    """A ParentControlEvidence rooted in a sandbox HOME."""
    home = os.path.join(tmp, "home")
    os.makedirs(home, exist_ok=True)
    with SandboxHome(home):
        return pc.ParentControlEvidence.at_live_root(run_id)


_ENV_SEQ = [0]


def write_env(directory, text=GOOD_ENV, mode=0o600):
    """A fresh file per call: chmod 0o400/0o200 would otherwise make the
    next rewrite of a shared path fail with PermissionError."""
    _ENV_SEQ[0] += 1
    path = os.path.join(directory, f"parent-{_ENV_SEQ[0]}.env")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(path, mode)
    return path


class NoNetwork:
    """Process-wide kill switch. Any socket/DNS/TLS attempt records itself
    and raises, so a test can prove the harness never tried."""

    def __init__(self):
        self.attempts = []

    def __enter__(self):
        self._saved = {
            "socket": socket.socket,
            "create_connection": socket.create_connection,
            "getaddrinfo": socket.getaddrinfo,
            "gethostbyname": socket.gethostbyname,
            "ssl_ctx": ssl.create_default_context,
            "wrap": ssl.SSLContext.wrap_socket,
        }

        def boom(name):
            def f(*a, **k):
                self.attempts.append(name)
                raise AssertionError(f"network blocked: {name}")
            return f

        socket.socket = boom("socket.socket")
        socket.create_connection = boom("socket.create_connection")
        socket.getaddrinfo = boom("socket.getaddrinfo")
        socket.gethostbyname = boom("socket.gethostbyname")
        ssl.create_default_context = boom("ssl.create_default_context")
        ssl.SSLContext.wrap_socket = boom("ssl.wrap_socket")
        return self

    def __exit__(self, *exc):
        socket.socket = self._saved["socket"]
        socket.create_connection = self._saved["create_connection"]
        socket.getaddrinfo = self._saved["getaddrinfo"]
        socket.gethostbyname = self._saved["gethostbyname"]
        ssl.create_default_context = self._saved["ssl_ctx"]
        ssl.SSLContext.wrap_socket = self._saved["wrap"]
        return False


class FakeResponse:
    def __init__(self, status, headers, body):
        self.status = status
        self._headers = headers
        self._body = body

    def getheaders(self):
        return list(self._headers)

    def read(self, limit=None):
        return self._body if limit is None else self._body[:limit]


class FakeConnection:
    """Records requests; never touches a socket."""

    def __init__(self, response=None, raise_on_request=None):
        self.requests = []
        self._response = response or FakeResponse(200, [("ETag", '"e"')], b"")
        self._raise = raise_on_request
        self.closed = False

    def request(self, method, url, body=None, headers=None):
        self.requests.append((method, url, len(body or b""), dict(headers or {})))
        if self._raise is not None:
            raise self._raise

    def getresponse(self):
        return self._response

    def close(self):
        self.closed = True


SECRETS = (FAKE_AK, FAKE_SEC)


def perform(tmp, conn, factory=None, **kw):
    """End-to-end through the REAL `run_control`, in a sandbox HOME."""
    return sandbox_run(tmp, conn, factory=factory, **kw)


def factory_for(conn):
    def make(host):
        make.hosts.append(host)
        return conn
    make.hosts = []
    return make


_UNSET = object()


def gates(tmp, *, execute=True, adam=True, confirm=CONFIRM,
          bucket="bible-pal-cas-probe", account=ACCOUNT,
          creds=None, root=_UNSET):
    """`root=_UNSET` uses the canonical root so the CONTROL case passes;
    an explicit `root=None` really means the flag was omitted."""
    return pc.ExecutionGates(
        execute=execute, authorized_by_adam=adam, confirmation=confirm,
        bucket=bucket, account_id=account,
        credentials_file=creds if creds is not None else write_env(tmp),
        evidence_root=(pc.canonical_evidence_root() if root is _UNSET
                       else root))


# ═══════════════════════════════════════════════════════════════════════════
# 1-2  PLAN MODE
# ═══════════════════════════════════════════════════════════════════════════

class PlanModeTests(unittest.TestCase):

    def test_1_plan_mode_does_not_read_the_credential_file(self):
        """Any open() of the real credential path is a hard failure."""
        opened = []
        real_open, real_osopen = open, os.open

        def guard_open(file, *a, **k):
            opened.append(str(file))
            return real_open(file, *a, **k)

        def guard_osopen(path, *a, **k):
            opened.append(str(path))
            return real_osopen(path, *a, **k)

        import builtins
        builtins.open, os.open = guard_open, guard_osopen
        try:
            rc = pc.main(["--plan", "--account-id", ACCOUNT])
        finally:
            builtins.open, os.open = real_open, real_osopen
        self.assertEqual(rc, pc.EXIT_SUCCESS)
        self.assertNotIn(REAL_CREDENTIAL_PATH, opened)
        self.assertFalse([p for p in opened if p.endswith(".env")])

    def test_2_plan_mode_opens_zero_sockets_under_the_kill_switch(self):
        with NoNetwork() as net:
            rc = pc.main(["--plan", "--account-id", ACCOUNT])
        self.assertEqual(rc, pc.EXIT_SUCCESS)
        self.assertEqual(net.attempts, [])

    def test_2b_plan_mode_creates_no_evidence(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = os.path.join(tmp.name, "never")
        rc = pc.main(["--plan", "--account-id", ACCOUNT,
                      "--evidence-root", root])
        self.assertEqual(rc, pc.EXIT_SUCCESS)
        self.assertFalse(os.path.exists(root))

    def test_2c_plan_output_names_target_and_denied_and_says_not_performed(self):
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            pc.main(["--plan", "--account-id", ACCOUNT])
        text = buf.getvalue()
        self.assertIn("LIVE PARENT CONTROL NOT PERFORMED IN PLAN MODE", text)
        self.assertIn("bible-pal-cas-probe", text)
        self.assertIn("bible-pal-audio", text)
        self.assertNotIn(ACCOUNT, text)          # account id never echoed


# ═══════════════════════════════════════════════════════════════════════════
# 3-7  GATES AND TARGET IMMUTABILITY
# ═══════════════════════════════════════════════════════════════════════════

class ExecutionGateTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_3_every_live_gate_is_required(self):
        gates(self.tmp).assert_may_execute()          # control passes
        for label, kwargs in (
                ("no --execute", {"execute": False}),
                ("no --authorized-by-adam", {"adam": False}),
                ("no --confirm", {"confirm": None}),
                ("wrong --confirm", {"confirm": "PLEASE"}),
                ("lowercase confirm", {"confirm": CONFIRM.lower()}),
                ("no --account-id", {"account": None}),
                ("no --credentials-file", {"creds": ""}),
                ("no --evidence-root", {"root": ""})):
            with self.subTest(missing=label):
                with self.assertRaises((pc.MissingAuthorization,
                                        pc.SafetyBarrierTripped,
                                        pc.ProductionNameDetected,
                                        pc.ParentControlRefused)):
                    gates(self.tmp, **kwargs).assert_may_execute()

    def test_4_wrong_bucket_is_refused(self):
        for bad in ("bible-pal-cas-probe-2", "some-other-bucket", "",
                    "BIBLE-PAL-CAS-PROBE"):
            with self.subTest(bucket=bad):
                with self.assertRaises(pc.ProductionNameDetected):
                    gates(self.tmp, bucket=bad).assert_may_execute()

    def test_5_production_bucket_is_refused(self):
        with self.assertRaises(pc.ProductionNameDetected):
            gates(self.tmp, bucket="bible-pal-audio").assert_may_execute()
        with self.assertRaises(pc.ProductionNameDetected):
            pc.assert_no_production_name("bible-pal-audio")

    def test_6_production_name_variants_fail_safely(self):
        """Unlike the Gate D scan, this one is CASEFOLDED."""
        for variant in ("bible-pal-audio", "BIBLE-PAL-AUDIO",
                        "Bible-Pal-Audio", "s3://BIBLE-PAL-AUDIO/x",
                        "  bible-pal-AUDIO  "):
            with self.subTest(variant=variant):
                with self.assertRaises(pc.ProductionNameDetected):
                    pc.assert_no_production_name(variant)
        # And a variant can never become the live target either.
        with self.assertRaises((pc.ProductionNameDetected,
                                pc.SafetyBarrierTripped)):
            gates(self.tmp, bucket="BIBLE-PAL-AUDIO").assert_may_execute()

    def test_7_malformed_account_id_is_refused(self):
        for bad in (None, "", "xyz", ACCOUNT.upper(), ACCOUNT[:31],
                    ACCOUNT + "0", "6014dd2b42f24effa4f5d3866e23344",
                    " " + ACCOUNT, 12345):
            with self.subTest(account=repr(bad)[:24]):
                with self.assertRaises((pc.MissingAuthorization,
                                        pc.EndpointRefused,
                                        pc.SafetyBarrierTripped)):
                    gates(self.tmp, account=bad).assert_may_execute()

    def test_22_production_cannot_become_target_via_mutable_aliases(self):
        """Rebinding the display aliases changes nothing enforceable."""
        saved = (pc.PROBE_BUCKET, pc.DENIED_NAMES, pc.EXECUTE_CONFIRMATION)
        try:
            pc.PROBE_BUCKET = "bible-pal-audio"
            pc.DENIED_NAMES = ()
            pc.EXECUTE_CONFIRMATION = "anything"
            with self.assertRaises(pc.ProductionNameDetected):
                gates(self.tmp, bucket="bible-pal-audio").assert_may_execute()
            with self.assertRaises(pc.MissingAuthorization):
                gates(self.tmp, confirm="anything").assert_may_execute()
            signed = pc.build_control_request(
                credential=synthetic_credential(), account_id=ACCOUNT,
                run_id="ctl-1-a", amz_date=AMZ_DATE)
            self.assertEqual(signed.target.bucket, "bible-pal-cas-probe")
        finally:
            (pc.PROBE_BUCKET, pc.DENIED_NAMES,
             pc.EXECUTE_CONFIRMATION) = saved

    def test_22b_environment_cannot_redirect_the_target(self):
        for var in ("R2_BUCKET", "AWS_ENDPOINT_URL", "PROBE_BUCKET",
                    "R2_ACCOUNT_ID"):
            os.environ[var] = "bible-pal-audio"
            self.addCleanup(os.environ.pop, var, None)
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-1-a", amz_date=AMZ_DATE)
        self.assertEqual(signed.target.bucket, "bible-pal-cas-probe")

    def test_gates_run_before_any_credential_read_or_network(self):
        """A failing gate must not read the file or build a connection."""
        conn = FakeConnection()
        make = factory_for(conn)
        with self.assertRaises(pc.MissingAuthorization):
            pc.run_control(gates=gates(self.tmp, adam=False),
                           connection_factory=make)
        self.assertEqual(make.hosts, [])
        self.assertEqual(conn.requests, [])


# ═══════════════════════════════════════════════════════════════════════════
# 8-11  CREDENTIAL FILE
# ═══════════════════════════════════════════════════════════════════════════

class CredentialFileTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_8_metadata_checks_fail_closed(self):
        missing = os.path.join(self.tmp, "nope.env")
        with self.assertRaises(pc.MissingAuthorization):
            pc.assert_credential_file_metadata(missing)
        loose = write_env(self.tmp, mode=0o644)
        with self.assertRaises(pc.ParentControlRefused):
            pc.assert_credential_file_metadata(loose)
        os.chmod(loose, 0o600)
        pc.assert_credential_file_metadata(loose)          # control
        link = os.path.join(self.tmp, "link.env")
        os.symlink(loose, link)
        with self.assertRaises(pc.ParentControlRefused):
            pc.assert_credential_file_metadata(link)
        directory = os.path.join(self.tmp, "dir.env")
        os.mkdir(directory, 0o700)
        with self.assertRaises(pc.ParentControlRefused):
            pc.assert_credential_file_metadata(directory)
        for bad in (None, "", 5):
            with self.assertRaises(pc.MissingAuthorization):
                pc.assert_credential_file_metadata(bad)

    def test_9_parser_accepts_a_synthetic_correct_file(self):
        cred = pc.parse_parent_credentials(GOOD_ENV)
        self.assertEqual(cred.access_key_id, FAKE_AK)
        self.assertEqual(cred.secret_access_key, FAKE_SEC)
        self.assertFalse(hasattr(cred, "session_token"))
        # Comments and blank lines are tolerated.
        cred2 = pc.parse_parent_credentials(
            "# disposable\n\n" + GOOD_ENV + "\n")
        self.assertEqual(cred2, cred)
        # And a real read path works on a synthetic file.
        self.assertEqual(read := pc.read_parent_credentials(
            write_env(self.tmp)), cred)
        self.assertEqual(read.access_key_id, FAKE_AK)

    def test_10_parser_rejects_unknown_duplicate_and_missing_keys(self):
        cases = {
            "unknown key": GOOD_ENV + "R2_ACCOUNT_ID=abc123def456\n",
            "duplicate ak": GOOD_ENV + f"R2_ACCESS_KEY_ID={FAKE_AK}\n",
            "duplicate sec": GOOD_ENV + f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "missing secret": f"R2_ACCESS_KEY_ID={FAKE_AK}\n",
            "missing ak": f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "empty": "",
            "not kv": "just a line\n" + GOOD_ENV,
            "lowercase key": f"r2_access_key_id={FAKE_AK}\n"
                             f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "empty value": "R2_ACCESS_KEY_ID=\n"
                           f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "short value": "R2_ACCESS_KEY_ID=abc\n"
                           f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "value with space": "R2_ACCESS_KEY_ID=aaaa aaaa aaaa\n"
                                f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "value with tab": "R2_ACCESS_KEY_ID=aaaaaaaa\taaaa\n"
                              f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
        }
        for label, text in cases.items():
            with self.subTest(case=label):
                with self.assertRaises(pc.ParentControlRefused):
                    pc.parse_parent_credentials(text)
        with self.assertRaises(pc.ParentControlRefused):
            pc.parse_parent_credentials(b"bytes")

    def test_10b_embedded_control_characters_are_rejected(self):
        for ctl in ("\x00", "\r", "\x1b", "\x7f"):
            with self.subTest(ctl=repr(ctl)):
                text = (f"R2_ACCESS_KEY_ID=aaaaaaaa{ctl}aaaa\n"
                        f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n")
                with self.assertRaises(pc.ParentControlRefused):
                    pc.parse_parent_credentials(text)

    def test_11_secret_values_never_enter_exception_text(self):
        secret = "SuperSecretValue123456789"
        bad_inputs = [
            f"R2_ACCESS_KEY_ID={secret}\nR2_SECRET_ACCESS_KEY={secret}\n"
            f"R2_EXTRA={secret}\n",
            f"R2_ACCESS_KEY_ID={secret}\nR2_ACCESS_KEY_ID={secret}\n",
            f"R2_ACCESS_KEY_ID={secret} with space\n",
            f"R2_ACCESS_KEY_ID={secret}\n",
        ]
        for text in bad_inputs:
            with self.subTest(text=text[:34]):
                with self.assertRaises(pc.ParentControlRefused) as ctx:
                    pc.parse_parent_credentials(text)
                self.assertNotIn(secret, str(ctx.exception))

    def test_11b_the_real_credential_file_is_never_touched_by_tests(self):
        """Self-check: this suite must not depend on the real file.

        The needles are assembled at runtime so this assertion cannot
        match its own source text and pass or fail spuriously.
        """
        with open(os.path.abspath(__file__), encoding="utf-8") as _fh:
            source = _fh.read()
        for call in ("read_parent_credentials", "assert_credential_file_metadata",
                     "parse_parent_credentials"):
            needle = call + "(" + "REAL_CREDENTIAL_PATH"
            self.assertNotIn(needle, source)
        # The real path is named exactly once: where the constant is
        # defined for the plan-mode "was not opened" assertion.
        self.assertEqual(source.count("r2-disposable" "-probe.env"), 1)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "real.env")))


# ═══════════════════════════════════════════════════════════════════════════
# 12-15  REQUEST SHAPE
# ═══════════════════════════════════════════════════════════════════════════

class ControlRequestShapeTests(unittest.TestCase):

    def signed(self, run_id="ctl-1-a"):
        return pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id=run_id, amz_date=AMZ_DATE)

    def test_12_no_security_token_header_and_no_session_token(self):
        signed = self.signed()
        headers = signed.header_map()
        self.assertNotIn("x-amz-security-token", headers)
        self.assertNotIn("x-amz-security-token", signed.signed_header_names)
        for value in headers.values():
            self.assertNotIn("jwt/", value)

    def test_13_signed_headers_are_exact(self):
        self.assertEqual(
            list(self.signed().signed_header_names),
            ["host", "if-none-match", "x-amz-content-sha256", "x-amz-date"])

    def test_13b_sigv4_algorithm_region_and_service(self):
        auth = self.signed().header_map()["authorization"]
        self.assertTrue(auth.startswith("AWS4-HMAC-SHA256 "))
        self.assertIn("/auto/s3/aws4_request", auth)
        self.assertIn("SignedHeaders=host;if-none-match;"
                      "x-amz-content-sha256;x-amz-date", auth)

    def test_14_body_is_exactly_256_bytes_and_hashed_correctly(self):
        signed = self.signed()
        self.assertEqual(len(signed.body), 256)
        self.assertEqual(len(pc.control_body()), 256)
        self.assertEqual(signed.header_map()["x-amz-content-sha256"],
                         hashlib.sha256(signed.body).hexdigest())

    def test_14b_conditional_header_and_empty_query(self):
        signed = self.signed()
        self.assertEqual(signed.header_map()["if-none-match"], "*")
        self.assertEqual(signed.target.query, ())
        self.assertEqual(signed.target.method, "PUT")
        self.assertEqual(signed.target.bucket, "bible-pal-cas-probe")

    def test_15_control_key_grammar_is_unique_and_non_colliding(self):
        key = pc.control_key_for("ctl-73608-6a890643")
        self.assertEqual(
            key, "catalog/probe/control/ctl-73608-6a890643/parent-put.json")
        # Cannot be mistaken for a Gate D allocator key.
        self.assertFalse(probe._grammar().allocated_key.fullmatch(key))
        self.assertNotIn(key, probe._fixed_probe_keys())
        # Cannot collide with either frozen Gate D run namespace.
        for run in ("run-45842-6a87a66f", "run-73608-6a890643"):
            self.assertNotIn(run, key)
        for bad in ("", "ctl", "run-1-a", "ctl-1-a/../..", "CTL-1-A",
                    "ctl-1-zz", "ctl-1-a\n"):
            with self.subTest(run_id=repr(bad)):
                with self.assertRaises(pc.SafetyBarrierTripped):
                    pc.control_key_for(bad)
        self.assertNotEqual(pc.new_control_run_id(), "")
        self.assertRegex(pc.new_control_run_id(), r"^ctl-\d+-[0-9a-f]+$")

    def test_build_refuses_anything_but_a_ParentCredential(self):
        temp = probe.mint_probe_credential(
            group="T-CAS-1", account_id="0" * 32,
            parent_access_key_id=FAKE_AK, parent_secret_access_key=FAKE_SEC,
            now=1786708800)
        for bad in (temp, None, ("a", "b"), {"a": "b"}):
            with self.subTest(kind=type(bad).__name__):
                with self.assertRaises(pc.SafetyBarrierTripped):
                    pc.build_control_request(
                        credential=bad, account_id=ACCOUNT,
                        run_id="ctl-1-a", amz_date=AMZ_DATE)


# ═══════════════════════════════════════════════════════════════════════════
# 16-17  ONE REQUEST ONLY
# ═══════════════════════════════════════════════════════════════════════════

class OneRequestInvariantTests(unittest.TestCase):

    def signed(self):
        return pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-1-a", amz_date=AMZ_DATE)

    def test_16_a_second_send_is_refused(self):
        conn = FakeConnection()
        t = pc.OneShotTransport(endpoint_host="h", connection_factory=lambda h: conn)
        t.send_once(self.signed())
        self.assertTrue(t.spent)
        for _ in range(3):
            with self.assertRaises(pc.SafetyBarrierTripped):
                t.send_once(self.signed())
        self.assertEqual(len(conn.requests), 1)

    def test_16b_the_latch_holds_even_when_the_request_raises(self):
        conn = FakeConnection(raise_on_request=OSError("boom"))
        t = pc.OneShotTransport(endpoint_host="h", connection_factory=lambda h: conn)
        outcome = t.send_once(self.signed())
        self.assertEqual(outcome.failure_category, "OSError")
        self.assertTrue(t.spent)
        with self.assertRaises(pc.SafetyBarrierTripped):
            t.send_once(self.signed())

    def test_16c_a_factory_failure_still_spends_the_latch(self):
        def bad_factory(host):
            raise RuntimeError("no connection")
        t = pc.OneShotTransport(endpoint_host="h",
                                connection_factory=bad_factory)
        outcome = t.send_once(self.signed())
        self.assertEqual(outcome.failure_category, "RuntimeError")
        with self.assertRaises(pc.SafetyBarrierTripped):
            t.send_once(self.signed())

    def test_17_redirects_are_recorded_not_followed(self):
        conn = FakeConnection(FakeResponse(
            302, [("Location", "https://elsewhere.example/x")], b""))
        t = pc.OneShotTransport(endpoint_host="h", connection_factory=lambda h: conn)
        outcome = t.send_once(self.signed())
        self.assertEqual(outcome.status, 302)
        self.assertEqual(len(conn.requests), 1)      # not followed
        self.assertEqual(pc.derive_verdict(outcome), "R2_REJECTED")

    def test_17b_no_verification_or_cleanup_request_is_made(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        conn = FakeConnection(FakeResponse(200, [("ETag", '"e"')], b""))
        make = factory_for(conn)
        perform(tmp.name, conn, factory=make)
        self.assertEqual(len(conn.requests), 1)
        self.assertEqual(conn.requests[0][0], "PUT")
        self.assertEqual(len(make.hosts), 1)

    def test_17c_the_module_contains_no_retry_or_delete_machinery(self):
        with open(pc.__file__, encoding="utf-8") as _fh:
            source = _fh.read()
        for token in ("shutil.rmtree", "os.remove", "os.unlink", "os.rmdir",
                      "os.replace", "shutil.move", "allow_redirects",
                      "urllib.request", "requests."):
            self.assertNotIn(token, source, f"unexpected {token!r}")


# ═══════════════════════════════════════════════════════════════════════════
# 18-21  EVIDENCE
# ═══════════════════════════════════════════════════════════════════════════

class EvidenceTests(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def run_once(self, response=None, raise_on_request=None):
        conn = FakeConnection(response, raise_on_request)
        return perform(self.tmp, conn)

    def test_18_error_sanitizer_populates_safe_diagnostics(self):
        body = (b"<Error><Code>InvalidArgument</Code><Message>Unsupported "
                b"header 'x-amz-security-token' in this request</Message>"
                b"</Error>")
        record, _ = self.run_once(FakeResponse(
            400, [("cf-ray", "a2ee5ec95eaea942-DTW")], body))
        self.assertEqual(record["http_status"], 400)
        self.assertEqual(record["error_code"], "InvalidArgument")
        self.assertIn("Unsupported header", record["error_message"])
        self.assertEqual(record["error_argument"], "x-amz-security-token")
        self.assertEqual(record["cf_ray"], "a2ee5ec95eaea942-DTW")
        self.assertEqual(record["response_body_len"], len(body))
        self.assertEqual(record["response_body_sha256"],
                         hashlib.sha256(body).hexdigest())
        self.assertEqual(record["verdict"], "R2_REJECTED")

    def test_19_evidence_excludes_all_credential_material(self):
        record, paths = self.run_once()
        with open(paths["record_path"], encoding="utf-8") as _fh:
            raw = _fh.read()
        for secret in (FAKE_AK, FAKE_SEC, GOOD_ENV.strip()):
            self.assertNotIn(secret, raw)
        for token in ("authorization", "Authorization", "signature",
                      "Signature", "canonical", "AWS4-HMAC"):
            self.assertNotIn(token, raw, f"{token!r} reached the evidence")
        self.assertEqual(set(record) - pc.PARENT_CONTROL_FIELDS, set())
        self.assertIs(record["session_token_present"], False)
        self.assertIs(record["x_amz_security_token_present"], False)
        self.assertIs(record["production_contacted"], False)

    def test_19d_a_header_NAME_in_a_diagnostic_is_kept_not_scrubbed(self):
        """`x-amz-security-token` is a header NAME, not credential
        material. If R2 names it in an error, that is precisely the
        diagnostic this harness exists to capture, and scrubbing it would
        destroy the most informative possible result. The VALUE can never
        appear, because no token is ever sent."""
        body = (b"<Error><Code>InvalidArgument</Code><Message>Unsupported "
                b"header 'x-amz-security-token' in this request</Message>"
                b"</Error>")
        record, paths = self.run_once(FakeResponse(400, [], body))
        with open(paths["record_path"], encoding="utf-8") as _fh:
            raw = _fh.read()
        self.assertIn("x-amz-security-token", raw)          # kept
        self.assertEqual(record["error_argument"], "x-amz-security-token")
        # ...while the request provably carried no such header at all.
        self.assertIs(record["x_amz_security_token_present"], False)
        for secret in (FAKE_AK, FAKE_SEC):
            self.assertNotIn(secret, raw)

    def test_19b_a_record_carrying_a_known_secret_is_refused(self):
        record, _ = self.run_once()
        poisoned = dict(record, key=record["key"] + FAKE_SEC)
        with self.assertRaises((probe.EvidenceValidationError,
                                pc.SafetyBarrierTripped)):
            pc.assert_no_secret_material(poisoned, (FAKE_SEC,))

    def test_19c_unexpected_or_unsafe_record_fields_are_refused(self):
        record, _ = self.run_once()
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.assert_record_is_safe(dict(record, authorization="AWS4..."))
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.assert_record_is_safe(dict(record, extra_field=1))
        incomplete = dict(record)
        incomplete.pop("cf_ray")
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.assert_record_is_safe(incomplete)
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.assert_record_is_safe(
                dict(record, x_amz_security_token_present=True))

    def test_20_manifest_and_anchor_verify(self):
        record, paths = self.run_once()
        with open(paths["record_path"], "rb") as _fh:
            raw = _fh.read()
        with open(paths["manifest_path"],
                                   encoding="utf-8") as _fh:
            manifest = json.loads(_fh.read())
        self.assertEqual(manifest["files"]["parent_control_record.json"],
                         hashlib.sha256(raw).hexdigest())
        self.assertEqual(manifest["run_id"], record["run_id"])
        with open(paths["manifest_path"], "rb") as _fh:
            computed = hashlib.sha256(_fh.read()).hexdigest()
        with open(paths["anchor_path"], encoding="utf-8") as _fh:
            anchor = _fh.read().strip()
        self.assertEqual(computed, anchor)
        self.assertEqual(computed, paths["manifest_sha256"])
        for path in (paths["record_path"], paths["manifest_path"],
                     paths["anchor_path"]):
            self.assertEqual(stat.S_IMODE(os.lstat(path).st_mode) & 0o077, 0)
        run_dir = os.path.dirname(paths["record_path"])
        self.assertEqual(stat.S_IMODE(os.lstat(run_dir).st_mode), 0o700)

    def test_21_a_pre_existing_run_id_refuses_to_overwrite(self):
        first = sandbox_evidence(self.tmp, "ctl-1-a")
        self.addCleanup(first.close)
        with self.assertRaises(FileExistsError):
            sandbox_evidence(self.tmp, "ctl-1-a")
        # And an existing record file cannot be rewritten.
        ev = sandbox_evidence(self.tmp, "ctl-1-b")
        self.addCleanup(ev.close)
        conn = FakeConnection()
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-1-b", amz_date=AMZ_DATE)
        outcome = pc.OneShotTransport(
            endpoint_host="h",
            connection_factory=lambda h: conn).send_once(signed)
        record = pc.build_parent_control_record(
            run_id="ctl-1-b", signed=signed, outcome=outcome,
            verdict=pc.derive_verdict(outcome), secrets=SECRETS)
        ev.write(record, secrets=SECRETS)
        with self.assertRaises(FileExistsError):
            ev.write(record, secrets=SECRETS)

    def test_20b_gate_d_evidence_roots_are_never_touched(self):
        with open(pc.__file__, encoding="utf-8") as _fh:
            source = _fh.read()
        self.assertNotIn("cas-probe-evidence", source)
        self.assertNotIn("cas-probe-anchors", source)
        self.assertIn("parent-control-evidence", source)
        self.assertIn("parent-control-anchors", source)


# ═══════════════════════════════════════════════════════════════════════════
# VERDICT MODEL
# ═══════════════════════════════════════════════════════════════════════════

class VerdictTests(unittest.TestCase):

    def outcome(self, status=None, failure=None, body=b""):
        return pc.TransportOutcome(
            status=status, headers=(), body=body, body_truncated=False,
            failure_category=failure, t_request_attempt_mono_ns=1)

    def test_verdict_model(self):
        self.assertEqual(pc.derive_verdict(self.outcome(200)), "SUCCESS")
        self.assertEqual(pc.derive_verdict(self.outcome(201)), "SUCCESS")
        self.assertEqual(pc.derive_verdict(self.outcome(400)), "R2_REJECTED")
        self.assertEqual(pc.derive_verdict(self.outcome(403)), "R2_REJECTED")
        self.assertEqual(pc.derive_verdict(self.outcome(500)), "R2_REJECTED")
        self.assertEqual(
            pc.derive_verdict(self.outcome(failure="TimeoutError")),
            "TRANSPORT_FAILURE")
        self.assertEqual(pc.derive_verdict(self.outcome()), "INCOMPLETE")
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.derive_verdict("nope")

    def test_verdicts_map_to_distinct_exit_codes(self):
        codes = {v: pc._VERDICT_EXIT[v] for v in
                 ("SUCCESS", "R2_REJECTED", "TRANSPORT_FAILURE",
                  "INCOMPLETE")}
        self.assertEqual(codes["SUCCESS"], 0)
        self.assertEqual(len(set(codes.values())), 4)

    def test_no_cas_vocabulary_leaks_into_this_harness(self):
        with open(pc.__file__, encoding="utf-8") as _fh:
            source = _fh.read()
        for token in ("PASS", "NO-GO", "ABANDON", "GO/NO-GO"):
            self.assertNotIn(f'"{token}"', source)
        self.assertIn("does not test the Gate D matrix", source)


# ═══════════════════════════════════════════════════════════════════════════
# 23  KILL-SWITCH POSITIVE CONTROL
# ═══════════════════════════════════════════════════════════════════════════

class KillSwitchPositiveControlTests(unittest.TestCase):

    def test_23_kill_switch_is_non_vacuous(self):
        """The switch must actually block a real attempt."""
        with NoNetwork() as net:
            for call in (lambda: socket.socket(),
                         lambda: socket.getaddrinfo("example.invalid", 443),
                         lambda: socket.create_connection(("h", 1)),
                         lambda: ssl.create_default_context()):
                with self.assertRaises(AssertionError):
                    call()
        self.assertEqual(len(net.attempts), 4)

    def test_23b_the_whole_offline_flow_runs_with_zero_network(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        conn = FakeConnection(FakeResponse(
            400, [("cf-ray", "ray-1")],
            b"<Error><Code>InvalidArgument</Code></Error>"))
        with NoNetwork() as net:
            record, paths = perform(tmp.name, conn)
        self.assertEqual(net.attempts, [])
        self.assertEqual(record["verdict"], "R2_REJECTED")
        self.assertTrue(os.path.exists(paths["anchor_path"]))

    def test_23c_live_factory_is_only_reachable_through_main_execute(self):
        with open(pc.__file__, encoding="utf-8") as _fh:
            source = _fh.read()
        self.assertEqual(source.count("live_connection_factory"), 2)
        self.assertIn("import http.client", source)
        self.assertNotIn("import http.client\nimport", source.split(
            "def live_connection_factory")[0])


# ═══════════════════════════════════════════════════════════════════════════
# INDEPENDENCE FROM GATE D
# ═══════════════════════════════════════════════════════════════════════════

class GateDIndependenceTests(unittest.TestCase):

    def test_only_pure_helpers_are_imported(self):
        """Parsed with `ast`, so comments and formatting cannot skew it."""
        import ast
        with open(pc.__file__, encoding="utf-8") as _fh:
            tree = ast.parse(_fh.read())
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) \
                    and node.module == "probe_r2_cas":
                imported |= {alias.name for alias in node.names}
            if isinstance(node, ast.Import):
                self.assertNotIn("probe_r2_cas",
                                 [a.name for a in node.names],
                                 "the whole Gate D module must not be imported")
        allowed = {
            "MIN_PROJECTED_SECRET_CHARS", "EndpointRefused",
            "EvidenceValidationError", "MissingAuthorization",
            "ProductionNameDetected", "SafetyBarrierTripped",
            "_iter_persisted_strings", "_sha256_hex",
            "assert_no_known_secret", "build_endpoint_host",
            "canonical_secret_projection", "new_request_target",
            "parse_s3_error", "safe_error_argument", "safe_error_message",
            "sign_request", "synthetic_payload",
        }
        self.assertEqual(imported, allowed)
        for forbidden in ("R2Transport", "EvidenceWriter", "TemporaryCredential",
                          "mint_probe_credential", "LiveProbeRunner",
                          "test_spec", "TEST_MATRIX"):
            self.assertNotIn(forbidden, imported)

    def test_gate_d_transport_still_refuses_non_temporary_credentials(self):
        """This harness must not have weakened the reviewed gate."""
        transport = probe.R2Transport(
            endpoint_host=probe.build_endpoint_host("0" * 32),
            connection_factory=lambda h: FakeConnection(),
            wall_clock=lambda: 1786708800)
        with self.assertRaises(probe.SafetyBarrierTripped):
            transport._assert_amz_date_fresh(synthetic_credential(),
                                             AMZ_DATE)

    def test_gate_d_evidence_schema_still_refuses_a_control_key(self):
        record = {"record_kind": "REQUEST_RECORD", "phase": "T",
                  "run_id": "run-ctl-0001", "group": "T-CAS-1", "test_id": "A",
                  "repetition": 1, "sequence": 1,
                  "correlation_id": "T/run-ctl-0001/A/1/1",
                  "bucket": "bible-pal-cas-probe",
                  "key": pc.control_key_for("ctl-1-a"),
                  "endpoint_host_sha256": "0" * 64, "http_method": "PUT",
                  "query_params": [], "request_body_len": 256,
                  "request_body_sha256": "0" * 64,
                  "signed_headers": ["host"], "session_token_present": False,
                  "session_token_signed": False,
                  "request_time_epoch": 1787000000}
        with self.assertRaises(probe.EvidenceValidationError):
            probe.validate_record(record, ())


class TransformedSecretBoundaryTests(unittest.TestCase):
    """Codex HIGH: transformed known secrets must not reach evidence OR
    the console. Synthetic secrets only."""

    SECRET = "AlphaBetaGammaDeltaThetaValue"

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def variants(self):
        return {
            "exact": self.SECRET,
            "spaces": "Alpha Beta Gamma Delta Theta Value",
            "hyphens": "Alpha-Beta-Gamma-Delta-Theta-Value",
            "underscores": "Alpha_Beta_Gamma_Delta_Theta_Value",
            "dots": "Alpha.Beta.Gamma.Delta.Theta.Value",
            "quotes": 'Alpha"Beta"Gamma"Delta"Theta"Value',
            "xml decimal entity": "Alpha&#66;etaGammaDeltaThetaValue",
            "xml hex entity": "Alpha&#x42;etaGammaDeltaThetaValue",
            "percent encoding": "Alpha%42etaGammaDeltaThetaValue",
            "double encoded": "Alpha&amp;#66;etaGammaDeltaThetaValue",
        }

    def test_transformed_secret_in_every_persisted_field_is_rejected(self):
        base = {"record_kind": "PARENT_CONTROL_RECORD", "run_id": "ctl-1-a",
                "cf_ray": None, "request_id": None, "error_message": None,
                "error_argument": None, "nested": {"list": ["safe"]}}
        for field in ("run_id", "cf_ray", "request_id", "error_message",
                      "error_argument"):
            for label, value in self.variants().items():
                with self.subTest(field=field, transform=label):
                    with self.assertRaises((probe.EvidenceValidationError,
                                            pc.SafetyBarrierTripped)) as ctx:
                        pc.assert_no_transformed_secret(
                            dict(base, **{field: value}),
                            (self.SECRET,), "test")
                    self.assertNotIn("Alpha", str(ctx.exception))

    def test_transformed_secret_nested_in_lists_and_dicts_is_rejected(self):
        for label, value in self.variants().items():
            with self.subTest(transform=label):
                with self.assertRaises((probe.EvidenceValidationError,
                                        pc.SafetyBarrierTripped)):
                    pc.assert_no_transformed_secret(
                        {"a": {"b": [{"c": value}]}}, (self.SECRET,), "test")

    def test_a_session_token_shaped_secret_is_rejected(self):
        import base64
        token = base64.b64encode(b"jwt/" + b"header.payload.sig" * 4).decode()
        split = "-".join(token[i:i + 5] for i in range(0, len(token), 5))
        for label, shape in (("raw", token), ("hyphen split", split)):
            with self.subTest(shape=label):
                with self.assertRaises((probe.EvidenceValidationError,
                                        pc.SafetyBarrierTripped)):
                    pc.assert_no_transformed_secret(
                        {"cf_ray": shape}, (token,), "test")

    def test_legitimate_identifiers_still_persist(self):
        pc.assert_no_transformed_secret(
            {"cf_ray": "a2ee5ec95eaea942-DTW",
             "request_id": "abc123DEF456",
             "error_code": "InvalidArgument"},
            (self.SECRET, FAKE_AK, FAKE_SEC), "test")

    def test_the_safe_header_NAME_is_not_confused_with_a_token_value(self):
        body = (b"<Error><Code>InvalidArgument</Code><Message>Unsupported "
                b"header 'x-amz-security-token' in this request</Message>"
                b"</Error>")
        record, paths = perform(self.tmp, FakeConnection(
            FakeResponse(400, [], body)))
        self.assertEqual(record["error_argument"], "x-amz-security-token")
        with open(paths["record_path"], encoding="utf-8") as fh:
            self.assertIn("x-amz-security-token", fh.read())

    def test_a_response_echoing_the_real_secret_is_redacted(self):
        """The live path passes the real credential into parsing, so an
        echoed secret is redacted where the text is first interpreted."""
        body = ("<Error><Code>InvalidArgument</Code><Message>bad key "
                + FAKE_SEC + "</Message></Error>").encode()
        record, paths = perform(self.tmp, FakeConnection(
            FakeResponse(400, [], body)))
        with open(paths["record_path"], encoding="utf-8") as fh:
            raw = fh.read()
        self.assertNotIn(FAKE_SEC, raw)
        self.assertNotIn(FAKE_SEC, record["error_message"] or "")
        self.assertNotIn(FAKE_SEC, pc.render_result(
            run_id=record["run_id"], paths=paths, record=record))

    def test_console_cannot_print_an_unvalidated_response_value(self):
        """A transformed secret in cf_ray is refused, and nothing derived
        from the response reaches the record, the console or stderr."""
        env = write_env(self.tmp,
                        f"R2_ACCESS_KEY_ID={FAKE_AK}\n"
                        f"R2_SECRET_ACCESS_KEY={self.SECRET}\n")
        conn = FakeConnection(FakeResponse(
            400, [("cf-ray", "Alpha-Beta-Gamma-Delta-Theta-Value")], b""))
        with self.assertRaises(pc.ConfidentialityWithheld) as ctx:
            sandbox_run(self.tmp, conn, gates_kwargs={"creds": env})
        self.assertNotIn("Alpha", str(ctx.exception))
        self.assertEqual(len(conn.requests), 1)     # the request happened

    def test_bounded_response_identifier_grammar(self):
        pc.assert_response_identifier_is_safe(None, "cf_ray")
        pc.assert_response_identifier_is_safe("a2ee5ec95eaea942-DTW", "cf_ray")
        for bad in ("has space", 'has"quote', "has%percent", "has&amp;",
                    "x" * 129, 12345):
            with self.subTest(value=repr(bad)[:20]):
                with self.assertRaises(probe.EvidenceValidationError):
                    pc.assert_response_identifier_is_safe(bad, "cf_ray")

    def test_the_boundary_refuses_to_run_without_known_secrets(self):
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.assert_no_transformed_secret({"a": "b"}, (), "test")

    def test_deterministic_decode_is_bounded_and_pure(self):
        self.assertEqual(pc.deterministic_decode("plain"), "plain")
        self.assertEqual(pc.deterministic_decode("A&#66;C"), "ABC")
        self.assertEqual(pc.deterministic_decode("A%42C"), "ABC")
        self.assertEqual(pc.deterministic_decode("A&amp;#66;C"), "ABC")
        with self.assertRaises(pc.SafetyBarrierTripped):
            pc.deterministic_decode(b"bytes")


class D2BodyEqualityTests(unittest.TestCase):
    """Codex MEDIUM: the control must change authentication ONLY."""

    D2_RECORD = ("/Users/zowee/.local/state/bible-pal/cas-probe-evidence/"
                 "run-73608-6a890643/request/"
                 "T_run-73608-6a890643_A_0001_000001.json")

    def test_body_is_byte_identical_to_gate_d2(self):
        body = pc.control_body()
        self.assertEqual(len(body), 256)
        self.assertEqual(hashlib.sha256(body).hexdigest(), pc.D2_BODY_SHA256)
        self.assertEqual(
            pc.D2_BODY_SHA256,
            "e28ba69bdecae0003bc057249a6fbc975ed567488ada96e98f213f161dc646ba")
        self.assertEqual(body, probe.synthetic_payload("seed", 256))

    def test_the_frozen_d2_record_attests_to_the_same_digest(self):
        """Read-only, from the SAFE persisted request record."""
        if not os.path.exists(self.D2_RECORD):
            self.skipTest("frozen Gate D2 evidence is not present")
        with open(self.D2_RECORD, encoding="utf-8") as fh:
            record = json.load(fh)
        self.assertEqual(record["request_body_len"], 256)
        self.assertEqual(record["request_body_sha256"], pc.D2_BODY_SHA256)

    def test_the_signed_request_carries_those_exact_bytes(self):
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-1-a", amz_date=AMZ_DATE)
        self.assertEqual(hashlib.sha256(signed.body).hexdigest(),
                         pc.D2_BODY_SHA256)
        self.assertEqual(signed.header_map()["x-amz-content-sha256"],
                         pc.D2_BODY_SHA256)


class ParserNormalizationTests(unittest.TestCase):
    """Codex MEDIUM: the parser must not silently reshape credential
    bytes."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_no_normalization_of_whitespace_or_layout(self):
        cases = {
            "leading space before key": f" R2_ACCESS_KEY_ID={FAKE_AK}\n"
                                        f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "tab before key": f"\tR2_ACCESS_KEY_ID={FAKE_AK}\n"
                              f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "space before =": f"R2_ACCESS_KEY_ID ={FAKE_AK}\n"
                              f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "space after =": f"R2_ACCESS_KEY_ID= {FAKE_AK}\n"
                             f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "trailing space": f"R2_ACCESS_KEY_ID={FAKE_AK} \n"
                              f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "trailing tab": f"R2_ACCESS_KEY_ID={FAKE_AK}\t\n"
                            f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
            "indented comment": f"  #x\nR2_ACCESS_KEY_ID={FAKE_AK}\n"
                                f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n",
        }
        for label, text in cases.items():
            with self.subTest(case=label):
                with self.assertRaises(pc.ParentControlRefused):
                    pc.parse_parent_credentials(text)

    def test_shell_style_quoting_is_refused_not_interpreted(self):
        for quote in ('"', "'"):
            for label, text in (
                    ("both ends", f'R2_ACCESS_KEY_ID={quote}{FAKE_AK}{quote}\n'
                                  f'R2_SECRET_ACCESS_KEY={FAKE_SEC}\n'),
                    ("leading only", f'R2_ACCESS_KEY_ID={quote}{FAKE_AK}\n'
                                     f'R2_SECRET_ACCESS_KEY={FAKE_SEC}\n'),
                    ("secret quoted", f'R2_ACCESS_KEY_ID={FAKE_AK}\n'
                                      f'R2_SECRET_ACCESS_KEY={quote}'
                                      f'{FAKE_SEC}{quote}\n')):
                with self.subTest(quote=quote, case=label):
                    with self.assertRaises(pc.ParentControlRefused) as ctx:
                        pc.parse_parent_credentials(text)
                    self.assertNotIn(FAKE_SEC, str(ctx.exception))

    def test_values_are_returned_byte_for_byte(self):
        odd = "aB3/+=_.-~!@$^*()[]{}|;:,<>?"
        cred = pc.parse_parent_credentials(
            f"R2_ACCESS_KEY_ID={odd}\nR2_SECRET_ACCESS_KEY={FAKE_SEC}\n")
        self.assertEqual(cred.access_key_id, odd)          # not reshaped
        self.assertEqual(cred.secret_access_key, FAKE_SEC)

    def test_crlf_removes_only_the_terminator(self):
        cred = pc.parse_parent_credentials(GOOD_ENV.replace("\n", "\r\n"))
        self.assertEqual(cred.access_key_id, FAKE_AK)
        self.assertEqual(cred.secret_access_key, FAKE_SEC)
        # A bare \r INSIDE a value is not a terminator: it splits the line
        # and the result is refused rather than silently repaired.
        with self.assertRaises(pc.ParentControlRefused):
            pc.parse_parent_credentials(
                f"R2_ACCESS_KEY_ID=aaaa\raaaa\n"
                f"R2_SECRET_ACCESS_KEY={FAKE_SEC}\n")

    def test_exact_0600_is_required(self):
        for mode in (0o400, 0o200, 0o700, 0o644, 0o640, 0o000):
            with self.subTest(mode=oct(mode)):
                path = write_env(self.tmp, mode=mode)
                with self.assertRaises(pc.ParentControlRefused):
                    pc.assert_credential_file_metadata(path)
        path = write_env(self.tmp, mode=0o600)
        st = pc.assert_credential_file_metadata(path)       # control
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)

    def test_descriptor_level_verification(self):
        path = write_env(self.tmp, mode=0o600)
        self.assertEqual(pc.read_parent_credentials(path).access_key_id,
                         FAKE_AK)                            # control
        real_open = os.open

        def racing_open(p, *a, **k):
            fd = real_open(p, *a, **k)
            os.chmod(p, 0o644)          # loosened AFTER the lstat gate
            return fd

        os.open = racing_open
        try:
            with self.assertRaises(pc.ParentControlRefused) as ctx:
                pc.read_parent_credentials(path)
        finally:
            os.open = real_open
        self.assertIn("open descriptor", str(ctx.exception))


class ExplicitLiveArgumentTests(unittest.TestCase):
    """Codex MEDIUM: no live argument may come from a default."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_missing_bucket_is_refused_before_credential_or_network(self):
        conn = FakeConnection()
        make = factory_for(conn)
        with self.assertRaises(pc.MissingAuthorization):
            pc.run_control(gates=gates(self.tmp, bucket=None),
                           connection_factory=make)
        self.assertEqual(make.hosts, [])
        self.assertEqual(conn.requests, [])

    def test_missing_evidence_root_is_refused(self):
        conn = FakeConnection()
        make = factory_for(conn)
        for missing in (None, ""):
            with self.subTest(root=repr(missing)):
                with self.assertRaises(pc.MissingAuthorization):
                    pc.run_control(gates=gates(self.tmp, root=missing),
                                   connection_factory=make)
        self.assertEqual(make.hosts, [])

    def test_arbitrary_evidence_roots_are_refused(self):
        for bad in ("/tmp/whatever", self.tmp,
                    "~/.local/state/bible-pal",
                    "~/.local/state/bible-pal/cas-probe-evidence",
                    "~/.local/state/bible-pal/cas-probe-anchors",
                    "~/.local/state/bible-pal-parent-control/../bible-pal",
                    "~/.local/state/bible-pal-parent-control/sub"):
            with self.subTest(root=bad):
                with self.assertRaises(pc.ParentControlRefused):
                    pc.assert_evidence_root_is_canonical(bad)

    def test_the_canonical_root_is_accepted(self):
        canonical = pc.canonical_evidence_root()
        self.assertTrue(canonical.endswith("bible-pal-parent-control"))
        for form in ("~/.local/state/bible-pal-parent-control",
                     "~/.local/state/bible-pal-parent-control/",
                     canonical, canonical + "/."):
            with self.subTest(form=form):
                self.assertEqual(
                    pc.assert_evidence_root_is_canonical(form), canonical)
        gates(self.tmp).assert_may_execute()          # full control passes

    def test_the_cli_supplies_no_default_for_either_flag(self):
        args = pc.build_parser().parse_args(["--plan"])
        self.assertIsNone(args.bucket)
        self.assertIsNone(args.evidence_root)


class PhysicalEvidenceRootTests(unittest.TestCase):
    """Codex round-2 MEDIUM 1: the live root is a PHYSICAL invariant, not
    a lexical string comparison."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home, exist_ok=True)
        self.addCleanup(self._tmp.cleanup)

    def _open(self):
        with SandboxHome(self.home):
            return pc.open_live_evidence_root()

    def _c(self, *parts):
        return os.path.join(self.home, *parts)

    def test_A_normal_dedicated_root_succeeds(self):
        fd = self._open()
        self.addCleanup(os.close, fd)
        st = os.fstat(fd)
        self.assertTrue(stat.S_ISDIR(st.st_mode))
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o700)

    def test_A_root_itself_as_a_symlink_is_refused(self):
        elsewhere = os.path.join(self.tmp, "elsewhere")
        os.makedirs(elsewhere, mode=0o700)
        os.makedirs(self._c(".local", "state"), mode=0o700)
        os.symlink(elsewhere,
                   self._c(".local", "state", "bible-pal-parent-control"))
        with self.assertRaises(pc.ParentControlRefused):
            self._open()

    def test_A_parent_component_symlink_is_refused(self):
        elsewhere = os.path.join(self.tmp, "sneaky-state")
        os.makedirs(elsewhere, mode=0o700)
        os.makedirs(self._c(".local"), mode=0o700)
        os.symlink(elsewhere, self._c(".local", "state"))
        with self.assertRaises(pc.ParentControlRefused):
            self._open()

    def test_A_symlink_to_a_gate_d_shaped_location_is_refused(self):
        shaped = os.path.join(self.tmp, "bible-pal", "cas-probe-evidence")
        os.makedirs(shaped, mode=0o700)
        os.makedirs(self._c(".local", "state"), mode=0o700)
        os.symlink(shaped,
                   self._c(".local", "state", "bible-pal-parent-control"))
        with self.assertRaises(pc.ParentControlRefused):
            self._open()
        self.assertEqual(os.listdir(shaped), [])

    def test_C_existing_root_with_the_wrong_mode_is_refused(self):
        root = self._c(".local", "state", "bible-pal-parent-control")
        os.makedirs(root, mode=0o700)
        for mode in (0o500, 0o755, 0o750, 0o770):
            with self.subTest(mode=oct(mode)):
                os.chmod(root, mode)
                with self.assertRaises(pc.ParentControlRefused):
                    self._open()
        os.chmod(root, 0o700)
        self.addCleanup(os.close, self._open())          # control

    def test_lexical_variants_do_not_widen_acceptance(self):
        with SandboxHome(self.home):
            canonical = pc.canonical_evidence_root()
            for form in (canonical, canonical + "/", canonical + "/."):
                self.assertEqual(pc.assert_evidence_root_is_canonical(form),
                                 os.path.normpath(canonical))
            for bad in (canonical + "/../bible-pal", canonical + "/sub",
                        self._c(".local", "state")):
                with self.assertRaises(pc.ParentControlRefused):
                    pc.assert_evidence_root_is_canonical(bad)

    def test_B_writes_are_anchored_to_the_validated_descriptor(self):
        """Swapping the directory AFTER validation must not redirect the
        write: the descriptor, not the pathname, is the target."""
        ev = sandbox_evidence(self.tmp, "ctl-7-a")
        self.addCleanup(ev.close)
        root = self._c(".local", "state", "bible-pal-parent-control")
        hijack = os.path.join(self.tmp, "hijack")
        os.makedirs(os.path.join(hijack, "parent-control-evidence",
                                 "ctl-7-a"), mode=0o700)
        os.rename(root, os.path.join(self.tmp, "moved-aside"))
        os.symlink(hijack, root)
        ev.write_attempt_record(pc.build_attempt_record(
            run_id="ctl-7-a",
            signed=pc.build_control_request(
                credential=synthetic_credential(), account_id=ACCOUNT,
                run_id="ctl-7-a", amz_date=AMZ_DATE)))
        self.assertEqual(
            os.listdir(os.path.join(hijack, "parent-control-evidence",
                                    "ctl-7-a")), [])
        moved = os.path.join(self.tmp, "moved-aside",
                             "parent-control-evidence", "ctl-7-a")
        self.assertIn(pc.ATTEMPT_RECORD_FILENAME, os.listdir(moved))

    def test_child_directory_symlinks_are_refused(self):
        root = self._c(".local", "state", "bible-pal-parent-control")
        os.makedirs(root, mode=0o700)
        os.makedirs(os.path.join(self.tmp, "elsewhere2"), mode=0o700)
        os.symlink(os.path.join(self.tmp, "elsewhere2"),
                   os.path.join(root, "parent-control-evidence"))
        with SandboxHome(self.home):
            with self.assertRaises(pc.ParentControlRefused):
                pc.ParentControlEvidence.at_live_root("ctl-8-a")


class SoleOrchestrationPathTests(unittest.TestCase):
    """Codex round-2 MEDIUM 2: exactly ONE live-capable workflow."""

    def test_D_perform_control_is_gone(self):
        self.assertFalse(hasattr(pc, "perform_control"))

    def test_E_no_second_whole_workflow_api_exists(self):
        """Any module-level callable taking a credential AND driving a
        request would be a second live path, whatever it is named."""
        import inspect
        offenders = []
        for name, obj in vars(pc).items():
            if not inspect.isfunction(obj) or name == "run_control":
                continue
            params = set(inspect.signature(obj).parameters)
            if "credential" in params and (
                    "connection_factory" in params
                    or "evidence_root" in params):
                offenders.append(name)
        self.assertEqual(offenders, [])

    def test_F_cli_execute_reaches_only_run_control(self):
        import ast
        with open(pc.__file__, encoding="utf-8") as fh:
            source = fh.read()
        main = next(n for n in ast.parse(source).body
                    if isinstance(n, ast.FunctionDef) and n.name == "main")
        called = {n.func.id for n in ast.walk(main)
                  if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertIn("run_control", called)
        self.assertNotIn("live_connection_factory", called)
        self.assertEqual(source.count("live_connection_factory"), 2)

    def test_no_env_var_or_alias_selects_another_path(self):
        for var in ("PARENT_CONTROL_MODE", "R2_ORCHESTRATOR",
                    "PARENT_CONTROL_ROOT"):
            os.environ[var] = "anything"
            self.addCleanup(os.environ.pop, var, None)
        self.assertFalse(pc.build_parser().parse_args(["--plan"]).execute)


class AttemptJournalTests(unittest.TestCase):
    """Codex round-2 MEDIUM 3: no request without a durable marker."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def _run_dir(self, run_id):
        return os.path.join(self.tmp, "home", ".local", "state",
                            "bible-pal-parent-control",
                            "parent-control-evidence", run_id)

    def test_G_marker_exists_before_the_request_is_made(self):
        outer = self

        class WatchingConnection(FakeConnection):
            def request(self, *a, **k):
                seen.append(sorted(os.listdir(
                    outer._run_dir("ctl-5-a"))))
                return FakeConnection.request(self, *a, **k)

        seen = []
        sandbox_run(self.tmp, WatchingConnection(), run_id="ctl-5-a")
        self.assertEqual(len(seen), 1)
        self.assertIn(pc.ATTEMPT_RECORD_FILENAME, seen[0])
        self.assertIn(pc.ATTEMPT_ANCHOR_FILENAME, seen[0])

    def test_G_marker_content_and_anchor_verify(self):
        sandbox_run(self.tmp, FakeConnection(), run_id="ctl-5-b")
        run_dir = self._run_dir("ctl-5-b")
        with open(os.path.join(run_dir, pc.ATTEMPT_RECORD_FILENAME),
                  "rb") as fh:
            raw = fh.read()
        record = json.loads(raw)
        self.assertEqual(record["record_kind"],
                         "PARENT_CONTROL_ATTEMPT_RECORD")
        self.assertIs(record["request_may_have_been_attempted"], True)
        self.assertIs(record["session_token_present"], False)
        self.assertIs(record["x_amz_security_token_present"], False)
        self.assertEqual(record["body_sha256"], pc.D2_BODY_SHA256)
        self.assertEqual(set(record), pc.ATTEMPT_RECORD_FIELDS)
        with open(os.path.join(run_dir, pc.ATTEMPT_ANCHOR_FILENAME),
                  encoding="utf-8") as fh:
            self.assertEqual(fh.read().strip(),
                             hashlib.sha256(raw).hexdigest())
        for name in (pc.ATTEMPT_RECORD_FILENAME, pc.ATTEMPT_ANCHOR_FILENAME):
            mode = stat.S_IMODE(os.lstat(os.path.join(run_dir, name)).st_mode)
            self.assertEqual(mode & 0o077, 0)

    def test_H_marker_write_failure_means_zero_requests(self):
        conn = FakeConnection()
        transport = pc.OneShotTransport(endpoint_host="h",
                                        connection_factory=lambda h: conn)
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-5-c", amz_date=AMZ_DATE)

        def failing_journal():
            raise RuntimeError("journal unavailable")

        with self.assertRaises(RuntimeError):
            transport.send_once(signed, on_attempt_boundary=failing_journal)
        self.assertEqual(conn.requests, [])
        self.assertTrue(conn.closed)

    def test_H_a_factory_failure_never_writes_a_marker(self):
        """A connection that never materialised must not leave evidence
        implying a request may have occurred."""
        calls = []

        def bad_factory(host):
            raise RuntimeError("no connection")

        transport = pc.OneShotTransport(endpoint_host="h",
                                        connection_factory=bad_factory)
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-5-d", amz_date=AMZ_DATE)
        outcome = transport.send_once(
            signed, on_attempt_boundary=lambda: calls.append(1))
        self.assertEqual(outcome.failure_category, "RuntimeError")
        self.assertEqual(calls, [])

    def test_I_J_K_L_confidentiality_rejection_after_the_request(self):
        secret = "AlphaBetaGammaDeltaThetaValue"
        env = write_env(self.tmp,
                        "R2_ACCESS_KEY_ID=%s\nR2_SECRET_ACCESS_KEY=%s\n"
                        % (FAKE_AK, secret))
        conn = FakeConnection(FakeResponse(
            400, [("cf-ray", "Alpha-Beta-Gamma-Delta-Theta-Value")],
            b"<Error><Code>InvalidArgument</Code></Error>"))
        with self.assertRaises(pc.ConfidentialityWithheld):
            sandbox_run(self.tmp, conn, run_id="ctl-6-a",
                        gates_kwargs={"creds": env})
        self.assertEqual(len(conn.requests), 1)              # L
        run_dir = self._run_dir("ctl-6-a")
        names = sorted(os.listdir(run_dir))
        self.assertIn(pc.ATTEMPT_RECORD_FILENAME, names)     # I
        self.assertIn(pc.TERMINAL_RECORD_FILENAME, names)    # J
        self.assertNotIn("parent_control_record.json", names)
        with open(os.path.join(run_dir, pc.TERMINAL_RECORD_FILENAME),
                  encoding="utf-8") as fh:
            terminal = json.load(fh)
        self.assertEqual(terminal["terminal_category"],
                         "RESULT_WITHHELD_FOR_CONFIDENTIALITY")
        self.assertEqual(set(terminal), pc.TERMINAL_RECORD_FIELDS)
        self.assertEqual(terminal["http_status"], 400)
        for name in names:                                   # K
            with open(os.path.join(run_dir, name), encoding="utf-8") as fh:
                blob = fh.read()
            self.assertNotIn("Alpha", blob)
            self.assertNotIn("cf_ray", blob)

    def test_K_cli_prints_a_generic_refusal_with_no_traceback(self):
        import contextlib
        import io
        secret = "AlphaBetaGammaDeltaThetaValue"
        env = write_env(self.tmp,
                        "R2_ACCESS_KEY_ID=%s\nR2_SECRET_ACCESS_KEY=%s\n"
                        % (FAKE_AK, secret))
        conn = FakeConnection(FakeResponse(
            400, [("cf-ray", "Alpha-Beta-Gamma-Delta-Theta-Value")], b""))
        home = os.path.join(self.tmp, "home")
        os.makedirs(home, exist_ok=True)
        out, err = io.StringIO(), io.StringIO()
        with SandboxHome(home):
            saved = pc.live_connection_factory
            pc.live_connection_factory = factory_for(conn)
            try:
                with contextlib.redirect_stdout(out), \
                        contextlib.redirect_stderr(err):
                    rc = pc.main([
                        "--execute", "--authorized-by-adam",
                        "--confirm", CONFIRM,
                        "--bucket", "bible-pal-cas-probe",
                        "--account-id", ACCOUNT,
                        "--credentials-file", env,
                        "--evidence-root", pc.canonical_evidence_root()])
            finally:
                pc.live_connection_factory = saved
        self.assertEqual(rc, pc.EXIT_REFUSED)
        combined = out.getvalue() + err.getvalue()
        self.assertIn("confidentiality boundary", combined)
        self.assertNotIn("Alpha", combined)
        self.assertNotIn("Traceback", combined)

    def test_M_no_retry_after_a_transport_failure(self):
        conn = FakeConnection(raise_on_request=OSError("boom"))
        sandbox_run(self.tmp, conn, run_id="ctl-6-b")
        self.assertEqual(len(conn.requests), 1)

    def test_concurrent_sends_still_allow_at_most_one(self):
        import threading
        conn = FakeConnection()
        transport = pc.OneShotTransport(endpoint_host="h",
                                        connection_factory=lambda h: conn)
        signed = pc.build_control_request(
            credential=synthetic_credential(), account_id=ACCOUNT,
            run_id="ctl-6-c", amz_date=AMZ_DATE)
        errors = []

        def go():
            try:
                transport.send_once(signed)
            except Exception as exc:              # noqa: BLE001
                errors.append(type(exc).__name__)

        threads = [threading.Thread(target=go) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(conn.requests), 1)
        self.assertEqual(len(errors), 7)


class DecoderBoundTests(unittest.TestCase):
    """Codex round-2 LOW 1: cover the demonstrated four-layer case and
    stay FINITE."""

    SECRET = "AlphaBetaGammaDeltaThetaValue"

    def _nested(self, layers):
        text = "Alpha%42etaGammaDeltaThetaValue"
        for _ in range(layers - 1):
            text = text.replace("%", "%25", 1)
        return text

    def test_N_one_through_max_layers_are_rejected(self):
        for layers in range(1, pc._MAX_DECODE_ROUNDS + 1):
            with self.subTest(layers=layers):
                with self.assertRaises((probe.EvidenceValidationError,
                                        pc.SafetyBarrierTripped)):
                    pc.assert_no_transformed_secret(
                        {"cf_ray": self._nested(layers)},
                        (self.SECRET,), "test")

    def test_N_the_bound_is_deliberate_and_documented(self):
        beyond = self._nested(pc._MAX_DECODE_ROUNDS + 1)
        self.assertIn("%", pc.deterministic_decode(beyond))
        self.assertEqual(pc._MAX_DECODE_ROUNDS, 5)
        with open(pc.__file__, encoding="utf-8") as fh:
            self.assertIn("DELIBERATELY FINITE", fh.read())


class LiveRootGuardTests(unittest.TestCase):
    """Codex round-2 LOW 5: catch an ATTEMPT, not merely a surviving
    directory."""

    def test_O_guard_records_an_attempt_even_if_deleted_afterwards(self):
        before = len(LIVE_ROOT_ATTEMPTS)
        try:
            with self.assertRaises(AssertionError):
                pc.open_live_evidence_root()      # REAL root, unsandboxed
            self.assertEqual(len(LIVE_ROOT_ATTEMPTS), before + 1)
        finally:
            del LIVE_ROOT_ATTEMPTS[before:]
        self.assertFalse(os.path.exists(REAL_LIVE_ROOT))

    def test_O_sandboxed_roots_still_work(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = os.path.join(tmp.name, "home")
        os.makedirs(home)
        with SandboxHome(home):
            fd = pc.open_live_evidence_root()
        os.close(fd)


class _SyscallTrace:
    """Record mkdir / directory-fsync / file-fsync in real order.

    Inodes are captured AT the moment of the call, because fd integers are
    recycled and a post-hoc lookup would mislabel later events.
    """

    def __init__(self):
        self.events = []

    def __enter__(self):
        self._mkdir, self._fsync = os.mkdir, os.fsync

        def tr_mkdir(name, mode=0o777, *, dir_fd=None):
            result = self._mkdir(name, mode, dir_fd=dir_fd)
            parent = os.fstat(dir_fd).st_ino if dir_fd is not None else None
            self.events.append(("mkdir", name, parent))
            return result

        def tr_fsync(fd):
            st = os.fstat(fd)
            kind = "fsync-dir" if stat.S_ISDIR(st.st_mode) else "fsync-file"
            self.events.append((kind, None, st.st_ino))
            return self._fsync(fd)

        os.mkdir, os.fsync = tr_mkdir, tr_fsync
        return self

    def __exit__(self, *exc):
        os.mkdir, os.fsync = self._mkdir, self._fsync
        return False

    def mark(self, label):
        self.events.append((label, None, None))

    def labelled(self, inode_names):
        out = []
        for op, name, inode in self.events:
            if op == "mkdir":
                out.append(("mkdir", name, inode_names.get(inode, "?")))
            elif op.startswith("fsync"):
                out.append((op, inode_names.get(inode, "?"), None))
            else:
                out.append((op, None, None))
        return out


class _FsyncFailsOn:
    """Make `os.fsync` fail for one specific directory, by inode."""

    def __init__(self, path):
        self.inode = os.stat(path).st_ino
        self.hits = 0

    def __enter__(self):
        self._fsync = os.fsync

        def tr(fd):
            if os.fstat(fd).st_ino == self.inode:
                self.hits += 1
                raise OSError(5, "injected fsync failure")
            return self._fsync(fd)

        os.fsync = tr
        return self

    def __exit__(self, *exc):
        os.fsync = self._fsync
        return False


class DirectoryEntryDurabilityTests(unittest.TestCase):
    """Codex round-3 MEDIUM 3: a created directory ENTRY is only durable
    once its PARENT has been fsynced."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home, exist_ok=True)
        self.addCleanup(self._tmp.cleanup)

    def _paths(self):
        root = os.path.join(self.home, ".local", "state",
                            "bible-pal-parent-control")
        return {
            "HOME": self.home,
            ".local": os.path.join(self.home, ".local"),
            "state": os.path.join(self.home, ".local", "state"),
            "root": root,
            "evidence": os.path.join(root, "parent-control-evidence"),
            "anchors": os.path.join(root, "parent-control-anchors"),
        }

    def _prebuild(self, upto):
        """Create the hierarchy through `upto` so the NEXT component is
        the only fresh one."""
        order = ["HOME", ".local", "state", "root", "evidence", "anchors"]
        paths = self._paths()
        for name in order[:order.index(upto) + 1]:
            os.makedirs(paths[name], mode=0o700, exist_ok=True)
        return paths

    def _run(self, conn, run_id="ctl-10-a"):
        return sandbox_run(self.tmp, conn, run_id=run_id)

    # ── G: the full fresh-hierarchy ordered trace ───────────────────────

    def test_G_fresh_hierarchy_order_is_create_then_fsync_parent(self):
        conn = FakeConnection()

        with _SyscallTrace() as trace:
            class Marking(FakeConnection):
                def request(inner, *a, **k):
                    trace.mark("conn.request")
                    return FakeConnection.request(inner, *a, **k)

            marking = Marking()
            self._run(marking, run_id="ctl-17-a")
        paths = self._paths()
        paths["run"] = os.path.join(paths["evidence"], "ctl-17-a")
        names = {os.stat(p).st_ino: n for n, p in paths.items()}
        events = trace.labelled(names)

        # Every mkdir is IMMEDIATELY followed by an fsync of its parent.
        for index, (op, name, parent) in enumerate(events):
            if op != "mkdir":
                continue
            nxt = events[index + 1]
            self.assertEqual(nxt[0], "fsync-dir",
                             f"{name!r} was created without a parent fsync")
            self.assertEqual(nxt[1], parent,
                             f"{name!r}'s fsync targeted {nxt[1]}, not "
                             f"its parent {parent}")

        flat = [(op, name) for op, name, _ in events]
        request_at = flat.index(("conn.request", None))
        before = flat[:request_at]

        # The whole hierarchy chain is created AND persisted before the
        # request. `mkdir` records the real directory name; the fsync
        # records the parent it was created in.
        created_before = [(n, p) for o, n, p in events[:request_at]
                          if o == "mkdir"]
        self.assertEqual(created_before, [
            (".local", "HOME"),
            ("state", ".local"),
            ("bible-pal-parent-control", "state"),
            ("parent-control-evidence", "root"),
            ("parent-control-anchors", "root"),
            ("ctl-17-a", "evidence"),
        ])
        for parent in ("HOME", ".local", "state", "root", "evidence"):
            self.assertIn(("fsync-dir", parent), before,
                          f"{parent} was not fsynced before the request")
        # Both attempt files were fsynced, plus the run directory.
        self.assertGreaterEqual(
            len([1 for op, _ in before if op == "fsync-file"]), 2)
        self.assertIn(("fsync-dir", "run"), before)
        self.assertEqual(len(marking.requests), 1)

    # ── H: an existing hierarchy needs no redundant parent fsyncs ───────

    def test_H_existing_hierarchy_only_fsyncs_the_new_run_parent(self):
        paths = self._prebuild("anchors")
        with _SyscallTrace() as trace:
            self._run(FakeConnection(), run_id="ctl-18-b")
        names = {os.stat(p).st_ino: n for n, p in paths.items()}
        names[os.stat(os.path.join(paths["evidence"],
                                   "ctl-18-b")).st_ino] = "run"
        events = trace.labelled(names)
        made = [n for op, n, _ in events if op == "mkdir"]
        self.assertEqual(made, ["ctl-18-b"])       # only the run is new
        # Look only at the pre-request hierarchy phase: everything from
        # the first file fsync onward belongs to writing evidence files,
        # whose own directory fsyncs are expected and unrelated.
        kinds = [op for op, _, _ in events]
        end = kinds.index("fsync-file") if "fsync-file" in kinds else len(kinds)
        hierarchy = [n for op, n, _ in events[:end] if op == "fsync-dir"]
        # The new run's parent MUST still be persisted...
        self.assertEqual(hierarchy, ["evidence"])
        # ...and no pre-existing ancestor is needlessly fsynced.
        for stale in ("HOME", ".local", "state", "root", "anchors"):
            self.assertNotIn(stale, hierarchy)

    # ── A–F: parent-fsync failure means ZERO requests ───────────────────

    def _assert_zero_requests_when_fsync_fails(self, prebuild_upto,
                                               failing_dir, run_id):
        paths = self._prebuild(prebuild_upto)
        conn = FakeConnection()
        with _FsyncFailsOn(paths[failing_dir]) as injected:
            with self.assertRaises(OSError):
                self._run(conn, run_id=run_id)
        self.assertGreaterEqual(injected.hits, 1)
        self.assertEqual(conn.requests, [],
                         "a request was made despite a durability failure")

    def test_A_fresh_dot_local_parent_fsync_failure(self):
        self._assert_zero_requests_when_fsync_fails("HOME", "HOME", "ctl-11-a")

    def test_B_fresh_state_parent_fsync_failure(self):
        self._assert_zero_requests_when_fsync_fails(".local", ".local",
                                                    "ctl-12-b")

    def test_C_fresh_root_parent_fsync_failure(self):
        self._assert_zero_requests_when_fsync_fails("state", "state",
                                                    "ctl-13-c")

    def test_D_fresh_evidence_dir_parent_fsync_failure(self):
        self._assert_zero_requests_when_fsync_fails("root", "root", "ctl-14-d")

    def test_E_fresh_anchors_dir_parent_fsync_failure(self):
        """The anchors directory is created in the pre-request path, so
        its parent fsync failing must also stop everything."""
        paths = self._prebuild("evidence")
        conn = FakeConnection()
        with _FsyncFailsOn(paths["root"]) as injected:
            with self.assertRaises(OSError):
                self._run(conn, run_id="ctl-15-e")
        self.assertGreaterEqual(injected.hits, 1)
        self.assertEqual(conn.requests, [])

    def test_F_run_directory_parent_fsync_failure(self):
        """The always-fresh case: parent-control-evidence must be fsynced
        after the run directory is created, and a failure is fatal."""
        self._assert_zero_requests_when_fsync_fails("anchors", "evidence",
                                                    "ctl-16-f")

    def test_no_partial_run_is_left_usable_after_a_durability_failure(self):
        paths = self._prebuild("anchors")
        conn = FakeConnection()
        with _FsyncFailsOn(paths["evidence"]):
            with self.assertRaises(OSError):
                self._run(conn, run_id="ctl-19-c")
        run_dir = os.path.join(paths["evidence"], "ctl-19-c")
        # The directory may exist, but no attempt artifact was written and
        # no request was made.
        if os.path.exists(run_dir):
            self.assertEqual(os.listdir(run_dir), [])
        self.assertEqual(conn.requests, [])

    def test_the_durability_scope_is_documented_not_overclaimed(self):
        with open(pc.__file__, encoding="utf-8") as fh:
            source = fh.read()
        self.assertIn("F_FULLFSYNC", source)
        self.assertIn("NOT power-loss media durability", source)
        self.assertNotIn("fcntl.F_FULLFSYNC", source)


if __name__ == "__main__":   # pragma: no cover
    unittest.main(verbosity=2)
