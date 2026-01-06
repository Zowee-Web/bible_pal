import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/reflection_templates.dart';

/// Service for generating post-story reflections
/// Based on SPEC.md Features #34-37 and INVARIANTS.md Reflection Language Safety
///
/// Key constraints:
/// - No AI generation at playback time (uses pre-written templates)
/// - Descriptive language only, no prescriptions
/// - Kid mode uses short, literal language
/// - All reflections are optional and skippable
class ReflectionService {
  /// Get a reflection for a parable based on its metadata
  ///
  /// Returns null if no matching template is found.
  /// Uses emotionalTags first, then falls back to mood.
  ReflectionContent? getReflectionForParable({
    required Parable parable,
    required bool isKidMode,
  }) {
    // Try to find a reflection based on emotional tags first
    if (parable.emotionalTags.isNotEmpty) {
      for (final tag in parable.emotionalTags) {
        final reflection = _getReflectionByTag(tag, isKidMode);
        if (reflection != null) {
          return reflection;
        }
      }
    }

    // Fall back to mood-based reflection
    return _getReflectionByMood(parable.mood, isKidMode);
  }

  /// Get reflection by emotional tag
  ReflectionContent? _getReflectionByTag(String tag, bool isKidMode) {
    if (isKidMode) {
      return kidReflectionsByTag[tag];
    }
    return adultReflectionsByTag[tag];
  }

  /// Get reflection by mood
  ReflectionContent? _getReflectionByMood(String mood, bool isKidMode) {
    if (isKidMode) {
      return kidReflectionsByMood[mood];
    }
    return adultReflectionsByMood[mood];
  }

  /// Check if a reflection should be shown based on user preferences
  bool shouldShowReflection({
    required bool showEverydayReflections,
    required Parable parable,
    required bool isKidMode,
  }) {
    if (!showEverydayReflections) {
      return false;
    }

    // Check if we have a reflection available for this parable
    final reflection = getReflectionForParable(
      parable: parable,
      isKidMode: isKidMode,
    );

    return reflection != null;
  }
}
