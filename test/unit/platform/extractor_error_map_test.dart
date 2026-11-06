import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/extractor/extractor_error_map.dart';

void main() {
  group('ExtractorErrorMap.decode', () {
    test('every documented code maps to its typed error', () {
      final cases = <String, Type>{
        ExtractorErrorMap.unavailable: ExtractorUnavailableError,
        ExtractorErrorMap.outOfDate: ExtractorOutOfDateError,
        ExtractorErrorMap.unsupportedSite: UnsupportedSiteError,
        ExtractorErrorMap.loginRequired: LoginRequiredError,
        ExtractorErrorMap.privateOrRemoved: PrivateOrRemovedError,
        ExtractorErrorMap.ageRestricted: AgeRestrictedError,
        ExtractorErrorMap.geoBlocked: GeoBlockedError,
        ExtractorErrorMap.drmProtected: DrmProtectedError,
        ExtractorErrorMap.liveUnsupported: LiveStreamUnsupportedError,
        ExtractorErrorMap.playlistUnsupported: PlaylistUnsupportedError,
        ExtractorErrorMap.destinationUnavailable: DestinationUnavailableError,
        ExtractorErrorMap.lowStorage: LowStorageError,
        ExtractorErrorMap.postProcessingFailed: PostProcessingFailedError,
        ExtractorErrorMap.cancelled: DownloadCancelledError,
        ExtractorErrorMap.rateLimited: RateLimitError,
        ExtractorErrorMap.cookiesExpired: CookiesExpiredError,
        ExtractorErrorMap.network: NetworkUnavailableError,
      };
      for (final e in cases.entries) {
        final err = ExtractorErrorMap.decode(e.key, detail: 'x');
        expect(err.runtimeType, e.value, reason: e.key);
      }
    });

    test('unknown and null codes fall back to UnexpectedError', () {
      expect(ExtractorErrorMap.decode('SOMETHING_NEW'), isA<UnexpectedError>());
      expect(ExtractorErrorMap.decode(null), isA<UnexpectedError>());
    });

    test('user messages never carry the diagnostic detail', () {
      final err = ExtractorErrorMap.decode(
        ExtractorErrorMap.loginRequired,
        detail: 'ZZ_DIAGZZ',
      );
      expect(err.userMessage, isNot(contains('ZZ_DIAGZZ')));
      expect(err.diagnosticMessage, contains('ZZ_DIAGZZ'));
    });

    test('a missing detail still yields a readable diagnostic', () {
      expect(
        ExtractorErrorMap.decode(
          ExtractorErrorMap.geoBlocked,
        ).diagnosticMessage,
        isNotEmpty,
      );
    });
  });
}
