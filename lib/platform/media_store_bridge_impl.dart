import 'package:flutter/services.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/platform/deletion_report_mapping.dart';
import 'package:mytube/platform/media_store_bridge.dart';

/// Concrete [MediaStoreBridge] that communicates with [MediaStorePlugin] on
/// the Android side via a MethodChannel (P3-01).
class MediaStoreBridgeImpl implements MediaStoreBridge {
  static const _channel = MethodChannel('com.example.mytube/media_store');

  @override
  Future<Result<List<MediaStoreVideo>>> queryVideos() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('queryVideos');
      final list = (raw ?? []).map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return MediaStoreVideo(
          mediaStoreId: map['mediaStoreId'] as String,
          contentUri: map['contentUri'] as String,
          displayName: map['displayName'] as String,
          durationMs: (map['durationMs'] as num?)?.toInt(),
          widthPx: (map['widthPx'] as num?)?.toInt(),
          heightPx: (map['heightPx'] as num?)?.toInt(),
          mimeType: map['mimeType'] as String?,
          sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
          dateAddedSeconds: (map['dateAddedSeconds'] as num?)?.toInt(),
          dateModifiedSeconds: (map['dateModifiedSeconds'] as num?)?.toInt(),
        );
      }).toList();
      return Result.ok(list);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        return Result.err(
          PermissionDeniedError(
            diagnosticMessage: 'MediaStore queryVideos: ${e.message}',
          ),
        );
      }
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'MediaStore queryVideos platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'MediaStore queryVideos unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<MediaStorePermissionStatus> checkPermission() async {
    try {
      final status = await _channel.invokeMethod<String>('checkPermission');
      return _parsePermissionStatus(status);
    } catch (_) {
      return MediaStorePermissionStatus.denied;
    }
  }

  @override
  Future<MediaStorePermissionStatus> requestPermission() async {
    try {
      final status = await _channel.invokeMethod<String>('requestPermission');
      return _parsePermissionStatus(status);
    } catch (_) {
      return MediaStorePermissionStatus.denied;
    }
  }

  @override
  Future<Result<SourceDeletionReport>> deleteVideos(
    List<String> contentUris,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('deleteVideos', {
        'contentUris': contentUris,
      });
      return Result.ok(parseSourceDeletionReport(raw, contentUris));
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'MediaStore deleteVideos platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'MediaStore deleteVideos unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  MediaStorePermissionStatus _parsePermissionStatus(String? status) {
    return switch (status) {
      'granted' => MediaStorePermissionStatus.granted,
      'partiallyGranted' => MediaStorePermissionStatus.partiallyGranted,
      'permanentlyDenied' => MediaStorePermissionStatus.permanentlyDenied,
      _ => MediaStorePermissionStatus.denied,
    };
  }
}

// Suppress unused-import warning for AvailabilityState until the source
// adapter (P3-03) wires it up.
// ignore: unused_element
AvailabilityState _unusedAvailabilityRef() => AvailabilityState.available;
