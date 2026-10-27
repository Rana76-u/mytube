import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Library reads for a [LibraryQuery] — the combined title search (LIB-003),
/// filters (LIB-004) and sort (LIB-005).
///
/// Scoped `autoDispose`: every distinct query keeps a full result list, so a
/// search that types ten characters would otherwise pin ten copies of the
/// library in memory for the rest of the session. Disposal happens once the
/// list stops watching the query (on the next query or on unmount); invalidate
/// the specific query to refresh after a mutation.
///
/// Lives beside [libraryViewStateProvider] (not in the screen) because the
/// shell header and the Library tab both invalidate it after a scan, a URL add
/// or a per-item action.
final libraryItemsProvider = FutureProvider.autoDispose
    .family<List<VideoItemSummary>, LibraryQuery>((ref, query) async {
      final repository = ref.watch(videoRepositoryProvider);
      final result = await repository.queryItems(query);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw StateError(error.diagnosticMessage),
      };
    });

/// The user's tags, offered as options by the tag filter and the Discover chip
/// row (`libraryTagsProvider`).
final libraryTagsProvider = FutureProvider<List<LibraryTag>>((ref) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getTags();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
