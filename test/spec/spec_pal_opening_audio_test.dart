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

    test(
        'spec_pal_opening_default_voice_has_full_coverage.succeeds — Ruth has no further fallback',
        () {
      // The default voice is the terminal node of the cross-voice
      // fallback chain. It MUST carry every opening asset, otherwise
      // there is no graceful path and the resolution is `missing`.
      final missing = <String>[];
      for (final line in palOpeningLines) {
        final file =
            File('$audioBase/${PalVoiceRegistry.defaultVoiceKey}/${line.id}.mp3');
        if (!file.existsSync() || file.lengthSync() == 0) {
          missing.add(line.id);
        }
      }
      expect(missing, isEmpty,
          reason:
              'Default voice (${PalVoiceRegistry.defaultVoiceKey}) missing opening assets: ${missing.join(', ')}');
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
      // tagged 'missing' with the error type.
      expect(src, contains('Future<PalAudioResolution> playLineResolved'),
          reason: 'playLineResolved is the resolution-aware entry point');
      expect(src, contains("source: 'missing'"),
          reason: 'missing branch must tag source as missing');
      expect(src, contains('errorType: e2.runtimeType.toString()'),
          reason: 'missing branch must record error_type for telemetry');
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
      final start = src.indexOf('Future<void> _startConversation()');
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
      final start = src.indexOf('Future<void> _startConversation()');
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
