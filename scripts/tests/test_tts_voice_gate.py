#!/usr/bin/env python3
"""Tests for scripts/story_factory/tts_voice_gate.py.

Every voices.json / schema fixture is synthetic and written inside a
tempfile.TemporaryDirectory; the real registry files are used only by the two
explicitly-labelled live-corpus tests, read-only. No network, no ElevenLabs.

Run:
    python3 -m unittest scripts.tests.test_tts_voice_gate -v
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))

from story_factory.tts_voice_gate import (  # noqa: E402
    ResolvedTtsVoice, TtsVoiceGateError, resolve_new_story_tts_voice,
)

GOOD_KEY = "VOICE_JAMES_HUSKY"       # approved, literal mapping in fixtures
OTHER_KEY = "VOICE_BRADFORD"         # second approved narrator
ENV_KEY = "VOICE_CHARLOTTE_V3"       # env-placeholder narrator
BANNED_KEY = "VOICE_JOHN_DOE"        # banned + legacy-audio-only
GOOD_ID = "EkK5I93UQWFDigLMpZcX"
OTHER_ID = "N2lVS1w4EtoT3dr4eOWO"


def fixture_files(tmp, *, voices=None, enum=None, legacy_only=None):
    """Write a synthetic voices.json + meta schema; return their paths."""
    voices_doc = {
        "_legacyAudioOnlyVoices": {"voices": legacy_only if legacy_only is not None
                                   else [BANNED_KEY, "VOICE_CHRIS_DEFAULT"]},
        "voices": voices if voices is not None else [
            {"voiceKey": GOOD_KEY, "elevenLabsId": GOOD_ID,
             "audience": ["adult", "kid"]},
            {"voiceKey": OTHER_KEY, "elevenLabsId": OTHER_ID,
             "audience": ["adult"]},
            {"voiceKey": ENV_KEY,
             "elevenLabsId": "_LOAD_FROM_ENV_VOICE_CHARLOTTE_V3",
             "audience": ["adult"]},
        ],
        # palVoices deliberately contains a same-named trap: the gate must
        # never consult the conversation pool.
        "palVoices": [{"voiceKey": GOOD_KEY, "elevenLabsId": "PALPOOLPALPOOLPALP00"}],
    }
    schema_doc = {"properties": {"storyVoiceKey": {
        "enum": enum if enum is not None
        else [GOOD_KEY, OTHER_KEY, ENV_KEY, BANNED_KEY]}}}
    vp = os.path.join(tmp, "voices.json")
    sp = os.path.join(tmp, "meta.schema.json")
    json.dump(voices_doc, open(vp, "w"))
    json.dump(schema_doc, open(sp, "w"))
    return vp, sp


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.voices, self.schema = fixture_files(self._tmp.name)

    def resolve(self, meta, **kw):
        kw.setdefault("voices_path", self.voices)
        kw.setdefault("schema_path", self.schema)
        kw.setdefault("env", {})
        return resolve_new_story_tts_voice(meta, **kw)

    def refuse(self, meta, fragment, **kw):
        with self.assertRaises(TtsVoiceGateError) as ctx:
            self.resolve(meta, **kw)
        self.assertIn(fragment, str(ctx.exception))
        return ctx.exception


class TestSafeNewStory(Base):

    def test_only_story_voice_key_passes(self):
        r = self.resolve({"storyVoiceKey": GOOD_KEY})
        self.assertIsInstance(r, ResolvedTtsVoice)
        self.assertEqual(r.story_voice_key, GOOD_KEY)
        self.assertEqual(r.eleven_labs_id, GOOD_ID)
        self.assertEqual(r.mapping_source, "voices.json")
        self.assertFalse(r.legacy_field_equal)

    def test_both_fields_equal_tolerated_and_flagged(self):
        """Pinned compatibility contract: an equal legacy duplicate does not
        block, but the result flags it so the controller can report drift."""
        r = self.resolve({"storyVoiceKey": GOOD_KEY, "voiceKey": GOOD_KEY})
        self.assertEqual(r.story_voice_key, GOOD_KEY)
        self.assertTrue(r.legacy_field_equal)

    def test_expected_narrator_match_passes(self):
        r = self.resolve({"storyVoiceKey": GOOD_KEY},
                         expected_story_voice_key=GOOD_KEY)
        self.assertEqual(r.story_voice_key, GOOD_KEY)

    def test_kid_story_with_kid_audience_passes(self):
        r = self.resolve({"storyVoiceKey": GOOD_KEY, "kidFriendly": True})
        self.assertEqual(r.eleven_labs_id, GOOD_ID)


class TestConflicts(Base):

    def test_two_different_approved_fields_refused(self):
        """The exact hazard: legacy voiceKey must never out-vote storyVoiceKey
        (the shell's legacy branch would have picked OTHER_KEY here)."""
        self.refuse({"storyVoiceKey": GOOD_KEY, "voiceKey": OTHER_KEY},
                    "conflicts with storyVoiceKey")

    def test_banned_legacy_voice_key_refused(self):
        self.refuse({"storyVoiceKey": GOOD_KEY, "voiceKey": BANNED_KEY},
                    "conflicts with storyVoiceKey")

    def test_expected_narrator_mismatch_refused(self):
        self.refuse({"storyVoiceKey": GOOD_KEY},
                    "does not match", expected_story_voice_key=OTHER_KEY)

    def test_legacy_voice_keys_map_refused(self):
        self.refuse({"storyVoiceKey": GOOD_KEY,
                     "voiceKeys": {"short": OTHER_KEY}},
                    "voiceKeys{} per-length map")

    def test_reflection_voice_key_refused(self):
        self.refuse({"storyVoiceKey": GOOD_KEY,
                     "reflectionVoiceKey": GOOD_KEY},
                    "reflectionVoiceKey")


class TestInvalidNarrator(Base):

    def test_banned_story_voice_key_refused(self):
        self.refuse({"storyVoiceKey": BANNED_KEY}, "rejected by registry")

    def test_unknown_narrator_refused(self):
        self.refuse({"storyVoiceKey": "VOICE_NOT_REAL"}, "rejected by registry")

    def test_legacy_audio_only_narrator_refused(self):
        """Even if a legacy-only voice were approved and mapped, new authoring
        must refuse it. Build a fixture where it would otherwise resolve."""
        voices = [{"voiceKey": OTHER_KEY, "elevenLabsId": OTHER_ID,
                   "audience": ["adult"]}]
        vp, sp = fixture_files(self._tmp.name, voices=voices,
                               enum=[OTHER_KEY], legacy_only=[OTHER_KEY])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": OTHER_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("legacy-audio-only", str(ctx.exception))

    def test_missing_story_voice_key_refused(self):
        self.refuse({}, "missing")
        self.refuse({"voiceKey": GOOD_KEY}, "missing")  # legacy alone never suffices

    def test_empty_story_voice_key_refused(self):
        self.refuse({"storyVoiceKey": "   "}, "empty")
        self.refuse({"storyVoiceKey": None}, "missing")

    def test_schema_missing_narrator_refused(self):
        vp, sp = fixture_files(self._tmp.name, enum=[OTHER_KEY])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("not in the meta.schema.json enum", str(ctx.exception))


class TestMapping(Base):

    def test_no_active_mapping_refused(self):
        vp, sp = fixture_files(
            self._tmp.name,
            voices=[{"voiceKey": OTHER_KEY, "elevenLabsId": OTHER_ID,
                     "audience": ["adult"]}])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("no active voices.json mapping", str(ctx.exception))

    def test_pal_pool_never_satisfies_mapping(self):
        """GOOD_KEY exists in palVoices in every fixture; with it removed from
        the narrator pool, resolution must fail — the conversation pool is not
        a narrator source."""
        vp, sp = fixture_files(
            self._tmp.name,
            voices=[{"voiceKey": OTHER_KEY, "elevenLabsId": OTHER_ID,
                     "audience": ["adult"]}])
        with self.assertRaises(TtsVoiceGateError):
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})

    def test_duplicate_active_mapping_refused(self):
        vp, sp = fixture_files(
            self._tmp.name,
            voices=[{"voiceKey": GOOD_KEY, "elevenLabsId": GOOD_ID,
                     "audience": ["adult"]},
                    {"voiceKey": GOOD_KEY, "elevenLabsId": OTHER_ID,
                     "audience": ["adult"]}])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("ambiguous", str(ctx.exception))

    def test_empty_eleven_labs_id_refused(self):
        vp, sp = fixture_files(
            self._tmp.name,
            voices=[{"voiceKey": GOOD_KEY, "elevenLabsId": "  ",
                     "audience": ["adult"]}])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("empty ElevenLabs ID", str(ctx.exception))

    def test_shared_eleven_labs_id_refused(self):
        vp, sp = fixture_files(
            self._tmp.name,
            voices=[{"voiceKey": GOOD_KEY, "elevenLabsId": GOOD_ID,
                     "audience": ["adult"]},
                    {"voiceKey": OTHER_KEY, "elevenLabsId": GOOD_ID,
                     "audience": ["adult"]}])
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice({"storyVoiceKey": GOOD_KEY},
                                        voices_path=vp, schema_path=sp, env={})
        self.assertIn("also mapped", str(ctx.exception))

    def test_kid_story_with_adult_only_voice_refused(self):
        self.refuse({"storyVoiceKey": OTHER_KEY, "kidFriendly": True},
                    "not kid-audience eligible")


