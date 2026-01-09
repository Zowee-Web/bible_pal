import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/app_logger.dart';
import 'core/diagnostics_lifecycle_observer.dart';
import 'features/onboarding/first_launch_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging with app version info
  // TODO: Read version from pubspec.yaml or package_info_plus
  setLoggerAppInfo(version: '1.0.0', build: '1');

  // Log app startup
  logEvent('app_started', {
    'platform': Platform.operatingSystem,
    'platform_version': Platform.operatingSystemVersion,
  });

  // Initialize diagnostics lifecycle observer (flushes breadcrumbs on background)
  // Only active when DIAGNOSTICS_ENABLED=true
  initializeDiagnosticsLifecycle();

  // TODO: Re-enable dotenv when .env is wired as a Flutter asset.
  // await dotenv.load(fileName: '.env');

  // Optional: simple sanity check in debug builds
  // assert(
  //   (dotenv.env['ELEVENLABS_API_KEY'] ?? '').isNotEmpty,
  //   'ELEVENLABS_API_KEY missing. Create a .env at project root and add it; also list .env under flutter/assets in pubspec.yaml.',
  // );

  runApp(
    const ProviderScope(
      child: Bootstrap(),
    ),
  );
}

class Bootstrap extends StatelessWidget {
  const Bootstrap({super.key});

  Future<bool> _isFirstLaunch() async {
    final sp = await SharedPreferences.getInstance();
    // Check if first-launch onboarding has been completed
    return sp.getBool(kFirstLaunchCompleteKey) != true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isFirstLaunch(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        // Show first-launch onboarding or main app
        if (snap.data!) {
          return const AppRouter(showFirstLaunch: true);
        }
        return const AppRouter(showFirstLaunch: false);
      },
    );
  }
}
