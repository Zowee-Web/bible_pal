// Spec tests for Feature 2.0 — PAL pre-greeting opening layer audio.
//
// Background: the default voice (Ruth) was occasionally dropping the
// very-first-after-launch opening greeting because of an asymmetry in
// PalAudioService — non-default voices got two `setAsset` attempts per
// call (own voice, then cross-voice fallback to default), whereas the
// default voice got only one. The iOS audio session sometimes was not
// ready in time for that single attempt and failure was silent.
//
// These tests pin down the contracts that prevent the regression.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/core/pal_voice_registry.dart';
import 'package:bible_pal/features/pal/opening/pal_opening_lines.dart';
import 'package:bible_pal/services/pal_audio_service.dart';

void main() {
  final projectRoot = _findProjectRoot();
  final audioBase = '$projectRoot/assets/pal/audio';

  group('Feature 2.0 — PAL opening audio coverage', () {
    test('spec_pal_opening_audio_coverage_all_voices.succeeds', () {
      // Files where the missing-asset → cross-voice fallback to the
      // default voice's asset is the accepted graceful degradation.
      // Listed explicitly so any *new* missing file (a regression)
      // breaks the test.
      const acceptedCrossVoiceFallbacks = <String>{
        // Stillwater is missing OPENING_WEARY_04; PalAudioService falls
        // back to the default voice's (Ruth's) asset for this line.
        'VOICE_STILLWATER/OPENING_WEARY_04',
      };

      final missing = <String>[];
      for (final voice in PalVoiceRegistry.voices) {
        for (final line in palOpeningLines) {
          final relPath = '${voice.voiceKey}/${line.id}';
          final file = File('$audioBase/$relPath.mp3');
          if (!file.existsSync() || file.lengthSync() == 0) {
            if (!acceptedCrossVoiceFallbacks.contains(relPath)) {
              missing.add('$relPath.mp3');
            }
          }
        }
      }
      expect(missing, isEmpty,
          reason:
              'Missing PAL opening audio (excluding accepted cross-voice fallbacks): ${missing.join(', ')}');
    });

    test('spec_pal_opening_ruth_asset_coverage.succeeds', () {
      // Strict bundle-coverage audit for VOICE_RUTH_COMFORT.
      //
      // Ruth is the terminal node of the cross-voice fallback chain
      // (the default voice has no further voice to fall back to), so
      // a missing asset for her surfaces directly to the user as a
      // silent greeting. This test fails if ANY of the three
      // conditions below is violated for any of the 60 opening lines:
      //
      //   1. file exists at the expected pubspec-relative path
      //   2. file is non-empty
      //   3. file's parent directory is declared as a Flutter asset
      //      in pubspec.yaml (otherwise the file ships on disk in
      //      source but is not bundled into the iOS .app)
      //
      // The reason string lists every missing file by ID + which
      // condition failed, so a build-time failure pinpoints exactly
      // what is broken.

      // Condition 3: pubspec declares the Ruth asset directory.
      final pubspec = File('$projectRoot/pubspec.yaml').readAsStringSync();
      const ruthDir = 'assets/pal/audio/${PalVoiceRegistry.defaultVoiceKey}/';
      expect(
        pubspec.contains(ruthDir),
        isTrue,
        reason:
            'pubspec.yaml is missing an `assets:` entry for `$ruthDir`. '
            'Without that line, files in this directory ship in source '
            'but are NOT bundled into the iOS / Android app at build '
            'time, which produces a runtime PlayerException with '
            'duration_ms == null and resolved_source == "missing".',
      );

      // Conditions 1 + 2: every opening line ID has a non-empty
      // file at the expected location.
      final missing = <String>[];
      for (final line in palOpeningLines) {
        final relPath = '${PalVoiceRegistry.defaultVoiceKey}/${line.id}.mp3';
        final file = File('$audioBase/$relPath');
        if (!file.existsSync()) {
          missing.add('$relPath (file does not exist)');
          continue;
        }
        if (file.lengthSync() == 0) {
          missing.add('$relPath (file is 0 bytes)');
        }
      }
      expect(
        missing,
        isEmpty,
        reason: missing.isEmpty
            ? ''
            : 'Ruth (${PalVoiceRegistry.defaultVoiceKey}) is missing or '
                'has empty opening assets — expected all 60 ids from '
                'palOpeningLines:\n  - ${missing.join('\n  - ')}',
      );
    });
  });

  group('Feature 2.0 — PAL opening audio resolution contract', () {
    test('spec_pal_opening_ruth_missing_audio_falls_back.succeeds', () {
      // Static contract: when the default voice's asset is missing,
      // the resolution is `missing` with played=false and an
      // error_type set — caller must honor SPEC's text-only floor
      // (1800ms) instead of silently skipping the greeting.
      // (Live audio playback is platform-dependent and verified via
      // the coverage test above + the call-site source assertion in
      // the sequencing group.)
      final src = File(
              '$projectRoot/lib/services/pal_audio_service.dart')
          .readAsStringSync();
      // The fallback contract lives in playLineResolved: when the
      // default voice's secondary attempt fails, return a resolution
      // tagged 'missing' (or 'operation_stopped' for the iOS -11849
      // recovery path) with the error type.
      expect(src, contains('Future<PalAudioResolution> playLineResolved'),
          reason: 'playLineResolved is the resolution-aware entry point');
      expect(src, contains("'missing'"),
          reason:
              "missing branch must still emit source: 'missing' for true asset-load failures");
      expect(src, contains("'operation_stopped'"),
          reason:
              "iOS -11849 must surface as source: 'operation_stopped' (not 'missing')");
      expect(src, contains('e.runtimeType.toString()'),
          reason: 'failure path must record error_type for telemetry');
      // Symmetric retry: the default voice retries the same path
      // rather than falling out after a single setAsset attempt.
      // Strip whitespace so multi-line formatting does not break the
      // contract check.
      final compact = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(compact, contains('isDefault ? path'),
          reason:
              'default voice must retry same asset to match non-default voices\' two-attempt budget');
    });

    test('spec_pal_opening_audio_failure_not_silent.succeeds', () {
      // Failure must always surface to telemetry. We assert the call
      // site emits `pal_opening_audio_resolution` on every path —
      // success, retry, missing, and exception.
      final src = File(
              '$projectRoot/lib/features/main_menu/main_menu_screen.dart')
          .readAsStringSync();
      final start = src.indexOf(
          RegExp(r'Future<void> _startConversation\([^)]*\)'));
      expect(start, greaterThan(-1),
          reason: '_startConversation entry not found');
      // Find the segment for the opening flow only — bounded by the
      // transition to playingGreeting.
      final endMarker = src.indexOf('_VoiceFlowState.playingGreeting', start);
      expect(endMarker, greaterThan(start),
          reason: 'playingGreeting transition not found after opening flow');
      final segment = src.substring(start, endMarker);
      // Two emit sites: the normal try-block (covers asset / fallback /
      // missing) and the catch-block (covers exception path).
      final emits = 'pal_opening_audio_resolution'.allMatches(segment).length;
      expect(emits, greaterThanOrEqualTo(2),
          reason:
              'pal_opening_audio_resolution must be emitted on both normal-resolution and exception paths so failures are never silent');
      // Required fields by the telemetry spec.
      const requiredFields = [
        "'voice_key'",
        "'opening_line_id'",
        "'expected_path'",
        "'resolved_source'",
        "'success'",
      ];
      for (final field in requiredFields) {
        expect(segment, contains(field),
            reason:
                'pal_opening_audio_resolution payload must include $field');
      }
    });

    test('spec_pal_opening_completes_before_checkin_prompt.succeeds', () {
      // SPEC Feature 2.0: "TTS playback of the opening line must
      // complete before Feature 2.1 begins — no overlap permitted."
      // We assert the call site sequences awaitPlaybackComplete (or
      // the 1800ms text-only floor) BEFORE transitioning to the
      // playingGreeting state which kicks off Feature 2.1.
      final src = File(
              '$projectRoot/lib/features/main_menu/main_menu_screen.dart')
          .readAsStringSync();
      final start = src.indexOf(
          RegExp(r'Future<void> _startConversation\([^)]*\)'));
      expect(start, greaterThan(-1),
          reason: '_startConversation entry not found');
      final segment = src.substring(start);
      final idxAwaitComplete = segment.indexOf('awaitPlaybackComplete');
      final idxFloor = segment.indexOf('milliseconds: 1800');
      final idxNextState = segment.indexOf('_VoiceFlowState.playingGreeting');
      expect(idxAwaitComplete, greaterThan(-1),
          reason: 'opening flow must await playback completion');
      expect(idxFloor, greaterThan(-1),
          reason: 'opening flow must keep the 1800ms text-only floor');
      expect(idxNextState, greaterThan(-1),
          reason: 'transition to playingGreeting not found');
      expect(idxAwaitComplete < idxNextState, isTrue,
          reason:
              'awaitPlaybackComplete must precede transition to playingGreeting');
      expect(idxFloor < idxNextState, isTrue,
          reason:
              '1800ms floor must precede transition to playingGreeting (no silent skip)');
    });
  });

  group('Feature 2.0 — assetPath sanity', () {
    test('asset path matches SPEC Feature 2.0 layout', () {
      // SPEC line 61: "Pre-generated audio assets at
      // assets/pal/audio/{voiceKey}/{lineId}.mp3"
      expect(
        PalAudioService.assetPath('VOICE_RUTH_COMFORT', 'OPENING_GENTLE_01'),
        'assets/pal/audio/VOICE_RUTH_COMFORT/OPENING_GENTLE_01.mp3',
      );
    });
  });
}

String _findProjectRoot() {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}
