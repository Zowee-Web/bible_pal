import '../models/parable.dart';

/// Priority-ranked Traditional-only search for PALs Paths (SPEC Feature 50.7).
///
/// Design contract (LOCKED):
/// - Pure function over constructor inputs — same snapshot + same query
///   → same ranked result every call.
/// - Operates ONLY on Traditional stories. Creative stories are
///   defensively re-filtered at the constructor (Story Mode Non-Blur
///   Invariant #6).
/// - Kid-mode filter applied at the snapshot layer.
/// - The raw query string is NEVER logged, persisted, or included in
///   telemetry (INVARIANTS Analytics Telemetry Privacy — Search query
///   privacy). The `search()` method takes the query and returns
///   results. No other side effects.
///
/// Priority order (LOCKED per SPEC 50.7):
///   1. Scripture anchor match — `bibleSourceRef` exact-normalized OR
///      `bibleStoryKey` substring/normalized match
///   2. Chapter or book match — query parsed as a Bible reference
///      ("Book", "Book Chapter", "Book Chapter:Verse", or
///      "Book Chapter:Verse-Verse") against the story's bibleSourceRef
///   3. Metadata match — substring match (case-insensitive) against
///      title, characterDisplayNames, characterIds,
///      primaryCharacterDisplayName, themeTags, and bibleStoryKey
///
/// Ties within a tier are broken by `bibleOrderIndex` ascending, then
/// `storyId`.
class SearchService {
  /// Snapshot of Traditional + kid-eligible parables. Already filtered.
  final List<Parable> _parables;

  const SearchService._(this._parables);

  /// Construct a SearchService from a snapshot of all Traditional
  /// parables + the kid-mode flag. The constructor filters defensively:
  /// Creative stories excluded (belt-and-suspenders against upstream
  /// drift) and non-kid stories excluded when `kidFriendlyOnly` is true.
  factory SearchService({
    required List<Parable> traditionalParables,
    required bool kidFriendlyOnly,
  }) {
    final filtered = traditionalParables.where((p) {
      if (p.storytellingMode != 'traditional') return false;
      if (kidFriendlyOnly && !p.kidFriendly) return false;
      return true;
    }).toList(growable: false);
    return SearchService._(filtered);
  }

  /// Search the snapshot for the given query, returning a priority-
  /// ranked list. Empty query returns an empty list. The query string
  /// is never logged or persisted.
  List<Parable> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <Parable>[];

    final parsed = _parseReference(normalized);

    final tier1 = <Parable>[]; // scripture anchor (exact)
    final tier2 = <Parable>[]; // chapter/book match (parsed reference)
    final tier3 = <Parable>[]; // metadata substring
    final seen = <String>{};

    for (final p in _parables) {
      final ref = (p.bibleSourceRef ?? '').toLowerCase();
      final storyKey = (p.bibleStoryKey ?? '').toLowerCase();

      // Tier 1: scripture anchor match
      if (ref == normalized || storyKey == normalized) {
        if (seen.add(p.storyId)) tier1.add(p);
        continue;
      }

      // Tier 1 also: bibleStoryKey substring match (e.g. "zacchaeus"
      // matches bibleStoryKey "zacchaeus")
      if (storyKey.isNotEmpty && storyKey.contains(normalized)) {
        if (seen.add(p.storyId)) tier1.add(p);
        continue;
      }

      // Tier 2: parsed-reference match
      if (parsed != null && _matchesReference(p, parsed)) {
        if (seen.add(p.storyId)) tier2.add(p);
        continue;
      }

      // Tier 3: metadata substring match
      if (_matchesMetadata(p, normalized)) {
        if (seen.add(p.storyId)) tier3.add(p);
        continue;
      }
    }

    // Sort within tiers by bibleOrderIndex ascending, then storyId.
    int comparator(Parable a, Parable b) {
      final byIdx =
          (a.bibleOrderIndex ?? 0).compareTo(b.bibleOrderIndex ?? 0);
      if (byIdx != 0) return byIdx;
      return a.storyId.compareTo(b.storyId);
    }

    tier1.sort(comparator);
    tier2.sort(comparator);
    tier3.sort(comparator);

