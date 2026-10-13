import 'package:flutter/material.dart';
import 'package:mytube/app/app_info.dart';

/// Temporary home until Discover/Reels/Library/Saved/Settings land in P1-03.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  static const statusMessage =
      'The app shell is ready. Library tabs and playback will appear here.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppInfo.name)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(statusMessage, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
