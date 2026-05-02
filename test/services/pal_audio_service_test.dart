import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/core/pal_voice_registry.dart';

void main() {
  group('PalAudioService.assetPath', () {
    test('builds correct path for prompt', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'MORNING_DAY_01'),
        'assets/pal/audio/VOICE_GRACE/MORNING_DAY_01.mp3',
      );
    });

    test('builds correct path for micro-response', () {
      expect(
        PalAudioService.assetPath('VOICE_SHEPHERD', 'RESP_JOY_01'),
        'assets/pal/audio/VOICE_SHEPHERD/RESP_JOY_01.mp3',
      );
    });

    test('builds correct path for preview (new PAL line)', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_HOPE', PalAudioService.previewLineId),
        'assets/pal/audio/VOICE_HOPE/OPENING_AFTN_01.mp3',
      );
    });

    test('builds correct path for onboarding', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'onboard_01'),
        'assets/pal/audio/VOICE_GRACE/onboard_01.mp3',
      );
    });

    test('all voice keys produce valid paths', () {
      for (final voice in PalVoiceRegistry.voices) {
        final path =
            PalAudioService.assetPath(voice.voiceKey, 'MORNING_DAY_01');
        expect(path, contains(voice.voiceKey));
        expect(path, endsWith('.mp3'));
        expect(path, startsWith('assets/pal/audio/'));
      }
    });
  });

  group('PalLine', () {
    test('can be constructed with id and text', () {
      const line = PalLine(id: 'test_01', text: 'Hello friend.');
      expect(line.id, 'test_01');
      expect(line.text, 'Hello friend.');
    });
  });

  group('PalAudioService.assetPath for new line types', () {
    test('builds correct path for opening line', () {
      expect(
        PalAudioService.assetPath('VOICE_GRACE', 'OPENING_GENTLE_01'),
        'assets/pal/audio/VOICE_GRACE/OPENING_GENTLE_01.mp3',
      );
    });

    test('builds correct path for reflection line', () {
      expect(
        PalAudioService.assetPath('VOICE_SHEPHERD', 'REFL_JOYFUL_01'),
        'assets/pal/audio/VOICE_SHEPHERD/REFL_JOYFUL_01.mp3',
      );
    });

    test('builds correct path for tone-biased reflection', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_HOPE', 'REFL_TB_JOYFUL_GENTLE_01'),
        'assets/pal/audio/VOICE_HOPE/REFL_TB_JOYFUL_GENTLE_01.mp3',
      );
    });

    test('builds correct path for framing line', () {
      expect(
        PalAudioService.assetPath(
            'VOICE_GRACE', 'FRAME_DAVID_ANOINTED_01'),
        'assets/pal/audio/VOICE_GRACE/FRAME_DAVID_ANOINTED_01.mp3',
      );
    });

    test('builds correct path for transition line', () {
      expect(
        PalAudioService.assetPath('VOICE_STILLWATER', 'TRANS_01'),
        'assets/pal/audio/VOICE_STILLWATER/TRANS_01.mp3',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Cancel-safety regression. `awaitPlaybackComplete` MUST accept both
  // ProcessingState.completed (natural end) AND ProcessingState.idle
  // (forced stop via _player.stop()). Without `idle` here, every
  // caller's await hangs after `palAudio.stop()` is invoked from
  // `_cancelConversation`, leaving stale futures that race the next
  // PAL session and silently corrupt the audio session state. After
  // a few cancel/retry cycles the stack wedges and PAL goes mute
  // until the app is force-quit.
  //
  // AudioPlayer can't be cleanly mocked without adding mocktail/
  // mockito to the project, and behavioral testing against the real
  // player would require actual asset playback. So this is a source-
  // level pin: a future refactor can't silently regress the contract
  // without this test failing.
  // ---------------------------------------------------------------------
  group('PalAudioService.awaitPlaybackComplete cancel-safety contract', () {
    test('predicate accepts both `completed` and `idle` terminal states',
        () {
      final source =
          File('lib/services/pal_audio_service.dart').readAsStringSync();
      final lines = source.split('\n');

      // Locate the awaitPlaybackComplete method body and capture the
      // window between its declaration and the next closing brace.
      final declIdx = lines.indexWhere(
          (l) => l.contains('Future<void> awaitPlaybackComplete()'));
      expect(declIdx, greaterThan(-1),
          reason: 'awaitPlaybackComplete must remain a public API.');

      // Take a 12-line window forward (covers the firstWhere predicate).
      final body = lines.skip(declIdx).take(12).join('\n');

      expect(body, contains('ProcessingState.completed'),
          reason: 'awaitPlaybackComplete must still wait for natural-end.');
      expect(body, contains('ProcessingState.idle'),
          reason:
              'awaitPlaybackComplete MUST also accept `idle` so cancel '
              'via _player.stop() unblocks the await. Without this, '
              'cancel-then-retry corrupts the audio session.');
    });
  });

  // ---------------------------------------------------------------------
  // Source-level pin: playLine MUST self-heal on iOS PlayerException
  // -11849 ("Operation Stopped") by calling recoverFromOperationStopped
  // and retrying. Without this, the AVPlayer stays wedged and every
  // subsequent setAsset returns the same code — silently. PAL goes
  // mute on the NEXT line until the app is force-quit.
  // playLineResolved already had its own -11849 detection (it returns
  // an `operation_stopped` resolution and lets the caller schedule
  // cooldown); playLine had no equivalent and was the source of the
  // accumulating wedge.
  // ---------------------------------------------------------------------
  group('PalAudioService.playLine cancel-safety contract', () {
    test('catches PlayerException -11849 and self-heals via recovery', () {
      final source =
          File('lib/services/pal_audio_service.dart').readAsStringSync();
      final lines = source.split('\n');

      // Locate the playLine method body.
      final declIdx = lines.indexWhere(
          (l) => l.contains('Future<bool> playLine(String lineId'));
      expect(declIdx, greaterThan(-1),
          reason: 'playLine must remain a public API.');

      // Take a generous window forward (covers the catch + self-heal).
      final body = lines.skip(declIdx).take(60).join('\n');

      expect(body, contains('-11849'),
          reason: 'playLine MUST detect iOS PlayerException -11849.');
      expect(body, contains('recoverFromOperationStopped'),
          reason: 'playLine MUST call recoverFromOperationStopped on '
              '-11849 to dispose+recreate the wedged AVPlayer. Without '
              'this, the wedge persists and PAL goes mute on the next '
              'line.');
    });
  });
}
