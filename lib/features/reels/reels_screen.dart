import 'package:flutter/material.dart';

/// Reels tab — full-screen, vertical swipe-first playback (PLAY-001–PLAY-003).
///
/// This is a placeholder until Phase 6 (P6-01–P6-04) wires the player.
class ReelsScreen extends StatelessWidget {
  const ReelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reels')),
      body: const Center(child: Text('Reels')),
    );
  }
}
