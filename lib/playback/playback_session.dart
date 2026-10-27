import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/playback/now_playing.dart';

/// How the current playback surface is presented (plan M6).
enum PlaybackSessionMode {
  /// Nothing is loaded.
  idle,

  /// Playing, but the player page is closed: audio continues behind the shell
  /// and the mini-player dock is the only surface.
  mini,

  /// The full player page is open.
  expanded,
}

/// What the app is currently playing, independent of any route.
///
/// This is the single owner of "what is playing" (ADR-014). The player page
/// adopts an item when it opens, collapses the session to [PlaybackSessionMode
/// .mini] when it is closed by swipe/back — leaving the engine running — and
/// the mini-player dock reads the same state to render itself. Nothing else
/// keeps a copy, so the dock and the page can never disagree.
class PlaybackSession {
  const PlaybackSession({this.item, this.mode = PlaybackSessionMode.idle});

  /// The item loaded into the shared engine, or null when idle.
  final VideoItemSummary? item;

  /// How that item is currently presented.
  final PlaybackSessionMode mode;

  /// Whether anything is loaded (mini or expanded).
  bool get isActive => item != null && mode != PlaybackSessionMode.idle;

  /// Whether the mini dock should render.
  bool get isMini => item != null && mode == PlaybackSessionMode.mini;

  PlaybackSession copyWith({
    VideoItemSummary? item,
    PlaybackSessionMode? mode,
  }) => PlaybackSession(item: item ?? this.item, mode: mode ?? this.mode);

  @override
  bool operator ==(Object other) =>
      other is PlaybackSession &&
      other.item?.id == item?.id &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(item?.id, mode);
}

/// Owns [PlaybackSession] (ADR-014).
///
/// It also publishes the now-playing label, so the media notification and the
/// lock-screen controls follow the session no matter which surface started it
/// (P13-02/P13-03 stay unchanged in behaviour).
class PlaybackSessionController extends Notifier<PlaybackSession> {
  @override
  PlaybackSession build() => const PlaybackSession();

  /// Records [item] as what is playing and marks the page open.
  void adopt(VideoItemSummary item) {
    ref.read(nowPlayingProvider.notifier).setTitle(item.title);
    state = PlaybackSession(item: item, mode: PlaybackSessionMode.expanded);
  }

  /// The player page closed but playback continues: dock into the mini player.
  ///
  /// No-op when nothing is loaded, so popping a page that never started
  /// playback leaves the shell alone.
  void collapse() {
    if (state.item == null) return;
    state = state.copyWith(mode: PlaybackSessionMode.mini);
  }

  /// The mini player was tapped: the page is open again.
  void expand() {
    if (state.item == null) return;
    state = state.copyWith(mode: PlaybackSessionMode.expanded);
  }

  /// Stops the session entirely (explicit close, Reels taking over the engine).
  ///
  /// The caller owns the engine stop and the progress flush, because only it
  /// knows which item's position has to be written.
  void stop() {
    if (state.mode == PlaybackSessionMode.idle && state.item == null) return;
    state = const PlaybackSession();
  }
}

/// The app's playback session (ADR-014).
final playbackSessionProvider =
    NotifierProvider<PlaybackSessionController, PlaybackSession>(
      PlaybackSessionController.new,
    );
