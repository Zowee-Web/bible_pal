import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/service_providers.dart';
import '../../core/app_logger.dart';
import '../../core/diagnostics_config.dart';

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
  bool _contentFilteringEnabled = true;
  String _storytellingMode =
      'traditional'; // Default is Traditional per Contracts v2
  String _languageStyle = 'WEB'; // Story presentation diction (Contracts v2)
  // Voice consent (Phase 3)
  bool? _storyNarrationEnabled;
  bool? _palGreetingsEnabled;

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
      _contentFilteringEnabled =
          appState.userPreferences.contentFilteringEnabled;
      _storytellingMode = appState.userPreferences.storytellingMode;
      _languageStyle = appState.userPreferences.languageStyle;
      // Voice consent (Phase 3)
      _storyNarrationEnabled = appState.userPreferences.storyNarrationEnabled;
      _palGreetingsEnabled = appState.userPreferences.palGreetingsEnabled;
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

  Future<void> _setShowEverydayReflections(bool on) async {
    setState(() => _showEverydayReflections = on);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateShowEverydayReflections(on);
  }

  Future<void> _setContentFilteringEnabled(bool on) async {
    setState(() => _contentFilteringEnabled = on);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateContentFilteringEnabled(on);
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Background Sound'),
            subtitle: const Text('Play ambient audio during parables'),
            value: _backgroundSoundOn,
            onChanged: _setBackgroundSound,
          ),
          SwitchListTile(
            title: const Text('Kid Friendly'),
            subtitle: const Text('Only show parables appropriate for children'),
            value: _kidFriendlyOnly,
            onChanged: _setKidFriendlyOnly,
          ),
          SwitchListTile(
            title: const Text('Relate stories to everyday life'),
            subtitle: const Text('Show a brief reflection after each story'),
            value: _showEverydayReflections,
            onChanged: _setShowEverydayReflections,
          ),
          SwitchListTile(
            title: const Text('Content Filter'),
            subtitle: const Text('Block inappropriate content in stories'),
            value: _contentFilteringEnabled,
            onChanged: _setContentFilteringEnabled,
          ),
          const Divider(),
          const ListTile(
            title: Text('Story Mode'),
            subtitle: Text(
                'Choose between creative parables or traditional Bible retellings'),
          ),
          RadioListTile<String>(
            title: const Text('Creative Stories'),
            subtitle: const Text('Original faith-inspired parables'),
            value: 'creative',
            groupValue: _storytellingMode,
            onChanged: (value) => _setStorytellingMode(value!),
          ),
          RadioListTile<String>(
            title: const Text('Traditional Stories'),
            subtitle: const Text('Actual Bible stories faithfully retold'),
            value: 'traditional',
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
            subtitle: const Text('Audio playback of parables'),
            value: _storyNarrationEnabled ?? false,
            onChanged: (value) => _setStoryNarrationEnabled(value),
          ),
          SwitchListTile(
            title: const Text('PAL Greetings'),
            subtitle: const Text('Voice greetings from your PAL'),
            value: _palGreetingsEnabled ?? false,
            onChanged: (value) => _setPalGreetingsEnabled(value),
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
    );
  }
}
