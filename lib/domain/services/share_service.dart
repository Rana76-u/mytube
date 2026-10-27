import 'package:flutter/services.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/share_bridge.dart';

/// What actually happened when the user asked to share an item, so the caller
/// can show the right feedback without inspecting URIs (plan M8).
enum ShareOutcome {
  /// A direct-URL item: its link was copied to the clipboard.
  linkCopied,

  /// A local / file-based item: the system share sheet was opened.
  sheetOpened,

  /// Nothing could be shared — no source, no clipboard, or no native bridge.
  unavailable,
}

/// Shares a library item using only capabilities the app already has (plan M8).
///
/// Two paths, chosen by what the item actually is:
///  * **direct URL** — the source is a durable, publicly addressable link, so
///    copying it to the clipboard is the whole job and needs no platform code;
///  * **local / SAF / cloud-file** — the source is a `content://` / `file://`
///    URI the receiving app cannot resolve without a temporary read grant, so
///    it goes through [ShareBridge] (`Intent.ACTION_SEND` +
///    `FLAG_GRANT_READ_URI_PERMISSION`).
///
/// Nothing here logs or returns a raw URI: a failure is reported as
/// [ShareOutcome.unavailable] and the caller shows a user-safe message
/// (AGENTS privacy rules).
class ShareService {
  ShareService({required this.repository, required this.bridge});

  final VideoRepository repository;
  final ShareBridge bridge;

  /// Shares the item with [id] and reports what happened.
  Future<ShareOutcome> share(VideoItemId id) async {
    final locations = switch (await repository.getSourceLocationsForVideo(id)) {
      Ok(:final value) => value,
      // A repository failure is indistinguishable to the user from "nothing to
      // share", so both take the same safe path.
      Err() => const <SourceLocation>[],
    };
    if (locations.isEmpty) return ShareOutcome.unavailable;

    // The primary location is the durable identity of the item (P7-05); the
    // list is already ordered primary-first.
    final uri = locations.first.sourceUri.trim();
    if (uri.isEmpty) return ShareOutcome.unavailable;

    if (_isWebUrl(uri)) return _copyLink(uri);

    // Only file-ish schemes can be granted to another app; anything else (a
    // provider-private token, say) stays unshared rather than leaking it.
    if (!_isShareableFileUri(uri)) return ShareOutcome.unavailable;
    final shared = await bridge.shareFile(uri: uri, mimeType: 'video/*');
    return shared ? ShareOutcome.sheetOpened : ShareOutcome.unavailable;
  }

  Future<ShareOutcome> _copyLink(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      return ShareOutcome.linkCopied;
    } on PlatformException {
      // No clipboard service on this host.
      return ShareOutcome.unavailable;
    }
  }

  /// `http(s)` sources are copyable links; everything else is shared as a file.
  static bool _isWebUrl(String uri) {
    final lower = uri.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static bool _isShareableFileUri(String uri) {
    final lower = uri.toLowerCase();
    return lower.startsWith('content://') || lower.startsWith('file://');
  }
}
