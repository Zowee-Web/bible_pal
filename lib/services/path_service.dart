import '../core/character_registry.dart';
import '../core/timeline_era.dart';
import '../features/paths/path_instance.dart';
import '../features/paths/path_type.dart';
import '../features/paths/theme_vocabulary.dart';
import '../models/parable.dart';

/// PALs Paths service — real implementation for Phase 2 + 3 (SPEC Feature 50).
///
/// Design contract (LOCKED):
/// - PathService is a **pure function over its constructor inputs**.
///   Same inputs → same outputs, every call.
/// - It takes a read-only snapshot of the Traditional parable list, the
///   curated `jesus_life` sequence, the kid-mode flag, and (Phase 3) the
///   set of completed story IDs at construction time. It holds no mutable
///   state.
/// - It MUST NOT call `ParableService.selectParable()` — path traversal
///   is deterministic by canonical path order, never by mood expansion
///   (Mood Expansion Serving Invariant scope).
/// - PALs Paths operates only on Traditional stories. The constructor
///   defensively re-filters to `storytellingMode == "traditional"` even
///   though the caller (provider) already filters — belt-and-suspenders
///   enforcement of the Story Mode Non-Blur Invariant #6.
/// - Kid mode is enforced at the snapshot layer: when `kidFriendlyOnly`
///   is true, non-kid stories are filtered out at construction time so
///   downstream methods never have to re-check (INVARIANTS Kid Safety
///   #3a).
/// - **Path order is sacred** (SPEC Feature 50.6 — LOCKED): `getNextInPath`
///   advances by canonical position and MUST NEVER filter by completion
///   state. Completed stories remain in sequence.
/// - **Resume heuristic** (SPEC Feature 50.6b): `getResumePoint` is the
///   ONE path-related affordance that filters by completion state. It
///   jumps to the first uncompleted story in canonical path order, or
///   to the first story if every entry is completed (replay mode).
class PathService {
  /// Snapshot of Traditional + kid-eligible parables. Already filtered.
  final List<Parable> _parables;

  /// Curated chronological sequence for `jesus_life`. Story IDs only.
  final List<String> _jesusLifeSequence;

  /// Snapshot of completed story IDs (Phase 3, SPEC Feature 50.4 + 50.11).
  /// Read from `CompletedStoriesStore` via `completedStoryIdsProvider`
  /// at construction time. When the store updates, the provider is
  /// invalidated and a fresh PathService is built with the new set.
  final Set<String> _completedStoryIds;

  const PathService._({
    required List<Parable> parables,
    required List<String> jesusLifeSequence,
    required Set<String> completedStoryIds,
  })  : _parables = parables,
        _jesusLifeSequence = jesusLifeSequence,
        _completedStoryIds = completedStoryIds;

  /// Construct a PathService from a snapshot of all Traditional parables
  /// plus the curated `jesus_life` sequence, the kid-mode flag, and
  /// (optional, Phase 3) the set of completed story IDs.
  ///
  /// The constructor filters defensively:
  /// - Creative stories excluded (should already be filtered upstream)
  /// - Non-kid stories excluded when `kidFriendlyOnly == true`
  ///
  /// `completedStoryIds` defaults to the empty set so Phase 2 tests and
  /// any caller that doesn't care about completion state keep working
  /// unchanged. An empty set means `getResumePoint` returns the first
  /// eligible story and `getCompletionPercentage` returns 0.0.
  ///
  /// The resulting service is immutable and deterministic.
  factory PathService({
    required List<Parable> traditionalParables,
    required List<String> jesusLifeSequence,
    required bool kidFriendlyOnly,
    Set<String> completedStoryIds = const <String>{},
  }) {
    final filtered = traditionalParables.where((p) {
      if (p.storytellingMode != 'traditional') return false;
      if (kidFriendlyOnly && !p.kidFriendly) return false;
      return true;
    }).toList(growable: false);

    return PathService._(
      parables: filtered,
      jesusLifeSequence: List<String>.unmodifiable(jesusLifeSequence),
      completedStoryIds: Set<String>.unmodifiable(completedStoryIds),
    );
  }

  /// True if the given story ID has been completed. Pure lookup against
  /// the constructor-time snapshot. Safe to call from build() methods.
  ///
  /// **This helper is ONLY consulted by `getResumePoint`,
  /// `getCompletionPercentage`, and UI completion markers. It is NEVER
  /// consulted by `getNextInPath` — path order is sacred (SPEC 50.6).**
  bool isStoryCompleted(String storyId) {
    return _completedStoryIds.contains(storyId);
  }

  // --------------------------------------------------------------------
  // getPathStories — ordered story list for a specific path
  // --------------------------------------------------------------------

