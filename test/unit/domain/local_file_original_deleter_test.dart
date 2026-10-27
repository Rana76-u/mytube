import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/local_file_original_deleter.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';

/// ADR-017: local originals are one family with two owners — MediaStore rows
/// (deleted through the OS confirmation flow) and SAF documents (deleted through
/// the folder grant). The deleter routes by id scheme and never lets one owner's
/// failure hide the other's success.

const _mediaStoreOne = 'content://media/external/video/media/1';
const _mediaStoreTwo = 'content://media/external/video/media/2';
const _safOne =
    'content://com.android.externalstorage.documents/tree/primary%3AMovies/'
    'document/primary%3AMovies%2Fa.mp4';

class _FakeMediaStore implements MediaStoreBridge {
  _FakeMediaStore({this.report, this.error, this.throws = false});

  /// Fixed answer; when null every requested id is reported deleted.
  final SourceDeletionReport? report;

  /// When set, the call returns this error.
  final AppError? error;

  /// When true, the call throws instead of answering (a dead channel).
  final bool throws;

  final List<List<String>> batches = <List<String>>[];

  @override
  Future<Result<SourceDeletionReport>> deleteVideos(
    List<String> contentUris,
  ) async {
    batches.add(List<String>.of(contentUris));
    if (throws) throw StateError('channel closed');
    if (error case final error?) return Result.err(error);
    return Result.ok(
      report ?? SourceDeletionReport(deleted: List<String>.of(contentUris)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeSaf implements SafBridge {
  _FakeSaf({this.report, this.error, this.throws = false});

  final SourceDeletionReport? report;
  final AppError? error;
  final bool throws;

  final List<List<String>> batches = <List<String>>[];

  @override
  Future<Result<SourceDeletionReport>> deleteDocuments(
    List<String> uris,
  ) async {
    batches.add(List<String>.of(uris));
    if (throws) throw StateError('channel closed');
    if (error case final error?) return Result.err(error);
    return Result.ok(
      report ?? SourceDeletionReport(deleted: List<String>.of(uris)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('LocalFileOriginalDeleter (ADR-017)', () {
    test(
      'routes MediaStore ids and SAF documents to their own bridge',
      () async {
        final mediaStore = _FakeMediaStore();
        final saf = _FakeSaf();
        final deleter = LocalFileOriginalDeleter(
          mediaStore: mediaStore,
          saf: saf,
        );

        final report = (await deleter.deleteOriginals([
          _mediaStoreOne,
          _safOne,
          _mediaStoreTwo,
        ])).valueOrThrow;

        expect(mediaStore.batches, [
          [_mediaStoreOne, _mediaStoreTwo],
        ]);
        expect(saf.batches, [
          [_safOne],
        ]);
        expect(report.deleted, [_mediaStoreOne, _mediaStoreTwo, _safOne]);
        expect(report.isComplete, isTrue);
      },
    );

    test('merges both bridges into one per-id report', () async {
      final mediaStore = _FakeMediaStore();
      final saf = _FakeSaf(
        report: const SourceDeletionReport(failed: [_safOne]),
      );
      final deleter = LocalFileOriginalDeleter(
        mediaStore: mediaStore,
        saf: saf,
      );

      final report = (await deleter.deleteOriginals([
        _mediaStoreOne,
        _safOne,
      ])).valueOrThrow;

      expect(report.deleted, [_mediaStoreOne]);
      expect(report.failed, [_safOne]);
      expect(report.total, 2);
      expect(report.isComplete, isFalse);
    });

    test(
      'reports a MediaStore failure as kept while SAF still answers',
      () async {
        final mediaStore = _FakeMediaStore(
          error: const UnexpectedError(diagnosticMessage: 'no write access'),
        );
        final saf = _FakeSaf();
        final deleter = LocalFileOriginalDeleter(
          mediaStore: mediaStore,
          saf: saf,
        );

        final report = (await deleter.deleteOriginals([
          _mediaStoreOne,
          _safOne,
        ])).valueOrThrow;

        // A failed batch is a per-id fact, not an error for the whole family.
        expect(report.deleted, [_safOne]);
        expect(report.failed, [_mediaStoreOne]);
      },
    );

    test(
      'reports a SAF failure as kept while MediaStore still answers',
      () async {
        final mediaStore = _FakeMediaStore();
        final saf = _FakeSaf(
          error: const UnexpectedError(diagnosticMessage: 'grant revoked'),
        );
        final deleter = LocalFileOriginalDeleter(
          mediaStore: mediaStore,
          saf: saf,
        );

        final report = (await deleter.deleteOriginals([
          _mediaStoreOne,
          _safOne,
        ])).valueOrThrow;

        expect(report.deleted, [_mediaStoreOne]);
        expect(report.failed, [_safOne]);
      },
    );

    test('passes a partial MediaStore batch through unchanged', () async {
      final mediaStore = _FakeMediaStore(
        report: const SourceDeletionReport(
          deleted: [_mediaStoreOne],
          failed: [_mediaStoreTwo],
        ),
      );
      final saf = _FakeSaf();
      final deleter = LocalFileOriginalDeleter(
        mediaStore: mediaStore,
        saf: saf,
      );

      final report = (await deleter.deleteOriginals([
        _mediaStoreOne,
        _mediaStoreTwo,
      ])).valueOrThrow;

      expect(report.deleted, [_mediaStoreOne]);
      expect(report.failed, [_mediaStoreTwo]);
      expect(report.isComplete, isFalse);
    });

    test('reports a throwing bridge as kept rather than failing', () async {
      final mediaStore = _FakeMediaStore(throws: true);
      final saf = _FakeSaf(throws: true);
      final deleter = LocalFileOriginalDeleter(
        mediaStore: mediaStore,
        saf: saf,
      );

      final report = (await deleter.deleteOriginals([
        _mediaStoreOne,
        _safOne,
      ])).valueOrThrow;

      expect(report.deleted, isEmpty);
      expect(report.failed, [_mediaStoreOne, _safOne]);
      expect(report.isComplete, isFalse);
    });

    test('does not call a bridge with nothing to delete', () async {
      final mediaStore = _FakeMediaStore();
      final saf = _FakeSaf();
      final deleter = LocalFileOriginalDeleter(
        mediaStore: mediaStore,
        saf: saf,
      );

      final report = (await deleter.deleteOriginals([_safOne])).valueOrThrow;

      expect(mediaStore.batches, isEmpty);
      expect(saf.batches, hasLength(1));
      expect(report.deleted, [_safOne]);
    });

    test('declares exactly the two local provider types', () async {
      final deleter = LocalFileOriginalDeleter(
        mediaStore: _FakeMediaStore(),
        saf: _FakeSaf(),
      );

      expect(
        deleter.providerTypes.toList()..sort((a, b) => a.index - b.index),
        [ProviderType.localMediaStore, ProviderType.selectedFolder],
      );
    });
  });

  group('SourceDeletionReport', () {
    test('counts what it accounts for and whether anything was kept', () {
      const report = SourceDeletionReport(deleted: ['a', 'b'], failed: ['c']);

      expect(report.total, 3);
      expect(report.isComplete, isFalse);
      expect(const SourceDeletionReport().total, 0);
      expect(const SourceDeletionReport().isComplete, isTrue);
    });

    test('merge keeps both sides of two batches', () {
      const first = SourceDeletionReport(deleted: ['a']);
      const second = SourceDeletionReport(deleted: ['b'], failed: ['c']);

      final merged = first.merge(second);

      expect(merged.deleted, ['a', 'b']);
      expect(merged.failed, ['c']);
      expect(merged.total, 3);
    });
  });
}
