import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/story_length_bucket.dart';
import '../../core/app_logger.dart';
import '../../models/parable.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/parable_player_notifier.dart';
import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';
import '../pals_parables/parable_player_screen.dart';
import '../paths/path_launch_context.dart';

/// Full-screen story length picker shown before the audio player.
///
/// Two modes (SPEC Feature 6 + Feature 50.12 — one canonical length
/// picker, one canonical player):
///
/// 1. **Mood mode** (existing): receives a detected `mood` and optional
///    `userText`, calls `selectParable()` to resolve a story for the
///    chosen length bucket, then loads the player.
///
/// 2. **Path mode** (Phase 3.1): receives a `fixedParable` already
///    chosen by the user from a PALs Paths flow plus a non-null
///    `launchContext`. The user picks a length, the length picker
///    resolves the matching variant of the same story by
///    `(bibleStoryKey, languageStyle, kidFriendly, storyLength)`, then
///    loads the player with the original `launchContext` preserved so
///    "Next in Your Journey" still advances correctly.
///
/// Exactly one mode is active per push:
/// - Mood mode:  `fixedParable == null && launchContext == null`
/// - Path mode:  `fixedParable != null && launchContext != null`
class LengthPickerScreen extends ConsumerStatefulWidget {
  final String mood;
  final String userText;

  /// When set, the picker operates in PATH mode — the user has already
  /// chosen a specific story from a path, and the picker just selects
  /// a length variant of it. The story's [Parable.bibleStoryKey],
  /// [Parable.languageStyle], and [Parable.kidFriendly] are used to
  /// find the matching variant.
  final Parable? fixedParable;

  /// Required in PATH mode. Carries the launch context through to the
  /// player so `Next in Your Journey` advances by canonical position.
  final PathLaunchContext? launchContext;

  /// Optional subtitle shown in PATH mode (e.g. "From PALs Paths • David").
  final String? pathSubtitle;

  /// Optional hint: the bibleStoryKey pre-selected by PAL's preview.
  /// In MOOD mode, constrains selectParable() to variants of this story.
  /// Falls back to normal selection if no variant matches the chosen length.
  final String? bibleStoryKey;

  const LengthPickerScreen({
    super.key,
    this.mood = '',
    this.userText = '',
    this.fixedParable,
    this.launchContext,
    this.pathSubtitle,
    this.bibleStoryKey,
  }) : assert(
          (fixedParable == null && launchContext == null) ||
              (fixedParable != null && launchContext != null),
          'fixedParable and launchContext must be set together (path mode) '
          'or both null (mood mode).',
        );

  @override
  ConsumerState<LengthPickerScreen> createState() => _LengthPickerScreenState();
}

class _LengthPickerScreenState extends ConsumerState<LengthPickerScreen> {
  bool _isLoading = false;
  StoryLengthBucket? _selectedBucket;

  /// PATH-MODE variant resolver (SPEC Feature 6 + Feature 50.12).
  ///
  /// Delegates to [ParableService.resolveVariant] — the canonical
  /// 4-axis match shared by length picker, player screen, and PALs
  /// Paths. Does NOT invoke mood expansion.
  Future<Parable?> _resolvePathVariant(StoryLengthBucket bucket) async {
    final fixed = widget.fixedParable!;
    final parableService = await ref.read(parableServiceProvider.future);
    return parableService.resolveVariant(
      current: fixed,
      storyLength: bucket.name,
      languageStyle: fixed.languageStyle,
    );
  }

