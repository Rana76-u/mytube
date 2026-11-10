import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Google Drive video source.
///
/// Drive file IDs are the durable source identities. Playback uses the Drive
/// API media endpoint with a short-lived authorization header, never a stored
/// download URL.
class GoogleDriveAdapter
    implements VideoSourceAdapter, SearchableVideoSourceAdapter {
  const GoogleDriveAdapter({required GoogleDriveApi api})
    : _api = api; // ignore: prefer_initializing_formals

  static const _videoExtensions = {
    '3g2',
    '3gp',
    'avi',
    'flv',
    'm2ts',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpe',
    'mpeg',
    'mpg',
    'mts',
    'ogv',
    'ts',
    'webm',
    'wmv',
  };

  static const _mimeTypeQuery = "mimeType contains 'video/'";

  final GoogleDriveApi _api;

  static String get _videoQuery => "($_mimeTypeQuery or $_extensionQuery)";

  @override
  ProviderType get sourceType => ProviderType.googleDrive;

  @override
  Future<SourceCapabilities> getCapabilities() async =>
      const SourceCapabilities(
        canStream: true,
        canSeek: true,
        canProvideThumbnail: true,
        canSearch: true,
        canDownload: true,
        supportsPagination: false,
      );

  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) {
    if (continuationToken != null) {
      return Future.value(
        const Err(
          UnexpectedError(
            diagnosticMessage:
                'Google Drive full listing does not accept a continuation '
                'token',
          ),
        ),
      );
    }
    return _list(_videoQuery, cancellationToken);
  }

  @override
  Future<Result<SourcePage>> searchVideos(
    String query, {
    required CancellationToken cancellationToken,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || cancellationToken.isCancelled) {
      return Future.value(const Ok(SourcePage(videos: [])));
    }
    final escapedQuery = normalizedQuery
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'");
    final searchQuery =
        '$_videoQuery and (name contains \'$escapedQuery\' or '
        'fullText contains \'$escapedQuery\')';
    return _list(searchQuery, cancellationToken);
  }

  Future<Result<SourcePage>> _list(
    String query,
    CancellationToken cancellationToken,
  ) async {
    final videos = <SourceVideo>[];
    final seenFileIds = <String>{};
    final seenPageTokens = <String>{};
    String? pageToken;

    while (!cancellationToken.isCancelled) {
      final pageResult = await _api.listFiles(
        query: query,
        pageToken: pageToken,
      );
      final Map<String, dynamic> page;
      switch (pageResult) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          page = value;
      }

      final files = page['files'];
      if (files is! List) {
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Google Drive list response has no files',
          ),
        );
      }
      for (final value in files) {
        if (cancellationToken.isCancelled) {
          return Ok(SourcePage(videos: videos));
        }
        if (value is! Map<String, dynamic>) continue;
        final fileId = value['id'];
        if (fileId is! String ||
            !_isValidSourceId(fileId) ||
            !seenFileIds.add(fileId) ||
            !_isVideoFile(value)) {
          continue;
        }
        videos.add(_toSourceVideo(value));
      }

      final nextToken = page['nextPageToken'];
      if (nextToken == null) break;
      if (nextToken is! String ||
          nextToken.isEmpty ||
          !seenPageTokens.add(nextToken)) {
        return const Err(
          UnexpectedError(
            diagnosticMessage:
                'Google Drive returned an invalid or repeated page token',
          ),
        );
      }
      pageToken = nextToken;
    }
    return Ok(SourcePage(videos: videos));
  }

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async {
    if (!_isValidSourceId(sourceId)) return const Ok(null);
    final result = await _api.getFile(sourceId);
    switch (result) {
      case Err(:final error) when error is NotFoundError:
        return const Ok(null);
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        if (value['id'] != sourceId || !_isVideoFile(value)) {
          if (value['id'] != sourceId) {
            return const Err(
              UnexpectedError(
                diagnosticMessage:
                    'Google Drive returned a mismatched file identity',
              ),
            );
          }
          return const Ok(null);
        }
        return Ok(_toSourceVideo(value));
    }
  }

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async {
    final result = await getVideo(sourceId);
    return switch (result) {
      Err(:final error) => switch (error) {
        AuthenticationRequiredError() => const Ok(
          AvailabilityState.reconnectRequired,
        ),
        PermissionDeniedError() => const Ok(
          AvailabilityState.permissionRevoked,
        ),
        NetworkUnavailableError() => const Ok(AvailabilityState.offline),
        _ => Err(error),
      },
      Ok(value: null) => const Ok(AvailabilityState.missing),
      Ok(value: final video) => Ok(
        video?.availability ?? AvailabilityState.missing,
      ),
    };
  }

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async {
    if (!_isValidSourceId(sourceId)) {
      return const Err(
        NotFoundError(diagnosticMessage: 'Invalid Google Drive file identity'),
      );
    }
    final result = await _api.getFile(sourceId);
    final Map<String, dynamic> file;
    switch (result) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        file = value;
    }
    if (file['id'] != sourceId) {
      return const Err(
        UnexpectedError(
          diagnosticMessage: 'Google Drive returned a mismatched file identity',
        ),
      );
    }
    if (!_isVideoFile(file)) {
      return const Err(
        UnsupportedFormatError(
          diagnosticMessage: 'Google Drive item is not a video file',
        ),
      );
    }

    final tokenResult = await _api.accessToken();
    final String token;
    switch (tokenResult) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        token = value;
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${Uri.encodeComponent(sourceId)}',
      const {'alt': 'media', 'supportsAllDrives': 'true'},
    );
    return Ok(
      PlayableSource(
        uri: uri,
        sourceId: sourceId,
        sourceType: ProviderType.googleDrive,
        mimeType: _stringValue(file['mimeType']),
        canSeek: true,
        httpHeaders: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async {
    final result = await _api.getFile(sourceId);
    return switch (result) {
      Err(:final error) => Err(error),
      Ok(:final value) => switch (value['capabilities']) {
        {'canDownload': true} => const Ok(DownloadEligibility.eligible),
        {'canDownload': false} => const Ok(DownloadEligibility.prohibited),
        _ => const Ok(DownloadEligibility.unknown),
      },
    };
  }

  bool _isVideoFile(Map<String, dynamic> file) {
    final mimeType = _stringValue(file['mimeType']);
    if (mimeType != null && mimeType.toLowerCase().startsWith('video/')) {
      return true;
    }
    final name = _stringValue(file['name']);
    if (name == null || !name.contains('.')) return false;
    return _videoExtensions.contains(name.split('.').last.toLowerCase());
  }

  SourceVideo _toSourceVideo(Map<String, dynamic> file) {
    final videoMetadata = file['videoMediaMetadata'];
    final metadata = videoMetadata is Map<String, dynamic>
        ? videoMetadata
        : const <String, dynamic>{};
    final fileId = file['id'] as String;
    final name = _stringValue(file['name']);
    return SourceVideo(
      sourceId: fileId,
      sourceType: ProviderType.googleDrive,
      displayName: name == null || name.isEmpty ? 'Google Drive video' : name,
      mimeType: _stringValue(file['mimeType']),
      sizeBytes: _intValue(file['size']),
      durationMs: _intValue(metadata['durationMillis']),
      widthPx: _intValue(metadata['width']),
      heightPx: _intValue(metadata['height']),
      availability: AvailabilityState.available,
    );
  }

  bool _isValidSourceId(String sourceId) =>
      sourceId.isNotEmpty &&
      sourceId.length <= 256 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(sourceId);

  String? _stringValue(Object? value) => value is String ? value : null;

  int? _intValue(Object? value) => switch (value) {
    int number => number,
    String text => int.tryParse(text),
    _ => null,
  };

  static String get _extensionQuery => _videoExtensions
      .map((extension) => "name contains '.$extension'")
      .join(' or ');
}
