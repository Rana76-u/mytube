import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Size, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/playback/video_player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Manual fake [VideoPlayerPlatform] (house style — no mocking package).
///
/// Records every engine call and lets tests push [VideoEvent]s / errors into
/// the per-player event stream, mirroring the real Android plugin.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int nextPlayerId = 0;
  final Map<int, DataSource> created = <int, DataSource>{};
  final List<int> disposed = <int>[];
  final List<int> played = <int>[];
  final List<int> paused = <int>[];
  final Map<int, Duration> seeks = <int, Duration>{};
  final Map<int, double> volumes = <int, double>{};
  final Map<int, double> speeds = <int, double>{};
  final Map<int, Duration> positions = <int, Duration>{};
  final Map<int, StreamController<VideoEvent>> events =
      <int, StreamController<VideoEvent>>{};

  StreamController<VideoEvent> _controllerFor(int playerId) => events
      .putIfAbsent(playerId, () => StreamController<VideoEvent>.broadcast());

  void emit(int playerId, VideoEvent event) {
    _controllerFor(playerId).add(event);
  }

  void emitError(int playerId, PlatformException error) {
    _controllerFor(playerId).addError(error);
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = nextPlayerId++;
    created[id] = options.dataSource;
    _controllerFor(id);
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    final controller = events.remove(playerId);
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _controllerFor(playerId).stream;

  @override
  Future<void> play(int playerId) async => played.add(playerId);

  @override
  Future<void> pause(int playerId) async => paused.add(playerId);

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      seeks[playerId] = position;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes[playerId] = volume;

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      speeds[playerId] = speed;

  // The engine applies looping state on its initialized event; nothing in this
  // feature uses looping yet (Reels loops in Phase 6), so a no-op is enough.
  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
}

