import 'dart:async';
import 'dart:io' show File;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import 'package:just_audio/just_audio.dart'
    show PlayerException, PlayerInterruptedException;
import '../../core/journey_testing_config.dart';
import '../../core/pal_voice_registry.dart';
import '../../services/pal_audio_service.dart' show PalAudioService;
import '../journey/journey_continuation_offer.dart';
import '../journey/journey_offer_runtime.dart';
import '../pal_memory/pal_memory_runtime.dart';
import '../../services/pal_prompt_service.dart';
import '../../services/stt_service.dart';
import '../../providers/service_providers.dart';
import '../../core/biblical_figure_registry.dart';
import '../../core/pal_reflection_lines.dart';
import '../../core/pal_transition_lines.dart';
import '../pal/opening/pal_opening_lines.dart';
import '../pal/opening/pal_opening_recency.dart';
import '../../theme/app_theme.dart';
import '../../theme/living_sky.dart';
import '../onboarding/first_launch_screen.dart' show kPalIntroShownKey;
import '../kids/parent_lock_flows.dart';
import '../settings/settings_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HapticFeedback;
import '../../providers/parable_player_notifier.dart';
import '../../models/parable.dart';
import '../../core/story_length_bucket.dart';
import '../../core/kid_feeling_cards.dart';
import '../pals_parables/parable_player_screen.dart';
import '../consent/voice_consent_dialog.dart';
import '../../core/app_logger.dart';
import '../../widgets/glass_input_decoration.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/premium_components.dart';
import '../paths/paths_page.dart';

/// Re-entrancy guard shared across mood/text/voice entry flows so the user
/// can't double-tap themselves into two parallel selections.
bool _moodFlowSelecting = false;

/// Session-scope flag — Journey Doctrine Slice 2. Once the journey
/// cascade SPEAKS at cold-open (offer audio plays — regardless of how
/// the user responds), subsequent cold-opens in the same session skip
/// the cascade. The engine's 3-day cooldown already handles the adult
/// lane long-term; this flag is what keeps the kid lane (no cooldown
/// per the Kid-Lane Appendix) from re-offering on every PAL tap.
/// Resets on app launch.
bool _journeyCascadeSpokenThisSession = false;

/// PAL Memory Doctrine Slice 2d (see docs/PAL_MEMORY_DOCTRINE.md):
/// resolve every cascade dependency from Riverpod and run
/// [fireMemoryLine]. Always awaited from [selectStoryAndOpenPlayer] so
/// the player screen never opens over a memory carrier. Errors are
/// absorbed by [fireMemoryLine]; this wrapper exists only to bridge
/// Riverpod ↔ the pure-ish cascade.
Future<void> _maybeSpeakMemoryLine(WidgetRef ref) async {
  final appState = ref.read(appStateProvider).valueOrNull;
  final preferences = appState?.userPreferences;
  // Short-circuit cheaply if preferences are missing — avoids loading
  // any of the heavier providers in the bootstrap-failure case.
  if (preferences == null) return;

  final sessionStore = await ref.read(palSessionStoreProvider.future);
  final registry =
      await ref.read(palMemoryDisplayNameRegistryProvider.future);
  final audioResolver = await ref.read(memoryAudioResolverProvider.future);
  final palAudio = ref.read(palAudioServiceProvider);

  await fireMemoryLine(
    preferences: preferences,
    sessionStore: sessionStore,
    displayNameRegistry: registry,
    audioResolver: audioResolver,
    playPlan: palAudio.playMemoryPlan,
    now: DateTime.now(),
    logger: logEvent,
  );
}

/// Selects a story for the given mood using the user's saved
/// `preferredLengthBucket` and current preferences, loads it into the
/// player, and navigates straight to the player screen with a one-time
/// arrival animation. Replaces the legacy length-picker step in the
/// mood/text/voice flows. PALs Paths still goes through `LengthPickerScreen`.
Future<void> selectStoryAndOpenPlayer({
  required WidgetRef ref,
  required BuildContext context,
  required String mood,
  required String userText,
  String? bibleStoryKey,
}) async {
  if (_moodFlowSelecting) return;
  _moodFlowSelecting = true;
  try {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final appState = ref.read(appStateProvider).valueOrNull;
    final savedBucketName =
        appState?.userPreferences.preferredLengthBucket ?? 'short';
    final bucket = StoryLengthBucket.fromJson(savedBucketName);

    // Keep session-scoped bucket in sync (back-compat with rest of app).
    ref.read(sessionLengthBucketProvider.notifier).state = bucket;

    logEvent('mood_flow_story_select', {
      'mood': mood,
      'length_bucket': bucket.name,
      'has_user_text': userText.isNotEmpty,
      'has_bible_story_key': bibleStoryKey != null,
    });

    // PAL Memory Doctrine Slice 2d — speak a memory line if the cascade
    // allows. Awaited so the player screen does NOT open over the
    // carrier. Errors are absorbed inside the helper.
    //
    // The Journey Doctrine Slice 2 cascade (offer + STT + dispatch)
    // does NOT fire from this entry point in V1 — the user has
    // already expressed intent by tapping a mood, so an STT response
    // window would be confusing. Journey lives at the cold-open
    // (PAL button) path; see [_MainMenuScreenState._runConversation].
    await _maybeSpeakMemoryLine(ref);
    if (!context.mounted) return;

    final parable = await appStateNotifier.selectParable(
      mood: mood,
      lengthBucket: bucket,
      userText: userText,
      bibleStoryKey: bibleStoryKey,
    );

    if (!context.mounted) return;
    if (parable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No story available for this mood yet.'),
        ),
      );
      return;
    }

    await appStateNotifier.addToHistory(parable);
    if (!context.mounted) return;

    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    // Mood flow: no launchContext (PALs Paths owns that field).
    final success = await playerNotifier.loadParable(parable);
    if (!context.mounted) return;

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

    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const ParablePlayerScreen(showArrivalAnimation: true),
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
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  } finally {
    _moodFlowSelecting = false;
  }
}

/// Main Menu Screen
/// Based on SPEC Feature 48 — Main Horizontal Navigation (LOCKED 3 pages).
///
/// Layout: three-page horizontal PageView. Default landing page is PAL
/// Sanctuary at index 0.
/// - Page 0 (PAL Sanctuary): PAL orb hero, Daily Bread verse, swipe hint
/// - Page 1 (Mood): Mood buttons, Text PAL, Read Story, Favorites/History/My PALs
///   (class name retained as `_StudyPage` internally to minimize diff)
/// - Page 2 (PALs Paths): Path-type selector + search (SPEC Feature 50)
class MainMenuScreen extends ConsumerWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appStateAsync = ref.watch(appStateProvider);

    return appStateAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.parchment,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.softSkyBlue,
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        backgroundColor: AppTheme.parchment,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: LivingSky.getPalette(LivingSky.getPhase()).foreground.mutedText,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to load app',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: LivingSky.getPalette(LivingSky.getPhase()).foreground.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (appState) {
        final dailyVerse = appState.dailyBread;
        final dailyBread = dailyVerse != null
            ? '"${dailyVerse.verse}"'
            : '"In Your presence is fullness of joy."';
        final verseReference = dailyVerse?.reference ?? 'Psalm 16:11';
        final isKidMode = appState.userPreferences.kidFriendlyOnly;
        final effectiveTheme = isKidMode ? AppTheme.kidsTheme : theme;

        return Theme(
          data: effectiveTheme,
          child: _MainMenuBody(
            theme: theme,
            effectiveTheme: effectiveTheme,
            kidMode: isKidMode,
            dailyBread: dailyBread,
            verseReference: verseReference,
          ),
        );
      },
    );
  }
}

/// Stateful body that owns the [PageController] for the Sanctuary & Study pages.
class _MainMenuBody extends ConsumerStatefulWidget {
  final ThemeData theme;
  final ThemeData effectiveTheme;
  final bool kidMode;
  final String dailyBread;
  final String verseReference;

  const _MainMenuBody({
    required this.theme,
    required this.effectiveTheme,
    required this.kidMode,
    required this.dailyBread,
    required this.verseReference,
  });

  @override
  ConsumerState<_MainMenuBody> createState() => _MainMenuBodyState();
}

class _MainMenuBodyState extends ConsumerState<_MainMenuBody> {
  late final PageController _pageController;
  int _currentPage = 0;
  final GlobalKey<_StudyPageState> _studyPageKey = GlobalKey<_StudyPageState>();
  final GlobalKey<PathsPageState> _pathsPageKey = GlobalKey<PathsPageState>();

