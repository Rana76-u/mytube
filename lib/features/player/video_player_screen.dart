import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Dedicated player screen for a single library item (PLAY-001/PLAY-009).
///
/// Reached by tapping a video card in the Library/Discover/Saved lists. It
/// resolves the item's source through [PlaybackSourceResolver] (never the
/// widgets themselves touching persistence or adapters), hands the short-lived
/// [PlayableSource] to the app-owned [PlaybackController], and paints it with
/// the shared [VideoSurface] + [PlaybackControls] so behaviour matches Reels
/// (PLAT-005 — no `video_player` type appears here).
///
/// Playback is one-shot: looping (a Reels-only behaviour, PLAY-003) is turned
/// off on entry, position resumes from stored watch progress when there is
/// any (P5-08), and every controller tick is forwarded to
/// [WatchProgressService] which throttles the actual writes. Leaving the
/// screen flushes the final position and stops playback so no engine keeps
/// running under the tab shell.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});

  /// The library item to play. Carries only the summary the resolver needs
  /// (id + title); source locations are read inside the resolver.
  final VideoItemSummary item;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  /// The app-owned controller, captured while mounted so `dispose()` (where
  /// `ref` is unsafe) can still stop playback — same pattern as Reels.
  late final PlaybackController _controller;

  /// Captured for the same reason: the last position must reach storage on
  /// teardown, not only on throttled writes.
  late final WatchProgressService _watchProgress;

  /// Bumped on entry and teardown so a resolution that finishes after the
  /// user left the screen is discarded instead of starting playback.
  int _playToken = 0;

  /// Controller whose [PlaybackController.state] is currently feeding watch
  /// progress, plus the exact listener registered on it, so rebuilds and
  /// teardown always remove the callback they installed.
  PlaybackController? _progressSource;
  void Function()? _progressListener;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playbackControllerProvider);
    _watchProgress = ref.read(watchProgressServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPlayback());
  }

  @override
  void dispose() {
    // `ref` is unsafe here (the element is already deactivated), hence the
    // captured references (house rule: cancel work, release resources).
    _playToken++;
    _detachProgressListener();
    unawaited(_watchProgress.flush(widget.item.id));
    _controller.stop();
    super.dispose();
  }

  Future<void> _startPlayback() async {
    if (!mounted) return;
    final token = ++_playToken;

    // Reels-style looping must be off for a one-shot player session; the
    // controller carries this flag across play() calls.
    await _controller.setLooping(false);
    if (token != _playToken || !mounted) return;

    final result = await ref
        .read(playbackSourceResolverProvider)
        .resolveForItem(widget.item);
    if (result case Err(:final error)) {
      if (token != _playToken || !mounted) return;
      // User-safe text only; raw URIs/diagnostics never reach the UI.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      return;
    }
    final source = (result as Ok<PlayableSource>).value;
    if (token != _playToken || !mounted) return;

    await _controller.play(source);
    if (token != _playToken || !mounted) return;

    // Resume from stored progress once the engine has a loaded duration
    // (P5-08/LIB-002). Failure is silent: playback simply starts over.
    final resume = await _watchProgress.resumePosition(widget.item.id);
    if (token != _playToken || !mounted || resume == null) return;
    await _controller.seekTo(resume);
  }

  /// Registers the watch-progress listener on the current controller exactly
  /// once per controller instance; re-invoked from [build] only when the
  /// provider handed us a different controller (tests override it).
  void _attachProgressListener(PlaybackController controller) {
    if (_progressSource == controller) return;
    _detachProgressListener();
    void listener() {
      final state = controller.state.value;
      if (state.status == PlaybackStatus.idle) return;
      unawaited(
        _watchProgress.reportPosition(
          id: widget.item.id,
          position: state.position,
        ),
      );
      // Flush at pause/error boundaries so even a short watch persists.
      if (state.status == PlaybackStatus.paused ||
          state.status == PlaybackStatus.error) {
        unawaited(_watchProgress.flush(widget.item.id));
      }
    }

    controller.state.addListener(listener);
    _progressSource = controller;
    _progressListener = listener;
  }

  void _detachProgressListener() {
    _progressSource?.state.removeListener(_progressListener!);
    _progressSource = null;
    _progressListener = null;
  }

  @override
  Widget build(BuildContext context) {
    // Forward every position tick to the throttled progress service and
    // flush at state boundaries (pause/error) so a short watch persists.
    final controller = ref.watch(playbackControllerProvider);
    _attachProgressListener(controller);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(child: Center(child: VideoSurface())),
            // Error text and the gated Retry affordance already live inside
            // PlaybackControls (P4-07/AVAIL-002/PLAY-009) — no duplication.
            const PlaybackControls(),
          ],
        ),
      ),
    );
  }
}
