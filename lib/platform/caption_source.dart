import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

/// A sidecar subtitle file the user picked, already read to text (VP4.3).
///
/// Only the display [name] and the raw contents travel back to Dart — never a
/// durable URI, and the text carries no credentials, so it is safe to parse and
/// hand to the caption pipeline.
class PickedSidecar {
  const PickedSidecar({required this.name, required this.text});

  /// The file's display name, shown in the sheet so the choice is legible.
  final String name;

  /// The file's text, which the domain parser turns into cues.
  final String text;
}

/// Opens the system document picker and reads a chosen `.srt` / `.vtt` file.
///
/// Its own narrow interface rather than a method on [SafBridge]: the folder
/// bridge is about video *folders* and its many test doubles should not have to
/// grow a subtitle concern. The concrete implementation is a Kotlin method
/// channel; tests and non-Android hosts supply a fake.
abstract interface class CaptionSource {
  /// Returns the picked file, or `null` when the user cancelled.
  Future<Result<PickedSidecar?>> pickAndRead();
}

/// Method-channel [CaptionSource] backed by `CaptionsPlugin` (Android).
///
/// Device-only behaviour: the picker and the content-resolver read live in
/// Kotlin, so this class is exercised on a real device, not in the unit suite
/// (where an injected fake stands in for it). On a host without the plugin the
/// channel throws and the failure is reported as an ordinary error state.
class MethodChannelCaptionSource implements CaptionSource {
  const MethodChannelCaptionSource();

  static const _channel = MethodChannel('com.example.mytube/captions');

  @override
  Future<Result<PickedSidecar?>> pickAndRead() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
        'pickSidecar',
      );
      if (raw == null) return Result.ok(null);
      final name = raw['name'] as String? ?? 'subtitles';
      final text = raw['text'] as String? ?? '';
      return Result.ok(PickedSidecar(name: name, text: text));
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'Captions pickSidecar platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } on MissingPluginException {
      // Unsupported host (desktop, or a build without the plugin): no picker,
      // reported as a plain error the sheet can surface rather than a crash.
      return Result.err(
        const UnexpectedError(
          diagnosticMessage: 'Captions picker is unavailable on this device.',
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'Captions pickSidecar unexpected error: $e',
          cause: e,
        ),
      );
    }
  }
}

/// Injected [CaptionSource]; overridden in tests and on unsupported hosts.
final captionSourceProvider = Provider<CaptionSource>(
  (ref) => const MethodChannelCaptionSource(),
);
