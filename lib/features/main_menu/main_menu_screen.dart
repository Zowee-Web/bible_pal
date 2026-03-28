import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import '../../services/typewriter_click_service.dart';
import '../../services/pal_prompt_service.dart';
import '../../services/mood_service.dart';
import '../../services/verse_service.dart';
import '../../services/stt_service.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../onboarding/first_launch_screen.dart' show kPalIntroShownKey;
import '../settings/settings_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HapticFeedback;
import '../../providers/parable_player_notifier.dart';
import '../../core/story_length_bucket.dart';
import '../../models/parable.dart';
import '../../widgets/pal_length_picker.dart';
import '../consent/voice_consent_dialog.dart';
import '../../core/app_logger.dart';
import '../../widgets/starfield_background.dart';

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
        final isKidMode = appState.userPreferences.kidFriendlyOnly;
        final effectiveTheme = isKidMode ? AppTheme.kidsTheme : theme;

        return Theme(
          data: effectiveTheme,
          child: Scaffold(
          backgroundColor: AppTheme.parchment,
          body: Stack(
            children: [
              const StarfieldBackground(),
              SafeArea(
                bottom: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                    // Settings icon — top right
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4, top: 4),
                        child: IconButton(
                          icon: Icon(
                            Icons.settings_outlined,
                            color: AppTheme.warmIvory.withOpacity(0.45),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // PAL orb — hero of the screen
                    _PalButtonWithIntro(theme: theme),

                    const SizedBox(height: 8),

                    // Listening streak (quiet, non-gamified)
                    Builder(builder: (context) {
                      final streak = ref.watch(appStateProvider).valueOrNull?.userPreferences.currentStreak ?? 0;
                      if (streak < 2) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '$streak day streak',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.warmGold,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Reserved panel: playing/finished states, mood buttons when idle
                    const _ReservedPanel(),

                    const SizedBox(height: 16),

                    // Text PAL + Read Story — just above Daily Bread
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pushNamed('/pals_parables', arguments: {'textOnly': true}),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                foregroundColor: AppTheme.warmIvory,
                                backgroundColor: AppTheme.glassCard.withOpacity(0.5),
                                side: const BorderSide(color: AppTheme.glassBorder, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline, size: 15, color: AppTheme.celestialBlue),
                              label: const Text('Text PAL'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final ps = ref.read(parablePlayerProvider);
                                if (ps.currentParable != null) {
                                  Navigator.of(context).pushNamed('/story_reader');
                                } else {
                                  Navigator.of(context).pushNamed('/pals_parables', arguments: {'textOnly': true, 'navigateToReader': true});
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                foregroundColor: AppTheme.warmIvory,
                                backgroundColor: AppTheme.glassCard.withOpacity(0.5),
                                side: const BorderSide(color: AppTheme.glassBorder, width: 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.menu_book_outlined, size: 15, color: AppTheme.celestialBlue),
                              label: const Text('Read Story'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Daily Bread card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.glassCard.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.glassBorder, width: 1),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '✦  Daily Bread  ✦',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.warmGold.withOpacity(0.8),
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dailyBread.replaceAll('"', '').replaceAll('\u201C', '').replaceAll('\u201D', ''),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: AppTheme.warmIvory,
                                height: 1.55,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '— $verseReference',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.warmGold,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Bottom nav row — Favorites / History / My PALs
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        children: [
                          Expanded(child: _GlassNavButton(
                            icon: Icons.favorite_outline,
                            label: 'Favorites',
                            onTap: () => Navigator.of(context).pushNamed('/favorites'),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _GlassNavButton(
                            icon: Icons.history_outlined,
                            label: 'History',
                            onTap: () => Navigator.of(context).pushNamed('/history'),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _GlassNavButton(
                            icon: Icons.people_outline,
                            label: 'My PALs',
                            onTap: () => Navigator.of(context).pushNamed('/my_pals'),
                          )),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        );
      },
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
  String _displayedText = '';
  int _charIndex = 0;
  int _currentLine = 0;
  Timer? _typingTimer;
  final _clickHelper = TypewriterClickHelper();

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
  MoodResult? _moodResult;
  VerseResponse? _moodVerse;
  Timer? _autoStoryTimer;

  // Services for voice flow
  final PalPromptService _promptService = PalPromptService();
  final SttService _sttService = SttService();
  final Random _random = Random();

  // Micro-response ring buffer (session-only, per mood)
  final Map<String, List<String>> _recentMicroResponseIds = {};

  // Mic pulse animation
  late final AnimationController _micPulseController;

  // Guard against double-navigation race
  bool _navigatingToPlayer = false;

  // Holds transcript while user is choosing story length
  String _pendingTranscript = '';

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

    _micPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _checkIntroState();
    _initStt();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _autoStoryTimer?.cancel();
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
    setState(() {
      _introChecked = true;
      _showIntro = !alreadyShown;
    });
    if (_showIntro) {
      await _clickHelper.preInitialize();
      if (!mounted) return;
      _startTypingLine();
    }
  }

  void _startTypingLine() {
    if (_currentLine >= _introLines.length) {
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
        final nextChar = line[_charIndex];
        _clickHelper.onCharAppended(nextChar);
        setState(() {
          _charIndex++;
          _displayedText = line.substring(0, _charIndex);
        });
      } else {
        timer.cancel();
        if (_currentLine == _introLines.length - 1) {
          _startPulse();
        } else {
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
    _clickHelper.enabled = false;
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

    _clickHelper.enabled = false;
    _typingTimer?.cancel();
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
    _navigatingToPlayer = false;
    setState(() {
      _voiceFlow = _VoiceFlowState.inactive;
      _greetingText = null;
      _microResponseText = null;
      _partialTranscript = '';
      _pendingTranscript = '';
      _finalTranscript = null;
      _moodResult = null;
      _moodVerse = null;
    });
  }

  /// Start the full voice conversation: greeting → listen → respond → story.
  Future<void> _startConversation() async {
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

    // Fetch verse for this mood
    final verseService = VerseService();
    final verse = verseService.getVerseForMood(result.mood);

    setState(() {
      _voiceFlow = _VoiceFlowState.responding;
      _moodResult = result;
      _moodVerse = verse;
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

    setState(() {
      _microResponseText = responseText;
      _pendingTranscript = transcript;
      _voiceFlow = _VoiceFlowState.choosingLength;
    });
  }

  /// Called when the user taps a length pill — sets bucket and starts story.
  void _onLengthChosen(StoryLengthBucket bucket) {
    ref.read(sessionLengthBucketProvider.notifier).state = bucket;
    _selectAndPlayStory(_pendingTranscript);
  }

  /// Select a story and navigate to the player.
  Future<void> _selectAndPlayStory(String userText) async {
    if (_moodResult == null || _navigatingToPlayer) return;
    _navigatingToPlayer = true;

    setState(() => _voiceFlow = _VoiceFlowState.selectingStory);

    final lengthBucket = ref.read(sessionLengthBucketProvider);

    logEvent('pal_tap', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
      'input_method': 'voice_main_menu',
    });

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final parable = await appStateNotifier.selectParable(
        mood: _moodResult!.mood,
        lengthBucket: lengthBucket,
        userText: userText,
      );

      if (!mounted) return;

      if (parable == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No story available for this mood and length yet.'),
            duration: Duration(seconds: 3),
          ),
        );
        _cancelConversation();
        return;
      }

      await appStateNotifier.addToHistory(parable);

      if (!mounted) return;
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);

      // Store PAL's response and verse for display on the player screen
      playerNotifier.setPalResponse(_microResponseText, _moodVerse);

      if (!mounted) return;

      // Reset voice flow state before navigating
      setState(() {
        _voiceFlow = _VoiceFlowState.inactive;
        _greetingText = null;
        _microResponseText = null;
        _finalTranscript = null;
        _moodResult = null;
        _moodVerse = null;
      });

      Navigator.of(context).pushNamed('/parable_player');
      _navigatingToPlayer = false;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading story: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
      _cancelConversation();
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
        return 'Tap for a mood‑based story';
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

          // Voice flow status (above PAL button)
          if (_voiceFlow != _VoiceFlowState.inactive) ...[
            _buildVoiceFlowOverlay(theme),
            const SizedBox(height: 12),
          ],

          // PAL Orb — circular glowing celestial button
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _pulseAnimation,
                child: AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final tapGlow =
                        Curves.easeInOut.transform(1.0 - _glowController.value) * 0.6;
                    return Container(
                      width: 224,
                      height: 224,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.3, -0.4),
                          radius: 1.1,
                          colors: [
                            Color(0xFF4A86C8), // bright celestial centre
                            Color(0xFF1E4A80), // mid blue
                            Color(0xFF0D1E3A), // deep navy edge
                          ],
                          stops: [0.0, 0.55, 1.0],
                        ),
                        border: Border.all(
                          color: AppTheme.warmGold.withOpacity(0.7),
                          width: 1.5,
                        ),
                        boxShadow: [
                          // Ambient celestial glow
                          BoxShadow(
                            color: AppTheme.celestialBlue.withOpacity(0.35),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                          // Outer ring
                          BoxShadow(
                            color: AppTheme.celestialBlue.withOpacity(0.15),
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
              const SizedBox(height: 10),
              // Subtitle below the orb
              Text(
                _palSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.warmIvory.withOpacity(0.6),
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),

          // Length pills — appear below the orb when choosing
          if (_voiceFlow == _VoiceFlowState.choosingLength) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LengthPill(label: 'Short', onTap: () => _onLengthChosen(StoryLengthBucket.short)),
                const SizedBox(width: 10),
                _LengthPill(label: 'Full', onTap: () => _onLengthChosen(StoryLengthBucket.full)),
                const SizedBox(width: 10),
                _LengthPill(label: 'Long', onTap: () => _onLengthChosen(StoryLengthBucket.long)),
              ],
            ),
          ],

          // Cancel button during voice flow
          if (_voiceFlow != _VoiceFlowState.inactive) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelConversation,
              child: Text(
                'Cancel',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.deepCharcoal.withOpacity(0.6),
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
    switch (_voiceFlow) {
      case _VoiceFlowState.inactive:
        return const SizedBox.shrink();

      case _VoiceFlowState.playingGreeting:
        return Text(
          _greetingText ?? '...',
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppTheme.deepCharcoal,
            fontStyle: FontStyle.italic,
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
                  color: AppTheme.deepCharcoal.withOpacity(0.5),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            if (_partialTranscript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _partialTranscript,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.deepCharcoal,
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
                  color: AppTheme.deepCharcoal.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            if (_microResponseText != null) ...[
              const SizedBox(height: 6),
              Text(
                _microResponseText!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.deepCharcoal,
                  fontStyle: FontStyle.italic,
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
            color: AppTheme.warmIvory.withOpacity(0.7),
            fontStyle: FontStyle.italic,
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
                  color: AppTheme.deepCharcoal.withOpacity(0.6),
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
                color: AppTheme.deepCharcoal,
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

  bool _isSelectingFromMood = false;

  Future<void> _handleMoodButtonTap(String mood) async {
    if (_isSelectingFromMood) return;
    setState(() => _isSelectingFromMood = true);

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final userPrefs = ref.read(appStateProvider).requireValue.userPreferences;
      appStateNotifier.updateLastDetectedMood(mood);

      // Determine length bucket: use saved preference or ask via PAL picker
      StoryLengthBucket lengthBucket;
      final savedPref = userPrefs.preferredLengthBucket;

      if (savedPref != null) {
        // User has a saved preference — use it directly
        lengthBucket = StoryLengthBucket.fromJson(savedPref);
      } else {
        // First time — show PAL length picker
        if (!mounted) return;
        final picked = await showPalLengthPicker(context);

        if (picked == null || !mounted) {
          setState(() => _isSelectingFromMood = false);
          return;
        }

        lengthBucket = picked;
        // Save their choice for next time
        await appStateNotifier.updatePreferredLengthBucket(picked.name);
      }

      // Update session provider to stay in sync
      ref.read(sessionLengthBucketProvider.notifier).state = lengthBucket;

      logEvent('pal_tap', {
        'length_bucket': lengthBucket.name,
        'detected_mood': mood,
        'input_method': 'mood_button_main_menu',
      });

      final parable = await appStateNotifier.selectParable(
        mood: mood,
        lengthBucket: lengthBucket,
        userText: '',
      );

      if (!mounted) return;

      if (parable == null) {
        setState(() => _isSelectingFromMood = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No story available for this mood and length yet.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      await appStateNotifier.addToHistory(parable);

      if (!mounted) return;
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);

      if (!mounted) return;
      setState(() => _isSelectingFromMood = false);

      Navigator.of(context).pushNamed('/parable_player');
    } catch (e) {
      setState(() => _isSelectingFromMood = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading story: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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

    // "Listen Again" suggestion — show when user has favorites
    final favorites = ref.watch(appStateProvider).valueOrNull?.favorites ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (favorites.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextButton.icon(
              onPressed: _isSelectingFromMood ? null : () => _playRandomFavorite(favorites),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              icon: Icon(Icons.replay, size: 18, color: theme.colorScheme.primary.withOpacity(0.7)),
              label: Text(
                'Listen to an old favorite',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary.withOpacity(0.7),
                ),
              ),
            ),
          ),
        Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: moods.map((entry) {
        final (label, moodKey) = entry;
        return ElevatedButton(
          onPressed: _isSelectingFromMood
              ? null
              : () => _handleMoodButtonTap(moodKey),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(label),
        );
      }).toList(),
    ),
      ],
    );
  }

  Future<void> _playRandomFavorite(List<dynamic> favorites) async {
    if (_isSelectingFromMood || favorites.isEmpty) return;
    setState(() => _isSelectingFromMood = true);

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final randomFav = favorites[DateTime.now().millisecond % favorites.length];
      final parableService = await ref.read(parableServiceProvider.future);
      final parable = await parableService.getParableById(randomFav.storyId);

      if (parable == null || !mounted) {
        setState(() => _isSelectingFromMood = false);
        return;
      }

      await appStateNotifier.addToHistory(parable);
      if (!mounted) return;

      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);
      if (!mounted) return;

      setState(() => _isSelectingFromMood = false);
      Navigator.of(context).pushNamed('/parable_player');
    } catch (e) {
      setState(() => _isSelectingFromMood = false);
    }
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
    final notifier = ref.read(parablePlayerProvider.notifier);
    return Column(
      key: const ValueKey('finished'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          state.currentParable!.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.warmIvory.withOpacity(0.7),
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
                side: const BorderSide(color: AppTheme.glassBorder, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.favorite_outline, size: 16, color: AppTheme.celestialBlue),
              label: const Text('Save'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await notifier.loadParable(state.currentParable!);
                if (!mounted) return;
                await _handlePlay(notifier);
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                side: const BorderSide(color: AppTheme.glassBorder, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.replay, size: 16, color: AppTheme.celestialBlue),
              label: const Text('Replay'),
            ),
          ],
        ),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Glass nav button — Favorites / History / My PALs
// ---------------------------------------------------------------------------

class _GlassNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.glassCard.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: AppTheme.celestialBlue),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.warmIvory,
                  letterSpacing: 0.3,
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
// Length pill — Short / Full / Long chooser in the PAL voice flow
// ---------------------------------------------------------------------------

class _LengthPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LengthPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.glassCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.celestialBlue.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.celestialBlue.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.warmIvory,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
