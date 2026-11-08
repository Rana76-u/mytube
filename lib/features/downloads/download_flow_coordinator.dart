import 'package:mytube/domain/services/link_extraction.dart';

/// The intake origin for a link that is entering the app.
enum DownloadIntakeOrigin { share, clipboard, paste }

/// The result of a DL5 intake route selection.
class DownloadFlowResult {
  const DownloadFlowResult({
    required this.ok,
    required this.needsOptionsSheet,
    required this.reason,
    this.link,
  });

  final bool ok;
  final bool needsOptionsSheet;
  final String reason;
  final WebLink? link;

  bool get isDuplicate => reason == 'duplicate';
  bool get isInvalid => reason == 'invalid';
}

/// Pure orchestration for the DL5 intake flow.
///
/// The coordinator validates the incoming link once, checks whether it is
/// already active or already in the library, decides whether the user should be
/// prompted or the download can start immediately, and keeps the decision logic
/// free of any UI or platform code.
class DownloadFlowCoordinator {
  const DownloadFlowCoordinator();

  DownloadFlowResult startDownloadFlow({
    required String? rawText,
    required DownloadIntakeOrigin origin,
    required bool askBeforeEachDownload,
    required Iterable<String> queuedLinks,
    required Iterable<String> libraryLinks,
  }) {
    final parsed = rawText == null ? null : WebLink.parse(rawText.trim());
    if (parsed == null) {
      return const DownloadFlowResult(
        ok: false,
        needsOptionsSheet: false,
        reason: 'invalid',
      );
    }

    final queueSet = queuedLinks
        .map((item) => WebLink.parse(item.trim()))
        .whereType<WebLink>()
        .map((link) => link.url.toString())
        .toSet();
    final librarySet = libraryLinks
        .map((item) => WebLink.parse(item.trim()))
        .whereType<WebLink>()
        .map((link) => link.url.toString())
        .toSet();

    final canonical = parsed.url.toString();
    if (queueSet.contains(canonical) || librarySet.contains(canonical)) {
      return DownloadFlowResult(
        ok: false,
        needsOptionsSheet: false,
        reason: 'duplicate',
        link: parsed,
      );
    }

    final shouldPrompt =
        askBeforeEachDownload || origin == DownloadIntakeOrigin.clipboard;
    return DownloadFlowResult(
      ok: true,
      needsOptionsSheet: shouldPrompt,
      reason: shouldPrompt ? 'prompt' : 'start',
      link: parsed,
    );
  }
}
