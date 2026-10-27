import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/services/caption_parser.dart';
import 'package:mytube/playback/playback_controller.dart'
    show CaptionCapableController;
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/platform/caption_source.dart';

/// How large the subtitle text renders (design §7's "subtitle size", VP4.3).
enum CaptionTextSize {
  small('Small', 0.8),
  medium('Medium', 1.0),
  large('Large', 1.35);

  const CaptionTextSize(this.label, this.scale);

  final String label;

  /// Multiplied onto the base caption font size by the overlay.
  final double scale;
}

/// The backdrop behind the subtitle text (design §7's "background", VP4.3).
enum CaptionBackground {
  none('None'),
  shadow('Shadow'),
  box('Box');

  const CaptionBackground(this.label);

  final String label;
}

/// Everything the caption overlay and the sheet need to know (VP4.3).
class CaptionsState {
  const CaptionsState({
    this.cues = const <CaptionCue>[],
    this.label,
    this.enabled = false,
    this.size = CaptionTextSize.medium,
    this.background = CaptionBackground.box,
  });

  /// The parsed sidecar cues, empty until a file is loaded.
  final List<CaptionCue> cues;

  /// Display name of the loaded file, shown in the sheet; null when none.
  final String? label;

  /// Whether captions are drawn and delivered to the engine right now.
  final bool enabled;

  final CaptionTextSize size;
  final CaptionBackground background;

  bool get hasFile => cues.isNotEmpty;

  CaptionsState copyWith({
    List<CaptionCue>? cues,
    String? label,
    bool? enabled,
    CaptionTextSize? size,
    CaptionBackground? background,
    bool clearLabel = false,
  }) => CaptionsState(
    cues: cues ?? this.cues,
    label: clearLabel ? null : (label ?? this.label),
    enabled: enabled ?? this.enabled,
    size: size ?? this.size,
    background: background ?? this.background,
  );
}

/// Owns the session's captions: the loaded sidecar, the display options and the
/// delivery of cues to the engine seam (VP4.3).
///
/// Session-scoped and never persisted, exactly like loop and the sleep timer: a
/// subtitle picked for one video must not leak onto the next, so the player page
/// calls [clear] whenever the item changes. The cues are also forwarded to the
/// controller — and, through it, to any engine that declares the caption
/// capability — so "captions reach the handle" holds even though the visible
/// text is painted by the app overlay (which alone can honour size/background).
class CaptionsNotifier extends Notifier<CaptionsState> {
  @override
  CaptionsState build() => const CaptionsState();

  /// Opens the picker, parses the chosen sidecar and turns captions on.
  ///
  /// Returns a user-safe message on failure (or null on success/cancel) so the
  /// sheet can surface why nothing appeared; a cancel is not an error.
  Future<String?> load() async {
    final result = await ref.read(captionSourceProvider).pickAndRead();
    if (result case Err(:final error)) {
      return error.userMessage;
    }
    final sidecar = (result as Ok<PickedSidecar?>).value;
    // A cancel (null) leaves the previous file untouched rather than blanking.
    if (sidecar == null) return null;
    return _applyPicked(sidecar);
  }

  String? _applyPicked(PickedSidecar sidecar) {
    final cues = parseCaptions(sidecar.text);
    if (cues.isEmpty) {
      // A file with no parseable cue is a real problem to report, not a silent
      // success: the user picked something and nothing shows.
      return 'No captions found in ${sidecar.name}.';
    }
    state = state.copyWith(cues: cues, label: sidecar.name, enabled: true);
    _deliver();
    return null;
  }

  /// Turns the overlay (and the engine cues) on or off without dropping the
  /// loaded file, so the sheet's toggle can hide captions and bring them back.
  void setEnabled(bool enabled) {
    if (state.cues.isEmpty && enabled) return;
    state = state.copyWith(enabled: enabled);
    _deliver();
  }

  void setSize(CaptionTextSize size) => state = state.copyWith(size: size);

  void setBackground(CaptionBackground background) =>
      state = state.copyWith(background: background);

  /// Drops the loaded file. Called on an item change so one video's subtitles
  /// never render on the next (VP4.3 acceptance).
  void clear() {
    state = const CaptionsState();
    _deliver();
  }

  void _deliver() {
    final controller = ref.read(playbackControllerProvider);
    if (controller case final CaptionCapableController captionController) {
      final cues = state.enabled ? state.cues : const <CaptionCue>[];
      unawaited(captionController.setCaptions(cues.isEmpty ? null : cues));
    }
  }
}

/// Provider for the session's captions (mutating access).
final captionsProvider = NotifierProvider<CaptionsNotifier, CaptionsState>(
  CaptionsNotifier.new,
);

/// Read-only alias for the caption state.
final captionsStateProvider = Provider<CaptionsState>(
  (ref) => ref.watch(captionsProvider),
);
