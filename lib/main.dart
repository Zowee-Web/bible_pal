import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/app_logger.dart';
import 'core/diagnostics_lifecycle_observer.dart';
import 'features/onboarding/first_launch_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging with runtime version info
  final packageInfo = await PackageInfo.fromPlatform();
  setLoggerAppInfo(
    version: packageInfo.version,
    build: packageInfo.buildNumber,
  );

  // Log app startup
  logEvent('app_start', {
    'platform': Platform.operatingSystem,
    'platform_version': Platform.operatingSystemVersion,
  });

  // Initialize diagnostics lifecycle observer (flushes breadcrumbs on background)
  // Only active when DIAGNOSTICS_ENABLED=true
  initializeDiagnosticsLifecycle();

  // Load the bundled client config (graceful — app still starts if missing).
  // This is a secret-reduced file generated from .env by scripts/gen_app_env.sh:
  // it carries only the keys the app reads at runtime, never pipeline secrets.
  try {
    await dotenv.load(fileName: 'assets/config/app.env');
  } catch (e) {
    debugPrint('dotenv: app.env not loaded ($e) — continuing without it.');
  }

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
        if (snap.hasError) {
          // Safe default: show first-launch onboarding if prefs fail to load
          return const AppRouter(showFirstLaunch: true);
        }
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
