import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/library/video_thumbnail.dart';
import 'package:mytube/features/player/fullscreen_controller.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/up_next_provider.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Dedicated player page for a library item (PLAY-001/PLAY-009, DESIGN.md §5).
///
/// Reached by tapping a video card anywhere in the app. It resolves the item's
/// source through [PlaybackSourceResolver] (never the widgets themselves
/// touching persistence or adapters), hands the short-lived [PlayableSource] to
/// the app-owned [PlaybackController], and paints it with the shared
/// [VideoSurface] + [PlaybackControls] so behaviour matches Reels (PLAT-005 —
/// no `video_player` type appears here).
///
/// Layout follows DESIGN.md §5: one [CustomScrollView] whose first sliver is a
/// pinned 16:9 player, so the video stays docked while the metadata, the action
/// toolbar and "Up Next" scroll beneath it. Tapping the video toggles the
/// overlay chrome (auto-hidden after 3 s of playback); dragging it down docks
/// the session into the mini player (ADR-014).
///
/// Playback is one-shot: looping (a Reels-only behaviour, PLAY-003) is turned
/// off on entry, position resumes from stored watch progress when there is any
/// (P5-08), and every controller tick is forwarded to [WatchProgressService]
/// which throttles the actual writes.
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
  /// How long the overlay chrome stays up during uninterrupted playback.
  static const Duration _chromeTimeout = Duration(seconds: 3);

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

  /// Whether the overlay chrome (controls over the video) is drawn.
  bool _chromeVisible = true;

  /// Hides the chrome again once playback has been running untouched.
  Timer? _chromeTimer;

  /// Accumulated downward drag on the video, in pixels; past
  /// [AppSizes.dockDragThreshold] the page docks into the mini player.
  double _dragDown = 0;

  /// Captured so teardown/route pops can update the session without touching
  /// `ref` (same reason as [_controller]).
  late final PlaybackSessionController _session;

  /// Captured for the same reason: `dispose` must restore the system UI.
  late final FullscreenController _fullscreen;

  /// Set when this page already decided the session's fate (docked by a drag),
  /// so `dispose` does not collapse it a second time.
  bool _sessionHandedOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _item = widget.item;
    _controller = ref.read(playbackControllerProvider);
    _watchProgress = ref.read(watchProgressServiceProvider);
    _session = ref.read(playbackSessionProvider.notifier);
    _fullscreen = ref.read(fullscreenControllerProvider.notifier);
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
    _chromeTimer?.cancel();
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
    // Backgrounding mid-fullscreen must not strand the device in immersive
    // landscape once the user comes back to something else (plan M5).
    if (state == AppLifecycleState.paused) {
      unawaited(ref.read(fullscreenControllerProvider.notifier).restore());
    }
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
    setState(() {
      _item = item;
      _chromeVisible = true;
    });
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

  /// Shows the chrome and, while playing, schedules the auto-hide (DESIGN §5).
  void _revealChrome({bool autoHide = true}) {
    _chromeTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    if (!autoHide) return;
    if (!_controller.state.value.isPlaying) return;
    _chromeTimer = Timer(_chromeTimeout, () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    if (_chromeVisible) {
      _chromeTimer?.cancel();
      setState(() => _chromeVisible = false);
    } else {
      _revealChrome(autoHide: false);
    }
  }

  /// Docks the session into the mini player and closes the page (ADR-014).
  void _dockToMini() {
    _chromeTimer?.cancel();
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
        return PopScope(
          // Every way out of the page — back gesture, app bar, system pop —
          // hands the item to the mini player before teardown (ADR-014).
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _collapseSessionIfMine();
          },
          child: Scaffold(
            backgroundColor: fullscreen ? Colors.black : null,
            // Immersive fullscreen owns the whole screen, so the bar goes away
            // with the rest of the chrome; it stays for the normal page so the
            // back gesture, the title and PiP keep working (plan M5).
            appBar: fullscreen
                ? null
                : AppBar(
                    backgroundColor: Colors.transparent,
                    title: Text(
                      _item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      // Offered only where the host supports PiP (feature-detected
                      // via the coordinator, so no dead button on unsupported
                      // devices).
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
                    ],
                  ),
            body: fullscreen ? _buildFullscreen() : _buildPage(),
          ),
        );
      },
    );
  }

  /// Fullscreen: the video fills the screen and only the overlay chrome sits on
  /// top of it (no metadata, no action toolbar — plan M5).
  Widget _buildFullscreen() {
    return _PlayerBox(
      item: _item,
      chromeVisible: _chromeVisible,
      onTap: _toggleChrome,
      onDragDown: (delta) => _dragDown += delta,
      onDragEnd: (velocity) => _handleDockDrag(velocity),
      chrome: _chrome(includeFullscreenAction: false),
    );
  }

  /// The normal page: pinned player, then metadata, actions and Up Next.
  Widget _buildPage() {
    // A 16:9 box at the page width; the pinned header needs a concrete extent.
    final width = MediaQuery.sizeOf(context).width;
    final playerHeight = width * 9 / 16;

    return CustomScrollView(
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
              chromeVisible: _chromeVisible,
              onTap: _toggleChrome,
              onDragDown: (delta) => _dragDown += delta,
              onDragEnd: (velocity) => _handleDockDrag(velocity),
              chrome: _chrome(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _MetadataBlock(
            item: _item,
            onShowChrome: () => _revealChrome(autoHide: false),
          ),
        ),
        SliverToBoxAdapter(child: _ActionToolbar(item: _item)),
        SliverToBoxAdapter(
          child: _UpNextSection(current: _item, onTap: _switchTo),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }

  /// The overlay control bar drawn over the video (DESIGN §5).
  Widget _chrome({bool includeFullscreenAction = true}) {
    return PlaybackControls(
      compact: true,
      actions: [
        if (includeFullscreenAction)
          IconButton(
            key: const ValueKey('player_fullscreen_button'),
            tooltip: 'Fullscreen',
            color: Colors.white,
            onPressed: () {
              _chromeTimer?.cancel();
              unawaited(
                ref.read(fullscreenControllerProvider.notifier).enter(),
              );
            },
            icon: const Icon(Icons.fullscreen),
          )
        else
          IconButton(
            key: const ValueKey('player_fullscreen_exit_button'),
            tooltip: 'Exit fullscreen',
            color: Colors.white,
            onPressed: () {
              unawaited(ref.read(fullscreenControllerProvider.notifier).exit());
              _revealChrome();
            },
            icon: const Icon(Icons.fullscreen_exit),
          ),
      ],
    );
  }

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
    _revealChrome(autoHide: false);
  }
}