class TestEnvPlaceholder(Base):

    def test_env_mapping_resolves_with_material_present(self):
        r = self.resolve({"storyVoiceKey": ENV_KEY},
                         env={"VOICE_CHARLOTTE_V3": "A" * 20})
        self.assertEqual(r.eleven_labs_id, "A" * 20)
        self.assertEqual(r.mapping_source, "voices.json+env:VOICE_CHARLOTTE_V3")

    def test_env_mapping_missing_refused_without_secret_leak(self):
        exc = self.refuse({"storyVoiceKey": ENV_KEY},
                          "missing or empty", env={})
        self.assertIn("VOICE_CHARLOTTE_V3", str(exc))  # names the VAR only

    def test_env_mapping_malformed_refused_without_echoing_value(self):
        secret = "hunter2-not-a-real-id"
        exc = self.refuse({"storyVoiceKey": ENV_KEY},
                          "does not look like",
                          env={"VOICE_CHARLOTTE_V3": secret})
        self.assertNotIn(secret, str(exc))


class TestZeroTtsOnFailure(Base):
    """Integration-style proof: when the gate refuses, the TTS collaborator is
    invoked ZERO times."""

    def _pipeline(self, meta, tts):
        """Minimal model of the designated new-story route: gate, then TTS."""
        result = self.resolve(meta)
        tts(result.story_voice_key, result.eleven_labs_id)
        return result

    def test_gate_failure_means_zero_tts_calls(self):
        tts = mock.Mock()
        bad_metas = [
            {},                                                    # missing
            {"storyVoiceKey": BANNED_KEY},                         # banned
            {"storyVoiceKey": GOOD_KEY, "voiceKey": OTHER_KEY},    # conflict
            {"storyVoiceKey": "VOICE_NOT_REAL"},                   # unknown
        ]
        for meta in bad_metas:
            with self.subTest(meta=meta):
                with self.assertRaises(TtsVoiceGateError):
                    self._pipeline(meta, tts)
        self.assertEqual(tts.call_count, 0)

    def test_gate_success_reaches_tts_exactly_once(self):
        tts = mock.Mock()
        self._pipeline({"storyVoiceKey": GOOD_KEY}, tts)
        tts.assert_called_once_with(GOOD_KEY, GOOD_ID)



