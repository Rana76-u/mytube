import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/library/video_item_card.dart';

void main() {
  group('LibraryScreen (P5-01)', () {
    testWidgets('shows empty state when library is empty', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeEmptyRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library Empty'), findsOneWidget);
      expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('shows video list when items exist', (tester) async {
      final items = [
        VideoItemSummary(
          id: VideoItemId('id1'),
          title: 'Video 1',
          durationMs: 60000,
          isFavourite: false,
          watchProgressMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
        VideoItemSummary(
          id: VideoItemId('id2'),
          title: 'Video 2',
          durationMs: 120000,
          isFavourite: true,
          watchProgressMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: items),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VideoItemCard), findsNWidgets(2));
      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('shows error state when repository fails', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeErrorRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('displays search button in app bar', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeEmptyRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsOneWidget);
      addTearDown(container.dispose);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake repositories for testing
// ---------------------------------------------------------------------------

class _FakeEmptyRepository implements VideoRepository {
  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async => Result.ok([]);

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async => throw UnimplementedError();

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async =>
      throw UnimplementedError();

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async => throw UnimplementedError();
}

class _FakeRepository implements VideoRepository {
  _FakeRepository({required this.items});

  final List<VideoItemSummary> items;

  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async =>
      Result.ok(items);

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async => throw UnimplementedError();

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async =>
      throw UnimplementedError();

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async => throw UnimplementedError();
}

class _FakeErrorRepository implements VideoRepository {
  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async {
    return Result.err(
      const UnexpectedError(
        userMessage: 'Failed to load library',
        diagnosticMessage: 'Test error',
      ),
    );
  }

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async => throw UnimplementedError();

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async =>
      throw UnimplementedError();

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async => throw UnimplementedError();
}
