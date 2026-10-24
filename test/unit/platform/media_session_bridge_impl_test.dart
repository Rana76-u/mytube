import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/platform/media_session_bridge.dart';
import 'package:mytube/platform/media_session_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/media_session');

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('encodeMediaSnapshot (pure)', () {
    test('serializes durations to milliseconds and keeps primitives', () {
      const snapshot = MediaSessionSnapshot(
        title: 'Clip',
        isPlaying: true,
        position: Duration(seconds: 12),
        duration: Duration(minutes: 1, seconds: 30),
        canSeek: false,
        speed: 1.5,
      );

      final map = encodeMediaSnapshot(snapshot);

      expect(map['title'], 'Clip');
      expect(map['isPlaying'], isTrue);
      expect(map['positionMs'], 12000);
      expect(map['durationMs'], 90000);
      expect(map['canSeek'], isFalse);
      expect(map['speed'], 1.5);
    });
  });

  group('decodeMediaTransport (pure)', () {
    test('maps every transport action', () {
      expect(
        decodeMediaTransport({'action': 'play'})?.action,
        MediaTransportAction.play,
      );
      expect(
        decodeMediaTransport({'action': 'pause'})?.action,
        MediaTransportAction.pause,
      );
      expect(
        decodeMediaTransport({'action': 'seekTo'})?.action,
        MediaTransportAction.seekTo,
      );
      expect(
        decodeMediaTransport({'action': 'stop'})?.action,
        MediaTransportAction.stop,
      );
    });

    test('carries the seek position in milliseconds', () {
      final command = decodeMediaTransport({
        'action': 'seekTo',
        'positionMs': 42000,
      });
      expect(command?.position, const Duration(seconds: 42));
    });

    test('a missing position decodes to null position', () {
      final command = decodeMediaTransport({'action': 'seekTo'});
      expect(command?.action, MediaTransportAction.seekTo);
      expect(command?.position, isNull);
    });

    test('unknown actions decode to null', () {
      expect(decodeMediaTransport({'action': 'shuffle'}), isNull);
      expect(decodeMediaTransport(<Object?, Object?>{}), isNull);
    });
  });

  group('MediaSessionBridgeImpl command channel (P13-03)', () {
    test('render / stop / release invoke the matching methods', () async {
      final calls = <String>[];
      Object? renderArgs;
      setHandler((call) async {
        calls.add(call.method);
        if (call.method == 'render') {
          renderArgs = call.arguments;
        }
        return null;
      });

      final impl = MediaSessionBridgeImpl();
      await impl.render(
        const MediaSessionSnapshot(
          title: 'Clip',
          isPlaying: true,
          position: Duration(seconds: 1),
          duration: Duration(seconds: 60),
          canSeek: true,
        ),
      );
      await impl.stop();
      await impl.release();

      expect(calls, ['render', 'stop', 'release']);
      expect((renderArgs! as Map)['title'], 'Clip');
      expect((renderArgs! as Map)['durationMs'], 60000);
    });

    test('requestNotificationPermission returns the native result', () async {
      setHandler((call) async {
        if (call.method == 'requestNotificationPermission') return false;
        return null;
      });

      final impl = MediaSessionBridgeImpl();
      final granted = await impl.requestNotificationPermission();
      expect(granted, isFalse);
      await impl.release();
    });

    test(
      'missing plugin degrades safely (no throw, permission reported true)',
      () async {
        // No mock handler set → invokeMethod throws MissingPluginException, which
        // the implementation must swallow so unsupported hosts never crash
        // playback (PLAY-013).
        final impl = MediaSessionBridgeImpl();
        await expectLater(
          impl.render(
            const MediaSessionSnapshot(
              title: 'Clip',
              isPlaying: true,
              position: Duration.zero,
              duration: Duration.zero,
              canSeek: false,
            ),
          ),
          completes,
        );
        await expectLater(impl.stop(), completes);
        expect(await impl.requestNotificationPermission(), isTrue);
        await expectLater(impl.release(), completes);
      },
    );

    test('PlatformException from a command is swallowed', () async {
      setHandler((call) async {
        throw PlatformException(code: 'SESSION_FAILED');
      });

      final impl = MediaSessionBridgeImpl();
      await expectLater(
        impl.render(
          const MediaSessionSnapshot(
            title: 'Clip',
            isPlaying: false,
            position: Duration.zero,
            duration: Duration.zero,
            canSeek: false,
          ),
        ),
        completes,
      );
      expect(await impl.requestNotificationPermission(), isTrue);
      await impl.release();
    });
  });

  group('MediaSessionBridgeImpl transport delivery', () {
    test('an incoming onTransport call emits a decoded command', () async {
      final impl = MediaSessionBridgeImpl();
      addTearDown(impl.release);

      final received = <MediaTransportCommand>[];
      final sub = impl.commands.listen(received.add);

      // Simulate the native side calling back into the Dart handler.
      const codec = StandardMethodCodec();
      final encoded = codec.encodeMethodCall(
        const MethodCall('onTransport', <String, Object>{
          'action': 'seekTo',
          'positionMs': 7000,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, encoded, (ByteData? _) {});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.action, MediaTransportAction.seekTo);
      expect(received.single.position, const Duration(seconds: 7));
      await sub.cancel();
    });
  });
}
