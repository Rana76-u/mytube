import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/features/reels/reels_source_preloader.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

PlayableSource _source(String id) => PlayableSource(
  uri: Uri.parse('content://play/$id'),
  sourceId: id,
  sourceType: ProviderType.localMediaStore,
  canSeek: true,
);

/// Resolver whose completions the test controls, so a preload can be observed
/// mid-flight and then cancelled.
class _ControlledResolver implements PlaybackSourceResolver {
  final List<String> requested = <String>[];
  final Map<String, Completer<Result<PlayableSource>>> _pending = {};

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) {
    requested.add(item.id.value);
    final completer = Completer<Result<PlayableSource>>();
    _pending[item.id.value] = completer;
    return completer.future;
  }

  void complete(String id) => _pending[id]!.complete(Result.ok(_source(id)));

  void completeWithError(String id) => _pending[id]!.complete(
    const Err(UnexpectedError(diagnosticMessage: 'resolve failed')),
  );
}

/// Resolver that finishes on the next microtask, for cache-fill tests.
class _AutoResolver implements PlaybackSourceResolver {
  int resolveCalls = 0;

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) {
    resolveCalls++;
    return Future.value(Result.ok(_source(item.id.value)));
  }
}

Future<void> _flush() async {
  // Drain the resolver future and the preloader's `.then` continuation.
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ReelsSourcePreloader (P6-04, PLAY-008)', () {
    test('caches a preloaded source and hands it out once via take', () async {
      final preloader = ReelsSourcePreloader(resolver: _AutoResolver());
      preloader.preload(_item('a'));
      await _flush();

      expect(preloader.cachedCount, 1);
      expect(preloader.take(_item('a')), isNotNull);
      // take() consumes the entry, so a second call misses.
      expect(preloader.take(_item('a')), isNull);
      expect(preloader.cachedCount, 0);
    });

    test('does not resolve the same reel twice while it is warm', () async {
      final resolver = _AutoResolver();
      final preloader = ReelsSourcePreloader(resolver: resolver);
      preloader
        ..preload(_item('a'))
        ..preload(_item('a'));
      await _flush();

      expect(resolver.resolveCalls, 1);
    });

    test(
      'discards a preload that finishes after invalidation (rapid swipe)',
      () async {
        final resolver = _ControlledResolver();
        final preloader = ReelsSourcePreloader(resolver: resolver);

        preloader.preload(_item('a')); // resolution now in flight
        expect(preloader.cachedCount, 0); // not yet resolved

        preloader.invalidate(); // the user swiped before it landed
        resolver.complete('a');
        await _flush();

        // The stale result was dropped instead of cached.
        expect(preloader.cachedCount, 0);
        expect(preloader.take(_item('a')), isNull);
      },
    );

    test(
      'a preload completed before invalidation is still consumable',
      () async {
        final resolver = _ControlledResolver();
        final preloader = ReelsSourcePreloader(resolver: resolver);

        preloader.preload(_item('a'));
        resolver.complete('a');
        await _flush();

        preloader.invalidate();
        // A just-swiped reel can still reuse its already-warmed source.
        expect(preloader.take(_item('a')), isNotNull);
      },
    );

    test('the cache is FIFO-bounded to maxCache entries', () async {
      final preloader = ReelsSourcePreloader(
        resolver: _AutoResolver(),
        maxCache: 2,
      );
      preloader
        ..preload(_item('a'))
        ..preload(_item('b'))
        ..preload(_item('c'));
      await _flush();

      expect(preloader.cachedCount, 2);
      // The oldest ('a') was evicted to make room for 'c'.
      expect(preloader.take(_item('a')), isNull);
      expect(preloader.take(_item('b')), isNotNull);
      expect(preloader.take(_item('c')), isNotNull);
    });

    test(
      'clear empties the cache so nothing stale survives leaving the tab',
      () async {
        final preloader = ReelsSourcePreloader(resolver: _AutoResolver());
        preloader.preload(_item('a'));
        await _flush();
        expect(preloader.cachedCount, 1);

        preloader.clear();
        expect(preloader.cachedCount, 0);
        expect(preloader.take(_item('a')), isNull);
      },
    );

    test('a failed resolve is not cached', () async {
      final resolver = _ControlledResolver();
      final preloader = ReelsSourcePreloader(resolver: resolver);

      preloader.preload(_item('a'));
      resolver.completeWithError('a');
      await _flush();

      expect(preloader.cachedCount, 0);
    });

    test('onWarmed reports a fresh landing to the host', () async {
      final warmed = <String>[];
      final preloader = ReelsSourcePreloader(
        resolver: _AutoResolver(),
        onWarmed: (item, source) => warmed.add(item.id.value),
      );
      preloader.preload(_item('a'));
      await _flush();

      expect(warmed, ['a']);
    });

    test('onWarmed never fires for stale or failed preloads', () async {
      var callbacks = 0;
      final resolver = _ControlledResolver();
      final preloader = ReelsSourcePreloader(
        resolver: resolver,
        onWarmed: (item, source) => callbacks++,
      );

      preloader.preload(_item('a'));
      preloader.invalidate(); // 'a' lands stale (the user already swiped)
      resolver.complete('a');
      await _flush();

      preloader.preload(_item('b'));
      resolver.completeWithError('b');
      await _flush();

      expect(callbacks, 0);
    });
  });
}
