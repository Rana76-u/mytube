import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/reels/reel_gesture_coordinator.dart';
import 'package:mytube/features/reels/reel_gesture_feedback.dart';
import 'package:mytube/features/reels/reels_fit_policy.dart';
import 'package:mytube/features/reels/reels_queue.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';
import 'package:mytube/features/reels/reels_source_preloader.dart';
import 'package:mytube/features/reels/reels_video_surface.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/pip_coordinator.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Reels tab — the vertical, swipe-first queue with autoplay, looping, an
/// on-demand control overlay, and limited adjacent preloading (PLAY-001..004,
/// PLAY-008).
///
/// A full-screen [PageView] walks the [ReelsQueue] one reel per page. When this
/// tab is [active] the current reel starts playing on entry, loops until the
/// user swipes, and the newly-revealed reel autoplays on the next swipe
/// (PLAY-002/PLAY-003). Tapping the playing reel toggles a minimal control
/// overlay backed by the shared [PlaybackControls] (PLAY-004/PLAY-005); it
/// auto-hides so the video stays unobstructed. The overlay also carries a
/// one-tap fit toggle, because a reel scales itself from the clip's shape
/// rather than from the app-wide display mode ([ReelsVideoSurface]).
///
/// [PlaybackSourceResolver] turns a reel into a short-lived [PlayableSource];
/// a [ReelsSourcePreloader] warms the next reel ahead of the swipe and cancels
/// that work when a rapid swipe makes it stale (PLAY-008). [PlaybackController]
/// plays and loops, and [ReelsVideoSurface] paints the current page. When a
/// preload lands the screen also pre-warms that reel's engine in the background
/// (`prewarm`, P7-11), so the swipe promotes a ready decoder instead of paying
/// the open+initialize delay mid-gesture — a gapless cut.
///
/// The Reel gesture controller (Reel_Video_Controller.md, RC-02) rides on top
/// of this: each interactive page wraps its surface in a passive [Listener]
/// that forwards raw pointers to a [ReelGestureCoordinator], which arbitrates
/// single tap → play/pause, center double tap → favourite, side double tap →
/// ±10s skip, and horizontal drag → precise-seek preview committed on release.
/// The Listener never joins the gesture arena, so the [PageView]'s vertical
/// paging is untouched (§3 rule 6), and the tappable controls (favourite,
/// controls toggle, overlay) sit in a screen-level Stack *above* the pages —
/// their pointers hit-test there first and structurally cannot reach the
/// arbiter (§3 rule 1). Transient feedback ([ReelTapIndicator],
/// [ReelSeekFeedback], [ReelSeekPreviewBar]) is IgnorePointer-wrapped and
/// display-only. The long-press speed actions (§2G/§2H) drive the shared
/// [PlaybackController.setSpeed]: a hold ramps 1.0x→2.0x with a live
/// [ReelSpeedIndicator], a downward swipe locks that exact speed (persisted
/// across the release as a [ReelSpeedLockIndicator]), and a second downward
/// swipe unlocks back to 1.0x — all cleared on a reel change so a lock never
/// leaks to the next clip or the dedicated player.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key, this.active = true});

  /// Whether the Reels tab is the visible tab. Playback only runs while true,
  /// so switching to another tab stops the reel (the host drives this from the
  /// selected bottom-nav index).
  final bool active;

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();

  /// The app-owned controller, captured once while mounted. `dispose()` cannot
  /// read providers (the element is already deactivated), so playback teardown
  /// uses this stored reference instead of `ref.read` (PLAY-002/PLAY-003).
  late final PlaybackController _controller;

  /// Warms the next reel's source and drops stale preloads on rapid swipes
  /// (PLAY-008). Also created in `initState` so `dispose()` can clear it without
  /// touching `ref`.
  late final ReelsSourcePreloader _preloader;

  /// App-owned PiP coordinator (P13-04, PLAY-010). Captured in `initState` so
  /// `dispose()` can detach its listeners without touching `ref`.
  late final PipCoordinator _pip;

  /// Mirrors [_pip.inPip] / [_pip.supported] into widget state so the reel hides
  /// its overlay chrome while floating and only offers a PiP control where the
  /// host supports it. A [ValueNotifier] fires only on an actual change, so an
  /// unsupported host leaves these false and the existing tests are unaffected.
  bool _inPip = false;
  bool _pipSupported = false;

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

  /// The current reel's manually pinned fit, or null to let
  /// [reelsBoxFit] pick from the clip's aspect. Set by the overlay toggle and
  /// cleared whenever a different reel starts, because the next clip has a
  /// different shape to respect.
  BoxFit? _fitOverride;

  /// Auto-hides the overlay so a tap reveals controls without leaving them on
  /// the video permanently.
  Timer? _controlsHideTimer;

  /// How long the overlay stays up after a tap before auto-hiding.
  static const Duration _controlsTimeout = Duration(seconds: 3);

  /// How many reels ahead of the current one to keep warm. Deliberately small —
  /// PLAY-008 asks for *limited* preloading (ARCHITECTURE §8: "preload only a
  /// small number of adjacent items").
  static const int _preloadAhead = 1;

  // --- Reel gesture controller (RC-02) -------------------------------------

  /// Arbitrates taps, double taps, and horizontal seeks for the current reel.
  /// Pure Dart with an injected clock, so the widget layer only forwards
  /// pointers and applies the emitted actions.
  late final ReelGestureCoordinator _coordinator;

  /// Reference point for the coordinator's monotonic clock. `clock.now()`
  /// (package:clock) is zone-patched inside widget tests — flutter_test runs
  /// every `testWidgets` body on a fake clock advanced by `pump` — which
  /// keeps gesture timing assertions deterministic; on device it falls back
  /// to wall time, good enough for tap windows and ramps. (`DateTime.now()`
  /// would *not* work here: zones cannot patch it, so fake-async pumps would
  /// leave the double-tap windows unresolvable in tests.)
  final DateTime _gestureEpoch = clock.now();

  /// The one-shot timer driving the coordinator's deadlines; re-armed from
  /// `nextDeadline` after every pointer event, so nothing keeps ticking once
  /// a gesture ends.
  Timer? _gestureTickTimer;

  /// Resolves the gesture surface's [RenderBox] for global→local coordinates.
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'reels_gesture_surface');

  /// Center play/pause glyph; persistent while paused, timed while playing.
  IconData? _tapIndicator;
  Timer? _tapIndicatorTimer;

  /// Side chip confirming the last double-tap skip; auto-hides.
  ({bool forward, int seconds})? _seekFeedback;
  Timer? _seekFeedbackTimer;

  /// Live horizontal-drag preview; null while no seek gesture is in flight.
  Duration? _seekPreviewFrom;
  Duration? _seekPreviewTarget;
  Duration? _seekPreviewDuration;

  /// The current reel's favourite state, seeded from [VideoItemSummary] when
  /// the reel starts and flipped optimistically by [ReelGestureCoordinator]
  /// actions; reverted if the repository write fails. The repository stays
  /// the single source of truth (§5 FavoriteRepository).
  bool _favourite = false;

  /// Live long-press boost speed shown by [ReelSpeedIndicator], or null while
  /// no boost is held. Every value mirrored here is also pushed to the engine
  /// through [PlaybackController.setSpeed], so the displayed multiplier and
  /// the actual playback speed cannot drift apart (§6).
  double? _boostSpeed;

  /// The persisted locked speed shown by [ReelSpeedLockIndicator], or null
  /// while unlocked. Mirrors [ReelGestureCoordinator.lockedSpeed]; cleared on
  /// a reel change because this app scopes the lock to a single reel session
  /// (§2H "until the application applies a documented lifecycle rule").
  double? _lockedSpeed;

  /// Surface-local centre of the in-flight double-tap heart burst (§2C), or
  /// null while none is showing. The [ReelHeartBurst] clears it itself when its
  /// one-shot animation completes, and [_clearGestureUi] drops it on a reel
  /// change/teardown — so the celebration never survives the gesture that made
  /// it and no timer is left pending.
  Offset? _heartBurstAt;

  /// Bumped per burst so two consecutive favourite double taps each replay the
  /// pop instead of reusing an already-mounted, already-finished one.
  int _heartBurstSeq = 0;

  /// The most recent pointer-up position in surface-local coordinates, captured
  /// before the coordinator runs so a centre double tap can drop its heart where
  /// the finger actually lifted (§2C "approximate location of the double tap").
  Offset? _lastPointerLocal;

  /// The gesture surface's current size, refreshed on every pointer event so
  /// the heart burst can clamp itself fully on-screen in any orientation.
  Size? _surfaceSize;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playbackControllerProvider);
    _pip = ref.read(pipCoordinatorProvider);
    _pip.inPip.addListener(_onPipChanged);
    _pip.supported.addListener(_onPipChanged);
    _onPipChanged();
    _coordinator = ReelGestureCoordinator(
      config: const ReelGestureConfig(),
      onAction: _onGestureAction,
    );
    _controller.state.addListener(_syncGestureContext);
    _syncGestureContext();
    _preloader = ReelsSourcePreloader(
      resolver: ref.read(playbackSourceResolverProvider),
      onWarmed: _onSourceWarmed,
    );
    if (widget.active) {
      // Queue data may already be loaded (tab kept alive in the IndexedStack),
      // so schedule the first autoplay once the frame is up.
      _syncPlayback();
    }
    // Observe app lifecycle in its own right (P13-05): the Reels tab is kept
    // alive by the shell's IndexedStack, so it can release / re-arm its spare
    // decoder on background / resume without the shell knowing about playback.
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _controlsHideTimer?.cancel();
    _clearGestureUi();
    _coordinator.dispose();
    _controller.state.removeListener(_syncGestureContext);
    _pip.inPip.removeListener(_onPipChanged);
    _pip.supported.removeListener(_onPipChanged);
    _preloader.clear();
    _controller.setLooping(false);
    _controller.stop();
    unawaited(_controller.dropPrewarm());
    _pageController.dispose();
    super.dispose();
  }

  /// Mirrors the coordinator's PiP listenables into widget state. Called from
  /// `initState` for the initial values and on every subsequent change so the
  /// reel can hide chrome while floating and gate the PiP control on support.
  void _onPipChanged() {
    if (!mounted) return;
    setState(() {
      _inPip = _pip.inPip.value;
      _pipSupported = _pip.supported.value;
    });
  }

  // --- App lifecycle: resource disposal + resume parity (P13-05) ------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The live reel deliberately keeps playing into the background (P13-02
    // background audio), but the single idle prewarmed *next-reel engine* is a
    // spare decoder that should not be held while the app is off-screen —
    // Android can reclaim background decoders anyway. Releasing it on the way
    // out frees the codec, and re-arming it on resume restores the gapless
    // swipe the user expects next (PLAY-012). `inactive` (app-switcher peek /
    // transient dialog) and `detached` (process ending) stay no-ops so a quick
    // glance never churns the decoder.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_controller.dropPrewarm());
      case AppLifecycleState.resumed:
        _rewarmNextEngine();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Re-opens a background engine for the reel after the current one when the
  /// app returns to the foreground after [didChangeAppLifecycleState] released
  /// it. The resolved source is usually still cached, so no re-resolve is
  /// needed; a missing entry just restarts the warm, whose `onWarmed` callback
  /// re-prewarms the engine when it lands.
  void _rewarmNextEngine() {
    if (!mounted || !widget.active) return;
    final queue = ref.read(reelsQueueProvider).value;
    if (queue == null || queue.isEmpty) return;
    final nextIndex = queue.index + 1;
    if (nextIndex >= queue.length) return;
    final next = queue.items[nextIndex];
    final cached = _preloader.peek(next);
    if (cached != null) {
      unawaited(_controller.prewarm(cached));
    } else {
      _preloader.preload(next);
    }
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
  ///
  /// Deferred to the end of the frame on purpose. This runs from `initState`,
  /// from `didUpdateWidget` when the shell switches to the Reels tab, and from
  /// the `ref.listen` callback registered in [build] — all inside a widget
  /// lifecycle. [_playItem] publishes the now-playing label, which writes a
  /// provider, and Riverpod refuses provider mutations while the tree is
  /// building (they can leave two listeners of the same provider with
  /// different states). One coalesced post-frame callback keeps every entry
  /// point legal without scheduling the same start twice.
  void _syncPlayback() {
    if (!widget.active || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _startCurrentReel();
    });
  }

  /// Whether a [_syncPlayback] deferral is already queued for this element.
  bool _syncScheduled = false;

  /// The actual autoplay decision, run after the current frame is built.
  void _startCurrentReel() {
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
    // Publish the reel's human title for the media notification / lock screen
    // (P13-03). The last writer wins; the notification label is safe (never a
    // URI) and the coordinator hides the session whenever playback goes idle.
    ref.read(nowPlayingProvider.notifier).setTitle(item.title);
    // A new reel re-derives its fit from its own aspect ratio and drops the
    // previous reel's on-demand overlay: the controls belong to the reel they
    // were opened on, so a swipe never leaves them covering the next clip
    // (PLAY-004 "auto-hides so the video stays unobstructed").
    _fitOverride = null;
    _controlsHideTimer?.cancel();
    // A swipe is the documented lifecycle boundary for the speed lock and
    // every in-flight gesture: drop both, and re-seed the favourite display
    // from the incoming reel.
    _coordinator.resetForNewReel();
    _clearGestureUi();
    setState(() {
      _reelError = null;
      _controlsVisible = false;
      _favourite = item.isFavourite;
    });

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

  /// A preloaded source just landed for the next reel: pre-initialize its
  /// engine in the background so the eventual swipe promotes a ready decoder
  /// instead of paying the open+initialize delay mid-gesture (P7-11). This is
  /// best-effort — the controller never shows prewarm failures and holds at
  /// most one spare engine, so rapid swipes stay bounded.
  void _onSourceWarmed(VideoItemSummary item, PlayableSource source) {
    if (!mounted || !widget.active) return;
    // Only adjacent reels get an engine; never pre-warm what is already live.
    if (item.id == _playingItemId) return;
    unawaited(_controller.prewarm(source));
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
    _coordinator.resetForNewReel();
    _clearGestureUi();
    _preloader.clear();
    if (mounted) setState(() => _reelError = null);
    _controller.setLooping(false);
    _controller.stop();
    // Drop the prewarmed next-reel engine too; the queue cache is gone, so a
    // decoder for it would just idle (P7-11).
    unawaited(_controller.dropPrewarm());
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

  /// Flips the current reel between letterboxed (whole frame) and full-bleed
  /// (cropped) — both aspect-true. The first tap pins the mode the surface is
  /// already showing, so the button always reads as "switch to the other one".
  void _toggleReelFit() {
    final auto = reelsBoxFit(
      videoSize: _controller.state.value.videoSize,
      override: _fitOverride,
    );
    setState(() => _fitOverride = nextReelsBoxFit(auto));
  }

  // ---------------------------------------------------------------------------
  // Reel gesture controller (RC-02, Reel_Video_Controller.md §2/§3)
  // ---------------------------------------------------------------------------

  /// The coordinator's monotonic clock, anchored at [ReelsScreenState]'s
  /// construction. See [_gestureEpoch] for why this is deterministic in tests.
  Duration _gestureNow() => clock.now().difference(_gestureEpoch);

  /// Converts a pointer event into surface-local coordinates and refreshes
  /// the coordinator's geometry, so zone thresholds and the swipe→duration
  /// mapping track rotation/resizes without any listener plumbing.
  Offset? _localPointer(PointerEvent event) {
    final context = _surfaceKey.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    _surfaceSize = box.size;
    _coordinator.updateSurfaceSize(box.size);
    return box.globalToLocal(event.position);
  }

  void _onPointerDown(PointerDownEvent event) {
    final local = _localPointer(event);
    if (local == null) return;
    final now = _gestureNow();
    _coordinator.pointerDown(now, local);
    _scheduleGestureTick(now);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final local = _localPointer(event);
    if (local == null) return;
    _coordinator.pointerMove(_gestureNow(), local);
  }

  void _onPointerUp(PointerUpEvent event) {
    final local = _localPointer(event);
    if (local == null) return;
    // Capture before the coordinator runs: a centre double tap resolves
    // synchronously here and needs the lift point for its heart burst (§2C).
    _lastPointerLocal = local;
    final now = _gestureNow();
    _coordinator.pointerUp(now, local);
    _scheduleGestureTick(now);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final now = _gestureNow();
    _coordinator.pointerCancel(now);
    _scheduleGestureTick(now);
  }

  /// Arms the single one-shot timer for the coordinator's pending deadlines
  /// (double-tap window, long-press recognition, boost ramp). Deadlines are
  /// phase-scoped, so a finished gesture leaves nothing scheduled — a held
  /// finger can never keep a runaway timer ticking after release (§2G).
  void _scheduleGestureTick(Duration now) {
    _gestureTickTimer?.cancel();
    _gestureTickTimer = null;
    final deadline = _coordinator.nextDeadline(now);
    if (deadline == null) return;
    final wait = deadline - now;
    _gestureTickTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      final t = _gestureNow();
      _coordinator.tick(t);
      _scheduleGestureTick(t);
    });
  }

  /// Keeps the coordinator's clamping context in step with the engine so a
  /// seek preview can never target past the end or before zero (§2D/§2F).
  void _syncGestureContext() {
    final state = _controller.state.value;
    _coordinator.updatePlaybackContext(
      position: state.position,
      duration: state.duration > Duration.zero ? state.duration : null,
      seekable: state.canSeek,
    );
  }

  /// Applies one arbitrated gesture. Exactly one primary action lands per
  /// recognized gesture because the coordinator already suppressed every
  /// conflicting candidate (§3 rule 7); this switch only maps actions onto
  /// the existing services — no policy lives here.
  void _onGestureAction(ReelGestureAction action) {
    switch (action) {
      case TogglePlayPause():
        unawaited(_togglePlayback());
      case ToggleFavorite():
        unawaited(
          _toggleFavourite(fromDoubleTap: true, anchor: _lastPointerLocal),
        );
      case SeekForward(:final delta):
        unawaited(_skipReel(forward: true, delta: delta));
      case SeekBackward(:final delta):
        unawaited(_skipReel(forward: false, delta: delta));
      case SeekPreviewStarted(:final target):
        _showSeekPreview(target, anchor: true);
      case SeekPreviewUpdated(:final target):
        _showSeekPreview(target, anchor: false);
      case SeekPreviewCommitted(:final target):
        _clearSeekPreview();
        unawaited(_controller.seekTo(target));
      case SeekPreviewCancelled():
        _clearSeekPreview();
      case BoostStarted(:final speed):
        _applyBoost(speed);
      case BoostStepped(:final speed):
        _applyBoost(speed);
      case BoostEnded(:final speed):
        _endBoost(speed);
      case SpeedLockEngaged(:final speed):
        _engageLock(speed);
      case SpeedLockReleased():
        _releaseLock();
    }
  }

  // --- Long-press speed boost / lock (RC-03, §2G–§2H) -----------------------

  /// The resting speed with no boost and no lock, read from the coordinator's
  /// config so the host never hard-codes a second source of the 1.0x default.
  double get _baseSpeed => _coordinator.config.baseSpeed;

  /// Applies one boost value — used for both the initial [BoostStarted] and
  /// every [BoostStepped]. The engine command and the indicator read the same
  /// authoritative number, so what is shown is exactly what plays (§6). Speed
  /// updates go through [setState] but stay confined to the controller-layer
  /// overlay; the playing surface is unchanged (§2G: no full-page rebuild).
  void _applyBoost(double speed) {
    unawaited(_controller.setSpeed(speed));
    if (!mounted) return;
    setState(() => _boostSpeed = speed);
  }

  /// A normal hold released without locking: restore the resting speed
  /// (`baseSpeed`, or the still-active locked floor the coordinator hands
  /// back) and drop the temporary pill. The persistent lock indicator, when
  /// one is active, is driven separately by [_lockedSpeed].
  void _endBoost(double resting) {
    unawaited(_controller.setSpeed(resting));
    if (!mounted) return;
    setState(() {
      _boostSpeed = null;
      _lockedSpeed = _coordinator.lockedSpeed;
    });
  }

  /// A downward swipe engaged the lock at [speed]. Keeps that exact value on
  /// the engine and swaps the temporary pill for the persistent lock
  /// indicator *now*: releasing a fresh lock emits no action (§2H preserves it
  /// silently), so clearing [_boostSpeed] here is what stops the pill from
  /// sticking after the finger lifts.
  void _engageLock(double speed) {
    unawaited(_controller.setSpeed(speed));
    if (!mounted) return;
    setState(() {
      _lockedSpeed = speed;
      _boostSpeed = null;
    });
  }

  /// A second downward swipe cleared the lock: reset to [baseSpeed] and hide
  /// both indicators, since the remainder of the hold plays at the ordinary
  /// speed and there is nothing left to advertise.
  void _releaseLock() {
    unawaited(_controller.setSpeed(_baseSpeed));
    if (!mounted) return;
    setState(() {
      _lockedSpeed = null;
      _boostSpeed = null;
    });
  }

  Future<void> _togglePlayback() async {
    final status = _controller.state.value.status;
    if (status == PlaybackStatus.playing) {
      await _controller.pause();
      if (!mounted) return;
      // Paused: the play glyph stays up until playback resumes (§2A).
      _showTapIndicator(Icons.play_arrow, persist: true);
    } else if (status == PlaybackStatus.paused ||
        status == PlaybackStatus.completed) {
      await _controller.resume();
      if (!mounted) return;
      _showTapIndicator(Icons.pause, persist: false);
    }
    // buffering/idle/error: a tap is deliberately inert — pausing mid-buffer
    // or replaying nothing would look like a broken control.
  }

  void _showTapIndicator(IconData icon, {required bool persist}) {
    _tapIndicatorTimer?.cancel();
    _tapIndicatorTimer = null;
    setState(() => _tapIndicator = icon);
    if (!persist) {
      _tapIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _tapIndicator = null);
      });
    }
  }

  Future<void> _skipReel({
    required bool forward,
    required Duration delta,
  }) async {
    // skipForward/skipBackward clamp against the known duration inside the
    // controller, so repeated double taps accumulate safely (§2D/§2E, §8.6–8).
    if (forward) {
      await _controller.skipForward(delta);
    } else {
      await _controller.skipBackward(delta);
    }
    if (!mounted) return;
    _seekFeedbackTimer?.cancel();
    setState(
      () => _seekFeedback = (forward: forward, seconds: delta.inSeconds),
    );
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _showSeekPreview(Duration target, {required bool anchor}) {
    final state = _controller.state.value;
    if (anchor) _seekPreviewFrom = state.position;
    _seekPreviewTarget = target;
    _seekPreviewDuration = state.duration > Duration.zero
        ? state.duration
        : null;
    setState(() {});
  }

  void _clearSeekPreview() {
    if (_seekPreviewTarget == null && _seekPreviewFrom == null) return;
    _seekPreviewFrom = null;
    _seekPreviewTarget = null;
    _seekPreviewDuration = null;
    setState(() {});
  }

  Future<void> _toggleFavourite({
    bool fromDoubleTap = false,
    Offset? anchor,
  }) async {
    final item = ref.read(reelsQueueProvider).value?.current;
    if (item == null) return;
    final next = !_favourite;
    // Optimistic flip keyed to the *video id* — the visible index could move
    // under a rapid swipe mid-write (§5 FavoriteRepository).
    setState(() => _favourite = next);
    // §2C: a centre double tap that *likes* the reel flashes an animated heart
    // at the tap point. An unlike (and a rail-button tap, which already has its
    // own pop) flips the state without a floating heart, matching the "a like is
    // a celebration" convention and keeping the surface uncluttered (§4).
    if (fromDoubleTap && next) _showHeartBurst(anchor);
    final result = await ref
        .read(videoRepositoryProvider)
        .setFavourite(id: item.id, value: next);
    if (result case Err()) {
      if (mounted) setState(() => _favourite = !next);
    }
  }

  /// Places a heart burst at [anchor] (the double-tap lift point), clamped so
  /// the whole glyph stays on-screen in portrait and landscape (§4 "ensure all
  /// overlays work in portrait and landscape"). Bumping [_heartBurstSeq] remounts
  /// the widget so a repeat favourite replays the animation.
  void _showHeartBurst(Offset? anchor) {
    final size = _surfaceSize;
    final raw =
        anchor ??
        (size == null ? Offset.zero : Offset(size.width / 2, size.height / 2));
    const radius = 52.0; // half of ReelHeartBurst's default size
    final centre = size == null
        ? raw
        : Offset(
            raw.dx.clamp(radius, math.max(radius, size.width - radius)),
            raw.dy.clamp(radius, math.max(radius, size.height - radius)),
          );
    if (!mounted) return;
    setState(() {
      _heartBurstAt = centre;
      _heartBurstSeq++;
    });
  }

  /// The burst reported its animation finished: drop it. No timer backs this —
  /// the widget's one-shot controller is the only thing keeping it alive, so a
  /// reel change simply stops rendering it (and [_clearGestureUi] nulls the
  /// field before the controller could call back after teardown).
  void _onHeartBurstDone() {
    if (!mounted) return;
    setState(() => _heartBurstAt = null);
  }

  /// Drops every transient gesture visual and the coordinator's tick timer.
  /// Used on reel changes, tab changes, and teardown; emits nothing and never
  /// calls [setState] (callers pair it with their own state update). Also
  /// returns the engine to [baseSpeed] when a boost or lock was live, so a
  /// locked reel can never leak its speed to the next clip or to the shared
  /// dedicated-player controller (acceptance criterion 18, §6).
  void _clearGestureUi() {
    _gestureTickTimer?.cancel();
    _gestureTickTimer = null;
    _tapIndicatorTimer?.cancel();
    _tapIndicatorTimer = null;
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = null;
    _tapIndicator = null;
    _seekFeedback = null;
    _heartBurstAt = null;
    _seekPreviewFrom = null;
    _seekPreviewTarget = null;
    _seekPreviewDuration = null;
    final hadSpeedGesture = _boostSpeed != null || _lockedSpeed != null;
    _boostSpeed = null;
    _lockedSpeed = null;
    if (hadSpeedGesture) {
      unawaited(_controller.setSpeed(_baseSpeed));
    }
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
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
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
              surfaceKey: isCurrent ? _surfaceKey : null,
              fitOverride: isCurrent ? _fitOverride : null,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              error: isCurrent ? _reelError : null,
              hideChrome: _inPip,
            );
          },
        ),
        // The controller / feedback overlay is chrome: it must vanish while
        // floating so the PiP window shows only the video (PLAY-010).
        if (widget.active && !_inPip && queue.isNotEmpty)
          ..._buildControllerLayer(),
      ],
    );
  }

  /// The screen-level interactive/feedback layers sitting *above* the PageView
  /// in the widget Stack. Because a Stack hit-tests its frontmost child that
  /// covers a point, pointers on any control here never reach the pages'
  /// gesture Listener — interactive controls win first (§3 rule 1) without the
  /// coordinator needing any knowledge of where buttons live.
  List<Widget> _buildControllerLayer() {
    final layer = <Widget>[];

    // Transient feedback — purely decorative, so IgnorePointer keeps every
    // tap flowing to the gesture surface below.
    if (_tapIndicator case final icon?) {
      layer.add(
        Positioned.fill(
          child: IgnorePointer(
            child: ReelTapIndicator(
              key: const ValueKey('reels_tap_indicator'),
              icon: icon,
            ),
          ),
        ),
      );
    }
    if (_seekFeedback case final feedback?) {
      layer.add(
        Positioned.fill(
          child: IgnorePointer(
            child: ReelSeekFeedback(
              key: const ValueKey('reels_seek_feedback'),
              forward: feedback.forward,
              seconds: feedback.seconds,
            ),
          ),
        ),
      );
    }
    if (_seekPreviewTarget case final target?) {
      layer.add(
        Positioned(
          left: 32,
          right: 32,
          bottom: 96,
          child: IgnorePointer(
            child: ReelSeekPreviewBar(
              key: const ValueKey('reels_seek_preview'),
              from: _seekPreviewFrom ?? Duration.zero,
              target: target,
              duration: _seekPreviewDuration,
            ),
          ),
        ),
      );
    }

    // Speed boost / lock indicators (§2G/§2H). The temporary pill takes
    // precedence while a hold is live; the persistent lock pill shows only once
    // no boost is being displayed. Both are IgnorePointer so they never steal
    // the hold or the swipe-down that drives them.
    if (_boostSpeed case final speed?) {
      layer.add(
        Positioned.fill(
          child: IgnorePointer(
            child: ReelSpeedIndicator(
              key: const ValueKey('reels_speed_indicator'),
              speed: speed,
            ),
          ),
        ),
      );
    } else if (_lockedSpeed case final speed?) {
      layer.add(
        Positioned.fill(
          child: IgnorePointer(
            child: ReelSpeedLockIndicator(
              key: const ValueKey('reels_speed_lock'),
              speed: speed,
            ),
          ),
        ),
      );
    }

    // Double-tap favourite heart (§2C): a one-shot burst anchored to the lift
    // point, centred on that point and IgnorePointer so it never intercepts the
    // next gesture. It removes itself via [_onHeartBurstDone] when its animation
    // finishes.
    if (_heartBurstAt case final centre?) {
      const size = 104.0;
      layer.add(
        Positioned(
          left: centre.dx - size / 2,
          top: centre.dy - size / 2,
          child: IgnorePointer(
            child: SizedBox(
              width: size,
              height: size,
              child: ReelHeartBurst(
                key: ValueKey('reels_heart_burst_$_heartBurstSeq'),
                position: centre,
                size: size,
                onCompleted: _onHeartBurstDone,
              ),
            ),
          ),
        ),
      );
    }

    if (_controlsVisible) {
      // The open overlay claims the whole surface: taps that miss a control
      // hit this scrim and hide it again (PLAY-004), and while it is up the
      // gesture surface underneath is deliberately inert — revealing or
      // dismissing controls is the "intentional UI change" §2A allows.
      layer.add(
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _hideControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A dim scrim keeps the video visible while the controls read
                // clearly.
                const ColoredBox(color: Color(0x66000000)),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: _FitToggle(
                      controller: _controller,
                      fitOverride: _fitOverride,
                      onPressed: _toggleReelFit,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    key: const ValueKey('reels_controls_overlay'),
                    padding: const EdgeInsets.only(bottom: 8),
                    // The app-wide display mode (including Stretch) belongs to
                    // the dedicated player; a reel replaces it with the aspect-
                    // true [ReelsVideoSurface] plus the fit toggle above.
                    child: const PlaybackControls(showDisplayMode: false),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Persistent on-video controls (§2B): the favourite toggle and the
      // controls reveal. Small, corner-anchored, and above the gesture layer.
      layer.add(
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReelFavoriteButton(
                favourite: _favourite,
                onPressed: () => unawaited(_toggleFavourite()),
              ),
              IconButton(
                key: const ValueKey('reels_controls_toggle'),
                tooltip: 'Playback controls',
                onPressed: _toggleControls,
                icon: const Icon(Icons.tune, color: Colors.white),
              ),
              // PiP is offered only where the host supports it (feature-detected
              // through the coordinator), so no dead button appears otherwise.
              if (_pipSupported)
                IconButton(
                  key: const ValueKey('reels_pip_button'),
                  tooltip: 'Picture-in-picture',
                  onPressed: () => unawaited(_pip.enter()),
                  icon: const Icon(
                    Icons.picture_in_picture_alt,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return layer;
  }
}

/// One reel page. The current page renders the playing [ReelsVideoSurface] with
/// the title caption overlaid, wrapped in a passive [Listener] that forwards
/// raw pointers to the screen's [ReelGestureCoordinator]; the other pages show a
/// still caption frame so a swipe previews the next item (PLAY-001, PLAY-002,
/// PLAY-004).
///
/// A [Listener] observes pointers without ever joining the gesture arena, so
/// the [PageView]'s vertical drag still wins every vertical gesture exactly as
/// before (§3 rule 6) — this page adds no [GestureDetector] that could race it.
/// All tappable controls live in the screen-level Stack above this page, so
/// their hit-tests are resolved before any pointer reaches the Listener
/// (§3 rule 1).
class _ReelPage extends StatelessWidget {
  const _ReelPage({
    required this.item,
    required this.position,
    required this.total,
    required this.showSurface,
    required this.surfaceKey,
    required this.fitOverride,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    this.error,
    this.hideChrome = false,
  });

  final VideoItemSummary item;
  final int position;
  final int total;
  final bool showSurface;

  /// Attached to the interactive page's gesture surface so the screen can
  /// resolve global→local pointer coordinates against its actual size. Only
  /// non-null on the current, active page — a [GlobalKey] must be unique.
  final Key? surfaceKey;

  /// The pinned fit for this reel, or null for the automatic rule.
  final BoxFit? fitOverride;

  /// Raw pointer taps forwarded to the coordinator; the passive [Listener]
  /// never claims them, so [PageView] paging is unaffected.
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerMoveEvent) onPointerMove;
  final void Function(PointerUpEvent) onPointerUp;
  final void Function(PointerCancelEvent) onPointerCancel;

  final String? error;

  /// Hides the title caption while the app floats in a PiP window (P13-04,
  /// PLAY-010): the OS captures the whole Flutter window, so overlay chrome
  /// must be removed in Dart to leave only the video.
  final bool hideChrome;

  @override
  Widget build(BuildContext context) {
    final caption = _Caption(
      position: position,
      total: total,
      title: item.title,
      error: error,
    );
    if (showSurface && error == null) {
      return Listener(
        key: surfaceKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerCancel,
        child: Stack(
          key: const ValueKey('reels_tap_layer'),
          fit: StackFit.expand,
          children: [
            ReelsVideoSurface(item: item, fitOverride: fitOverride),
            // Keep the title/position readable over the playing video, unless
            // floating in PiP where the caption is chrome that must hide.
            if (!hideChrome)
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

/// Overlay button flipping the current reel between letterboxed
/// ([BoxFit.contain], whole frame) and full-bleed ([BoxFit.cover], cropped) —
/// both keep the picture's real aspect ratio (PLAY-007).
///
/// Labelled from the fit actually in effect, including the automatic choice for
/// an unpinned reel, so the icon and tooltip always describe the *other* mode
/// the tap will switch to.
class _FitToggle extends StatelessWidget {
  const _FitToggle({
    required this.controller,
    required this.fitOverride,
    this.onPressed,
  });

  final PlaybackController controller;
  final BoxFit? fitOverride;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final fullBleed =
            reelsBoxFit(videoSize: state.videoSize, override: fitOverride) ==
            BoxFit.cover;
        return IconButton(
          key: const ValueKey('reels_fit_toggle'),
          tooltip: fullBleed ? 'Fit to screen' : 'Fill screen',
          onPressed: onPressed,
          icon: Icon(fullBleed ? Icons.fit_screen : Icons.crop_free),
          color: Colors.white,
        );
      },
    );
  }
}

/// The persistent on-video favourite toggle (§2B). Beyond the ordinary
/// active/inactive icon swap it plays a short scale "pop" whenever the state
/// flips — from a rail tap or a double-tap like — so favouriting feels tactile
/// without changing the control's footprint (§2B "a subtle animation when
/// favoriting or unfavoriting"). The pop collapses to a plain swap under the
/// reduced-motion preference, the icon keeps the same [Icons.favorite]/
/// [Icons.favorite_border] identity (the heart *burst* uses a distinct glyph so
/// the two never collide), and the button carries an explicit selected-state
/// [Semantics] for TalkBack (§4 "semantic labels for important controls").
class _ReelFavoriteButton extends StatefulWidget {
  const _ReelFavoriteButton({required this.favourite, this.onPressed});

  final bool favourite;
  final VoidCallback? onPressed;

  @override
  State<_ReelFavoriteButton> createState() => _ReelFavoriteButtonState();
}

class _ReelFavoriteButtonState extends State<_ReelFavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1.0, end: 1.35),
      weight: 40,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1.35, end: 1.0),
      weight: 60,
    ),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    // No pop on the first build — the reel just started, the user did nothing.
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _ReelFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favourite != widget.favourite &&
        !reelsReduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.favourite,
      child: IconButton(
        key: const ValueKey('reels_favorite_button'),
        tooltip: widget.favourite
            ? 'Remove from favorites'
            : 'Add to favorites',
        onPressed: widget.onPressed,
        icon: ScaleTransition(
          scale: _scale,
          child: Icon(
            widget.favourite ? Icons.favorite : Icons.favorite_border,
            color: widget.favourite ? kReelsFavoriteColor : Colors.white,
          ),
        ),
      ),
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
    // Layout-safe for every orientation and text scale: the caption
    // shrink-wraps from the bottom, and both the title and the error are
    // line-clipped with an ellipsis so a landscape page or an enlarged system
    // font can never grow the column past the screen into a RenderFlex overflow
    // (§4 "overlays work in portrait and landscape", "controls sized for
    // touchscreen interaction").
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
