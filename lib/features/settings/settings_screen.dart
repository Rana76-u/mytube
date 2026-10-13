import 'package:flutter/material.dart';

/// Settings tab — providers, folders, playback preferences, downloads, cache,
/// library controls, and theme selection (NAV-005, SET-001, SET-002).
///
/// This is a placeholder until later phases wire individual settings sections.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings')),
    );
  }
}
