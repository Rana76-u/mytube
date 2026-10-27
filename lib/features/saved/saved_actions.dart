import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/features/saved/saved_providers.dart';
import 'package:mytube/features/saved/text_prompt.dart';

/// Saved-tab actions shared by the shell header and the Saved tab.
///
/// Creating a collection only ever writes app metadata — the videos themselves
/// are untouched (AGENTS data integrity).
Future<void> createCollectionFromPrompt(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await promptForText(
    context,
    title: 'New collection',
    label: 'Name',
  );
  if (name == null) return;
  final repository = ref.read(videoRepositoryProvider);
  final result = await repository.createCollection(name: name);
  if (!context.mounted) return;
  switch (result) {
    case Ok():
      ref.invalidate(savedCollectionsProvider);
    case Err(:final error):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
  }
}
