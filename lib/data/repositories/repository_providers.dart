import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Riverpod provider for [VideoRepository].
///
/// Depends on [databaseProvider] — the database is opened lazily on first use.
/// Tests override [databaseProvider] with an in-memory instance; this provider
/// picks up the override automatically.
///
/// Example test setup:
/// ```dart
/// final container = ProviderContainer(overrides: [
///   databaseProvider.overrideWithValue(AppDatabase.inMemory()),
/// ]);
/// final repo = container.read(videoRepositoryProvider);
/// ```
final videoRepositoryProvider = Provider<VideoRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = DriftVideoRepository(db);
  ref.onDispose(repo.dispose);
  return repo;
});
