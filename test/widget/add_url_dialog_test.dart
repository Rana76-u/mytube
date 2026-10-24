import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/features/library/add_url_dialog.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter_provider.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

// ---------------------------------------------------------------------------
// Fakes and harness (house style — manual fakes, no mocking package)
// ---------------------------------------------------------------------------

/// Manual fake prober with a scripted outcome; records probed URLs.
class _FakeUrlMetadataProber implements UrlMetadataProber {
  _FakeUrlMetadataProber(this.outcome);

  UrlProbeOutcome outcome;
  final List<Uri> probed = [];

  @override
  Future<UrlProbeOutcome> probe(
    Uri url, {
    Duration timeout = defaultProbeTimeout,
    CancellationToken? cancellationToken,
  }) async {
    probed.add(url);
    return outcome;
  }
}

UrlProbeSuccess _success() => const UrlProbeSuccess(
  UrlProbeMetadata(
    statusCode: 200,
    mimeType: 'video/mp4',
    sizeBytes: 4096,
    acceptsRange: true,
  ),
);

/// Records every mutation so tests can assert what the flow persisted.
/// [getAllItems] synthesizes summaries from the inserted rows, so the
/// LibraryScreen list reflects what was added during the test.
class _RecordingRepository implements VideoRepository {
  final List<VideoItemInsert> insertedItems = [];
  final List<SourceLocationInsert> insertedLocations = [];
  final List<String> metadataUpdateIds = [];
  List<SourceLocation> locationsToReturn = [];

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async => Result.ok([
    for (final item in insertedItems)
      VideoItemSummary(
        id: VideoItemId(item.id),
        title: item.title,
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: item.createdAt,
      ),
  ]);

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async => Result.ok(locationsToReturn);

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Result.ok(locationsToReturn);

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async =>
      getAllItems();

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async =>
      getAllItems();

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Result.ok(const []);

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async =>
      Result.ok(const []);

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteCollection(String id) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> setCollectionPinned({
    required String id,
    required bool pinned,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  ) async => Result.ok(const []);

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(
    VideoItemId videoId,
  ) async => Result.ok(const {});

  @override
  Future<Result<List<LibraryTag>>> getTagsForVideo(VideoItemId id) async =>
      Result.ok(const []);

  @override
  Future<Result<LibraryTag>> ensureTag(String name) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> addTagToVideo({
    required VideoItemId id,
    required String tagId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeTagFromVideo({
    required VideoItemId id,
    required String tagId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async {
    insertedItems.add(item);
    return Result.ok(item.id);
  }

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async {
    insertedLocations.add(location);
    return Result.ok(location.id);
  }

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async {
    metadataUpdateIds.add(id);
    return Result.ok(null);
  }

  @override
  Future<void> dispose() async {}

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
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> setPrimarySourceLocation({
    required String videoItemId,
    required String locationId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<DuplicateCandidate>>> findDuplicateCandidates({
    required int sizeBytes,
    required int durationMs,
  }) async => throw UnimplementedError();
}

/// Host that opens [AddUrlDialog] and captures what it pops with.
class _DialogHost extends StatefulWidget {
  const _DialogHost({required this.onPopped});

  final ValueChanged<DirectUrlEntryResult?> onPopped;

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final result = await showDialog<DirectUrlEntryResult>(
              context: context,
              builder: (_) => const AddUrlDialog(),
            );
            widget.onPopped(result);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests — P4-01/P4-02 URL entry UI
// ---------------------------------------------------------------------------

void main() {
  const invalidMessage =
      'Enter a direct video link that starts with http:// or https://.';

  group('AddUrlDialog (P4-01)', () {
    late _RecordingRepository repo;
    late _FakeUrlMetadataProber prober;
    late ProviderContainer container;
    DirectUrlEntryResult? popped;

    setUp(() {
      repo = _RecordingRepository();
      prober = _FakeUrlMetadataProber(_success());
      popped = null;
    });

    /// Pumps the host, opens the dialog, and wires the provider overrides.
    Future<void> openDialog(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => repo),
          urlMetadataProberProvider.overrideWith((ref) => prober),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: _DialogHost(onPopped: (result) => popped = result),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders a single URL field with Add and Cancel', (
      tester,
    ) async {
      await openDialog(tester);

      expect(find.text('Add video URL'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('invalid input shows inline guidance and never probes', (
      tester,
    ) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'not a url');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(find.text(invalidMessage), findsOneWidget);
      expect(
        find.byType(AddUrlDialog),
        findsOneWidget,
        reason: 'the dialog stays open for correction',
      );
      expect(repo.insertedItems, isEmpty);
      expect(prober.probed, isEmpty);
    });

    testWidgets('a successful add pops with a result and persists one entry', (
      tester,
    ) async {
      await openDialog(tester);

      await tester.enterText(
        find.byType(TextField),
        'https://example.com/videos/holiday.mp4',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AddUrlDialog),
        findsNothing,
        reason: 'success closes the dialog',
      );
      expect(popped, isNotNull);
      expect(popped!.isNew, isTrue);
      expect(popped!.availability, AvailabilityState.available);
      expect(repo.insertedItems, hasLength(1));
      expect(
        repo.insertedLocations.single.sourceUri,
        'https://example.com/videos/holiday.mp4',
      );
    });

    testWidgets(
      'a definitive probe failure keeps the dialog open with the message',
      (tester) async {
        prober.outcome = const UrlProbeFailure(
          error: NotFoundError(diagnosticMessage: 'probe: 404'),
          isTransient: false,
        );
        await openDialog(tester);

        await tester.enterText(
          find.byType(TextField),
          'https://example.com/gone.mp4',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        expect(
          find.byType(AddUrlDialog),
          findsOneWidget,
          reason: 'a rejected URL must not be added silently',
        );
        expect(find.text('This item could not be found.'), findsOneWidget);
        expect(repo.insertedItems, isEmpty);
      },
    );

    testWidgets('a transient probe failure still adds and pops (URL-003)', (
      tester,
    ) async {
      prober.outcome = const UrlProbeFailure(
        error: UnexpectedError(diagnosticMessage: 'probe timeout'),
        isTransient: true,
      );
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'https://x.dev/v.mp4');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.byType(AddUrlDialog), findsNothing);
      expect(popped, isNotNull);
      expect(popped!.isNew, isTrue);
      expect(popped!.availability, AvailabilityState.unknown);
      expect(repo.insertedItems, hasLength(1));
    });

    testWidgets('cancel closes without probing or persisting', (tester) async {
      await openDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AddUrlDialog), findsNothing);
      expect(popped, isNull);
      expect(repo.insertedItems, isEmpty);
      expect(prober.probed, isEmpty);
    });
  });

  group('LibraryScreen URL entry (P4-01)', () {
    late _RecordingRepository repo;
    late _FakeUrlMetadataProber prober;
    late ProviderContainer container;

    setUp(() {
      repo = _RecordingRepository();
      prober = _FakeUrlMetadataProber(_success());
    });

    Future<void> pumpLibrary(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => repo),
          urlMetadataProberProvider.overrideWith((ref) => prober),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the app-bar link icon opens the dialog', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pumpAndSettle();

      expect(find.text('Add video URL'), findsOneWidget);
    });

    testWidgets('the empty-state action opens the dialog', (tester) async {
      await pumpLibrary(tester);

      // "Scan device" is now the primary FilledButton; the URL entry moved to
      // the secondary OutlinedButton so first-run guidance covers both paths.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add URL'));
      await tester.pumpAndSettle();

      expect(find.text('Add video URL'), findsOneWidget);
    });

    testWidgets('a completed add refreshes the list and confirms', (
      tester,
    ) async {
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/videos/holiday.mp4',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // The screen invalidated its list provider, which re-read the
      // repository and now shows the freshly inserted item.
      expect(find.text('holiday.mp4'), findsOneWidget);
      expect(find.text('URL added to your library.'), findsOneWidget);

      // Let the snackbar auto-hide timer fire and its exit animation end so
      // no timers are left pending at teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
