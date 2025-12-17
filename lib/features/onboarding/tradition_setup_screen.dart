import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_router.dart';

const _pkTradition = 'settings.tradition';

class TraditionSetupScreen extends StatefulWidget {
  const TraditionSetupScreen({super.key});

  @override
  State<TraditionSetupScreen> createState() => _TraditionSetupScreenState();
}

class _TraditionSetupScreenState extends State<TraditionSetupScreen> {
  Future<void> _saveAndGo(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pkTradition, value);

    if (!mounted) return; // ✅ safeguard against async gap

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRouter(needsTradition: false)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    const options = [
      'Catholic',
      'Protestant',
      'Orthodox',
      'Messianic',
      'Non-Denominational',
      'Other',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Tradition')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Select your faith tradition to personalize Bible PAL.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          ...options.map(
            (o) => Card(
              child: ListTile(
                title: Text(o),
                onTap: () => _saveAndGo(o),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
