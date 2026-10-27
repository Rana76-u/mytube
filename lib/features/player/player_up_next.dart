import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/app/theme/player_theme.dart';
import 'package:mytube/core/ui/skeleton.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/library/video_thumbnail.dart';
import 'package:mytube/features/player/playback_queue.dart';

/// "Up Next": the explicit queue, then the recommendation pool, under the
/// player (design §4, VP3.5).
///
/// The section is the visible half of [upNextRowsProvider]: the videos the user
/// queued, followed by the suggestions, with the playing item pinned at the top
/// under a `Now playing` label. The header's Autoplay switch is what lets the
/// end of a video roll into the row beneath it ([PlayerAutoplayCountdown]).
class PlayerUpNextSection extends ConsumerWidget {
  const PlayerUpNextSection({
    super.key,
    required this.current,
    required this.onPlay,
  });

  /// The item on screen: shown as the `Now playing` row and never repeated in
  /// the list below it.
  final VideoItemSummary current;

  /// Loads [item] in place (the page's own switch, not a new route).
  final void Function(VideoItemSummary item) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = ref.watch(upNextRowsProvider(current.id));
    // A fresh or empty library has nothing to suggest: hide the whole section
    // rather than show a header over a lone "Now playing" row.
    if (rows.isEmpty) return const SizedBox.shrink();
    final queue = ref.watch(playbackQueueProvider);

