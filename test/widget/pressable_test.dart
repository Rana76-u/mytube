import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/ui/motion.dart';
import 'package:mytube/core/ui/pressable.dart';

/// Records the platform haptic calls a press produces so the two haptic
/// strengths are observable without a device.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

double _scaleOf(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  group('PressableScale (DESIGN.md §4)', () {
    testWidgets('pressing scales the surface to 0.95 and releasing restores it '
        'with a selection tick', (tester) async {
      final haptics = _recordHaptics(tester);
      await tester.pumpWidget(
        _host(PressableScale(onTap: () {}, child: const Text('Like'))),
      );
      expect(_scaleOf(tester), 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Like')),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(_scaleOf(tester), AppMotion.pressedScale);
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), 1);
    });

    testWidgets('a cancelled press restores the surface without a tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(PressableScale(onTap: () => taps++, child: const Text('Save'))),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Save')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester), AppMotion.pressedScale);

      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), 1);
      expect(taps, 0);
    });

    testWidgets('the owning mode fires onTap and reports a light impact for a '
        'primary action', (tester) async {
      final haptics = _recordHaptics(tester);
      var taps = 0;
      await tester.pumpWidget(
        _host(
          PressableScale(
            onTap: () => taps++,
            haptic: PressHaptic.light,
            child: const Text('Play'),
          ),
        ),
      );

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('the passive mode leaves the tap to the child', (tester) async {
      // No onTap: a child that owns its own gesture (an InkWell, a ChoiceChip)
      // must still receive the tap and be the only thing that reacts.
      var childTaps = 0;
      await tester.pumpWidget(
        _host(
          PressableScale(
            child: TextButton(
              onPressed: () => childTaps++,
              child: const Text('Chip'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Chip'));
      await tester.pumpAndSettle();

      expect(childTaps, 1);
    });

    testWidgets('a disabled surface keeps its size and never vibrates', (
      tester,
    ) async {
      final haptics = _recordHaptics(tester);
      var taps = 0;
      await tester.pumpWidget(
        _host(
          PressableScale(
            enabled: false,
            onTap: () => taps++,
            child: const Text('Disabled'),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Disabled')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_scaleOf(tester), 1);
      expect(haptics, isEmpty);
      expect(taps, 0);
    });

    testWidgets('the reduced-motion preference drops the scale but keeps the '
        'press usable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          PressableScale(onTap: () => taps++, child: const Text('Quiet')),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Quiet')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('a long press reaches the supplied handler', (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(
        _host(
          PressableScale(
            onTap: () {},
            onLongPress: () => longPresses++,
            child: const Text('Hold'),
          ),
        ),
      );

      await tester.longPress(find.text('Hold'));
      await tester.pumpAndSettle();

      expect(longPresses, 1);
    });
  });
}
