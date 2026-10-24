import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/platform/audio_focus_bridge.dart';
import 'package:mytube/platform/audio_focus_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const commands = MethodChannel('com.example.mytube/audio_focus');

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commands, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(commands, null);
  });

  group('audioFocusChangeFromEvent (pure mapping)', () {
    test('maps every native string tag', () {
      expect(audioFocusChangeFromEvent('gained'), AudioFocusChange.gained);
      expect(
        audioFocusChangeFromEvent('lostTransientCanDuck'),
        AudioFocusChange.lostTransientCanDuck,
      );
      expect(
        audioFocusChangeFromEvent('lostTransient'),
        AudioFocusChange.lostTransient,
      );
      expect(
        audioFocusChangeFromEvent('lostEphemeral'),
        AudioFocusChange.lostEphemeral,
      );
      expect(audioFocusChangeFromEvent('lost'), AudioFocusChange.lost);
    });

    test('mirrors the AudioManager integer constants', () {
      expect(audioFocusChangeFromEvent(1), AudioFocusChange.gained);
      expect(
        audioFocusChangeFromEvent(-2),
        AudioFocusChange.lostTransientCanDuck,
      );
      expect(audioFocusChangeFromEvent(-1), AudioFocusChange.lostTransient);
      expect(audioFocusChangeFromEvent(-3), AudioFocusChange.lostEphemeral);
      expect(audioFocusChangeFromEvent(0), AudioFocusChange.lost);
    });

    test('unknown / null payloads map to null', () {
      expect(audioFocusChangeFromEvent('nonsense'), isNull);
      expect(audioFocusChangeFromEvent(99), isNull);
      expect(audioFocusChangeFromEvent(null), isNull);
      expect(audioFocusChangeFromEvent(3.5), isNull);
    });
  });

  group('AudioFocusBridgeImpl command channel (P13-01)', () {
    test(
      'requestFocus / abandonFocus / release invoke the matching methods',
      () async {
        final calls = <String>[];
        setHandler((call) async {
          calls.add(call.method);
          return null;
        });

        final impl = AudioFocusBridgeImpl();
        await impl.requestFocus();
        await impl.abandonFocus();
        await impl.release();

        expect(calls, ['requestFocus', 'abandonFocus', 'release']);
      },
    );

    test(
      'PlatformException from a command is swallowed (never throws)',
      () async {
        setHandler((call) async {
          throw PlatformException(code: 'AUDIOFOCUS_DENIED');
        });

        final impl = AudioFocusBridgeImpl();
        await expectLater(impl.requestFocus(), completes);
        await expectLater(impl.abandonFocus(), completes);
      },
    );

    test('missing plugin degrades to a no-op (never throws)', () async {
      // No mock handler set → invokeMethod throws MissingPluginException, which
      // the implementation must catch so unsupported platforms don't crash.
      final impl = AudioFocusBridgeImpl();
      await expectLater(impl.requestFocus(), completes);
      await expectLater(impl.abandonFocus(), completes);
      await expectLater(impl.release(), completes);
    });
  });

  group('AudioFocusBridgeImpl event stream safety', () {
    test(
      'changes stays silent and never errors when no host is present',
      () async {
        final impl = AudioFocusBridgeImpl();
        final mapped = <AudioFocusChange>[];
        Object? seenError;
        // With no EventChannel host, receiveBroadcastStream surfaces a
        // MissingPluginException that the getter swallows via handleError: the
        // listener sees neither events nor an error (PLAY-013).
        final sub = impl.changes.listen(
          mapped.add,
          onError: (Object e) => seenError = e,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(mapped, isEmpty);
        expect(seenError, isNull);
        await sub.cancel();
      },
    );
  });
}
