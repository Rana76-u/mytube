import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/player/video_surface.dart';
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
/// VP5.3 turns the old poster thumbnail into the live picture: the same
/// [VideoSurface] the page renders, cropped into the small box, so a docked
/// video keeps moving rather than freezing on a still frame, and the [Hero]
/// hand-off shows one continuous surface instead of a poster snapping to video.
/// A 2dp red line on the top edge keeps the playhead readable without a seek
/// bar (design §9).
///
/// Interactions:
///  * tap → reopen the player page (expands the session);
///  * play/pause → the shared [PlaybackController];
///  * a downward drag, a left/right swipe, or the close button → stop the
///    engine, flush the position, and clear the session so nothing is left
///    playing behind the shell.
class MiniPlayerDock extends ConsumerWidget {
  const MiniPlayerDock({super.key});

  /// Drag past this many pixels (down, or left/right) dismisses the dock.
  static const double _dismissDrag = 24;

  /// Fling velocity that dismisses without reaching the pixel threshold.
  static const double _dismissVelocity = 120;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(playbackSessionProvider);
    final item = session.item;
    if (!session.isMini || item == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final controller = ref.watch(playbackControllerProvider);

    return GestureDetector(
      // Dismiss by a downward drag (the dock "falls away") or by swiping the
      // bar sideways off the screen (VP5.3) — either ends the session.
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > _dismissVelocity) {
          _dismiss(ref, item);
        }
      },
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > _dismissDrag) _dismiss(ref, item);
      },
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > _dismissVelocity) {
          _dismiss(ref, item);
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx.abs() > _dismissDrag) _dismiss(ref, item);
      },
      child: Material(
        key: const ValueKey('mini_player'),
        color: theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: AppSizes.miniPlayerHeight,
          child: Stack(
            children: [
              Positioned.fill(
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
                                // The live surface, cropped to the small box so
                                // a docked video keeps playing (VP5.3).
                                child: const VideoSurface(fit: BoxFit.cover),
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
                          onPressed: () => playing
                              ? controller.pause()
                              : controller.resume(),
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
              // The playhead lives on the top edge, where a full-width red line
              // reads as progress without taking any of the 56dp row (VP5.3).
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _MiniProgressLine(controller: controller),
              ),
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

/// The 2dp red playhead line on the dock's top edge (VP5.3).
///
/// Mirrors [PlayerProgressLine] but sits on top and uses a fixed accent red
/// rather than the player's themed track colour, so it reads against any shell
/// surface. Nothing is drawn until the engine reports a real duration.
class _MiniProgressLine extends StatelessWidget {
  const _MiniProgressLine({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final total = state.duration.inMilliseconds;
        if (total <= 0) return const SizedBox.shrink();
        final fraction = (state.position.inMilliseconds / total).clamp(
          0.0,
          1.0,
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: const SizedBox(
              height: 2,
              child: ColoredBox(
                key: ValueKey('mini_player_progress'),
                color: Color(0xFFE53935),
              ),
            ),
          ),
        );
      },
    );
  }
}
