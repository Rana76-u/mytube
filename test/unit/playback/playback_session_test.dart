import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_session.dart';

VideoItemSummary _item(String id, {String? title}) => VideoItemSummary(
  id: VideoItemId(id),
  title: title ?? 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

/// The app-owned playback session (ADR-014): it is the single owner of "what is
/// playing", so the player page, the mini player dock and the shell can never
/// disagree about it.
void main() {
  ProviderContainer containerFor() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  PlaybackSessionController controllerOf(ProviderContainer container) =>
      container.read(playbackSessionProvider.notifier);

  PlaybackSession sessionOf(ProviderContainer container) =>
      container.read(playbackSessionProvider);

  group('Session lifecycle', () {
    test('starts idle with nothing loaded', () {
      final session = sessionOf(containerFor());

      expect(session.mode, PlaybackSessionMode.idle);
      expect(session.item, isNull);
      expect(session.isActive, isFalse);
      expect(session.isMini, isFalse);
    });

    test('adopting an item marks the page open and publishes the label', () {
      final container = containerFor();
      final item = _item('a', title: 'Beach day');

      controllerOf(container).adopt(item);

      final session = sessionOf(container);
      expect(session.item?.id.value, 'a');
      expect(session.mode, PlaybackSessionMode.expanded);
      expect(session.isActive, isTrue);
      expect(session.isMini, isFalse);
      // The media notification follows the session, not the route.
      expect(container.read(nowPlayingProvider).title, 'Beach day');
    });

    test('collapsing docks the item without losing it', () {
      final container = containerFor();
      controllerOf(container).adopt(_item('a'));

      controllerOf(container).collapse();

      final session = sessionOf(container);
      expect(session.mode, PlaybackSessionMode.mini);
      expect(session.item?.id.value, 'a');
      expect(session.isMini, isTrue);
      expect(session.isActive, isTrue);
    });

    test('expanding returns the docked item to the page', () {
      final container = containerFor();
      controllerOf(container)
        ..adopt(_item('a'))
        ..collapse();

      controllerOf(container).expand();

      expect(sessionOf(container).mode, PlaybackSessionMode.expanded);
      expect(sessionOf(container).isMini, isFalse);
    });

    test('stopping clears everything', () {
      final container = containerFor();
      controllerOf(container)
        ..adopt(_item('a'))
        ..collapse();

      controllerOf(container).stop();

      final session = sessionOf(container);
      expect(session.mode, PlaybackSessionMode.idle);
      expect(session.item, isNull);
      expect(session.isActive, isFalse);
    });

    test('collapse and expand are no-ops with nothing loaded', () {
      final container = containerFor();
      final controller = controllerOf(container);

      // Popping a page that never started playback must not conjure a session.
      controller
        ..collapse()
        ..expand();

      expect(sessionOf(container).mode, PlaybackSessionMode.idle);
      expect(sessionOf(container).item, isNull);
    });

    test('switching items replaces the loaded item and its label', () {
      final container = containerFor();
      final controller = controllerOf(container);

      controller.adopt(_item('a', title: 'First'));
      controller.adopt(_item('b', title: 'Second'));

      expect(sessionOf(container).item?.id.value, 'b');
      expect(container.read(nowPlayingProvider).title, 'Second');
    });
  });

  group('Value semantics', () {
    test('an unchanged session is not re-notified', () {
      final container = containerFor();
      final controller = controllerOf(container);
      var notifications = 0;
      container.listen<PlaybackSession>(
        playbackSessionProvider,
        (_, _) => notifications++,
      );

      controller
        ..collapse()
        ..expand()
        ..stop();

      expect(
        notifications,
        0,
        reason: 'idle → idle transitions carry no information',
      );
    });

    test('equal sessions compare equal', () {
      expect(
        PlaybackSession(item: _item('a'), mode: PlaybackSessionMode.mini),
        PlaybackSession(item: _item('a'), mode: PlaybackSessionMode.mini),
      );
      expect(
        PlaybackSession(item: _item('a'), mode: PlaybackSessionMode.mini),
        isNot(
          PlaybackSession(item: _item('a'), mode: PlaybackSessionMode.idle),
        ),
      );
      expect(
        PlaybackSession(item: _item('a')),
        isNot(PlaybackSession(item: _item('b'))),
      );
    });
  });
}
