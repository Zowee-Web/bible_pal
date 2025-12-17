import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';

const _pkTradition = 'settings.tradition';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  Future<bool> _needsTradition() async {
    final sp = await SharedPreferences.getInstance();
    // If null, we still need to ask the user for their tradition once.
    return sp.getString(_pkTradition) == null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _needsTradition(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        // AppRouter should return a MaterialApp configured for your app.
        return AppRouter(needsTradition: snap.data!);
      },
    );
  }
}
