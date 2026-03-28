import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/service_providers.dart';
import '../../core/app_logger.dart';
import '../../core/diagnostics_config.dart';
import '../../core/pal_voice_registry.dart';
import '../../widgets/living_sky_background.dart';

const _pkBackgroundSound = 'settings.backgroundSoundOn';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loaded = false;
  bool _backgroundSoundOn = false;
  bool _kidFriendlyOnly = false;
  bool _showEverydayReflections = true;
  String _storytellingMode =
      'traditional'; // Default is Traditional per Contracts v2
  String _languageStyle = 'WEB'; // Story presentation diction (Contracts v2)
  // Voice consent (Phase 3)
  bool? _storyNarrationEnabled;
  bool? _palGreetingsEnabled;
  // PAL voice selection
  String _palVoiceKey = PalVoiceRegistry.defaultVoiceKey;
  // User name
  String _userName = '';
  // Name audio status
  bool _nameAudioReady = false;
  bool _nameAudioGenerating = false;
  // Bedtime mode
  bool _bedtimeModeEnabled = false;
  int _sleepTimerMinutes = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();

    final backgroundSound = sp.getBool(_pkBackgroundSound);
    if (backgroundSound == null) {
      await sp.setBool(_pkBackgroundSound, false);
      _backgroundSoundOn = false;
    } else {
      _backgroundSoundOn = backgroundSound;
    }

    // Load kid-friendly mode, reflections, storytelling mode, story language, and voice consent from UserPreferences
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      _kidFriendlyOnly = appState.userPreferences.kidFriendlyOnly;
      _showEverydayReflections =
          appState.userPreferences.showEverydayReflections;
      _storytellingMode = appState.userPreferences.storytellingMode;
      _languageStyle = appState.userPreferences.languageStyle;
      // Voice consent (Phase 3)
      _storyNarrationEnabled = appState.userPreferences.storyNarrationEnabled;
      _palGreetingsEnabled = appState.userPreferences.palGreetingsEnabled;
      // PAL voice selection
      _palVoiceKey = appState.userPreferences.palVoiceKey;
      // User name
      _userName = appState.userPreferences.userName;
      // Bedtime mode
      _bedtimeModeEnabled = appState.userPreferences.bedtimeModeEnabled;
      _sleepTimerMinutes = appState.userPreferences.sleepTimerMinutes;
    }

    // Check name audio status
    if (_userName.isNotEmpty) {
      final nameAudio = ref.read(nameAudioServiceProvider);
      _nameAudioReady = await nameAudio.isAvailable(_userName, _palVoiceKey);
    }

    setState(() => _loaded = true);
  }

  Future<void> _setBackgroundSound(bool on) async {
    setState(() => _backgroundSoundOn = on);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_pkBackgroundSound, on);
  }

  Future<void> _setKidFriendlyOnly(bool on) async {
    // Log mode change
    logEvent('mode_changed', {
      'setting': 'kid_friendly',
      'from': _kidFriendlyOnly,
      'to': on,
    });

    setState(() => _kidFriendlyOnly = on);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateKidFriendlyOnly(on);
  }

  Future<void> _setBedtimeMode(bool on) async {
    setState(() => _bedtimeModeEnabled = on);
    final appState = ref.read(appStateProvider.notifier);
    final prefs = ref.read(appStateProvider).requireValue.userPreferences;
    await appState.updateUserPreferences(prefs.copyWith(bedtimeModeEnabled: on));
  }

  Future<void> _setSleepTimer(int minutes) async {
    setState(() => _sleepTimerMinutes = minutes);
    final appState = ref.read(appStateProvider.notifier);
    final prefs = ref.read(appStateProvider).requireValue.userPreferences;
    await appState.updateUserPreferences(prefs.copyWith(sleepTimerMinutes: minutes));
  }

  Future<void> _setShowEverydayReflections(bool on) async {
    setState(() => _showEverydayReflections = on);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateShowEverydayReflections(on);
  }

  Future<void> _setStorytellingMode(String mode) async {
    // Log mode change
    logEvent('mode_changed', {
      'setting': 'storytelling_mode',
      'from': _storytellingMode,
      'to': mode,
    });

    setState(() => _storytellingMode = mode);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateStorytellingMode(mode);
  }

  Future<void> _setLanguageStyle(String style) async {
    // Log language style change (Contracts v2: presentation diction)
    logEvent('language_style_changed', {
      'from': _languageStyle,
      'to': style,
      'kid_mode': _kidFriendlyOnly,
    });

    setState(() => _languageStyle = style);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateLanguageStyle(style);
  }

  Future<void> _setStoryNarrationEnabled(bool enabled) async {
    logEvent('voice_consent_changed', {
      'feature': 'story_narration',
      'from': _storyNarrationEnabled,
      'to': enabled,
    });

    setState(() => _storyNarrationEnabled = enabled);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateStoryNarrationConsent(enabled);
  }

  Future<void> _setPalGreetingsEnabled(bool enabled) async {
    logEvent('voice_consent_changed', {
      'feature': 'pal_greetings',
      'from': _palGreetingsEnabled,
      'to': enabled,
    });

    setState(() => _palGreetingsEnabled = enabled);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updatePalGreetingsConsent(enabled);
  }

  Future<void> _setPalVoiceKey(String voiceKey) async {
    logEvent('pal_voice_changed', {
      'from': _palVoiceKey,
      'to': voiceKey,
    });

    setState(() => _palVoiceKey = voiceKey);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updatePalVoiceKey(voiceKey);

    // Regenerate name audio for the new voice
    final nameAudio = ref.read(nameAudioServiceProvider);
    await nameAudio.invalidateCache();
    if (_userName.isNotEmpty) {
      nameAudio.generateNamePhrases(name: _userName, voiceKey: voiceKey);
    }
  }

  Future<void> _editUserName() async {
    final controller = TextEditingController(text: _userName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Your Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == _userName) return;

    logEvent('user_name_changed', {
      'had_previous': _userName.isNotEmpty,
    });

    setState(() => _userName = result);
    final appNotifier = ref.read(appStateProvider.notifier);
    await appNotifier.updateUserName(result);

    // Generate name audio in background
    final nameAudio = ref.read(nameAudioServiceProvider);
    await nameAudio.invalidateCache();
    nameAudio.generateNamePhrases(name: result, voiceKey: _palVoiceKey);
  }

  Future<void> _regenerateNameAudio() async {
    if (_userName.isEmpty || _nameAudioGenerating) return;
    setState(() => _nameAudioGenerating = true);
    final nameAudio = ref.read(nameAudioServiceProvider);
    await nameAudio.invalidateCache();
    final success = await nameAudio.generateNamePhrases(
      name: _userName,
      voiceKey: _palVoiceKey,
    );
    if (!mounted) return;
    setState(() {
      _nameAudioReady = success;
      _nameAudioGenerating = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Voice greeting generated! PAL will now say your name.'
              : 'Generation failed — check your internet connection and API key in Settings.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _previewVoice() async {
    final palAudio = ref.read(palAudioServiceProvider);
    await palAudio.playPreview(_palVoiceKey);
  }

  Future<void> _resetOnboarding() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Onboarding?'),
        content: const Text(
          'This will restart the onboarding experience. '
          'Your favorites, history, and content preferences will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Reset onboarding state via StorageService (release-safe)
    final storageService = await ref.read(storageServiceProvider.future);
    await storageService.resetFirstLaunchUserFacing();

    if (!mounted) return;

    logEvent('reset_onboarding', {});

    // Navigate to first launch screen, clearing the navigation stack
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/first_launch',
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Your Name'),
            subtitle: Text(_userName.isEmpty ? 'Not set' : _userName),
            trailing: const Icon(Icons.edit),
            onTap: _editUserName,
          ),
          if (_userName.isNotEmpty)
            ListTile(
              leading: Icon(
                _nameAudioReady ? Icons.record_voice_over : Icons.voice_over_off,
                color: _nameAudioReady ? Colors.green : Colors.orange,
              ),
              title: Text(
                _nameAudioReady
                    ? 'Voice greeting ready'
                    : 'Voice greeting not generated',
              ),
              subtitle: Text(
                _nameAudioReady
                    ? 'PAL will say your name when greeting you'
                    : 'Tap to generate so PAL can say your name',
              ),
              trailing: _nameAudioGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _regenerateNameAudio,
                      child: Text(_nameAudioReady ? 'Regenerate' : 'Generate'),
                    ),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Background Sound'),
            subtitle: const Text('Play ambient audio during stories'),
            value: _backgroundSoundOn,
            onChanged: _setBackgroundSound,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Bedtime Mode'),
            subtitle: const Text('Dims the screen, fades audio after stories end'),
            value: _bedtimeModeEnabled,
            onChanged: _setBedtimeMode,
          ),
          if (_bedtimeModeEnabled) ...[
            ListTile(
              title: const Text('Sleep Timer'),
              subtitle: Text('Fade out $_sleepTimerMinutes minutes after story ends'),
              trailing: DropdownButton<int>(
                value: _sleepTimerMinutes,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Immediately')),
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 10, child: Text('10 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                ],
                onChanged: (v) => _setSleepTimer(v ?? 5),
              ),
            ),
          ],
          const Divider(),
          SwitchListTile(
            title: const Text('Kid Friendly'),
            subtitle: const Text('Only show stories appropriate for children'),
            value: _kidFriendlyOnly,
            onChanged: _setKidFriendlyOnly,
          ),
          SwitchListTile(
            title: const Text('Relate stories to everyday life'),
            subtitle: const Text('Show a brief reflection after each story'),
            value: _showEverydayReflections,
            onChanged: _setShowEverydayReflections,
          ),
          const Divider(),
          const ListTile(
            title: Text('Story Mode'),
            subtitle: Text(
                'Choose between creative stories or traditional Bible retellings'),
          ),
          RadioListTile<String>(
            title: const Text('Traditional Stories'),
            subtitle: const Text('Actual Bible stories faithfully retold'),
            value: 'traditional',
            groupValue: _storytellingMode,
            onChanged: (value) => _setStorytellingMode(value!),
          ),
          RadioListTile<String>(
            title: const Text('Creative Stories'),
            subtitle: const Text('Original faith-inspired stories'),
            value: 'creative',
            groupValue: _storytellingMode,
            onChanged: (value) => _setStorytellingMode(value!),
          ),
          const Divider(),
          const ListTile(
            title: Text('Story Language Style'),
            subtitle: Text('Choose the language style for story narration'),
          ),
          RadioListTile<String>(
            title: const Text('Modern (WEB)'),
            subtitle: const Text('Contemporary language style'),
            value: 'WEB',
            groupValue: _languageStyle,
            onChanged: (value) => _setLanguageStyle(value!),
          ),
          RadioListTile<String>(
            title: const Text('Classic (KJV)'),
            subtitle: const Text('Traditional/poetic language style'),
            value: 'KJV',
            groupValue: _languageStyle,
            onChanged: (value) => _setLanguageStyle(value!),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reset Onboarding'),
            subtitle: const Text('Return to PAL\'s introduction'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _resetOnboarding,
          ),
          const Divider(),
          const ListTile(
            title: Text('Voice Features'),
            subtitle: Text('Control audio narration and voice greetings'),
          ),
          SwitchListTile(
            title: const Text('Story Narration'),
            subtitle: const Text('Audio playback of stories'),
            value: _storyNarrationEnabled ?? true,
            onChanged: (value) => _setStoryNarrationEnabled(value),
          ),
          SwitchListTile(
            title: const Text('PAL Greetings'),
            subtitle: const Text('Voice greetings from your PAL'),
            value: _palGreetingsEnabled ?? true,
            onChanged: (value) => _setPalGreetingsEnabled(value),
          ),
          const Divider(),
          ListTile(
            title: const Text("PAL's Voice"),
            subtitle: const Text('Choose a voice for PAL'),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Preview voice',
              onPressed: _previewVoice,
            ),
          ),
          for (final voice in PalVoiceRegistry.voices)
            RadioListTile<String>(
              title: Text('${voice.emoji} ${voice.displayName}'),
              subtitle: Text(voice.description),
              value: voice.voiceKey,
              groupValue: _palVoiceKey,
              onChanged: (value) => _setPalVoiceKey(value!),
            ),
          // Diagnostics entry - only visible when diagnostics are enabled
          if (kDiagnosticsEnabled) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Diagnostics'),
              subtitle: const Text('View logs and export support bundle'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/diagnostics'),
            ),
          ],
        ],
          ),
          ),
        ],
      ),
    );
  }
}
