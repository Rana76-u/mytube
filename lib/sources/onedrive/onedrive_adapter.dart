import 'dart:collection';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/onedrive/onedrive_graph_api.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Read-only video source adapter for the owner's Microsoft OneDrive account.
///
/// Durable source IDs are `<driveId>/<itemId>`. Playback URLs are requested
/// when needed and returned only in-memory; OneDrive's pre-authorized download
/// URLs are never stored as source identity or exposed in diagnostics.
class OneDriveAdapter
    implements VideoSourceAdapter, SearchableVideoSourceAdapter {
  const OneDriveAdapter({required OneDriveGraphApi graphApi})
    : _graphApi = graphApi; // ignore: prefer_initializing_formals

  final OneDriveGraphApi _graphApi;

  @override
  ProviderType get sourceType => ProviderType.oneDrive;

  @override
  Future<SourceCapabilities> getCapabilities() async =>
      const SourceCapabilities(
        canStream: true,
        canSeek: true,
        canProvideThumbnail: false,
        canSearch: true,
        canDownload: true,
        supportsPagination: false,
      );

  /// Lists video files throughout the connected drive, following Graph's
  /// server-provided paging links and walking child folders.
  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return const Ok(SourcePage(videos: []));
    }
    if (continuationToken != null) {
      return const Err(
        UnexpectedError(
          diagnosticMessage:
              'OneDrive full-drive listing does not accept a continuation '
              'token',
        ),
      );
    }
    final driveResult = await _graphApi.get('/me/drive');
    final Map<String, dynamic> drive;
    switch (driveResult) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        drive = value;
    }
    final driveId = drive['id'];
    if (driveId is! String || driveId.isEmpty) {
      return const Err(
        UnexpectedError(
          diagnosticMessage: 'Microsoft Graph drive response has no ID',
        ),
      );
    }

    final videos = <SourceVideo>[];
    final folders = Queue<String>()..add('');
    final visitedFolders = <String>{};
    final visitedItems = <String>{};
    while (folders.isNotEmpty) {
      if (cancellationToken.isCancelled) {
        return Ok(SourcePage(videos: videos));
      }
      final folderId = folders.removeFirst();
      if (!visitedFolders.add(folderId)) continue;
      var pageResult = await _graphApi.get(
        folderId.isEmpty
            ? '/drives/${Uri.encodeComponent(driveId)}/root/children'
            : '/drives/${Uri.encodeComponent(driveId)}/items/'
                  '${Uri.encodeComponent(folderId)}/children',
        queryParameters: const {
          r'$select': 'id,name,size,file,folder,video,parentReference',
          r'$top': '200',
        },
      );
      final visitedPageLinks = <String>{};
      while (true) {
        if (cancellationToken.isCancelled) {
          return Ok(SourcePage(videos: videos));
        }
        final Map<String, dynamic> page;
        switch (pageResult) {
          case Err(:final error):
            return Err(error);
          case Ok(:final value):
            page = value;
        }
        final values = page['value'];
        if (values is! List) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Microsoft Graph drive page has no items',
            ),
          );
        }
        for (final value in values) {
          if (cancellationToken.isCancelled) {
            return Ok(SourcePage(videos: videos));
          }
          if (value is! Map<String, dynamic>) continue;
          final itemId = value['id'];
          if (itemId is! String || itemId.isEmpty) continue;
          final folder = value['folder'];
          if (folder is Map<String, dynamic>) {
            folders.add(itemId);
            continue;
          }
          if (!visitedItems.add(itemId) || !_isVideoFile(value)) continue;
          videos.add(_toSourceVideo(value, driveId));
        }
        final nextLink = page['@odata.nextLink'];
        if (nextLink == null) break;
        if (nextLink is! String) {
          return const Err(
            UnexpectedError(
              diagnosticMessage:
                  'Microsoft Graph returned an invalid next-page link',
            ),
          );
        }
        final uri = Uri.tryParse(nextLink);
        if (uri == null || !visitedPageLinks.add(uri.toString())) {
          return const Err(
            UnexpectedError(
              diagnosticMessage:
                  'Microsoft Graph returned an invalid or repeated page link',
            ),
          );
        }
        pageResult = await _graphApi.getNextPage(uri);
      }
    }
    return Ok(SourcePage(videos: videos));
  }

  /// Searches files through Graph's OneDrive search endpoint.
  ///
  /// Search results are collected across all response pages before being
  /// returned so callers do not accidentally treat a partial result as a full
  /// provider scan.
  @override
  Future<Result<SourcePage>> searchVideos(
    String query, {
    required CancellationToken cancellationToken,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || cancellationToken.isCancelled) {
      return const Ok(SourcePage(videos: []));
    }
    final driveResult = await _graphApi.get('/me/drive');
    final String driveId;
    switch (driveResult) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final id = value['id'];
        if (id is! String || id.isEmpty) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Microsoft Graph drive response has no ID',
            ),
          );
        }
        driveId = id;
    }
    final escapedQuery = normalizedQuery.replaceAll("'", "''");
    final encodedQuery = Uri.encodeComponent(
      escapedQuery,
    ).replaceAll("'", '%27');
    var pageResult = await _graphApi.get(
      '/drives/${Uri.encodeComponent(driveId)}/root/search'
      "(q='$encodedQuery')",
      queryParameters: const {
        r'$select': 'id,name,size,file,folder,video,parentReference',
        r'$top': '200',
      },
    );
    final videos = <SourceVideo>[];
    final seen = <String>{};
    final visitedPageLinks = <String>{};
    while (!cancellationToken.isCancelled) {
      final Map<String, dynamic> page;
      switch (pageResult) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          page = value;
      }
      final values = page['value'];
      if (values is! List) {
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Microsoft Graph search page has no items',
          ),
        );
      }
      for (final value in values) {
        if (cancellationToken.isCancelled) break;
        if (value is! Map<String, dynamic> ||
            !_isVideoFile(value) ||
            value['id'] is! String ||
            !seen.add(value['id'] as String)) {
          continue;
        }
        videos.add(_toSourceVideo(value, driveId));
      }
      final nextLink = page['@odata.nextLink'];
      if (nextLink == null) break;
      if (nextLink is! String) {
        return const Err(
          UnexpectedError(
            diagnosticMessage:
                'Microsoft Graph returned an invalid next-page link',
          ),
        );
      }
      final uri = Uri.tryParse(nextLink);
      if (uri == null || !visitedPageLinks.add(uri.toString())) {
        return const Err(
          UnexpectedError(
            diagnosticMessage:
                'Microsoft Graph returned an invalid or repeated page link',
          ),
        );
      }
      pageResult = await _graphApi.getNextPage(uri);
    }
    return Ok(SourcePage(videos: videos));
  }

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async {
    final identity = _parseSourceId(sourceId);
    if (identity == null) return const Ok(null);
    final result = await _graphApi.get(_itemPath(identity));
    switch (result) {
      case Err<Map<String, dynamic>>(:final error) when error is NotFoundError:
        return const Ok(null);
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        if (value['id'] is! String) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Microsoft Graph item response has no ID',
            ),
          );
        }
        if (!_isVideoFile(value)) return const Ok(null);
        return Ok(_toSourceVideo(value, identity.driveId));
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
    final identity = _parseSourceId(sourceId);
    if (identity == null) {
      return const Err(
        NotFoundError(diagnosticMessage: 'Invalid OneDrive source identity'),
      );
    }
    final result = await _graphApi.get(_itemPath(identity));
    switch (result) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        if (value['id'] is! String) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Microsoft Graph item response has no ID',
            ),
          );
        }
        if (!_isVideoFile(value)) {
          return const Err(
            UnsupportedFormatError(
              diagnosticMessage: 'OneDrive item is not a video file',
            ),
          );
        }
        final downloadUrl = value['@microsoft.graph.downloadUrl'];
        final uri = downloadUrl is String ? Uri.tryParse(downloadUrl) : null;
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return const Err(
            PermissionDeniedError(
              userMessage:
                  'OneDrive could not provide a playable file. Check file '
                  'access and reconnect if needed.',
              diagnosticMessage:
                  'OneDrive item response did not contain a valid temporary '
                  'download URL',
            ),
          );
        }
        final video = _toSourceVideo(value, identity.driveId);
        return Ok(
          PlayableSource(
            uri: uri,
            sourceId: sourceId,
            sourceType: ProviderType.oneDrive,
            mimeType: video.mimeType,
            canSeek: true,
          ),
        );
    }
  }

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async {
    final result = await getVideo(sourceId);
    return switch (result) {
      Err(:final error) => Err(error),
      Ok(value: final video) => Ok(
        video?.availability == AvailabilityState.available
            ? DownloadEligibility.eligible
            : DownloadEligibility.unknown,
      ),
    };
  }

  bool _isVideoFile(Map<String, dynamic> item) {
    if (item['file'] is! Map<String, dynamic>) return false;
    final file = item['file'] as Map<String, dynamic>;
    final mimeType = file['mimeType'];
    if (mimeType is String && mimeType.toLowerCase().startsWith('video/')) {
      return true;
    }
    final name = item['name'];
    if (name is! String) return false;
    final extension = name.split('.').last.toLowerCase();
    return const {
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
    }.contains(extension);
  }

  SourceVideo _toSourceVideo(Map<String, dynamic> item, String driveId) {
    final file = item['file'];
    final video = item['video'];
    final mimeType = file is Map<String, dynamic> ? file['mimeType'] : null;
    final size = item['size'];
    final duration = video is Map<String, dynamic> ? video['duration'] : null;
    final width = video is Map<String, dynamic> ? video['width'] : null;
    final height = video is Map<String, dynamic> ? video['height'] : null;
    final itemId = item['id'] as String;
    final name = item['name'];
    final parentReference = item['parentReference'];
    final itemDriveId =
        parentReference is Map<String, dynamic> &&
            parentReference['driveId'] is String
        ? parentReference['driveId'] as String
        : driveId;
    return SourceVideo(
      sourceId: _sourceId(itemDriveId, itemId),
      sourceType: ProviderType.oneDrive,
      displayName: name is String && name.isNotEmpty ? name : 'OneDrive video',
      mimeType: mimeType is String ? mimeType : null,
      sizeBytes: size is int ? size : null,
      durationMs: duration is int ? duration : null,
      widthPx: width is int ? width : null,
      heightPx: height is int ? height : null,
      availability: AvailabilityState.available,
    );
  }

  String _itemPath(_OneDriveItemIdentity identity) =>
      '/drives/${Uri.encodeComponent(identity.driveId)}/items/'
      '${Uri.encodeComponent(identity.itemId)}';

  String _sourceId(String driveId, String itemId) => '$driveId/$itemId';

  _OneDriveItemIdentity? _parseSourceId(String sourceId) {
    final separator = sourceId.indexOf('/');
    if (separator <= 0 ||
        separator == sourceId.length - 1 ||
        sourceId.indexOf('/', separator + 1) != -1) {
      return null;
    }
    return _OneDriveItemIdentity(
      driveId: sourceId.substring(0, separator),
      itemId: sourceId.substring(separator + 1),
    );
  }
}

class _OneDriveItemIdentity {
  const _OneDriveItemIdentity({required this.driveId, required this.itemId});

  final String driveId;
  final String itemId;
}
