import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/playback/playback_provider.dart';

/// A sleep-timer choice (design §7, VP4.5).
///
/// The list is exactly what the design asks for and nothing else: a timer that
/// cannot be honoured (say, one that outlives the session) is worse than no
/// option at all. [endOfVideo] is not a countdown — it stops playback when the
/// current video finishes rather than after a delay.
enum SleepTimerLength {
  off('Off', null),
  fifteen('15 minutes', 15),
  thirty('30 minutes', 30),
  fortyFive('45 minutes', 45),
  sixty('60 minutes', 60),
  endOfVideo('End of this video', null);

  const SleepTimerLength(this.label, this.minutes);

  /// Text shown in the sheet row and its option list.
  final String label;

  /// Length in minutes, or null for the two choices that are not delays.
  final int? minutes;

  /// The delay before playback pauses, or null when nothing counts down
  /// ([off], and [endOfVideo], which waits for the video itself).
  Duration? get delay => minutes == null ? null : Duration(minutes: minutes!);

  /// Whether finishing the current video is what stops playback.
  ///
  /// A looping video never finishes, so choosing this also has to turn looping
  /// off — the sheet does that in the same tap (VP4.5).
  bool get stopsAtVideoEnd => this == SleepTimerLength.endOfVideo;

  /// The state a session starts and ends in.
  static const SleepTimerLength defaultLength = SleepTimerLength.off;
}

/// Arms the sleep countdown.
///
/// A scheduler rather than `package:clock`: the test host never creates a real
/// timer, so no pending-timer assertion can fire and a test decides exactly when
/// the deadline arrives (the same seam `PlayerChromeController` uses).
typedef SleepTimerScheduler =
    Timer Function(Duration delay, void Function() callback);

/// Owns the session's sleep timer and pauses the player when it expires.
///
/// Session-scoped and never persisted: a countdown that survived a restart
/// would pause a video the user has no way to expect. The pause goes to the
/// app-wide [playbackControllerProvider] — the same controller the player page
/// drives — so there is one owner of playback and no second state to keep in
/// sync.
class SleepTimerNotifier extends Notifier<SleepTimerLength> {
  SleepTimerNotifier({this.scheduler = Timer.new});

  final SleepTimerScheduler scheduler;

  Timer? _timer;

  @override
  SleepTimerLength build() {
    ref.onDispose(_cancel);
    return SleepTimerLength.defaultLength;
  }

  /// Starts (or stops) the countdown for [length].
  ///
  /// Setting any choice cancels the previous deadline first, so picking a
  /// shorter time genuinely shortens the wait instead of leaving two armed.
  void set(SleepTimerLength length) {
    _cancel();
    state = length;
    final delay = length.delay;
    if (delay == null) return;
    _timer = scheduler(delay, _expire);
  }

  /// Cancels the countdown and returns to [SleepTimerLength.off].
  void cancel() {
    _cancel();
    state = SleepTimerLength.defaultLength;
  }

  Future<void> _expire() async {
    _timer = null;
    // The deadline is spent either way, so the row cannot show "30 minutes"
    // for a timer that already fired.
    state = SleepTimerLength.defaultLength;
    await ref.read(playbackControllerProvider).pause();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Provider for the session's sleep timer.
final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerLength>(
      SleepTimerNotifier.new,
    );
