import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';

/// Pure, framework-free format selection (ARCHITECTURE §15.6, DL1.3).
///
/// Turns the flat list of [WebFormat]s the extractor returned plus a
/// [DownloadPreset] into a concrete [FormatSelection]: which video stream,
/// which audio stream (for a merge), the output container, a size estimate and
/// any advisories. It performs no I/O and knows nothing about the engine, so
/// the whole matrix is unit-testable (NFR-005).
class FormatSelector {
  const FormatSelector();

  /// Selects formats for [info] under [preset].
  ///
  /// Throws a typed [AppError] for the cases the caller must handle as a
  /// failure rather than a degraded choice: all-DRM media
  /// ([DrmProtectedError]), a live stream ([LiveStreamUnsupportedError]), a
  /// playlist ([PlaylistUnsupportedError]), or no usable streams at all
  /// ([UnsupportedFormatError]).
  FormatSelection select(WebMediaInfo info, DownloadPreset preset) {
    switch (info.kind) {
      case WebMediaKind.live:
        throw const LiveStreamUnsupportedError(
          diagnosticMessage: 'live media routed before selection',
        );
      case WebMediaKind.playlist:
        throw const PlaylistUnsupportedError(
          diagnosticMessage: 'playlist routed before selection',
        );
      case WebMediaKind.video:
        break;
    }

    final usable = info.formats.where((f) => !f.isDrm).toList(growable: false);
    if (usable.isEmpty) {
      if (info.hasDrmFormats) {
        throw const DrmProtectedError(
          diagnosticMessage: 'all offered formats are DRM-encrypted',
        );
      }
      throw const UnsupportedFormatError(
        diagnosticMessage: 'extractor returned no usable formats',
      );
    }

    return preset.kind == DownloadMediaKind.audio
        ? _selectAudio(usable, preset)
        : _selectVideo(usable, preset);
  }

  FormatSelection _selectVideo(List<WebFormat> usable, DownloadPreset preset) {
    final notes = <FormatSelectionNote>{};
    final mp4Only = preset.container == ContainerPreference.mp4;

    var videoPool = usable.where((f) => f.hasVideo).toList(growable: false);
    if (videoPool.isEmpty) {
      throw const UnsupportedFormatError(
        diagnosticMessage: 'no video-bearing format available',
      );
    }

    // "MP4 only" restricts the pool to H.264 video; when none exists we fall
    // back to the best overall and record that MP4 could not be honoured
    // (§15.6 rule 4).
    if (mp4Only) {
      final h264Pool = videoPool.where((f) => f.isH264).toList();
      if (h264Pool.isEmpty) {
        notes.add(FormatSelectionNote.mp4Unavailable);
      } else {
        videoPool = h264Pool;
      }
    }

    final video = _pickVideo(
      videoPool,
      preset.maxHeight,
      preset.compatMode,
      notes,
    );

    if (video.isModernCodec || video.isHdr) {
      notes.add(FormatSelectionNote.codecMayNotPlay);
    }

    // Muxed (video already carries audio) needs no merge; a video-only pick
    // must be paired with the best audio for the target container.
    final WebFormat? audio;
    final OutputContainer container;
    final bool needsMerge;
    if (video.hasAudio) {
      audio = null;
      needsMerge = false;
      container = _containerFromExt(video.ext);
    } else {
      // Prefer an H.264/AAC (MP4) pairing; modern video pairs with Opus (MKV).
      final wantAac =
          video.isH264 && !notes.contains(FormatSelectionNote.mp4Unavailable);
      audio = _pickAudio(usable, wantAac: wantAac);
      needsMerge = audio != null; // silent video has nothing to merge.
      container = (wantAac && audio != null && audio.isAac)
          ? OutputContainer.mp4
          : OutputContainer.mkv;
      if (needsMerge) notes.add(FormatSelectionNote.needsMerge);
    }

    final estimated = _estimate(video, audio);
    return FormatSelection(
      choice: FormatChoice(video: video, audio: audio),
      container: container,
      needsMerge: needsMerge,
      estimatedBytes: estimated,
      notes: notes,
    );
  }

