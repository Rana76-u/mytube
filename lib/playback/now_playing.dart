import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The label the media notification / lock-screen control should show for the
/// item currently loaded in the shared player (P13-03).
///
/// Kept deliberately tiny and app-owned: playback screens publish the human
/// title they are about to play, and [MediaSessionCoordinator] reads it to
/// render the notification. It carries **no** URI or signed URL — the durable
/// source identity stays in the repository, and the notification only ever shows
/// a safe display label (SEC-005).
class NowPlayingInfo {
  const NowPlayingInfo({this.title});

  /// Display label for the current item, or null when nothing has been played.
  final String? title;

  /// Fallback used when a session is live but no title was published.
  static const String unlabeled = 'Video';
}

/// Holds the [NowPlayingInfo] for the app-wide player.
///
/// A [Notifier] rather than a field on the playback controller so the
/// engine-neutral [PlaybackController] never learns about display metadata.
class NowPlayingNotifier extends Notifier<NowPlayingInfo> {
  @override
  NowPlayingInfo build() => const NowPlayingInfo();

  /// Publishes [title] as the current now-playing label.
  ///
  /// Called by a screen right before it plays an item; the last writer wins,
  /// which is safe because exactly one source is live at a time. Clearing back
  /// to null is unnecessary: the coordinator hides the session on idle, so a
  /// stale label is never shown.
  void setTitle(String? title) {
    state = NowPlayingInfo(title: title);
  }
}

final nowPlayingProvider = NotifierProvider<NowPlayingNotifier, NowPlayingInfo>(
  NowPlayingNotifier.new,
);
