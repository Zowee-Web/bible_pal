import 'path_type.dart';

/// A single path instance that can be displayed in the path-instance
/// list (e.g. "David", "Kingdom", "Faith", "Genesis", or "The Life of
/// Jesus"). Each instance belongs to one [PathType].
///
/// For `jesusLife` there is exactly one instance (pathId `"default"`).
/// For the other four path types, one instance is surfaced per distinct
/// pathId that has at least one eligible annotated story after kid-mode
/// filtering (SPEC Feature 50 + INVARIANTS #3a: empty paths are hidden).
class PathInstance {
  /// The path type this instance belongs to.
  final PathType pathType;

  /// Wire-format path id (e.g. `"david"`, `"kingdom"`, `"faith"`,
  /// `"genesis"`, `"default"`). Lowercase snake_case.
  final String pathId;

  /// User-facing display label (e.g. "David", "Kingdom", "Faith",
  /// "Genesis", "The Life of Jesus").
  final String displayLabel;

  /// Number of eligible stories in this instance after kid-mode
  /// filtering. May be 0 only transiently — empty instances are
  /// filtered out before reaching the UI.
  final int storyCount;

  const PathInstance({
    required this.pathType,
    required this.pathId,
    required this.displayLabel,
    required this.storyCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathInstance &&
          runtimeType == other.runtimeType &&
          pathType == other.pathType &&
          pathId == other.pathId &&
          displayLabel == other.displayLabel &&
          storyCount == other.storyCount;

  @override
  int get hashCode =>
      pathType.hashCode ^
      pathId.hashCode ^
      displayLabel.hashCode ^
      storyCount.hashCode;

  @override
  String toString() =>
      'PathInstance(${pathType.wireId}, $pathId, "$displayLabel", '
      'count=$storyCount)';
}
