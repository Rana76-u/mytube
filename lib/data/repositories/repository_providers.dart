import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/repositories/drift_recommendation_history_repository.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';
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

/// Riverpod provider for [RecommendationHistoryRepository] (disc redesign §18,
/// ADR-003).
///
/// Shares [databaseProvider] with the library repository and follows the same
/// test seam: override [databaseProvider] with an in-memory database and the
/// exposure store picks it up automatically.
final recommendationHistoryRepositoryProvider =
    Provider<RecommendationHistoryRepository>((ref) {
      final db = ref.watch(databaseProvider);
      final repo = DriftRecommendationHistoryRepository(db);
      ref.onDispose(repo.dispose);
      return repo;
    });