/// The video plus its overlay chrome (and the gestures that drive it).
///
/// Kept separate from the page so the fullscreen branch renders exactly the
/// same surface, controls and gestures as the docked one.
class _PlayerBox extends StatelessWidget {
  const _PlayerBox({
    required this.item,
    required this.chromeVisible,
    required this.onTap,
    required this.chrome,
    required this.onDragDown,
    required this.onDragEnd,
  });

  final VideoItemSummary item;
  final bool chromeVisible;
  final VoidCallback onTap;
  final Widget chrome;
  final void Function(double delta) onDragDown;
  final void Function(double velocity) onDragEnd;

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // Keyed so the shell's Hero can carry the same picture into the mini
        // player dock (plan M6).
        Hero(
          tag: 'player_surface_${item.id.value}',
          child: const VideoSurface(),
        ),
        // The scrim and the controls appear/disappear together, so the video is
        // never covered by an invisible tap-eater.
        IgnorePointer(
          ignoring: !chromeVisible,
          child: AnimatedOpacity(
            duration: chromeVisible
                ? const Duration(milliseconds: 160)
                : const Duration(milliseconds: 220),
            opacity: chromeVisible ? 1 : 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: chrome,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return GestureDetector(
      key: const ValueKey('player_video_area'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: (details) => onDragDown(details.delta.dy),
      onVerticalDragEnd: (details) => onDragEnd(details.primaryVelocity ?? 0),
      child: ColoredBox(color: Colors.black, child: stack),
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

/// Title, `provider · age` line and the watched-progress hint under the video.
class _MetadataBlock extends StatelessWidget {
  const _MetadataBlock({required this.item, required this.onShowChrome});

  final VideoItemSummary item;

  /// Tapping the metadata re-reveals the video's controls, so the page has no
  /// dead area.
  final VoidCallback onShowChrome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onShowChrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              key: const ValueKey('player_title'),
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              VideoItemCard.metadataLine(item),
              key: const ValueKey('player_metadata_line'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The player's action toolbar: Like, Save, Share, Tags, Sources and the
/// display-mode selector, as one horizontally scrollable pill row (DESIGN §5).
///
/// Like maps onto the existing favourite flag (no dislike signal is stored —
/// plan assumptions), and every other entry reuses the shared
/// [videoItemActionsFor] bundle so the page offers exactly what a card's `⋮`
/// offers.
class _ActionToolbar extends ConsumerWidget {
  const _ActionToolbar({required this.item});

  final VideoItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = videoItemActionsFor(context, ref, item);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget pill({
      required Key key,
      required IconData icon,
      required String label,
      VoidCallback? onTap,
      bool active = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ActionChip(
          key: key,
          avatar: Icon(
            icon,
            size: 18,
            color: active ? colorScheme.primary : colorScheme.onSurface,
          ),
          label: Text(label),
          onPressed: onTap,
          backgroundColor: colorScheme.surface,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('player_action_toolbar'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          pill(
            key: const ValueKey('player_action_like'),
            icon: item.isFavourite ? Icons.favorite : Icons.favorite_border,
            label: 'Like',
            active: item.isFavourite,
            onTap: actions.onToggleFavourite,
          ),
          pill(
            key: const ValueKey('player_action_save'),
            icon: Icons.playlist_add,
            label: 'Save',
            onTap: actions.onSaveToCollection,
          ),
          pill(
            key: const ValueKey('player_action_share'),
            icon: Icons.share,
            label: 'Share',
            onTap: actions.onShare,
          ),
          pill(
            key: const ValueKey('player_action_tags'),
            icon: Icons.sell_outlined,
            label: 'Tags',
            onTap: actions.onManageTags,
          ),
          pill(
            key: const ValueKey('player_action_sources'),
            icon: Icons.link,
            label: 'Sources',
            onTap: actions.onManageSources,
          ),
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: DisplayModeMenu(),
          ),
        ],
      ),
    );
  }
}

/// "Up Next": recommendation rows under the player (DESIGN.md §5).
///
/// Each row is a 120-px-wide 16:9 thumbnail plus title and age, and tapping it
/// loads that item in place instead of pushing another route, so the engine
/// session and its progress reporting stay in one owner.
class _UpNextSection extends ConsumerWidget {
  const _UpNextSection({required this.current, required this.onTap});

  final VideoItemSummary current;
  final void Function(VideoItemSummary item) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(upNextProvider(current.id)).value ?? const [];
    // A failed or empty pool simply hides the section: the page is already
    // playing something, so there is nothing to recover.
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const ValueKey('player_up_next'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text('Up Next', style: theme.textTheme.titleSmall),
        ),
        for (final item in items)
          _UpNextRow(item: item, onTap: () => onTap(item)),
      ],
    );
  }
}

class _UpNextRow extends StatelessWidget {
  const _UpNextRow({required this.item, required this.onTap});

  final VideoItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('player_up_next_${item.id.value}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppSizes.upNextThumbWidth,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoThumbnail(item: item),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    VideoItemCard.metadataLine(item),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