PlayableSource _source(String uri, {bool canSeek = true}) => PlayableSource(
  uri: Uri.parse(uri),
  sourceId: uri,
  sourceType: ProviderType.directUrl,
  canSeek: canSeek,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlayerPlatform platform;
  VideoPlayerPlatform? originalPlatform;

  setUp(() {
    platform = FakeVideoPlayerPlatform();
    originalPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    final restore = originalPlatform;
    if (restore != null) {
      VideoPlayerPlatform.instance = restore;
    }
  });

  group('playbackKindFor', () {
    test('classifies supported and unsupported schemes', () {
      expect(
        playbackKindFor(Uri.parse('content://media/external/video/1')),
        PlaybackKind.content,
      );
      expect(
        playbackKindFor(Uri.parse('content://com.android.providers/a')),
        PlaybackKind.content,
      );
      expect(
        playbackKindFor(Uri.parse('file:///sdcard/v.mp4')),
        PlaybackKind.file,
      );
      expect(
        playbackKindFor(Uri.parse('https://example.com/v.mp4')),
        PlaybackKind.network,
      );
      expect(
        playbackKindFor(Uri.parse('http://192.168.1.10:8080/v.mp4')),
        PlaybackKind.network,
      );
      expect(
        playbackKindFor(Uri.parse('ftp://example.com/v.mp4')),
        PlaybackKind.unsupported,
      );
      expect(
        playbackKindFor(Uri.parse('rtsp://example.com/live')),
        PlaybackKind.unsupported,
      );
      expect(
        playbackKindFor(Uri.parse('/relative/path.mp4')),
        PlaybackKind.unsupported,
      );
    });
  });

  group('VideoPlayerHandle scheme routing', () {
    test('content:// routes to the engine contentUri data source', () async {
      final handle = VideoPlayerHandle(
        source: _source('content://media/external/video/42'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(0, VideoEvent(eventType: VideoEventType.initialized));
      await initializing;

      final dataSource = platform.created[0]!;
      expect(dataSource.sourceType, DataSourceType.contentUri);
      expect(dataSource.uri, 'content://media/external/video/42');
    });

    test('https routes to the engine network data source', () async {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(0, VideoEvent(eventType: VideoEventType.initialized));
      await initializing;

      expect(platform.created[0]!.sourceType, DataSourceType.network);
      expect(platform.created[0]!.uri, 'https://example.com/v.mp4');
    });

    test('network sources carry adapter headers into the engine', () async {
      final handle = VideoPlayerHandle(
        source: PlayableSource(
          uri: Uri.parse('https://example.com/v.mp4'),
          sourceId: 'https://example.com/v.mp4',
          sourceType: ProviderType.directUrl,
          httpHeaders: const {'User-Agent': 'MyTube/0.1'},
        ),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(0, VideoEvent(eventType: VideoEventType.initialized));
      await initializing;

      expect(platform.created[0]!.httpHeaders, {'User-Agent': 'MyTube/0.1'});
    });

    test('file:// routes to the engine file data source', () async {
      final handle = VideoPlayerHandle(
        source: _source('file:///storage/emulated/0/DCIM/v.mp4'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(0, VideoEvent(eventType: VideoEventType.initialized));
      await initializing;

      final dataSource = platform.created[0]!;
      expect(dataSource.sourceType, DataSourceType.file);
      // The engine absolute-normalizes the path against the host filesystem
      // (on a Windows dev host the URI gains a drive letter; on Android it
      // stays POSIX).  Assert the stable suffix only.
      expect(dataSource.uri, endsWith('storage/emulated/0/DCIM/v.mp4'));
    });

    test('unsupported scheme never reaches the engine', () {
      expect(
        () => videoPlayerHandleFactory(_source('rtsp://example.com/live')),
        throwsStateError,
      );
      expect(platform.created, isEmpty);
    });
  });

  group('VideoPlayerHandle snapshot mapping', () {
    test('uninitialized engines report not-ready buffering state', () {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      final snapshot = handle.snapshot;
      expect(snapshot.initialized, isFalse);
      expect(snapshot.playing, isFalse);
      expect(snapshot.duration, Duration.zero);
      expect(snapshot.errorText, isNull);
    });

    test('initialized event populates duration and readiness', () async {
      final handle = VideoPlayerHandle(
        source: _source('content://media/external/video/7'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      expect(handle.snapshot.initialized, isFalse);

      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 90),
          size: const Size(1920, 1080),
          rotationCorrection: 0,
        ),
      );
      await initializing;

      final snapshot = handle.snapshot;
      expect(snapshot.initialized, isTrue);
      expect(snapshot.duration, const Duration(seconds: 90));
    });

    test('buffering and playing-state events toggle the snapshot', () async {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(640, 360),
          rotationCorrection: 0,
        ),
      );
      await initializing;

      platform.emit(0, VideoEvent(eventType: VideoEventType.bufferingStart));
      await pumpEventQueue();
      expect(handle.snapshot.buffering, isTrue);

      platform.emit(0, VideoEvent(eventType: VideoEventType.bufferingEnd));
      await pumpEventQueue();
      expect(handle.snapshot.buffering, isFalse);

      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: true,
        ),
      );
      await pumpEventQueue();
      expect(handle.snapshot.playing, isTrue);
    });

    test('completed event marks completion and stops the engine', () async {
      final handle = VideoPlayerHandle(
        source: _source('content://media/external/video/9'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(320, 240),
          rotationCorrection: 0,
        ),
      );
      await initializing;

      platform.emit(0, VideoEvent(eventType: VideoEventType.completed));
      await pumpEventQueue();
      await pumpEventQueue(); // controller pauses, then seeks to the end

      expect(handle.snapshot.completed, isTrue);
      expect(platform.paused, contains(0));
      expect(platform.seeks[0], const Duration(seconds: 10));
    });

    test(
      'platform errors surface as snapshot error text and throw from initialize',
      () async {
        final handle = VideoPlayerHandle(
          source: _source('https://example.com/v.mp4'),
        );
        addTearDown(handle.dispose);

        final initializing = handle.initialize();
        await pumpEventQueue();
        platform.emitError(
          0,
          PlatformException(
            code: 'VideoError',
            message: 'Source error: secret-detail',
          ),
        );

        await expectLater(initializing, throwsA(isA<PlatformException>()));
        await pumpEventQueue();

        expect(handle.snapshot.errorText, 'Source error: secret-detail');
        expect(handle.snapshot.initialized, isFalse);
      },
    );
  });

  group('VideoPlayerHandle commands and lifecycle', () {
    test('commands are forwarded to the engine', () async {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 60),
          size: const Size(640, 360),
          rotationCorrection: 0,
        ),
      );
      await initializing;

      await handle.play();
      // Speed only reaches the platform while playing (the package defers it
      // for paused media and re-applies on resume), so set it before pausing.
      await handle.setSpeed(1.5);
      await handle.pause();
      await handle.seekTo(const Duration(seconds: 7));
      await handle.setVolume(0.5);
      await pumpEventQueue();

      expect(platform.played, [0]);
      // The engine's initialized event applies the current (paused) state, so
      // it issues its own platform pause before our explicit one.
      expect(platform.paused, [0, 0]);
      expect(platform.seeks[0], const Duration(seconds: 7));
      expect(platform.volumes[0], 0.5);
      expect(platform.speeds[0], 1.5);
    });

    test(
      'changes stream emits on engine updates and closes on dispose',
      () async {
        final handle = VideoPlayerHandle(
          source: _source('https://example.com/v.mp4'),
        );

        final changes = <int>[];
        var streamClosed = false;
        final subscription = handle.changes.listen(
          (_) => changes.add(1),
          onDone: () => streamClosed = true,
        );

        final initializing = handle.initialize();
        await pumpEventQueue();
        platform.emit(
          0,
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 5),
            size: const Size(320, 240),
            rotationCorrection: 0,
          ),
        );
        await initializing;
        await pumpEventQueue();
        expect(changes, isNotEmpty);

        await handle.dispose();
        await pumpEventQueue();
        expect(streamClosed, isTrue);
        expect(platform.disposed, contains(0));

        await handle.dispose(); // idempotent
        expect(platform.disposed.where((id) => id == 0), hasLength(1));
        await subscription.cancel();
      },
    );
  });

  group('VideoPlayerHandle.buildVideo', () {
    /// Initializes a handle and drives the engine's `initialized` event with
    /// the given natural [size] / [rotationCorrection], returning the handle.
    Future<VideoPlayerHandle> initializedHandle({
      required Size size,
      int rotationCorrection = 0,
    }) async {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      final initializing = handle.initialize();
      await pumpEventQueue();
      platform.emit(
        0,
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: size,
          rotationCorrection: rotationCorrection,
        ),
      );
      await initializing;
      return handle;
    }

    test('returns null before the engine is initialized', () {
      final handle = VideoPlayerHandle(
        source: _source('https://example.com/v.mp4'),
      );
      addTearDown(handle.dispose);

      expect(handle.buildVideo(), isNull);
    });

    test(
      'anchors the texture to the natural size so layout stays bounded',
      () async {
        final handle = await initializedHandle(size: const Size(1920, 1080));

        final widget = handle.buildVideo();
        // A FittedBox lays its child out with unbounded constraints; the anchored
        // SizedBox is what keeps the texture from ever taking an infinite size
        // (the Reels-open layout crash).
        expect(widget, isA<SizedBox>());
        final box = widget! as SizedBox;
        expect(box.width, 1920);
        expect(box.height, 1080);
        expect(box.child, isA<VideoPlayer>());
      },
    );

    test(
      'swaps the box for 90°/270° rotation to match the internal RotatedBox',
      () async {
        final handle = await initializedHandle(
          size: const Size(1920, 1080),
          rotationCorrection: 90,
        );

        final box = handle.buildVideo()! as SizedBox;
        expect(box.width, 1080);
        expect(box.height, 1920);
      },
    );

    test('returns null when the engine reports an empty size', () async {
      final handle = await initializedHandle(size: Size.zero);

      expect(handle.buildVideo(), isNull);
    });
  });
}
