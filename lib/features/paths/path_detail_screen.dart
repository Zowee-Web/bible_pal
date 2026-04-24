import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics_events.dart';
import '../../models/parable.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';
import '../pals_parables/parable_player_screen.dart';
import 'path_launch_context.dart';
import 'path_type.dart';

/// Screen 3 of the PALs Paths drill-down (SPEC Feature 50).
///
/// Shows the ordered list of stories in a single path instance. Each
/// story tile shows title + scripture reference. Tapping a tile loads
/// the parable into the canonical player with a [PathLaunchContext] so
/// the player renders "Next in Your Journey" (SPEC Feature 50.6).
///
/// **Path order is sacred** (SPEC Feature 50.6 — LOCKED): completed
/// stories are NOT filtered out of the list. Phase 3 will add a subtle
/// gold completion marker; Phase 2 renders the list without markers.
class PathDetailScreen extends ConsumerStatefulWidget {
  final PathType pathType;
  final String pathId;
  final String displayLabel;

  const PathDetailScreen({
    super.key,
    required this.pathType,
    required this.pathId,
    required this.displayLabel,
  });

  @override
  ConsumerState<PathDetailScreen> createState() => _PathDetailScreenState();
}

class _PathDetailScreenState extends ConsumerState<PathDetailScreen> {
  @override
  void initState() {
    super.initState();
    // SPEC Feature 50.10: `path_opened` is strict — fire only when a
    // real path instance/detail is opened, not on every pill tap.
    // The detail screen is the meaningful "open" moment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnalyticsEvents.logPathOpened(
        pathType: widget.pathType.wireId,
        pathId: widget.pathId,
      );
      // For character paths, also fire character_path_selected.
      if (widget.pathType == PathType.characters) {
        // `language_style` comes from the first story's languageStyle
        // when available; fall back to WEB.
        final pathServiceAsync = ref.read(pathServiceProvider);
        final svc = pathServiceAsync.valueOrNull;
        String languageStyle = 'WEB';
        if (svc != null) {
          final stories =
              svc.getPathStories(widget.pathType, widget.pathId);
          if (stories.isNotEmpty) languageStyle = stories.first.languageStyle;
        }
        AnalyticsEvents.logCharacterPathSelected(
          characterId: widget.pathId,
          languageStyle: languageStyle,
        );
      }
    });
  }

  /// Launch a path-selected story by pushing the canonical length
  /// picker in PATH mode (SPEC Feature 6 + Feature 50.12). The length
  /// picker resolves the user's chosen variant and loads the player
  /// with the preserved [PathLaunchContext] so "Next in Your Journey"
  /// still advances by canonical position.
  ///
  /// Path stories open the canonical player directly. The player owns
  /// the load: it resolves the user's preferred length variant and calls
  /// `loadParable` from a post-frame callback in its own State, AFTER
  /// the route push has settled and a frame boundary has elapsed. See
  /// [ParablePlayerScreen] for why this avoids the iOS audio-session
  /// hang the in-place bypass produced.
  void _launchStory(
    BuildContext context,
    Parable parable,
    int positionInPath,
  ) {
    final launchContext = PathLaunchContext(
      pathType: widget.pathType,
      pathId: widget.pathId,
      positionInPath: positionInPath,
    );

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ParablePlayerScreen(
          pendingParable: parable,
          pendingLaunchContext: launchContext,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeInOut);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final pathServiceAsync = ref.watch(pathServiceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.foreground.primaryIcon),
        title: Text(
          widget.displayLabel,
          style: TextStyle(
            color: palette.foreground.primaryText,
            fontWeight: FontWeight.w600,
            shadows: palette.foreground.textShadow,
          ),
        ),
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: pathServiceAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(
                  "Couldn't load this path right now.",
                  style: TextStyle(color: palette.foreground.secondaryText),
                ),
              ),
              data: (pathService) {
                final stories =
                    pathService.getPathStories(widget.pathType, widget.pathId);
                if (stories.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'No stories in this path yet.',
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

                // Phase 3: Continue Your Journey affordance (SPEC
                // Feature 50.6b). Shown only when the user has ≥ 1
                // completed story on this path — otherwise the user
                // just taps the first story in the list.
                final completedCount = stories
                    .where((s) => pathService.isStoryCompleted(s.storyId))
                    .length;
                final showContinue = completedCount > 0;
                final resumePoint = showContinue
                    ? pathService.getResumePoint(
                        widget.pathType, widget.pathId)
                    : null;
                final resumeIndex = resumePoint == null
                    ? -1
                    : stories.indexWhere(
                        (s) => s.storyId == resumePoint.storyId);

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: stories.length + (showContinue ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (showContinue && index == 0) {
                      return _ContinueYourJourneyCard(
                        palette: palette,
                        resumeStory: resumePoint,
                        onTap: () {
                          if (resumePoint != null && resumeIndex >= 0) {
                            _launchStory(
                                context, resumePoint, resumeIndex);
                          }
                        },
                      );
                    }
                    final storyIdx =
                        showContinue ? index - 1 : index;
                    final story = stories[storyIdx];
                    final isCompleted =
                        pathService.isStoryCompleted(story.storyId);
                    return _StoryTile(
                      story: story,
                      position: storyIdx,
                      palette: palette,
                      isCompleted: isCompleted,
                      onTap: () => _launchStory(context, story, storyIdx),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  final Parable story;
  final int position;
  final SkyPalette palette;
  final bool isCompleted;
  final VoidCallback onTap;

  const _StoryTile({
    required this.story,
    required this.position,
    required this.palette,
    required this.onTap,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.cardBorder,
              width: 1.2,
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accentColor.withOpacity(0.18),
                    border: Border.all(
                      color: palette.accentColor.withOpacity(0.55),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${position + 1}',
                    style: TextStyle(
                      color: palette.accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        story.title,
                        style: TextStyle(
                          color: palette.foreground.primaryText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          shadows: palette.foreground.textShadow,
                        ),
                      ),
                      if (story.bibleSourceRef != null &&
                          story.bibleSourceRef!.isNotEmpty) ...[
                        const SizedBox(height: 3),
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
                // Phase 3: subtle gold check marker on completed stories
                // (SPEC Feature 50.6 + 50.6b). Minimal visual treatment —
                // no animation, no badge-like emphasis.
                if (isCompleted) ...[
                  Icon(
                    Icons.check_circle,
                    color: palette.accentColor,
                    size: 20,
                    semanticLabel: 'Completed',
                  ),
                  const SizedBox(width: 10),
                ],
                Icon(
                  Icons.play_arrow_rounded,
                  color: palette.accentColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Continue Your Journey card (SPEC Feature 50.6b — resume heuristic)
// ---------------------------------------------------------------------------

/// Card rendered at the top of the path detail list when the user has
/// ≥ 1 completion on the current path. Tapping it jumps to the resume
/// point (first uncompleted story, or first story if all complete).
///
/// This is the ONE path-related affordance that filters by completion
/// state. It is DIFFERENT from "Next in Your Journey" in the canonical
/// player, which advances by canonical position and never filters by
/// completion (path order is sacred — SPEC 50.6).
class _ContinueYourJourneyCard extends StatelessWidget {
  final SkyPalette palette;
  final Parable? resumeStory;
  final VoidCallback onTap;

  const _ContinueYourJourneyCard({
    required this.palette,
    required this.resumeStory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (resumeStory == null) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: palette.accentColor.withOpacity(0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.accentColor.withOpacity(0.20),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Continue Your Journey',
                  style: TextStyle(
                    color: palette.accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    shadows: palette.foreground.subtitleShadow,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  resumeStory!.title,
                  style: TextStyle(
                    color: palette.foreground.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    shadows: palette.foreground.textShadow,
                  ),
                ),
                if (resumeStory!.bibleSourceRef != null &&
                    resumeStory!.bibleSourceRef!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    resumeStory!.bibleSourceRef!,
                    style: TextStyle(
                      color: palette.foreground.secondaryText,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      shadows: palette.foreground.subtitleShadow,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