  /// Returns the ordered list of parables belonging to the given
  /// `(pathType, pathId)` combination. Returns an empty list if the path
  /// is unknown or no stories match.
  List<Parable> getPathStories(PathType pathType, String pathId) {
    switch (pathType) {
      case PathType.jesusLife:
        return _storiesForJesusLife();
      case PathType.bibleOrder:
        return _storiesForBibleOrder(pathId);
      case PathType.timeline:
        return _storiesForTimeline(pathId);
      case PathType.themes:
        return _storiesForThemes(pathId);
      case PathType.characters:
        return _storiesForCharacters(pathId);
    }
  }

  List<Parable> _storiesForJesusLife() {
    // Preserve the curated sequence order. Only include sequence entries
    // that both (a) exist in the snapshot after kid-mode filtering and
    // (b) have `primaryCharacterId == "jesus"`. Missing stories are
    // silently skipped — the spec allows the curated index to reference
    // stories that may not yet be annotated.
    final byId = {for (final p in _parables) p.storyId: p};
    final result = <Parable>[];
    for (final storyId in _jesusLifeSequence) {
      final parable = byId[storyId];
      if (parable == null) continue;
      if (parable.primaryCharacterId != 'jesus') continue;
      result.add(parable);
    }
    return result;
  }

  List<Parable> _storiesForBibleOrder(String pathId) {
    // pathId is a book slug (e.g. "genesis", "matthew"). Match against
    // the book prefix of `bibleSourceRef`. Annotated stories must have
    // `bibleOrderIndex` — ones missing it are excluded from this path.
    final normalizedBook = pathId.trim().toLowerCase();
    if (normalizedBook.isEmpty) return const <Parable>[];

    final matches = _parables.where((p) {
      if (p.bibleOrderIndex == null) return false;
      final book = _bookSlugFromRef(p.bibleSourceRef);
      return book == normalizedBook;
    }).toList();

    matches.sort((a, b) {
      final byIdx = (a.bibleOrderIndex ?? 0).compareTo(b.bibleOrderIndex ?? 0);
      if (byIdx != 0) return byIdx;
      final byCharOrder = (a.characterPathOrder ?? 0)
          .compareTo(b.characterPathOrder ?? 0);
      if (byCharOrder != 0) return byCharOrder;
      return a.storyId.compareTo(b.storyId);
    });
    return matches;
  }

  List<Parable> _storiesForTimeline(String pathId) {
    // pathId is an era wire id (e.g. "kingdom"). Must be one of the 9
    // locked eras; unknown values return empty.
    if (TimelineEraParse.fromWire(pathId) == null) return const <Parable>[];

    final matches =
        _parables.where((p) => p.timelineEra == pathId).toList();
    matches.sort(_byBibleOrderIndex);
    return matches;
  }

  List<Parable> _storiesForThemes(String pathId) {
    // pathId is a theme wire id (e.g. "faith"). Must be one of the 8
    // locked theme tags; unknown values return empty.
    if (!ThemeTagParse.isValid(pathId)) return const <Parable>[];

    final matches = _parables.where((p) {
      final tags = p.themeTags;
      if (tags == null) return false;
      return tags.contains(pathId);
    }).toList();
    matches.sort(_byBibleOrderIndex);
    return matches;
  }

  List<Parable> _storiesForCharacters(String pathId) {
    // pathId is a primaryCharacterId. Jesus is explicitly excluded from
    // the Characters path list per SPEC 50.8 — returning empty for
    // `jesus` guarantees the path UI never surfaces Jesus here even if
    // a caller asks.
    if (pathId == 'jesus') return const <Parable>[];
    if (pathId.isEmpty) return const <Parable>[];

    final matches = _parables
        .where((p) => p.primaryCharacterId == pathId)
        .toList();

    matches.sort((a, b) {
      final byCharOrder = (a.characterPathOrder ?? 0)
          .compareTo(b.characterPathOrder ?? 0);
      if (byCharOrder != 0) return byCharOrder;
      final byIdx = (a.bibleOrderIndex ?? 0).compareTo(b.bibleOrderIndex ?? 0);
      if (byIdx != 0) return byIdx;
      return a.storyId.compareTo(b.storyId);
    });
    return matches;
  }

  // --------------------------------------------------------------------
  // getNextInPath — path-order-is-sacred advancement
  // --------------------------------------------------------------------

  /// Returns the next story in canonical path order after
  /// `positionInPath`, or null if the current story is the final entry
  /// in the path.
  ///
  /// **Path order is sacred** (SPEC Feature 50.6 — LOCKED): this method
  /// advances by position and NEVER filters by completion state.
  /// Completed stories remain in sequence. This is the central contract
  /// of PALs Paths — a guided Scripture journey, not a "what haven't
  /// you heard yet" checklist.
  Parable? getNextInPath(
    PathType pathType,
    String pathId,
    int positionInPath,
  ) {
    final stories = getPathStories(pathType, pathId);
    final nextIndex = positionInPath + 1;
    if (nextIndex < 0 || nextIndex >= stories.length) return null;
    return stories[nextIndex];
  }

