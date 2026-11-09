import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/services/clipboard_link_policy.dart';
import 'package:mytube/features/downloads/clipboard_watcher.dart';
import 'package:mytube/features/downloads/download_flow_coordinator.dart';
import 'package:mytube/features/downloads/download_preset_notifier.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/features/downloads/share_intake_coordinator.dart';
import 'package:mytube/features/downloads/ui/clipboard_prompt_sheet.dart';
import 'package:mytube/features/downloads/ui/download_from_link_sheet.dart';
import 'package:mytube/features/downloads/ui/download_options_sheet.dart';
import 'package:mytube/features/downloads/ui/downloads_screen.dart';
import 'package:mytube/features/downloads/ui/link_probe_progress_dialog.dart';
import 'package:mytube/features/downloads/web_link_enqueue.dart';
import 'package:mytube/features/library/library_actions.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/source_adapter.dart';

/// UI host for share, clipboard and paste intake (DL5 + DL6).
abstract final class DownloadIntakeHost {
  static const _coordinator = DownloadFlowCoordinator();
  static final _enqueue = WebLinkEnqueue();
  static final _share = ShareIntakeCoordinator();
  static bool _clipboardOpen = false;

  static Future<bool> consumeShare(BuildContext context, WidgetRef ref) async {
    String? text;
    try {
      text = await ref.read(shareIntakeBridgeProvider).consumeShareText();
    } catch (_) {
      return false;
    }
    if (text == null || !context.mounted) return false;
    await ref.read(shareIntakeBridgeProvider).clearPendingShareText();
    if (!context.mounted) return true;

    final queued = await _queuedUrls(ref);
    final result = _share.handleShareText(
      text,
      queueCount: queued.length,
      now: DateTime.now(),
    );
    if (!context.mounted) return true;
    switch (result.status) {
      case ShareIntakeStatus.accepted when result.link != null:
        await startDownload(
          context,
          ref,
          rawText: result.link!.url.toString(),
          origin: DownloadIntakeOrigin.share,
        );
      case ShareIntakeStatus.missingUrl:
        _snack(context, 'No web link was found in that share.');
      case ShareIntakeStatus.rateLimited:
      case ShareIntakeStatus.queueFull:
        _snack(context, result.message ?? 'Could not start that download.');
      case ShareIntakeStatus.accepted:
        break;
    }
    return true;
  }

