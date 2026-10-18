import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/availability_check_service.dart';
import 'package:mytube/domain/services/availability_check_service_provider.dart';
import 'package:mytube/features/library/manage_sources_sheet.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRepository implements VideoRepository {
  _FakeRepository(this.locations);

  List<SourceLocation> locations;
  final List<String> setPrimaryCalls = [];

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Ok(locations);

  @override
  Future<Result<void>> setPrimarySourceLocation({
    required String videoItemId,
    required String locationId,
  }) async {
    setPrimaryCalls.add(locationId);
    locations = [
      for (final l in locations) _copy(l, isPrimary: l.id == locationId),
    ];
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeAvailabilityService implements AvailabilityCheckService {
  final List<String> recheckCalls = [];
  final List<String> mediaStoreGrantCalls = [];
  final List<String> folderReconnectCalls = [];

  @override
  Future<Result<AvailabilityState>> recheckLocation(
    SourceLocation location,
  ) async {
    recheckCalls.add(location.id);
    return const Ok(AvailabilityState.available);
  }

  @override
  Future<Result<AvailabilityState>> requestMediaStoreAccessAndRecheck(
    SourceLocation location,
  ) async {
    mediaStoreGrantCalls.add(location.id);
    return const Ok(AvailabilityState.available);
  }

  @override
  Future<Result<AvailabilityState>> reconnectFolderAndRecheck(
    SourceLocation location,
  ) async {
    folderReconnectCalls.add(location.id);
    return const Ok(AvailabilityState.available);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

SourceLocation _copy(
  SourceLocation l, {
  bool? isPrimary,
  AvailabilityState? availability,
}) => SourceLocation(
  id: l.id,
  videoItemId: l.videoItemId,
  providerType: l.providerType,
  sourceUri: l.sourceUri,
  displayName: l.displayName,
  availability: availability ?? l.availability,
  lastCheckedAt: l.lastCheckedAt,
  sizeBytes: l.sizeBytes,
  thumbnailUri: l.thumbnailUri,
  isPrimary: isPrimary ?? l.isPrimary,
);

SourceLocation _loc({
  required String id,
  ProviderType providerType = ProviderType.localMediaStore,
  String sourceUri = 'content://media/external/video/1',
  String? displayName,
  AvailabilityState availability = AvailabilityState.available,
  bool isPrimary = false,
}) => SourceLocation(
  id: id,
  videoItemId: 'video-1',
  providerType: providerType,
  sourceUri: sourceUri,
  displayName: displayName,
  availability: availability,
  isPrimary: isPrimary,
);

final _video = VideoItemSummary(
  id: VideoItemId('video-1'),
  title: 'My Video',
  durationMs: 60000,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 1_700_000_000_000,
);

/// Opens the sheet through a real modal route so its Done button (which pops
/// the navigator) behaves exactly as in production.
Future<void> _openSheet(
  WidgetTester tester, {
  required _FakeRepository repo,
  required _FakeAvailabilityService service,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoRepositoryProvider.overrideWith((ref) => repo),
        availabilityCheckServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open_sheet'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => ManageSourcesSheet(video: _video),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open_sheet')));
  await tester.pumpAndSettle();
}

void main() {
  group('ManageSourcesSheet (P7-06/P7-07)', () {
    testWidgets('lists every source with its availability status', (
      tester,
    ) async {
      final repo = _FakeRepository([
        _loc(id: 'loc-a', isPrimary: true),
        _loc(id: 'loc-b', availability: AvailabilityState.missing),
      ]);
      await _openSheet(tester, repo: repo, service: _FakeAvailabilityService());

      expect(find.text('Manage sources'), findsOneWidget);
      expect(find.text('My Video'), findsOneWidget);
      // Primary marker on loc-a only.
      expect(find.text('Primary'), findsOneWidget);
      // Both availability chips render (AVAIL-001 — rows never vanish).
      expect(
        find.byKey(const ValueKey('availability_available')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('availability_missing')),
        findsOneWidget,
      );
    });

    testWidgets('offering set-primary updates the repository and reloads', (
      tester,
    ) async {
      final repo = _FakeRepository([
        _loc(id: 'loc-a', isPrimary: true),
        _loc(id: 'loc-b', availability: AvailabilityState.missing),
      ]);
      await _openSheet(tester, repo: repo, service: _FakeAvailabilityService());

      // Set-primary action only appears for the non-primary row.
      await tester.tap(find.byKey(const ValueKey('source_primary_loc-b')));
      await tester.pumpAndSettle();

      expect(repo.setPrimaryCalls, ['loc-b']);
      // After the reload, loc-b is now the primary and its button disappears.
      expect(find.byKey(const ValueKey('source_primary_loc-b')), findsNothing);
      expect(
        find.byKey(const ValueKey('source_primary_loc-a')),
        findsOneWidget,
      );
    });

    testWidgets(
      'recheck on a missing row re-checks it and refreshes the badge',
      (tester) async {
        final repo = _FakeRepository([
          _loc(id: 'loc-a', availability: AvailabilityState.missing),
        ]);
        final service = _FakeAvailabilityService();
        await _openSheet(tester, repo: repo, service: service);

        await tester.tap(find.byKey(const ValueKey('source_recheck_loc-a')));
        await tester.pumpAndSettle();

        expect(service.recheckCalls, ['loc-a']);
        expect(
          find.byKey(const ValueKey('availability_available')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('availability_missing')),
          findsNothing,
        );
      },
    );

    testWidgets('a revoked MediaStore row routes retry through the permission '
        'flow (AVAIL-002)', (tester) async {
      final repo = _FakeRepository([
        _loc(
          id: 'loc-ms',
          availability: AvailabilityState.permissionRevoked,
          providerType: ProviderType.localMediaStore,
        ),
      ]);
      final service = _FakeAvailabilityService();
      await _openSheet(tester, repo: repo, service: service);

      await tester.tap(find.byKey(const ValueKey('source_recheck_loc-ms')));
      await tester.pumpAndSettle();

      expect(service.mediaStoreGrantCalls, ['loc-ms']);
      expect(service.recheckCalls, isEmpty);
    });

    testWidgets('a revoked selected-folder row routes retry through folder '
        'reconnect (AVAIL-002)', (tester) async {
      final repo = _FakeRepository([
        _loc(
          id: 'loc-sf',
          providerType: ProviderType.selectedFolder,
          sourceUri: 'content://folder/1',
          availability: AvailabilityState.permissionRevoked,
        ),
      ]);
      final service = _FakeAvailabilityService();
      await _openSheet(tester, repo: repo, service: service);

      await tester.tap(find.byKey(const ValueKey('source_recheck_loc-sf')));
      await tester.pumpAndSettle();

      expect(service.folderReconnectCalls, ['loc-sf']);
    });

    testWidgets(
      'a signed URL row shows host + path but never the query token',
      (tester) async {
        final repo = _FakeRepository([
          _loc(
            id: 'loc-url',
            providerType: ProviderType.directUrl,
            sourceUri: 'https://cdn.example.com/video/clip.mp4?token=SECRET',
            availability: AvailabilityState.expiredLink,
          ),
        ]);
        await _openSheet(
          tester,
          repo: repo,
          service: _FakeAvailabilityService(),
        );

        expect(find.text('cdn.example.com/video/clip.mp4'), findsOneWidget);
        expect(find.textContaining('SECRET'), findsNothing);
      },
    );

    testWidgets('Done closes the sheet', (tester) async {
      final repo = _FakeRepository([_loc(id: 'loc-a')]);
      await _openSheet(tester, repo: repo, service: _FakeAvailabilityService());

      await tester.tap(find.byKey(const ValueKey('manage_sources_done')));
      await tester.pumpAndSettle();

      expect(find.text('Manage sources'), findsNothing);
    });
  });
}