class TestLiveCorpusCompatibility(unittest.TestCase):
    """Read-only checks against the REAL repository data."""

    def test_legacy_conflict_story_1005_not_reinterpreted(self):
        """1005: storyVoiceKey=VOICE_CHRIS_DEFAULT (banned), legacy
        voiceKey=VOICE_JAMES_HUSKY. Historical compatibility mode must keep
        resolving the legacy field; the new gate must refuse — neither path
        silently revoices it."""
        meta_path = os.path.join(REPO_ROOT, "assets", "stories", "traditional",
                                 "1005", "meta_1005.json")
        if not os.path.exists(meta_path):
            self.skipTest("story 1005 not present in this worktree")
        meta = json.load(open(meta_path, encoding="utf-8"))
        self.assertEqual(meta.get("voiceKey"), "VOICE_JAMES_HUSKY")
        with self.assertRaises(TtsVoiceGateError):
            resolve_new_story_tts_voice(meta, env={})
        # Legacy shell precedence for historical stories is untouched:
        script = open(os.path.join(REPO_ROOT, "scripts",
                                   "generate_opus_audio.sh")).read()
        self.assertIn(".voiceKey // .storyVoiceKey // empty", script)

    def test_legacy_divergent_story_1018_refused_by_gate_only(self):
        meta_path = os.path.join(REPO_ROOT, "assets", "stories", "traditional",
                                 "1018", "meta_1018.json")
        if not os.path.exists(meta_path):
            self.skipTest("story 1018 not present in this worktree")
        meta = json.load(open(meta_path, encoding="utf-8"))
        self.assertNotEqual(meta.get("voiceKey"), meta.get("storyVoiceKey"))
        with self.assertRaises(TtsVoiceGateError) as ctx:
            resolve_new_story_tts_voice(meta, env={})
        self.assertIn("conflicts", str(ctx.exception))

    def test_real_new_style_meta_resolves(self):
        """A clean modern meta (storyVoiceKey only) must pass against the real
        registry files, proving the gate works on production data."""
        meta_path = os.path.join(REPO_ROOT, "assets", "stories", "traditional",
                                 "1592", "meta_1592.json")
        if not os.path.exists(meta_path):
            self.skipTest("story 1592 not present in this worktree")
        meta = json.load(open(meta_path, encoding="utf-8"))
        r = resolve_new_story_tts_voice(meta, env={})
        self.assertEqual(r.story_voice_key, meta["storyVoiceKey"])
        self.assertTrue(r.eleven_labs_id)




