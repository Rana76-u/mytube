import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/format_selector.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/extractor_job_spec.dart';

/// Builds the extractor job snapshot and enqueues it (DL6 options / paste).
class WebLinkEnqueue {
  WebLinkEnqueue({
    FormatSelector selector = const FormatSelector(),
    Uuid uuid = const Uuid(),
  }) : _selector = selector,
       _uuid = uuid;

  final FormatSelector _selector;
  final Uuid _uuid;

  /// Selects formats for [info] under [preset] and starts an extractor job.
  Result<DownloadRequest> requestFor({
    required WebMediaInfo info,
    required DownloadPreset preset,
    String? videoItemId,
  }) {
    final FormatSelection selection;
    try {
      selection = _selector.select(info, preset);
    } on AppError catch (error) {
      return Result.err(error);
    }

    final spec = specFor(selection, preset);
    final height = selection.choice.video?.height;
    final summary = [
      if (preset.kind == DownloadMediaKind.audio) preset.audioFormat.name,
      if (preset.kind == DownloadMediaKind.video)
        preset.bestQuality ? 'Best' : '${preset.maxHeight}p',
      if (height != null && preset.kind == DownloadMediaKind.video)
        '${height}p',
      selection.container.name,
    ].join(' · ');

    return Result.ok(
      DownloadRequest(
        videoItemId: videoItemId ?? _uuid.v4(),
        providerType: ProviderType.webLink,
        sourceUri: info.canonicalUrl,
        sizeBytes: selection.estimatedBytes,
        sourceKind: DownloadSourceKind.extractor,
        mediaKind: preset.kind,
        title: info.title,
        thumbnailUri: info.thumbnailUrl,
        formatSummary: summary,
        presetJson: spec.encode(),
        destination: preset.destination,
      ),
    );
  }

  static ExtractorJobSpec specFor(
    FormatSelection selection,
    DownloadPreset preset,
  ) {
    final primary = selection.choice.video;
    final paired = selection.choice.audio;
    final isAudio = preset.kind == DownloadMediaKind.audio;
    return ExtractorJobSpec(
      videoFormatId: isAudio ? null : primary?.formatId,
      audioFormatId: isAudio
          ? (primary?.formatId ?? paired?.formatId)
          : paired?.formatId,
      merge: selection.needsMerge,
      container: selection.container,
      concurrentFragments: preset.fragments,
      useAria2c: preset.useAria2c,
      rateLimitKbps: preset.rateLimitKbps,
      subtitleLangs: preset.subtitleLangs,
      embedSubtitles: preset.embedSubs,
      sponsorBlock: preset.sponsorBlock,
    );
  }

  Future<Result<DownloadRecord>> start({
    required DownloadManager manager,
    required WebMediaInfo info,
    required DownloadPreset preset,
    String? videoItemId,
  }) async {
    final request = requestFor(
      info: info,
      preset: preset,
      videoItemId: videoItemId,
    );
    return switch (request) {
      Ok(:final value) => manager.start(value),
      Err(:final error) => Result.err(error),
    };
  }
}
