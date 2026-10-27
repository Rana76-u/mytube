import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/motion.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/captions_notifier.dart';
import 'package:mytube/features/player/fullscreen_controller.dart';
import 'package:mytube/features/player/playback_queue.dart';
import 'package:mytube/features/player/player_action_row.dart';
import 'package:mytube/features/player/player_keyboard_shortcuts.dart';
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_caption_overlay.dart';
import 'package:mytube/features/player/player_device_controls.dart';
import 'package:mytube/features/player/player_device_controls_provider.dart';
import 'package:mytube/features/player/player_gesture_layer.dart';
import 'package:mytube/features/player/player_layout.dart';
import 'package:mytube/features/player/player_metadata_panel.dart';
import 'package:mytube/features/player/player_overlay.dart';
import 'package:mytube/features/player/player_settings_sheet.dart';
import 'package:mytube/features/player/player_up_next.dart';
import 'package:mytube/features/player/scrub_preview_service.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/features/player/vertical_expand_notifier.dart';
import 'package:mytube/features/player/video_loop_notifier.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';
import 'package:mytube/playback/pip_coordinator.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Dedicated player page for a library item (PLAY-001/PLAY-009, DESIGN.md §5).
///
/// Reached by tapping a video card anywhere in the app. It resolves the item's
/// source through [PlaybackSourceResolver] (never the widgets themselves
/// touching persistence or adapters), hands the short-lived [PlayableSource] to
/// the app-owned [PlaybackController], and paints it with the shared
/// [VideoSurface] plus the player's own overlay chrome (VP2.5 — no
/// `video_player` type appears here).
///
/// Layout follows DESIGN.md §5: one [CustomScrollView] whose first sliver is a
/// pinned 16:9 player, so the video stays docked while the metadata, the action
/// toolbar and "Up Next" scroll beneath it. The page has no permanent app bar
/// (VP3.1): back, title and PiP live in the overlay top bar and fade with the
/// controls. The overlay chrome ([PlayerOverlay]) is driven by
/// [PlayerChromeController] — tap toggles it and it auto-hides after 3 s of
/// playback (VP2.1) — while [PlayerGestureLayer] owns double taps, the scrub
/// drag, and (in fullscreen) brightness, volume and pinch. Swiping the portrait
/// player down still docks the session into the mini player (ADR-014).
///
/// Playback is one-shot: looping (a Reels-only behaviour, PLAY-003) starts off
/// on entry and follows the toolbar's Loop pill if the user turns it on,
/// position resumes from stored watch progress when there is any (P5-08), and
/// every controller tick is forwarded to [WatchProgressService] which throttles
/// the actual writes.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});

  /// The library item to play. Carries only the summary the resolver needs
  /// (id + title); source locations are read inside the resolver.
  final VideoItemSummary item;

  /// The route every card uses to open the player: a short slide/fade so the
  /// video reads as docking out of the feed, and back into the mini player when
  /// the page is closed (plan M6).
  static Route<void> route(VideoItemSummary item) => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => VideoPlayerScreen(item: item),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  /// The app-owned controller, captured while mounted so `dispose()` (where
  /// `ref` is unsafe) can still stop playback — same pattern as Reels.
  late final PlaybackController _controller;

  /// Captured for the same reason: the last position must reach storage on
  /// teardown, not only on throttled writes.
  late final WatchProgressService _watchProgress;

  /// Bumped on every (re)start and on teardown so a resolution that finishes
  /// after the user left the page — or switched items — is discarded instead of
  /// starting playback.
  int _playToken = 0;

  /// Controller whose [PlaybackController.state] is currently feeding watch
  /// progress, plus the exact listener registered on it, so rebuilds and
  /// teardown always remove the callback they installed.
  PlaybackController? _progressSource;
  void Function()? _progressListener;

  /// The item currently loaded. Changes in place when an "Up Next" row is
  /// tapped, so one page can walk a queue without stacking routes.
  late VideoItemSummary _item;

  /// Accumulated downward drag on the video, in pixels; past
  /// [AppSizes.dockDragThreshold] the page docks into the mini player.
  double _dragDown = 0;

  /// Decides when the overlay chrome hides (VP2.1): tap toggles it, playback
  /// auto-hides it after 3 s, and a scrub, a settings sheet, an in-flight
  /// gesture, lock, completion or an error keep it up.
  late final PlayerChromeController _chrome;

  /// The scrub-frame source (VP2.4/VP1.4), built on the first scrub rather
  /// than on entry: it reads the repository and the native decoder, neither of
  /// which a session that never drags the bar should pay for.
  ScrubPreviewService? _preview;

  /// Captured so teardown/route pops can update the session without touching
  /// `ref` (same reason as [_controller]).
  late final PlaybackSessionController _session;

  /// Captured for the same reason: `dispose` must release the panel and the
  /// system UI.
  late final FullscreenController _fullscreen;

  /// Panel keep-awake while playing (design §9) and brightness/volume for the
  /// gesture layer, both behind the app-owned seam (VP2.3).
  late final PlayerDeviceControls _device;

  /// The keep-awake state last pushed to the platform, so a repeated tick with
  /// the same status never re-hits the plugin.
  bool _screenAwake = false;

  /// Set when this page already decided the session's fate (docked by a drag),
  /// so `dispose` does not collapse it a second time.
  bool _sessionHandedOff = false;

  /// Lock mode (VP5.6): drives the inert gesture layer and the lock overlay.
  /// A plain [ValueNotifier] (not a provider) because, like [PlayerChromeController],
  /// one lock belongs to one player page and must die with it.
  final ValueNotifier<bool> _locked = ValueNotifier<bool>(false);

  /// The portrait scroll position, kept across a fullscreen round trip so
  /// leaving fullscreen drops the user back where they were (VP5.5, design §10).
  /// The scroll view only exists in the portrait tree, so the offset is captured
  /// on entry (while [_scrollController] still has clients) and re-applied after
  /// the view is rebuilt on exit.
  final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _item = widget.item;
    _controller = ref.read(playbackControllerProvider);
    _watchProgress = ref.read(watchProgressServiceProvider);
    _session = ref.read(playbackSessionProvider.notifier);
    _fullscreen = ref.read(fullscreenControllerProvider.notifier);
    _device = ref.read(playerDeviceControlsProvider);
    // Bound to the controller captured here: `build` watches the same provider,
    // and a different instance only ever arrives with a new State (tests).
    _chrome = PlayerChromeController(state: _controller.state);
    // Claim the session before the first frame so the shell never renders a
    // stale mini player for the item this page is about to play (ADR-014).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.adopt(widget.item);
      _startPlayback();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // `ref` is unsafe here (the element is already deactivated), hence the
    // captured references (house rule: cancel work, release resources).
    _playToken++;
    _chrome.dispose();
    _locked.dispose();
    _scrollController.dispose();
    // Leaving the page releases the panel: a hidden player must not keep the
    // screen on (VP2.3).
    if (_screenAwake) unawaited(_device.keepScreenAwake(false));
    _detachProgressListener();
    unawaited(_watchProgress.flush(_item.id));
    super.dispose();
  }

  /// Docks the session into the mini player unless this page already did.
  ///
  /// The session owns "what is playing": closing the page docks the item into
  /// the mini player and leaves the engine running, so only an explicit close
  /// (dock dismissal, Reels taking over) stops it (ADR-014).
  ///
  /// Called from the route's [PopScope] rather than `dispose`, because Riverpod
  /// forbids mutating a provider from a widget life-cycle; a pop callback runs
  /// before teardown and outside the build phase. A drag that already docked
  /// sets [_sessionHandedOff], keeping this a no-op.
  void _collapseSessionIfMine() {
    if (_sessionHandedOff) return;
    _sessionHandedOff = true;
    _session.collapse();
    unawaited(_fullscreen.restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // VP5.2: persist the latest position the moment the app leaves the
    // foreground, so an OS process suspend cannot lose a few seconds of watch.
    // Flush uses the captured service (never `ref`), so it is safe on
    // `detached` too. Background playback itself is left running — that policy
    // belongs to [AudioFocusCoordinator] (background audio / PiP hold focus),
    // so the engine is deliberately not paused here.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_watchProgress.flush(_item.id));
    }
    // Backgrounding mid-fullscreen must not strand the device in immersive
    // landscape once the user comes back to something else (plan M5).
    if (state == AppLifecycleState.paused) {
      unawaited(ref.read(fullscreenControllerProvider.notifier).restore());
    }
  }

  Future<void> _startPlayback() async {
    if (!mounted) return;
    final token = ++_playToken;

    // A one-shot session starts unlooped, but the toolbar's Loop pill makes
    // looping a user choice (VP3.4); the controller carries the flag across
    // play() calls, so every (re)start re-asserts it.
    await _controller.setLooping(ref.read(videoLoopNotifierProvider));
    if (token != _playToken || !mounted) return;

    final result = await ref
        .read(playbackSourceResolverProvider)
        .resolveForItem(_item);
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

    // Publish the item's title for the media notification / lock screen
    // (P13-03). Safe label only — never the resolved URI.
    ref.read(nowPlayingProvider.notifier).setTitle(_item.title);

    await _controller.play(source);
    if (token != _playToken || !mounted) return;

    // Resume from stored progress once the engine has a loaded duration
    // (P5-08/LIB-002). Failure is silent: playback simply starts over.
    final resume = await _watchProgress.resumePosition(_item.id);
    if (token != _playToken || !mounted || resume == null) return;
    // Skip an end-of-media resume point: seeking to (or past) the final frame
    // leaves the video frozen on a last frame — often black — that reads as
    // "nothing plays / no video." A stale progress near the end is treated as
    // "watch again from the start."
    final duration = _controller.state.value.duration;
    if (duration > Duration.zero && resume >= duration) return;
    await _controller.seekTo(resume);
  }

  /// Switches the page to [item] in place (an "Up Next" tap): flushes the
  /// previous item's position, re-resolves the new source and restarts playback
  /// from that item's own resume point.
  void _switchTo(VideoItemSummary item) {
    if (item.id == _item.id) return;
    final previous = _item;
    unawaited(_watchProgress.flush(previous.id));
    // The previous item's memoised location is not this item's source, and a
    // later return to it may see changed sources (VP2.4).
    _preview?.invalidate();
    setState(() => _item = item);
    // A new video must not inherit the last one's subtitles (VP4.3).
    ref.read(captionsProvider.notifier).clear();
    // A new source is a new picture: an unlocked aspect choice falls back to
    // Fit, while a locked one stays as the user left it (VP4.4).
    ref.read(aspectRatioLockNotifierProvider.notifier).sourceChanged();
    _chrome.show();
    // The queue promised this video; once it is on screen it has been consumed
    // (VP3.5), so it must not also appear as a row below it.
    ref.read(playbackQueueProvider.notifier).remove(item.id);
    ref.read(playbackSessionProvider.notifier).adopt(item);
    unawaited(_startPlayback());
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
      _syncScreenAwake(state.isPlaying);
      unawaited(
        _watchProgress.reportPosition(id: _item.id, position: state.position),
      );
      // Flush at pause/error boundaries so even a short watch persists.
      if (state.status == PlaybackStatus.paused ||
          state.status == PlaybackStatus.error) {
        unawaited(_watchProgress.flush(_item.id));
      }
    }

    controller.state.addListener(listener);
    _progressSource = controller;
    _progressListener = listener;
  }

  void _detachProgressListener() {
    final listener = _progressListener;
    if (listener != null) _progressSource?.state.removeListener(listener);
    _progressSource = null;
    _progressListener = null;
  }

  /// Holds the screen awake while the video plays and lets it sleep otherwise
  /// (design §9). Only a real change reaches the platform.
  void _syncScreenAwake(bool playing) {
    if (_screenAwake == playing) return;
    _screenAwake = playing;
    unawaited(_device.keepScreenAwake(playing));
  }

  /// Shows the chrome without arming the auto-hide, for actions that leave the
  /// user looking at the controls (a settings chip, a snap-back).
  void _revealChrome() => _chrome.show(autoHide: false);

  /// Enters or leaves lock mode (VP5.6). Locking hides the chrome and freezes
  /// every gesture, leaving only the tap-to-reveal unlock affordance; unlocking
  /// brings the chrome back. Haptic feedback confirms both transitions. Leaving
  /// fullscreen auto-unlocks via the listener in [build], so the lock is always
  /// a fullscreen-only affordance.
  void _setLocked(bool locked) {
    if (_locked.value == locked) return;
    _locked.value = locked;
    _chrome.setLocked(locked);
    unawaited(HapticFeedback.mediumImpact());
    if (!locked) _revealChrome();
  }

  /// Enters fullscreen for the current item (VP5.5, design §10). The portrait
  /// scroll offset is captured first — while [_scrollController] still has
  /// clients — so leaving fullscreen can drop the user back where they were,
  /// and a landscape rotation is requested only for landscape/unknown sources:
  /// a vertical video stays portrait while immersive.
  void _enterFullscreen() {
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
    final vertical = isVerticalVideo(_item.widthPx, _item.heightPx);
    unawaited(
      ref
          .read(fullscreenControllerProvider.notifier)
          .enter(allowLandscape: !vertical),
    );
  }

  /// Fullscreen on/off from a single place — the F shortcut (VP7.1) and the
  /// top-bar button share this so the scroll-offset bookkeeping cannot drift.
  void _toggleFullscreen() {
    if (ref.read(fullscreenControllerProvider)) {
      unawaited(ref.read(fullscreenControllerProvider.notifier).exit());
      _revealChrome();
      return;
    }
    _enterFullscreen();
  }

  /// The frame to show in the seek bar's bubble for [position] (VP2.4).
  ///
  /// Built lazily and memoised: the service reads the item's sources once and
  /// then only decodes frames, so a drag never touches persistence per update.
  Future<Uint8List?> _framePreview(Duration position) async {
    if (!mounted) return null;
    final service = _preview;
    if (service != null) return service.frameAt(_item.id, position);
    // First scrub: build the service from the provider and keep it for the
    // next drag. The type annotation is explicit because `ref.read` would
    // otherwise infer a nullable `T` from the nullable field it is stored in.
    final ScrubPreviewService created = ref.read(scrubPreviewServiceProvider);
    _preview = created;
    return created.frameAt(_item.id, position);
  }

  /// Flips the Loop pill and applies it to the engine immediately (VP3.4).
  void _toggleLoop() {
    final loop = ref.read(videoLoopNotifierProvider.notifier).toggle();
    unawaited(_controller.setLooping(loop));
  }

  /// Docks the session into the mini player and closes the page (ADR-014).
  void _dockToMini() {
    _chrome.hide();
    _sessionHandedOff = true;
    _session.collapse();
    unawaited(_fullscreen.restore());
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // Forward every position tick to the throttled progress service and
    // flush at state boundaries (pause/error) so a short watch persists.
    final controller = ref.watch(playbackControllerProvider);
    _attachProgressListener(controller);
    final pip = ref.watch(pipCoordinatorProvider);
    final fullscreen = ref.watch(fullscreenControllerProvider);

    // The lock lives only in fullscreen (VP5.6): leaving it by any route — the
    // chevron, the exit button, backgrounding, a dock — must never strand the
    // page locked behind an inert gesture layer.
    ref.listen<bool>(fullscreenControllerProvider, (previous, next) {
      if (!next && _locked.value) _setLocked(false);
      // Leaving fullscreen rebuilds the portrait scroll view from scratch; hop
      // back to the offset captured on entry once it has re-attached (VP5.5).
      if (previous == true && !next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _scrollController.hasClients &&
              _savedScrollOffset > 0) {
            _scrollController.jumpTo(_savedScrollOffset);
          }
        });
      }
    });

    // Android PiP captures the whole Flutter window, so every overlay chrome —
    // the app bar and the playback controls — must disappear while floating
    // (PLAY-010). A chrome-less body leaves only the video for the float window.
    return ValueListenableBuilder<bool>(
      valueListenable: pip.inPip,
      builder: (context, inPip, _) {
        if (inPip) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(child: VideoSurface()),
          );
        }
        return PlayerKeyboardShortcuts(
          controller: controller,
          // Lock mode freezes every gesture (VP5.6); the keyboard is no way
          // around that.
          guard: () => _locked.value,
          onToggleFullscreen: _toggleFullscreen,
          child: PopScope(
            // Every way out of the page — back gesture, app bar, system pop —
            // hands the item to the mini player before teardown (ADR-014).
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) _collapseSessionIfMine();
            },
            child: Scaffold(
              backgroundColor: fullscreen ? Colors.black : null,
              // No app bar (VP3.1): back, title and PiP fade with the overlay, so
              // the picture owns the top of the page and nothing is duplicated.
              body: fullscreen ? _buildFullscreen(pip) : _buildPage(pip),
            ),
          ),
        );
      },
    );
  }

  /// Fullscreen: the video fills the screen and only the overlay chrome sits on
  /// top of it (no metadata, no action toolbar — plan M5).
  Widget _buildFullscreen(PipCoordinator pip) {
    // The fullscreen overlay keeps its controls clear of notches, cutouts and
    // rounded corners (VP5.5, design §10): the device padding plus a larger
    // base inset, since this branch no longer sits inside the page's SafeArea.
    final insets = MediaQuery.of(context).padding;
    const base = AppSpacing.md;
    final overlayPadding = EdgeInsets.fromLTRB(
      base + insets.left,
      base + insets.top,
      base + insets.right,
      base + insets.bottom,
    );
    return _PlayerBox(
      item: _item,
      controller: _controller,
      chrome: _chrome,
      overlayPadding: overlayPadding,
      // Fullscreen has no app bar either, so the chevron is the way back to the
      // page (VP2.5).
      onMinimise: () {
        unawaited(ref.read(fullscreenControllerProvider.notifier).exit());
        _revealChrome();
      },
      topActions: _topBarActions(pip: pip, fullscreen: true),
      // The vertical drag belongs to the brightness/volume gesture here.
      deviceGestures: true,
      onDragDown: (delta) => _dragDown += delta,
      onDragEnd: (velocity) => _handleDockDrag(velocity),
      framePreview: _framePreview,
      onSkipToNext: _skipToNext(),
      lock: _locked,
      onUnlock: () => _setLocked(false),
    );
  }

  /// The normal page: pinned player, then metadata, actions and Up Next.
  Widget _buildPage(PipCoordinator pip) {
    // The pinned header needs a concrete extent. 16:9 at the page width is the
    // default for every source; a vertical one may grow past it when the user
    // asks for Expand (VP3.2).
    final media = MediaQuery.of(context);
    final expanded = ref.watch(verticalExpandNotifierProvider);
    final loop = ref.watch(videoLoopNotifierProvider);
    final vertical = isVerticalVideo(_item.widthPx, _item.heightPx);
    final playerHeight = portraitPlayerHeight(
      width: media.size.width,
      // The page sits in a SafeArea, so the status bar is not available.
      availableHeight: media.size.height - media.padding.top,
      expanded: expanded,
      videoWidth: _item.widthPx,
      videoHeight: _item.heightPx,
    );

    // The player sits under the status bar (design §4 keeps the page in a
    // SafeArea) now that no app bar reserves that space for it.
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        key: const ValueKey('player_scroll_view'),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DockedPlayerHeader(
              height: playerHeight < AppSizes.minTapTarget * 2
                  ? AppSizes.minTapTarget * 2
                  : playerHeight,
              child: _PlayerBox(
                item: _item,
                controller: _controller,
                chrome: _chrome,
                // Back is the overlay's arrow, not an app bar's (VP3.1).
                onBack: () => Navigator.of(context).maybePop(),
                topActions: _topBarActions(pip: pip, fullscreen: false),
                // Only a vertical source can be expanded, so only it carries
                // the control (VP3.2).
                expanded: vertical && expanded,
                onToggleExpand: vertical
                    ? () => ref
                          .read(verticalExpandNotifierProvider.notifier)
                          .toggle()
                    : null,
                onDragDown: (delta) => _dragDown += delta,
                onDragEnd: (velocity) => _handleDockDrag(velocity),
                framePreview: _framePreview,
                completedAction: _completedAction(),
                onSkipToNext: _skipToNext(),
                lock: _locked,
                onUnlock: () => _setLocked(false),
              ),
            ),
          ),
          SliverToBoxAdapter(child: PlayerMetadataPanel(item: _item)),
          SliverToBoxAdapter(
            child: PlayerActionRow(
              item: _item,
              loop: loop,
              onToggleLoop: _toggleLoop,
            ),
          ),
          SliverToBoxAdapter(
            child: PlayerUpNextSection(current: _item, onPlay: _switchTo),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ],
      ),
    );
  }

  /// The row the queue would roll into next, or null when there is none. Read
  /// from the same list the Up Next section draws, so an error "Skip to next"
  /// and the autoplay countdown always name the same video (VP3.5, VP5.1).
  VideoItemSummary? _nextUp() {
    final rows = ref.watch(upNextRowsProvider(_item.id));
    return rows.isEmpty ? null : rows.first;
  }

  /// The error panel's "Skip to next" action, or null when there is nothing to
  /// skip to (VP5.1) — which removes the button rather than leaving a dead one.
  VoidCallback? _skipToNext() {
    final VideoItemSummary? next = _nextUp();
    return next == null ? null : () => _switchTo(next);
  }

  /// The end-of-video countdown, or null when nothing should roll into the
  /// next video (autoplay switched off, or no queued/suggested row left).
  ///
  /// Read from the same list the section draws, so the promised video is
  /// always the top row (VP3.5).
  Widget? _completedAction() {
    if (!ref.watch(autoplayEnabledProvider)) return null;
    final VideoItemSummary? next = _nextUp();
    if (next == null) return null;
    return PlayerAutoplayCountdown(item: next, onPlay: () => _switchTo(next));
  }

  /// Top-bar controls for the overlay (VP2.5, VP3.1).
  ///
  /// An action slot rather than hard-coded buttons: PiP joins the page chrome
  /// here, the settings gear follows in VP4.1, captions in VP4.3 and lock in
  /// VP5.6.
  List<Widget> _topBarActions({
    required PipCoordinator pip,
    required bool fullscreen,
  }) => [
    // Offered only where the host supports PiP (feature-detected via the
    // coordinator, so no dead button on unsupported devices).
    ValueListenableBuilder<bool>(
      valueListenable: pip.supported,
      builder: (context, supported, _) {
        if (!supported) return const SizedBox.shrink();
        return IconButton(
          key: const ValueKey('player_pip_button'),
          tooltip: 'Picture-in-picture',
          onPressed: () => unawaited(pip.enter()),
          icon: const Icon(Icons.picture_in_picture_alt),
        );
      },
    ),
    // The captions toggle (VP4.3). With a sidecar loaded it shows/hides the
    // overlay; with none it opens the sheet straight onto the Captions page so
    // the button is never a dead affordance.
    Consumer(
      builder: (context, ref, _) {
        final captions = ref.watch(captionsProvider);
        return IconButton(
          key: const ValueKey('player_captions_button'),
          tooltip: 'Captions',
          onPressed: () {
            if (captions.hasFile) {
              ref.read(captionsProvider.notifier).setEnabled(!captions.enabled);
              _revealChrome();
            } else {
              unawaited(
                openPlayerSettingsSheet(
                  context,
                  item: _item,
                  chrome: _chrome,
                  initialPage: PlayerSettingsPage.captions,
                ),
              );
            }
          },
          icon: Icon(
            captions.enabled && captions.hasFile
                ? Icons.closed_caption
                : Icons.closed_caption_off,
          ),
        );
      },
    ),
    // The settings gear (VP4.1): the sheet holds the chrome up while it is open
    // and writes through the same providers as the page behind it.
    IconButton(
      key: const ValueKey('player_settings_button'),
      tooltip: 'Settings',
      onPressed: () => unawaited(
        openPlayerSettingsSheet(context, item: _item, chrome: _chrome),
      ),
      icon: const Icon(Icons.settings_outlined),
    ),
    if (fullscreen) ...[
      // Lock mode (VP5.6) lives only in fullscreen: it hides the chrome and
      // freezes every gesture, leaving the tap-to-reveal unlock affordance.
      IconButton(
        key: const ValueKey('player_lock_button'),
        tooltip: 'Lock',
        onPressed: () => _setLocked(true),
        icon: const Icon(Icons.lock_outline),
      ),
      IconButton(
        key: const ValueKey('player_fullscreen_exit_button'),
        tooltip: 'Exit fullscreen',
        onPressed: () {
          unawaited(ref.read(fullscreenControllerProvider.notifier).exit());
          _revealChrome();
        },
        icon: const Icon(Icons.fullscreen_exit),
      ),
    ] else
      IconButton(
        key: const ValueKey('player_fullscreen_button'),
        tooltip: 'Fullscreen',
        onPressed: _enterFullscreen,
        icon: const Icon(Icons.fullscreen),
      ),
  ];

  /// Ends a vertical drag on the video: past the threshold (or with enough
  /// downward velocity) it docks into the mini player, otherwise it snaps back
  /// and re-reveals the chrome.
  void _handleDockDrag(double velocity) {
    final dragged = _dragDown;
    _dragDown = 0;
    if (dragged > AppSizes.dockDragThreshold || velocity > 700) {
      _dockToMini();
      return;
    }
    _revealChrome();
  }
}

