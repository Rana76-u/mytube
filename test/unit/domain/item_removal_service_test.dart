import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/item_removal_service.dart';

import '../../support/fake_video_repository.dart';

/// ADR-017: removing one item either deletes its originals or only unlinks it,
/// and the decision is made from the item's actual source locations — never from
/// a guess about what kind of video it is.

const _videoId = 'vid-1';
const _mediaStoreOne = 'content://media/external/video/media/1';
const _safDocument =
    'content://com.android.externalstorage.documents/tree/primary%3AMovies/'
    'document/primary%3AMovies%2Fa.mp4';
const _directUrl = 'https://example.com/a.mp4';
const _oneDriveItem = 'onedrive:item/ABC';

/// The two provider types [LocalFileOriginalDeleter] owns; the real deleter is
/// exercised separately, so these tests stay about the decision.
const _localTypes = {ProviderType.localMediaStore, ProviderType.selectedFolder};

VideoItemSummary _item({
  ProviderType? primaryProvider = ProviderType.localMediaStore,
}) => VideoItemSummary(
  id: VideoItemId(_videoId),
  title: 'Test Video',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
  primaryProvider: primaryProvider,
);

SourceLocation _location(
  ProviderType providerType,
  String sourceUri, {
  AvailabilityState availability = AvailabilityState.available,
  bool isPrimary = false,
}) => SourceLocation(
  id: 'loc-$sourceUri',
  videoItemId: _videoId,
  providerType: providerType,
  sourceUri: sourceUri,
  availability: availability,
  isPrimary: isPrimary,
);

/// Records each batch it is handed and answers with [report], or with every
/// requested id as deleted when no report is supplied.
class _RecordingDeleter implements ItemOriginalDeleter {
  _RecordingDeleter({required this.providerTypes, this.report, this.error});

  @override
  final Set<ProviderType> providerTypes;

  /// Fixed answer; when null the deleter claims it deleted everything.
  final SourceDeletionReport? report;

  /// When set, the call fails instead of reporting anything.
  final AppError? error;

  /// Every batch this deleter received, in call order.
  final List<List<String>> batches = <List<String>>[];

  @override
  Future<Result<SourceDeletionReport>> deleteOriginals(
    List<String> sourceIds,
  ) async {
    batches.add(List<String>.of(sourceIds));
    if (error case final error?) return Result.err(error);
    return Result.ok(
      report ?? SourceDeletionReport(deleted: List<String>.of(sourceIds)),
    );
  }
}

VideoItemRemovalService _service(
  VideoRepository repository,
  List<ItemOriginalDeleter> deleters,
) => VideoItemRemovalService(repository: repository, deleters: deleters);

FakeVideoRepository _repositoryFor(List<SourceLocation> locations) =>
    FakeVideoRepository(locations: {_videoId: locations});

