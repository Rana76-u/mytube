import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/library/video_thumbnail.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';

/// The mini-player dock: a 56dp bar above the bottom navigation that keeps the
/// current item reachable once the player page is closed (DESIGN.md §6,
/// ADR-014).
///
/// It renders only while the session is [PlaybackSessionMode.mini] — i.e. the
/// page was closed by swipe-down or back, and playback deliberately continues.
/// Everything it shows comes from the session, so the dock can never display a
/// different item from the one the engine is playing.
///
/// Interactions:
///  * tap → reopen the player page (expands the session);
///  * play/pause → the shared [PlaybackController];
///  * close, or a downward drag → stop the engine, flush the position, and
///    clear the session so nothing is left playing behind the shell.
class MiniPlayerDock extends ConsumerWidget {
  const MiniPlayerDock({super.key});

  /// Downward drag past this many pixels dismisses the dock.
  static const double _dismissDrag = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(playbackSessionProvider);
    final item = session.item;
    if (!session.isMini || item == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final controller = ref.watch(playbackControllerProvider);

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 120) {
          _dismiss(ref, item);
        }
      },
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > _dismissDrag) _dismiss(ref, item);
      },
      child: Material(
        key: const ValueKey('mini_player'),
        color: theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: AppSizes.miniPlayerHeight,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('mini_player_open'),
                  onTap: () => _open(context, ref, item),
                  child: Row(
                    children: [
                      SizedBox(
                        width: AppSizes.miniPlayerHeight * 16 / 9,
                        height: AppSizes.miniPlayerHeight,
                        child: Hero(
                          tag: 'player_surface_${item.id.value}',
                          child: VideoThumbnail(item: item),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.title,
                          key: const ValueKey('mini_player_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ValueListenableBuilder<PlaybackState>(
                valueListenable: controller.state,
                builder: (context, state, _) {
                  final playing = state.isPlaying || state.isBuffering;
                  return IconButton(
                    key: const ValueKey('mini_player_play_pause'),
                    tooltip: playing ? 'Pause' : 'Play',
                    onPressed: () =>
                        playing ? controller.pause() : controller.resume(),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  );
                },
              ),
              IconButton(
                key: const ValueKey('mini_player_close'),
                tooltip: 'Close player',
                onPressed: () => _dismiss(ref, item),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }

  /// Reopens the player page for the docked item, expanding the session.
  void _open(BuildContext context, WidgetRef ref, VideoItemSummary item) {
    ref.read(playbackSessionProvider.notifier).expand();
    Navigator.of(context).push(VideoPlayerScreen.route(item));
  }

  /// Ends the session: stop the engine, persist the last position and drop the
  /// media notification, so the dock never outlives what it describes.
  void _dismiss(WidgetRef ref, VideoItemSummary item) {
    final controller = ref.read(playbackControllerProvider);
    final progress = ref.read(watchProgressServiceProvider);
    ref.read(playbackSessionProvider.notifier).stop();
    ref.read(nowPlayingProvider.notifier).setTitle(null);
    controller.stop();
    unawaited(progress.flush(item.id));
  }
}