    return [...tier1, ...tier2, ...tier3];
  }

  // --------------------------------------------------------------------
  // Reference parsing
  // --------------------------------------------------------------------

  /// Parses a normalized (lowercase, trimmed) query into a
  /// [_ParsedReference] if it looks like a Bible reference, or null if
  /// it does not. Minimal parser — Phase 2 handles the 6 books present
  /// in the first annotation batch plus a few extras for robustness.
  static _ParsedReference? _parseReference(String normalized) {
    // Match: "<book>" optionally followed by " <chapter>" optionally
    // followed by ":<verse>[-<verse>]". The book may be multi-word and
    // may start with a leading digit ("1 samuel").
    final re = RegExp(
      r'^((?:\d\s+)?[a-z]+)(?:\s+(\d+))?(?:\s*:\s*(\d+)(?:\s*-\s*(\d+))?)?$',
    );
    final m = re.firstMatch(normalized);
    if (m == null) return null;

    final rawBook = m.group(1)!.trim();
    final bookSlug = rawBook.replaceAll(RegExp(r'\s+'), '_');
    if (!_knownBookSlugs.contains(bookSlug)) return null;

    final chapter = m.group(2) != null ? int.tryParse(m.group(2)!) : null;
    final verseStart = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
    final verseEnd = m.group(4) != null ? int.tryParse(m.group(4)!) : null;

    return _ParsedReference(
      bookSlug: bookSlug,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
    );
  }

  /// Known book slugs for the parser. Deliberately small for Phase 2 —
  /// covers the first annotation batch (Genesis, Exodus, Ruth, 1 Samuel,
  /// Matthew, Luke) plus a handful of common extras so the parser
  /// degrades gracefully as more books get annotated. A full-featured
  /// parser lands in a later phase.
  static const Set<String> _knownBookSlugs = {
    'genesis',
    'exodus',
    'leviticus',
    'numbers',
    'deuteronomy',
    'joshua',
    'judges',
    'ruth',
    '1_samuel',
    '2_samuel',
    '1_kings',
    '2_kings',
    'psalms',
    'proverbs',
    'isaiah',
    'jeremiah',
    'daniel',
    'jonah',
    'matthew',
    'mark',
    'luke',
    'john',
    'acts',
    'romans',
    'hebrews',
  };

  bool _matchesReference(Parable p, _ParsedReference parsed) {
    final ref = p.bibleSourceRef;
    if (ref == null || ref.isEmpty) return false;

    // Extract the book name from the parable's reference and compare.
    final match = RegExp(r'^(.+?)\s+(\d+)(?::(\d+)(?:-(\d+))?)?').firstMatch(ref);
    if (match == null) return false;

    final refBook =
        match.group(1)!.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (refBook != parsed.bookSlug) return false;

    // Book-only query: match any story in that book.
    if (parsed.chapter == null) return true;

    final refChapter = int.tryParse(match.group(2)!);
    if (refChapter == null) return false;
    if (refChapter != parsed.chapter) return false;

    // Chapter-only query: match any story in that chapter.
    if (parsed.verseStart == null) return true;

    final refVerseStart =
        match.group(3) != null ? int.tryParse(match.group(3)!) : null;
    final refVerseEnd =
        match.group(4) != null ? int.tryParse(match.group(4)!) : null;

    // Verse range query: check overlap with the parable's verse range.
    if (refVerseStart == null) return false;
    final parsedEnd = parsed.verseEnd ?? parsed.verseStart!;
    final refEnd = refVerseEnd ?? refVerseStart;
    // Overlap test.
    return parsed.verseStart! <= refEnd && parsedEnd >= refVerseStart;
  }

  // --------------------------------------------------------------------
  // Metadata substring matching
  // --------------------------------------------------------------------

  bool _matchesMetadata(Parable p, String normalized) {
    if (p.title.toLowerCase().contains(normalized)) return true;

    final primaryDisplay =
        p.primaryCharacterDisplayName?.toLowerCase() ?? '';
    if (primaryDisplay.contains(normalized)) return true;

    final primaryId = p.primaryCharacterId?.toLowerCase() ?? '';
    if (primaryId.contains(normalized)) return true;

    final characterIds = p.characterIds ?? const <String>[];
    for (final id in characterIds) {
      if (id.toLowerCase().contains(normalized)) return true;
    }

    final characterNames = p.characterDisplayNames ?? const <String>[];
    for (final name in characterNames) {
      if (name.toLowerCase().contains(normalized)) return true;
    }

    final themeTags = p.themeTags ?? const <String>[];
    for (final tag in themeTags) {
      if (tag.toLowerCase().contains(normalized)) return true;
    }

    // bibleStoryKey substring already covered in Tier 1 as a scripture
    // anchor match, but keep a metadata-tier fallback for partial hits
    // not caught there.
    final storyKey = p.bibleStoryKey?.toLowerCase() ?? '';
    if (storyKey.contains(normalized)) return true;

    return false;
  }
}

/// Internal parsed-reference representation. Not exported.
class _ParsedReference {
  final String bookSlug;
  final int? chapter;
  final int? verseStart;
  final int? verseEnd;

  const _ParsedReference({
    required this.bookSlug,
    this.chapter,
    this.verseStart,
    this.verseEnd,
  });
}
