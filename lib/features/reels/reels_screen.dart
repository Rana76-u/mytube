import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/features/reels/reels_queue.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';
import 'package:mytube/features/reels/reels_source_preloader.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Reels tab — the vertical, swipe-first queue with autoplay, looping, an
/// on-demand control overlay, and limited adjacent preloading (PLAY-001..004,
/// PLAY-008).
///
/// A full-screen [PageView] walks the [ReelsQueue] one reel per page. When this
/// tab is [active] the current reel starts playing on entry, loops until the
/// user swipes, and the newly-revealed reel autoplays on the next swipe
/// (PLAY-002/PLAY-003). Tapping the playing reel toggles a minimal control
/// overlay backed by the shared [PlaybackControls] (PLAY-004/PLAY-005); it
/// auto-hides so the video stays unobstructed.
///
/// [PlaybackSourceResolver] turns a reel into a short-lived [PlayableSource];
/// a [ReelsSourcePreloader] warms the next reel ahead of the swipe and cancels
/// that work when a rapid swipe makes it stale (PLAY-008). [PlaybackController]
/// plays and loops, and [VideoSurface] paints the current page.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key, this.active = true});

  /// Whether the Reels tab is the visible tab. Playback only runs while true,
  /// so switching to another tab stops the reel (the host drives this from the
  /// selected bottom-nav index).
  final bool active;

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  final PageController _pageController = PageController();

  /// The app-owned controller, captured once while mounted. `dispose()` cannot
  /// read providers (the element is already deactivated), so playback teardown
  /// uses this stored reference instead of `ref.read` (PLAY-002/PLAY-003).
  late final PlaybackController _controller;

  /// Warms the next reel's source and drops stale preloads on rapid swipes
  /// (PLAY-008). Also created in `initState` so `dispose()` can clear it without
  /// touching `ref`.
  late final ReelsSourcePreloader _preloader;

  /// Bumped on every navigation/dispose so an in-flight source resolution that
  /// finishes after a swipe or teardown is discarded instead of playing.
  int _playToken = 0;

  /// The reel currently handed to the player, used to avoid restarting the
  /// same source on a state emission that did not change the page.
  VideoItemId? _playingItemId;

  /// User-safe message for the current reel when its source could not be
  /// resolved. Never carries a URI or provider detail.
  String? _reelError;

  /// Whether the on-demand control overlay is showing (PLAY-004).
  bool _controlsVisible = false;

  /// Auto-hides the overlay so a tap reveals controls without leaving them on
  /// the video permanently.
  Timer? _controlsHideTimer;

  /// How long the overlay stays up after a tap before auto-hiding.
  static const Duration _controlsTimeout = Duration(seconds: 4);

  /// How many reels ahead of the current one to keep warm. Deliberately small —
  /// PLAY-008 asks for *limited* preloading (ARCHITECTURE §8: "preload only a
  /// small number of adjacent items").
  static const int _preloadAhead = 1;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playbackControllerProvider);
    _preloader = ReelsSourcePreloader(
      resolver: ref.read(playbackSourceResolverProvider),
    );
    if (widget.active) {
      // Queue data may already be loaded (tab kept alive in the IndexedStack),
      // so schedule the first autoplay once the frame is up.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPlayback());
    }
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _syncPlayback();
    } else {
      _stopPlayback();
    }
  }

  @override
  void dispose() {
    // Invalidate any in-flight work and release the shared engine so a reel
    // never keeps playing under another tab. `ref` is unsafe here (the element
    // is already deactivated), so the captured references are used directly.
    _playToken++;
    _controlsHideTimer?.cancel();
    _preloader.clear();
    _controller.setLooping(false);
    _controller.stop();
    _pageController.dispose();
    super.dispose();
  }

  /// Mirrors a settled swipe into the queue state.
  void _onPageChanged(int index) {
    ref.read(reelsQueueProvider.notifier).goTo(index);
  }

  /// Keeps the [PageView] in sync when the queue index moves for a reason
  /// other than a drag. A swipe that already landed on [index] is a no-op, so
  /// this never fights the gesture.
  void _syncPageToQueue(ReelsQueue? queue) {
    final index = queue?.index;
    if (index == null || !_pageController.hasClients) return;
    final visible = _pageController.page?.round();
    if (visible != index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Starts playback of the current reel when the tab is active and the page
  /// changed since the last start. No-op while loading, empty, or inactive.
  void _syncPlayback() {
    if (!widget.active) return;
    final queue = ref.read(reelsQueueProvider).value;
    final item = queue?.current;
    if (item == null) return;
    if (item.id == _playingItemId) return;
    _playItem(item, queue!);
  }

  Future<void> _playItem(VideoItemSummary item, ReelsQueue queue) async {
    final token = ++_playToken;
    _playingItemId = item.id;
    setState(() => _reelError = null);

    // Stale-work cancellation (PLAY-008): drop any preload started for the reel
    // we just left, then warm only a small window ahead of the current page.
    _preloader.invalidate();
    _preloadWindow(queue);

    final controller = _controller;
    final resolver = ref.read(playbackSourceResolverProvider);

    // Loop the reel until the user swipes away (PLAY-003). The controller
    // carries this across the play() below and any subsequent reel.
    await controller.setLooping(true);
    if (token != _playToken || !mounted) return;

    // Prefer a source warmed by the preloader for an instant start; otherwise
    // resolve now. Either path yields the same short-lived [PlayableSource].
    final preloaded = _preloader.take(item);
    final result = preloaded != null
        ? Result.ok(preloaded)
        : await resolver.resolveForItem(item);
    if (token != _playToken || !mounted) return;

    switch (result) {
      case Ok(:final value):
        // controller.play() never throws; failures surface as an error status
        // that the surface reflects without leaving this screen.
        await controller.play(value);
      case Err(:final error):
        setState(() => _reelError = error.userMessage);
    }
  }

  /// Warms the sources for the [_preloadAhead] reels after the current page.
  void _preloadWindow(ReelsQueue queue) {
    final start = queue.index + 1;
    final end = math.min(queue.length, start + _preloadAhead);
    for (var i = start; i < end; i++) {
      _preloader.preload(queue.items[i]);
    }
  }

  /// Stops playback and clears reel-local state when leaving the tab.
  void _stopPlayback() {
    _playToken++;
    _playingItemId = null;
    _controlsHideTimer?.cancel();
    _preloader.clear();
    if (mounted) setState(() => _reelError = null);
    _controller.setLooping(false);
    _controller.stop();
  }

  /// Toggles the on-demand control overlay and (re)arms its auto-hide timer so
  /// the video is never left covered (PLAY-004).
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _controlsHideTimer?.cancel();
    if (_controlsVisible) {
      _controlsHideTimer = Timer(_controlsTimeout, _hideControls);
    }
  }

  void _hideControls() {
    if (mounted) setState(() => _controlsVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reelsQueueProvider, (previous, next) {
      _syncPageToQueue(next.value);
      _syncPlayback();
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: AsyncValueWidget<ReelsQueue>(
          value: ref.watch(reelsQueueProvider),
          loadingMessage: 'Loading reels...',
          onRetry: () => ref.invalidate(reelsQueueProvider),
          onData: (queue) {
            if (queue.isEmpty) {
              return EmptyState(
                title: 'No Reels Yet',
                message:
                    'Add videos to your library to start '
                    'swiping through reels.',
                icon: Icons.play_circle_outlined,
              );
            }
            return _buildQueue(queue);
          },
        ),
      ),
    );
  }

  Widget _buildQueue(ReelsQueue queue) {
    return PageView.builder(
      key: const ValueKey('reels_page_view'),
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: queue.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final isCurrent = index == queue.index;
        final interactive = isCurrent && widget.active;
        return _ReelPage(
          item: queue.items[index],
          position: index + 1,
          total: queue.length,
          // Only paint the surface on the current page while the tab is
          // active; an inactive tab shows the still caption instead.
          showSurface: interactive,
          controlsVisible: interactive && _controlsVisible,
          onTap: interactive ? _toggleControls : null,
          error: isCurrent ? _reelError : null,
        );
      },
    );
  }
}

