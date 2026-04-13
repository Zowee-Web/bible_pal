import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/features/my_pals/select_pals_dialog.dart';
import 'package:bible_pal/features/consent/voice_consent_dialog.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:bible_pal/services/reflection_service.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/models/journal_entry.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/ambient_sound_type.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/scripture_sources_panel.dart';
import '../../widgets/name_prompt_overlay.dart';
import '../../widgets/premium_components.dart';
import '../../theme/living_sky.dart';
import '../paths/next_in_journey_block.dart';

/// Parable Player Screen
/// Based on SPEC.md Features 11, 12, 16, 17, 34-37
/// Displays parable with scripture sources, audio playback, and post-story reflection
class ParablePlayerScreen extends ConsumerStatefulWidget {
  const ParablePlayerScreen({super.key});

  @override
  ConsumerState<ParablePlayerScreen> createState() =>
      _ParablePlayerScreenState();
}

class _ParablePlayerScreenState extends ConsumerState<ParablePlayerScreen> {
  bool _isFavorited = false;
  bool _isDraggingSlider = false;
  double _dragValue = 0;
  bool _showReflection = false;
  final bool _reflectionDismissed = false;
  bool _isReflectionPlaying = false;
  bool _reflectionAudioPlayed = false;
  bool _hasReflectionAudio = false;
  final ReflectionService _reflectionService = ReflectionService();

  // Separate audio player for reflection (to not interfere with story player)
  AudioPlayer? _reflectionPlayer;

  // Scroll controller for auto-scrolling to reflection
  final ScrollController _scrollController = ScrollController();

  // Ambient audio local UI state
  bool _ambientOn = false;
  AmbientSoundType _ambientType = AmbientSoundType.defaultType;
  double _ambientVol = 0.10;

  // Bedtime mode sleep timer
  Timer? _sleepTimer;

  bool get _isBedtimeModeActive {
    final appState = ref.read(appStateProvider).valueOrNull;
    return appState?.userPreferences.bedtimeModeEnabled ?? false;
  }

  bool _completionListenerSet = false;
  bool _showNamePrompt = false;

  @override
  void initState() {
    super.initState();
    _checkIfFavorited();
    _checkReflectionAudioExists();
    _journalFocusNode.addListener(_onJournalFocusChange);
    _loadAmbientState();
  }