# ---------------------------------------------------------------------------
# Shell route lockdown — hermetic sandbox with a PATH-jailed stub curl.
# NOT --dry-run: these prove the gate/lockdown themselves prevent network,
# not the dry-run flag. The stub curl logs every invocation and fabricates a
# 200 + >1KB body, so a run that legitimately reaches TTS succeeds without
# any real network and consumes zero credits.
# ---------------------------------------------------------------------------

STORY_TEXT = "And the word of the story was read aloud in the assembly.\n"


def build_shell_sandbox(tmp):
    """Copy the script + gate + registry + real voices/schema into an isolated
    PROJECT_ROOT so nothing touches the real worktree; return paths dict."""
    import shutil
    scripts = os.path.join(tmp, "scripts")
    sf = os.path.join(scripts, "story_factory")
    os.makedirs(sf)
    for rel in ("scripts/generate_opus_audio.sh",):
        shutil.copy(os.path.join(REPO_ROOT, rel), scripts)
    for rel in ("scripts/story_factory/tts_voice_gate.py",
                "scripts/story_factory/story_voice_registry.py"):
        shutil.copy(os.path.join(REPO_ROOT, rel), sf)
    os.makedirs(os.path.join(tmp, "server"))
    shutil.copy(os.path.join(REPO_ROOT, "server", "voices.json"),
                os.path.join(tmp, "server"))
    os.makedirs(os.path.join(tmp, "assets", "stories", "traditional"))
    os.makedirs(os.path.join(tmp, "assets", "stories", "creative"))
    shutil.copy(os.path.join(REPO_ROOT, "assets", "stories", "meta.schema.json"),
                os.path.join(tmp, "assets", "stories"))

    bin_dir = os.path.join(tmp, "bin")
    os.makedirs(bin_dir)
    curl_log = os.path.join(tmp, "curl_invocations.log")
    stub = os.path.join(bin_dir, "curl")
    with open(stub, "w") as fh:
        fh.write(f"""#!/usr/bin/env bash
# PATH-jailed stub curl: log ONE line per invocation (args %q-escaped so the
# multi-line JSON -d payload cannot split the record), write a fake >1KB body
# to -o, report 200.
{{ printf 'CURL_CALL'; printf ' %q' "$@"; printf '\n'; }} >> "{curl_log}"
out=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "-o" ]]; then out="$a"; fi
    prev="$a"
done
if [[ -n "$out" ]]; then head -c 2048 /dev/zero > "$out"; fi
printf '200'
""")
    os.chmod(stub, 0o755)
    return {
        "script": os.path.join(scripts, "generate_opus_audio.sh"),
        "root": tmp, "bin": bin_dir, "curl_log": curl_log,
        "stories": os.path.join(tmp, "assets", "stories", "traditional"),
    }


