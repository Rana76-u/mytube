import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

const _url = 'https://example.com/videos/holiday.mp4';

/// Manual fake prober (house style — no mocking package).
class FakeUrlMetadataProber implements UrlMetadataProber {
  FakeUrlMetadataProber(this.outcome);

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

/// Seeds a directUrl source location for [_url] through the repository so the
/// duplicate-detection path has an existing row to find.
Future<void> _seedDirectUrlLocation(
  DriftVideoRepository repo, {
  String itemId = 'seed',
  String locationId = 'seed-sl',
  AvailabilityState availability = AvailabilityState.missing,
}) async {
  await repo.insertVideoItem(
    VideoItemInsert(
      id: itemId,
      title: 'Seed Title',
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await repo.insertSourceLocation(
    SourceLocationInsert(
      id: locationId,
      videoItemId: itemId,
      providerType: ProviderType.directUrl,
      sourceUri: _url,
      availability: availability,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — P4-01/P4-02 DirectUrlService
// ---------------------------------------------------------------------------

void main() {
  group('DirectUrlService (P4-01/P4-02)', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late FakeUrlMetadataProber fakeProber;
    late DirectUrlService service;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      fakeProber = FakeUrlMetadataProber(_success());
      service = DirectUrlService(repository: repo, prober: fakeProber);
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    test(
      'a new URL with a successful probe inserts item + location metadata',
      () async {
        final result = await service.addUrl(_url);

        expect(result, isA<Ok<DirectUrlEntryResult>>());
        final r = (result as Ok<DirectUrlEntryResult>).value;
        expect(r.isNew, isTrue);
        expect(r.availability, AvailabilityState.available);

        final items = await db.select(db.videoItems).get();
        expect(items, hasLength(1));
        expect(items.single.title, 'holiday.mp4');

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, hasLength(1));
        final loc = locs.single;
        expect(loc.videoItemId, r.videoItemId);
        expect(loc.providerType, 'directUrl');
        expect(loc.sourceId, _url);
        expect(loc.displayName, 'holiday.mp4');
        expect(loc.availability, 'available');
        expect(loc.mimeType, 'video/mp4');
        expect(loc.sizeBytes, 4096);
        expect(loc.lastCheckedAt, isNotNull);
      },
    );

    test('re-adding the same URL refreshes in place instead of duplicating '
        '(URL-001)', () async {
      await _seedDirectUrlLocation(repo);

      final result = await service.addUrl(_url);

      expect(result, isA<Ok<DirectUrlEntryResult>>());
      final r = (result as Ok<DirectUrlEntryResult>).value;
      expect(r.isNew, isFalse);
      expect(r.videoItemId, 'seed');
      expect(r.availability, AvailabilityState.available);

      // Exactly one row in each table, refreshed in place.
      expect(await db.select(db.videoItems).get(), hasLength(1));
      final locs = await db.select(db.sourceLocations).get();
      expect(locs, hasLength(1));
      expect(locs.single.id, 'seed-sl');
      expect(locs.single.availability, 'available');
      expect(locs.single.displayName, 'holiday.mp4');
    });

    test(
      'a definitive probe failure on an existing URL leaves the row untouched',
      () async {
        await _seedDirectUrlLocation(
          repo,
          availability: AvailabilityState.available,
        );
        fakeProber.outcome = const UrlProbeFailure(
          error: NotFoundError(diagnosticMessage: 'probe: 404'),
          isTransient: false,
        );

        final result = await service.addUrl(_url);

        expect(result, isA<Err<DirectUrlEntryResult>>());
        expect(
          (result as Err<DirectUrlEntryResult>).error,
          isA<NotFoundError>(),
        );

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, hasLength(1));
        expect(locs.single.availability, 'available');
      },
    );

    test(
      'an invalid scheme rejects before probing and writes nothing',
      () async {
        final result = await service.addUrl('ftp://example.com/v.mp4');

        expect(result, isA<Err<DirectUrlEntryResult>>());
        expect(
          (result as Err<DirectUrlEntryResult>).error,
          isA<InvalidUrlError>(),
        );
        expect(fakeProber.probed, isEmpty);
        expect(await db.select(db.videoItems).get(), isEmpty);
        expect(await db.select(db.sourceLocations).get(), isEmpty);
      },
    );

    test(
      'a definitive 404 on a new URL writes nothing (URL-002, URL-005)',
      () async {
        fakeProber.outcome = const UrlProbeFailure(
          error: NotFoundError(diagnosticMessage: 'probe: 404'),
          isTransient: false,
        );

        final result = await service.addUrl(_url);

        expect(result, isA<Err<DirectUrlEntryResult>>());
        expect(
          (result as Err<DirectUrlEntryResult>).error,
          isA<NotFoundError>(),
        );
        expect(await db.select(db.videoItems).get(), isEmpty);
        expect(await db.select(db.sourceLocations).get(), isEmpty);
      },
    );

    test(
      'a transient timeout still adds the entry as unknown (URL-003 fallback)',
      () async {
        fakeProber.outcome = const UrlProbeFailure(
          error: UnexpectedError(diagnosticMessage: 'probe timeout'),
          isTransient: true,
        );

        final result = await service.addUrl(_url);

        expect(result, isA<Ok<DirectUrlEntryResult>>());
        final r = (result as Ok<DirectUrlEntryResult>).value;
        expect(r.isNew, isTrue);
        expect(r.availability, AvailabilityState.unknown);

        final loc = await db.select(db.sourceLocations).getSingle();
        expect(loc.availability, 'unknown');
        expect(loc.mimeType, isNull);
        expect(loc.sizeBytes, isNull);
      },
    );

    test('an offline probe still adds the entry as offline', () async {
      fakeProber.outcome = const UrlProbeFailure(
        error: NetworkUnavailableError(diagnosticMessage: 'socket'),
        isTransient: true,
      );

      final result = await service.addUrl(_url);

      expect(result, isA<Ok<DirectUrlEntryResult>>());
      final r = (result as Ok<DirectUrlEntryResult>).value;
      expect(r.availability, AvailabilityState.offline);

      final loc = await db.select(db.sourceLocations).getSingle();
      expect(loc.availability, 'offline');
    });

    test(
      'a pre-cancelled token rejects before probing and writes nothing',
      () async {
        final token = CancellationToken()..cancel();

        final result = await service.addUrl(_url, cancellationToken: token);

        expect(result, isA<Err<DirectUrlEntryResult>>());
        expect(
          (result as Err<DirectUrlEntryResult>).error,
          isA<UnexpectedError>(),
        );
        expect(fakeProber.probed, isEmpty);
        expect(await db.select(db.videoItems).get(), isEmpty);
        expect(await db.select(db.sourceLocations).get(), isEmpty);
      },
    );

    test('the same URI under a different provider is never treated as a '
        'duplicate (conservative matching)', () async {
      // A local-media entry that happens to use the URL as its source id
      // must not absorb the directUrl entry.
      await repo.insertVideoItem(
        const VideoItemInsert(
          id: 'local-item',
          title: 'Local',
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      await repo.insertSourceLocation(
        SourceLocationInsert(
          id: 'local-sl',
          videoItemId: 'local-item',
          providerType: ProviderType.localMediaStore,
          sourceUri: _url,
          availability: AvailabilityState.available,
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      final result = await service.addUrl(_url);

      expect(result, isA<Ok<DirectUrlEntryResult>>());
      final r = (result as Ok<DirectUrlEntryResult>).value;
      expect(r.isNew, isTrue);
      expect(r.videoItemId, isNot('local-item'));

      final locs = await db.select(db.sourceLocations).get();
      expect(locs, hasLength(2));
      expect(locs.where((l) => l.providerType == 'directUrl'), hasLength(1));
    });
  });
}
