import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_overlay.dart';
import 'package:mytube/features/player/player_up_next.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Hand-written [PlaybackController] (house style): records commands and lets
/// a test push a new state, with no engine or provider underneath.
class _FakeController implements PlaybackController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  int pauses = 0;
  int resumes = 0;
  final List<Duration> seeks = <Duration>[];
  final List<Duration> skips = <Duration>[];
  final List<double> speeds = <double>[];

  void emit(PlaybackState next) => _state.value = next;

  @override
  ValueListenable<PlaybackState> get state => _state;

  /// Releases the notifier; named apart from [dispose] so the controller
  /// contract stays intact.
  void disposeState() => _state.dispose();

  @override
  Future<void> play(PlayableSource source) async {}

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> skipForward(Duration delta) async => skips.add(delta);

  @override
  Future<void> skipBackward(Duration delta) async => skips.add(-delta);

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> prewarm(PlayableSource source) async {}

  @override
  Future<void> dropPrewarm() async {}

  @override
  Widget? buildVideo() => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Deterministic stand-in for `Timer`: the chrome controller never creates a
/// real timer, so no pending-timer assertion can fire and a test can inspect
/// whether the auto-hide countdown is currently armed.
class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

class _Scheduler {
  final List<_FakeTimer> timers = <_FakeTimer>[];

  _FakeTimer? get last => timers.isEmpty ? null : timers.last;

  Timer call(Duration delay, void Function() callback) {
    final timer = _FakeTimer(callback);
    timers.add(timer);
    return timer;
  }
}

PlaybackState _state({
  PlaybackStatus status = PlaybackStatus.playing,
  Duration position = const Duration(seconds: 12),
  Duration duration = const Duration(minutes: 1),
  bool canSeek = true,
  String? error,
}) => PlaybackState(
  status: status,
  position: position,
  duration: duration,
  canSeek: canSeek,
  canRetry: error != null,
  error: error,
);