def add_sandbox_story(sb, sid, story_voice_key, *, banned=False):
    d = os.path.join(sb["stories"], str(sid))
    os.makedirs(d)
    json.dump({"storyId": sid, "mode": "traditional", "kidFriendly": False,
               "storyVoiceKey": story_voice_key},
              open(os.path.join(d, f"meta_{sid}.json"), "w"))
    with open(os.path.join(d, f"story_{sid}_traditional_web_short.txt"), "w") as fh:
        fh.write(STORY_TEXT)
    return d


def run_sandbox(sb, args, timeout=180):
    env = dict(os.environ,
               PATH=sb["bin"] + os.pathsep + os.environ.get("PATH", ""),
               ELEVENLABS_API_KEY="FAKE_TEST_KEY_NOT_REAL")
    return subprocess.run([sb["script"]] + args, capture_output=True,
                          text=True, timeout=timeout, env=env, cwd=sb["root"])


def curl_calls(sb):
    if not os.path.exists(sb["curl_log"]):
        return []
    return [ln for ln in open(sb["curl_log"]).read().splitlines()
            if ln.startswith("CURL_CALL")]


class TestShellRouteLockdown(unittest.TestCase):

    def sandbox(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return build_shell_sandbox(tmp.name)

    # -- A: retry bypass ----------------------------------------------------

    def test_new_authoring_with_retry_file_refused_zero_network(self):
        sb = self.sandbox()
        d = add_sandbox_story(sb, 3001, GOOD_KEY)
        retry = os.path.join(sb["root"], "failures.txt")
        text = os.path.join(d, "story_3001_traditional_web_short.txt")
        out_mp3 = os.path.join(d, "audio_3001_story_short.mp3")
        with open(retry, "w") as fh:
            fh.write(f"{out_mp3}|{text}|{GOOD_KEY}\n")
        proc = run_sandbox(sb, ["--new-authoring", "--retry-file", retry])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("mutually exclusive", proc.stderr)
        self.assertEqual(curl_calls(sb), [])                # zero network
        self.assertNotIn("Retrying:", proc.stdout)          # file not processed
        self.assertFalse(os.path.exists(out_mp3))           # no audio written

    def test_legacy_retry_file_mode_still_works(self):
        sb = self.sandbox()
        d = add_sandbox_story(sb, 1901, GOOD_KEY)
        retry = os.path.join(sb["root"], "failures.txt")
        text = os.path.join(d, "story_1901_traditional_web_short.txt")
        out_mp3 = os.path.join(d, "audio_1901_story_short.mp3")
        with open(retry, "w") as fh:
            fh.write(f"{out_mp3}|{text}|{GOOD_KEY}\n")
        proc = run_sandbox(sb, ["--retry-file", retry])
        self.assertIn("Retrying:", proc.stdout)
        self.assertEqual(len(curl_calls(sb)), 1)
        self.assertTrue(os.path.exists(out_mp3))

    # -- C: deliberate initialization ---------------------------------------

    def test_lockdown_is_not_an_unbound_variable_accident(self):
        sb = self.sandbox()
        retry = os.path.join(sb["root"], "failures.txt")
        open(retry, "w").write("")
        proc = run_sandbox(sb, ["--new-authoring", "--retry-file", retry])
        self.assertEqual(proc.returncode, 2)                # explicit refusal code
        self.assertNotIn("unbound variable", proc.stderr)
        self.assertIn("mutually exclusive", proc.stderr)
        script_src = open(sb["script"]).read()
        self.assertIn('NEW_AUTH_VOICE_ID=""', script_src)   # global init present

    # -- B: safe retry guidance ---------------------------------------------

    def test_new_authoring_failure_guidance_avoids_retry_file(self):
        sb = self.sandbox()
        add_sandbox_story(sb, 3002, BANNED_KEY)             # gate will refuse
        proc = run_sandbox(sb, ["--new-authoring", "--story", "3002"])
        self.assertNotEqual(proc.returncode, 0)
        combined = proc.stdout + proc.stderr
        self.assertIn("REFUSED", combined)
        self.assertNotIn("--retry-file", proc.stdout)       # no legacy advice
        self.assertIn("--new-authoring --expected-voice", proc.stdout)
        self.assertEqual(curl_calls(sb), [])
        self.assertNotIn(GOOD_ID, combined)                 # no ID exposure

    def test_legacy_failure_guidance_still_recommends_retry_file(self):
        sb = self.sandbox()
        d = add_sandbox_story(sb, 1902, "VOICE_NOT_MAPPED_ANYWHERE")
        proc = run_sandbox(sb, ["--story", "1902"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("--retry-file", proc.stdout)
        self.assertEqual(curl_calls(sb), [])

    # -- Test-quality fix + F: gate refusal alone prevents curl -------------

    def test_gate_refusal_prevents_curl_without_dry_run(self):
        """Replaces the hollow dry-run test: NON-dry-run, stub curl on PATH,
        banned narrator. Zero curl invocations proves the GATE is what stopped
        the network, not --dry-run."""
        sb = self.sandbox()
        add_sandbox_story(sb, 3003, BANNED_KEY)
        proc = run_sandbox(sb, ["--new-authoring", "--story", "3003"])
        self.assertIn("REFUSED", proc.stdout + proc.stderr)
        self.assertEqual(curl_calls(sb), [])

    def test_expected_mismatch_prevents_curl(self):
        sb = self.sandbox()
        add_sandbox_story(sb, 3004, GOOD_KEY)
        proc = run_sandbox(sb, ["--new-authoring",
                                "--expected-voice", OTHER_KEY,
                                "--story", "3004"])
        self.assertIn("REFUSED", proc.stdout + proc.stderr)
        self.assertEqual(curl_calls(sb), [])

    def test_valid_story_gated_voice_id_reaches_stub_curl(self):
        sb = self.sandbox()
        add_sandbox_story(sb, 3005, GOOD_KEY)
        proc = run_sandbox(sb, ["--new-authoring",
                                "--expected-voice", GOOD_KEY,
                                "--story", "3005"])
        calls = curl_calls(sb)
        self.assertEqual(len(calls), 1, msg=proc.stdout + proc.stderr)
        self.assertIn(f"text-to-speech/{GOOD_ID}", calls[0])
        self.assertEqual(proc.returncode, 0)


class TestGenerateAudioCampaignGuard(unittest.TestCase):
    """generate_audio.py must refuse campaign IDs 3000-3258 before metadata
    mutation and before any TTS/network path is reachable."""

    SCRIPT = os.path.join(REPO_ROOT, "scripts", "story_factory",
                          "generate_audio.py")

    def run_script(self, sid):
        # No ELEVENLABS_API_KEY supplied: if the guard did NOT fire first, the
        # run would still abort later — but with a different message, so the
        # assertions below genuinely locate the refusal point.
        env = {k: v for k, v in os.environ.items()
               if k != "ELEVENLABS_API_KEY"}
        return subprocess.run(
            [sys.executable, self.SCRIPT, "--story_id", str(sid),
             "--mode", "traditional"],
            capture_output=True, text=True, timeout=60, env=env, cwd=REPO_ROOT)

    def test_unit_boundaries(self):
        sf_dir = os.path.join(REPO_ROOT, "scripts", "story_factory")
        if sf_dir not in sys.path:
            sys.path.insert(0, sf_dir)   # generate_audio.py uses flat imports
        from generate_audio import CampaignRouteError, check_campaign_route
        for sid in (3000, 3129, 3258):
            with self.subTest(sid=sid):
                with self.assertRaises(CampaignRouteError):
                    check_campaign_route(sid)
        for sid in (2999, 3259):
            with self.subTest(sid=sid):
                check_campaign_route(sid)  # must not raise

    def test_campaign_ids_refused_before_metadata_or_network(self):
        for sid in (3000, 3129, 3258):
            with self.subTest(sid=sid):
                proc = self.run_script(sid)
                self.assertEqual(proc.returncode, 1)
                self.assertIn("campaign range", proc.stdout)
                # Proves refusal precedes directory/metadata/env handling:
                self.assertNotIn("story directory not found", proc.stdout)
                self.assertNotIn("ELEVENLABS_API_KEY", proc.stdout)

    def test_control_ids_not_rejected_by_campaign_guard(self):
        """2999 / 3259 pass the guard; they then fail on the missing story
        directory, which proves the guard did not reject them and no audio was
        attempted."""
        for sid in (2999, 3259):
            with self.subTest(sid=sid):
                proc = self.run_script(sid)
                self.assertNotIn("campaign range", proc.stdout)
                self.assertIn("story directory not found", proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
