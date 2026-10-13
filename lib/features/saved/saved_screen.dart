import 'package:flutter/material.dart';

/// Saved tab — favorites and custom collections (NAV-004, LIB-002).
///
/// This is a placeholder until Phase 5 (P5-05–P5-07) wires favorites and
/// collections.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: const Center(child: Text('Saved')),
    );
  }
}