  static Future<void> onAppResumed(BuildContext context, WidgetRef ref) async {
    final preset = ref.read(downloadPresetProvider);
    if (!preset.clipboardDetect) return;
    var decision = await _probeClipboard(ref, preset);
    if ((decision == null || decision.decision == ClipboardDecision.ignore) &&
        context.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!context.mounted) return;
      decision = await _probeClipboard(ref, ref.read(downloadPresetProvider));
    }
    if (!context.mounted || decision == null) return;
    switch (decision.decision) {
      case ClipboardDecision.ignore:
        return;
      case ClipboardDecision.directUrl:
        await _rememberHash(ref, decision.handledHash);
        if (context.mounted) await addDirectUrl(context, ref);
      case ClipboardDecision.prompt:
        await _showClipboardPrompt(context, ref, decision);
    }
  }

  static Future<void> openPasteSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final url = await showDownloadFromLinkSheet(context);
    if (url == null || !context.mounted) return;
    await startDownload(
      context,
      ref,
      rawText: url,
      origin: DownloadIntakeOrigin.paste,
    );
  }

  static Future<void> startDownload(
    BuildContext context,
    WidgetRef ref, {
    required String rawText,
    required DownloadIntakeOrigin origin,
    String? videoItemId,
  }) async {
    await _ensureNotice(context, ref);
    if (!context.mounted) return;

    final queued = await _queuedUrls(ref);
    final flow = _coordinator.startDownloadFlow(
      rawText: rawText,
      origin: origin,
      askBeforeEachDownload: ref.read(downloadPresetProvider).askEveryTime,
      queuedLinks: queued,
      libraryLinks: queued,
    );
    if (!context.mounted) return;
    if (!flow.ok) {
      if (flow.isDuplicate) {
        _snack(context, 'That link is already queued or downloaded.');
      } else {
        _snack(context, 'Paste an http:// or https:// link.');
      }
      return;
    }
    final link = flow.link;
    if (link == null) return;

    final info = await _probe(
      context,
      ref,
      link.url,
      rawText: rawText,
      origin: origin,
    );
    if (!context.mounted || info == null) return;

    var preset = ref.read(downloadPresetProvider);
    if (flow.needsOptionsSheet) {
      final picked = await showDownloadOptionsSheet(
        context,
        title: info.title ?? link.displayDescription,
        uploader: info.uploader,
        duration: info.duration,
        thumbnailUrl: info.thumbnailUrl,
        info: info,
        initialPreset: preset,
        onPickFolder: () => _pickFolder(ref),
      );
      if (!context.mounted || picked == null) return;
      preset = picked.preset;
      if (picked.saveForNextTime) {
        await ref
            .read(downloadPresetProvider.notifier)
            .update(preset.copyWith(askEveryTime: false));
      }
    }

    final started = await _enqueue.start(
      manager: ref.read(downloadManagerProvider),
      info: info,
      preset: preset,
      videoItemId: videoItemId,
    );
    if (!context.mounted) return;
    switch (started) {
      case Ok():
        _showDownloadStarted(context);
      case Err(:final error):
        await _showError(context, ref, error, rawText: rawText, origin: origin);
    }
  }

  static Future<ClipboardLinkResult?> _probeClipboard(
    WidgetRef ref,
    DownloadPreset preset,
  ) async {
    try {
      final watcher = ClipboardWatcher(
        bridge: ref.read(clipboardProbeBridgeProvider),
        enabled: preset.clipboardDetect,
        lastHandledHash: preset.lastClipboardHash,
      );
      return watcher.checkForLink();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _showClipboardPrompt(
    BuildContext context,
    WidgetRef ref,
    ClipboardLinkResult decision,
  ) async {
    if (_clipboardOpen) return;
    final url = decision.link?.url.toString();
    if (url == null) return;
    _clipboardOpen = true;
    try {
      final action = await showClipboardPromptSheet(context, link: url);
      await _rememberHash(ref, decision.handledHash);
      if (!context.mounted) return;
      switch (action) {
        case ClipboardPromptAction.download:
          await startDownload(
            context,
            ref,
            rawText: url,
            origin: DownloadIntakeOrigin.clipboard,
          );
        case ClipboardPromptAction.stream:
          _snack(
            context,
            "Streaming isn't available for this link yet. Download it instead.",
          );
        case ClipboardPromptAction.dismiss:
        case null:
          break;
      }
    } finally {
      _clipboardOpen = false;
    }
  }

  static Future<void> _rememberHash(WidgetRef ref, String? hash) async {
    if (hash == null) return;
    await ref
        .read(downloadPresetProvider.notifier)
        .patch((p) => p.copyWith(lastClipboardHash: hash));
  }

  static Future<WebMediaInfo?> _probe(
    BuildContext context,
    WidgetRef ref,
    Uri url, {
    required String rawText,
    required DownloadIntakeOrigin origin,
  }) async {
    final token = CancellationToken();
    final probe = ref
        .read(mediaExtractorProvider)
        .probe(url, cancellationToken: token);
    final result = await showDialog<Result<WebMediaInfo>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => LinkProbeProgressDialog(
        host: url.host,
        probe: probe,
        onCancel: () {
          token.cancel();
          Navigator.pop(dialogContext);
        },
      ),
    );
    if (!context.mounted || result == null) return null;
    switch (result) {
      case Ok(:final value):
        return value;
      case Err(:final error):
        if (error is DownloadCancelledError) return null;
        final displayError = error is UnexpectedError
            ? UnexpectedError(
                userMessage:
                    'Could not read video details from this link. Check your '
                    'connection and try again.',
                diagnosticMessage: error.diagnosticMessage,
                cause: error.cause,
              )
            : error;
        await _showError(
          context,
          ref,
          displayError,
          rawText: rawText,
          origin: origin,
        );
        return null;
    }
  }

  static void _showDownloadStarted(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Download added to the queue.'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ),
    );
  }

  static Future<List<String>> _queuedUrls(WidgetRef ref) async {
    final listed = await ref.read(downloadRepositoryProvider).listAll();
    return switch (listed) {
      Ok(:final value) => [
        for (final record in value)
          if (record.status != DownloadStatus.canceled) record.sourceUri,
      ],
      Err() => const <String>[],
    };
  }

  static Future<Uri?> _pickFolder(WidgetRef ref) async {
    final result = await ref
        .read(downloadPresetProvider.notifier)
        .pickDestinationFolder();
    return switch (result) {
      Ok() => switch (ref.read(downloadPresetProvider).destination) {
        PickedFolderDestination(:final treeUri) => treeUri,
        _ => null,
      },
      Err() => null,
    };
  }

  static Future<void> _ensureNotice(BuildContext context, WidgetRef ref) async {
    try {
      final dao = ref.read(databaseProvider).appPreferencesDao;
      final seen = await dao.getString(
        AppPreferenceKeys.downloadNoticeAcknowledged,
      );
      if (seen == 'true' || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Before you download'),
          content: const Text(
            'Downloading from third-party sites can breach their terms. '
            'You are responsible for how you use this. Using your own '
            'account cookies can get that account limited by the site.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      await dao.setString(AppPreferenceKeys.downloadNoticeAcknowledged, 'true');
    } catch (_) {
      // Storage unavailable — skip rather than block the download.
    }
  }

  static Future<void> _showError(
    BuildContext context,
    WidgetRef ref,
    AppError error, {
    String? rawText,
    DownloadIntakeOrigin? origin,
  }) async {
    if (!context.mounted) return;
    final retry = rawText != null && origin != null;
    await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Could not download'),
        content: Text(error.userMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (error is ExtractorOutOfDateError)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'update'),
              child: const Text('Update extractor'),
            ),
          if (error is DestinationUnavailableError)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'folder'),
              child: const Text('Choose another folder'),
            ),
          if (retry)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'retry'),
              child: const Text('Retry'),
            ),
        ],
      ),
    ).then((value) async {
      if (!context.mounted) return;
      if (value == 'retry' && rawText != null && origin != null) {
        await startDownload(context, ref, rawText: rawText, origin: origin);
      }
      if (value == 'folder') {
        await ref.read(downloadPresetProvider.notifier).pickDestinationFolder();
      }
    });
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
