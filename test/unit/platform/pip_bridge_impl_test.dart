import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/platform/pip_bridge.dart';
import 'package:mytube/platform/pip_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/pip');

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('pipAspectFor (pure)', () {
    test('reduces a landscape picture to lowest terms (16:9)', () {
      expect(pipAspectFor(const Size(1920, 1080)), const PipAspect(16, 9));
    });

    test('reduces a portrait picture to lowest terms (9:16)', () {
      expect(pipAspectFor(const Size(1080, 1920)), const PipAspect(9, 16));
    });

    test('a square picture becomes 1:1', () {
      expect(pipAspectFor(const Size(500, 500)), const PipAspect(1, 1));
    });

    test('clamps an ultra-tall picture to the narrow legal ratio', () {
      // 1:10 is far narrower than Android allows (min 1:2.39) → the boundary.
      expect(pipAspectFor(const Size(100, 1000)), const PipAspect(100, 239));
    });

    test('clamps an ultra-wide picture to the wide legal ratio', () {
      expect(pipAspectFor(const Size(1000, 100)), const PipAspect(239, 100));
    });

    test('returns null for an unknown or empty size', () {
      expect(pipAspectFor(null), isNull);
      expect(pipAspectFor(const Size(0, 0)), isNull);
    });
  });

  group('PipBridgeImpl command channel (P13-04)', () {
    test(
      'enter / setAutoEnter / release invoke the matching methods',
      () async {
        final calls = <MethodCall>[];
        setHandler((call) async {
          calls.add(call);
          return null;
        });

        final impl = PipBridgeImpl();
        await impl.enter(aspectWidth: 16, aspectHeight: 9);
        await impl.setAutoEnter(true);
        await impl.release();

        expect(calls.map((c) => c.method), [
          'enter',
          'setAutoEnter',
          'release',
        ]);
        final enterArgs = calls.first.arguments as Map;
        expect(enterArgs['width'], 16);
        expect(enterArgs['height'], 9);
        expect((calls[1].arguments as Map)['enabled'], isTrue);
      },
    );

    test('isSupported returns the native result', () async {
      setHandler((call) async {
        if (call.method == 'isSupported') return true;
        return null;
      });

      final impl = PipBridgeImpl();
      addTearDown(impl.release);
      expect(await impl.isSupported(), isTrue);
    });

    test(
      'missing plugin degrades safely (isSupported false, commands no-op)',
      () async {
        // No mock handler → invokeMethod throws MissingPluginException, which the
        // implementation must swallow so unsupported hosts never crash (PLAY-013).
        final impl = PipBridgeImpl();
        expect(await impl.isSupported(), isFalse);
        await expectLater(
          impl.enter(aspectWidth: 1, aspectHeight: 1),
          completes,
        );
        await expectLater(impl.setAutoEnter(true), completes);
        await expectLater(impl.release(), completes);
      },
    );

    test('PlatformException from a command is swallowed', () async {
      setHandler((call) async {
        throw PlatformException(code: 'PIP_FAILED');
      });

      final impl = PipBridgeImpl();
      expect(await impl.isSupported(), isFalse);
      await expectLater(impl.enter(), completes);
      await expectLater(impl.setAutoEnter(false), completes);
      await impl.release();
    });
  });

  group('PipBridgeImpl mode delivery', () {
    test('an incoming onPipModeChanged call emits the boolean', () async {
      final impl = PipBridgeImpl();
      addTearDown(impl.release);

      final received = <bool>[];
      final sub = impl.modeChanges.listen(received.add);

      // Simulate the native side calling back into the Dart handler.
      const codec = StandardMethodCodec();
      final encoded = codec.encodeMethodCall(
        const MethodCall('onPipModeChanged', true),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, encoded, (ByteData? _) {});
      await Future<void>.delayed(Duration.zero);

      expect(received, [true]);

      final leave = codec.encodeMethodCall(
        const MethodCall('onPipModeChanged', false),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, leave, (ByteData? _) {});
      await Future<void>.delayed(Duration.zero);
      expect(received, [true, false]);

      await sub.cancel();
    });
  });
}
