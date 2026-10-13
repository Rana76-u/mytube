import 'package:flutter/material.dart';

/// Library tab — searchable, filterable video collection (LIB-001–LIB-009).
///
/// This is a placeholder until Phase 5 (P5-01) wires the real library UI.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: const Center(child: Text('Library')),
    );
  }
}
