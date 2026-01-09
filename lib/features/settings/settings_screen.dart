import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';
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
  String _storytellingMode = 'creative';
  String _storyLanguage = 'WEB';

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

    // Load kid-friendly mode, reflections, storytelling mode, and story language from UserPreferences (via app state)
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      _kidFriendlyOnly = appState.userPreferences.kidFriendlyOnly;
      _showEverydayReflections = appState.userPreferences.showEverydayReflections;
      _storytellingMode = appState.userPreferences.storytellingMode;
      _storyLanguage = appState.userPreferences.storyLanguage;
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

  Future<void> _setStoryLanguage(String language) async {
    // Log story language change
    logEvent('story_language_changed', {
      'from': _storyLanguage,
      'to': language,
      'kid_mode': _kidFriendlyOnly,
    });

    setState(() => _storyLanguage = language);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateStoryLanguage(language);
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
          const Divider(),
          const ListTile(
            title: Text('Story Mode'),
            subtitle: Text('Choose between creative parables or traditional Bible retellings'),
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
            subtitle: const Text('Real Bible stories retold poetically'),
            value: 'traditional',
            groupValue: _storytellingMode,
            onChanged: (value) => _setStorytellingMode(value!),
          ),
          const Divider(),
          const ListTile(
            title: Text('Story Language'),
            subtitle: Text('Choose the Bible translation style for stories'),
          ),
          RadioListTile<String>(
            title: const Text('Modern (WEB)'),
            subtitle: const Text('World English Bible - contemporary language'),
            value: 'WEB',
            groupValue: _storyLanguage,
            onChanged: (value) => _setStoryLanguage(value!),
          ),
          RadioListTile<String>(
            title: const Text('Classic (KJV)'),
            subtitle: const Text('King James Version - traditional language'),
            value: 'KJV',
            groupValue: _storyLanguage,
            onChanged: (value) => _setStoryLanguage(value!),
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