  // --------------------------------------------------------------------
  // getPathInstances — list of instances for a path-type drill-down
  // --------------------------------------------------------------------

  /// Returns the list of available path instances for the given path
  /// type, after kid-mode filtering. Instances with zero eligible
  /// stories are excluded.
  ///
  /// For `jesusLife`, exactly one instance is returned (pathId
  /// `"default"`) when the curated sequence has any eligible entry
  /// after kid-mode filtering. Empty curated sequence → empty list.
  List<PathInstance> getPathInstances(PathType pathType) {
    switch (pathType) {
      case PathType.jesusLife:
        return _instancesForJesusLife();
      case PathType.bibleOrder:
        return _instancesForBibleOrder();
      case PathType.timeline:
        return _instancesForTimeline();
      case PathType.themes:
        return _instancesForThemes();
      case PathType.characters:
        return _instancesForCharacters();
    }
  }

  List<PathInstance> _instancesForJesusLife() {
    final stories = _storiesForJesusLife();
    if (stories.isEmpty) return const <PathInstance>[];
    return [
      PathInstance(
        pathType: PathType.jesusLife,
        pathId: 'default',
        displayLabel: 'The Life of Jesus',
        storyCount: stories.length,
      ),
    ];
  }

  List<PathInstance> _instancesForBibleOrder() {
    final byBook = <String, int>{};
    for (final p in _parables) {
      if (p.bibleOrderIndex == null) continue;
      final book = _bookSlugFromRef(p.bibleSourceRef);
      if (book == null || book.isEmpty) continue;
      byBook[book] = (byBook[book] ?? 0) + 1;
    }

    final instances = byBook.entries
        .map((e) => PathInstance(
              pathType: PathType.bibleOrder,
              pathId: e.key,
              displayLabel: _bookDisplayLabel(e.key),
              storyCount: e.value,
            ))
        .toList();
    // Sort by lowest bibleOrderIndex story within each book for a
    // stable canonical order across runs.
    instances.sort((a, b) {
      final minA = _minBibleOrderForBookSlug(a.pathId);
      final minB = _minBibleOrderForBookSlug(b.pathId);
      return minA.compareTo(minB);
    });
    return instances;
  }

  List<PathInstance> _instancesForTimeline() {
    final byEra = <String, int>{};
    for (final p in _parables) {
      final era = p.timelineEra;
      if (era == null) continue;
      if (TimelineEraParse.fromWire(era) == null) continue;
      byEra[era] = (byEra[era] ?? 0) + 1;
    }

    final instances = byEra.entries
        .map((e) => PathInstance(
              pathType: PathType.timeline,
              pathId: e.key,
              displayLabel: TimelineEraParse.fromWire(e.key)!.displayLabel,
              storyCount: e.value,
            ))
        .toList();
    // Sort by canonical era order (enum declaration order).
    instances.sort((a, b) {
      final ai = TimelineEra.values
          .indexWhere((era) => era.wireId == a.pathId);
      final bi = TimelineEra.values
          .indexWhere((era) => era.wireId == b.pathId);
      return ai.compareTo(bi);
    });
    return instances;
  }

  List<PathInstance> _instancesForThemes() {
    final byTheme = <String, int>{};
    for (final p in _parables) {
      final tags = p.themeTags;
      if (tags == null) continue;
      for (final tag in tags) {
        if (!ThemeTagParse.isValid(tag)) continue;
        byTheme[tag] = (byTheme[tag] ?? 0) + 1;
      }
    }

    final instances = byTheme.entries
        .map((e) => PathInstance(
              pathType: PathType.themes,
              pathId: e.key,
              displayLabel: ThemeTagParse.fromWire(e.key)!.displayLabel,
              storyCount: e.value,
            ))
        .toList();
    // Sort by canonical theme order (enum declaration order).
    instances.sort((a, b) {
      final ai = ThemeTag.values.indexWhere((t) => t.wireId == a.pathId);
      final bi = ThemeTag.values.indexWhere((t) => t.wireId == b.pathId);
      return ai.compareTo(bi);
    });
    return instances;
  }

  List<PathInstance> _instancesForCharacters() {
    final byChar = <String, int>{};
    for (final p in _parables) {
      final charId = p.primaryCharacterId;
      if (charId == null || charId.isEmpty) continue;
      // Jesus is reserved for jesus_life (SPEC 50.8) — NEVER surface in
      // the Characters path list.
      if (charId == 'jesus') continue;
      byChar[charId] = (byChar[charId] ?? 0) + 1;
    }

    final instances = byChar.entries
        .map((e) => PathInstance(
              pathType: PathType.characters,
              pathId: e.key,
              displayLabel: CharacterRegistry.getDisplayName(e.key),
              storyCount: e.value,
            ))
        .toList();
    // Sort alphabetically by display label for predictable UX.
    instances.sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    return instances;
  }

