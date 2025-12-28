import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/greeting_service.dart';

void main() {
  group('GreetingService', () {
    test('should return a non-empty greeting (morning)', () {
      final greetingService =
          GreetingService(now: () => DateTime(2025, 1, 1, 9, 0)); // 9 AM
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

    test('morning greeting should contain morning-related text', () {
      final greetingService =
          GreetingService(now: () => DateTime(2025, 1, 1, 9, 0)); // 9 AM
      final greeting = greetingService.getGreeting();
      expect(
        greeting.contains('morning') || greeting.contains('Morning'),
        true,
        reason: 'Morning greeting should mention "morning"',
      );
    });

    test('afternoon greeting should contain appropriate text', () {
      final greetingService =
          GreetingService(now: () => DateTime(2025, 1, 1, 14, 0)); // 2 PM
      final greeting = greetingService.getGreeting();
      expect(
        greeting.contains('afternoon') ||
            greeting.contains('today') ||
            greeting.contains('day'),
        true,
        reason: 'Afternoon greeting should mention "afternoon", "today", or "day"',
      );
    });

    test('evening greeting should contain evening-related text', () {
      final greetingService =
          GreetingService(now: () => DateTime(2025, 1, 1, 19, 0)); // 7 PM
      final greeting = greetingService.getGreeting();
      expect(
        greeting.contains('evening') || greeting.contains('tonight'),
        true,
        reason: 'Evening greeting should mention "evening" or "tonight"',
      );
    });

    test('late night greeting should contain night-related text', () {
      final greetingService =
          GreetingService(now: () => DateTime(2025, 1, 1, 22, 0)); // 10 PM
      final greeting = greetingService.getGreeting();
      expect(
        greeting.contains('night') ||
            greeting.contains('tonight') ||
            greeting.contains('quiet hour'),
        true,
        reason:
            'Late night greeting should mention "night", "tonight", or "quiet hour"',
      );
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
