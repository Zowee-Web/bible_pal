import 'pal_memory_line.dart';

/// Versioned registry of memory-line templates.
///
/// PAL Memory Doctrine Slice 2a (see docs/PAL_MEMORY_DOCTRINE.md):
/// every template here is observational ("you sat with", "you spent
/// time with", "I remember") and contains the `{storyName}` placeholder
/// so the resulting line is verifiable against the session log. New
/// variants MUST pass the observation-only audit in
/// `pal_memory_templates_test.dart` — never edit a template without
/// updating the audit if a new verb is introduced.
///
/// The list is intentionally small. The doctrine prefers a few well-aged
/// lines spoken rarely over a sprawling registry that drifts into
/// inference territory. Grow this list only under explicit editorial
/// review — same discipline as the story corpus.
class PalMemoryTemplates {
  PalMemoryTemplates._();

  static const Map<RecencyBand, List<String>> _registry = {
    RecencyBand.yesterday: [
      'Yesterday you sat with {storyName}.',
      'Yesterday you spent time with {storyName}.',
      'I remember {storyName} from yesterday.',
    ],
    RecencyBand.fewDaysAgo: [
      'A few days ago you sat with {storyName}.',
      'A few days ago you spent time with {storyName}.',
      'I remember {storyName} from a few days ago.',
    ],
    RecencyBand.earlierThisWeek: [
      'Earlier this week you sat with {storyName}.',
      'Earlier this week you spent time with {storyName}.',
      'I remember {storyName} from earlier this week.',
    ],
  };

  /// Wording variants for the given recency band. Engine picks one
  /// deterministically per source session so the same session never
  /// produces two different lines on repeat queries.
  static List<String> variantsFor(RecencyBand band) =>
      _registry[band] ?? const <String>[];

  /// Flat view over every template. Used by the observation-only audit.
  static Iterable<String> all() => _registry.values.expand((v) => v);
}
