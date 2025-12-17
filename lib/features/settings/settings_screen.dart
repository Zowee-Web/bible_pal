import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_notifier.dart';

const _pkBackgroundSound = 'settings.backgroundSoundOn';
const _pkKidFriendlyOnly = 'settings.kidFriendlyOnly';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loaded = false;
  bool _backgroundSoundOn = false;
  bool _kidFriendlyOnly = false;
  String _storytellingMode = 'creative';

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

    final kidFriendlyOnly = sp.getBool(_pkKidFriendlyOnly);
    if (kidFriendlyOnly == null) {
      await sp.setBool(_pkKidFriendlyOnly, false);
      _kidFriendlyOnly = false;
    } else {
      _kidFriendlyOnly = kidFriendlyOnly;
    }

    // Load storytelling mode from UserPreferences (via app state)
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      _storytellingMode = appState.userPreferences.storytellingMode;
    }

    setState(() => _loaded = true);
  }

  Future<void> _setBackgroundSound(bool on) async {
    setState(() => _backgroundSoundOn = on);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_pkBackgroundSound, on);
  }

  Future<void> _setKidFriendlyOnly(bool on) async {
    setState(() => _kidFriendlyOnly = on);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_pkKidFriendlyOnly, on);
  }

  Future<void> _setStorytellingMode(String mode) async {
    setState(() => _storytellingMode = mode);
    final appState = ref.read(appStateProvider.notifier);
    await appState.updateStorytellingMode(mode);
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
        ],
      ),
    );
  }
}
