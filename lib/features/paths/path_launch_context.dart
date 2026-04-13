import 'path_type.dart';

/// Carries path-launch state from a path detail screen into the canonical
/// [ParablePlayerScreen]. When this is non-null on a player load, the
/// player renders the "Next in Your Journey" block (SPEC Feature 50.6 —
/// path order is sacred: it advances by canonical position, never filtered
/// by completion state).
///
/// When this is null, the player renders nothing path-related. Mood,
/// favorite, history, and standalone search launches pass null.
class PathLaunchContext {
  /// The path type this launch belongs to. LOCKED enum per SPEC 50.1.
  final PathType pathType;

  /// The specific path within [pathType]. Conventions (SPEC 50.10):
  /// - `jesusLife`: always `"default"`
  /// - `bibleOrder`: book slug (e.g. `"genesis"`)
  /// - `timeline`: era wire id (e.g. `"kingdom"`)
  /// - `themes`: theme tag (e.g. `"faith"`)
  /// - `characters`: `primaryCharacterId` from the registry (never `"jesus"`)
  final String pathId;

  /// Zero-based index of the current story within the ordered path
  /// sequence. The player uses this to resolve "next in journey" by
  /// asking `PathService.getNextInPath(pathType, pathId, positionInPath)`.
  final int positionInPath;

  const PathLaunchContext({
    required this.pathType,
    required this.pathId,
    required this.positionInPath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathLaunchContext &&
          runtimeType == other.runtimeType &&
          pathType == other.pathType &&
          pathId == other.pathId &&
          positionInPath == other.positionInPath;

  @override
  int get hashCode =>
      pathType.hashCode ^ pathId.hashCode ^ positionInPath.hashCode;

  @override
  String toString() =>
      'PathLaunchContext(${pathType.wireId}, $pathId, pos=$positionInPath)';
}
