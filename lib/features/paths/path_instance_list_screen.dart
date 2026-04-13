import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/service_providers.dart';
import '../../theme/living_sky.dart';
import '../../widgets/living_sky_background.dart';
import 'path_detail_screen.dart';
import 'path_instance.dart';
import 'path_type.dart';

/// Screen 2 of the PALs Paths drill-down (SPEC Feature 50).
///
/// Lists path instances for a given [PathType] — e.g. "David / Moses /
/// Abraham / Ruth" for Characters, "Patriarchs / Exodus / Kingdom /
/// Jesus Ministry" for Timeline, "Faith / Hope / Mercy / ..." for
/// Themes, "Genesis / Exodus / Luke / ..." for Bible Order. For
/// jesus_life, a single instance is rendered (though typical flow skips
/// this screen and goes straight to PathDetailScreen).
///
/// Tapping an instance pushes [PathDetailScreen] for that
/// (pathType, pathId) combination.
class PathInstanceListScreen extends ConsumerWidget {
  final PathType pathType;

  const PathInstanceListScreen({super.key, required this.pathType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final pathServiceAsync = ref.watch(pathServiceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.foreground.primaryIcon),
        title: Text(
          pathType.displayLabel,
          style: TextStyle(
            color: palette.foreground.primaryText,
            fontWeight: FontWeight.w600,
            shadows: palette.foreground.textShadow,
          ),
        ),
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: pathServiceAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => Center(
                child: Text(
                  "Couldn't load paths right now.",
                  style: TextStyle(color: palette.foreground.secondaryText),
                ),
              ),
              data: (pathService) {
                final instances = pathService.getPathInstances(pathType);
                if (instances.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'No paths available yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.foreground.secondaryText,
                          fontSize: 15,
                          shadows: palette.foreground.subtitleShadow,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: instances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _InstanceTile(
                    instance: instances[index],
                    palette: palette,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PathDetailScreen(
                            pathType: instances[index].pathType,
                            pathId: instances[index].pathId,
                            displayLabel: instances[index].displayLabel,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceTile extends StatelessWidget {
  final PathInstance instance;
  final SkyPalette palette;
  final VoidCallback onTap;

  const _InstanceTile({
    required this.instance,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.cardBorder,
              width: 1.2,
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.displayLabel,
                        style: TextStyle(
                          color: palette.foreground.primaryText,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          shadows: palette.foreground.textShadow,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        instance.storyCount == 1
                            ? '1 story'
                            : '${instance.storyCount} stories',
                        style: TextStyle(
                          color: palette.foreground.secondaryText,
                          fontSize: 13,
                          shadows: palette.foreground.subtitleShadow,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: palette.foreground.secondaryIcon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
