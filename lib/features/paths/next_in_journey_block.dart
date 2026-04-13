import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/length_picker/length_picker_screen.dart';
import '../../models/parable.dart';
import '../../providers/parable_player_notifier.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import 'path_launch_context.dart';
import 'path_type.dart';

/// "Next in Your Journey" block rendered at the bottom of the canonical
/// Story Player (SPEC Feature 50.6 — LOCKED).
///
/// Rendering conditions (ALL must be true):
/// 1. `state.launchContext != null` — the current story was launched
///    from a PALs Paths context
/// 2. `state.playbackCompleted == true` — the story body has finished
/// 3. `PathService.getNextInPath()` returns a non-null next story —
///    the current story is NOT the final entry in the path
///
/// **Path order is sacred** (SPEC Feature 50.6 — LOCKED):
/// `getNextInPath()` advances by canonical position and NEVER filters
/// by completion state. A completed next story is rendered normally
/// (no auto-skip). Phase 3 will add a subtle completion marker; Phase 2
/// renders the next story without that marker.
///
/// Tapping the block calls `loadParable(nextStory, launchContext: next)`
/// where `next.positionInPath = current.positionInPath + 1`. Playback
/// does not auto-start — the user must tap Play on the main controls.
class NextInJourneyBlock extends ConsumerWidget {
  const NextInJourneyBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(parablePlayerProvider);

    // Condition 1: must be launched from a path
    final launchContext = playerState.launchContext;
    if (launchContext == null) return const SizedBox.shrink();

    // Condition 2: playback of the current story body must have completed
    if (!playerState.playbackCompleted) return const SizedBox.shrink();

    // Resolve the next story via PathService. PathService is async
    // (FutureProvider) so degrade gracefully if it's loading or errored.
    final pathServiceAsync = ref.watch(pathServiceProvider);
    final pathService = pathServiceAsync.valueOrNull;
    if (pathService == null) return const SizedBox.shrink();

    // Condition 3: there must BE a next story in canonical order
    final next = pathService.getNextInPath(
      launchContext.pathType,
      launchContext.pathId,
      launchContext.positionInPath,
    );
    if (next == null) return const SizedBox.shrink();

    // Phase 3: check whether the next story is already completed so
    // we can render a subtle completion marker. Path order is sacred —
    // we still render the block and advance normally; the marker is
    // purely informational. (SPEC Feature 50.6 — LOCKED.)
    final nextIsCompleted = pathService.isStoryCompleted(next.storyId);

    return _NextBlockBody(
      next: next,
      nextIsCompleted: nextIsCompleted,
      nextLaunchContext: PathLaunchContext(
        pathType: launchContext.pathType,
        pathId: launchContext.pathId,
        positionInPath: launchContext.positionInPath + 1,
      ),
    );
  }
}

class _NextBlockBody extends ConsumerWidget {
  final Parable next;
  final bool nextIsCompleted;
  final PathLaunchContext nextLaunchContext;

  const _NextBlockBody({
    required this.next,
    required this.nextIsCompleted,
    required this.nextLaunchContext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                'Next in Your Journey',
                style: TextStyle(
                  color: palette.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  shadows: palette.foreground.subtitleShadow,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      next.title,
                      style: TextStyle(
                        color: palette.foreground.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        shadows: palette.foreground.textShadow,
                      ),
                    ),
                  ),
                  // Phase 3: subtle completion marker when the next
                  // story has already been completed. Block still
                  // renders — path order is sacred.
                  if (nextIsCompleted) ...[
                    const SizedBox(width: 10),
                    Icon(
                      Icons.check_circle,
                      color: palette.accentColor,
                      size: 20,
                      semanticLabel: 'Completed',
                    ),
                  ],
                ],
              ),
              if (next.bibleSourceRef != null &&
                  next.bibleSourceRef!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  next.bibleSourceRef!,
                  style: TextStyle(
                    color: palette.foreground.secondaryText,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    shadows: palette.foreground.subtitleShadow,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: _NextPlayButton(
                  palette: palette,
                  onTap: () {
                    // SPEC Feature 6 + Feature 50.12 — path-launched
                    // stories route through the canonical length
                    // picker. The picker resolves the user's chosen
                    // variant and loads the player with the
                    // preserved launchContext so "Next in Your
                    // Journey" keeps advancing by canonical position.
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LengthPickerScreen(
                          fixedParable: next,
                          launchContext: nextLaunchContext,
                          pathSubtitle:
                              'From PALs Paths • ${nextLaunchContext.pathType.displayLabel}',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPlayButton extends StatelessWidget {
  final SkyPalette palette;
  final VoidCallback onTap;

  const _NextPlayButton({required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                color: palette.accentColor,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                'Play',
                style: TextStyle(
                  color: palette.accentColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