  /// Picks the video stream honouring the height cap and preference order:
  /// compatibility codec, then higher frame rate, then higher bitrate (§15.6
  /// rules 2-3).
  WebFormat _pickVideo(
    List<WebFormat> pool,
    int cap,
    bool compatMode,
    Set<FormatSelectionNote> notes,
  ) {
    final heights =
        pool
            .where((f) => f.height != null)
            .map((f) => f.height!)
            .toSet()
            .toList()
          ..sort();

    int? target;
    if (heights.isEmpty) {
      target = null; // every candidate is unknown-height; rank the whole pool.
    } else if (cap == 0) {
      target = heights.last; // Best → greatest available height.
    } else {
      final allowed = heights.where((h) => h <= cap).toList();
      if (allowed.isEmpty) {
        target = heights.first; // below every height → lowest, quality lowered.
        notes.add(FormatSelectionNote.qualityLowered);
      } else {
        target = allowed.last; // greatest height at or below the cap.
      }
    }

    final atTarget = pool
        .where((f) => (target == null) ? f.height == null : f.height == target)
        .toList();
    final ranked = atTarget.isNotEmpty ? atTarget : pool;

    return ranked.reduce((a, b) => _preferVideo(a, b, compatMode) ? a : b);
  }

  /// True when [a] is the preferred video stream over [b].
  bool _preferVideo(WebFormat a, WebFormat b, bool compatMode) {
    if (compatMode) {
      // H.264 wins under the compatibility option.
      if (a.isH264 != b.isH264) return a.isH264;
    }
    final afps = a.fps ?? 0, bfps = b.fps ?? 0;
    if (afps != bfps) return afps > bfps;
    final abr = a.bitrateKbps ?? 0, bbr = b.bitrateKbps ?? 0;
    if (abr != bbr) return abr > bbr;
    return false;
  }

  /// Best audio-only stream, preferring AAC (MP4) or Opus (MKV) per [wantAac].
  WebFormat? _pickAudio(List<WebFormat> all, {required bool wantAac}) {
    final audioPool = all.where((f) => f.hasAudio).toList();
    if (audioPool.isEmpty) return null;
    final preferred = audioPool
        .where((f) => wantAac ? f.isAac : f.isOpus)
        .toList();
    final pool = preferred.isNotEmpty ? preferred : audioPool;
    return pool.reduce(
      (a, b) => (a.bitrateKbps ?? 0) >= (b.bitrateKbps ?? 0) ? a : b,
    );
  }

  FormatSelection _selectAudio(List<WebFormat> usable, DownloadPreset preset) {
    final notes = <FormatSelectionNote>{};
    final audioOnly = usable.where((f) => f.isAudioOnly).toList();
    final pool = audioOnly.isNotEmpty
        ? audioOnly
        : usable.where((f) => f.hasAudio).toList();
    if (pool.isEmpty) {
      throw const UnsupportedFormatError(
        diagnosticMessage: 'no audio format available for an audio download',
      );
    }

    // Match the requested codec when a source stream already carries it (then
    // it is copied, no re-encode); otherwise pick the best source and let the
    // runner re-encode (MP3 always re-encodes — §15.6 rule 5).
    final WebFormat chosen;
    final OutputContainer container;
    switch (preset.audioFormat) {
      case AudioFormat.m4a:
        chosen = _bestMatching(pool, (f) => f.isAac);
        container = OutputContainer.mp4;
      case AudioFormat.opus:
        chosen = _bestMatching(pool, (f) => f.isOpus);
        container = OutputContainer.mkv;
      case AudioFormat.mp3:
        chosen = _bestByBitrate(pool);
        container = OutputContainer.other; // always re-encoded
    }

    return FormatSelection(
      choice: FormatChoice(video: chosen),
      container: container,
      needsMerge: false,
      estimatedBytes: chosen.sizeBytes,
      notes: notes,
    );
  }

  WebFormat _bestMatching(List<WebFormat> pool, bool Function(WebFormat) test) {
    final matching = pool.where(test).toList();
    return _bestByBitrate(matching.isNotEmpty ? matching : pool);
  }

  WebFormat _bestByBitrate(List<WebFormat> pool) => pool.reduce(
    (a, b) => (a.bitrateKbps ?? 0) >= (b.bitrateKbps ?? 0) ? a : b,
  );

  OutputContainer _containerFromExt(String? ext) => switch (ext) {
    'mp4' => OutputContainer.mp4,
    'm4a' => OutputContainer.mp4,
    _ => OutputContainer.mkv,
  };

  /// Sum of the chosen sizes when all are known; otherwise `null` — an unknown
  /// size is never rendered as a fake `0` (§15.6 rule 6).
  int? _estimate(WebFormat video, WebFormat? audio) {
    if (video.sizeBytes == null) return null;
    if (audio != null && audio.sizeBytes == null) return null;
    return video.sizeBytes! + (audio?.sizeBytes ?? 0);
  }
}
