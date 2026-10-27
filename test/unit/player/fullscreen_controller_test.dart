import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/fullscreen_controller.dart';

/// Fullscreen is a display state driven entirely through the platform chrome
/// channels, so these tests record what was pushed to `SystemChrome` instead of
/// measuring a layout (plan M5).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// The argument of the last `SystemChrome.*` call for [method]: a mode name
  /// for the system-UI call, a list of orientation names for the other.
  Object? lastArg(String method) {
    final matches = calls.where((call) => call.method == method);
    return matches.isEmpty ? null : matches.last.arguments;
  }

  /// The orientation names the app asked for most recently.
  List<String> orientations() =>
      ((lastArg('SystemChrome.setPreferredOrientations') as List?) ?? const [])
          .cast<String>();

  ProviderContainer containerFor() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('entering fullscreen is immersive and landscape', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    expect(container.read(fullscreenControllerProvider), isFalse);

    await controller.enter();

    expect(container.read(fullscreenControllerProvider), isTrue);
    expect(
      lastArg('SystemChrome.setEnabledSystemUIMode'),
      'SystemUiMode.immersiveSticky',
    );
    expect(orientations(), isNotEmpty);
    expect(
      orientations().every((value) => value.contains('landscape')),
      isTrue,
      reason: 'a fullscreen video gets the wide orientations',
    );
  });

  test('a vertical source stays portrait while immersive (VP5.5)', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    await controller.enter(allowLandscape: false);

    expect(container.read(fullscreenControllerProvider), isTrue);
    expect(
      lastArg('SystemChrome.setEnabledSystemUIMode'),
      'SystemUiMode.immersiveSticky',
      reason: 'still immersive, just not wide',
    );
    expect(
      orientations().every((value) => value.contains('portrait')),
      isTrue,
      reason: 'a portrait-first video gets the tall orientations',
    );
  });

  test('the landscape preference follows the most recent entry', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    await controller.enter(allowLandscape: false);
    await controller.exit();
    await controller.enter();

    expect(
      orientations().every((value) => value.contains('landscape')),
      isTrue,
      reason: 'a later landscape source re-enables the wide orientations',
    );
  });

  test('leaving fullscreen restores edge-to-edge portrait', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    await controller.enter();
    await controller.exit();

    expect(container.read(fullscreenControllerProvider), isFalse);
    expect(
      lastArg('SystemChrome.setEnabledSystemUIMode'),
      'SystemUiMode.edgeToEdge',
    );
    expect(
      orientations().every((value) => value.contains('portrait')),
      isTrue,
      reason: 'the rest of the app assumes portrait',
    );
  });

  test('toggle flips the mode both ways', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    await controller.toggle();
    expect(container.read(fullscreenControllerProvider), isTrue);

    await controller.toggle();
    expect(container.read(fullscreenControllerProvider), isFalse);
  });

  test('repeated calls for the same mode are cheap and idempotent', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    await controller.enter();
    final afterEnter = calls.length;
    await controller.enter();

    // Already fullscreen: no second platform round trip.
    expect(calls.length, afterEnter);

    await controller.exit();
    final afterExit = calls.length;
    await controller.exit();
    expect(calls.length, afterExit);
  });

  test(
    'restore is defensive: it drops the flag and puts the UI back',
    () async {
      final container = containerFor();
      final controller = container.read(fullscreenControllerProvider.notifier);

      await controller.enter();
      calls.clear();

      // The app was backgrounded mid-fullscreen, or the route is going away.
      await controller.restore();

      expect(container.read(fullscreenControllerProvider), isFalse);
      expect(
        lastArg('SystemChrome.setEnabledSystemUIMode'),
        'SystemUiMode.edgeToEdge',
      );
    },
  );

  test('disposing the provider restores the system UI', () async {
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);
    await controller.enter();
    calls.clear();

    container.dispose();
    // The onDispose hook fires synchronously; give the channel call a turn.
    await Future<void>.delayed(Duration.zero);

    expect(
      lastArg('SystemChrome.setEnabledSystemUIMode'),
      'SystemUiMode.edgeToEdge',
    );
  });

  test('a rejecting host does not break the mode', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => throw PlatformException(code: 'unavailable'),
        );
    final container = containerFor();
    final controller = container.read(fullscreenControllerProvider.notifier);

    // Display chrome is best-effort; playback must never be interrupted by a
    // device that refuses an orientation change.
    await controller.enter();
    expect(container.read(fullscreenControllerProvider), isTrue);

    await controller.exit();
    expect(container.read(fullscreenControllerProvider), isFalse);
  });
}
