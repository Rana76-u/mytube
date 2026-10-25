import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/playback/now_playing.dart';

/// The now-playing label is published from a playback screen and consumed by the
/// app shell's `ref.listen`, which forwards every change to
/// [MediaSessionCoordinator.setNowPlaying]. Value equality is what keeps an
/// identical re-publish (a re-issued play of the same item) from becoming a
/// pointless notification hop.
void main() {
  group('NowPlayingInfo', () {
    test('compares by title', () {
      expect(
        const NowPlayingInfo(title: 'A'),
        const NowPlayingInfo(title: 'A'),
      );
      expect(
        const NowPlayingInfo(title: 'A').hashCode,
        const NowPlayingInfo(title: 'A').hashCode,
      );
      expect(const NowPlayingInfo(title: 'A'), isNot(const NowPlayingInfo()));
      expect(
        const NowPlayingInfo(),
        const NowPlayingInfo(title: null),
        reason: 'an absent title is the same label as no entry at all',
      );
    });
  });

  group('NowPlayingNotifier', () {
    late ProviderContainer container;
    late int notifications;

    setUp(() {
      container = ProviderContainer();
      notifications = 0;
      container.listen(
        nowPlayingProvider,
        (_, _) => notifications++,
        fireImmediately: false,
      );
    });

    tearDown(() => container.dispose());

    test('a new title notifies listeners', () {
      container.read(nowPlayingProvider.notifier).setTitle('Clip');
      expect(container.read(nowPlayingProvider).title, 'Clip');
      expect(notifications, 1);
    });

    test('re-publishing the same title notifies nobody', () {
      final notifier = container.read(nowPlayingProvider.notifier);
      notifier.setTitle('Clip');
      notifier.setTitle('Clip');
      notifier.setTitle('Clip');
      expect(notifications, 1);
    });

    test('a changed title notifies again', () {
      final notifier = container.read(nowPlayingProvider.notifier);
      notifier.setTitle('One');
      notifier.setTitle('Two');
      expect(notifications, 2);
      expect(container.read(nowPlayingProvider).title, 'Two');
    });

    test('build starts unlabeled', () {
      expect(container.read(nowPlayingProvider).title, isNull);
      expect(container.read(nowPlayingProvider), const NowPlayingInfo());
    });
  });
}
