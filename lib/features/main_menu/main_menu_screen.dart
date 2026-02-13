import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import '../../services/typewriter_click_service.dart';
import '../../services/greeting_audio_service.dart';
import '../../services/voice_consent_gate.dart';
import '../../theme/app_theme.dart';
import '../onboarding/first_launch_screen.dart' show kPalIntroShownKey;
import '../settings/settings_screen.dart';
import '../../core/app_logger.dart';

/// Main Menu Screen
/// Based on UI/UX Design Spec Section 4: Home Screen
///
/// Layout: Vertical, clean, centered, no scrolling required
/// - Daily Bread Verse (top, fixed, calm)
/// - PAL's Parables button (centerpiece, large, with gold outline)
/// - Favorites & History buttons (secondary, smaller, softer)
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
                  color: AppTheme.deepCharcoal.withOpacity(0.5),
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
                    color: AppTheme.deepCharcoal.withOpacity(0.7),
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

        return Scaffold(
          backgroundColor: AppTheme.parchment,
          body: SafeArea(
            bottom: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // Settings Icon (top right, subtle)
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: IconButton(
                                icon: Icon(
                                  Icons.settings_outlined,
                                  color: AppTheme.deepCharcoal.withOpacity(0.6),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const SettingsScreen()),
                                  );
                                },
                              ),
                            ),
                          ),

                          // Flexible spacer to center content
                          const Spacer(flex: 1),

                          // Daily Bread Verse Section (Top Area - Fixed, Calm, Centered)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              children: [
                                Text(
                                  'Daily Bread',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppTheme.warmGold,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  dailyBread,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '— $verseReference',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.deepCharcoal.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // PAL's Parables Button (Centerpiece - Large, Gold Outline)
                          // Wrapped with intro overlay for first-launch experience
                          _PalButtonWithIntro(theme: theme),

                          const SizedBox(height: 24),

                          // Secondary Buttons (Favorites, History & My PALs - Smaller, Softer)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pushNamed('/favorites');
                                        },
                                        style: OutlinedButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(vertical: 16),
                                          side: BorderSide(
                                            color: AppTheme.lightBlue,
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        icon: Icon(
                                          Icons.favorite_outline,
                                          size: 20,
                                          color: AppTheme.softSkyBlue,
                                        ),
                                        label: Text(
                                          'Favorites',
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            color: AppTheme.deepCharcoal,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pushNamed('/history');
                                        },
                                        style: OutlinedButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(vertical: 16),
                                          side: BorderSide(
                                            color: AppTheme.lightBlue,
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        icon: Icon(
                                          Icons.history_outlined,
                                          size: 20,
                                          color: AppTheme.softSkyBlue,
                                        ),
                                        label: Text(
                                          'History',
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            color: AppTheme.deepCharcoal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pushNamed('/my_pals');
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    side: BorderSide(
                                      color: AppTheme.lightBlue,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.people_outline,
                                    size: 20,
                                    color: AppTheme.softSkyBlue,
                                  ),
                                  label: Text(
                                    'My PALs',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: AppTheme.deepCharcoal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Flexible spacer to center content
                          const Spacer(flex: 2),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// PAL button with first-launch intro overlay.
/// Shows a 3-line typewriter intro on first launch, then pulses the button.
class _PalButtonWithIntro extends ConsumerStatefulWidget {
  final ThemeData theme;

  const _PalButtonWithIntro({required this.theme});

  @override
  ConsumerState<_PalButtonWithIntro> createState() => _PalButtonWithIntroState();
}

class _PalButtonWithIntroState extends ConsumerState<_PalButtonWithIntro>
    with SingleTickerProviderStateMixin {
  // Intro state
  bool _showIntro = false;
  bool _introChecked = false;
  String _displayedText = '';
  int _charIndex = 0;
  int _currentLine = 0;
  Timer? _typingTimer;
  final _clickHelper = TypewriterClickHelper();
  final _greetingAudio = GreetingAudioService.instance;

  // Pulse animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  int _pulseCount = 0;

  static const _introLines = [
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

    // Pre-initialize greeting audio for instant playback when PAL is tapped
    _greetingAudio.initialize();

    _checkIntroState();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pulseController.removeStatusListener(_onPulseStatus);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkIntroState() async {
    final sp = await SharedPreferences.getInstance();
    final alreadyShown = sp.getBool(kPalIntroShownKey) ?? false;
    if (!mounted) return;
    setState(() {
      _introChecked = true;
      _showIntro = !alreadyShown;
    });
    if (_showIntro) {
      // Pre-initialize audio for instant first-character click
      await _clickHelper.preInitialize();
      if (!mounted) return;
      _startTypingLine();
    }
  }

  void _startTypingLine() {
    if (_currentLine >= _introLines.length) {
      // All lines done, mark intro as shown
      _markIntroShown();
      return;
    }

    final line = _introLines[_currentLine];
    _charIndex = 0;

    _typingTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charIndex < line.length) {
        // Get the next character BEFORE updating state
        final nextChar = line[_charIndex];
        // Play click BEFORE setState for proper audio-visual sync
        _clickHelper.onCharAppended(nextChar);
        setState(() {
          _charIndex++;
          _displayedText = line.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
        // Line complete
        if (_currentLine == _introLines.length - 1) {
          // Last line ("Tap PAL to start.") - start pulse
          _startPulse();
        } else {
          // Pause before next line
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted || !_showIntro) return;
            setState(() {
              _currentLine++;
              _displayedText = '';
            });
            _startTypingLine();
          });
        }
      }
    });
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
        // Start next pulse cycle
        _pulseController.forward();
      } else {
        // Done pulsing - mark intro shown after a brief delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _showIntro) {
            _markIntroShown();
          }
        });
      }
    }
  }

  Future<void> _markIntroShown() async {
    _clickHelper.enabled = false; // Disable clicks when intro ends
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kPalIntroShownKey, true);
    if (!mounted) return;
    setState(() {
      _showIntro = false;
    });
  }

  void _onPalTap() {
    // Disable clicks immediately when user taps PAL
    _clickHelper.enabled = false;

    // Cancel any running timers/animations
    _typingTimer?.cancel();
    _pulseController.stop();

    // Mark intro as shown (fire and forget)
    if (_showIntro) {
      SharedPreferences.getInstance().then((sp) {
        sp.setBool(kPalIntroShownKey, true);
      });
      setState(() {
        _showIntro = false;
      });
    }

    // Play PAL greeting (non-blocking, consent-aware)
    _maybePlayPalGreeting();

    // Navigate to PAL's stories
    Navigator.of(context).pushNamed('/pals_parables');
  }

  /// Play PAL greeting audio if voice consent allows (non-blocking, fail-safe)
  void _maybePlayPalGreeting() {
    // Check voice consent
    final appState = ref.read(appStateProvider).valueOrNull;
    final prefs = appState?.userPreferences;
    final consentResult = VoiceConsentGate.checkPalGreetings(prefs);

    if (consentResult != VoiceGateResult.allowed) {
      // Silently skip - respect user preference
      return;
    }

    // Play greeting (fire-and-forget with error handling)
    _greetingAudio.playGreeting().catchError((error) {
      debugPrint('[PAL Greeting] Playback error: $error');
    });

    // Log success
    logEvent('pal_greeting_played', {
      'source': 'pal_button_tap',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    // Don't show anything until we've checked intro state
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
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60, maxHeight: 80),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Show completed lines
                    for (int i = 0; i < _currentLine; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _introLines[i],
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppTheme.deepCharcoal,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    // Current typing line
                    if (_currentLine < _introLines.length)
                      Text(
                        _displayedText + (_charIndex < _introLines[_currentLine].length ? '▋' : ''),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppTheme.deepCharcoal,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),

          // PAL Button with pulse animation
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.warmGold,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.warmGold.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: AppTheme.softSkyBlue,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _onPalTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories_outlined,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'PAL',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap for a mood based story',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