/// The video plus its overlay chrome, gesture layer and progress line.
///
/// Kept separate from the page so the fullscreen branch renders exactly the
/// same surface, controls and gestures as the docked one.
class _PlayerBox extends StatelessWidget {
  const _PlayerBox({
    required this.item,
    required this.controller,
    required this.chrome,
    required this.topActions,
    required this.onDragDown,
    required this.onDragEnd,
    required this.framePreview,
    required this.lock,
    required this.onUnlock,
    this.onBack,
    this.onMinimise,
    this.expanded = false,
    this.onToggleExpand,
    this.completedAction,
    this.onSkipToNext,
    this.overlayPadding = EdgeInsets.zero,
    this.deviceGestures = false,
  });

  final VideoItemSummary item;
  final PlaybackController controller;

  /// Owns chrome visibility; the overlay and gestures both report into it.
  final PlayerChromeController chrome;

  /// Host controls for the overlay top bar (PiP, fullscreen).
  final List<Widget> topActions;

  /// Leaves the page (portrait). Null in fullscreen, which uses the chevron.
  final VoidCallback? onBack;

  /// Leaves fullscreen; null hides the chevron (portrait shows the arrow).
  final VoidCallback? onMinimise;

  /// Whether the portrait box is grown past 16:9 for a vertical source, and
  /// the control that flips it (VP3.2). Null hides the control.
  final bool expanded;
  final VoidCallback? onToggleExpand;

