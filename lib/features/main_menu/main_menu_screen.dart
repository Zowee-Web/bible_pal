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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HapticFeedback;
import '../../providers/parable_player_notifier.dart';
import '../../models/parable.dart';
import '../../widgets/story_length_radio_selector.dart';
import '../../core/story_length_bucket.dart';
import '../consent/voice_consent_dialog.dart';
import '../../services/reflection_service.dart';
import '../my_pals/select_pals_dialog.dart';
import '../../models/share_record.dart';
import 'package:uuid/uuid.dart';
import '../../services/stt_service.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

/// File-private tap counter for cross-widget PAL tap signaling.
/// Incremented by [_PalButtonWithIntro], watched by [_ReservedPanel].
final _palTapProvider = StateProvider<int>((ref) => 0);

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

                          const SizedBox(height: 16),

                          // Reserved panel: swaps IDLE / NOW PLAYING / FINISHED
                          const _ReservedPanel(),

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
    with TickerProviderStateMixin {
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
  late final AnimationController _glowController;

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

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Pre-initialize greeting audio for instant playback when PAL is tapped
    _greetingAudio.initialize();

    _checkIntroState();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _pulseController.removeStatusListener(_onPulseStatus);
    _pulseController.dispose();
    _glowController.dispose();
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
    // Soft glow (one-shot, fades out over 400ms)
    _glowController.forward(from: 0.0);

    // Light haptic feedback (no-op on web)
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }

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

    // Signal the reserved panel to start voice-first STT flow
    ref.read(_palTapProvider.notifier).state++;
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

          // PAL Button with pulse animation + tap glow
          ScaleTransition(
            scale: _pulseAnimation,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final glowOpacity =
                    Curves.easeInOut.transform(1.0 - _glowController.value) *
                        0.5;
                return Container(
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
                      if (glowOpacity > 0.01)
                        BoxShadow(
                          color: AppTheme.warmGold.withOpacity(glowOpacity),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                    ],
                  ),
                  child: child,
                );
              },
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

// ---------------------------------------------------------------------------
// Reserved Panel — crossfades between IDLE / NOW PLAYING / FINISHED
// ---------------------------------------------------------------------------

/// Panel mode derived from [ParablePlayerState].
enum _PanelMode { idle, listening, nowPlaying, finished }

/// Reserved panel directly under the PAL hero button.
/// Uses [AnimatedSwitcher] to crossfade between three content states.
class _ReservedPanel extends ConsumerStatefulWidget {
  const _ReservedPanel();

  @override
  ConsumerState<_ReservedPanel> createState() => _ReservedPanelState();
}

class _ReservedPanelState extends ConsumerState<_ReservedPanel> {
  StoryLengthBucket _selectedBucket = StoryLengthBucket.short;
  bool _reflectionExpanded = false;
  final ReflectionService _reflectionService = ReflectionService();

  // Voice-first STT state
  SttService? _sttService;
  bool _isVoiceActive = false;
  String _partialTranscript = '';

  @override
  void dispose() {
    _sttService?.dispose();
    super.dispose();
  }

  // --------------- state derivation ---------------

