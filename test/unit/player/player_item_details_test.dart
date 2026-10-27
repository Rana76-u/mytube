import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/player_item_details.dart';

import '../../support/fake_video_repository.dart';

/// Fixed clock so the relative date in the meta line is deterministic.
final DateTime _now = DateTime.utc(2026, 10, 27, 12);

VideoItemSummary _item({
  String id = 'vid-1',
  int? createdAtMs,
  int? durationMs,
  int? widthPx,
  int? heightPx,
  ProviderType? primaryProvider,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Trip clip',
  durationMs: durationMs,
  widthPx: widthPx,
  heightPx: heightPx,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: createdAtMs ?? _now.millisecondsSinceEpoch,
  primaryProvider: primaryProvider,
);

SourceLocation _location({
  String uri = '/storage/emulated/0/Download/trip.mp4',
  ProviderType provider = ProviderType.selectedFolder,
  String? displayName,
  AvailabilityState availability = AvailabilityState.available,
  int? sizeBytes,
  bool isPrimary = false,
}) => SourceLocation(
  id: 'loc-1',
  videoItemId: 'vid-1',
  providerType: provider,
  sourceUri: uri,
  displayName: displayName,
  availability: availability,
  sizeBytes: sizeBytes,
  isPrimary: isPrimary,
);

void main() {
  group('playerMetaLine', () {
    test('prints date, source, resolution, size and duration in order', () {
      final line = playerMetaLine(
        _item(
          createdAtMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          durationMs: 750000,
          widthPx: 1920,
          heightPx: 1080,
          primaryProvider: ProviderType.localMediaStore,
        ),
        sizeBytes: 1610612736,
        now: _now,
      );

      expect(line, '1 day ago · Local · 1920×1080 · 1.5 GB · 12:30');
    });

    test('pluralises the date bucket', () {
      expect(
        playerMetaLine(
          _item(
            createdAtMs: _now
                .subtract(const Duration(days: 3))
                .millisecondsSinceEpoch,
          ),
          now: _now,
        ),
        startsWith('3 days ago'),
      );
    });

    test('drops every unknown part instead of printing zeros', () {
      expect(playerMetaLine(_item(), now: _now), 'just now');
    });

    test('keeps the parts that are known on a partial record', () {
      final line = playerMetaLine(
        _item(
          createdAtMs: _now
              .subtract(const Duration(hours: 5))
              .millisecondsSinceEpoch,
          durationMs: 65000,
          primaryProvider: ProviderType.cloudflareR2,
        ),
        now: _now,
      );

      expect(line, '5 hours ago · R2 · 1:05');
    });
  });

  group('resolutionLabel', () {
    test('uses the multiplication sign', () {
      expect(resolutionLabel(1280, 720), '1280×720');
    });

    test('is empty when a dimension is missing or not a real size', () {
      expect(resolutionLabel(null, 720), isEmpty);
      expect(resolutionLabel(1280, null), isEmpty);
      expect(resolutionLabel(0, 720), isEmpty);
    });
  });

  group('describeSourceLocation', () {
    test('prefers the stored display name and labels a SAF folder', () {
      final described = describeSourceLocation(
        _location(displayName: 'Trip.mp4'),
      );

      expect(described.fileName, 'Trip.mp4');
      expect(described.locationLabel, 'Download');
    });

    test('falls back to the last path segment', () {
      expect(describeSourceLocation(_location()).fileName, 'trip.mp4');
    });

    test('names the device for a MediaStore row', () {
      final described = describeSourceLocation(
        _location(
          provider: ProviderType.localMediaStore,
          uri: 'content://media/external/video/media/42',
          displayName: '42',
        ),
      );

      expect(described.locationLabel, 'This device');
    });

    test('prints only the host for a direct URL, never the query', () {
      final described = describeSourceLocation(
        _location(
          provider: ProviderType.directUrl,
          uri: 'https://cdn.example.com/v/trip.mp4?token=SECRET&sig=abc',
        ),
      );

      expect(described.fileName, 'trip.mp4');
      expect(described.locationLabel, 'cdn.example.com');
      // A signed URL's parameters must not reach the UI (AGENTS privacy rules).
      expect(described.locationLabel, isNot(contains('SECRET')));
      expect(described.fileName, isNot(contains('SECRET')));
    });

    test('names the cloud provider', () {
      expect(
        describeSourceLocation(
          _location(
            provider: ProviderType.oneDrive,
            uri: '/drive/root/Videos/trip.mp4',
          ),
        ).locationLabel,
        'OneDrive',
      );
    });

    test('says so when the row carries no path to read a name from', () {
      expect(
        describeSourceLocation(
          _location(provider: ProviderType.directUrl, uri: ''),
        ).fileName,
        'Unknown file',
      );
    });
  });

  test('availabilityLabel covers the states the card can show', () {
    expect(availabilityLabel(AvailabilityState.available), 'Available');
    expect(availabilityLabel(AvailabilityState.missing), 'File missing');
    expect(availabilityLabel(AvailabilityState.unknown), 'Not checked yet');
  });

  group('PlayerItemDetails', () {
    test('primary takes the flagged location, else the first row', () {
      final secondary = _location(uri: '/a.mp4');
      final preferred = _location(
        uri: '/b.mp4',
        isPrimary: true,
        sizeBytes: 10,
      );

      expect(
        PlayerItemDetails(locations: [secondary, preferred]).primary?.sourceUri,
        '/b.mp4',
      );
      expect(PlayerItemDetails(locations: [secondary]).sizeBytes, isNull);
      expect(PlayerItemDetails().primary, isNull);
    });
  });

  group('playerItemDetailsProvider', () {
    ProviderContainer containerWith(FakeVideoRepository repository) =>
        ProviderContainer(
          overrides: [videoRepositoryProvider.overrideWithValue(repository)],
        );

    test('reads sources and tags for the item', () async {
      final container = containerWith(
        FakeVideoRepository(
          locations: const {
            'vid-1': [
              SourceLocation(
                id: 'l1',
                videoItemId: 'vid-1',
                providerType: ProviderType.selectedFolder,
                sourceUri: '/Download/trip.mp4',
                availability: AvailabilityState.available,
                sizeBytes: 2048,
              ),
            ],
          },
          tags: const {
            'vid-1': [LibraryTag(id: 't1', name: 'travel')],
          },
        ),
      );
      addTearDown(container.dispose);

      final details = await container.read(
        playerItemDetailsProvider(VideoItemId('vid-1')).future,
      );

      expect(details.sizeBytes, 2048);
      expect(details.tags.map((tag) => tag.name), ['travel']);
    });

    test(
      'a failed read fails soft: the card simply has nothing to show',
      () async {
        final container = containerWith(
          FakeVideoRepository(
            sourceLocationsError: const NotFoundError(
              userMessage: 'gone',
              diagnosticMessage: 'test',
            ),
          ),
        );
        addTearDown(container.dispose);

        final details = await container.read(
          playerItemDetailsProvider(VideoItemId('vid-1')).future,
        );

        expect(details.locations, isEmpty);
        expect(details.primary, isNull);
      },
    );
  });
}
