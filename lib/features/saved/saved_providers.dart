import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Collections for the Saved screen, newest-first with item counts (NAV-004).
final savedCollectionsProvider = FutureProvider<List<CollectionSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getCollections();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});

/// Favourited videos surfaced on the Saved screen (LIB-002 / NAV-004).
final favouriteItemsProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.queryItems(
    const LibraryQuery(filter: VideoFilter(favouritesOnly: true)),
  );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});

/// The items of one collection, keyed by collection id, in manual order.
final collectionItemsProvider =
    FutureProvider.family<List<VideoItemSummary>, String>((ref, id) async {
      final repository = ref.watch(videoRepositoryProvider);
      final result = await repository.getCollectionItems(id);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw StateError(error.diagnosticMessage),
      };
    });

/// Every library item — the pool offered when adding videos to a collection.
final allLibraryItemsProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getAllItems();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});

/// The collection ids that contain the given video id — used to mark current
/// membership in the add-videos sheet.
final videoCollectionIdsProvider = FutureProvider.family<Set<String>, String>((
  ref,
  videoId,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getCollectionIdsForVideo(
    VideoItemId(videoId),
  );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
