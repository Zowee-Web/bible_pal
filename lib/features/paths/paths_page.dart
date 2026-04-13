import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_logger.dart';
import '../../models/parable.dart';
import '../../providers/parable_player_notifier.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/glass_input_decoration.dart';
import '../pals_parables/parable_player_screen.dart';
import 'path_detail_screen.dart';
import 'path_instance_list_screen.dart';
import 'path_type.dart';

/// PALs Paths page — right-most page of the main horizontal nav
/// (SPEC Feature 48 page 2 / Feature 50).
///
/// Phase 2 shell:
/// - Featured tile for `jesus_life` at the top (Feature 50.1b). Tapping
///   it navigates directly to the single `jesus_life` detail screen
///   (only one instance — skip the instance list).
/// - Four standard path-type pills (bible_order / timeline / themes /
///   characters). Tapping a pill navigates to a [PathInstanceListScreen]
///   for that path type.
/// - Bottom-anchored search input (Feature 50.7) — matches Mood page
///   style. Non-empty query replaces the content area with ranked
///   Traditional-only results. Empty query restores the default
///   featured tile + pill layout.
///
/// Tapping a search result loads the parable into the canonical player
/// WITHOUT a `PathLaunchContext` (standalone search launches do not
/// carry path context per SPEC 50.6).
class PathsPage extends ConsumerStatefulWidget {
  final ThemeData theme;

  const PathsPage({super.key, required this.theme});

  @override
  ConsumerState<PathsPage> createState() => PathsPageState();
}