  @override
  void initState() {
    super.initState();
    // SPEC Feature 48 — LOCKED: default landing page is always index 0
    // (PAL Sanctuary). Mood is index 1, PALs Paths is index 2.
    _pageController = PageController(initialPage: 0);
    _pageController.addListener(_onPageChanged);

    // Listen for player state changes — reset study page when story ends
    ref.listenManual(parablePlayerProvider, (prev, next) {
      final hadParable = prev?.currentParable != null;
      final hasParable = next.currentParable != null;
      if (hadParable && !hasParable) {
        // Player cleared — user returned from story
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _studyPageKey.currentState?._resetInputState();
        });
      }
    });
  }

  void _onPageChanged() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Living Sky fills entire background, continuous across pages.
          // The time-of-day background is unchanged in Kids mode — only the
          // PAL orb recolors (SPEC Feature 51.1).
          const LivingSkyBackground(),
          SafeArea(
            bottom: true,
            child: Column(
              children: [
                // Settings gear — top right, always visible
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    child: IconButton(
                      icon: Icon(
                        Icons.settings_outlined,
                        color: palette.foreground.secondaryIcon,
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ),
                ),
                // PageView fills the rest. SPEC Feature 48 — LOCKED
                // three-page layout: PAL Sanctuary (0, default) → Mood
                // (1) → PALs Paths (2). Inner horizontal scrollers on any
                // page must yield to the outer drag on overscroll.
                //
                // Phase 3.2 polish — dismiss keyboard on horizontal swipe.
                // When the user starts dragging the outer PageView with
                // a TextField focused (Mood or PALs Paths search), we
                // immediately drop focus so the keyboard doesn't follow
                // them to the destination page. The `depth == 0` filter
                // ensures nested vertical scrollables inside each page
                // (e.g. the PALs Paths home scroll, path detail lists,
                // mood mood-text scroll) don't trigger false dismissals.
                // Returning `false` leaves the notification unconsumed
                // so the PageView drag proceeds normally.
                Expanded(
                  child: NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      }
                      return false;
                    },
                    child: PageView(
                      controller: _pageController,
                      children: [
                        // Page 0: PAL Sanctuary (default landing)
                        _SanctuaryPage(
                          theme: widget.theme,
                          kidMode: widget.kidMode,
                          dailyBread: widget.dailyBread,
                          verseReference: widget.verseReference,
                        ),
                        // Page 1: Mood (internal class name retained as
                        // _StudyPage to minimize diff — user-facing copy
                        // is "Mood")
                        _StudyPage(key: _studyPageKey, theme: widget.theme),
                        // Page 2: PALs Paths (SPEC Feature 50)
                        PathsPage(key: _pathsPageKey, theme: widget.theme),
                      ],
                    ),
                  ),
                ),
                // Page dots indicator at bottom (3 dots)
                _PageDots(currentPage: _currentPage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page dots indicator
// ---------------------------------------------------------------------------

class _PageDots extends StatelessWidget {
  final int currentPage;
  const _PageDots({required this.currentPage});

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        // SPEC Feature 48: 3 dots for PAL / Mood / PALs Paths.
        children: List.generate(3, (index) {
          final isActive = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 8 : 6,
            height: isActive ? 8 : 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? palette.accentColor.withOpacity(0.85)
                  : palette.foreground.mutedText,
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1: The Sanctuary — PAL orb hero, Daily Bread, swipe hint
// ---------------------------------------------------------------------------

class _SanctuaryPage extends ConsumerWidget {
  final ThemeData theme;
  final bool kidMode;
  final String dailyBread;
  final String verseReference;

  const _SanctuaryPage({
    required this.theme,
    required this.kidMode,
    required this.dailyBread,
    required this.verseReference,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Column(
      children: [
        const Spacer(flex: 3),

        // PAL orb — THE hero. Recolors to the warm Kids palette in kid
        // mode; the rest of the Sanctuary keeps the time-of-day palette
        // (SPEC Feature 51.1).
        _PalButtonWithIntro(theme: theme, kidMode: kidMode),

        const SizedBox(height: 8),

        // Streak (subtle)
        Builder(builder: (context) {
          final streak = ref.watch(appStateProvider).valueOrNull?.userPreferences.currentStreak ?? 0;
          if (streak < 2) return const SizedBox.shrink();
          return Text(
            '$streak day streak',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.foreground.primaryText,
              fontWeight: FontWeight.w500,
            ),
          );
        }),

        const Spacer(flex: 2),

        // Daily Bread — atmospheric, with subtle scrim on medium backgrounds
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.foreground.scrimColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Text(
                    dailyBread.replaceAll('"', '').replaceAll('\u201C', '').replaceAll('\u201D', ''),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: palette.foreground.secondaryText,
                      height: 1.55,
                      shadows: palette.foreground.subtitleShadow,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '— $verseReference',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.foreground.secondaryText,
                      letterSpacing: 0.6,
                      shadows: palette.foreground.subtitleShadow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Swipe hint chevron
        _SwipeHintChevron(palette: palette),

        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe hint chevron — animated "swipe >" at bottom of Sanctuary page
// ---------------------------------------------------------------------------

class _SwipeHintChevron extends StatefulWidget {
  final SkyPalette palette;
  const _SwipeHintChevron({required this.palette});
  @override
  State<_SwipeHintChevron> createState() => _SwipeHintChevronState();
}

class _SwipeHintChevronState extends State<_SwipeHintChevron> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (_controller.value * 0.4),
          child: Transform.translate(
            offset: Offset(4 * _controller.value, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'swipe',
                  style: TextStyle(
                    color: widget.palette.foreground.mutedText,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                    shadows: widget.palette.foreground.subtitleShadow,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: widget.palette.foreground.mutedText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PAL framing overlay — user-controlled dismiss with animated continue hint
// ---------------------------------------------------------------------------

class _PalFramingOverlay extends StatefulWidget {
  final String displayText;
  final VoidCallback onContinue;

  const _PalFramingOverlay({
    required this.displayText,
    required this.onContinue,
  });

  @override
  State<_PalFramingOverlay> createState() => _PalFramingOverlayState();
}

class _PalFramingOverlayState extends State<_PalFramingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _hintVisible = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    // Show continue hint immediately with the text — feels intentional
    _hintVisible = true;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onContinue,
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
          widget.onContinue();
        }
      },
      child: Material(
        color: Colors.black.withValues(alpha: 0.88),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.displayText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 8,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _hintVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: 0.3 + (_pulseController.value * 0.4),
                      child: Transform.translate(
                        offset: Offset(0, -4 * _pulseController.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 28,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'continue',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2: The Study — mood buttons, Text PAL, Read Story, nav buttons
// ---------------------------------------------------------------------------

class _StudyPage extends ConsumerStatefulWidget {
  final ThemeData theme;
  const _StudyPage({super.key, required this.theme});

  @override
  ConsumerState<_StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<_StudyPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  // Animated placeholder
  late final AnimationController _hintFadeController;
  late final Animation<double> _hintFadeAnimation;
  Timer? _hintCycleTimer;
  int _currentHintIndex = 0;
  bool _userIsTyping = false;

  /// Feature 2.0 passive placeholder rotation: a shuffled copy of the full
  /// 60-line Delilah opening library. Reshuffled on each full-cycle wrap
  /// to guarantee full-pool coverage with no immediate repeats.
  List<String> _hints = buildShuffledOpeningLineTexts();

  @override
  void initState() {
    super.initState();
    _currentHintIndex = 0;

    _hintFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _hintFadeAnimation = CurvedAnimation(
      parent: _hintFadeController,
      curve: Curves.easeInOut,
    );
    _hintFadeController.value = 1.0; // start visible

    _textController.addListener(_onTextChanged);
    _scheduleNextHint();
  }

  void _onTextChanged() {
    final typing = _textController.text.trim().isNotEmpty;
    if (typing != _userIsTyping) {
      setState(() => _userIsTyping = typing);
      if (typing) {
        _hintCycleTimer?.cancel();
        _hintFadeController.stop();
      } else {
        _resetHintAnimation();
      }
    }
  }

  /// Single source of truth for resetting the text field and hint animation.
  void _resetInputState() {
    _textController.clear();
    _textFocusNode.unfocus();
    setState(() => _userIsTyping = false);
    _resetHintAnimation();
  }

  /// Fully reset hint animation to a clean starting state.
  void _resetHintAnimation() {
    _hintCycleTimer?.cancel();
    _hintFadeController.stop();
    _currentHintIndex = Random().nextInt(_hints.length);
    _hintFadeController.value = 1.0;
    _scheduleNextHint();
  }

  void _scheduleNextHint() {
    _hintCycleTimer?.cancel();
    _hintCycleTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _userIsTyping) return;
      // Fade out over 3s
      _hintFadeController.reverse().then((_) {
        if (!mounted || _userIsTyping) return;
        setState(() {
          final prevLine = _hints[_currentHintIndex];
          final nextIndex = _currentHintIndex + 1;
          if (nextIndex >= _hints.length) {
            // Full-cycle wrap: reshuffle the whole pool and guarantee the
            // new first line isn't a repeat of the line we just showed.
            _hints = buildShuffledOpeningLineTexts(avoidFirst: prevLine);
            _currentHintIndex = 0;
          } else {
            _currentHintIndex = nextIndex;
          }
        });
        // Pause briefly, then fade in over 3s
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || _userIsTyping) return;
          _hintFadeController.forward().then((_) {
            if (!mounted || _userIsTyping) return;
            _scheduleNextHint();
          });
        });
      });
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _hintCycleTimer?.cancel();
    _hintFadeController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Capture text, then reset field immediately
    _resetInputState();

    final appStateNotifier = ref.read(appStateProvider.notifier);
    final moodResult = appStateNotifier.moodService.detectMood(text);
    appStateNotifier.updateLastDetectedMood(moodResult.mood);

    // PAL framing response: show before navigating (text-input only).
    String? previewKey;
    final userPrefs = ref.read(appStateProvider).valueOrNull?.userPreferences;
    if (userPrefs != null) {
      final parableService = await ref.read(parableServiceProvider.future);
      previewKey = await parableService.previewBibleStoryKey(
        mood: moodResult.mood,
        userPrefs: userPrefs,
        userText: text,
      );
      if (previewKey != null && mounted) {
        await BiblicalFigureRegistry.ensureLoaded();
        await PalTransitionLines.ensureLoaded();
        await PalReflectionLines.ensureLoaded();
        final framingRef =
            BiblicalFigureRegistry.getFramingLineRef(previewKey);
        final transitionRef =
            PalTransitionLines.getLineRef(previewKey);
        // Feature 5.1 tone-biased reflection retired with the 12-line
        // time-bucketed opening library (SPEC §2.0). Opening lines no
        // longer carry a tone enum, so reflection always uses the
        // default mood ref.
        final reflectionRef = PalReflectionLines.getLineRef(moodResult.mood);
        if (framingRef != null && mounted) {
          // Text-input flow: no audio. PAL's voice responses are reserved
          // for the voice flow (`_processMoodFromVoice`); typed input
          // shows the framing overlay only. Voice + audio for typed input
          // was the original Feature 5.1a behavior but was removed because
          // it felt intrusive in a quiet text-entry context.

          // Compose overlay text: reflection → transition → framing.
          // Transition is the conversational bridge ("I have a story
          // for you") between mood acknowledgement and story intro;
          // it reads naturally between the two, not as an outro after
          // the framing line.
          // The overlay is text-only — no audio plays during it.
          final parts = <String>[
            if (reflectionRef != null) reflectionRef.text,
            if (transitionRef != null) transitionRef.text,
            framingRef.text,
          ];
          final displayText = parts.join('\n\n');
          const fadeDuration = Duration(milliseconds: 1500);

          // Show user-controlled overlay with swipe/tap to continue
          await showGeneralDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.transparent,
            transitionDuration: fadeDuration,
            transitionBuilder: (ctx, animation, _, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            pageBuilder: (ctx, _, __) {
              return _PalFramingOverlay(
                displayText: displayText,
                onContinue: () {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                },
              );
            },
          );
          if (!mounted) return;
        }
      }
    }
    // Text-input flow is silent until the player itself starts playback.
    // Voice flow (`_processMoodFromVoice`) plays the framing line.

    if (!mounted) return;
    await selectStoryAndOpenPlayer(
      ref: ref,
      context: context,
      mood: moodResult.mood,
      userText: text,
      bibleStoryKey: previewKey,
    );
    // Dismiss keyboard when returning from player
    if (mounted) _textFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    // Kids mode (SPEC Feature 51.3): feeling cards replace the adult mood
    // buttons (in _ReservedPanel) and the typed text field is hidden.
    final kidMode = ref.watch(appStateProvider).valueOrNull?.userPreferences
            .kidFriendlyOnly ??
        false;

    // Tap-outside-to-dismiss (Phase 3.2 polish). Opaque hit-test lets
    // taps on empty regions dismiss the keyboard while interactive
    // children (mood buttons, text field, nav tiles) still absorb
    // their own taps first.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
      children: [
        // Content area — centered vertically
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),

                      // Heading — routes through foreground palette for
                      // phase-aware contrast (Phase 3.2 global pass). Kids
                      // mode uses a gentler, heart-centered prompt (51.3).
                      Text(
                        kidMode
                            ? 'How is your heart today?'
                            : 'How are you feeling?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: palette.foreground.primaryText,
                          letterSpacing: 0.3,
                          height: 1.3,
                          shadows: palette.foreground.textShadow,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        kidMode
                            ? 'Tap how you feel and PAL will find a story'
                            : 'Tap a mood and PAL will find a story for you',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: palette.foreground.secondaryText,
                          letterSpacing: 0.2,
                          height: 1.4,
                          shadows: palette.foreground.subtitleShadow,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Mood buttons / now playing / finished
                      const _ReservedPanel(),

                      const SizedBox(height: 16),

                      // Nav — Favorites / Journal / History / My PALs
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(child: GlassTile(
                              icon: Icons.favorite_outline,
                              label: 'Favorites',
                              onTap: () => Navigator.of(context).pushNamed('/favorites'),
                            )),
                            const SizedBox(width: 6),
                            Expanded(child: GlassTile(
                              icon: Icons.book_outlined,
                              label: 'Journal',
                              onTap: () => Navigator.of(context).pushNamed('/journal'),
                            )),
                            const SizedBox(width: 6),
                            Expanded(child: GlassTile(
                              icon: Icons.history_outlined,
                              label: 'History',
                              onTap: () => Navigator.of(context).pushNamed('/history'),
                            )),
                            const SizedBox(width: 6),
                            Expanded(child: GlassTile(
                              icon: Icons.people_outline,
                              label: 'My PALs',
                              onTap: () => Navigator.of(context).pushNamed('/my_pals'),
                            )),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Kid Mode pill — entering is a tap; exiting requires
                      // the parent gate (hold 3s, SPEC Feature 51.2).
                      Center(child: _KidModeToggle(palette: palette)),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Text PAL input — pinned to bottom. Hidden in Kids mode, where the
        // feeling cards are the only input (no keyboard — SPEC Feature 51.3).
        if (!kidMode)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: AnimatedBuilder(
            animation: _hintFadeController,
            builder: (context, _) {
              return TextField(
                controller: _textController,
                focusNode: _textFocusNode,
                style: glassInputTextStyle(palette),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                // Shared glass input decoration (see lib/widgets/
                // glass_input_decoration.dart). The PALs Paths search
                // field uses the same helper so both surfaces stay
                // visually identical (SPEC Feature 48 page 2).
                decoration: glassInputDecoration(
                  palette: palette,
                  hintText: _hints[_currentHintIndex],
                  hintAlpha: _userIsTyping ? 0.0 : _hintFadeAnimation.value,
                  suffixIcon: _userIsTyping
                      ? Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.warmHighlight,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                              onPressed: _submitText,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        )
                      : null,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitText(),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kid Mode toggle + parent gate (SPEC Feature 51.2)
// ---------------------------------------------------------------------------

/// The "Kid Mode" pill on the Mood page.
///
/// Entering Kids mode is a single tap. **Exiting** is guarded by the parent
/// gate (SPEC Feature 51.2): the grown-up must press and hold the pill for
/// [_kHoldToExit] before `kidFriendlyOnly` flips back to false. A tap while
/// ON only nudges a "Hold to exit" hint — it never exits. This preserves the
/// Kid Safety Contract Invariant (a child cannot wander out of Kids mode).
class _KidModeToggle extends ConsumerStatefulWidget {
  final SkyPalette palette;
  const _KidModeToggle({required this.palette});

  @override
  ConsumerState<_KidModeToggle> createState() => _KidModeToggleState();
}

class _KidModeToggleState extends ConsumerState<_KidModeToggle>
    with SingleTickerProviderStateMixin {
  /// How long a grown-up must hold to exit Kids mode.
  static const Duration _kHoldToExit = Duration(seconds: 3);

  late final AnimationController _holdController;
  bool _holding = false;

  /// Whether the current press began while Kids mode was ON. The tap-up
  /// action is decided from THIS, not the live state — so a press that began
  /// as a hold-to-exit can never trigger "enter" on release, even if the gate
  /// completed mid-hold and the pill rebuilt into the OFF (enter) state under
  /// the still-down finger. (Fixes the "release re-enables Kids mode" bug.)
  bool _pressStartedOn = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: _kHoldToExit)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _completeExit();
        }
      });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _enterKidMode() {
    HapticFeedback.lightImpact();
    ref.read(appStateProvider.notifier).updateKidFriendlyOnly(true);
  }

  void _onTapDown(bool isOn) {
    _pressStartedOn = isOn;
    if (isOn) {
      // Begin the hold-to-exit gate.
      HapticFeedback.selectionClick();
      setState(() => _holding = true);
      _holdController.forward(from: 0.0);
    }
  }

  void _onTapUp() {
    if (_pressStartedOn) {
      // Released during a hold — cancel if the gate hasn't already fired.
      // Never enters, even if the gate just completed under the finger.
      _cancelHold();
    } else {
      // A tap that began while OFF → enter Kids mode (no gate on entry).
      _enterKidMode();
    }
  }

  void _onTapCancel() {
    if (_pressStartedOn) _cancelHold();
  }

  void _cancelHold() {
    if (!_holding) return;
    setState(() => _holding = false);
    _holdController.stop();
    _holdController.reset();
  }

  Future<void> _completeExit() async {
    HapticFeedback.mediumImpact();
    setState(() => _holding = false);
    _holdController.reset();

    // Parent lock (SPEC Feature 51.6): when set, the completed hold must be
    // confirmed by Face ID / Touch ID or the 4-digit PIN before exiting.
    // Failing/cancelling auth leaves Kids mode ON.
    final prefs = ref.read(appStateProvider).valueOrNull?.userPreferences;
    if (prefs?.hasParentLock ?? false) {
      final authed = await authenticateParent(context, ref);
      if (!authed) return;
    }

    await ref.read(appStateProvider.notifier).updateKidFriendlyOnly(false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final appState = ref.watch(appStateProvider).valueOrNull;
    final isOn = appState?.userPreferences.kidFriendlyOnly ?? false;

    // One gesture detector for both states. Entering is a tap; exiting is a
    // 3s hold. The tap-up branch is chosen from the state at tap-DOWN
    // (_pressStartedOn), so a release after a completed exit does nothing.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onTapDown(isOn),
      onTapUp: (_) => _onTapUp(),
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) {
          return _pill(
            palette: palette,
            isOn: isOn,
            fill: isOn ? _holdController.value : 0.0,
            label: isOn ? 'ON' : 'OFF',
            hint: isOn
                ? (_holding ? 'Keep holding to exit…' : 'Hold to exit')
                : null,
          );
        },
      ),
    );
  }

  Widget _pill({
    required SkyPalette palette,
    required bool isOn,
    required double fill,
    required String label,
    required String? hint,
  }) {
    final borderRadius = BorderRadius.circular(20);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hint sits ABOVE the pill so the grown-up's finger doesn't cover it
        // while holding to exit (SPEC Feature 51.2).
        if (hint != null) ...[
          Text(
            hint,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.foreground.tertiaryText,
              letterSpacing: 0.2,
              shadows: palette.foreground.subtitleShadow,
            ),
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isOn
                      ? palette.warmHighlight.withOpacity(0.08)
                      : palette.cardColor,
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isOn
                        ? palette.warmHighlight.withOpacity(0.8)
                        : palette.cardBorder,
                    width: isOn ? 2 : 1,
                  ),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isOn
                          ? palette.foreground.primaryText
                          : palette.foreground.secondaryText,
                      shadows: palette.foreground.subtitleShadow,
                    ),
                    children: [
                      const TextSpan(text: 'Kid Mode: '),
                      TextSpan(
                        text: label,
                        style: TextStyle(
                          color: isOn
                              ? palette.warmHighlight
                              : palette.foreground.tertiaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Hold-to-exit progress fill — grows left→right as the
              // grown-up holds. Purely visual feedback for the gate.
              if (fill > 0.0)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fill.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.warmHighlight.withOpacity(0.25),
                        borderRadius: borderRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Voice mood flow states for the conversational PAL interaction on main menu.
enum _VoiceFlowState {
  /// Normal main menu, no conversation active.
  inactive,

  /// PAL opening line is displaying (Feature 2.0).
  playingOpeningLine,

  /// PAL greeting audio is playing.
  playingGreeting,

  /// STT is listening for user's mood response.
  listening,

  /// Mood detected, PAL micro-response audio playing.
  responding,

  /// Waiting for user to choose story length.
  choosingLength,

  /// Story being selected and loaded.
  selectingStory,
}

/// PAL button with first-launch intro overlay and voice-first conversational flow.
///
/// Flow: Tap PAL → greeting plays → mic auto-activates → user speaks →
/// mood detected → PAL micro-response → auto-select story → navigate to player.
class _PalButtonWithIntro extends ConsumerStatefulWidget {
  final ThemeData theme;

  /// When true the orb recolors to the warm Kids palette (SPEC Feature 51.1).
  final bool kidMode;

  const _PalButtonWithIntro({required this.theme, this.kidMode = false});

  @override
  ConsumerState<_PalButtonWithIntro> createState() => _PalButtonWithIntroState();
}

class _PalButtonWithIntroState extends ConsumerState<_PalButtonWithIntro>
    with TickerProviderStateMixin {
  // Intro state
  bool _showIntro = false;
  bool _introChecked = false;
  Timer? _wordTimer;

  // Line-by-line fade-in animation for intro
  List<String> _introLines = [];
  List<AnimationController> _lineControllers = [];
  List<Animation<double>> _lineAnimations = [];
  int _revealedLines = 0;

  // Pulse animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  int _pulseCount = 0;
  late final AnimationController _glowController;

  // Voice flow state
  _VoiceFlowState _voiceFlow = _VoiceFlowState.inactive;
  String? _greetingText;
  String? _microResponseText;
  String _partialTranscript = '';
  String? _finalTranscript;
  Timer? _autoStoryTimer;

  // Hard reentrancy guard for the PAL voice conversation. Set true
  // at the entry of `_startConversation` and released ONLY in
  // `_cancelConversation` (which runs on every cancel/error path
  // AND immediately before story navigation in the success path).
  // The earlier per-flow flag was reset in `_startConversation`'s
  // finally — but `_runConversation` returns as soon as STT
  // *setup* completes, while mood detection and story navigation
  // continue asynchronously via STT callbacks. That left a ~2s
  // window where a second `_onPalTap` could start a parallel
  // conversation, racing the shared audio player and producing
  // PlayerException -11849 on the second opening. This flag stays
  // up for the entire conversation lifetime, so the second tap is
  // always blocked.
  bool _voiceConversationActive = false;
  // Set true when the opening playback fails with iOS -11849
  // ("Operation Stopped"). The current AVPlayer instance is wedged
  // and any subsequent setAsset on it will keep returning -11849.
  // `_cancelConversation` consults this flag and runs an audio-
  // recovery cooldown before releasing the conversation guard so
  // the next tap starts against a fresh player + reactivated
  // session, not the wedged one.
  bool _needsAudioCooldown = false;

  // Services for voice flow
  final SttService _sttService = SttService();
  final Random _random = Random();

  // Micro-response ring buffer (session-only, per mood)
  final Map<String, List<String>> _recentMicroResponseIds = {};

  // Mic pulse animation
  late final AnimationController _micPulseController;

  // Breathing animation — continuous subtle scale + glow oscillation
  late final AnimationController _breathController;
  late final Animation<double> _breathScale;
  late final Animation<double> _breathGlow;

  static const _defaultIntroLines = [
    'Meet PAL.',
    'Your guide to mood-based Bible stories.',
    'Tap PAL to start.',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.addStatusListener(_onPulseStatus);

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _micPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Breathing animation — 4s cycle, subtle scale + glow oscillation
    _breathController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _breathScale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _breathGlow = Tween<double>(begin: 0.25, end: 0.45).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    _checkIntroState();
    _initStt();
  }

  @override
  void dispose() {
    _wordTimer?.cancel();
    _autoStoryTimer?.cancel();
    for (final c in _lineControllers) {
      c.dispose();
    }
    _breathController.dispose();
    _pulseController.removeStatusListener(_onPulseStatus);
    _pulseController.dispose();
    _glowController.dispose();
    _micPulseController.dispose();
    _sttService.dispose();
    super.dispose();
  }

  Future<void> _initStt() async {
    // A launch prewarm was tried and removed (2026-07-09 STT
    // investigation): the ~2.3s "first yes" cost is an AVAudioSession
    // mic-route power-up, and the plugin's stop() tears that route back
    // down, so a prewarm at launch didn't persist to the journey
    // capture. The real fix is ensureAudioSessionActive() (now
    // .playAndRecord) called before the offer plays — see
    // _tryFireJourneyCascade. Just initialize here.
    await _sttService.initialize();
  }

  // ---------------------------------------------------------------------------
  // Intro logic (unchanged)
  // ---------------------------------------------------------------------------

  Future<void> _checkIntroState() async {
    final sp = await SharedPreferences.getInstance();
    final alreadyShown = sp.getBool(kPalIntroShownKey) ?? false;
    if (!mounted) return;

    if (!alreadyShown) {
      // Build intro lines with personalised greeting
      final appState = ref.read(appStateProvider).valueOrNull;
      final userName = appState?.userPreferences.userName ?? '';
      _introLines = [
        if (userName.isNotEmpty) 'HI, ${userName.toUpperCase()}',
        ..._defaultIntroLines,
      ];

      _lineControllers = List.generate(
        _introLines.length,
        (_) => AnimationController(
          duration: const Duration(milliseconds: 920),
          vsync: this,
        ),
      );
      _lineAnimations = _lineControllers
          .map((c) => CurvedAnimation(parent: c, curve: Curves.easeIn))
          .toList();
    }

    setState(() {
      _introChecked = true;
      _showIntro = !alreadyShown;
    });

    if (_showIntro) {
      if (!mounted) return;
      _startLineFadeIn();
    }
  }

  /// Reveal lines one at a time with a staggered fade-in
  void _startLineFadeIn() {
    // Reveal the first line immediately
    _lineControllers[0].forward();
    _revealedLines = 1;
    setState(() {});

    _wordTimer = Timer.periodic(
      const Duration(milliseconds: 1610), // 920ms fade + 690ms pause
      (timer) {
        if (!mounted || !_showIntro) {
          timer.cancel();
          return;
        }
        if (_revealedLines >= _introLines.length) {
          timer.cancel();
          _startPulse();
          return;
        }
        _lineControllers[_revealedLines].forward();
        _revealedLines++;
        setState(() {});
      },
    );
  }

  void _skipIntroToEnd() {
    _wordTimer?.cancel();
    for (final c in _lineControllers) {
      c.value = 1.0;
    }
    _revealedLines = _introLines.length;
    setState(() {});
    _startPulse();
  }

  void _startPulse() {
    _pulseCount = 0;
    _pulseController.forward();
  }

  void _onPulseStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _pulseController.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _pulseCount++;
      if (_pulseCount < 2) {
        _pulseController.forward();
      } else {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _showIntro) {
            _markIntroShown();
          }
        });
      }
    }
  }

  Future<void> _markIntroShown() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kPalIntroShownKey, true);
    if (!mounted) return;
    setState(() {
      _showIntro = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Voice-first conversational flow
  // ---------------------------------------------------------------------------

  void _onPalTap() {
    _glowController.forward(from: 0.0);
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }

    _wordTimer?.cancel();
    _pulseController.stop();

    if (_showIntro) {
      SharedPreferences.getInstance().then((sp) {
        sp.setBool(kPalIntroShownKey, true);
      });
      setState(() {
        _showIntro = false;
      });
    }

    // Start the voice-first conversational flow.
    _startConversation();
  }

  /// Cancel the voice flow and return to inactive state.
  void _cancelConversation() {
    _autoStoryTimer?.cancel();
    _sttService.stopListening();
    _micPulseController.stop();
    // Unblock an in-flight journey capture immediately (don't wait out
    // the 12s safety timer). Completing with null, combined with the
    // isCancelled checkpoint in fireJourneyOffer, makes the cascade
    // return `cancelled` — no decline clip, no mic restart.
    final capture = _journeyCaptureCompleter;
    if (capture != null && !capture.isCompleted) {
      _journeyCaptureCompleter = null;
      capture.complete(null);
    }
    final palAudio = ref.read(palAudioServiceProvider);
    palAudio.stop();

    if (_needsAudioCooldown) {
      // Hold the conversation reentrancy guard up while the audio
      // stack recovers (dispose+recreate player, deactivate→
      // reactivate session, ~950ms total). A new tap during this
      // window would otherwise hit the wedged AVPlayer and reproduce
      // -11849 again. Release the guard ONLY when recovery
      // completes.
      _needsAudioCooldown = false;
      logEvent('pal_audio_cooldown_started', {});
      // Fire-and-forget; outcome is logged by the service.
      () async {
        try {
          await palAudio.recoverFromOperationStopped();
        } finally {
          _voiceConversationActive = false;
          logEvent('pal_audio_cooldown_finished', {});
        }
      }();
    } else {
      // Release the conversation reentrancy guard. This is the
      // authoritative termination signal for the entire PAL flow —
      // every cancel/error path calls this, and the success path
      // calls it immediately before navigating to the story player.
      _voiceConversationActive = false;
    }

    // Resume breathing animation
    if (!_breathController.isAnimating) {
      _breathController.repeat(reverse: true);
    }
    setState(() {
      _voiceFlow = _VoiceFlowState.inactive;
      _greetingText = null;
      _microResponseText = null;
      _partialTranscript = '';
      _finalTranscript = null;
    });
  }

  /// Start the full voice conversation: greeting → listen → respond → story.
  ///
  /// Hard reentrancy guard at the actual call site. The InkWell's
  /// `onTap` rebuild gate is the first line of defense, but breadcrumb
  /// data showed a second `_startConversation` landing while a prior
  /// flow was already in playingGreeting → listening — the two flows
  /// then raced the shared audio player and the second opening's
  /// `setAsset` returned PlayerException -11849 ("Operation Stopped").
  /// This guard closes that race by checking both
  /// `_voiceConversationActive` (a flag held across the entire flow
  /// lifetime — released only by `_cancelConversation`) and the
  /// public `_voiceFlow` state. Anything other than `inactive` blocks.
  Future<void> _startConversation() async {
    // Single-entry contract: `_startConversation` is invoked only
    // from `_onPalTap`. Debug-only assert catches any future
    // accidental re-entry from a new caller; release builds rely
    // on the runtime guard below.
    assert(!_voiceConversationActive,
        'Conversation restarted unexpectedly');

    if (_voiceConversationActive ||
        _voiceFlow != _VoiceFlowState.inactive) {
      logEvent('pal_opening_reentry_blocked', {
        'voice_flow': _voiceFlow.name,
        'conversation_active': _voiceConversationActive,
      });
      return;
    }
    _voiceConversationActive = true;
    try {
      await _runConversation();
    } catch (e) {
      // Unexpected exception in the conversation flow — release the
      // guard so the user isn't stuck with all future PAL taps
      // silently blocked. _cancelConversation isn't guaranteed to
      // run on a thrown exception.
      _voiceConversationActive = false;
      rethrow;
    }
    // NOTE: deliberate — do NOT release the guard here. _runConversation
    // returns as soon as STT setup completes, but mood detection and
    // story navigation continue asynchronously via STT callbacks.
    // _cancelConversation (called in every cancel/error path AND
    // immediately before story navigation in the success path) is the
    // authoritative termination signal for the conversation.
  }

  Future<void> _runConversation() async {
    // Pause breathing during voice flow
    _breathController.stop();

    // Transition voice flow to playingOpeningLine IMMEDIATELY so the
    // "PAL is speaking" UI affordance shows the moment the user taps.
    // The cascade below is async (permissions check, provider reads)
    // and would otherwise leave the user staring at a stale UI for a
    // few hundred ms.
    if (mounted) {
      setState(() {
        _voiceFlow = _VoiceFlowState.playingOpeningLine;
      });
    }

    // Journey Doctrine Slice 2 — try the journey continuation cascade
    // BEFORE the cold-open greeting. If the cascade fires (eligible
    // recent journey-source session + audio + consent), it REPLACES
    // the cold-open entirely: PAL plays the offer instead of the
    // greeting, captures the user's response, and dispatches:
    //
    //   acceptedAndContinued: opens the next-in-journey story
    //     directly; cold-open + mood STT + mood-flow are all skipped.
    //
    //   declinedMoodRedirect: routes the user's mood-utterance to
    //     `_processMoodFromVoice` exactly as if they'd said it via
    //     the normal cold-open + STT path. Slice 2d may still fire
    //     on the resulting story (different memory thread).
    //
    //   declinedExplicit / declinedAmbiguous: the runtime already
    //     played the decline clip; fall through to the normal
    //     mood-flow's STT capture (existing _startListeningForMood
    //     path below).
    //
    //   engineSilent / consentBlocked / missingClip / playbackFailed
    //   / exception: fall through to the normal cold-open. No
    //   user-visible journey behavior; silence-floor honest.
    //
    // STT response capture reuses the existing `_sttService`
    // instance (not a fresh one) — fixes the iOS audio-session
    // conflict that broke the first integration attempt.
    final journeyOutcome = await _tryFireJourneyCascade();
    if (!mounted) return;

    switch (journeyOutcome.outcome) {
      case JourneyOfferOutcome.acceptedAndContinued:
        if (journeyOutcome.offer != null) {
          await _openJourneyNextStory(journeyOutcome.offer!);
        }
        return;
      case JourneyOfferOutcome.declinedMoodRedirect:
        // User's response IS the mood signal — route to mood-flow
        // exactly as the cold-open STT path would.
        if (journeyOutcome.moodPhrase != null &&
            journeyOutcome.moodPhrase!.trim().isNotEmpty) {
          await _processMoodFromVoice(journeyOutcome.moodPhrase!);
          return;
        }
        // Empty phrase shouldn't reach here but guard anyway.
        break;
      case JourneyOfferOutcome.declinedExplicit:
      case JourneyOfferOutcome.declinedAmbiguous:
        // Decline clip already played by runtime. Continue to mood
        // STT (the user still needs to give PAL something to work
        // with — the offer was declined, the next step is "what's
        // on your heart").
        //
        // FREEZE FIX (2026-07-05): the journey cascade leaves
        // `_voiceFlow == listening` (set by `_captureJourneyResponse`).
        // `_startListeningForMood` normally gates on the greeting state
        // and would SILENTLY NO-OP from here — the exact wedge
        // documented on `_journeyAcceptFallback` below: the decline clip
        // plays, then the orb freezes on a dead `listening` state, mic
        // never reopens. Pass `fromDecline: true` to skip that gate. We
        // deliberately do NOT fake the greeting state (no greeting is
        // playing here, and setting it would also mis-anchor the Feature
        // 2.0 opening-audio spec, which scans for the first greeting-
        // state transition after `_startConversation`).
        await _startListeningForMood(fromDecline: true);
        return;
      case JourneyOfferOutcome.cancelled:
        // User tapped Cancel. _cancelConversation already reset the orb,
        // mic, and voice flow. Do NOT restart listening or fall through
        // to the cold-open greeting — a cancel is a full stop.
        return;
      case JourneyOfferOutcome.engineSilent:
      case JourneyOfferOutcome.consentBlocked:
      case JourneyOfferOutcome.missingClip:
      case JourneyOfferOutcome.playbackFailed:
      case JourneyOfferOutcome.exception:
        // No journey today — fall through to the normal cold-open
        // greeting + mood STT path.
        break;
    }

    // Feature 2.0 — 12-line time-bucketed mood-blind opening greeting
    // (SPEC §2.0). Selection driven solely by current local hour with
    // persistent recency rotation; tone signal retired with the 60-line
    // library. Emotional warmth is handled later by Feature 2.1
    // micro-responses, AFTER the user has spoken.
    await PalOpeningRecency.ensureInitialized();
    final hour = DateTime.now().hour;
    final opening = pickOpeningLineForHour(hour);
    setState(() {
      _voiceFlow = _VoiceFlowState.playingOpeningLine;
      _greetingText = opening.text;
    });

    // Feature 2.0a — Play opening line audio (pre-generated).
    // Falls back to minimum display duration if audio is unavailable.
    final appStateForOpening = ref.read(appStateProvider).valueOrNull;
    final openingAudioEnabled =
        appStateForOpening?.userPreferences.palVoiceEnabled == true &&
        appStateForOpening?.userPreferences.palGreetingsEnabled != false;
    if (openingAudioEnabled) {
      final voiceKey =
          appStateForOpening?.userPreferences.palVoiceKey ?? PalVoiceRegistry.defaultVoiceKey;
      final palAudio = ref.read(palAudioServiceProvider);
      final expectedPath = PalAudioService.assetPath(voiceKey, opening.id);

      // Optional name-prefix splice. Only attaches to `bare`-type
      // opening lines so we don't stack greetings (e.g. avoid "Hi
      // there, Adam! Hi… how's your morning been?"). Probability is
      // 30% — natural and occasional, not every time. Cache miss
      // kicks off lazy generation for the next launch.
      File? nameClipFile;
      String? nameClipText;
      if (opening.type == OpeningLineType.bare) {
        final userName = appStateForOpening?.userPreferences.userName ?? '';
        if (userName.isNotEmpty && _random.nextDouble() < 0.30) {
          final nameAudio = ref.read(nameAudioServiceProvider);
          final nameClip =
              await nameAudio.getRandomNameClip(userName, voiceKey);
          if (nameClip != null) {
            nameClipFile = nameClip.file;
            nameClipText = nameClip.text;
          } else {
            // Cache miss — fire-and-forget so prefix is ready next time.
            nameAudio.generateNamePhrases(
                name: userName, voiceKey: voiceKey);
          }
        }
      }

      try {
        // Strict iOS audio session activation gate. Configures +
        // setActive(true) + 300ms settle delay before the first
        // playback so AVFoundation has a fully active session by
        // the time setAsset/play runs. Idempotent — subsequent
        // calls in the same app session are fast no-ops.
        await palAudio.ensureAudioSessionActive();
        var resolution = await palAudio.playLineResolved(
            opening.id, voiceKey,
            nameClipFile: nameClipFile);
        // Retry-once narrowly here in the opening flow for non-fatal
        // failures (e.g. transient asset-load issues). For iOS
        // -11849 ("Operation Stopped") the AVPlayer is wedged and
        // every subsequent setAsset on it returns the same code, so
        // retrying just delays the user's text-only fallback. Skip
        // the retry on `operation_stopped` and fall through to the
        // 1800ms text floor — `_cancelConversation` will run the
        // recovery cooldown before the next tap is allowed.
        if (!resolution.played && resolution.source != 'operation_stopped') {
          await Future.delayed(const Duration(milliseconds: 500));
          resolution = await palAudio.playLineResolved(opening.id, voiceKey);
          logEvent('pal_audio_opening_retry', {
            'line_id': opening.id,
            'voice_key': voiceKey,
            'retry_played': resolution.played,
          });
        }
        logEvent('pal_opening_audio_resolution', {
          'voice_key': voiceKey,
          'opening_line_id': opening.id,
          'expected_path': expectedPath,
          'resolved_source': resolution.source,
          'success': resolution.played,
          if (resolution.errorType != null) 'error_type': resolution.errorType,
          if (resolution.errorCode != null) 'error_code': resolution.errorCode,
          if (resolution.errorMessage != null)
            'error_message': resolution.errorMessage,
          if (resolution.errorIndex != null) 'error_index': resolution.errorIndex,
          if (resolution.errorString != null)
            'error_string': resolution.errorString,
        });
        // iOS -11849 leaves the AVPlayer wedged. Flag here so
        // `_cancelConversation` runs the recovery cooldown before
        // releasing the conversation guard for the next tap.
        if (resolution.source == 'operation_stopped') {
          _needsAudioCooldown = true;
        }
        if (resolution.played) {
          // Reflect the name prefix in the displayed greeting so the
          // text matches what's being voiced (e.g. "Hi there, Adam!
          // How's your day going?").
          if (nameClipFile != null && nameClipText != null && mounted) {
            setState(() => _greetingText = '$nameClipText ${opening.text}');
          }
          await palAudio.awaitPlaybackComplete();
          logEvent('pal_audio_played', {
            'line_id': opening.id,
            'type': 'opening',
            'voice_key': voiceKey,
            'name_prefix_attached': nameClipFile != null,
            'opening_line_type': opening.type.name,
          });
        } else {
          // SPEC Feature 2.0 floor: when audio cannot resolve, hold
          // the text on screen long enough to be readable before the
          // check-in prompt begins. Never silently skip.
          await Future.delayed(const Duration(milliseconds: 1800));
        }
      } catch (e) {
        debugPrint('[MainMenu] Opening line audio failed: $e');
        // Extract rich PlayerException fields onto the canonical
        // resolution event so we can distinguish iOS audio session
        // refusals (-11849, -11800, etc.) from true asset failures.
        final isPlayerException = e is PlayerException;
        final isInterrupted = e is PlayerInterruptedException;
        final richErr = <String, Object?>{
          'error_type': e.runtimeType.toString(),
          'error_string': e.toString(),
          if (isPlayerException) 'error_code': e.code,
          if (isPlayerException) 'error_message': e.message,
          if (isPlayerException) 'error_index': e.details['index'],
          if (isInterrupted) 'error_message': e.message,
        };
        logEvent('pal_audio_error', {
          'line_id': opening.id,
          'type': 'opening',
          'error': e.runtimeType.toString(),
        });
        logEvent('pal_opening_audio_resolution', {
          'voice_key': voiceKey,
          'opening_line_id': opening.id,
          'expected_path': expectedPath,
          'resolved_source': 'missing',
          'success': false,
          ...richErr,
        });
        if (isPlayerException && e.code == -11849) {
          _needsAudioCooldown = true;
        }
        await Future.delayed(const Duration(milliseconds: 1800));
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 1800));
    }
    if (!mounted || _voiceFlow != _VoiceFlowState.playingOpeningLine) return;

    // Feature 2.0 §3: opening line IS the only voiced beat at cold-open.
    // The old Phase 2 (96-prompt `_promptService.getPrompt()` text/audio)
    // is retired — its prompts include BURDEN/HEART probes that violate
    // the mood-blind cold-open invariant. The 96-prompt service stays
    // available for future follow-up flows after the user has spoken.
    //
    // Transition through `playingGreeting` momentarily so the existing
    // `_startListeningForMood` gate (which checks for that state) still
    // activates the mic. No audio plays in this transition; the opening
    // line audio has already finished above via `awaitPlaybackComplete`.
    setState(() => _voiceFlow = _VoiceFlowState.playingGreeting);

    if (!mounted || _voiceFlow != _VoiceFlowState.playingGreeting) return;

    // Greeting done — auto-activate mic.
    await _startListeningForMood();
  }

  /// Auto-activate STT after PAL greeting finishes.
  ///
  /// [fromDecline] skips the greeting-state gate for the journey decline
  /// path, which reopens the mic from the `listening` state the cascade
  /// leaves behind (see the declinedExplicit/declinedAmbiguous handler).
  Future<void> _startListeningForMood({bool fromDecline = false}) async {
    // Check permissions first
    final permResult = await _sttService.checkPermissions();
    if (!mounted) return;
    if (!fromDecline && _voiceFlow != _VoiceFlowState.playingGreeting) return;

    switch (permResult) {
      case SttPermissionResult.granted:
        break; // Continue to listening
      case SttPermissionResult.denied:
      case SttPermissionResult.permanentlyDenied:
        // Fall back to text input screen
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone not available. Opening text input.'),
              duration: const Duration(seconds: 2),
              action: permResult == SttPermissionResult.permanentlyDenied
                  ? SnackBarAction(
                      label: 'Settings',
                      onPressed: () => openAppSettings(),
                    )
                  : null,
            ),
          );
          _cancelConversation();
          Navigator.of(context).pushNamed('/pals_parables');
        }
        return;
    }

    setState(() {
      _voiceFlow = _VoiceFlowState.listening;
      _partialTranscript = '';
    });
    _micPulseController.repeat(reverse: true);

    final completer = Completer<void>();

    await _sttService.startListening(
      onResult: (result) {
        if (!mounted || _voiceFlow != _VoiceFlowState.listening) return;
        if (result.isFinal) {
          _micPulseController.stop();
          final transcript = result.text;
          if (transcript.isEmpty) {
            // Nothing heard — retry or fall back
            setState(() => _partialTranscript = '');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try tapping PAL again."),
                duration: Duration(seconds: 3),
              ),
            );
            _cancelConversation();
          } else {
            _processMoodFromVoice(transcript);
          }
          if (!completer.isCompleted) completer.complete();
        } else {
          setState(() => _partialTranscript = result.text);
        }
      },
      onError: (error) {
        if (!mounted) return;
        _micPulseController.stop();
        _cancelConversation();
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Timeout fallback
    unawaited(
      Future.delayed(const Duration(seconds: SttService.defaultListenSeconds + 1))
          .then((_) {
        if (!completer.isCompleted) {
          if (_partialTranscript.isNotEmpty && mounted) {
            _micPulseController.stop();
            _processMoodFromVoice(_partialTranscript);
          } else if (mounted && _voiceFlow == _VoiceFlowState.listening) {
            _micPulseController.stop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try tapping PAL again."),
                duration: Duration(seconds: 3),
              ),
            );
            _cancelConversation();
          }
          completer.complete();
        }
      }),
    );
  }

  /// Process mood from voice transcript, play micro-response, then start story.
  Future<void> _processMoodFromVoice(String transcript) async {
    final appNotifier = ref.read(appStateProvider.notifier);
    final moodService = appNotifier.moodService;
    final result = moodService.detectMood(transcript);

    // Persist mood for thematic Daily Bread alignment
    appNotifier.updateLastDetectedMood(result.mood);

    setState(() {
      _voiceFlow = _VoiceFlowState.responding;
      _finalTranscript = transcript;
      _partialTranscript = '';
    });

    // Micro-response: text always shown; audio gated behind useLegacyPal.
    final appState = ref.read(appStateProvider).valueOrNull;
    // Kids-mode warm fallback (SPEC Feature 51.3): an unmatched spoken
    // sentence lands on a joyful story instead of the weary no-match default.
    // Scoped to story selection; the micro-response audio keeps result.mood.
    final kidMode = appState?.userPreferences.kidFriendlyOnly ?? false;
    final effectiveMood = kidMode
        ? kidFallbackMood(
            detectedMood: result.mood,
            confidenceScore: result.confidenceScore,
          )
        : result.mood;
    final useLegacy = appState?.userPreferences.useLegacyPal ?? false;
    final voiceKey = appState?.userPreferences.palVoiceKey ?? PalVoiceRegistry.defaultVoiceKey;

    String responseText;
    if (!useLegacy ||
        appState?.userPreferences.palGreetingsEnabled == false) {
      // New path: spoken reflection line as PAL's response to the user.
      responseText = moodService.getMicroResponseText(result.mood);

      // Feature 5.1a — Play a single reflection line as spoken response.
      final palResponseEnabled =
          appState?.userPreferences.palVoiceEnabled == true &&
          appState?.userPreferences.palGreetingsEnabled != false;
      if (palResponseEnabled) {
        await PalReflectionLines.ensureLoaded();
        // Feature 5.1 tone-biased reflection retired with 12-line
        // time-bucketed opening library (SPEC §2.0). Reflection uses
        // default mood ref.
        final reflectionRef = PalReflectionLines.getLineRef(result.mood);
        if (reflectionRef != null && mounted) {
          final palAudio = ref.read(palAudioServiceProvider);
          try {
            final played =
                await palAudio.playLine(reflectionRef.id, voiceKey);
            if (played) {
              await palAudio.awaitPlaybackComplete();
              logEvent('pal_audio_played', {
                'line_id': reflectionRef.id,
                'type': 'reflection_response',
                'voice_key': voiceKey,
              });
            }
          } catch (e) {
            debugPrint('[MainMenu] Voice-path reflection audio failed: $e');
          }
          if (!mounted || _voiceFlow != _VoiceFlowState.responding) return;
          // Short pause before navigating
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } else {
      // Legacy path: play old RESP_* audio
      final responseId = _pickMicroResponseId(result.mood);
      final userName = appState?.userPreferences.userName ?? '';
      final palAudio = ref.read(palAudioServiceProvider);
      final nameAudio = ref.read(nameAudioServiceProvider);
      final nameClip = userName.isNotEmpty
          ? await nameAudio.getRandomNameClip(userName, voiceKey)
          : null;

      try {
        responseText = await palAudio.playMicroResponse(
          responseId,
          result.mood,
          voiceKey,
          nameClipFile: nameClip?.file,
          nameClipText: nameClip?.text,
        );

        logEvent('pal_line_played', {
          'line_id': responseId,
          'type': 'micro_response',
          'mood': result.mood,
          'voice_key': voiceKey,
          'name_prefix_used': nameClip != null && responseText.contains(nameClip.text),
        });

        // Wait for micro-response audio to finish playing
        await palAudio.awaitPlaybackComplete();
      } catch (e) {
        debugPrint('[MainMenu] PAL micro-response audio failed: $e');
        responseText = moodService.getMicroResponseText(result.mood);
      }
    }

    if (!mounted || _voiceFlow != _VoiceFlowState.responding) return;

    // Play the story-specific framing line (BiblicalFigureRegistry) before
    // the length picker.
    String? previewKey;
    final userPrefs = appState?.userPreferences;
    final palResponseEnabled = userPrefs != null &&
        userPrefs.palVoiceEnabled &&
        userPrefs.palGreetingsEnabled != false;

    if (userPrefs != null) {
      final parableService = await ref.read(parableServiceProvider.future);
      previewKey = await parableService.previewBibleStoryKey(
        mood: effectiveMood,
        userPrefs: userPrefs,
        userText: transcript,
      );

      if (previewKey != null && mounted && palResponseEnabled) {
        await BiblicalFigureRegistry.ensureLoaded();
        await PalTransitionLines.ensureLoaded();
        final transitionRef = PalTransitionLines.getLineRef(previewKey);
        final framingRef =
            BiblicalFigureRegistry.getFramingLineRef(previewKey);

        // Bridge beat: speak a transition line BETWEEN the reflection
        // (already played above) and the framing line. The transition
        // is the conversational hand-off — "I have a story for you" —
        // that signals PAL is moving from acknowledging the user's
        // mood to introducing a specific story.
        if (transitionRef != null) {
          final palAudio = ref.read(palAudioServiceProvider);
          try {
            final played =
                await palAudio.playLine(transitionRef.id, voiceKey);
            if (played) {
              await palAudio.awaitPlaybackComplete();
              logEvent('pal_audio_played', {
                'line_id': transitionRef.id,
                'type': 'transition_response',
                'voice_key': voiceKey,
                'bible_story_key': previewKey,
              });
            }
          } catch (e) {
            debugPrint('[MainMenu] Voice-path transition audio failed: $e');
          }
          if (!mounted || _voiceFlow != _VoiceFlowState.responding) return;
          await Future.delayed(const Duration(milliseconds: 300));
        }

        if (framingRef != null) {
          final palAudio = ref.read(palAudioServiceProvider);
          try {
            final played =
                await palAudio.playLine(framingRef.id, voiceKey);
            if (played) {
              await palAudio.awaitPlaybackComplete();
              logEvent('pal_audio_played', {
                'line_id': framingRef.id,
                'type': 'framing_response',
                'voice_key': voiceKey,
                'bible_story_key': previewKey,
              });
            }
          } catch (e) {
            debugPrint('[MainMenu] Voice-path framing audio failed: $e');
          }
          if (!mounted || _voiceFlow != _VoiceFlowState.responding) return;
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    // Open the player directly with the pre-selected story hint.
    if (!mounted) return;
    _cancelConversation();
    await selectStoryAndOpenPlayer(
      ref: ref,
      context: context,
      mood: effectiveMood,
      userText: transcript,
      bibleStoryKey: previewKey,
    );
    if (mounted) FocusScope.of(context).unfocus();
  }

  // -------------------------------------------------------------------
  // Journey Doctrine Slice 2 — cold-open cascade integration
  // -------------------------------------------------------------------

  /// Captures the user's STT response after the journey offer plays.
  /// Reuses the existing `_sttService` instance (NOT a fresh one) so
  /// the iOS audio session that PalAudioService just used cleanly
  /// hands off to STT. Mirrors `_startListeningForMood`'s mic-pulse
  /// state shape but routes the transcript back via Future instead
  /// of dispatching to mood detection.
  /// Strip PAL's own open-door tail from a transcript captured while
  /// the offer beat was still speaking (tail-overlap listening,
  /// 2026-07-09). Without this, the mic hearing "…tell me what's on
  /// your heart today" could misclassify as a mood redirect. Matching
  /// is normalized (lowercase, apostrophes/punctuation dropped) and
  /// longest-phrase-first so partial echoes strip cleanly; the user's
  /// own words ("yes", "I'm anxious") survive untouched.
  static String _stripOfferEcho(String transcript) {
    var t = transcript
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Covers every Open-Door Tail Family line (2026-07-15) — longer
    // phrases before their substrings, since replaceAll runs in order.
    const echoes = [
      'or tell me whats been on your mind lately',
      'or tell me what today has been like for you',
      'or tell me what youve been thinking about',
      'or tell me what brought you here today',
      'or tell me whats been weighing on you',
      'or tell me whats on your heart today',
      'or tell me how youre doing today',
      'or tell me whatevers on your mind',
      'or tell me how your day is going',
      'or tell me whats on your mind',
      'whats been on your mind lately',
      'what today has been like for you',
      'what youve been thinking about',
      'what brought you here today',
      'whats been weighing on you',
      'whats on your heart today',
      'how youre doing today',
      'whatevers on your mind',
      'how your day is going',
      'on your heart today',
      'your heart today',
      'or whats on your mind',
      'whats on your mind',
    ];
    for (final e in echoes) {
      t = t.replaceAll(e, ' ');
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String?> _captureJourneyResponse() async {
    // Single capture (2026-07-09): the earlier echo-only RETRY here
    // started a second startListening() immediately after the first
    // stopped — which is exactly what _cancelConversation() does to
    // abort, so the retry defeated the Cancel button (it re-listened
    // the instant cancel stopped it). With playAndRecord the mic is
    // live during the tail, so the strip-then-classify single pass is
    // enough; a pure-echo capture just classifies as ambiguous/decline,
    // which is the honest silence-floor outcome.
    final raw = await _captureJourneyResponseOnce();
    if (raw == null) return null;
    final cleaned = _stripOfferEcho(raw);
    return cleaned.isEmpty ? null : cleaned;
  }

  // Completer of the in-flight journey STT capture, exposed so
  // _cancelConversation can complete it with null immediately on Cancel
  // (rather than leaving the cascade awaiting the 12s safety timer).
  Completer<String?>? _journeyCaptureCompleter;

  Future<String?> _captureJourneyResponseOnce() async {
    if (!mounted) return null;
    setState(() {
      _voiceFlow = _VoiceFlowState.listening;
      _partialTranscript = '';
    });
    _micPulseController.repeat(reverse: true);

    final completer = Completer<String?>();
    _journeyCaptureCompleter = completer;
    Timer? safetyTimeout;
    // Track the last non-empty partial transcript. Adam's iPhone
    // 2026-07-01: the STT engine delivered partial "yes" but never
    // isFinal=true after _speech.stop() was invoked by the endpoint
    // timer. If we time out with a captured partial, complete with
    // it — the classifier can still dispatch on "yes".
    String lastPartial = '';

    void cleanup() {
      _micPulseController.stop();
      safetyTimeout?.cancel();
      if (identical(_journeyCaptureCompleter, completer)) {
        _journeyCaptureCompleter = null;
      }
    }

    void completeWithPartial() {
      if (completer.isCompleted) return;
      cleanup();
      completer.complete(
          lastPartial.trim().isEmpty ? null : lastPartial);
    }

    // Safety timer: 12s max wait for isFinal. The endpoint timer
    // inside SttService fires at 3.5s of silence following a
    // partial, so a normal capture completes in ~5-6s. 12s gives
    // slack for isFinal delivery; if it still hasn't arrived, we
    // trust the last partial (Adam's iPhone case: "yes" partial
    // captured but engine never finalized post-stop()).
    //
    // Set BEFORE startListening so a synchronous onError path
    // (test env, iOS permission edge-cases) has a cancelable timer.
    safetyTimeout = Timer(const Duration(seconds: 12), completeWithPartial);

    // Instant-accept watch (2026-07-09, tail-overlap listening): a
    // bare accept token in ANY partial dispatches immediately — no
    // 3.5s endpoint wait, no finalization. Safe against PAL's own
    // tail echo because "yes"/"yeah"/"yep" appear in ZERO of the 77
    // beat/offer texts (verified against outgoing_beats.json + the
    // render script's CLIPS) — those words can only be the user.
    final instantAccept = RegExp(r'\b(yes|yeah|yep)\b', caseSensitive: false);

    try {
      await _sttService.startListening(
        onResult: (result) {
          if (!mounted) return;
          // Cancel-aware: once _cancelConversation has flipped the flow
          // off `listening`, ignore any late/ stop()-induced result so
          // it can't complete the completer with an empty transcript
          // that would classify as ambiguous and reopen the mic. Mirrors
          // the mood-flow capture's `_voiceFlow != listening` guard.
          if (_voiceFlow != _VoiceFlowState.listening) return;
          if (!result.isFinal) {
            if (result.text.isNotEmpty) {
              lastPartial = result.text;
              if (instantAccept.hasMatch(result.text) &&
                  !completer.isCompleted) {
                cleanup();
                _sttService.stopListening();
                completer.complete('yes');
                return;
              }
            }
            setState(() => _partialTranscript = result.text);
            return;
          }
          if (!completer.isCompleted) {
            cleanup();
            completer.complete(
                result.text.trim().isEmpty ? null : result.text);
          }
        },
        onError: (_) => completeWithPartial(),
      );

      return await completer.future;
    } catch (_) {
      completeWithPartial();
      return lastPartial.trim().isEmpty ? null : lastPartial;
    }
  }

  /// Resolves every journey-cascade dependency from Riverpod and runs
  /// [fireJourneyOffer]. Called ONLY from the PAL-button (cold-open)
  /// entry point per the Entry-Point Split doctrine — the offer
  /// REPLACES the cold-open greeting; decline gets an "Of course."
  /// beat. Mood buttons bypass the cascade entirely (see
  /// _handleMoodButtonTap + JOURNEY_DOCTRINE.md § Entry-Point Split).
  ///
  /// Journey Doctrine Slice 2: silence-floor honest — if any gate
  /// closes, returns an outcome the caller treats as "fall through
  /// to the normal cold-open path."
  Future<JourneyOfferResult> _tryFireJourneyCascade() async {
    if (_journeyCascadeSpokenThisSession) {
      return const JourneyOfferResult(
        JourneyOfferOutcome.engineSilent,
        skippedReason: 'session_already_spoken',
      );
    }

    final appState = ref.read(appStateProvider).valueOrNull;
    final preferences = appState?.userPreferences;
    if (preferences == null) {
      return const JourneyOfferResult(
        JourneyOfferOutcome.consentBlocked,
        skippedReason: 'no_preferences',
      );
    }

    // STT permission is NOT pre-flighted here. checkPermissions()
    // has an 8s internal timeout that orphans in test-environment
    // teardown, and in production the STT capture step itself
    // handles denial cleanly (onError → null transcript → ambiguous
    // bucket → graceful decline). The cost is a ~10s offer audio
    // play before the user discovers they can't respond verbally —
    // acceptable for the mic-denied edge case.
    final sessionStore = await ref.read(palSessionStoreProvider.future);
    final registry = await ref.read(journeyRegistryProvider.future);
    final audioResolver =
        await ref.read(journeyAudioResolverProvider.future);
    final classifier = ref.read(journeyResponseClassifierProvider);
    final palAudio = ref.read(palAudioServiceProvider);

    // While the offer plays, keep the voice flow in playingOpeningLine
    // (PAL is speaking) so UI affordances match what the user hears.
    if (mounted) {
      setState(() => _voiceFlow = _VoiceFlowState.playingOpeningLine);
    }

    // Beta testing (JOURNEY_TESTING_ENABLED): when a cadence override is
    // driving repeat tests, tag every journey event `synthetic_session`
    // so panel-driven runs are excluded from baseline continuation
    // metrics. Compiled out in production (the flag is const false).
    final synthetic = kJourneyTestingEnabled &&
        (await sessionStore.getJourneyCadenceOverride()) != null;
    void journeyLog(String event, Map<String, Object?> props) {
      logEvent(
        event,
        synthetic ? {...props, 'synthetic_session': true} : props,
      );
    }

    // Activate the record-capable audio session BEFORE the ~13s offer
    // plays (2026-07-09 cold-start fix, from the STT investigation).
    // ensureAudioSessionActive now configures .playAndRecord, so this
    // call powers up the microphone input route up-front — hidden under
    // the offer's speech — instead of at listen() time. Without it the
    // route stays output-only (.playback) through the offer and the
    // plugin's listen() must renegotiate playback→record, the measured
    // ~2.3s that dropped the user's first "yes". The journey path skips
    // the cold-open greeting that would otherwise make this call.
    await palAudio.ensureAudioSessionActive();
    if (!mounted) {
      return const JourneyOfferResult(JourneyOfferOutcome.exception);
    }

    final result = await fireJourneyOffer(
      preferences: preferences,
      sessionStore: sessionStore,
      journeyRegistry: registry,
      audioResolver: audioResolver,
      classifier: classifier,
      // Offer plays fully, then the mic opens in real silence. Opening
      // it during playback interrupts the offer (mic and just_audio
      // fight for the route); the cold start is instead absorbed by the
      // ensureAudioSessionActive() call above, which warms the mic route
      // under cover of the offer.
      playOfferPlan: palAudio.playJourneyOffer,
      playDeclinePlan: palAudio.playJourneyDecline,
      captureResponse: _captureJourneyResponse,
      now: DateTime.now(),
      logger: journeyLog,
      // Cancel checkpoint: _cancelConversation drops _voiceConversationActive
      // and flips _voiceFlow to inactive. The runtime polls this after the
      // offer and after capture to abort without a decline clip or restart.
      isCancelled: () =>
          !_voiceConversationActive ||
          _voiceFlow == _VoiceFlowState.inactive,
    );

    if (result.offerWasSpoken) {
      _journeyCascadeSpokenThisSession = true;
    }
    return result;
  }

  /// Opens the next-in-journey story directly (the acceptance path).
  /// Skips Slice 2d recognition (the offer already named the
  /// character) and advances the journey-continuation cooldown after
  /// the player loads.
  ///
  /// Doctrine: cooldown advances only when the user accepts AND the
  /// next-in-journey story plays successfully. V0 treats "player
  /// loadParable returns true" as "plays successfully."
  Future<void> _openJourneyNextStory(JourneyContinuationOffer offer) async {
    logEvent('journey_accept_step', {'step': 'entered'});

    // Global timeout defense: no matter WHERE the accept path wedges
    // (loadParable audio-session state, register-cooldown SharedPrefs,
    // _cancelConversation's palAudio.stop(), the Navigator push
    // itself), the user eventually gets navigated. Which step tripped
    // the timeout is captured in telemetry via the per-step log
    // events emitted along the way.
    //
    // 75s, not 12s (2026-07-09, slim-build on-device finding): the
    // original 12s budget was sized for BUNDLED story audio, where
    // loadParable is near-instant. Slim/R2 builds legitimately stream
    // multi-MB story audio inside loadParable — Adam's accept downloaded
    // 4.4MB from R2, crossed 12s, and the timeout dumped him on the
    // browsing screen while the download quietly completed behind it.
    // loadParable now carries its own 45s timeout (feeding the existing
    // load_failed fallback), so this outer ceiling is a pure last-resort
    // wedge backstop sized above the worst-case legitimate flow
    // (~2s prep + 45s load cap + ~14s intro caps + nav).
    try {
      await _openJourneyNextStoryUnsafe(offer)
          .timeout(const Duration(seconds: 75));
    } on TimeoutException {
      logEvent('journey_accept_timeout', {
        'journey_id': offer.journey.journeyId,
        'next_story_anchor': offer.nextStory.scriptureAnchorId ??
            offer.nextStory.anchorId,
      });
      if (!mounted) return;
      // Best-effort fallback: cancel the conversation state so the
      // main menu is usable again. No navigation — staying on the
      // main menu is the safe surface (2026-07-09, Adam's on-device
      // call; see _journeyAcceptFallback).
      try {
        _cancelConversation();
      } catch (e) {
        logEvent('journey_accept_step', {
          'step': 'timeout_cancel_conversation_failed',
          'error': e.toString(),
        });
      }
    } catch (e, st) {
      logEvent('journey_accept_error', {
        'error': e.toString(),
        'stack_first_line': st.toString().split('\n').first,
      });
      if (mounted) {
        try {
          _cancelConversation();
        } catch (_) {}
      }
    }
  }

  /// Inner accept-path work — wrapped in `_openJourneyNextStory`'s
  /// timeout + error handler. Every await emits a telemetry
  /// breadcrumb so a future support-bundle capture shows which step
  /// the flow was in if it wedges.
  /// Updates the on-screen subtitle text to show the current step.
  /// Diagnostic aid — lets us see WHERE the accept path wedges by
  /// looking at the phone screen instead of digging through logs.
  /// Guarded by `mounted` because this can race with widget disposal.
  void _showAcceptStep(String step) {
    if (!mounted) return;
    setState(() => _greetingText = 'accept: $step');
  }

  /// Bulletproof accept-path fallback — used whenever the flow
  /// can't honor the user's "yes" (userPrefs missing, no matching
  /// parable, load failed).
  ///
  /// Earlier versions dropped these branches into
  /// `_startListeningForMood()`, which SILENTLY NO-OPS because it
  /// gates on `_voiceFlow == playingGreeting`. Coming from the
  /// journey cascade, `_voiceFlow` is `listening` (set by
  /// `_captureJourneyResponse`). So the fallback did nothing —
  /// leaving the user with a frozen "accept: <step>" subtitle,
  /// `_voiceFlow` stuck on `listening`, mic dead, and the outer
  /// 12s timeout satisfied (the future returned cleanly). Wedge.
  ///
  /// This helper reliably cancels the conversation (which clears
  /// `_greetingText`, resets `_voiceFlow` to inactive, drops
  /// transcripts, releases the mic) and navigates to the safe
  /// browsing screen. User always ends up somewhere usable.
  Future<void> _journeyAcceptFallback(String reason) async {
    logEvent('journey_accept_step', {'step': 'fallback_$reason'});
    if (!mounted) return;
    try {
      _cancelConversation();
    } catch (e) {
      logEvent('journey_accept_step', {
        'step': 'fallback_cancel_conversation_failed',
        'reason': reason,
        'error': e.toString(),
      });
    }
    // Stay on the main menu (2026-07-09, Adam's on-device call): the
    // earlier pushNamed('/pals_parables') dumped a failed accept onto
    // the legacy PAL's-Stories browsing screen, which reads as a
    // "strange mood screen" mid-conversation. _cancelConversation()
    // already resets the orb, mic, and greeting — the main menu IS the
    // safe usable surface, so no navigation is needed or wanted.
  }

  Future<void> _openJourneyNextStoryUnsafe(
      JourneyContinuationOffer offer) async {
    // Belt-and-braces #1: force the STT engine's higher-level stop
    // call. The plugin-level _speech.stop() added to SttService.
    // startListening's onResult isFinal branch didn't fully clear
    // the audio session in Adam's 2026-07-01 retest — mirror the
    // conservative path the mood-flow's cancel-conversation takes.
    try {
      _sttService.stopListening();
    } catch (_) {
      // Safe-fail; already-stopped throws are fine.
    }
    _showAcceptStep('stt_stopped');

    final appState = ref.read(appStateProvider).valueOrNull;
    final userPrefs = appState?.userPreferences;
    if (userPrefs == null) {
      await _journeyAcceptFallback('no_userprefs');
      return;
    }

    final bucketName = userPrefs.preferredLengthBucket ?? 'short';
    final bucket = StoryLengthBucket.fromJson(bucketName);

    logEvent('journey_accept_step', {'step': 'before_parable_service'});
    _showAcceptStep('parable_service');
    final parableService = await ref.read(parableServiceProvider.future);
    if (!mounted) return;

    logEvent('journey_accept_step', {'step': 'before_get_parable'});
    _showAcceptStep('get_parable');
    final journeyParable = await parableService.getParableByJourneyStory(
      offer.nextStory,
      lengthBucket: bucket,
      userPrefs: userPrefs,
    );
    if (!mounted) return;

    if (journeyParable == null) {
      // On-screen numeric detail — surface the failed tuple so we
      // can read it without pulling logs.  4-second hold so Adam
      // can actually READ it before nav flips to the browsing
      // screen. (2026-07-01: earlier version flashed too fast.)
      _showAcceptStep(
          'null:sn=${offer.nextStory.storyNumber}/bk=${bucket.name}/'
          'ls=${userPrefs.languageStyle}');
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      await _journeyAcceptFallback('parable_null');
      return;
    }

    logEvent('journey_accept_step', {
      'step': 'before_add_to_history',
      'story_id': journeyParable.storyId,
    });
    _showAcceptStep('add_to_history');
    final appStateNotifier = ref.read(appStateProvider.notifier);
    await appStateNotifier.addToHistory(journeyParable);
    if (!mounted) return;

    // Belt-and-braces #2: force iOS AVAudioSession back to .playback
    // BEFORE the parable player's setFilePath runs. If STT left the
    // session in .record, this is what unwedges just_audio.
    logEvent('journey_accept_step', {'step': 'before_audio_session_reset'});
    _showAcceptStep('audio_session');
    try {
      await ref.read(palAudioServiceProvider).ensureAudioSessionActive();
    } catch (e) {
      logEvent('journey_accept_step', {
        'step': 'audio_session_reset_failed',
        'error': e.toString(),
      });
    }
    if (!mounted) return;

    logEvent('journey_accept_step', {'step': 'before_load_parable'});
    _showAcceptStep('load_parable');
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    // Own 45s budget: on slim/R2 builds this call streams the story
    // audio from R2 (multi-MB), which must not share the outer wedge
    // backstop. Timeout resolves to false → the existing load_failed
    // fallback. The underlying download continues and caches, so a
    // retry accept typically succeeds instantly.
    final loaded = await playerNotifier
        .loadParable(journeyParable)
        .timeout(const Duration(seconds: 45), onTimeout: () {
      logEvent('journey_accept_step', {'step': 'load_parable_timeout'});
      return false;
    });
    if (!mounted) return;

    if (!loaded) {
      await _journeyAcceptFallback('load_failed');
      return;
    }

    logEvent('journey_accept_step', {'step': 'before_record_cooldown'});
    _showAcceptStep('record_cooldown');
    final sessionStore = await ref.read(palSessionStoreProvider.future);
    await sessionStore.recordJourneyContinuationSpoken();
    if (!mounted) return;

    // Play the same transition + framing intro every mood-flow story
    // gets. Adam 2026-07-01: earlier attempt hung the accept path
    // because the STT audio session wasn't released (root-cause fix
    // shipped in PR #61's SttService._speech.stop() call). Now that
    // the audio session is deterministically freed, the intro can
    // play cleanly. Helper wraps every awaitPlaybackComplete in an
    // 8s timeout so a future audio-stack anomaly can't strand the
    // user.
    logEvent('journey_accept_step', {'step': 'before_intro'});
    _showAcceptStep('intro');
    await _playJourneyStoryIntro(journeyParable);
    if (!mounted) return;

    logEvent('journey_accept_step', {'step': 'before_cancel_conversation'});
    _showAcceptStep('cancel_conversation');
    _cancelConversation();
    logEvent('journey_accept_step', {'step': 'before_navigate'});
    _showAcceptStep('navigate');
    // Fire-and-forget push (2026-07-09 breadcrumb finding): a Navigator
    // push future resolves when the pushed route is POPPED, not when it
    // appears. Awaiting it here kept this method (and therefore the
    // outer accept-path timeout) alive for the entire time the user
    // listened to the story — the timeout then fired mid-story and ran
    // its fallback cleanup underneath the player. The old 12s window
    // plus the old pushNamed('/pals_parables') fallback is what ripped
    // the user off the player onto the legacy browsing screen.
    unawaited(Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const ParablePlayerScreen(showArrivalAnimation: true),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeInOut);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale:
                  Tween<double>(begin: 0.98, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
      ),
    ));
    logEvent('journey_accept_step', {'step': 'navigate_pushed'});
  }

  /// Plays the transition + framing intro lines for a journey-
  /// accepted parable. Mirrors the intro sequence in
  /// [_processMoodFromVoice] so every story — mood-flow or
  /// journey-continuation — opens with the same PAL rhythm:
  /// recognition → introduction → Scripture. Silent skip on any
  /// gate (consent, missing library, missing ref, audio failure).
  ///
  /// The reflection line from _processMoodFromVoice is deliberately
  /// NOT included here — reflection responds to the USER's mood
  /// utterance; on journey accept, the user only said "yes" (no
  /// mood expressed), so no reflection is warranted.
  ///
  /// Re-enabled 2026-07-02 after PR #61's SttService._speech.stop()
  /// fix eliminated the audio-session wedge that had hung this
  /// helper on 2026-06-30. Each awaitPlaybackComplete is wrapped in
  /// an 8s timeout as belt-and-braces so a future audio anomaly
  /// can't strand the user.
  // ── Journey accept-acknowledgment rotation ──────────────────────
  // Played after "yes", before the story's framing line — a gentle step
  // onto the path that bridges the accept into the story announcement.
  // Governing rule (docs/JOURNEY_TRANSITION_VOICE.md): it must NEVER
  // draw attention to itself; the story is the destination. Softly
  // matched to the coming story's flavor so the set feels handcrafted,
  // not random. Tag: 'walk' | 'wonder' | 'any'. Eligible pool for a
  // story = its flavor's beats + all 'any' beats. Clips live in the
  // journey/ subdir (rendered by scripts/render_journey_audio.py).
  static const List<(String, String)> _acceptAcksAdult = [
    ('accept_keep_walking', 'walk'),
    ('accept_walk_farther', 'walk'),
    ('accept_see_where', 'wonder'),
    ('accept_continue', 'any'),
    ('accept_alright', 'any'),
    ('accept_of_course', 'any'),
  ];
  static const List<(String, String)> _acceptAcksKid = [
    ('accept_kid_keep_walking', 'walk'),
    ('accept_kid_what_happens', 'wonder'),
    ('accept_kid_come_on', 'any'),
    ('accept_kid_ready', 'any'),
    ('accept_kid_keep_going', 'any'),
  ];
  // Session-only recency so the same ack never plays twice in a row.
  String? _lastAcceptAckId;

  /// Soft flavor for the accept-ack match. 'wonder' for vision/dream/
  /// mystery stories, else 'walk' (the narrative default). Never
  /// critical — a miss just plays a still-appropriate neutral or
  /// walking beat.
  String _storyAckFlavor(Parable parable) {
    final key = (parable.bibleStoryKey ?? '').toLowerCase();
    final tags = <String>[
      ...parable.emotionalTags,
      ...?parable.themeTags,
    ].map((t) => t.toLowerCase());
    final wonder =
        RegExp(r'vision|dream|beast|revelation|ancient_of_days|mystery|wonder');
    if (wonder.hasMatch(key) || tags.any(wonder.hasMatch)) return 'wonder';
    return 'walk';
  }

  /// Pick the next accept-ack clip id, flavor-matched to [parable] and
  /// avoiding an immediate repeat.
  String _pickAcceptAck(Parable parable, bool isKid) {
    final pool = isKid ? _acceptAcksKid : _acceptAcksAdult;
    final flavor = _storyAckFlavor(parable);
    var eligible = pool
        .where((e) => e.$2 == flavor || e.$2 == 'any')
        .map((e) => e.$1)
        .where((id) => id != _lastAcceptAckId)
        .toList();
    if (eligible.isEmpty) {
      eligible =
          pool.map((e) => e.$1).where((id) => id != _lastAcceptAckId).toList();
    }
    if (eligible.isEmpty) eligible = pool.map((e) => e.$1).toList();
    final pick = eligible[_random.nextInt(eligible.length)];
    _lastAcceptAckId = pick;
    return pick;
  }

  Future<void> _playJourneyStoryIntro(Parable parable) async {
    final bibleStoryKey = parable.bibleStoryKey;
    if (bibleStoryKey == null || bibleStoryKey.isEmpty) return;

    final appState = ref.read(appStateProvider).valueOrNull;
    final userPrefs = appState?.userPreferences;
    if (userPrefs == null) return;
    if (userPrefs.palVoiceEnabled != true) return;
    if (userPrefs.palGreetingsEnabled == false) return;

    // Reset voice flow to `responding` — matches _processMoodFromVoice
    // pattern. Without this, the UI stays on `listening` (the state
    // _captureJourneyResponse left it in) which renders as the fallback
    // "Preparing your story..." text — confusing on the accept path
    // where PAL is actively speaking, not preparing.
    if (mounted) {
      setState(() => _voiceFlow = _VoiceFlowState.responding);
    }

    final voiceKey = userPrefs.palVoiceKey;
    final palAudio = ref.read(palAudioServiceProvider);

    // Accept acknowledgment: a gentle step onto the path BEFORE the
    // story is announced — bridges the "yes" so it doesn't jump-cut
    // into narration. Flavor-matched + rotated; never draws attention
    // to itself (docs/JOURNEY_TRANSITION_VOICE.md). Best-effort — a
    // miss or failure just falls through to the framing line.
    final ackId = _pickAcceptAck(parable, userPrefs.kidFriendlyOnly);
    if (mounted) {
      try {
        final playedAck = await palAudio.playLine('journey/$ackId', voiceKey);
        if (playedAck) {
          await palAudio.awaitPlaybackComplete().timeout(
                const Duration(seconds: 6),
                onTimeout: () {},
              );
          logEvent('pal_audio_played', {
            'line_id': ackId,
            'type': 'accept_ack_journey',
            'voice_key': voiceKey,
          });
        }
      } catch (e) {
        logEvent('pal_audio_error',
            {'context': 'journey_accept_ack', 'error': e.toString()});
      }
    }

    await BiblicalFigureRegistry.ensureLoaded();
    final framingRef =
        BiblicalFigureRegistry.getFramingLineRef(bibleStoryKey);

    // NOTE (2026-07-02): the transition line library is authored for
    // MOOD-FLOW context — every one of TRANS_01..12 references
    // "that" / "this" / "what you're carrying" / a matched feeling.
    // On journey-accept the user just said "yes" to a specific
    // continuation, not a mood — the story is already chosen, not
    // being matched. Playing a transition line here made Adam's
    // ear-check land wrong ("I think there's a story you would
    // connect with" — discovery framing, doesn't fit continuation).
    //
    // Doctrine-aligned answer: skip transition on journey-accept.
    // - PAL_VOICE.md Pillar 5: every question/line should help
    //   choose or land the story. Story is already chosen here.
    // - § PAL Knows When To Be Quiet: silence between "yes" and
    //   framing has intentional weight.
    // - Core Principle 4: no unnecessary questions/framings.
    //
    // Journey-specific transition audio (e.g. "Let's continue
    // David's story…") is a future follow-up if the framing-only
    // rhythm still feels bare after ear-check. See PR #57's
    // original discussion re: journey-continuation intro variants.

    // Framing: story-specific intro ("The story of…").
    if (framingRef != null && mounted) {
      try {
        final played = await palAudio.playLine(framingRef.id, voiceKey);
        if (played) {
          await palAudio.awaitPlaybackComplete().timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              logEvent('pal_audio_await_timeout', {
                'line_id': framingRef.id,
                'type': 'framing_journey_accept',
                'voice_key': voiceKey,
              });
            },
          );
          logEvent('pal_audio_played', {
            'line_id': framingRef.id,
            'type': 'framing_journey_accept',
            'voice_key': voiceKey,
            'bible_story_key': bibleStoryKey,
          });
        }
      } catch (e) {
        debugPrint('[MainMenu] Journey-accept framing audio failed: $e');
      }
    }
  }

  /// Pick a micro-response ID with non-repeat logic.
  String _pickMicroResponseId(String mood) {
    const microResponseIds = {
      'joyful': ['RESP_JOY_01', 'RESP_JOY_02', 'RESP_JOY_03', 'RESP_JOY_04', 'RESP_JOY_05', 'RESP_JOY_06'],
      'grateful': ['RESP_JOY_01', 'RESP_JOY_02', 'RESP_JOY_03', 'RESP_JOY_04', 'RESP_JOY_05', 'RESP_JOY_06'],
      'weary': ['RESP_WEARY_01', 'RESP_WEARY_02', 'RESP_WEARY_03', 'RESP_WEARY_04', 'RESP_WEARY_05', 'RESP_WEARY_06'],
      'anxious': ['RESP_ANX_01', 'RESP_ANX_02', 'RESP_ANX_03', 'RESP_ANX_04', 'RESP_ANX_05', 'RESP_ANX_06'],
      'hurting': ['RESP_HURT_01', 'RESP_HURT_02', 'RESP_HURT_03', 'RESP_HURT_04', 'RESP_HURT_05', 'RESP_HURT_06'],
      'brave_courage': ['RESP_JOY_01', 'RESP_JOY_02', 'RESP_JOY_03', 'RESP_JOY_04', 'RESP_JOY_05', 'RESP_JOY_06'],
      'calm_peaceful': ['RESP_NEU_01', 'RESP_NEU_02', 'RESP_NEU_03', 'RESP_NEU_04', 'RESP_NEU_05', 'RESP_NEU_06'],
      'encouraging': ['RESP_JOY_01', 'RESP_JOY_02', 'RESP_JOY_03', 'RESP_JOY_04', 'RESP_JOY_05', 'RESP_JOY_06'],
    };

    final pool = microResponseIds[mood] ?? microResponseIds['calm_peaceful']!;
    final recentIds = _recentMicroResponseIds.putIfAbsent(mood, () => []);

    var candidates = pool.where((id) => !recentIds.contains(id)).toList();
    if (candidates.isEmpty) {
      recentIds.clear();
      candidates = pool;
    }

    final picked = candidates[_random.nextInt(candidates.length)];
    recentIds.add(picked);
    if (recentIds.length > pool.length) {
      recentIds.removeAt(0);
    }

    return picked;
  }

  // ---------------------------------------------------------------------------
  // Button content builders
  // ---------------------------------------------------------------------------

  /// Large pulsing mic icon shown while STT is listening.
  Widget _buildMicContent(ThemeData theme) {
    return Center(
      key: const ValueKey('mic'),
      child: AnimatedBuilder(
        animation: _micPulseController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.5 + (_micPulseController.value * 0.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.mic, size: 44, color: Colors.white),
                SizedBox(height: 4),
                Text(
                  'Listening...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Normal PAL button content shown in all states except listening.
  Widget _buildPalContent(ThemeData theme) {
    return Center(
      key: const ValueKey('pal'),
      child: Text(
        'PAL',
        style: theme.textTheme.headlineLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 54,
          letterSpacing: 8,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String get _palSubtitle {
    switch (_voiceFlow) {
      case _VoiceFlowState.inactive:
        return '';
      case _VoiceFlowState.playingOpeningLine:
        return 'PAL is speaking...';
      case _VoiceFlowState.playingGreeting:
        return 'PAL is speaking...';
      case _VoiceFlowState.responding:
        return 'PAL is responding...';
      case _VoiceFlowState.choosingLength:
        return 'Choose your story length';
      default:
        return 'Preparing your story...';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    // All text/overlay tracks the time-of-day palette so it stays legible
    // on the (unchanged) Living Sky background. Only the orb's own colors
    // swap to the warm Kids palette in kid mode (SPEC Feature 51.1).
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final orbPalette = LivingSky.resolvePalette(kidMode: widget.kidMode);

    if (!_introChecked) {
      return const SizedBox(height: 140);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Intro text overlay (above button)
          if (_showIntro)
            GestureDetector(
              onTap: () {
                if (_revealedLines < _introLines.length) {
                  _skipIntroToEnd();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < _revealedLines; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: FadeTransition(
                          opacity: _lineAnimations[i],
                          child: Text(
                            _introLines[i],
                            style: (i == 0 && _introLines[0].startsWith('HI,')
                                    ? theme.textTheme.headlineSmall
                                    : theme.textTheme.titleMedium)
                                ?.copyWith(
                              color: palette.foreground.primaryText,
                              fontWeight: i == 0 && _introLines[0].startsWith('HI,')
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              shadows: palette.foreground.textShadow,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Voice flow status (above PAL button)
          if (_voiceFlow != _VoiceFlowState.inactive) ...[
            _buildVoiceFlowOverlay(theme),
            const SizedBox(height: 12),
          ],

          // PAL Orb — circular glowing celestial button with breathing animation
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _breathScale,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _breathScale.value,
                    child: child,
                  );
                },
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_glowController, _breathGlow]),
                    builder: (context, child) {
                      final tapGlow =
                          Curves.easeInOut.transform(1.0 - _glowController.value) * 0.6;
                      final ambientGlow = _breathGlow.value;
                      return Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: const Alignment(-0.3, -0.4),
                            radius: 1.1,
                            colors: orbPalette.orbGradientColors,
                            stops: const [0.0, 0.55, 1.0],
                          ),
                          border: Border.all(
                            color: orbPalette.warmHighlight.withOpacity(0.7),
                            width: 1.5,
                          ),
                          boxShadow: [
                            // Ambient celestial glow — driven by breathing
                            BoxShadow(
                              color: orbPalette.orbGlowColor.withOpacity(ambientGlow),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                            // Outer ring
                            BoxShadow(
                              color: orbPalette.orbGlowColor.withOpacity(ambientGlow * 0.4),
                              blurRadius: 60,
                              spreadRadius: 12,
                            ),
                            // Tap flash
                            if (tapGlow > 0.01)
                              BoxShadow(
                                color: orbPalette.warmHighlight.withOpacity(tapGlow),
                                blurRadius: 48,
                                spreadRadius: 10,
                              ),
                          ],
                        ),
                        child: child,
                      );
                    },
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _voiceFlow == _VoiceFlowState.inactive ? _onPalTap : null,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          child: _voiceFlow == _VoiceFlowState.listening
                              ? _buildMicContent(theme)
                              : _buildPalContent(theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ),
              const SizedBox(height: 10),
              // Subtitle below the orb
              Text(
                _palSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.foreground.tertiaryText,
                  letterSpacing: 0.3,
                  shadows: palette.foreground.subtitleShadow,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),

          // Cancel button during voice flow
          if (_voiceFlow != _VoiceFlowState.inactive) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelConversation,
              child: Text(
                'Cancel',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.foreground.tertiaryText,
                  shadows: palette.foreground.subtitleShadow,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build the voice flow overlay showing greeting text, transcript, or response.
  Widget _buildVoiceFlowOverlay(ThemeData theme) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    switch (_voiceFlow) {
      case _VoiceFlowState.inactive:
        return const SizedBox.shrink();

      case _VoiceFlowState.playingOpeningLine:
        return Text(
          _greetingText ?? '...',
          style: theme.textTheme.titleMedium?.copyWith(
            color: palette.foreground.primaryText,
            fontStyle: FontStyle.italic,
            shadows: palette.foreground.textShadow,
          ),
          textAlign: TextAlign.center,
        );

      case _VoiceFlowState.playingGreeting:
        return Text(
          _greetingText ?? '...',
          style: theme.textTheme.titleMedium?.copyWith(
            color: palette.foreground.primaryText,
            fontStyle: FontStyle.italic,
            shadows: palette.foreground.textShadow,
          ),
          textAlign: TextAlign.center,
        );

      case _VoiceFlowState.listening:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_greetingText != null)
              Text(
                _greetingText!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.foreground.mutedText,
                  fontStyle: FontStyle.italic,
                  shadows: palette.foreground.subtitleShadow,
                ),
                textAlign: TextAlign.center,
              ),
            if (_partialTranscript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _partialTranscript,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.foreground.primaryText,
                  shadows: palette.foreground.textShadow,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );

      case _VoiceFlowState.responding:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_finalTranscript != null)
              Text(
                '"${_finalTranscript!}"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.foreground.tertiaryText,
                  shadows: palette.foreground.subtitleShadow,
                ),
                textAlign: TextAlign.center,
              ),
            if (_microResponseText != null) ...[
              const SizedBox(height: 6),
              Text(
                _microResponseText!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: palette.foreground.primaryText,
                  fontStyle: FontStyle.italic,
                  shadows: palette.foreground.textShadow,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );

      case _VoiceFlowState.choosingLength:
        if (_microResponseText == null) return const SizedBox.shrink();
        return Text(
          _microResponseText!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.foreground.secondaryText,
            fontStyle: FontStyle.italic,
            shadows: palette.foreground.subtitleShadow,
          ),
          textAlign: TextAlign.center,
        );

      case _VoiceFlowState.selectingStory:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_finalTranscript != null)
              Text(
                '"${_finalTranscript!}"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.foreground.tertiaryText,
                  shadows: palette.foreground.subtitleShadow,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text(
              'Preparing your story...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.foreground.primaryText,
                shadows: palette.foreground.textShadow,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }
}


// ---------------------------------------------------------------------------
// Feeling card tile — Kids mode tap-a-feeling input (SPEC Feature 51.3)
// ---------------------------------------------------------------------------

/// A single large emoji feeling card shown in the Kids-mode mood grid.
/// Tapping it submits the card's canonical phrase into the mood pipeline.
class _FeelingCardTile extends StatelessWidget {
  final KidFeelingCard card;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _FeelingCardTile({
    required this.card,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: palette.foreground.subtleSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.foreground.subtleBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(card.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 6),
                Text(
                  card.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: palette.foreground.primaryText,
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

// ---------------------------------------------------------------------------
// Reserved Panel — crossfades between IDLE / NOW PLAYING / FINISHED
// ---------------------------------------------------------------------------

/// Panel mode derived from [ParablePlayerState].
enum _PanelMode { idle, nowPlaying, finished }

/// Reserved panel directly under the PAL hero button.
/// Uses [AnimatedSwitcher] to crossfade between three content states.
class _ReservedPanel extends ConsumerStatefulWidget {
  const _ReservedPanel();

  @override
  ConsumerState<_ReservedPanel> createState() => _ReservedPanelState();
}

class _ReservedPanelState extends ConsumerState<_ReservedPanel> {
  bool _isDraggingSlider = false;
  double _dragValue = 0;

  // --------------- state derivation ---------------

  _PanelMode _deriveMode(ParablePlayerState s) {
    if (s.currentParable == null) return _PanelMode.idle;
    if (s.playbackCompleted) return _PanelMode.finished;
    return _PanelMode.nowPlaying;
  }

  // --------------- helpers ---------------

  /// Compact one-line scripture reference for NOW PLAYING.
  static String _scriptureLineFor(Parable parable) {
    if (parable.hasBibleSourceRef) return parable.bibleSourceRef!;
    final src = parable.scriptureSources;
    if (src.isEmpty) return '';
    if (src.length <= 2) return src.join(', ');
    return '${src[0]}, ${src[1]} +${src.length - 2} more';
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // --------------- actions ---------------

  Future<void> _handlePlay(ParablePlayerNotifier notifier) async {
    final result = await notifier.play();
    if (!mounted) return;
    switch (result) {
      case VoicePlayResult.played:
      case VoicePlayResult.noParable:
      case VoicePlayResult.error:
        break;
      case VoicePlayResult.needsConsent:
        final consent = await VoiceConsentDialog.show(context);
        if (!mounted) return;
        if (consent == VoiceConsentResult.enabled) {
          await notifier.play();
        }
      case VoicePlayResult.disabled:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Story narration is disabled. Enable it in Settings.'),
          ),
        );
    }
  }

  Future<void> _saveFavorite(Parable parable) async {
    final notifier = ref.read(appStateProvider.notifier);
    await notifier.addFavorite(parable);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to Favorites'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleMoodButtonTap(String mood) async {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    appStateNotifier.updateLastDetectedMood(mood);

    // Journey Doctrine — Entry-Point Split (locked 2026-06-30):
    //   PAL button  = conversation. Memory, journey cascade, STT.
    //   Mood button = shortcut. No memory, no beat, no STT.
    //
    // The tapped mood already communicates the user's intent;
    // interrupting it with "Remember Daniel…?" contradicts what
    // they asked for. Slice 2d recognition + Slice 2 continuation
    // both fire ONLY from the PAL button (see _runConversation).
    // The mood button goes straight to selectStoryAndOpenPlayer,
    // which retains the existing transition + framing intro pattern.
    // See JOURNEY_DOCTRINE.md § Entry-Point Split.
    await selectStoryAndOpenPlayer(
      ref: ref,
      context: context,
      mood: mood,
      userText: '',
    );
    if (mounted) FocusScope.of(context).unfocus();
  }

  Widget _buildMoodButtons(ThemeData theme) {
    // Reorder moods based on time of day — surface contextually relevant moods first
    final hour = DateTime.now().hour;
    final timeWindow = PalPromptService.getTimeWindow(hour);

    const allMoods = [
      ('Joyful', 'joyful'),
      ('Grateful', 'grateful'),
      ('Weary', 'weary'),
      ('Anxious', 'anxious'),
      ('Hurting', 'hurting'),
      ('Brave', 'brave_courage'),
      ('Peaceful', 'calm_peaceful'),
      ('Encouraged', 'encouraging'),
    ];

    // Time-based ordering: surface most relevant moods first
    const morningOrder = ['encouraging', 'joyful', 'grateful', 'brave_courage', 'anxious', 'calm_peaceful', 'weary', 'hurting'];
    const eveningOrder = ['calm_peaceful', 'grateful', 'weary', 'hurting', 'anxious', 'joyful', 'encouraging', 'brave_courage'];
    const lateNightOrder = ['calm_peaceful', 'weary', 'hurting', 'anxious', 'grateful', 'joyful', 'encouraging', 'brave_courage'];

    List<String>? order;
    if (timeWindow == 'morning') {
      order = morningOrder;
    } else if (timeWindow == 'evening') {
      order = eveningOrder;
    } else if (timeWindow == 'lateNight') {
      order = lateNightOrder;
    }

    final List<(String, String)> moods;
    if (order != null) {
      final o = order;
      moods = List.of(allMoods)..sort((a, b) => o.indexOf(a.$2).compareTo(o.indexOf(b.$2)));
    } else {
      moods = allMoods;
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: moods.map((entry) {
        final (label, moodKey) = entry;
        return PrimaryGlowButton(
          label: label,
          onPressed: () => _handleMoodButtonTap(moodKey),
        );
      }).toList(),
    );
  }

  // --------------- build ---------------

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(parablePlayerProvider);
    final mode = _deriveMode(playerState);
    final theme = Theme.of(context);

    // Fixed-height envelope so the panel's height never drives the
    // outer column to recompute its `MainAxisAlignment.center` layout
    // when the mode switches (e.g., nowPlaying → idle on back-nav).
    // Without this, items above and below the panel visibly shift
    // toward the recalculated centerline as `AnimatedSwitcher` resizes.
    // 240 fits all three modes (idle mood-button wrap, nowPlaying
    // title+slider+play, finished save+replay) tightly so the screen
    // doesn't need to scroll on common iPhone heights.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        height: 240,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          // Layout builder centers each mode within the fixed envelope
          // so the existing visual centering is preserved.
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.center,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: _buildPanel(mode, playerState, theme),
        ),
      ),
    );
  }

  Widget _buildPanel(
      _PanelMode mode, ParablePlayerState state, ThemeData theme) {
    switch (mode) {
      case _PanelMode.idle:
        return _buildIdlePanel(theme);
      case _PanelMode.nowPlaying:
        return _buildNowPlayingPanel(state, theme);
      case _PanelMode.finished:
        return _buildFinishedPanel(state, theme);
    }
  }

  // --------------- IDLE ---------------

  Widget _buildIdlePanel(ThemeData theme) {
    // Kids mode swaps the adult mood buttons for the tap-a-feeling card grid
    // (SPEC Feature 51.3). The selection engine is unchanged — a card tap
    // submits a canonical phrase as userText, exactly like typing it.
    final kidMode = ref.watch(appStateProvider).valueOrNull?.userPreferences
            .kidFriendlyOnly ??
        false;
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        kidMode ? _buildFeelingCards(theme) : _buildMoodButtons(theme),
      ],
    );
  }

  /// Tap-a-feeling card grid for Kids mode (SPEC Feature 51.3).
  Widget _buildFeelingCards(ThemeData theme) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: kidFeelingCards.map((card) {
        return _FeelingCardTile(
          card: card,
          palette: palette,
          onTap: () => _handleFeelingCardTap(card),
        );
      }).toList(),
    );
  }

  Future<void> _handleFeelingCardTap(KidFeelingCard card) async {
    HapticFeedback.lightImpact();
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final moodResult =
        appStateNotifier.moodService.detectMood(card.canonicalPhrase);
    // Kids-mode warm fallback: cards always carry a keyword, so this only
    // matters if the engine ever returns the no-match default.
    final mood = kidFallbackMood(
      detectedMood: moodResult.mood,
      confidenceScore: moodResult.confidenceScore,
    );
    appStateNotifier.updateLastDetectedMood(mood);
    await selectStoryAndOpenPlayer(
      ref: ref,
      context: context,
      mood: mood,
      // Pass the canonical phrase so RelatabilityMatcher can rank the kid
      // pool by the situation tags the phrase carries.
      userText: card.canonicalPhrase,
    );
    if (mounted) FocusScope.of(context).unfocus();
  }

  // --------------- NOW PLAYING ---------------

  Widget _buildNowPlayingPanel(ParablePlayerState state, ThemeData theme) {
    final notifier = ref.read(parablePlayerProvider.notifier);
    final parable = state.currentParable!;
    final scripture = _scriptureLineFor(parable);

    return Column(
      key: const ValueKey('now_playing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Story title
        Text(
          parable.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (scripture.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            scripture,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),

        // Play / Pause
        IconButton(
          icon: Icon(
            notifier.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            size: 56,
          ),
          color: theme.colorScheme.primary,
          onPressed: () async {
            if (notifier.isPlaying) {
              notifier.pause();
            } else {
              await _handlePlay(notifier);
            }
          },
        ),
        const SizedBox(height: 8),

        // Seek slider
        StreamBuilder<Duration>(
          stream: notifier.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = notifier.duration ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            final displayValue = _isDraggingSlider
                ? _dragValue
                : position.inMilliseconds.toDouble().clamp(0.0, max);

            return Column(
              children: [
                Slider(
                  value: displayValue,
                  max: max > 0 ? max : 1,
                  onChangeStart: (v) {
                    setState(() {
                      _isDraggingSlider = true;
                      _dragValue = v;
                    });
                  },
                  onChanged: (v) {
                    setState(() => _dragValue = v);
                  },
                  onChangeEnd: (v) {
                    notifier.seek(Duration(milliseconds: v.toInt()));
                    setState(() => _isDraggingSlider = false);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(
                        _isDraggingSlider
                            ? Duration(milliseconds: _dragValue.toInt())
                            : position,
                      ), style: theme.textTheme.bodySmall),
                      Text(_fmt(duration),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // --------------- FINISHED ---------------

  Widget _buildFinishedPanel(ParablePlayerState state, ThemeData theme) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final notifier = ref.read(parablePlayerProvider.notifier);
    return Column(
      key: const ValueKey('finished'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          state.currentParable!.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.foreground.secondaryText,
            shadows: palette.foreground.subtitleShadow,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _saveFavorite(state.currentParable!),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                side: BorderSide(color: palette.cardBorder, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(Icons.favorite_outline, size: 16, color: palette.warmHighlight),
              label: const Text('Save'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final success = await notifier.loadParable(state.currentParable!);
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
                await _handlePlay(notifier);
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                side: BorderSide(color: palette.cardBorder, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(Icons.replay, size: 16, color: palette.warmHighlight),
              label: const Text('Replay'),
            ),
          ],
        ),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Length pill — Short / Full / Long chooser in the PAL voice flow
