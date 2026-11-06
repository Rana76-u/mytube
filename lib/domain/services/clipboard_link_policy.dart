import 'package:flutter/foundation.dart' show immutable;

import 'package:mytube/core/util/fnv1a_hash.dart';
import 'package:mytube/domain/services/link_extraction.dart';

/// What the app should do with text found on the clipboard on resume (ADR-024,
/// ARCHITECTURE §15.5, DL1.6).
enum ClipboardDecision {
  /// Show nothing: detection is off, there is no link, or this exact link was
  /// already handled (only a hash of it is remembered).
  ignore,

  /// A direct media-file URL — route it to the existing Add-URL download flow
  /// (ADR-019), not the extractor.
  directUrl,

  /// A web page worth offering: prompt Download / Stream / Dismiss.
  prompt,
}

/// The outcome of [decideClipboardLink]: the [decision], the parsed [link]
/// (when one was found), and the [handledHash] the caller should persist as
/// `download.lastClipboardHash` after acting on it.
@immutable
class ClipboardLinkResult {
  const ClipboardLinkResult(this.decision, {this.link, this.handledHash});

  final ClipboardDecision decision;
  final WebLink? link;

  /// Hash of the canonical URL, present only when the caller should remember
  /// this value. It is a hash — never the text (AGENTS clipboard rule).
  final String? handledHash;

  bool get shouldPrompt => decision == ClipboardDecision.prompt;
  bool get isDirectUrl => decision == ClipboardDecision.directUrl;
}

/// Extensions that make a clipboard link a *direct media file* rather than a
/// page the extractor should resolve. Kept conservative: an unrecognised
/// extension is treated as a web page (prompt), never silently downloaded.
const Set<String> _directMediaExtensions = {
  '.mp4',
  '.m4a',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.flv',
  '.wmv',
  '.mp3',
  '.m4b',
  '.aac',
  '.opus',
  '.ogg',
  '.wav',
  '.flac',
  '.ts',
};

/// Pure clipboard decision (DL1.6). Framework-free and side-effect-free so the
/// "prompt vs Add-URL vs ignore" rules are unit-tested without touching the
/// platform clipboard.
///
/// Rules (§15.5, ADR-024, AGENTS): never auto-start a download; a link is only
/// ever *offered*. Detection off, empty/non-URL text, and a value whose hash
/// equals [lastHandledHash] all resolve to [ClipboardDecision.ignore]. A direct
/// media-file URL is routed to the Add-URL flow; every other page prompts.
ClipboardLinkResult decideClipboardLink({
  required String? text,
  required bool detectionEnabled,
  required String? lastHandledHash,
}) {
  if (!detectionEnabled) {
    return const ClipboardLinkResult(ClipboardDecision.ignore);
  }

  final link = WebLink.parse(text ?? '');
  if (link == null) {
    return const ClipboardLinkResult(ClipboardDecision.ignore);
  }

  final hash = fnv1a128Hex(link.url.toString());
  if (lastHandledHash == hash) {
    // Same link we already offered — remember only the hash, so ignore again.
    return ClipboardLinkResult(ClipboardDecision.ignore, link: link);
  }

  if (_isDirectMediaFile(link.url)) {
    return ClipboardLinkResult(
      ClipboardDecision.directUrl,
      link: link,
      handledHash: hash,
    );
  }
  return ClipboardLinkResult(
    ClipboardDecision.prompt,
    link: link,
    handledHash: hash,
  );
}

bool _isDirectMediaFile(Uri uri) {
  final path = uri.path.toLowerCase();
  return _directMediaExtensions.any(path.endsWith);
}