  _PanelMode _deriveMode(ParablePlayerState s) {
    if (_isVoiceActive) return _PanelMode.listening;
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

  void _onReadTodaysStory() {
    final ps = ref.read(parablePlayerProvider);
    if (ps.currentParable != null) {
      Navigator.of(context).pushNamed('/parable_player');
    } else {
      Navigator.of(context).pushNamed('/pals_parables');
    }
  }

  void _onTextPal() {
    Navigator.of(context).pushNamed(
      '/pals_parables',
      arguments: {'textOnly': true},
    );
  }

  // --------------- voice-first STT flow ---------------

  Future<void> _handlePalTap() async {
    // Stop current playback if active
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    if (playerNotifier.isPlaying || playerNotifier.isPaused) {
      await playerNotifier.stop();
    }

    // Create STT service if needed
    _sttService ??= SttService();

    setState(() {
      _isVoiceActive = true;
      _partialTranscript = '';
    });

    final permResult = await _sttService!.checkPermissions();
    if (!mounted) return;

    switch (permResult) {
      case SttPermissionResult.granted:
        _startListening();

      case SttPermissionResult.denied:
        setState(() => _isVoiceActive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Voice input isn't available \u2014 tap Text PAL"),
            duration: Duration(seconds: 3),
          ),
        );

      case SttPermissionResult.permanentlyDenied:
        setState(() => _isVoiceActive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text("Voice input isn't available \u2014 tap Text PAL"),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
    }
  }

  Future<void> _startListening() async {
    final completer = Completer<void>();

    await _sttService!.startListening(
      onResult: (result) {
        if (!mounted) return;
        if (result.isFinal) {
          final transcript = result.text;
          if (transcript.isEmpty) {
            setState(() {
              _isVoiceActive = false;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text("I didn't catch that. Try again or tap Text PAL."),
                duration: Duration(seconds: 3),
              ),
            );
            logEvent('voice_input_cancelled', {'reason': 'timeout'});
          } else {
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count': transcript.split(RegExp(r'\s+')).length,
            });
            _processVoiceMood(transcript);
          }
          if (!completer.isCompleted) completer.complete();
        } else {
          setState(() => _partialTranscript = result.text);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isVoiceActive = false;
          _partialTranscript = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Voice input isn't available \u2014 tap Text PAL"),
            duration: Duration(seconds: 3),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'stt_error'});
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Timeout fallback: use partial transcript if available
    unawaited(
      Future.delayed(
              const Duration(seconds: SttService.defaultListenSeconds + 1))
          .then((_) {
        if (!completer.isCompleted) {
          if (_partialTranscript.isNotEmpty && mounted) {
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count': _partialTranscript.split(RegExp(r'\s+')).length,
            });
            _processVoiceMood(_partialTranscript);
          } else if (mounted) {
            setState(() {
              _isVoiceActive = false;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text("I didn't catch that. Try again or tap Text PAL."),
                duration: Duration(seconds: 3),
              ),
            );
            logEvent('voice_input_cancelled', {'reason': 'timeout'});
          }
          completer.complete();
        }
      }),
    );
  }

  Future<void> _processVoiceMood(String transcript) async {
    // Detect mood (skip compassionate reply in voice-first flow)
    final appNotifier = ref.read(appStateProvider.notifier);
    final moodResult = appNotifier.moodService.detectMood(transcript);

    logEvent('mood_detected', {
      'mood': moodResult.mood,
      'confidence': moodResult.confidenceScore,
      'input_method': 'voice',
    });

    // Select parable based on mood + current length bucket
    final parable = await appNotifier.selectParable(
      mood: moodResult.mood,
      lengthBucket: _selectedBucket,
      userText: transcript,
    );

    if (!mounted) return;

    if (parable == null) {
      setState(() {
        _isVoiceActive = false;
        _partialTranscript = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No story found for that mood. Try again.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Load parable into player
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    await playerNotifier.loadParable(parable);

    // Add to history
    await appNotifier.addToHistory(parable);

    // Voice flow complete — panel transitions to NOW PLAYING via _deriveMode
    setState(() {
      _isVoiceActive = false;
      _partialTranscript = '';
    });

    // Auto-play
    await _handlePlay(playerNotifier);
  }

  void _cancelListening() {
    _sttService?.cancel();
    setState(() {
      _isVoiceActive = false;
      _partialTranscript = '';
    });
    logEvent('voice_input_cancelled', {'reason': 'user_cancelled'});
  }

  // --------------- build ---------------

  @override
  Widget build(BuildContext context) {
    // React to PAL button taps from the hero button widget
    ref.listen<int>(_palTapProvider, (prev, next) {
      if (prev != next) _handlePalTap();
    });

    final playerState = ref.watch(parablePlayerProvider);
    final mode = _deriveMode(playerState);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 280),
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
      case _PanelMode.listening:
        return _buildListeningPanel(theme);
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
        StoryLengthRadioSelector(
          selectedBucket: _selectedBucket,
          onBucketChanged: (b) => setState(() => _selectedBucket = b),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _onReadTodaysStory,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: const Text("Read Today's Story"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _onTextPal,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: AppTheme.lightBlue, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Text PAL',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.deepCharcoal,
                  ),
                ),
                Text(
                  '(No audio)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.deepCharcoal.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --------------- LISTENING ---------------

  Widget _buildListeningPanel(ThemeData theme) {
    return Column(
      key: const ValueKey('listening'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Icon(
          Icons.mic,
          size: 56,
          color: Colors.red.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          'Listening...',
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppTheme.deepCharcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_partialTranscript.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _partialTranscript,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.deepCharcoal.withOpacity(0.7),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: _cancelListening,
          child: Text(
            'Cancel',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.deepCharcoal.withOpacity(0.6),
            ),
          ),
        ),
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
            final value =
                position.inMilliseconds.toDouble().clamp(0.0, max);

            return Column(
              children: [
                Slider(
                  value: value,
                  max: max > 0 ? max : 1,
                  onChanged: (v) =>
                      notifier.seek(Duration(milliseconds: v.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position),
                          style: theme.textTheme.bodySmall),
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
    return Column(
      key: const ValueKey('finished'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reflection — inline expand/collapse, NO navigation
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () =>
                setState(() => _reflectionExpanded = !_reflectionExpanded),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: const Text('Reflection'),
          ),
        ),
        if (_reflectionExpanded) _buildInlineReflection(state, theme),
        const SizedBox(height: 12),

        // Save to Favorites — direct action (unchanged)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _saveFavorite(state.currentParable!),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppTheme.lightBlue, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save to Favorites'),
          ),
        ),
        const SizedBox(height: 12),

        // Share with a PAL — dialog, NO navigation
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _shareWithPals(state.currentParable!),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppTheme.lightBlue, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Share with a PAL'),
          ),
        ),
      ],
    );
  }

  // --------------- inline reflection ---------------

  Widget _buildInlineReflection(ParablePlayerState state, ThemeData theme) {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return const SizedBox.shrink();

    if (!appState.userPreferences.showEverydayReflections) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Reflections are disabled in Settings.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final isKidMode = appState.userPreferences.kidFriendlyOnly;
    final reflection = _reflectionService.getReflectionForParable(
      parable: state.currentParable!,
      isKidMode: isKidMode,
    );

    if (reflection == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No reflection available for this story.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reflection.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            if (reflection.question != null && !isKidMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.help_outline,
                        size: 16,
                        color: theme.colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reflection.question!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------- share (dialog, no navigation) ---------------

  Future<void> _shareWithPals(Parable parable) async {
    final appStateAsync = ref.read(appStateProvider);
    final pals = appStateAsync.valueOrNull?.pals ?? [];

    if (!mounted) return;

    final selectedPalIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectPalsDialog(pals: pals),
    );

    if (selectedPalIds == null || selectedPalIds.isEmpty) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);

    for (final palId in selectedPalIds) {
      final shareId = const Uuid().v4();
      final share = ShareRecord(
        shareId: shareId,
        storyId: parable.storyId,
        storyTitle: parable.title,
        toPalId: palId,
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );
      await appStateNotifier.shareStoryWithPal(share);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedPalIds.length == 1
              ? 'Shared with 1 PAL'
              : 'Shared with ${selectedPalIds.length} PALs',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