  Future<void> _pickLength(StoryLengthBucket bucket) async {
    if (_isLoading) return;

    // Visual selection + haptic
    HapticFeedback.lightImpact();
    setState(() => _selectedBucket = bucket);

    // Brief pause to let glow animation show before navigating
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      ref.read(sessionLengthBucketProvider.notifier).state = bucket;
      await appStateNotifier.updatePreferredLengthBucket(bucket.name);

      logEvent('length_selected', {
        'length_bucket': bucket.name,
        'detected_mood': widget.mood,
      });

      // PATH MODE — resolve a variant of the fixed parable. Mood
      // expansion is bypassed (Mood Expansion Serving Invariant scope —
      // path launches are deterministic, not mood-driven).
      Parable? parable;
      if (widget.fixedParable != null) {
        parable = await _resolvePathVariant(bucket);
        if (parable == null) {
          setState(() {
            _isLoading = false;
            _selectedBucket = null;
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'No ${bucket.displayLabel.toLowerCase()} version of this story yet.'),
            ),
          );
          return;
        }
      } else {
        // MOOD MODE — select story for the chosen length.
        // If bibleStoryKey hint is set (from PAL preview), constrain to that story.
        parable = await appStateNotifier.selectParable(
          mood: widget.mood,
          lengthBucket: bucket,
          userText: widget.userText,
          bibleStoryKey: widget.bibleStoryKey,
        );
      }

      if (!mounted) return;

      if (parable == null) {
        setState(() {
          _isLoading = false;
          _selectedBucket = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No story available for this mood and length yet.')),
        );
        return;
      }

      await appStateNotifier.addToHistory(parable);
      if (!mounted) return;

      // Preserve launchContext in PATH mode so the player renders
      // "Next in Your Journey" and `story_completed` telemetry
      // records `source: 'path'`.
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      final success = await playerNotifier.loadParable(
        parable,
        launchContext: widget.launchContext,
      );

      if (!mounted) return;

      if (!success) {
        final playerState = ref.read(parablePlayerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(playerState.errorMessage ??
                'This story needs an internet connection the first time you play it.'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Smooth fade + scale transition into player
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ParablePlayerScreen(),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
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
    } catch (e) {
      setState(() {
        _isLoading = false;
        _selectedBucket = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: palette.foreground.primaryText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Finding your story...',
                          style: TextStyle(
                            fontSize: 16,
                            color: palette.foreground.primaryText,
                            shadows: palette.foreground.textShadow,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      const Spacer(flex: 2),

                      Text(
                        'How long would you like\nyour story?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: palette.foreground.primaryText,
                          shadows: palette.foreground.textShadow,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // PATH-MODE subtitle (Phase 3.1 polish). Shows
                      // "From PALs Paths • David" so the user knows
                      // the length choice will load a specific path
                      // story rather than a mood-driven pick.
                      if (widget.pathSubtitle != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.pathSubtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.foreground.secondaryText,
                            letterSpacing: 0.3,
                            shadows: palette.foreground.subtitleShadow,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 32),

                      // Three length cards
                      for (final bucket in StoryLengthBucket.values) ...[
                        _LengthCard(
                          bucket: bucket,
                          isSelected: _selectedBucket == bucket,
                          palette: palette,
                          onTap: () => _pickLength(bucket),
                        ),
                      ],

                      const Spacer(flex: 3),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Individual length card with glow + scale on selection.
class _LengthCard extends StatefulWidget {
  final StoryLengthBucket bucket;
  final bool isSelected;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _LengthCard({
    required this.bucket,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_LengthCard> createState() => _LengthCardState();
}

class _LengthCardState extends State<_LengthCard> {
  bool _pressed = false;

  double get _scale {
    if (_pressed) return 0.97;
    if (widget.isSelected) return 1.03;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final bucket = widget.bucket;
    final isSelected = widget.isSelected;
    final glow = palette.glowIntensity;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: isSelected
                  ? palette.warmHighlight.withOpacity(0.12)
                  : palette.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? palette.warmHighlight
                    : palette.cardBorder,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: palette.warmHighlight.withOpacity(0.40 * glow),
                        blurRadius: 22,
                        spreadRadius: 3,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  bucket.displayLabel,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: palette.foreground.primaryText,
                    letterSpacing: 0.3,
                    shadows: palette.foreground.textShadow,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  bucket.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.foreground.secondaryText,
                    shadows: palette.foreground.subtitleShadow,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
