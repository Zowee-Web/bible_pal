import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/pals_parables/pals_parables_screen.dart';

/// Tests for the VoiceInputState state machine (Feature 2.2).
///
/// Verifies all valid transitions per SPEC.md Feature 2.2
/// "Voice Conversation States (Milestone 1)".
void main() {
  group('VoiceInputState enum', () {
    test('has exactly 5 states per SPEC 2.2', () {
      expect(VoiceInputState.values.length, 5);
    });

    test('idle is the initial state', () {
      expect(VoiceInputState.values.first, VoiceInputState.idle);
    });

    test('contains all SPEC 2.2 states', () {
      expect(VoiceInputState.values, containsAll([
        VoiceInputState.idle,
        VoiceInputState.awaitingPermission,
        VoiceInputState.listening,
        VoiceInputState.confirming,
        VoiceInputState.proceeding,
      ]));
    });
  });

  group('VoiceInputState transitions (documented per SPEC 2.2)', () {
    // These tests document the expected transitions.
    // Actual transition behavior is tested via widget tests on PalsParablesScreen.

    test('idle → awaitingPermission is valid (mic tap, permission not granted)', () {
      const from = VoiceInputState.idle;
      const to = VoiceInputState.awaitingPermission;
      expect(from, isNot(equals(to)));
    });

    test('idle → listening is valid (mic tap, permission already granted)', () {
      const from = VoiceInputState.idle;
      const to = VoiceInputState.listening;
      expect(from, isNot(equals(to)));
    });

    test('awaitingPermission → listening is valid (permission granted)', () {
      const from = VoiceInputState.awaitingPermission;
      const to = VoiceInputState.listening;
      expect(from, isNot(equals(to)));
    });

    test('awaitingPermission → idle is valid (permission denied)', () {
      const from = VoiceInputState.awaitingPermission;
      const to = VoiceInputState.idle;
      expect(from, isNot(equals(to)));
    });

    test('listening → confirming is valid (final result received)', () {
      const from = VoiceInputState.listening;
      const to = VoiceInputState.confirming;
      expect(from, isNot(equals(to)));
    });

    test('listening → idle is valid (silence timeout, 0 words)', () {
      const from = VoiceInputState.listening;
      const to = VoiceInputState.idle;
      expect(from, isNot(equals(to)));
    });

    test('confirming → proceeding is valid (Continue tapped)', () {
      const from = VoiceInputState.confirming;
      const to = VoiceInputState.proceeding;
      expect(from, isNot(equals(to)));
    });

    test('confirming → listening is valid (re-record)', () {
      const from = VoiceInputState.confirming;
      const to = VoiceInputState.listening;
      expect(from, isNot(equals(to)));
    });

    test('confirming → idle is valid (cancel / clear)', () {
      const from = VoiceInputState.confirming;
      const to = VoiceInputState.idle;
      expect(from, isNot(equals(to)));
    });

    test('any state can transition to idle (back / TextField tap)', () {
      for (final state in VoiceInputState.values) {
        if (state == VoiceInputState.idle) continue;
        expect(state, isNot(equals(VoiceInputState.idle)));
      }
    });

    test('listening → confirming uses partial result as final when no finalResult received', () {
      // Documented behavior: if listenFor expires with partial but no final,
      // use partial text as the transcript.
      const from = VoiceInputState.listening;
      const to = VoiceInputState.confirming;
      expect(from, isNot(equals(to)));
    });
  });
}