void main() {
  group('VideoItemRemovalService.plan (ADR-017)', () {
    test('unlinks a direct-URL item instead of deleting anything', () async {
      final repository = _repositoryFor([
        _location(ProviderType.directUrl, _directUrl),
      ]);
      final deleter = _RecordingDeleter(providerTypes: _localTypes);

      final plan = (await _service(repository, [
        deleter,
      ]).plan(_item(primaryProvider: ProviderType.directUrl))).valueOrThrow;

      expect(plan.scope, ItemRemovalScope.removeFromLibrary);
      expect(plan.isDestructive, isFalse);
      expect(plan.originalsToDelete, isEmpty);
      expect(plan.recordOnly.single.sourceUri, _directUrl);
      // A direct URL is not a missing capability — it simply has no file.
      expect(plan.unsupportedProviders, isEmpty);
      expect(plan.originalCount, 0);
    });

    test('deletes a local MediaStore original', () async {
      final repository = _repositoryFor([
        _location(
          ProviderType.localMediaStore,
          _mediaStoreOne,
          isPrimary: true,
        ),
      ]);

      final plan = (await _service(repository, [
        _RecordingDeleter(providerTypes: _localTypes),
      ]).plan(_item())).valueOrThrow;

      expect(plan.scope, ItemRemovalScope.deleteOriginals);
      expect(plan.isDestructive, isTrue);
      expect(plan.originalCount, 1);
      expect(plan.recordOnly, isEmpty);
      expect(plan.deletingProviders.toList(), [ProviderType.localMediaStore]);
    });

    test(
      'splits a mixed item into files to delete and links to unlink',
      () async {
        final repository = _repositoryFor([
          _location(ProviderType.selectedFolder, _safDocument, isPrimary: true),
          _location(ProviderType.localMediaStore, _mediaStoreOne),
          _location(ProviderType.directUrl, _directUrl),
        ]);

        final plan = (await _service(repository, [
          _RecordingDeleter(providerTypes: _localTypes),
        ]).plan(_item())).valueOrThrow;

        expect(plan.scope, ItemRemovalScope.deleteOriginals);
        expect(plan.originalsToDelete.map((l) => l.sourceUri), [
          _safDocument,
          _mediaStoreOne,
        ]);
        expect(plan.recordOnly.single.providerType, ProviderType.directUrl);
        // Enum order, so the dialog always names the same providers first.
        expect(plan.deletingProviders.toList(), [
          ProviderType.localMediaStore,
          ProviderType.selectedFolder,
        ]);
      },
    );

    test(
      'does not treat an already-missing file as something to delete',
      () async {
        final repository = _repositoryFor([
          _location(
            ProviderType.localMediaStore,
            _mediaStoreOne,
            availability: AvailabilityState.missing,
          ),
        ]);

        final plan = (await _service(repository, [
          _RecordingDeleter(providerTypes: _localTypes),
        ]).plan(_item())).valueOrThrow;

        // Nothing can be destroyed, and a phantom "failed to delete" would be a
        // lie, so the plan degrades to a plain unlink.
        expect(plan.scope, ItemRemovalScope.removeFromLibrary);
        expect(plan.recordOnly.single.sourceUri, _mediaStoreOne);
        expect(plan.unsupportedProviders, isEmpty);
      },
    );

    test('keeps a cloud original that no deleter can destroy yet', () async {
      final repository = _repositoryFor([
        _location(ProviderType.oneDrive, _oneDriveItem),
      ]);

      final plan = (await _service(repository, [
        _RecordingDeleter(providerTypes: _localTypes),
      ]).plan(_item(primaryProvider: ProviderType.oneDrive))).valueOrThrow;

      expect(plan.scope, ItemRemovalScope.removeFromLibrary);
      expect(plan.recordOnly.single.sourceUri, _oneDriveItem);
      expect(plan.unsupportedProviders.toList(), [ProviderType.oneDrive]);
    });

    test(
      'falls back to an unlink when the item has no source locations',
      () async {
        final repository = _repositoryFor(const []);

        final plan = (await _service(repository, [
          _RecordingDeleter(providerTypes: _localTypes),
        ]).plan(_item(primaryProvider: null))).valueOrThrow;

        expect(plan.scope, ItemRemovalScope.removeFromLibrary);
        expect(plan.isDestructive, isFalse);
        expect(plan.originalsToDelete, isEmpty);
        expect(plan.recordOnly, isEmpty);
      },
    );

    test('propagates a source-location read failure', () async {
      const readError = UnexpectedError(diagnosticMessage: 'db unavailable');
      final repository = FakeVideoRepository(sourceLocationsError: readError);

      final result = await _service(repository, [
        _RecordingDeleter(providerTypes: _localTypes),
      ]).plan(_item());

      switch (result) {
        case Err(:final error):
          expect(error, same(readError));
        case Ok():
          fail('expected the plan to fail');
      }
    });
  });

  group('VideoItemRemovalService.remove (ADR-017)', () {
    test(
      'sends one batch per deleter and reports every deleted original',
      () async {
        final repository = _repositoryFor([
          _location(ProviderType.localMediaStore, _mediaStoreOne),
          _location(ProviderType.selectedFolder, _safDocument),
          _location(ProviderType.oneDrive, _oneDriveItem),
        ]);
        final local = _RecordingDeleter(providerTypes: _localTypes);
        final cloud = _RecordingDeleter(
          providerTypes: const {ProviderType.oneDrive},
        );
        final service = _service(repository, [local, cloud]);

        final plan = (await service.plan(_item())).valueOrThrow;
        final outcome = (await service.remove(plan)).valueOrThrow;

        // MediaStore and SAF share one deleter, so they share one call.
        expect(local.batches, [
          [_mediaStoreOne, _safDocument],
        ]);
        expect(cloud.batches, [
          [_oneDriveItem],
        ]);
        expect(outcome.deletedOriginals, 3);
        expect(outcome.undeletedOriginals, 0);
        expect(outcome.isPartial, isFalse);
        expect(outcome.nothingDeleted, isFalse);
        expect(repository.deletedIds, [_videoId]);
      },
    );

    test('reports a partial delete instead of a success', () async {
      final repository = _repositoryFor([
        _location(ProviderType.localMediaStore, _mediaStoreOne),
        _location(ProviderType.selectedFolder, _safDocument),
      ]);
      final local = _RecordingDeleter(
        providerTypes: _localTypes,
        report: const SourceDeletionReport(
          deleted: [_mediaStoreOne],
          failed: [_safDocument],
        ),
      );

      final plan = (await _service(repository, [
        local,
      ]).plan(_item())).valueOrThrow;
      final outcome = (await _service(repository, [
        local,
      ]).remove(plan)).valueOrThrow;

      expect(outcome.deletedOriginals, 1);
      expect(outcome.undeletedOriginals, 1);
      expect(outcome.isPartial, isTrue);
      expect(outcome.nothingDeleted, isFalse);
      // The unlink still succeeds: the user asked to stop seeing the item.
      expect(repository.deletedIds, [_videoId]);
    });

    test('still unlinks the item when the provider deletes nothing', () async {
      final repository = _repositoryFor([
        _location(ProviderType.localMediaStore, _mediaStoreOne),
      ]);
      final local = _RecordingDeleter(
        providerTypes: _localTypes,
        // Android's delete confirmation was dismissed.
        report: const SourceDeletionReport(failed: [_mediaStoreOne]),
      );

      final plan = (await _service(repository, [
        local,
      ]).plan(_item())).valueOrThrow;
      final outcome = (await _service(repository, [
        local,
      ]).remove(plan)).valueOrThrow;

      expect(outcome.deletedOriginals, 0);
      expect(outcome.undeletedOriginals, 1);
      expect(outcome.nothingDeleted, isTrue);
      expect(outcome.isPartial, isFalse);
      expect(repository.deletedIds, [_videoId]);
    });

    test('treats a failed provider call as "kept" and still unlinks', () async {
      final repository = _repositoryFor([
        _location(ProviderType.localMediaStore, _mediaStoreOne),
        _location(ProviderType.selectedFolder, _safDocument),
      ]);
      final local = _RecordingDeleter(
        providerTypes: _localTypes,
        error: const UnexpectedError(diagnosticMessage: 'bridge down'),
      );

      final plan = (await _service(repository, [
        local,
      ]).plan(_item())).valueOrThrow;
      final outcome = (await _service(repository, [
        local,
      ]).remove(plan)).valueOrThrow;

      expect(outcome.deletedOriginals, 0);
      expect(outcome.undeletedOriginals, 2);
      expect(repository.deletedIds, [_videoId]);
    });

    test('does not trust a deleter that under-reports its batch', () async {
      final repository = _repositoryFor([
        _location(ProviderType.localMediaStore, _mediaStoreOne),
        _location(ProviderType.selectedFolder, _safDocument),
      ]);
      final local = _RecordingDeleter(
        providerTypes: _localTypes,
        // Claims one id and stays silent about the other.
        report: const SourceDeletionReport(deleted: [_mediaStoreOne]),
      );

      final plan = (await _service(repository, [
        local,
      ]).plan(_item())).valueOrThrow;
      final outcome = (await _service(repository, [
        local,
      ]).remove(plan)).valueOrThrow;

      // An unmentioned id must never be presented as deleted.
      expect(outcome.deletedOriginals, 1);
      expect(outcome.undeletedOriginals, 1);
    });

    test(
      'reports an error and keeps the record when deleteItem fails',
      () async {
        const deleteError = UnexpectedError(diagnosticMessage: 'db locked');
        final repository = FakeVideoRepository(
          locations: {
            _videoId: [_location(ProviderType.localMediaStore, _mediaStoreOne)],
          },
          deleteError: deleteError,
        );
        final local = _RecordingDeleter(providerTypes: _localTypes);
        final service = _service(repository, [local]);

        final plan = (await service.plan(_item())).valueOrThrow;
        final result = await service.remove(plan);

        switch (result) {
          case Err(:final error):
            expect(error, same(deleteError));
          case Ok():
            fail('expected the removal to fail');
        }
        // Originals are attempted first (ADR-017), so an Err means "files may be
        // gone but the row survived" — the opposite order would orphan files.
        expect(local.batches, [
          [_mediaStoreOne],
        ]);
        expect(repository.deletedIds, isEmpty);
      },
    );

    test('does not call a deleter when the plan only unlinks', () async {
      final repository = _repositoryFor([
        _location(ProviderType.directUrl, _directUrl),
      ]);
      final local = _RecordingDeleter(providerTypes: _localTypes);
      final service = _service(repository, [local]);

      final plan = (await service.plan(
        _item(primaryProvider: ProviderType.directUrl),
      )).valueOrThrow;
      final outcome = (await service.remove(plan)).valueOrThrow;

      expect(local.batches, isEmpty);
      expect(outcome.deletedOriginals, 0);
      expect(outcome.undeletedOriginals, 0);
      expect(outcome.isPartial, isFalse);
      expect(outcome.nothingDeleted, isFalse);
      expect(repository.deletedIds, [_videoId]);
    });

    test('reports a plan entry as kept when its deleter disappeared', () async {
      final repository = _repositoryFor([
        _location(ProviderType.localMediaStore, _mediaStoreOne),
      ]);
      final planning = _service(repository, [
        _RecordingDeleter(providerTypes: _localTypes),
      ]);
      final plan = (await planning.plan(_item())).valueOrThrow;
      expect(plan.isDestructive, isTrue);

      // The deleter registry lost the local family between plan and confirm.
      final outcome = (await _service(
        repository,
        const <ItemOriginalDeleter>[],
      ).remove(plan)).valueOrThrow;

      expect(outcome.deletedOriginals, 0);
      expect(outcome.undeletedOriginals, 1);
      expect(repository.deletedIds, [_videoId]);
    });
  });
}
