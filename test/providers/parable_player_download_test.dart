// Cloud Foundation v1 — ParablePlayerState.downloadProgress lifecycle.
// SPEC Feature 27, Plan: Test #7.

import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParablePlayerState.downloadProgress', () {
    test('default state has null download progress', () {
      const state = ParablePlayerState();
      expect(state.downloadProgress, isNull);
    });

    test('copyWith sets and updates download progress', () {
      const state = ParablePlayerState();
      final updated = state.copyWith(downloadProgress: 0.42);
      expect(updated.downloadProgress, 0.42);
    });

    test('clearDownloadProgress resets to null even if value is supplied', () {
      const state = ParablePlayerState();
      final mid = state.copyWith(downloadProgress: 0.7);
      expect(mid.downloadProgress, 0.7);
      final cleared = mid.copyWith(clearDownloadProgress: true);
      expect(cleared.downloadProgress, isNull);
    });

    test('copyWith without specifying preserves existing progress', () {
      const state = ParablePlayerState();
      final mid = state.copyWith(downloadProgress: 0.3);
      final next = mid.copyWith(isLoading: true);
      expect(next.downloadProgress, 0.3);
      expect(next.isLoading, isTrue);
    });
  });
}