  // --------------------------------------------------------------------
  // getResumePoint — Continue Your Journey resume heuristic (SPEC 50.6b)
  // --------------------------------------------------------------------

  /// Returns the first uncompleted story in canonical path order, or the
  /// first story if every entry in the path is already completed (replay
  /// mode), or null if the path has no eligible stories.
  ///
  /// **This is the ONE path-related affordance that filters by completion
  /// state** (SPEC Feature 50.6b). It powers "Continue Your Journey" on
  /// the path detail screen. It is NOT used by the canonical player's
  /// "Next in Your Journey" block — that advances by canonical position
  /// (`getNextInPath`) and never filters by completion (SPEC 50.6 —
  /// path order is sacred).
  ///
  /// Kid-mode filtering is applied at the snapshot layer, so the
  /// returned story is always kid-eligible when kid mode is on.
  Parable? getResumePoint(PathType pathType, String pathId) {
    final stories = getPathStories(pathType, pathId);
    if (stories.isEmpty) return null;

    for (final story in stories) {
      if (!isStoryCompleted(story.storyId)) {
        return story;
      }
    }

    // Every story in the path is completed — jump to the first story
    // for replay from the beginning.
    return stories.first;
  }

  // --------------------------------------------------------------------
  // getCompletionPercentage — SPEC Feature 50.5
  // --------------------------------------------------------------------

  /// Returns path completion percentage in the range [0.0, 1.0].
  /// Computed as:
  ///
  ///     completed_eligible / total_eligible
  ///
  /// where "eligible" means the story passed kid-mode filtering at
  /// snapshot construction time. Ineligible stories never count toward
  /// either the numerator or the denominator, so a kid-mode user never
  /// sees a path stuck at "50% complete" because the remaining stories
  /// are adult-only (SPEC Feature 50.5 + INVARIANTS Kid Safety #3a).
  ///
  /// Edge cases:
  /// - Empty eligible set → returns 0.0 (never NaN)
  /// - All stories completed → returns 1.0
  /// - No completed stories → returns 0.0
  double getCompletionPercentage(PathType pathType, String pathId) {
    final stories = getPathStories(pathType, pathId);
    if (stories.isEmpty) return 0.0;

    final completedCount = stories
        .where((s) => isStoryCompleted(s.storyId))
        .length;
    return completedCount / stories.length;
  }

  // --------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------

  int _byBibleOrderIndex(Parable a, Parable b) {
    final byIdx = (a.bibleOrderIndex ?? 0).compareTo(b.bibleOrderIndex ?? 0);
    if (byIdx != 0) return byIdx;
    return a.storyId.compareTo(b.storyId);
  }

  int _minBibleOrderForBookSlug(String slug) {
    int min = 1 << 30;
    for (final p in _parables) {
      if (p.bibleOrderIndex == null) continue;
      if (_bookSlugFromRef(p.bibleSourceRef) != slug) continue;
      if (p.bibleOrderIndex! < min) min = p.bibleOrderIndex!;
    }
    return min;
  }

  /// Parse the book name from a `bibleSourceRef` like "1 Samuel 16:1-13"
  /// and normalize to a lowercase snake_case slug.
  ///
  /// Returns null if the reference is null/empty or does not contain a
  /// valid book prefix. The parser is deliberately minimal for Phase 2
  /// — it handles the 6 book names present in the first annotation
  /// batch: Genesis, Exodus, Ruth, 1 Samuel, Matthew, Luke. Additional
  /// books will parse correctly as long as the book name is followed by
  /// a space and a digit.
  static String? _bookSlugFromRef(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    // Find the first digit (start of chapter number) — everything
    // before it (trimmed) is the book name.
    final match = RegExp(r'^(.+?)\s+\d').firstMatch(ref);
    if (match == null) return null;
    final bookName = match.group(1)!.trim();
    return bookName.toLowerCase().replaceAll(' ', '_');
  }

  /// Reverse of [_bookSlugFromRef] — turn a slug like `"1_samuel"` into
  /// a human-readable display label `"1 Samuel"`. Preserves numbers.
  String _bookDisplayLabel(String slug) {
    final parts = slug.split('_');
    return parts.map((p) {
      if (p.isEmpty) return p;
      if (RegExp(r'^\d+$').hasMatch(p)) return p;
      return '${p[0].toUpperCase()}${p.substring(1)}';
    }).join(' ');
  }
}
