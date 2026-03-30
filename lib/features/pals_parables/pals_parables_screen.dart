import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bible_pal/services/pal_prompt_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/providers/service_providers.dart'
    show nameAudioServiceProvider, palAudioServiceProvider, sessionLengthBucketProvider;
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/services/stt_service.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/widgets/greeting_display.dart';
import 'package:bible_pal/widgets/pal_length_picker.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/theme/app_theme.dart';
import 'package:bible_pal/widgets/starfield_background.dart';

/// Voice input states for the PAL Voice Mood Input flow (Feature 2.2).
///
/// See SPEC.md Feature 2.2 for state machine transitions.
enum VoiceInputState {
  /// Default state. TextField + mic button visible.
  idle,

  /// System permission dialog is showing.
  awaitingPermission,

  /// Microphone active, STT processing. Partial transcript shown as preview.
  listening,

  /// Final transcript inserted into TextField. User can edit/re-record.
  confirming,

  /// Mood detected, proceeding with micro-response + verse + auto-story start.
  proceeding,
}

/// PAL's Parables Screen
/// Based on SPEC.md Features 2, 2.1, 2.2, 3, 4, 5, 14, 16
/// Complete flow: prompt → mood input (button, type, or voice) → micro-response + verse → auto-transition to parable playback
class PalsParablesScreen extends ConsumerStatefulWidget {
  const PalsParablesScreen({super.key, this.sttService, this.textOnly = false, this.navigateToReader = false, this.initialText});

  /// Optional STT service for dependency injection (testing).
  final SttService? sttService;

  /// When true, all PAL audio is suppressed (greeting + micro-response) and
  /// voice/mic input is hidden. Story audio playback is NOT affected.
  final bool textOnly;

  /// When true, navigate to story reader after selection; otherwise parable player.
  final bool navigateToReader;

  /// Pre-filled mood text from the main menu. When set, auto-submits on load.
  final String? initialText;

  @override
  ConsumerState<PalsParablesScreen> createState() => _PalsParablesScreenState();
}

class _PalsParablesScreenState extends ConsumerState<PalsParablesScreen> {
  final TextEditingController _moodController = TextEditingController();
  final PalPromptService _promptService = PalPromptService();
  final VerseService _verseService = VerseService();
  final Random _random = Random();

  late final SttService _sttService;

  String? _promptText;
  String? _promptTimeWindow;
  String? _microResponseText;
  MoodResult? _moodResult;
  VerseResponse? _verse;
  bool _isSelectingParable = false;

  // Voice input state (Feature 2.2)
  VoiceInputState _voiceState = VoiceInputState.idle;
  String _partialTranscript = '';
  bool _sttAvailable = false;

  // Auto-start timer (cancellable)
  Timer? _autoStartTimer;

  // Rotating hint text
  Timer? _hintRotationTimer;
  int _currentHintIndex = 0;
  double _hintOpacity = 1.0;

  static const _morningHints = [
    'Tell me how you\u2019re feeling\u2026',
    'What\u2019s on your heart today?',
    'How are you starting your day?',
    'What\u2019s ahead for you today?',
    'What are you grateful for today?',
    'How\u2019s your spirit doing?',
  ];

  static const _eveningHints = [
    'Tell me how you\u2019re feeling\u2026',
    'What\u2019s on your heart tonight?',
    'How did your day go?',
    'What\u2019s on your mind tonight?',
    'What\u2019s weighing on you?',
    'Anything you need to lay down today?',
  ];

  List<String> get _hints {
    final hour = DateTime.now().hour;
    return hour < 17 ? _morningHints : _eveningHints;
  }

  // Micro-response ring buffer (session-only, per mood)
  final Map<String, List<String>> _recentMicroResponseIds = {};

