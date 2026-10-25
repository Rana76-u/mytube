import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mytube/platform/pip_bridge.dart';
import 'package:mytube/playback/playback_controller.dart';

/// App-owned coordinator that drives Android Picture-in-Picture from the shared
/// [PlaybackController] and reports PiP state back for the UI (P13-04,
/// PLAY-010).
///
/// It owns *policy only* — no Android type appears here. Three jobs:
///
/// 1.  **Capability** — feature-detects PiP once via [PipBridge.isSupported] and
///     publishes it on [supported], so screens only offer a PiP control where it
///     actually works. On non-Android hosts / unsupported devices it stays false
///     and every command is a no-op (NFR-006, PLAY-013).
/// 2.  **Mode** — mirrors the native enter / leave transitions onto [inPip] so
///     the Reels and player surfaces can hide overlay chrome while floating.
/// 3.  **Auto-enter** — while a live video session is on screen it keeps the
///     system's auto-enter-on-leave enabled (Android 12+), so pressing Home
///     shrinks the video; a [enter] call shrinks on demand for every supported
///     level. Auto-enter is dropped the moment playback goes idle / completes /
///     errors, so a Home press then leaves the app rather than floating nothing.
///
/// Widgets call [enter] and read [inPip] / [supported]; they never touch the
/// bridge directly.
class PipCoordinator {
  PipCoordinator({
    required PlaybackController controller,
    required PipBridge bridge,
  }) : _controller = controller, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _bridge = bridge {
    _controller.state.addListener(_onPlaybackChanged);
    _modeSub = _bridge.modeChanges.listen(_onModeChanged);
    unawaited(_refreshSupport());
  }

  final PlaybackController _controller;
  final PipBridge _bridge;

  StreamSubscription<bool>? _modeSub;

  final ValueNotifier<bool> _inPip = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _supported = ValueNotifier<bool>(false);

  /// Last auto-enter we pushed, so an unchanged playback tick does not re-invoke
  /// the bridge every position update.
  bool _autoEnter = false;

  bool _disposed = false;

  /// Whether the app is currently floating in a PiP window (chrome should hide).
  ValueListenable<bool> get inPip => _inPip;

  /// Whether the host supports PiP at all (a control should only show when true).
  ValueListenable<bool> get supported => _supported;

  Future<void> _refreshSupport() async {
    final supported = await _bridge.isSupported();
    if (_disposed) {
      return;
    }
    _supported.value = supported;
  }

  // ---------------------------------------------------------------------------
  // Enter on demand
  // ---------------------------------------------------------------------------

  /// Requests PiP now, hinting the float window's aspect ratio from the loaded
  /// picture. A no-op when the host does not support PiP.
  Future<void> enter() async {
    if (!_supported.value || _disposed) {
      return;
    }
    final aspect = pipAspectFor(_controller.state.value.videoSize);
    await _bridge.enter(
      aspectWidth: aspect?.width,
      aspectHeight: aspect?.height,
    );
  }

  // ---------------------------------------------------------------------------
  // Mode / auto-enter policy
  // ---------------------------------------------------------------------------

  void _onModeChanged(bool inPip) {
    if (_disposed) {
      return;
    }
    _inPip.value = inPip;
  }

  void _onPlaybackChanged() {
    if (_disposed) {
      return;
    }
    final live = _isLiveVideo(_controller.state.value.status);
    if (live == _autoEnter) {
      return;
    }
    _autoEnter = live;
    unawaited(_bridge.setAutoEnter(live));
  }

  static bool _isLiveVideo(PlaybackStatus status) => switch (status) {
    PlaybackStatus.buffering => true,
    PlaybackStatus.playing => true,
    PlaybackStatus.paused => true,
    PlaybackStatus.idle => false,
    PlaybackStatus.completed => false,
    PlaybackStatus.error => false,
  };

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _controller.state.removeListener(_onPlaybackChanged);
    unawaited(_modeSub?.cancel());
    _modeSub = null;
    _inPip.dispose();
    _supported.dispose();
    // release() clears native PiP params; the bridge never throws.
    unawaited(_bridge.release());
  }
}
