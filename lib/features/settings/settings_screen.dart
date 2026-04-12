import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_notifier.dart';
import '../../providers/service_providers.dart';
import '../../core/app_logger.dart';
import '../../core/diagnostics_config.dart';
import '../../core/pal_voice_registry.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loaded = false;
  // PAL voice selection
  String _palVoiceKey = PalVoiceRegistry.defaultVoiceKey;
  // User name
  String _userName = '';
  // Name audio status
  bool _nameAudioReady = false;
  bool _nameAudioGenerating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Load voice and name from UserPreferences
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      _palVoiceKey = appState.userPreferences.palVoiceKey;
      _userName = appState.userPreferences.userName;
    }

    // Check name audio status
    if (_userName.isNotEmpty) {
      final nameAudio = ref.read(nameAudioServiceProvider);
      _nameAudioReady = await nameAudio.isAvailable(_userName, _palVoiceKey);
    }

    setState(() => _loaded = true);
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
    final palette = LivingSky.getPalette(LivingSky.getPhase());

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
          // Subtle scrim behind content for readability on medium backgrounds
          Positioned.fill(
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: palette.foreground.scrimColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [

                // ── 1. PAL's Voice ──
                _SectionHeader(title: "PAL's Voice", palette: palette),
                const SizedBox(height: 4),
                for (final voice in PalVoiceRegistry.voices)
                  _SettingRow(
                    title: '${voice.emoji} ${voice.displayName}',
                    subtitle: voice.description,
                    palette: palette,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.play_circle_outline, size: 22, color: palette.subtitleColor),
                          tooltip: 'Preview ${voice.displayName}',
                          onPressed: () {
                            final palAudio = ref.read(palAudioServiceProvider);
                            palAudio.playPreview(voice.voiceKey);
                          },
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                        Radio<String>(
                          value: voice.voiceKey,
                          groupValue: _palVoiceKey,
                          onChanged: (v) => _setPalVoiceKey(v!),
                          activeColor: palette.warmHighlight,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    onTap: () => _setPalVoiceKey(voice.voiceKey),
                  ),

                const SizedBox(height: 20),

                // ── 2. Your Name ──
                _SectionHeader(title: 'Your Name', palette: palette),
                const SizedBox(height: 4),
                _SettingRow(
                  title: _userName.isEmpty ? 'Not set' : _userName,
                  subtitle: null,
                  palette: palette,
                  trailing: Icon(Icons.edit_outlined, size: 20, color: palette.subtitleColor),
                  onTap: _editUserName,
                ),
                if (_userName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _SettingRow(
                    title: 'Voice Greeting',
                    subtitle: _nameAudioReady
                        ? 'PAL will say your name when greeting you'
                        : 'Tap to generate so PAL can say your name',
                    palette: palette,
                    trailing: _nameAudioGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _regenerateNameAudio,
                            child: Text(
                              _nameAudioReady ? 'Regenerate' : 'Generate',
                              style: TextStyle(color: palette.warmHighlight),
                            ),
                          ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── 5. Reset Onboarding ──
                _SettingRow(
                  title: 'Reset Onboarding',
                  subtitle: "Return to PAL's introduction",
                  palette: palette,
                  trailing: Icon(Icons.chevron_right, color: palette.subtitleColor),
                  onTap: _resetOnboarding,
                ),

                // ── Diagnostics (debug only) ──
                if (kDiagnosticsEnabled) ...[
                  const SizedBox(height: 20),
                  _SettingRow(
                    title: 'Diagnostics',
                    subtitle: 'View logs and export support bundle',
                    palette: palette,
                    trailing: Icon(Icons.chevron_right, color: palette.subtitleColor),
                    onTap: () => Navigator.pushNamed(context, '/diagnostics'),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable setting widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final SkyPalette palette;

  const _SectionHeader({required this.title, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: palette.foreground.secondaryText,
          letterSpacing: 0.5,
          shadows: palette.foreground.subtitleShadow,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SkyPalette palette;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.palette,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: palette.foreground.primaryText,
                        shadows: palette.foreground.textShadow,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: palette.foreground.tertiaryText,
                          shadows: palette.foreground.subtitleShadow,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