class PathsPageState extends ConsumerState<PathsPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final next = _searchController.text.trim();
    if (next != _query) {
      setState(() => _query = next);
    }
  }

  /// Dismiss the software keyboard before navigating or on outside tap.
  /// Called before every Navigator.push on this page so the keyboard
  /// never persists across screens.
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _navigateToInstanceList(PathType pathType) {
    _dismissKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PathInstanceListScreen(pathType: pathType),
      ),
    );
  }

  void _navigateToJesusLife() {
    _dismissKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PathDetailScreen(
          pathType: PathType.jesusLife,
          pathId: 'default',
          displayLabel: 'The Life of Jesus',
        ),
      ),
    );
  }

  Future<void> _launchSearchResult(Parable story) async {
    _dismissKeyboard();
    // Standalone search launches pass launchContext: null — the player
    // will NOT render "Next in Your Journey" for these (SPEC 50.6).
    final notifier = ref.read(parablePlayerProvider.notifier);
    final loaded = await notifier.loadParable(story);
    if (!loaded) {
      logEvent('search_launch_failed', {
        'story_id': story.storyId,
      }, level: LogLevel.warn);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ParablePlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    // Tap-outside-to-dismiss. HitTestBehavior.opaque lets taps on empty
    // areas of the page reach this detector; taps on interactive
    // children (cards, TextField) are absorbed by those widgets first
    // so they still work normally.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboard,
      child: Column(
        children: [
          // PALs Paths page title (SPEC Feature 48 page 2). Centered
          // above the hero Life of Jesus card so the header feels
          // balanced with the stack below. Raised slightly to reduce
          // dead space between the title and the rest of the content.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'PALs Paths',
                style: TextStyle(
                  color: palette.foreground.primaryText,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  shadows: palette.foreground.textShadow,
                ),
              ),
            ),
          ),

          // Content area — vertical path stack when no query, search
          // results when a query is set. The path stack replaces the
          // pre-polish horizontal pill row (SPEC Feature 48 page 2
          // pill rail) with a vertical cross-inspired rhythm: the
          // hero Life of Jesus card sits at the top with a wider
          // bleed, the 4 standard path cards stack below with a
          // narrower margin, creating a subtle T-silhouette.
          Expanded(
            child: _query.isEmpty
                ? _PathHomeContent(
                    palette: palette,
                    theme: widget.theme,
                    onTapJesusLife: _navigateToJesusLife,
                    onTapBibleOrder: () =>
                        _navigateToInstanceList(PathType.bibleOrder),
                    onTapTimeline: () =>
                        _navigateToInstanceList(PathType.timeline),
                    onTapThemes: () =>
                        _navigateToInstanceList(PathType.themes),
                    onTapCharacters: () =>
                        _navigateToInstanceList(PathType.characters),
                  )
                : _SearchResults(
                    query: _query,
                    palette: palette,
                    theme: widget.theme,
                    onResultTap: _launchSearchResult,
                  ),
          ),

          // Bottom-anchored search input (Feature 50.7) — matches Mood
          // page style (glass surface, keyboard-safe, does not scroll).
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _PathsSearchInput(
              controller: _searchController,
              focusNode: _searchFocus,
              palette: palette,
              onDismissKeyboard: _dismissKeyboard,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PathHomeContent — vertical cross-inspired path stack (Phase 3.2 polish)
// ---------------------------------------------------------------------------

/// Default PALs Paths content area: the hero Life of Jesus card at the
/// top followed by a vertical stack of 4 standard path cards (Bible
/// Order / Timeline / Themes / Characters) in the order locked by the
/// Phase 3.2 polish spec.
///
/// Layout creates a subtle cross-inspired silhouette:
/// - Hero card uses a **wider** bleed (horizontal margin 14)
/// - Standard cards use a **narrower** bleed (horizontal margin 24)
/// The 10pt width differential reads as a soft crossbar-above-spine
/// shape without being a literal cross. No rigid geometry.
///
/// When the user is searching, the parent Expanded swaps this widget
/// for `_SearchResults`; the path stack is hidden so results get the
/// full content area.
class _PathHomeContent extends StatelessWidget {
  final SkyPalette palette;
  final ThemeData theme;
  final VoidCallback onTapJesusLife;
  final VoidCallback onTapBibleOrder;
  final VoidCallback onTapTimeline;
  final VoidCallback onTapThemes;
  final VoidCallback onTapCharacters;

  const _PathHomeContent({
    required this.palette,
    required this.theme,
    required this.onTapJesusLife,
    required this.onTapBibleOrder,
    required this.onTapTimeline,
    required this.onTapThemes,
    required this.onTapCharacters,
  });

  @override
  Widget build(BuildContext context) {
    // Centered vertical cross composition (Option A). Every card sits
    // on a single vertical axis with a fixed width — the hero is
    // slightly wider as the anchor, and the 4 spine cards share a
    // uniform narrower width so the stack reads as a symbolic column,
    // not a menu. Widths are fixed (not phase-aware) because the
    // composition is pure geometry.
    const double heroMaxWidth = 360;
    const double spineMaxWidth = 200;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),

          // Hero — The Life of Jesus (SPEC 50.1b — LOCKED position).
          Center(
            child: SizedBox(
              width: heroMaxWidth,
              child: _PathHeroCard(
                palette: palette,
                onTap: onTapJesusLife,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Spine — Characters first (directly under the hero), then
          // Bible Order, Timeline, Themes. All uniform width, all on
          // the same vertical axis as the hero.
          Center(
            child: SizedBox(
              width: spineMaxWidth,
              child: _PathStandardCard(
                label: PathType.characters.displayLabel,
                subtitle: 'Voices of Scripture',
                palette: palette,
                onTap: onTapCharacters,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: spineMaxWidth,
              child: _PathStandardCard(
                label: PathType.bibleOrder.displayLabel,
                subtitle: 'Book by book',
                palette: palette,
                onTap: onTapBibleOrder,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: spineMaxWidth,
              child: _PathStandardCard(
                label: PathType.timeline.displayLabel,
                subtitle: 'Through the ages',
                palette: palette,
                onTap: onTapTimeline,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: spineMaxWidth,
              child: _PathStandardCard(
                label: PathType.themes.displayLabel,
                subtitle: 'By what they teach',
                palette: palette,
                onTap: onTapThemes,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Helper text — Phase 3.2 polish copy update.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              'Pick a path above, or search below.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.foreground.secondaryText,
                shadows: palette.foreground.subtitleShadow,
              ),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card — The Life of Jesus. Centered text, no icon, no chevron.
// Dominance comes from width and typography, not decoration.
// ---------------------------------------------------------------------------

class _PathHeroCard extends StatelessWidget {
  final SkyPalette palette;
  final VoidCallback onTap;

  const _PathHeroCard({
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.foreground.primaryText,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'The Life of Jesus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foreground.primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  shadows: palette.foreground.textShadow,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'A guided journey',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foreground.secondaryText,
                  fontSize: 12,
                  shadows: palette.foreground.subtitleShadow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Standard path card (Bible Order / Timeline / Themes / Characters)
// ---------------------------------------------------------------------------

/// Narrow fixed-width rounded card used by the 4 standard path types
/// in the centered vertical cross composition. Centered title +
/// subtitle, no icon, no chevron — the composition carries all the
/// weight, not the card internals.
class _PathStandardCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _PathStandardCard({
    required this.label,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.foreground.primaryText,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foreground.primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  shadows: palette.foreground.textShadow,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foreground.secondaryText,
                  fontSize: 11,
                  shadows: palette.foreground.subtitleShadow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom-anchored search input (SPEC Feature 50.7)
// ---------------------------------------------------------------------------

/// PALs Paths bottom-anchored search input (SPEC Feature 50.7).
///
/// Visually identical to the Mood page text input (SPEC Feature 48
/// page 2: "Bottom-anchored search input matching the Mood page input
/// style"). Both surfaces use the shared [glassInputDecoration] helper
/// so their container shape, padding, border, fill, and hint styling
/// are literally the same.
class _PathsSearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final SkyPalette palette;
  final VoidCallback onDismissKeyboard;

  const _PathsSearchInput({
    required this.controller,
    required this.focusNode,
    required this.palette,
    required this.onDismissKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: glassInputTextStyle(palette),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.search,
      // SPEC Feature 50.7: the ONLY difference from the Mood input is
      // the placeholder text (and the leading search glyph). Short
      // copy — character/story are already implied by the PALs Paths
      // surface so we don't need to spell them out.
      decoration: glassInputDecoration(
        palette: palette,
        hintText: 'Search Scripture',
        prefixIcon: Icon(
          Icons.search,
          color: palette.foreground.secondaryIcon,
          size: 22,
        ),
      ),
      // Dismiss keyboard on submit so the user can see the results
      // area cleanly. Query is already reactive via onChanged, so
      // submit is otherwise a no-op.
      onSubmitted: (_) => onDismissKeyboard(),
    );
  }
}

// ---------------------------------------------------------------------------
// Search results list (Tier 1 > Tier 2 > Tier 3 per SearchService)
// ---------------------------------------------------------------------------

class _SearchResults extends ConsumerWidget {
  final String query;
  final SkyPalette palette;
  final ThemeData theme;
  final void Function(Parable story) onResultTap;

  const _SearchResults({
    required this.query,
    required this.palette,
    required this.theme,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchServiceAsync = ref.watch(searchServiceProvider);
    return searchServiceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(
          "Couldn't search right now.",
          style: TextStyle(color: palette.foreground.secondaryText),
        ),
      ),
      data: (searchService) {
        final results = searchService.search(query);
        if (results.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'No stories matched.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foreground.secondaryText,
                  fontSize: 15,
                  shadows: palette.foreground.subtitleShadow,
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _SearchResultTile(
            story: results[index],
            palette: palette,
            onTap: () => onResultTap(results[index]),
          ),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Parable story;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.story,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.cardBorder, width: 1),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        story.title,
                        style: TextStyle(
                          color: palette.foreground.primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          shadows: palette.foreground.textShadow,
                        ),
                      ),
                      if (story.bibleSourceRef != null &&
                          story.bibleSourceRef!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          story.bibleSourceRef!,
                          style: TextStyle(
                            color: palette.foreground.secondaryText,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            shadows: palette.foreground.subtitleShadow,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.play_arrow_rounded,
                  color: palette.accentColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