  @override
  void initState() {
    super.initState();
    _sttService = widget.sttService ?? SttService();

    // Log screen view
    logEvent('screen_view', {'screen_name': 'pals_parables'});

    // Load prompt and play audio
    _loadAndPlayPrompt();

    // Initialize STT engine (non-blocking) to check availability
    if (!widget.textOnly) {
      _initStt();
    }

    // Start rotating hint text
    _currentHintIndex = _random.nextInt(_hints.length);
    _startHintRotation();

    // Auto-submit pre-filled text from main menu
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _moodController.text = widget.initialText!;
      // Delay to let the widget tree settle before processing
      Future.microtask(() {
        if (mounted) _handleMoodSubmission();
      });
    }
  }

  Future<void> _loadAndPlayPrompt() async {
    try {
      final prompt = await _promptService.getPrompt();
      if (mounted) {
        setState(() {
          _promptText = prompt.text;
          _promptTimeWindow = prompt.timeWindow;
        });
      }

      // Play PAL prompt audio (skip in text-only mode)
      if (!widget.textOnly) {
        _playPalPrompt(prompt);
      }
    } catch (e) {
      debugPrint('[PalsParables] Failed to load prompt: $e');
      if (mounted) {
        setState(() {
          _promptText = 'How are you doing today?';
          _promptTimeWindow = 'morning';
        });
      }
    }
  }

  Future<void> _playPalPrompt(PalPrompt prompt) async {
    final appState = ref.read(appStateProvider).valueOrNull;
    // Skip audio if PAL greetings are disabled — text still displays
    if (appState?.userPreferences.palGreetingsEnabled == false) return;

    final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
    final userName = appState?.userPreferences.userName ?? '';
    final palAudio = ref.read(palAudioServiceProvider);
    final nameAudio = ref.read(nameAudioServiceProvider);

    // Try to get a cached name clip for personalized prompt
    final nameClip = userName.isNotEmpty
        ? await nameAudio.getRandomNameClip(userName, voiceKey)
        : null;

    // If name is set but no clip cached, fire-and-forget generation for next time
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

      // Log telemetry
      logEvent('pal_line_played', {
        'line_id': prompt.id,
        'type': 'prompt',
        'time_window': prompt.timeWindow,
        'voice_key': voiceKey,
        'name_prefix_used': text != prompt.text,
      });

      if (mounted && text.isNotEmpty) {
        setState(() => _promptText = text);
      }
    } catch (e) {
      debugPrint('[PalsParables] PAL prompt audio failed: $e');
    }
  }

  Future<void> _initStt() async {
    final available = await _sttService.initialize();
    if (mounted) {
      setState(() => _sttAvailable = available);
    }
  }

  void _startHintRotation() {
    _hintRotationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      // Fade out
      setState(() => _hintOpacity = 0.0);
      // After fade-out, swap text and fade in
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _currentHintIndex = (_currentHintIndex + 1) % _hints.length;
          _hintOpacity = 1.0;
        });
      });
    });
  }

  @override
  void dispose() {
    _hintRotationTimer?.cancel();
    _autoStartTimer?.cancel();
    _moodController.dispose();
    _sttService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Mood button handler
  // ---------------------------------------------------------------------------

  /// Handle mood button tap. Bypasses detectMood() — directly sets mood.
  Future<void> _handleMoodButtonTap(String mood) async {
    if (_microResponseText != null) return; // Already proceeded

    // Show thinking state
    setState(() => _voiceState = VoiceInputState.proceeding);

    // Brief thinking delay (800-1500ms randomized) to feel human
    final delay = 800 + _random.nextInt(701); // 800..1500
    await Future.delayed(Duration(milliseconds: delay));

    if (!mounted) return;

    // Create mood result directly (no keyword detection needed)
    final moodResult = MoodResult(
      mood: mood,
      emotionalTags: [mood],
      confidenceScore: 1.0,
    );

    await _processMoodResult(moodResult, userText: '');
  }

  // ---------------------------------------------------------------------------
  // Voice input methods (Feature 2.2)
  // ---------------------------------------------------------------------------

  /// Handle mic button tap. Transitions through the state machine:
  /// idle → awaitingPermission → listening → confirming
  Future<void> _onMicTap() async {
    if (_voiceState != VoiceInputState.idle) return;

    // Auto-stop prompt audio if still playing (SPEC 2.2)
    ref.read(palAudioServiceProvider).stop();

    // Check if STT is available
    if (!_sttAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input not available on this platform'),
            duration: Duration(seconds: 3),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'stt_unavailable'});
      }
      return;
    }

    // Check permissions
    setState(() => _voiceState = VoiceInputState.awaitingPermission);

    final permResult = await _sttService.checkPermissions();

    if (!mounted) return;

    switch (permResult) {
      case SttPermissionResult.granted:
        _startListening();

      case SttPermissionResult.denied:
        setState(() => _voiceState = VoiceInputState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for voice input'),
            duration: Duration(seconds: 3),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'permission_denied'});

      case SttPermissionResult.permanentlyDenied:
        setState(() => _voiceState = VoiceInputState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Microphone permission denied. Enable it in Settings.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'permission_denied'});
    }
  }

  /// Start STT listening. Transitions: awaitingPermission → listening.
  Future<void> _startListening() async {
    setState(() {
      _voiceState = VoiceInputState.listening;
      _partialTranscript = '';
    });

    final completer = Completer<void>();

    await _sttService.startListening(
      onResult: (result) {
        if (!mounted) return;
        if (result.isFinal) {
          final transcript = result.text;
          if (transcript.isEmpty) {
            setState(() {
              _voiceState = VoiceInputState.idle;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try again or type your response."),
                duration: Duration(seconds: 3),
              ),
            );
            logEvent('voice_input_cancelled', {'reason': 'timeout'});
          } else {
            _moodController.text = transcript;
            setState(() {
              _voiceState = VoiceInputState.confirming;
              _partialTranscript = '';
            });
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count': transcript.split(RegExp(r'\s+')).length,
            });
          }
          if (!completer.isCompleted) completer.complete();
        } else {
          setState(() => _partialTranscript = result.text);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _voiceState = VoiceInputState.idle;
          _partialTranscript = '';
        });
        logEvent('voice_input_cancelled', {'reason': 'stt_unavailable'});
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Timeout fallback
    unawaited(
      Future.delayed(const Duration(seconds: SttService.defaultListenSeconds + 1))
          .then((_) {
        if (!completer.isCompleted) {
          if (_partialTranscript.isNotEmpty && mounted) {
            _moodController.text = _partialTranscript;
            setState(() {
              _voiceState = VoiceInputState.confirming;
              _partialTranscript = '';
            });
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count':
                  _moodController.text.split(RegExp(r'\s+')).length,
            });
          } else if (mounted) {
            setState(() {
              _voiceState = VoiceInputState.idle;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try again or type your response."),
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

  /// Cancel voice input and return to idle.
  Future<void> _cancelVoiceInput() async {
    await _sttService.stopListening();
    if (mounted) {
      setState(() {
        _voiceState = VoiceInputState.idle;
        _partialTranscript = '';
      });
      logEvent('voice_input_cancelled', {'reason': 'user_cancel'});
    }
  }

  /// Re-record: go back to listening from confirming state.
  Future<void> _reRecord() async {
    _moodController.clear();
    _startListening();
  }

  // ---------------------------------------------------------------------------
  // Mood submission (shared by typed and voice input — Invariant 17)
  // ---------------------------------------------------------------------------

  /// Handle mood detection from text input.
  Future<void> _handleMoodSubmission() async {
    if (_moodController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please share how you\'re doing')),
      );
      return;
    }

    final appNotifier = ref.read(appStateProvider.notifier);
    final moodService = appNotifier.moodService;
    final result = moodService.detectMood(_moodController.text);

    await _processMoodResult(result, userText: _moodController.text);
  }

  /// Process a mood result (from button, text, or voice) and continue the flow.
  Future<void> _processMoodResult(MoodResult result, {required String userText}) async {
    final verse = _verseService.getVerseForMood(result.mood);

    // Persist mood for thematic Daily Bread alignment (SPEC Feature #21)
    final appNotifier = ref.read(appStateProvider.notifier);
    appNotifier.updateLastDetectedMood(result.mood);

    // Select a micro-response from the mood bucket (non-repeat)
    final responseId = _pickMicroResponseId(result.mood);

    // Play PAL micro-response audio and get display text
    final appState = ref.read(appStateProvider).valueOrNull;
    final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_GRACE';
    final userName = appState?.userPreferences.userName ?? '';

    String responseText;
    if (widget.textOnly || appState?.userPreferences.palGreetingsEnabled == false) {
      // Text-only mode or PAL greetings disabled — no audio
      responseText = appNotifier.moodService.getMicroResponseText(result.mood);
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
          timeWindow: _promptTimeWindow,
        );

        // Log telemetry
        logEvent('pal_line_played', {
          'line_id': responseId,
          'type': 'micro_response',
          'time_window': _promptTimeWindow ?? 'unknown',
          'mood': result.mood,
          'voice_key': voiceKey,
          'name_prefix_used': nameClip != null && responseText.contains(nameClip.text),
        });
      } catch (e) {
        debugPrint('[PalsParables] PAL micro-response audio failed: $e');
        responseText = appNotifier.moodService.getMicroResponseText(result.mood);
      }
    }

    if (!mounted) return;

    setState(() {
      _moodResult = result;
      _microResponseText = responseText;
      _verse = verse;
      _voiceState = VoiceInputState.proceeding;
    });

    if (widget.textOnly) {
      // Text-only mode: skip the delay, go straight to story selection
      _autoSelectStory(userText);
    } else {
      // Audio mode: wait for micro-response to finish before selecting
      _startAutoStoryTimer(userText);
    }
  }

  /// Pick a micro-response ID from the mood bucket with non-repeat logic.
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
  // Auto-story start
  // ---------------------------------------------------------------------------

  void _startAutoStoryTimer(String userText) {
    _autoStartTimer?.cancel();
    _autoStartTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _autoSelectStory(userText);
      }
    });
  }

  Future<void> _autoSelectStory(String userText) async {
    if (_moodResult == null) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);
    final userPrefs = ref.read(appStateProvider).requireValue.userPreferences;

    // Determine length bucket: use saved preference or ask via PAL picker
    StoryLengthBucket lengthBucket;
    final savedPref = userPrefs.preferredLengthBucket;

    if (savedPref != null) {
      lengthBucket = StoryLengthBucket.fromJson(savedPref);
    } else {
      if (!mounted) return;
      final picked = await showPalLengthPicker(context);
      if (picked == null || !mounted) return;
      lengthBucket = picked;
      await appStateNotifier.updatePreferredLengthBucket(picked.name);
    }

    ref.read(sessionLengthBucketProvider.notifier).state = lengthBucket;

    logEvent('length_selected', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
    });

    setState(() => _isSelectingParable = true);

    logEvent('pal_tap', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
    });

    try {
      final parable = await appStateNotifier.selectParable(
        mood: _moodResult!.mood,
        lengthBucket: lengthBucket,
        userText: userText,
      );

      if (!mounted) return;

      if (parable == null) {
        setState(() => _isSelectingParable = false);
        if (!mounted) return;
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

      // Store PAL's response and verse in player state for the player screen
      if (_microResponseText != null || _verse != null) {
        playerNotifier.setPalResponse(_microResponseText, _verse);
      }

      if (!mounted) return;
      setState(() => _isSelectingParable = false);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        widget.navigateToReader ? '/story_reader' : '/parable_player',
      );
    } catch (e) {
      setState(() => _isSelectingParable = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading parable: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVoiceActive = _voiceState == VoiceInputState.listening ||
        _voiceState == VoiceInputState.awaitingPermission;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        title: const Text('PAL\'s Stories'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarfieldBackground(),
          ListView(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight + 16, 16, 16),
          children: [
          // Prompt Display
          GreetingDisplay(
            greeting: _promptText ?? '',
            emoji: '',
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Share how you\'re really doing so PAL can choose a story for your heart.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black54),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Mood Input Section (hidden after mood is set)
          if (_microResponseText == null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    // TextField (primary input, positioned first)
                    TextField(
                      controller: _moodController,
                      maxLines: 4,
                      minLines: 3,
                      autofocus: false,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                      enabled: !isVoiceActive,
                      onTap: () {
                        if (_voiceState == VoiceInputState.listening) {
                          _cancelVoiceInput();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: _voiceState == VoiceInputState.confirming
                            ? 'Edit your response or tap Continue'
                            : _hints[_currentHintIndex],
                        hintStyle: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withValues(alpha: _hintOpacity * 0.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.white38),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.white70, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Voice input controls (Feature 2.2)
                    _buildVoiceControls(theme),

                    const SizedBox(height: 12),

                    // Continue button
                    ElevatedButton(
                      onPressed: _microResponseText != null
                          ? null
                          : _handleMoodSubmission,
                      child: const Text('Continue'),
                    ),

                    const SizedBox(height: 20),

                    // Divider with "or" label
                    Row(
                      children: [
                        const Expanded(child: Divider(color: Colors.white54)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Or pick a mood:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              shadows: const [
                                Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                        const Expanded(child: Divider(color: Colors.white54)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick mood buttons
                    _buildMoodButtons(theme),
                  ],
                ),
              ),
          ],

          // Loading indicator while story is being selected
          if (_isSelectingParable) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Preparing your story...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
        ),
        ],
      ),
    );
  }

  /// Build the quick mood button row.
  Widget _buildMoodButtons(ThemeData theme) {
    const moods = [
      ('☀️', 'Joyful',     'joyful',        Color(0xFF7A4F00), Color(0xFFF5A623)),
      ('🙏', 'Grateful',   'grateful',      Color(0xFF3A2A00), Color(0xFFD4A520)),
      ('🌙', 'Weary',      'weary',         Color(0xFF1A2040), Color(0xFF3D5A9A)),
      ('🌊', 'Anxious',    'anxious',       Color(0xFF0A2A2A), Color(0xFF2D8A8A)),
      ('💙', 'Hurting',    'hurting',       Color(0xFF2A1040), Color(0xFF7B4FA0)),
      ('🦁', 'Brave',      'brave_courage', Color(0xFF4A2800), Color(0xFFD07020)),
      ('🕊️', 'Peaceful',   'calm_peaceful', Color(0xFF1A2D4A), Color(0xFF4B7ABE)),
      ('🌟', 'Encouraged', 'encouraging',   Color(0xFF2A3A10), Color(0xFF7AAA30)),
    ];
    final disabled = _voiceState == VoiceInputState.proceeding;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: moods.map((entry) {
        final (emoji, label, moodKey, bgColor, borderColor) = entry;
        return GestureDetector(
          onTap: disabled ? null : () => _handleMoodButtonTap(moodKey),
          child: AnimatedOpacity(
            opacity: disabled ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor.withOpacity(0.7), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: borderColor.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warmIvory,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Build voice input controls: mic button, listening indicator, re-record.
  Widget _buildVoiceControls(ThemeData theme) {
    switch (_voiceState) {
      case VoiceInputState.idle:
        if (widget.textOnly) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'or',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('voice_mic_button'),
              onPressed: _microResponseText != null ? null : _onMicTap,
              icon: const Icon(Icons.mic),
              tooltip: _sttAvailable
                  ? 'Tap to speak'
                  : 'Voice input not available on this platform',
              color: _sttAvailable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        );

      case VoiceInputState.awaitingPermission:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Requesting permission...'),
          ],
        );

      case VoiceInputState.listening:
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic,
                  key: const Key('voice_listening_indicator'),
                  color: theme.colorScheme.error,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Listening...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _cancelVoiceInput,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (_partialTranscript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _partialTranscript,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );

      case VoiceInputState.confirming:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _reRecord,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Re-record'),
            ),
          ],
        );

      case VoiceInputState.proceeding:
        return const SizedBox.shrink();
    }
  }
}