  Future<void> _loadAmbientState() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ambientOn = sp.getBool('settings.backgroundSoundOn') ?? false;
      _ambientType = AmbientSoundType.fromString(sp.getString('settings.ambientSoundType'));
      _ambientVol = sp.getDouble('settings.ambientVolume') ?? 0.10;
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _scrollController.dispose();
    _reflectionPlayer?.dispose();
    _journalFocusNode.removeListener(_onJournalFocusChange);
    _journalFocusNode.dispose();
    _journalController.dispose();
    super.dispose();
  }

  /// Check if pre-generated reflection audio exists for current parable
  Future<void> _checkReflectionAudioExists() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final reflectionPath = _getReflectionAudioPath(playerState.currentParable!);
    if (reflectionPath == null) return;

    try {
      // Try to load the asset to check if it exists
      await rootBundle.load('assets/stories/$reflectionPath');
      if (mounted) {
        setState(() => _hasReflectionAudio = true);
      }
    } catch (_) {
      // Asset doesn't exist - reflection audio not available
      if (mounted) {
        setState(() => _hasReflectionAudio = false);
      }
    }
  }

  /// Get reflection audio path from parable metadata or derive from story audio path
  /// Convention: parable_001_joyful_5min.mp3 → parable_001_joyful_5min.reflection.mp3
  String? _getReflectionAudioPath(Parable parable) {
    // Prefer explicit reflection path from manifest
    if (parable.reflectionAudioPath != null) {
      return parable.reflectionAudioPath;
    }
    // Fall back to convention-based derivation
    final storyAudioPath = parable.audioFilePath;
    if (storyAudioPath == null) return null;
    if (!storyAudioPath.endsWith('.mp3')) return null;
    return storyAudioPath.replaceAll('.mp3', '.reflection.mp3');
  }

  void _onPlaybackCompleted() async {
    // Check if we should show the post-first-story name prompt
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      final userName = appState.userPreferences.userName;
      final shouldShow = await NamePromptOverlay.shouldShow(userName);
      if (shouldShow && mounted) {
        setState(() => _showNamePrompt = true);
      }
    }

    if (!_reflectionDismissed) {
      setState(() => _showReflection = true);

      // Auto-scroll to show the reflection
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });

      // Auto-play reflection if voice consent is granted and audio exists
      await _maybeAutoPlayReflection();
    }

    _startBedtimeSleepTimerIfNeeded();
  }

  /// Start sleep timer if bedtime mode is enabled.
  /// After the timer expires, fade out any playing audio and stop.
  void _startBedtimeSleepTimerIfNeeded() {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return;
    if (!appState.userPreferences.bedtimeModeEnabled) return;

    _sleepTimer?.cancel();
    final minutes = appState.userPreferences.sleepTimerMinutes;

    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      if (!mounted) return;
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.audioService.fadeOutAndStop();
      // Also stop reflection audio if playing
      _reflectionPlayer?.stop();
    });
  }

  /// ADR-010: Reflection audio is NEVER auto-played.
  /// User must tap "Hear Reflection" button to play.
  /// This method is intentionally empty - kept for backwards compatibility.
  Future<void> _maybeAutoPlayReflection() async {
    // ADR-010: Reflection is opt-in only. Never auto-play.
    // User must tap "Hear Reflection" button.
    // This method intentionally does nothing.
  }

  /// Play pre-generated reflection audio from local assets
  Future<void> _playReflectionAudio() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final reflectionPath = _getReflectionAudioPath(playerState.currentParable!);
    if (reflectionPath == null) return;

    try {
      // Initialize reflection player if needed
      _reflectionPlayer ??= AudioPlayer();

      // Load from assets
      await _reflectionPlayer!.setAsset('assets/stories/$reflectionPath');

      logEvent('reflection_start', {
        'story_id': playerState.currentParable!.storyId,
      });

      setState(() {
        _isReflectionPlaying = true;
        _reflectionAudioPlayed = true;
      });

      await _reflectionPlayer!.play();

      // Listen for completion
      _reflectionPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() => _isReflectionPlaying = false);
          }
        }
      });
    } catch (e) {
      debugPrint('[ReflectionAudio] Error playing: $e');

      logEvent('reflection_fail', {
        'story_id': playerState.currentParable!.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);

      setState(() {
        _isReflectionPlaying = false;
        _hasReflectionAudio = false; // Mark as unavailable
      });
    }
  }

  /// Stop reflection audio playback
  Future<void> _stopReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.stop();
      setState(() => _isReflectionPlaying = false);
    }
  }

  /// Replay reflection audio
  Future<void> _replayReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.seek(Duration.zero);
      await _reflectionPlayer!.play();
      setState(() => _isReflectionPlaying = true);
    } else {
      await _playReflectionAudio();
    }
  }

  /// Handle play reflection button with consent check
  Future<void> _handlePlayReflection() async {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return;

    final gateResult =
        VoiceConsentGate.checkStoryNarration(appState.userPreferences);

    switch (gateResult) {
      case VoiceGateResult.allowed:
        await _playReflectionAudio();
        break;

      case VoiceGateResult.needsConsent:
        if (!mounted) return;
        final consentResult = await VoiceConsentDialog.show(context);
        if (consentResult == VoiceConsentResult.enabled) {
          await _playReflectionAudio();
        }
        break;

      case VoiceGateResult.blocked:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Voice narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
    }
  }

  Future<void> _checkIfFavorited() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable != null) {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final favorited = await appStateNotifier
          .isFavorited(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() {
          _isFavorited = favorited;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);

    if (_isFavorited) {
      await appStateNotifier
          .removeFavorite(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() => _isFavorited = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await appStateNotifier.addFavorite(playerState.currentParable!);
      if (mounted) {
        setState(() => _isFavorited = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _shareWithPals() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateAsync = ref.read(appStateProvider);
    final pals = appStateAsync.valueOrNull?.pals ?? [];

    if (!mounted) return;

    // Show dialog to select PALs
    final selectedPalIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectPalsDialog(pals: pals),
    );

    if (selectedPalIds == null || selectedPalIds.isEmpty) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);
    final parable = playerState.currentParable!;

    // Share with each selected PAL
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

    // Invoke platform share sheet with story content
    final shareService = ref.read(shareServiceProvider);
    await shareService.shareParable(
      parable: parable,
      storyText: playerState.parableText,
    );

    if (!mounted) return;

    // Show success message
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

  /// Handle play button press with voice consent check.
  /// Shows VoiceConsentDialog if user hasn't consented yet.
  Future<void> _handlePlay(ParablePlayerNotifier playerNotifier) async {
    final result = await playerNotifier.play();

    if (!mounted) return;

    switch (result) {
      case VoicePlayResult.played:
        // Audio started successfully, nothing more to do
        break;

      case VoicePlayResult.needsConsent:
        // Show consent dialog
        final consentResult = await VoiceConsentDialog.show(context);

        if (!mounted) return;

        // If user enabled narration, retry play
        if (consentResult == VoiceConsentResult.enabled) {
          // Re-check consent by playing again
          await playerNotifier.play();
        }
        // If declined or dismissed, stay in text-only mode (no action needed)
        break;

      case VoicePlayResult.disabled:
        // User explicitly disabled narration - show snackbar as gentle reminder
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Story narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;

      case VoicePlayResult.noParable:
        // Should not happen since button is only visible when parable is loaded
        break;

      case VoicePlayResult.error:
        // Error message is set in state, will be displayed by UI
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(parablePlayerProvider);
    final playerNotifier = ref.watch(parablePlayerProvider.notifier);
    final theme = Theme.of(context);
    // Phase 3.2 global contrast pass — resolve the sky palette once at
    // build time so text surfaces below route through the enforced
    // foreground palette (primary/secondary/tertiary + shadows).
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    // Detect playback completion and trigger reflection
    if (!_completionListenerSet) {
      _completionListenerSet = true;
      ref.listenManual(parablePlayerProvider, (prev, next) {
        final wasCompleted = prev?.playbackCompleted ?? false;
        if (!wasCompleted && next.playbackCompleted && mounted) {
          _onPlaybackCompleted();
        }
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // CRITICAL back-nav ordering (Phase 3.2 polish pass):
        // POP the route FIRST, then tear audio + state down AFTER.
        //
        // If we call `clear()` before `pop()`, Riverpod flips
        // `currentParable` to null and the widget rebuilds with
        // its "Tap PAL to start a story" empty state before the
        // pop transition completes. The user briefly sees that
        // empty state and perceives it as a broken back-nav
        // (appearing on a wrong screen). Popping first disposes
        // the widget before Riverpod can trigger the rebuild, so
        // the empty-state flash never paints.
        //
        // The notifier + reflection player live OUTSIDE the
        // widget tree, so calling them after pop is safe — their
        // cleanup just runs in the background while the user is
        // already on the previous route.
        final nav = Navigator.of(context);
        nav.pop();
        // Fire-and-forget cleanup. Reflection player doesn't need
        // setState (_stopReflectionAudio would, so we call stop()
        // directly to skip the setState branch on a disposing widget).
        _reflectionPlayer?.stop();
        // Story audio + ambient + clear parable state — runs on the
        // Riverpod notifier, not the widget.
        await playerNotifier.clear();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
        ),
        body: Stack(
          children: [
            const LivingSkyBackground(),
            SafeArea(
              child: playerState.currentParable == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_stories, size: 48, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          if (playerState.errorMessage != null) ...[
                            Text(
                              playerState.errorMessage!,
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            if (playerState.canRetry)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextButton(
                                  onPressed: () => Navigator.of(context)
                                      .pushNamedAndRemoveUntil(
                                          '/main_menu', (_) => false),
                                  child: const Text('Try Again'),
                                ),
                              ),
                          ] else
                            Text('Tap PAL to start a story', style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/main_menu', (_) => false),
                            child: const Text('Back to PAL'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Scrollable content area
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: Column(
                              children: [
                                // Story title — large, centered.
                                // Phase 3.2 contrast pass: routes
                                // through foreground palette for
                                // phase-aware white + shadow on all
                                // sky phases.
                                Text(
                                  playerState.currentParable!.title,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: palette.foreground.primaryText,
                                    shadows: palette.foreground.textShadow,
                                  ),
                                  textAlign: TextAlign.center,
                                ),

                                // Mood-flow verse (from PAL's mood response)
                                if (playerState.verse != null) ...[
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          '"${playerState.verse!.text}"',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: palette.foreground.primaryText,
                                            shadows: palette.foreground.subtitleShadow,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '— ${playerState.verse!.reference}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: palette.foreground.tertiaryText,
                                            shadows: palette.foreground.captionShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 32),

                                // LARGE Play/Pause Button — glowing orb style
                                GlowingOrbButton(
                                  icon: playerNotifier.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 80,
                                  onPressed: () async {
                                    if (playerNotifier.isPlaying) {
                                      playerNotifier.pause();
                                    } else {
                                      await _handlePlay(playerNotifier);
                                    }
                                  },
                                ),

                                const SizedBox(height: 8),

                                // Seek slider
                                StreamBuilder<Duration>(
                                  stream: playerNotifier.positionStream,
                                  builder: (context, snapshot) {
                                    final position = snapshot.data ?? Duration.zero;
                                    final duration =
                                        playerNotifier.duration ?? Duration.zero;
                                    final max = duration.inMilliseconds.toDouble();
                                    final displayValue = _isDraggingSlider
                                        ? _dragValue
                                        : position.inMilliseconds
                                            .toDouble()
                                            .clamp(0.0, max);

                                    final sliderPalette = LivingSky.getPalette(LivingSky.getPhase());
                                    return Column(
                                      children: [
                                        SliderTheme(
                                          data: SliderThemeData(
                                            activeTrackColor: sliderPalette.orbGlowColor,
                                            inactiveTrackColor: sliderPalette.cardBorder,
                                            thumbColor: sliderPalette.orbGlowColor,
                                            overlayColor: sliderPalette.orbGlowColor.withOpacity(0.2),
                                            trackHeight: 4,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                            trackShape: const RoundedRectSliderTrackShape(),
                                          ),
                                          child: Slider(
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
                                              playerNotifier.seek(
                                                Duration(milliseconds: v.toInt()),
                                              );
                                              setState(() => _isDraggingSlider = false);
                                            },
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatDuration(
                                                  _isDraggingSlider
                                                      ? Duration(milliseconds: _dragValue.toInt())
                                                      : position,
                                                ),
                                                style: TextStyle(
                                                  color: palette.foreground.secondaryText,
                                                  fontSize: 13,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                  shadows: palette.foreground.subtitleShadow,
                                                ),
                                              ),
                                              Text(
                                                _formatDuration(duration),
                                                style: TextStyle(
                                                  color: palette.foreground.secondaryText,
                                                  fontSize: 13,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                  shadows: palette.foreground.subtitleShadow,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                // Download progress (Android-only, R2 audio
                                // delivery — SPEC Feature 27, Cloud Foundation v1).
                                if (playerState.downloadProgress != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: CircularProgressIndicator(
                                            value: playerState.downloadProgress,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Downloading ${(playerState.downloadProgress! * 100).round()}%',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: palette.foreground.secondaryText,
                                            shadows: palette.foreground.subtitleShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (playerState.isLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                if (playerState.errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          playerState.errorMessage!,
                                          style: TextStyle(
                                              color: theme.colorScheme.error),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (playerState.canRetry &&
                                            playerState.currentParable != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: TextButton(
                                              onPressed: () {
                                                playerNotifier.loadParable(
                                                    playerState
                                                        .currentParable!);
                                              },
                                              child: const Text('Try Again'),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                const SizedBox(height: 16),

                                // Scripture Sources panel (SPEC.md Feature 12) — glass capsule
                                GlassCapsule(
                                  padding: const EdgeInsets.all(4),
                                  borderRadius: 16,
                                  child: ScriptureSourcesPanel(
                                    parable: playerState.currentParable!,
                                    playbackCompleted: playerState.playbackCompleted,
                                    onReadScriptureTapped: () {
                                      Navigator.of(context).pushNamed('/scripture_reader');
                                    },
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Action buttons — primary + glass hierarchy
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    // Read Story — glass (same style as siblings)
                                    GlassButton.icon(
                                      icon: Icons.menu_book,
                                      label: 'Read Story',
                                      onPressed: () => Navigator.of(context).pushNamed('/story_reader'),
                                    ),

                                    // Favorite — glass
                                    GlassButton.icon(
                                      icon: _isFavorited ? Icons.favorite : Icons.favorite_border,
                                      label: _isFavorited ? 'Favorited' : 'Favorite',
                                      onPressed: _toggleFavorite,
                                    ),

                                    // Share with a PAL — glass
                                    GlassButton.icon(
                                      icon: Icons.share,
                                      label: 'Share with a PAL',
                                      onPressed: _shareWithPals,
                                    ),

                                    // Share a clip — glass
                                    Builder(builder: (context) {
                                      return GlassButton.icon(
                                        icon: Icons.format_quote,
                                        label: 'Share a clip',
                                        onPressed: () async {
                                          final playerState = ref.read(parablePlayerProvider);
                                          if (playerState.currentParable == null) return;
                                          final box = context.findRenderObject() as RenderBox?;
                                          final origin = box != null
                                              ? box.localToGlobal(Offset.zero) & box.size
                                              : null;
                                          try {
                                            final shareService = ref.read(shareServiceProvider);
                                            await shareService.shareClip(
                                              parable: playerState.currentParable!,
                                              storyText: playerState.parableText,
                                              sharePositionOrigin: origin,
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Unable to share: $e')),
                                            );
                                          }
                                        },
                                      );
                                    }),
                                  ],
                                ),

                                // Ambient Sound Controls
                                _buildAmbientControls(theme),

                                // Post-Story Reflection (SPEC.md Features #34-36)
                                _buildReflectionSection(theme),

                                // Next in Your Journey (SPEC Feature 50.6 —
                                // LOCKED). Rendered ONLY when the current
                                // story was launched with a non-null
                                // PathLaunchContext, playback has completed,
                                // and PathService.getNextInPath() returns a
                                // non-null next story. Path order is sacred:
                                // advancement does NOT skip completed stories.
                                const NextInJourneyBlock(),

                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            // Bedtime mode dim overlay
            if (_isBedtimeModeActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
            // Post-first-story name prompt
            if (_showNamePrompt)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: NamePromptOverlay(
                    onDismiss: () {
                      if (mounted) setState(() => _showNamePrompt = false);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the post-story reflection section
  /// Only shows when:
  /// - Playback has completed
  /// Ambient sound controls — toggle, type selector, volume slider.
  ///
  /// Visual system (SPEC Feature 47 locked palette):
  /// - Container reads as a single subtle glass pane via
  ///   `foreground.subtleSurface` / `subtleBorder`.
  /// - Selected chip: solid `warmHighlight` fill + dark w600 label —
  ///   unmistakable across every phase.
  /// - Unselected chip: same `subtleSurface` family as the container
  ///   but with a slightly stronger border, so inactive chips read as
  ///   "quietly present" rather than washed out.
  /// - Slider and toggle both use `warmHighlight` so the whole block
  ///   feels like one system.
  Widget _buildAmbientControls(ThemeData theme) {
    final ambient = ref.read(ambientAudioServiceProvider);
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fg.subtleSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note, size: 16, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Ambient Sound',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _ambientOn,
                  activeColor: palette.warmHighlight,
                  onChanged: (on) async {
                    final sp = await SharedPreferences.getInstance();
                    await sp.setBool('settings.backgroundSoundOn', on);
                    if (on) {
                      final player = ref.read(parablePlayerProvider.notifier);
                      if (player.isPlaying) {
                        await ambient.forceStart();
                      }
                    } else {
                      await ambient.forceStop();
                    }
                    if (!mounted) return;
                    setState(() => _ambientOn = on);
                  },
                ),
              ),
            ],
          ),
          if (_ambientOn) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AmbientSoundType.values.map((t) {
                final isChipSelected = _ambientType == t;
                return ChoiceChip(
                  label: Text(
                    t.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isChipSelected
                          ? const Color(0xFF1A1A1A)
                          : fg.secondaryText,
                      fontWeight:
                          isChipSelected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  selected: isChipSelected,
                  selectedColor: palette.warmHighlight,
                  backgroundColor: fg.subtleSurface,
                  side: BorderSide(
                    color: isChipSelected
                        ? palette.warmHighlight
                        : fg.subtleBorder,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) async {
                    final sp = await SharedPreferences.getInstance();
                    await sp.setString('settings.ambientSoundType', t.assetName);
                    await ambient.forceStop();
                    setState(() => _ambientType = t);
                    final player = ref.read(parablePlayerProvider.notifier);
                    if (player.isPlaying) {
                      await ambient.forceStart();
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.volume_down, size: 16, color: fg.secondaryIcon),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: palette.warmHighlight,
                      inactiveTrackColor: fg.subtleBorder,
                      thumbColor: palette.warmHighlight,
                      overlayColor: palette.warmHighlight.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _ambientVol.clamp(0.02, 0.25),
                      min: 0.02,
                      max: 0.25,
                      onChanged: (v) async {
                        setState(() => _ambientVol = v);
                        final sp = await SharedPreferences.getInstance();
                        await sp.setDouble('settings.ambientVolume', v);
                        ambient.setVolume(v);
                      },
                    ),
                  ),
                ),
                Icon(Icons.volume_up, size: 16, color: fg.secondaryIcon),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// - User has showEverydayReflections enabled
  /// - Reflection has not been dismissed
  Widget _buildReflectionSection(ThemeData theme) {
    if (!_showReflection || _reflectionDismissed) {
      return const SizedBox.shrink();
    }

    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) {
      return const SizedBox.shrink();
    }

    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) {
      return const SizedBox.shrink();
    }

    // Check if reflections are enabled
    if (!appState.userPreferences.showEverydayReflections) {
      return const SizedBox.shrink();
    }

    final isKidMode = appState.userPreferences.kidFriendlyOnly;
    final reflection = _reflectionService.getReflectionForParable(
      parable: playerState.currentParable!,
      isKidMode: isKidMode,
    );

    if (reflection == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Standalone reflection audio button
        if (_hasReflectionAudio) ...[
          const SizedBox(height: 16),
          _buildReflectionAudioControls(theme),
        ],

        // Standalone journal input (adult only)
        if (!isKidMode) ...[
          const SizedBox(height: 12),
          _buildJournalInput(theme, playerState.currentParable!),
        ],
      ],
    );
  }

  // Journal input state
  final TextEditingController _journalController = TextEditingController();
  final FocusNode _journalFocusNode = FocusNode();
  bool _journalEditing = false;
  bool _journalSaved = false;

  void _onJournalFocusChange() {
    if (!_journalFocusNode.hasFocus && _journalEditing) {
      final parable = ref.read(parablePlayerProvider).currentParable;
      if (parable != null) _saveJournal(parable);
    }
  }

  void _saveJournal(Parable parable) async {
    final text = _journalController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _journalEditing = false);
      return;
    }

    final entry = JournalEntry(
      id: const Uuid().v4(),
      storyId: parable.storyId,
      storyTitle: parable.title,
      mood: parable.mood,
      note: text,
      createdAt: DateTime.now(),
    );

    final storage = await ref.read(storageServiceProvider.future);
    await storage.addJournalEntry(entry);

    if (mounted) {
      setState(() {
        _journalSaved = true;
        _journalEditing = false;
      });
      _journalController.clear();
    }
  }

  Widget _buildJournalInput(ThemeData theme, Parable parable) {
    if (_journalSaved) {
      return Text(
        'Saved to your journal.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: LivingSky.getPalette(LivingSky.getPhase()).foreground.tertiaryText,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (!_journalEditing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassButton.icon(
            icon: Icons.edit_note,
            label: 'Jot a thought',
            onPressed: () {
              setState(() => _journalEditing = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _journalFocusNode.requestFocus();
              });
            },
          ),
        ],
      );
    }

    final palette = LivingSky.getPalette(LivingSky.getPhase());
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: TextField(
        controller: _journalController,
        focusNode: _journalFocusNode,
        maxLength: 200,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _saveJournal(parable),
        cursorColor: palette.foreground.primaryText,
        style: TextStyle(
          color: palette.foreground.primaryText,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Jot a thought...',
          hintStyle: TextStyle(
            color: palette.foreground.tertiaryText,
            fontSize: 14,
          ),
          isDense: true,
          filled: true,
          fillColor: palette.cardColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: palette.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: palette.warmHighlight.withOpacity(0.5), width: 1.5),
          ),
          counterText: '',
        ),
      ),
    );
  }

  /// Build audio control buttons for reflection
  Widget _buildReflectionAudioControls(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Play/Stop/Replay button — glass style
        if (_isReflectionPlaying)
          GlassButton.icon(
            icon: Icons.stop,
            label: 'Stop',
            onPressed: _stopReflectionAudio,
          )
        else if (_reflectionAudioPlayed)
          GlassButton.icon(
            icon: Icons.replay,
            label: 'Replay',
            onPressed: _replayReflectionAudio,
          )
        else
          GlassButton.icon(
            icon: Icons.play_arrow,
            label: 'Hear Reflection', // ADR-010: User taps to hear
            onPressed: _handlePlayReflection,
          ),
      ],
    );
  }

  /// Format duration to MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
