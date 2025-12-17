import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/greeting_service.dart';

void main() {
  group('GreetingService', () {
    late GreetingService greetingService;

    setUp(() {
      greetingService = GreetingService();
    });

    test('should return a non-empty greeting', () {
      final greeting = greetingService.getGreeting();
      expect(greeting.isNotEmpty, true);
    });

    test('should return a time window name', () {
      final timeWindow = greetingService.getTimeWindowName();
      expect(
        ['Morning', 'Afternoon', 'Evening', 'Late Night'].contains(timeWindow),
        true,
      );
    });

    test('should return a time window emoji', () {
      final emoji = greetingService.getTimeWindowEmoji();
      expect(['🌅', '🌤️', '🌇', '🌙'].contains(emoji), true);
    });

    test('greeting should be appropriate for current time', () {
      final greeting = greetingService.getGreeting();
      final hour = DateTime.now().hour;

      if (hour >= 5 && hour < 12) {
        // Morning
        expect(
          greeting.contains('morning') || greeting.contains('Morning'),
          true,
        );
      } else if (hour >= 12 && hour < 17) {
        // Afternoon
        expect(
          greeting.contains('afternoon') ||
              greeting.contains('today') ||
              greeting.contains('day'),
          true,
        );
      } else if (hour >= 17 && hour < 21) {
        // Evening
        expect(
          greeting.contains('evening') || greeting.contains('tonight'),
          true,
        );
      } else {
        // Late Night
        expect(
          greeting.contains('night') ||
              greeting.contains('tonight') ||
              greeting.contains('quiet hour'),
          true,
        );
      }
    });
  });
}
