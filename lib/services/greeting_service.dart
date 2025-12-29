import 'dart:math';

/// Greeting Service
/// Based on SPEC.md Feature 2.1: Context-Aware Emotional Check-In Greeting
/// Provides time-appropriate, varied emotional check-in questions
class GreetingService {
  final Random _random;
  final DateTime Function() _now;

  /// Create a greeting service with optional clock and random injection (for testing)
  GreetingService({
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  /// Get a context-aware greeting based on the current time
  String getGreeting() {
    final hour = _now().hour;
    return _getGreetingForTimeWindow(hour);
  }

  /// Get greeting for a specific hour (useful for testing)
  String _getGreetingForTimeWindow(int hour) {
    if (hour >= 5 && hour < 12) {
      // Morning (5 AM - 11:59 AM)
      return _randomChoice(_morningGreetings);
    } else if (hour >= 12 && hour < 17) {
      // Afternoon (12 PM - 4:59 PM)
      return _randomChoice(_afternoonGreetings);
    } else if (hour >= 17 && hour < 21) {
      // Evening (5 PM - 8:59 PM)
      return _randomChoice(_eveningGreetings);
    } else {
      // Late Night (9 PM - 4:59 AM)
      return _randomChoice(_lateNightGreetings);
    }
  }

  /// Morning greetings (5 AM - 11:59 AM)
  static const List<String> _morningGreetings = [
    "Good morning! How's your day starting out?",
    "Morning! How are you feeling so far today?",
    "Hi there — how's your morning going?",
    "Good morning! What's on your heart today?",
  ];

  /// Afternoon greetings (12 PM - 4:59 PM)
  static const List<String> _afternoonGreetings = [
    "How's your afternoon going?",
    "I'm glad you're here — how are you doing today?",
    "How's your day been so far?",
    "Checking in — how are you feeling this afternoon?",
  ];

  /// Evening greetings (5 PM - 8:59 PM)
  static const List<String> _eveningGreetings = [
    "How's your evening going?",
    "Good to see you — how are you feeling tonight?",
    "How has your day been winding down?",
    "How are you doing this evening?",
  ];

  /// Late night greetings (9 PM - 4:59 AM)
  static const List<String> _lateNightGreetings = [
    "How's your night going?",
    "It's a quiet hour — how are you feeling?",
    "How are you doing tonight?",
    "Is everything going okay this late? How are you feeling?",
  ];

  /// Randomly select a greeting from a list
  String _randomChoice(List<String> greetings) {
    return greetings[_random.nextInt(greetings.length)];
  }

  /// Get the time window name for the current hour (useful for UI/debugging)
  String getTimeWindowName() {
    final hour = _now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Evening';
    } else {
      return 'Late Night';
    }
  }

  /// Get emoji for the current time window (optional, for UI decoration)
  String getTimeWindowEmoji() {
    final hour = _now().hour;
    if (hour >= 5 && hour < 12) {
      return '🌅'; // Morning
    } else if (hour >= 12 && hour < 17) {
      return '🌤️'; // Afternoon
    } else if (hour >= 17 && hour < 21) {
      return '🌇'; // Evening
    } else {
      return '🌙'; // Late Night
    }
  }
}
