import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

/// Data class for a PAL check-in prompt.
class PalPrompt {
  final String id; // e.g. "MORNING_DAY_01"
  final String timeWindow; // morning, afternoon, evening, lateNight
  final String category; // day, heart, burden, gratitude
  final String text;

  const PalPrompt({
    required this.id,
    required this.timeWindow,
    required this.category,
    required this.text,
  });
}

/// PAL Check-In Prompt Service
/// Replaces GreetingService with time-aware, category-weighted prompts.
/// Loads 96 prompts from pal_lines.json (16 buckets × 6 lines).
class PalPromptService {
  final Random _random;
  final DateTime Function() _now;

  /// Loaded prompt pools keyed by bucket (e.g. "morning_day").
  Map<String, List<PalPrompt>> _prompts = {};

  /// Ring buffers per bucket to avoid repeats (size = 6, matching bucket size).
  final Map<String, List<String>> _recentIds = {};

  /// Whether init has completed.
  bool _loaded = false;

  PalPromptService({
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  /// Category weights per time window.
  /// Order: [day, heart, burden, gratitude]
  static const Map<String, List<double>> _weights = {
    'morning': [0.35, 0.25, 0.15, 0.25],
    'afternoon': [0.30, 0.30, 0.25, 0.15],
    'evening': [0.20, 0.35, 0.30, 0.15],
    'lateNight': [0.15, 0.40, 0.35, 0.10],
  };

  static const List<String> _categories = [
    'day',
    'heart',
    'burden',
    'gratitude',
  ];

  /// Determine time window from device local time.
  static String getTimeWindow(int hour) {
    if (hour >= 5 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 22) return 'evening';
    return 'lateNight'; // 22-4
  }

  /// Load prompts from pal_lines.json. Safe to call multiple times.
  Future<void> ensureInit() async {
    if (_loaded) return;
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final promptsData = data['prompts'] as Map<String, dynamic>;

    _prompts = {};
    for (final entry in promptsData.entries) {
      final bucketKey = entry.key;
      final lines = entry.value as List<dynamic>;
      // Parse timeWindow and category from bucket key
      final parts = bucketKey.split('_');
      final timeWindow = parts[0];
      final category = parts.length > 1 ? parts.sublist(1).join('_') : parts[0];

      _prompts[bucketKey] = lines
          .map((item) => PalPrompt(
                id: item['id'] as String,
                timeWindow: timeWindow,
                category: category,
                text: item['text'] as String,
              ))
          .toList();
    }
    _loaded = true;
  }

  /// Initialize with pre-built prompt map (for testing without asset loading).
  void initWithPrompts(Map<String, List<PalPrompt>> prompts) {
    _prompts = prompts;
    _loaded = true;
  }

  /// Get a check-in prompt for the current time.
  Future<PalPrompt> getPrompt() async {
    await ensureInit();

    final hour = _now().hour;
    final timeWindow = getTimeWindow(hour);
    final category = _pickCategory(timeWindow);
    final bucketKey = '${timeWindow}_$category';

    return _pickFromBucket(bucketKey);
  }

  /// Choose a category using weighted random distribution.
  String _pickCategory(String timeWindow) {
    final weights = _weights[timeWindow] ?? _weights['morning']!;
    final roll = _random.nextDouble();

    double cumulative = 0;
    for (int i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (roll < cumulative) return _categories[i];
    }
    return _categories.last;
  }

  /// Pick a prompt from a bucket, avoiding recent IDs.
  PalPrompt _pickFromBucket(String bucketKey) {
    final pool = _prompts[bucketKey];
    if (pool == null || pool.isEmpty) {
      return PalPrompt(
        id: 'fallback',
        timeWindow: 'morning',
        category: 'day',
        text: 'How are you doing today?',
      );
    }

    final recentIds = _recentIds.putIfAbsent(bucketKey, () => []);

    // Filter out recently used
    var candidates = pool.where((p) => !recentIds.contains(p.id)).toList();
    if (candidates.isEmpty) {
      // Ring exhausted — reset and use full pool
      recentIds.clear();
      candidates = pool;
    }

    final picked = candidates[_random.nextInt(candidates.length)];

    // Update ring buffer
    recentIds.add(picked.id);
    if (recentIds.length > pool.length) {
      recentIds.removeAt(0);
    }

    return picked;
  }
}