/// The item an autoplay countdown would hand over, for the ended-state tests.
final VideoItemSummary _nextItem = VideoItemSummary(
  id: VideoItemId('next'),
  title: 'Next up video',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

void main() {
  late _FakeController controller;
  late _Scheduler timers;
  late PlayerChromeController chrome;
  late ProviderContainer container;

  setUp(() {
    controller = _FakeController();
    timers = _Scheduler();
    chrome = PlayerChromeController(
      state: controller.state,
      scheduler: timers.call,
    );
    container = ProviderContainer(
      overrides: [playbackControllerProvider.overrideWithValue(controller)],
    );
  });

  tearDown(() {
    chrome.dispose();
    container.dispose();
    controller.disposeState();
  });

  Future<void> pumpOverlay(
    WidgetTester tester, {
    PlaybackState? state,
    String? title,
    VoidCallback? onBack,
    VoidCallback? onMinimise,
    List<Widget> actions = const [],
    Widget? completedAction,
    VoidCallback? onSkipToNext,
    double textScale = 1.0,
  }) async {
    controller.emit(state ?? _state());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            // VP7.1: the accessibility setting that matters here is text
            // scaling, so a test can ask for the OS's 200 % and see whether
            // the overlay still lays out.
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Center(
                  child: SizedBox(
                    width: 400,
                    height: 300,
                    // Rebuilt by the state listener exactly as the player
                    // screen does it, so an engine tick is a real case here
                    // too.
                    child: ValueListenableBuilder<PlaybackState>(
                      valueListenable: controller.state,
                      builder: (context, live, _) => PlayerOverlay(
                        state: live,
                        controller: controller,
                        chrome: chrome,
                        title: title,
                        onBack: onBack,
                        onMinimise: onMinimise,
                        actions: actions,
                        completedAction: completedAction,
                        onSkipToNext: onSkipToNext,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  IconButton buttonIn(WidgetTester tester, String key) =>
      tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(IconButton),
        ),
      );

  group('PlayerOverlay top bar (VP2.5, VP3.1)', () {
    testWidgets('draws the title as one ellipsised line', (tester) async {
      await pumpOverlay(tester);
      expect(find.byKey(const ValueKey('player_top_bar_title')), findsNothing);

      await pumpOverlay(tester, title: 'My Video');
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('player_top_bar_title')),
      );
      expect(title.data, 'My Video');
      expect(title.maxLines, 1);
      // A long title must not push the actions off the bar.
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('back replaces the chevron when the host supplies one', (
      tester,
    ) async {
      var backs = 0;
      var minimised = 0;
      await pumpOverlay(
        tester,
        onBack: () => backs++,
        onMinimise: () => minimised++,
      );

      // Exactly one leading control: the arrow wins in portrait.
      expect(find.byKey(const ValueKey('player_back_button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_minimise_button')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('player_back_button')));
      expect(backs, 1);
      expect(minimised, 0);
    });

    testWidgets('offers the minimise chevron only when the host can leave', (
      tester,
    ) async {
      await pumpOverlay(tester);
      expect(
        find.byKey(const ValueKey('player_minimise_button')),
        findsNothing,
      );

      var minimised = 0;
      await pumpOverlay(tester, onMinimise: () => minimised++);
      await tester.tap(find.byKey(const ValueKey('player_minimise_button')));

      expect(minimised, 1);
    });

    testWidgets('renders host actions in the bar', (tester) async {
      await pumpOverlay(
        tester,
        actions: [
          IconButton(
            key: const ValueKey('extra'),
            onPressed: () {},
            icon: const Icon(Icons.picture_in_picture_alt),
          ),
        ],
      );

      expect(find.byKey(const ValueKey('extra')), findsOneWidget);
    });
  });

  group('PlayerOverlay centre cluster (VP2.5)', () {
    testWidgets('play/pause pauses a playing video and resumes a paused one', (
      tester,
    ) async {
      await pumpOverlay(tester, state: _state());
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('player_play_pause')))
            .tooltip,
        'Pause',
      );

      await tester.tap(find.byKey(const ValueKey('player_play_pause')));
      expect(controller.pauses, 1);
      expect(controller.resumes, 0);

      await pumpOverlay(tester, state: _state(status: PlaybackStatus.paused));
      await tester.tap(find.byKey(const ValueKey('player_play_pause')));
      expect(controller.resumes, 1);
    });

    testWidgets('a buffering video shows a spinner instead of play/pause', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        state: _state(status: PlaybackStatus.buffering),
      );

      expect(
        find.byKey(const ValueKey('player_centre_spinner')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player_play_pause')), findsNothing);
    });

    testWidgets('completion offers replay, which resumes the controller', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        state: _state(status: PlaybackStatus.completed),
      );

      expect(
        find.byKey(const ValueKey('player_replay_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player_play_pause')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('player_replay_button')));
      expect(controller.resumes, 1);
    });

    testWidgets('idle keeps the disabled transport (not a perpetual spinner)', (
      tester,
    ) async {
      // A bare idle session may mean "stopped" or "a source failed to
      // resolve", so it keeps the transport visible but inert rather than
      // lying with a loading spinner (that only covers the first buffer).
      await pumpOverlay(tester, state: PlaybackState.idle);

      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('player_play_pause')))
            .onPressed,
        isNull,
      );
      expect(buttonIn(tester, 'player_rewind_10').onPressed, isNull);
      expect(buttonIn(tester, 'player_forward_10').onPressed, isNull);
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('player_error_message')), findsNothing);
    });

    testWidgets('the first buffering pass (no duration) is loading too', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        state: _state(
          status: PlaybackStatus.buffering,
          duration: Duration.zero,
          canSeek: false,
        ),
      );

      expect(find.byKey(const ValueKey('player_play_pause')), findsNothing);
      expect(find.byKey(const ValueKey('player_centre_spinner')), findsNothing);
    });

    testWidgets('an errored video shows the panel, not the transport', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        state: _state(status: PlaybackStatus.error, error: 'Playback failed'),
      );

      expect(find.byKey(const ValueKey('player_play_pause')), findsNothing);
      expect(find.byKey(const ValueKey('player_forward_10')), findsNothing);
      expect(
        find.byKey(const ValueKey('player_error_message')),
        findsOneWidget,
      );
      expect(find.text('Playback failed'), findsOneWidget);
      // A loaded source is retryable (_state sets canRetry when an error is
      // given), and the host offered no next row, so Skip-to-next stays hidden.
      expect(find.byKey(const ValueKey('player_retry_button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_skip_next_button')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('player_retry_button')));
      await tester.pump();
    });

    testWidgets('Skip-to-next appears only when the host supplies it', (
      tester,
    ) async {
      var skipped = 0;
      await pumpOverlay(
        tester,
        state: _state(status: PlaybackStatus.error, error: 'No codec'),
        onSkipToNext: () => skipped++,
      );

      await tester.tap(find.byKey(const ValueKey('player_skip_next_button')));
      expect(skipped, 1);
    });

    testWidgets('an error with no retryable source offers no Retry', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        state: const PlaybackState(
          status: PlaybackStatus.error,
          error: 'This source type cannot be played.',
          canRetry: false,
        ),
      );

      expect(find.byKey(const ValueKey('player_retry_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('player_error_message')),
        findsOneWidget,
      );
    });

    testWidgets('the skip buttons move the playhead by ten seconds', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.tap(find.byKey(const ValueKey('player_rewind_10')));
      await tester.tap(find.byKey(const ValueKey('player_forward_10')));

      expect(controller.skips, [
        const Duration(seconds: -10),
        const Duration(seconds: 10),
      ]);
    });

    testWidgets('skips are disabled when the source cannot seek', (
      tester,
    ) async {
      await pumpOverlay(tester, state: _state(canSeek: false));

      expect(buttonIn(tester, 'player_rewind_10').onPressed, isNull);
      expect(buttonIn(tester, 'player_forward_10').onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('player_forward_10')));
      expect(controller.skips, isEmpty);
    });
  });

  group('PlayerOverlay bottom bar (VP2.5)', () {
    testWidgets('the time label toggles between elapsed and remaining', (
      tester,
    ) async {
      await pumpOverlay(tester);
      expect(find.text('0:12 / 1:00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player_time_label')));
      await tester.pump();

      expect(find.text('-0:48'), findsOneWidget);
      expect(find.text('0:12 / 1:00'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('player_time_label')));
      await tester.pump();

      expect(find.text('0:12 / 1:00'), findsOneWidget);
    });

    testWidgets('dragging the seek bar holds the auto-hide countdown', (
      tester,
    ) async {
      await pumpOverlay(tester);
      expect(chrome.isVisible, isTrue);
      expect(timers.last?.isActive, isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('player_seek_bar'))),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      // The countdown is cancelled while the finger is down, so the chrome
      // cannot vanish mid-scrub.
      expect(timers.last?.isActive, isFalse);
      expect(chrome.isVisible, isTrue);

      await gesture.up();
      await tester.pump();

      // Releasing re-arms it, so the chrome does not stay up forever.
      expect(timers.last?.isActive, isTrue);
    });

    testWidgets('the seek bar reports its own seek on release', (tester) async {
      await pumpOverlay(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('player_seek_bar'))),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(controller.seeks, isEmpty);

      await gesture.up();
      await tester.pump();

      expect(controller.seeks, hasLength(1));
    });
  });

  group('PlayerProgressLine (VP2.5)', () {
    Widget line(PlaybackState state) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: PlayerProgressLine(state: state),
          ),
        ),
      ),
    );

    testWidgets('paints the played fraction at the bottom edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        line(
          _state(
            position: const Duration(seconds: 15),
            duration: const Duration(minutes: 1),
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(
        find.byKey(const ValueKey('player_progress_line')),
      );
      expect(size.height, 2);
      expect(size.width, closeTo(100, 0.5));
    });

    testWidgets('an unknown duration paints nothing', (tester) async {
      await tester.pumpWidget(
        line(_state(duration: Duration.zero, canSeek: false)),
      );
      await tester.pump();

      final size = tester.getSize(
        find.byKey(const ValueKey('player_progress_line')),
      );
      expect(size.width, 0);
    });
  });

  group('PlayerLoadingIndicator (VP5.1)', () {
    Widget loading(PlaybackState state) => MaterialApp(
      home: Scaffold(body: PlayerLoadingIndicator(state: state)),
    );

    testWidgets('spins during the first buffering pass only', (tester) async {
      // A bare idle session does not spin (it may be stopped / a failed
      // resolve), so only the pre-duration buffer triggers the spinner.
      await tester.pumpWidget(loading(PlaybackState.idle));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsNothing,
      );

      await tester.pumpWidget(
        loading(
          const PlaybackState(
            status: PlaybackStatus.buffering,
            duration: Duration.zero,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsOneWidget,
      );
    });

    testWidgets('steps aside once a frame or a duration exists', (
      tester,
    ) async {
      // A known-duration rebuffer is the centre cluster's job, not the loading
      // spinner's; a playing or completed session never shows it.
      await tester.pumpWidget(
        loading(
          _state(
            status: PlaybackStatus.buffering,
            duration: const Duration(seconds: 30),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsNothing,
      );

      await tester.pumpWidget(loading(_state()));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsNothing,
      );
    });
  });

  group('PlayerOverlay ended action (VP3.5)', () {
    const Widget slot = Text('Next up', key: ValueKey('completed_slot'));

    testWidgets('the completed action appears only once the video ends', (
      tester,
    ) async {
      await pumpOverlay(tester, completedAction: slot);
      expect(find.byKey(const ValueKey('completed_slot')), findsNothing);

      await pumpOverlay(
        tester,
        state: _state(status: PlaybackStatus.completed),
        completedAction: slot,
      );
      expect(find.byKey(const ValueKey('completed_slot')), findsOneWidget);
      // The replay control keeps its place above it: the countdown adds a way
      // forward, it does not replace the way back.
      expect(
        find.byKey(const ValueKey('player_replay_button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'an inserted countdown starts ticking at the end, not at the build',
      (tester) async {
        var started = 0;
        await pumpOverlay(
          tester,
          state: _state(status: PlaybackStatus.completed),
          completedAction: PlayerAutoplayCountdown(
            item: _nextItem,
            onPlay: () => started++,
          ),
        );

        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('player_autoplay_countdown')),
              )
              .data,
          'Playing next in 5s',
        );

        await tester.pump(const Duration(seconds: 2));
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('player_autoplay_countdown')),
              )
              .data,
          'Playing next in 3s',
        );

        await tester.tap(find.byKey(const ValueKey('player_autoplay_cancel')));
        await tester.pump();
        expect(started, 0);

        await tester.pump(const Duration(seconds: 10));
        expect(started, 0);
      },
    );
  });

  group('PlayerLockOverlay (VP5.6)', () {
    Widget overlay(bool locked, VoidCallback onUnlock) => MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [PlayerLockOverlay(locked: locked, onUnlock: onUnlock)],
        ),
      ),
    );

    testWidgets('absent while unlocked', (tester) async {
      await tester.pumpWidget(overlay(false, () {}));
      await tester.pump();
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsNothing);
      expect(find.byKey(const ValueKey('player_unlock_button')), findsNothing);
    });

    testWidgets('reveals the single unlock affordance on tap', (tester) async {
      var unlocks = 0;
      await tester.pumpWidget(overlay(true, () => unlocks++));
      await tester.pump();

      // A locked screen starts as a bare padlock hint with no button.
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_unlock_button')), findsNothing);

      // The first tap reveals the unlock affordance…
      await tester.tap(find.byKey(const ValueKey('player_lock_overlay')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_unlock_button')),
        findsOneWidget,
      );

      // …and tapping it unlocks.
      await tester.tap(find.byKey(const ValueKey('player_unlock_button')));
      expect(unlocks, 1);
    });

    testWidgets('the reveal falls back to the hint after a pause', (
      tester,
    ) async {
      await tester.pumpWidget(overlay(true, () {}));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('player_lock_overlay')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_unlock_button')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('player_unlock_button')), findsNothing);
    });
  });

  group('PlayerOverlay semantics (VP7.1)', () {
    testWidgets('announces the video title as the page header', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpOverlay(tester, title: 'My Video');

      // getSemantics walks up from the Text to the role that wraps it.
      final node = tester.getSemantics(
        find.byKey(const ValueKey('player_top_bar_title')),
      );
      expect(node.label, 'My Video');
      expect(node.getSemanticsData().flagsCollection.isHeader, isTrue);

      semantics.dispose();
    });

    testWidgets('the time label is a button that names the toggle', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpOverlay(
        tester,
        state: _state(position: const Duration(seconds: 12)),
      );

      final label = find.byKey(const ValueKey('player_time_label'));
      var node = tester.getSemantics(label);
      expect(node.label, 'Elapsed time');
      expect(node.value, '0:12 / 1:00');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      // Toggling swaps both the words and the digits, so a screen reader is
      // never left describing the previous mode.
      await tester.tap(label);
      await tester.pump();

      node = tester.getSemantics(label);
      expect(node.label, 'Remaining time');
      expect(node.value, '-0:48');

      semantics.dispose();
    });

    testWidgets('an error is announced as a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpOverlay(
        tester,
        state: _state(
          status: PlaybackStatus.error,
          error: 'Could not load this video.',
        ),
      );

      final node = tester.getSemantics(
        find.byKey(const ValueKey('player_error_message')),
      );
      expect(node.label, 'Could not load this video.');
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

      semantics.dispose();
    });

    testWidgets('the first-load spinner is labelled until a duration lands', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      Future<void> pumpIndicator(PlaybackState state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: PlayerLoadingIndicator(state: state),
            ),
          ),
        );
        await tester.pump();
      }

      // The first buffering pass, before the engine knows a duration.
      await pumpIndicator(
        _state(status: PlaybackStatus.buffering, duration: Duration.zero),
      );
      final node = tester.getSemantics(
        find.byKey(const ValueKey('player_loading_spinner')),
      );
      expect(node.label, 'Loading video');

      // Once a duration arrives the pass is over: no spinner, no label left
      // behind for a screen reader to read.
      await pumpIndicator(_state());
      expect(
        find.byKey(const ValueKey('player_loading_spinner')),
        findsNothing,
      );

      semantics.dispose();
    });
  });

  group('PlayerOverlay tap targets (VP7.1)', () {
    testWidgets('every control in the bar keeps a 48 dp target', (
      tester,
    ) async {
      await pumpOverlay(tester, onBack: () {});

      for (final key in [
        'player_time_label',
        'player_back_button',
        'player_play_pause',
        'player_rewind_10',
        'player_forward_10',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: '$key must offer a 48 dp target',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(48),
          reason: '$key must offer a 48 dp target',
        );
      }
    });
  });

  group('PlayerOverlay text scaling (VP7.1)', () {
    testWidgets('lays out at 200 % without clipping a control', (tester) async {
      await pumpOverlay(
        tester,
        textScale: 2.0,
        title: 'A rather long video title that has to ellipsise',
        actions: [
          IconButton(
            key: const ValueKey('extra'),
            onPressed: () {},
            icon: const Icon(Icons.picture_in_picture_alt),
          ),
        ],
      );

      // A RenderFlex overflow is reported as a FlutterError; none is allowed,
      // and every control must still be on screen.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('player_play_pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_time_label')), findsOneWidget);
      expect(find.byKey(const ValueKey('extra')), findsOneWidget);
    });

    testWidgets('lays out an error at 200 % without clipping', (tester) async {
      await pumpOverlay(
        tester,
        textScale: 2.0,
        state: _state(
          status: PlaybackStatus.error,
          error: 'This video cannot be played.',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('player_error_message')),
        findsOneWidget,
      );
    });
  });

  group('PlayerOverlay.transportEnabled (VP2.5)', () {
    test('gates the transport by status', () {
      expect(
        PlayerOverlay.transportEnabled(
          const PlaybackState(status: PlaybackStatus.idle),
        ),
        isFalse,
      );
      expect(
        PlayerOverlay.transportEnabled(
          const PlaybackState(status: PlaybackStatus.error),
        ),
        isFalse,
      );
      for (final status in [
        PlaybackStatus.buffering,
        PlaybackStatus.playing,
        PlaybackStatus.paused,
        PlaybackStatus.completed,
      ]) {
        expect(
          PlayerOverlay.transportEnabled(PlaybackState(status: status)),
          isTrue,
          reason: '$status should allow transport',
        );
      }
    });
  });
}