    return Column(
      key: const ValueKey('player_up_next'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Text('Up Next', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                'Autoplay',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Switch(
                key: const ValueKey('player_autoplay_toggle'),
                value: ref.watch(autoplayEnabledProvider),
                onChanged: (_) =>
                    ref.read(autoplayEnabledProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
        _NowPlayingRow(item: current),
        for (final item in rows)
          PlayerUpNextRow(
            item: item,
            queued: queue.contains(item.id),
            onTap: () => onPlay(item),
          ),
      ],
    );
  }
}

/// The playing item: a row like any other, labelled instead of menued.
///
/// It carries no `⋮` because every action in it (Play next, Add to queue,
/// Remove) is about a video this row is not.
class _NowPlayingRow extends StatelessWidget {
  const _NowPlayingRow({required this.item});

  final VideoItemSummary item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('player_now_playing'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _UpNextThumbnail(item: item, width: AppSizes.upNextThumbWidth),
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
                  'Now playing',
                  key: const ValueKey('player_up_next_now_playing'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the row's `⋮` can do (VP3.5).
enum _RowAction { playNext, addToQueue, save, share, remove }

/// One Up Next row: 16:9 thumbnail with duration badge and watched-progress
/// bar, two-line title, meta line and a `⋮` menu.
class PlayerUpNextRow extends ConsumerWidget {
  const PlayerUpNextRow({
    super.key,
    required this.item,
    required this.onTap,
    this.queued = false,
  });

  final VideoItemSummary item;

  /// Loads this item in place.
  final VoidCallback onTap;

  /// Whether the item came from the explicit queue, which is the only case
  /// [remove] makes sense for.
  final bool queued;

  /// Menu order: the two queue moves, then the two library actions shared with
  /// a card's `⋮`, then the undo.
  static const Map<_RowAction, String> _labels = {
    _RowAction.playNext: 'Play next',
    _RowAction.addToQueue: 'Add to queue',
    _RowAction.save: 'Save',
    _RowAction.share: 'Share',
    _RowAction.remove: 'Remove from queue',
  };

  void _select(BuildContext context, WidgetRef ref, _RowAction action) {
    final queue = ref.read(playbackQueueProvider.notifier);
    switch (action) {
      case _RowAction.playNext:
        queue.playNext(item);
      case _RowAction.addToQueue:
        queue.add(item);
      case _RowAction.remove:
        queue.remove(item.id);
      case _RowAction.save:
      case _RowAction.share:
        // Reuse the shared bundle so a row saves and shares exactly like a card.
        final actions = videoItemActionsFor(context, ref, item);
        (action == _RowAction.save
                ? actions.onSaveToCollection
                : actions.onShare)
            ?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = item.id.value;
    return InkWell(
      key: ValueKey('player_up_next_$id'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UpNextThumbnail(item: item, width: AppSizes.upNextThumbWidth),
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
            PopupMenuButton<_RowAction>(
              key: ValueKey('player_up_next_menu_$id'),
              tooltip: 'More',
              onSelected: (action) => _select(context, ref, action),
              itemBuilder: (context) => [
                // Suggestions cannot be removed — they were never added — so
                // the undo only appears for a row that came from the queue.
                for (final action in _RowAction.values)
                  if (action != _RowAction.remove || queued)
                    PopupMenuItem<_RowAction>(
                      value: action,
                      child: Text(_labels[action]!),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The row's thumbnail: 16:9, rounded, with the duration badge and the red
/// watched-progress bar (design §4).
///
/// While the frame is still being produced the existing shimmer skeleton is
/// shown instead of the neutral placeholder, so a generating row reads as
/// "loading" rather than "no image."
class _UpNextThumbnail extends ConsumerWidget {
  const _UpNextThumbnail({required this.item, required this.width});

  final VideoItemSummary item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = width * 9 / 16;
    final thumbnail = ref.watch(videoThumbnailProvider(item.id.value));
    final frame = thumbnail.isLoading
        ? Shimmer(
            key: const ValueKey('player_up_next_thumbnail_skeleton'),
            child: SkeletonBox(
              width: width,
              height: height,
              radius: VideoThumbnail.radius,
            ),
          )
        : VideoThumbnail(item: item, width: width, height: height);

    final durationMs = item.durationMs;
    final watched = item.watchProgressMs;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          frame,
          if (durationMs != null && durationMs > 0)
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Black at 80 % behind white text (design §4 badge spec).
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    child: Text(
                      formatDuration(Duration(milliseconds: durationMs)),
                      key: ValueKey('player_up_next_duration_${item.id.value}'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // A partially-watched video says so on the picture itself, the same
          // red the seek track uses.
          if (durationMs != null && durationMs > 0 && watched > 0)
            Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(
                widthFactor: (watched / durationMs).clamp(0.0, 1.0),
                child: Container(
                  key: ValueKey('player_up_next_progress_${item.id.value}'),
                  height: 3,
                  color: PlayerColors.of(context).trackPlayed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The end-of-video countdown that rolls into the next Up Next row (VP3.5,
/// design §9).
///
/// Inserted only while the engine reports `completed`, so its timer starts at
/// the moment the video actually ends rather than when the page was built.
/// Cancel stops it and leaves the replay button in charge; the host removes the
/// widget as soon as playback moves on.
class PlayerAutoplayCountdown extends StatefulWidget {
  const PlayerAutoplayCountdown({
    super.key,
    required this.item,
    required this.onPlay,
    this.total = const Duration(seconds: 5),
  });

  /// The video that is about to start.
  final VideoItemSummary item;

  /// Loads [item]. Fires once when the countdown runs out.
  final VoidCallback onPlay;

  /// How long the user gets to cancel (design §9: 5 s).
  final Duration total;

  @override
  State<PlayerAutoplayCountdown> createState() =>
      _PlayerAutoplayCountdownState();
}

class _PlayerAutoplayCountdownState extends State<PlayerAutoplayCountdown> {
  late Duration _remaining = widget.total;
  Timer? _timer;

  /// Set once the user cancelled or the countdown fired: the pill removes
  /// itself, so the replay button is left in charge (design §9).
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final next = _remaining - const Duration(seconds: 1);
    if (next > Duration.zero) {
      setState(() => _remaining = next);
      return;
    }
    _finish(widget.onPlay);
  }

  /// Stops the timer, hides the pill and then runs [action] (if any), so a
  /// countdown that fires cannot tick again while the host switches items.
  void _finish([VoidCallback? action]) {
    _timer?.cancel();
    _timer = null;
    setState(() => _dismissed = true);
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final colors = PlayerColors.of(context);
    final seconds = (_remaining.inMilliseconds / 1000).ceil();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.pillBackground,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playing next in ${seconds}s',
                      key: const ValueKey('player_autoplay_countdown'),
                      style: TextStyle(color: colors.overlayText, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.item.title,
                      style: TextStyle(
                        color: colors.overlayText,
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('player_autoplay_play_now'),
                tooltip: 'Play now',
                onPressed: () => _finish(widget.onPlay),
                icon: Icon(Icons.play_arrow, color: colors.overlayIcon),
              ),
              TextButton(
                key: const ValueKey('player_autoplay_cancel'),
                onPressed: _finish,
                style: TextButton.styleFrom(
                  foregroundColor: colors.overlayText,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
