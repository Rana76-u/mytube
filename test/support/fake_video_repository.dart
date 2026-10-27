import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// A hand-written [VideoRepository] fake for tests that only exercise a couple
/// of reads (sharing, "Up Next").
///
/// House style is per-test manual fakes rather than a mocking package, but the
/// interface has ~30 members; re-declaring them per test file would bury the
/// behaviour under test. Everything the two callers below do not use throws
/// [UnimplementedError], so an accidental dependency on an unrelated query
/// fails loudly instead of silently returning empty data.
class FakeVideoRepository implements VideoRepository {
  FakeVideoRepository({
    List<VideoItemSummary>? items,
    Map<String, List<SourceLocation>>? locations,
    Map<String, List<LibraryTag>>? tags,
    this.sourceLocationsError,
    this.queryError,
    this.deleteError,
  }) : _items = items ?? const <VideoItemSummary>[],
       _locations = locations ?? const <String, List<SourceLocation>>{},
       _tags = tags ?? const <String, List<LibraryTag>>{};

  final List<VideoItemSummary> _items;
  final Map<String, List<SourceLocation>> _locations;
  final Map<String, List<LibraryTag>> _tags;

  /// When set, the matching read fails instead of returning data.
  final AppError? sourceLocationsError;
  final AppError? queryError;

  /// When set, [deleteItem] fails instead of removing the row.
  final AppError? deleteError;

  /// Every id passed to [deleteItem], in call order (ADR-017 tests assert that
  /// the record is removed only after the originals were attempted).
  final List<String> deletedIds = <String>[];

  /// Every [LibraryQuery] this fake answered, in call order, so a test can
  /// assert the sort/limit a provider asked for.
  final List<LibraryQuery> queries = <LibraryQuery>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async {
    if (sourceLocationsError case final error?) return Result.err(error);
    return Result.ok(_locations[id.value] ?? const <SourceLocation>[]);
  }

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    queries.add(query);
    if (queryError case final error?) return Result.err(error);
    final limit = query.limit;
    return Result.ok(
      limit == null ? _items : _items.take(limit).toList(growable: false),
    );
  }

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async =>
      Result.ok(_items);

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async {
    for (final item in _items) {
      if (item.id == id) return Result.ok(item);
    }
    return Result.err(
      const NotFoundError(
        userMessage: 'That video is no longer in your library.',
        diagnosticMessage: 'fake repository: unknown id',
      ),
    );
  }

  // ── Everything else is deliberately unimplemented ──────────────────────────

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) =>
      throw UnimplementedError('searchItems');

  @override
  Future<Result<List<LibraryTag>>> getTags() =>
      throw UnimplementedError('getTags');

  @override
  Future<Result<List<LibraryTag>>> getTagsForVideo(VideoItemId id) async =>
      Result.ok(_tags[id.value] ?? const <LibraryTag>[]);

  @override
  Future<Result<LibraryTag>> ensureTag(String name) =>
      throw UnimplementedError('ensureTag');

  @override
  Future<Result<void>> addTagToVideo({
    required VideoItemId id,
    required String tagId,
  }) => throw UnimplementedError('addTagToVideo');

  @override
  Future<Result<void>> removeTagFromVideo({
    required VideoItemId id,
    required String tagId,
  }) => throw UnimplementedError('removeTagFromVideo');

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) => throw UnimplementedError('saveProgress');

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) =>
      throw UnimplementedError('getProgress');

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) => throw UnimplementedError('setFavourite');

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async {
    if (deleteError case final error?) return Result.err(error);
    deletedIds.add(id.value);
    return const Ok(null);
  }

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) => throw UnimplementedError('getSourceLocationsByProvider');

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) =>
      throw UnimplementedError('insertVideoItem');

  @override
  Future<Result<String>> insertSourceLocation(SourceLocationInsert location) =>
      throw UnimplementedError('insertSourceLocation');

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) => throw UnimplementedError('updateSourceLocationAvailability');

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) => throw UnimplementedError('updateSourceLocationMetadata');

  @override
  Future<Result<void>> setPrimarySourceLocation({
    required String videoItemId,
    required String locationId,
  }) => throw UnimplementedError('setPrimarySourceLocation');

  @override
  Future<Result<List<DuplicateCandidate>>> findDuplicateCandidates({
    required int sizeBytes,
    required int durationMs,
  }) => throw UnimplementedError('findDuplicateCandidates');

  @override
  Future<Result<List<CollectionSummary>>> getCollections() =>
      throw UnimplementedError('getCollections');

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) => throw UnimplementedError('createCollection');

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) => throw UnimplementedError('renameCollection');

  @override
  Future<Result<void>> deleteCollection(String id) =>
      throw UnimplementedError('deleteCollection');

  @override
  Future<Result<void>> setCollectionPinned({
    required String id,
    required bool pinned,
  }) => throw UnimplementedError('setCollectionPinned');

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId, {
    int? limit,
  }) => throw UnimplementedError('getCollectionItems');

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) => throw UnimplementedError('addVideoToCollection');

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) => throw UnimplementedError('removeVideoFromCollection');

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(VideoItemId videoId) =>
      throw UnimplementedError('getCollectionIdsForVideo');
}