  /// Swipe-down bookkeeping for the mini-player dock (ADR-014).
  final void Function(double delta) onDragDown;
  final void Function(double velocity) onDragEnd;

  /// Scrub-frame loader for the seek bar's bubble (VP2.4/VP1.4).
  final Future<Uint8List?> Function(Duration position) framePreview;

  /// The overlay's end-of-video widget (autoplay countdown, VP3.5). Null when
  /// there is nothing to roll into.
  final Widget? completedAction;

  /// The error state's "Skip to next" action (VP5.1). Null when there is no
  /// next row, which removes the button rather than leaving a dead one.
  final VoidCallback? onSkipToNext;

  /// Notch / cutout insets handed to the overlay chrome in fullscreen (VP5.5).
  /// Zero in portrait, where the page is already inside a [SafeArea].
  final EdgeInsets overlayPadding;

  /// Whether brightness/volume/pinch gestures are live. True in fullscreen,
  /// where the vertical drag has no other owner; false in portrait so the
  /// swipe-down dock keeps it.
  final bool deviceGestures;

  /// Lock mode (VP5.6): when true every gesture (transport, seek, scrub, dock)
  /// is frozen and the [PlayerLockOverlay] swallows touches, leaving only
  /// [onUnlock]. Listened to here so the box rebuilds when the page locks.
  final ValueListenable<bool> lock;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    // VP7.1 reduced motion: the chrome still appears/disappears, it just stops
    // fading — the visibility change itself is essential, the transition is not.
    final reduceMotion = AppMotion.reduceAnimations(context);
    final fadeIn = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final fadeOut = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return ValueListenableBuilder<bool>(
      valueListenable: lock,
      builder: (context, locked, _) => GestureDetector(
        key: const ValueKey('player_video_area'),
        behavior: HitTestBehavior.opaque,
        // The dock and the gesture layer never share an axis: this detector owns
        // the vertical drag in portrait, the layer owns it in fullscreen
        // (brightness / volume). Two vertical recognisers would fight the arena.
        // A locked screen drops the dock drag too — "disables every gesture."
        onVerticalDragUpdate: deviceGestures || locked
            ? null
            : (details) => onDragDown(details.delta.dy),
        onVerticalDragEnd: deviceGestures || locked
            ? null
            : (details) => onDragEnd(details.primaryVelocity ?? 0),
        child: ColoredBox(
          color: Colors.black,
          child: ValueListenableBuilder<PlaybackState>(
            // The overlay and the gestures both need the state, so the host owns
            // the rebuild scope instead of each leaf listening separately.
            valueListenable: controller.state,
            builder: (context, state, _) => ValueListenableBuilder<bool>(
              valueListenable: chrome,
              builder: (context, visible, _) => Stack(
                fit: StackFit.expand,
                children: [
                  // Keyed so the shell's Hero can carry the same picture into the
                  // mini player dock (plan M6). The RepaintBoundary fences the
                  // video layer off from the overlay: a chrome rebuild (every
                  // position tick) must never repaint the decoded frame (VP7.2).
                  Hero(
                    tag: 'player_surface_${item.id.value}',
                    child: const RepaintBoundary(
                      key: ValueKey('player_video_repaint'),
                      child: VideoSurface(),
                    ),
                  ),
                  // Above the picture, below the chrome: a hidden bar leaves the
                  // gestures live, a visible one gets the first touch.
                  PlayerGestureLayer(
                    state: state,
                    controller: controller,
                    chrome: chrome,
                    locked: locked,
                    deviceGestures: deviceGestures,
                  ),
                  // The active subtitle line, painted by the app so its size and
                  // background honour the settings sheet (VP4.3). Kept below the
                  // chrome and above the bottom control bar.
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: AppSizes.playerCaptionInset,
                      ),
                      child: PlayerCaptionOverlay(),
                    ),
                  ),
                  // Its own layer as well: the overlay repaints on every tick,
                  // the picture beneath it must not (VP7.2).
                  RepaintBoundary(
                    key: const ValueKey('player_overlay_repaint'),
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: AnimatedOpacity(
                        duration: visible ? fadeIn : fadeOut,
                        opacity: visible ? 1 : 0,
                        child: PlayerOverlay(
                          state: state,
                          controller: controller,
                          chrome: chrome,
                          title: item.title,
                          onBack: onBack,
                          onMinimise: onMinimise,
                          actions: topActions,
                          framePreview: framePreview,
                          expanded: expanded,
                          onToggleExpand: onToggleExpand,
                          completedAction: completedAction,
                          onSkipToNext: onSkipToNext,
                          padding: overlayPadding,
                        ),
                      ),
                    ),
                  ),
                  // The loading phase has nothing to act on yet, so its centered
                  // spinner sits above the chrome and ignores visibility: it reads
                  // even while the controls are faded away (VP5.1, design §9).
                  PlayerLoadingIndicator(state: state),
                  // With the chrome away, a 2 dp playhead line keeps the position
                  // readable without the bar (VP2.5).
                  if (!visible)
                    IgnorePointer(child: PlayerProgressLine(state: state)),
                  // Topmost while locked: swallows every touch so nothing behind
                  // it can seek / scrub / pause, and reveals one unlock button on
                  // tap (VP5.6).
                  PlayerLockOverlay(locked: locked, onUnlock: onUnlock),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned sliver that keeps the 16:9 player docked while the metadata scrolls
/// (DESIGN.md §5 "sticky/dockable player").
class _DockedPlayerHeader extends SliverPersistentHeaderDelegate {
  const _DockedPlayerHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(child: child),
      );

  @override
  bool shouldRebuild(covariant _DockedPlayerHeader oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
