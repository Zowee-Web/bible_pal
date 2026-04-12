import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import '../../services/pal_prompt_service.dart';
import '../../services/stt_service.dart';
import '../../providers/service_providers.dart';
import '../../core/biblical_figure_registry.dart';
import '../../core/pal_transition_lines.dart';
import '../../theme/app_theme.dart';
import '../../theme/living_sky.dart';
import '../onboarding/first_launch_screen.dart' show kPalIntroShownKey;
import '../settings/settings_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HapticFeedback;
import '../../providers/parable_player_notifier.dart';
import '../../models/parable.dart';
import '../consent/voice_consent_dialog.dart';
import '../../core/app_logger.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/premium_components.dart';

/// Main Menu Screen
/// Based on UI/UX Design Spec Section 4: Home Screen
///
/// Layout: Two-page "Sanctuary & Study" design
/// - Page 1 (Sanctuary): PAL orb hero, Daily Bread verse, swipe hint
/// - Page 2 (Study): Mood buttons, Text PAL, Read Story, Favorites/History/My PALs
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
  final String dailyBread;
  final String verseReference;

  const _MainMenuBody({
    required this.theme,
    required this.effectiveTheme,
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
          // Living Sky fills entire background, continuous across pages
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
                // PageView fills the rest
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: [
                      // Page 1: The Sanctuary
                      _SanctuaryPage(
                        theme: widget.theme,
                        dailyBread: widget.dailyBread,
                        verseReference: widget.verseReference,
                      ),
                      // Page 2: The Study
                      _StudyPage(key: _studyPageKey, theme: widget.theme),
                    ],
                  ),
                ),
                // Page dots indicator at bottom
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
        children: List.generate(2, (index) {
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
  final String dailyBread;
  final String verseReference;

  const _SanctuaryPage({
    required this.theme,
    required this.dailyBread,
    required this.verseReference,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Column(
      children: [
        const Spacer(flex: 3),

        // PAL orb — THE hero, bigger and bolder
        _PalButtonWithIntro(theme: theme),

        const SizedBox(height: 8),

        // Streak (subtle)
        Builder(builder: (context) {
          final streak = ref.watch(appStateProvider).valueOrNull?.userPreferences.currentStreak ?? 0;
          if (streak < 2) return const SizedBox.shrink();
          return Text(
            '$streak day streak',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.accentColor,
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.accentColor.withOpacity(0.90),
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

  static const _morningHints = [
    'Tell me how you\u2019re feeling\u2026',
    'What\u2019s on your heart today?',
    'How are you starting your day?',
    'What are you grateful for today?',
    'How\u2019s your spirit doing?',
  ];

  static const _eveningHints = [
    'Tell me how you\u2019re feeling\u2026',
    'What\u2019s on your heart tonight?',
    'How did your day go?',
    'What\u2019s weighing on you?',
    'Anything you need to lay down today?',
  ];

  List<String> get _hints {
    final hour = DateTime.now().hour;
    return hour < 17 ? _morningHints : _eveningHints;
  }

  @override
  void initState() {
    super.initState();
    _currentHintIndex = Random().nextInt(_hints.length);

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
          _currentHintIndex = (_currentHintIndex + 1) % _hints.length;
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

    // PAL framing response: show before navigating (text-input Traditional only)
    final userPrefs = ref.read(appStateProvider).valueOrNull?.userPreferences;
    if (userPrefs != null && userPrefs.storytellingMode == 'traditional') {
      final parableService = await ref.read(parableServiceProvider.future);
      final previewKey = await parableService.previewBibleStoryKey(
        mood: moodResult.mood,
        userPrefs: userPrefs,
        userText: text,
      );
      if (previewKey != null && mounted) {
        await BiblicalFigureRegistry.ensureLoaded();
        await PalTransitionLines.ensureLoaded();
        final framingLine =
            BiblicalFigureRegistry.getFramingLine(previewKey);
        final transitionLine =
            PalTransitionLines.getLine(previewKey);
        if (framingLine != null && mounted) {
          // Compose: framing line + optional transition line
          final displayText = transitionLine != null
              ? '$framingLine\n\n$transitionLine'
              : framingLine;
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

    if (!mounted) return;
    await Navigator.of(context).pushNamed('/length_picker', arguments: {
      'mood': moodResult.mood,
      'userText': text,
    });
    // Dismiss keyboard when returning from length picker / player
    if (mounted) _textFocusNode.unfocus();
  }

  Widget _buildKidModePill(BuildContext context, SkyPalette palette) {
    final appState = ref.watch(appStateProvider).valueOrNull;
    final isOn = appState?.userPreferences.kidFriendlyOnly ?? false;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(appStateProvider.notifier).updateKidFriendlyOnly(!isOn);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isOn
              ? palette.warmHighlight.withOpacity(0.08)
              : palette.cardColor,
          borderRadius: BorderRadius.circular(20),
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
                text: isOn ? 'ON' : 'OFF',
                style: TextStyle(
                  color: isOn ? palette.warmHighlight : palette.foreground.tertiaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageStyleRow(BuildContext context, SkyPalette palette) {
    final appState = ref.watch(appStateProvider).valueOrNull;
    final currentStyle = appState?.userPreferences.languageStyle ?? 'WEB';
    final isTraditional = (appState?.userPreferences.storytellingMode ?? 'traditional') == 'traditional';
    final isKidMode = appState?.userPreferences.kidFriendlyOnly ?? false;

    // Auto-correct: if kid mode is on and KJV is selected, switch to WEB
    if (isKidMode && currentStyle == 'KJV') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(appStateProvider.notifier).updateLanguageStyle('WEB');
      });
    }

    final showRow = isTraditional && !isKidMode;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: showRow ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: showRow
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: palette.foreground.scrimColor != Colors.transparent
                        ? palette.foreground.scrimColor
                        : palette.cardColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: palette.cardBorder.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LanguageTab(
                          label: 'World English Bible',
                          selected: currentStyle == 'WEB',
                          palette: palette,
                          onTap: () {
                            ref.read(appStateProvider.notifier).updateLanguageStyle('WEB');
                          },
                        ),
                      ),
                      Expanded(
                        child: _LanguageTab(
                          label: 'King James Version',
                          selected: currentStyle == 'KJV',
                          palette: palette,
                          onTap: () {
                            ref.read(appStateProvider.notifier).updateLanguageStyle('KJV');
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildStoryModeToggle(BuildContext context, SkyPalette palette) {
    final appState = ref.watch(appStateProvider).valueOrNull;
    final currentMode = appState?.userPreferences.storytellingMode ?? 'traditional';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: palette.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.cardBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: _StoryModeTab(
                label: 'Traditional',
                subtitle: 'Scripture-based',
                icon: Icons.menu_book_outlined,
                selected: currentMode == 'traditional',
                palette: palette,
                onTap: () {
                  ref.read(appStateProvider.notifier).updateStorytellingMode('traditional');
                },
              ),
            ),
            Expanded(
              child: _StoryModeTab(
                label: 'Creative',
                subtitle: 'Inspired storytelling',
                icon: Icons.auto_awesome_outlined,
                selected: currentMode == 'creative',
                palette: palette,
                onTap: () {
                  ref.read(appStateProvider.notifier).updateStorytellingMode('creative');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    return Column(
      children: [
        // Content area — centered vertically
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),

                      // Heading — fixed style to prevent shifts on theme change (kid mode)
                      Text(
                        'How are you feeling?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: palette.textColor,
                          letterSpacing: 0.3,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap a mood and PAL will find a story for you',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: palette.subtitleColor,
                          letterSpacing: 0.2,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Mood buttons / now playing / finished
                      const _ReservedPanel(),

                      const SizedBox(height: 36),

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

                      const SizedBox(height: 14),

                      // Story mode toggle — Traditional / Creative
                      _buildStoryModeToggle(context, palette),

                      // Language style — WEB / KJV (Traditional only)
                      _buildLanguageStyleRow(context, palette),

                      const SizedBox(height: 10),

                      // Kid Mode pill
                      Center(child: _buildKidModePill(context, palette)),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Text PAL input — pinned to bottom
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: AnimatedBuilder(
            animation: _hintFadeController,
            builder: (context, _) {
              return TextField(
                controller: _textController,
                focusNode: _textFocusNode,
                style: TextStyle(color: palette.textColor, fontSize: 17, height: 1.4),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _hints[_currentHintIndex],
                  hintStyle: TextStyle(
                    color: palette.foreground.tertiaryText.withValues(
                      alpha: _userIsTyping ? 0.0 : _hintFadeAnimation.value,
                    ),
                    fontSize: 17,
                    height: 1.4,
                  ),
                  filled: true,
                  fillColor: palette.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: palette.cardBorder, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: palette.cardBorder, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: palette.warmHighlight.withOpacity(0.5), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
    );
  }
}


/// Voice mood flow states for the conversational PAL interaction on main menu.
enum _VoiceFlowState {
  /// Normal main menu, no conversation active.
  inactive,

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

  const _PalButtonWithIntro({required this.theme});

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

  // Services for voice flow
  final PalPromptService _promptService = PalPromptService();
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

    // Start the voice-first conversational flow
    _startConversation();
  }

  /// Cancel the voice flow and return to inactive state.
  void _cancelConversation() {
    _autoStoryTimer?.cancel();
    _sttService.stopListening();
    _micPulseController.stop();
    ref.read(palAudioServiceProvider).stop();
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
  Future<void> _startConversation() async {
    // Pause breathing during voice flow
    _breathController.stop();
    setState(() => _voiceFlow = _VoiceFlowState.playingGreeting);

    // Load and play PAL greeting
    try {
      final prompt = await _promptService.getPrompt();
      if (!mounted) return;
      setState(() => _greetingText = prompt.text);

      final appState = ref.read(appStateProvider).valueOrNull;
      if (appState?.userPreferences.palGreetingsEnabled != false) {
        final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
        final userName = appState?.userPreferences.userName ?? '';
        final palAudio = ref.read(palAudioServiceProvider);
        final nameAudio = ref.read(nameAudioServiceProvider);

        final nameClip = userName.isNotEmpty
            ? await nameAudio.getRandomNameClip(userName, voiceKey)
            : null;

        if (nameClip == null && userName.isNotEmpty) {
          nameAudio.generateNamePhrases(name: userName, voiceKey: voiceKey);
        }

        try {
          final text = await palAudio.playPrompt(
            prompt.id,
            voiceKey,
            nameClipFile: nameClip?.file,
            nameClipText: nameClip?.text,
          );

          logEvent('pal_line_played', {
            'line_id': prompt.id,
            'type': 'prompt',
            'time_window': prompt.timeWindow,
            'voice_key': voiceKey,
            'name_prefix_used': text != prompt.text,
          });

          if (mounted && text.isNotEmpty) {
            setState(() => _greetingText = text);
          }
        } catch (e) {
          debugPrint('[MainMenu] PAL prompt audio failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[MainMenu] Failed to load prompt: $e');
      if (mounted) {
        setState(() => _greetingText = 'How are you doing today?');
      }
    }

    if (!mounted || _voiceFlow != _VoiceFlowState.playingGreeting) return;

    // Greeting done — auto-activate mic
    await _startListeningForMood();
  }

  /// Auto-activate STT after PAL greeting finishes.
  Future<void> _startListeningForMood() async {
    // Check permissions first
    final permResult = await _sttService.checkPermissions();
    if (!mounted || _voiceFlow != _VoiceFlowState.playingGreeting) return;

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

    // Play PAL micro-response audio
    final responseId = _pickMicroResponseId(result.mood);
    final appState = ref.read(appStateProvider).valueOrNull;
    final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
    final userName = appState?.userPreferences.userName ?? '';

    String responseText;
    if (appState?.userPreferences.palGreetingsEnabled == false) {
      responseText = moodService.getMicroResponseText(result.mood);
    } else {
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

    // Navigate to length picker with the detected mood
    if (!mounted) return;
    _cancelConversation();
    await Navigator.of(context).pushNamed('/length_picker', arguments: {
      'mood': result.mood,
      'userText': transcript,
    });
    if (mounted) FocusScope.of(context).unfocus();
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
    final palette = LivingSky.getPalette(LivingSky.getPhase());

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
                              color: palette.textColor,
                              fontWeight: i == 0 && _introLines[0].startsWith('HI,')
                                  ? FontWeight.w700
                                  : FontWeight.w500,
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
                            colors: palette.orbGradientColors,
                            stops: const [0.0, 0.55, 1.0],
                          ),
                          border: Border.all(
                            color: AppTheme.warmGold.withOpacity(0.7),
                            width: 1.5,
                          ),
                          boxShadow: [
                            // Ambient celestial glow — driven by breathing
                            BoxShadow(
                              color: palette.orbGlowColor.withOpacity(ambientGlow),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                            // Outer ring
                            BoxShadow(
                              color: palette.orbGlowColor.withOpacity(ambientGlow * 0.4),
                              blurRadius: 60,
                              spreadRadius: 12,
                            ),
                            // Tap flash
                            if (tapGlow > 0.01)
                              BoxShadow(
                                color: AppTheme.warmGold.withOpacity(tapGlow),
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

    await Navigator.of(context).pushNamed('/length_picker', arguments: {
      'mood': mood,
      'userText': '',
    });
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
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
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMoodButtons(theme),
      ],
    );
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
// Story mode tab — used in the Traditional / Creative toggle
// ---------------------------------------------------------------------------

class _StoryModeTab extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _StoryModeTab({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? palette.warmHighlight.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: selected
              ? Border.all(color: palette.warmHighlight, width: 2)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.warmHighlight.withOpacity(0.20 * palette.glowIntensity),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? palette.warmHighlight : palette.foreground.secondaryIcon,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? palette.foreground.primaryText
                        : palette.foreground.secondaryText,
                    letterSpacing: 0.3,
                    shadows: palette.foreground.subtitleShadow,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: selected
                    ? palette.foreground.secondaryText
                    : palette.foreground.tertiaryText,
                shadows: palette.foreground.subtitleShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language style tab — used in the WEB / KJV toggle
// ---------------------------------------------------------------------------

class _LanguageTab extends StatelessWidget {
  final String label;
  final bool selected;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _LanguageTab({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glow = palette.glowIntensity;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? palette.warmHighlight.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? palette.warmHighlight
                : Colors.transparent,
            width: selected ? 2 : 0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.warmHighlight.withOpacity(0.25 * glow),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? palette.foreground.primaryText
                  : palette.foreground.secondaryText,
              letterSpacing: 0.1,
              shadows: palette.foreground.subtitleShadow,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Length pill — Short / Full / Long chooser in the PAL voice flow