/// One reel page. The current page renders the playing [VideoSurface] with the
/// title caption overlaid and a tap-target that reveals the on-demand
/// [PlaybackControls]; the others show a still caption frame so a swipe previews
/// the next item (PLAY-001, PLAY-002, PLAY-004).
class _ReelPage extends StatelessWidget {
  const _ReelPage({
    required this.item,
    required this.position,
    required this.total,
    required this.showSurface,
    required this.controlsVisible,
    this.onTap,
    this.error,
  });

  final VideoItemSummary item;
  final int position;
  final int total;
  final bool showSurface;
  final bool controlsVisible;
  final VoidCallback? onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final caption = _Caption(
      position: position,
      total: total,
      title: item.title,
      error: error,
    );
    if (showSurface && error == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        key: const ValueKey('reels_tap_layer'),
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const VideoSurface(),
            if (controlsVisible) ...[
              // A dim scrim keeps the video visible while the controls read
              // clearly; taps that miss a control fall through to the outer
              // gesture detector and hide the overlay again (PLAY-004).
              const ColoredBox(color: Color(0x66000000)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  key: const ValueKey('reels_controls_overlay'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: const PlaybackControls(),
                ),
              ),
            ] else
              // Keep the title/position readable over the playing video.
              Positioned(left: 0, right: 0, bottom: 0, child: caption),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Align(alignment: Alignment.bottomLeft, child: caption),
    );
  }
}

/// Bottom-anchored position + title (and any reel-local error) caption. Shared
/// by the still and playing pages so a swipe keeps the same text layout.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.position,
    required this.total,
    required this.title,
    this.error,
  });

  final int position;
  final int total;
  final String title;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$position / $total',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (error case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              key: const ValueKey('reels_reel_error'),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
