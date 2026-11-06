import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';

void main() {
  group('WebFormat', () {
    const h264 = WebFormat(
      formatId: '137',
      height: 1080,
      fps: 30,
      hasAudio: false,
      videoCodec: 'avc1.64001F',
      ext: 'mp4',
      sizeBytes: 1000,
    );
    const av1 = WebFormat(
      formatId: '399',
      height: 1080,
      fps: 60,
      hasAudio: false,
      videoCodec: 'av01.0.14M.08',
      ext: 'webm',
    );
    final aac = WebFormat(
      formatId: '140',
      hasVideo: false,
      audioCodec: 'mp4a.40.2',
      ext: 'm4a',
      sizeBytes: 500,
    );

    test('codec classification helpers', () {
      expect(h264.isH264, isTrue);
      expect(h264.isModernCodec, isFalse);
      expect(av1.isH264, isFalse);
      expect(av1.isModernCodec, isTrue);
      expect(aac.isAac, isTrue);
      expect(aac.isOpus, isFalse);
    });

    test('video-only / audio-only detection', () {
      expect(h264.isVideoOnly, isTrue);
      expect(h264.isAudioOnly, isFalse);
      expect(aac.isAudioOnly, isTrue);
    });

    test('unknown size stays null, not zero', () {
      expect(av1.sizeBytes, isNull);
    });

    test('value equality and hashCode', () {
      const same = WebFormat(
        formatId: '137',
        height: 1080,
        fps: 30,
        hasAudio: false,
        videoCodec: 'avc1.64001F',
        ext: 'mp4',
        sizeBytes: 1000,
      );
      expect(h264, equals(same));
      expect(h264.hashCode, same.hashCode);
      expect(h264, isNot(equals(av1)));
    });

    test('toString never prints a URL', () {
      expect(h264.toString(), contains('137'));
      expect(h264.toString(), isNot(contains('http')));
    });
  });

  group('WebMediaInfo', () {
    WebMediaInfo build({WebMediaKind kind = WebMediaKind.video}) =>
        WebMediaInfo(
          canonicalUrl: 'https://example.com/watch?v=SECRET&t=1',
          title: 'Demo',
          kind: kind,
          formats: const [
            WebFormat(formatId: 'a', height: 720, hasAudio: false),
            WebFormat(formatId: 'd', height: 1080, isDrm: true),
          ],
        );

    test('playableFormats drops DRM-only entries', () {
      final info = build();
      expect(info.hasDrmFormats, isTrue);
      expect(info.playableFormats.map((f) => f.formatId), ['a']);
    });

    test('toString redacts the query string', () {
      final info = build();
      expect(info.toString(), isNot(contains('SECRET')));
      expect(info.toString(), isNot(contains('v=')));
      expect(info.toString(), contains('example.com/watch'));
    });

    test('value equality includes formats and kind', () {
      expect(build(), equals(build()));
      expect(build(), isNot(equals(build(kind: WebMediaKind.live))));
    });
  });

  group('FormatChoice and FormatSelection', () {
    test('hasMergePair true only when both present', () {
      const both = FormatChoice(
        video: WebFormat(formatId: 'v', hasAudio: false),
        audio: WebFormat(formatId: 'a', hasVideo: false),
      );
      const muxed = FormatChoice(video: WebFormat(formatId: 'm'));
      expect(both.hasMergePair, isTrue);
      expect(muxed.hasMergePair, isFalse);
    });

    test('selection equality treats note sets order-independently', () {
      const a = FormatSelection(
        choice: FormatChoice(video: WebFormat(formatId: 'v')),
        container: OutputContainer.mp4,
        notes: {
          FormatSelectionNote.needsMerge,
          FormatSelectionNote.qualityLowered,
        },
      );
      const b = FormatSelection(
        choice: FormatChoice(video: WebFormat(formatId: 'v')),
        container: OutputContainer.mp4,
        notes: {
          FormatSelectionNote.qualityLowered,
          FormatSelectionNote.needsMerge,
        },
      );
      expect(a, equals(b));
      expect(a.hasNote(FormatSelectionNote.needsMerge), isTrue);
    });
  });

  group('DownloadDestination', () {
    test('distinct subtypes are never equal', () {
      const app = AppStorageDestination();
      const device = DeviceFolderDestination(DeviceFolderKind.movies);
      expect(app, isNot(equals(device)));
    });

    test('same-type destinations compare by their reference', () {
      const a = DeviceFolderDestination(DeviceFolderKind.music);
      const b = DeviceFolderDestination(DeviceFolderKind.music);
      const c = DeviceFolderDestination(DeviceFolderKind.movies);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));

      final p1 = PickedFolderDestination(
        Uri.parse('content://tree/document/primary%3ADownload'),
      );
      final p2 = PickedFolderDestination(
        Uri.parse('content://tree/document/primary%3ADownload'),
      );
      expect(p1, equals(p2));
    });

    test('SAF tree toString never prints the full grant URI', () {
      final picked = PickedFolderDestination(
        Uri.parse('content://com.android.externalstorage.documents/tree/prim'),
      );
      expect(picked.toString(), contains('content://'));
      expect(picked.toString(), isNot(contains('documents/tree/prim')));
    });

    test('OneDrive reference compares by folder id', () {
      const a = OneDriveDestination('fid');
      const b = OneDriveDestination('fid');
      expect(a, equals(b));
      expect(a.toString(), contains('fid'));
    });
  });

  group('Typed download errors (DL1.2)', () {
    test('every extractor error carries user-safe text and a diagnostic', () {
      const diag = 'ZZ_INTERNAL_DIAG_ZZ';
      final errors = <AppError>[
        const ExtractorUnavailableError(diagnosticMessage: diag),
        const ExtractorOutOfDateError(diagnosticMessage: diag),
        const UnsupportedSiteError(diagnosticMessage: diag),
        const LoginRequiredError(diagnosticMessage: diag),
        const PrivateOrRemovedError(diagnosticMessage: diag),
        const AgeRestrictedError(diagnosticMessage: diag),
        const GeoBlockedError(diagnosticMessage: diag),
        const DrmProtectedError(diagnosticMessage: diag),
        const LiveStreamUnsupportedError(diagnosticMessage: diag),
        const PlaylistUnsupportedError(diagnosticMessage: diag),
        const DestinationUnavailableError(diagnosticMessage: diag),
        const LowStorageError(diagnosticMessage: diag),
        const PostProcessingFailedError(diagnosticMessage: diag),
        const DownloadCancelledError(diagnosticMessage: diag),
        const CookiesExpiredError(diagnosticMessage: diag),
      ];
      for (final e in errors) {
        expect(e.userMessage, isNotEmpty);
        expect(e.diagnosticMessage, diag);
        // Diagnostic detail never leaks into the shown message.
        expect(e.userMessage, isNot(contains(diag)));
      }
    });

    test('errors are AppError subtypes usable in Result<T>', () {
      final Result<AppError> r = Result.err(
        const DrmProtectedError(diagnosticMessage: 'widevine'),
      );
      expect(r, isA<Err<AppError>>());
    });
  });
}
