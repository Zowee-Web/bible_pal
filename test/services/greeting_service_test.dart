import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/greeting_service.dart';

void main() {
  group('GreetingService', () {
    test('should return a non-empty greeting (morning)', () {
      final greetingService = GreetingService(
        now: () => DateTime(2025, 1, 1, 9, 0), // 9 AM
        random: Random(0), // Deterministic
      );
      final greeting = greetingService.getGreeting();
      expect(greeting.isNotEmpty, true);
    });

    test('should return correct time window name for each period', () {
      // Morning (5 AM - 11:59 AM)
      final morning =
          GreetingService(now: () => DateTime(2025, 1, 1, 8, 0)); // 8 AM
      expect(morning.getTimeWindowName(), 'Morning');

      // Afternoon (12 PM - 4:59 PM)
      final afternoon =
          GreetingService(now: () => DateTime(2025, 1, 1, 14, 0)); // 2 PM
      expect(afternoon.getTimeWindowName(), 'Afternoon');

      // Evening (5 PM - 8:59 PM)
      final evening =
          GreetingService(now: () => DateTime(2025, 1, 1, 19, 0)); // 7 PM
      expect(evening.getTimeWindowName(), 'Evening');

      // Late Night (9 PM - 4:59 AM)
      final lateNight =
          GreetingService(now: () => DateTime(2025, 1, 1, 22, 0)); // 10 PM
      expect(lateNight.getTimeWindowName(), 'Late Night');
    });

    test('should return correct emoji for each time window', () {
      // Morning
      final morning =
          GreetingService(now: () => DateTime(2025, 1, 1, 8, 0)); // 8 AM
      expect(morning.getTimeWindowEmoji(), '🌅');

      // Afternoon
      final afternoon =
          GreetingService(now: () => DateTime(2025, 1, 1, 14, 0)); // 2 PM
      expect(afternoon.getTimeWindowEmoji(), '🌤️');

      // Evening
      final evening =
          GreetingService(now: () => DateTime(2025, 1, 1, 19, 0)); // 7 PM
      expect(evening.getTimeWindowEmoji(), '🌇');

      // Late Night
      final lateNight =
          GreetingService(now: () => DateTime(2025, 1, 1, 22, 0)); // 10 PM
      expect(lateNight.getTimeWindowEmoji(), '🌙');
    });

    test('morning greetings all ask how the user is doing', () {
      // Verify every morning greeting contains a question or prompt
      for (var seed = 0; seed < 20; seed++) {
        final greetingService = GreetingService(
          now: () => DateTime(2025, 1, 1, 9, 0),
          random: Random(seed),
        );
        final greeting = greetingService.getGreeting();
        expect(
          greeting.contains('?'),
          true,
          reason: 'Morning greeting should ask a question: "$greeting"',
        );
      }
    });

    test('afternoon greetings all ask how the user is doing', () {
      for (var seed = 0; seed < 20; seed++) {
        final greetingService = GreetingService(
          now: () => DateTime(2025, 1, 1, 14, 0),
          random: Random(seed),
        );
        final greeting = greetingService.getGreeting();
        expect(
          greeting.contains('?'),
          true,
          reason: 'Afternoon greeting should ask a question: "$greeting"',
        );
      }
    });

    test('evening greetings all ask how the user is doing', () {
      for (var seed = 0; seed < 20; seed++) {
        final greetingService = GreetingService(
          now: () => DateTime(2025, 1, 1, 19, 0),
          random: Random(seed),
        );
        final greeting = greetingService.getGreeting();
        expect(
          greeting.contains('?') || greeting.contains('Tell me'),
          true,
          reason: 'Evening greeting should ask a question: "$greeting"',
        );
      }
    });

    test('late night greetings all ask how the user is doing', () {
      for (var seed = 0; seed < 20; seed++) {
        final greetingService = GreetingService(
          now: () => DateTime(2025, 1, 1, 22, 0),
          random: Random(seed),
        );
        final greeting = greetingService.getGreeting();
        expect(
          greeting.contains('?') || greeting.contains('Tell me'),
          true,
          reason: 'Late night greeting should ask a question: "$greeting"',
        );
      }
    });

    test('greetings have variety (at least 8 per time slot)', () {
      // Collect unique greetings across many seeds
      final morningSet = <String>{};
      final afternoonSet = <String>{};
      final eveningSet = <String>{};
      final lateNightSet = <String>{};

      for (var seed = 0; seed < 50; seed++) {
        morningSet.add(GreetingService(
          now: () => DateTime(2025, 1, 1, 9, 0),
          random: Random(seed),
        ).getGreeting());
        afternoonSet.add(GreetingService(
          now: () => DateTime(2025, 1, 1, 14, 0),
          random: Random(seed),
        ).getGreeting());
        eveningSet.add(GreetingService(
          now: () => DateTime(2025, 1, 1, 19, 0),
          random: Random(seed),
        ).getGreeting());
        lateNightSet.add(GreetingService(
          now: () => DateTime(2025, 1, 1, 22, 0),
          random: Random(seed),
        ).getGreeting());
      }

      expect(morningSet.length, greaterThanOrEqualTo(8));
      expect(afternoonSet.length, greaterThanOrEqualTo(8));
      expect(eveningSet.length, greaterThanOrEqualTo(8));
      expect(lateNightSet.length, greaterThanOrEqualTo(8));
    });

    test('default constructor uses real DateTime.now', () {
      // This test verifies the default behavior works for production
      final greetingService = GreetingService();
      final greeting = greetingService.getGreeting();
      expect(greeting.isNotEmpty, true);

      final timeWindow = greetingService.getTimeWindowName();
      expect(
        ['Morning', 'Afternoon', 'Evening', 'Late Night'].contains(timeWindow),
        true,
      );
    });
  });
}
