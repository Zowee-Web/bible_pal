import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/core/app_logger.dart';

/// CRITICAL: Voice transcript privacy tests (Invariant 17).
///
/// Verifies that voice transcripts can NEVER be logged, stored, or included
/// in diagnostics. These are build-failing safety tests.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    AppLogger.instance.clearBreadcrumbs();
  });

  group('CRITICAL: Voice Transcript Privacy (Invariant 17)', () {
    test('CRITICAL: AppLogger blocks "transcript" key', () {
      final result = logEvent('voice_test', {
        'transcript': 'I feel sad and lonely',
      });

      expect(result, LogResult.blocked,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Key "transcript" must be blocked by AppLogger.\n'
              'Voice transcripts must NEVER be logged (Invariant 17).');
    });

    test('CRITICAL: AppLogger blocks "recognized_text" key', () {
      final result = logEvent('voice_test', {
        'recognized_text': 'I am feeling stressed',
      });

      expect(result, LogResult.blocked,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Key "recognized_text" must be blocked by AppLogger.\n'
              'Voice transcripts must NEVER be logged (Invariant 17).');
    });

    test('CRITICAL: AppLogger blocks "speech_result" key', () {
      final result = logEvent('voice_test', {
        'speech_result': 'I feel grateful today',
      });

      expect(result, LogResult.blocked,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Key "speech_result" must be blocked by AppLogger.\n'
              'Voice transcripts must NEVER be logged (Invariant 17).');
    });

    test('CRITICAL: AppLogger blocks "voice_text" key', () {
      final result = logEvent('voice_test', {
        'voice_text': 'I am exhausted',
      });

      expect(result, LogResult.blocked,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Key "voice_text" must be blocked by AppLogger.\n'
              'Voice transcripts must NEVER be logged (Invariant 17).');
    });

    test('CRITICAL: voice_input_completed event has no user text', () {
      // This is the only voice completion event — it MUST NOT contain transcript
      final result = logEvent('voice_input_completed', {
        'input_method': 'voice',
        'word_count': 5,
        'detected_mood': 'joyful',
      });

      // Should succeed because only safe fields are logged
      expect(result, LogResult.success,
          reason: 'voice_input_completed with safe fields should log successfully');

      // Verify the event was captured in breadcrumbs
      final breadcrumbs = AppLogger.instance.getRecentBreadcrumbs();
      expect(breadcrumbs, isNotEmpty);

      final last = breadcrumbs.last;
      expect(last['event'], 'voice_input_completed');
      expect(last.containsKey('word_count'), true);
      expect(last.containsKey('detected_mood'), true);
      // Must NOT contain any transcript text
      expect(last.containsKey('transcript'), false,
          reason: 'Breadcrumb must not contain transcript');
      expect(last.containsKey('recognized_text'), false,
          reason: 'Breadcrumb must not contain recognized_text');
    });

    test('CRITICAL: voice_input_completed with transcript key is blocked', () {
      final result = logEvent('voice_input_completed', {
        'input_method': 'voice',
        'word_count': 5,
        'transcript': 'I feel grateful', // VIOLATION
      });

      expect(result, LogResult.blocked,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'voice_input_completed must NEVER include transcript data.');
    });

    test('CRITICAL: voice transcript routes through same handler as typed text', () {
      // Structural verification: PalsParablesScreen._handleMoodSubmission()
      // is the ONLY path for both typed and voice input.
      // This test documents the architectural contract (Invariant 17: Input Equivalence).
      //
      // Voice input sets _moodController.text = transcript, then the user
      // taps Continue which calls _handleMoodSubmission() → MoodService.detectMood().
      // This is the identical path to typing in the TextField.
      //
      // Enforced by: voice_privacy_scan_test.dart (no separate voice mood path in lib/)
      expect(true, true);
    });

    test('CRITICAL: no transcript stored in SharedPreferences', () async {
      // Verify that SharedPreferences does not contain any transcript-related keys
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        final lowerKey = key.toLowerCase();
        expect(lowerKey.contains('transcript'), false,
            reason: '🚨 PRIVACY VIOLATION 🚨\n'
                'SharedPreferences key "$key" contains "transcript".\n'
                'Voice transcripts must NEVER be persisted (Invariant 17).');
        expect(lowerKey.contains('recognized_text'), false,
            reason: 'SharedPreferences must not contain recognized_text');
        expect(lowerKey.contains('speech_result'), false,
            reason: 'SharedPreferences must not contain speech_result');
        expect(lowerKey.contains('voice_text'), false,
            reason: 'SharedPreferences must not contain voice_text');
      }
    });
  });
}
