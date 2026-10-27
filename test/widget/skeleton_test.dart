import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/ui/skeleton.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.dark,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('SkeletonBox', () {
    testWidgets('paints a surface-toned block with the requested geometry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Center(child: SkeletonBox(width: 120, height: 68))),
      );

      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonBox),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      final scheme = AppTheme.dark.colorScheme;

      expect(decoration.color, scheme.surfaceContainer);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(4),
        reason: 'the default radius is the duration-badge step',
      );
      expect(tester.getSize(find.byType(SkeletonBox)), const Size(120, 68));
    });

    testWidgets('a circular skeleton has no corner radius', (tester) async {
      await tester.pumpWidget(
        _host(const Center(child: SkeletonCircle(size: 32))),
      );

      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonCircle),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
      expect(tester.getSize(find.byType(SkeletonCircle)), const Size(32, 32));
    });
  });

  group('Shimmer (ADR-015 test policy)', () {
    testWidgets('sweeps its child and then settles so pumpAndSettle finishes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: Shimmer(child: SkeletonBox(width: 200, height: 90)),
          ),
        ),
      );

      // The sweep is a shader mask over the placeholder, not a replacement.
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(SkeletonBox), findsOneWidget);

      // A bounded number of sweeps: once the budget is spent no frame is
      // scheduled, so this must terminate instead of timing out.
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets(
      'a fixed-duration pump shows the placeholder before it settles',
      (tester) async {
        // The documented policy for tests that touch a skeleton: pump fixed
        // durations rather than pumpAndSettle when the loading frame matters.
        await tester.pumpWidget(
          _host(
            const Center(
              child: Shimmer(child: SkeletonBox(width: 8, height: 8)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SkeletonBox), findsOneWidget);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the reduced-motion preference renders the child undecorated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          const Center(
            child: Shimmer(child: SkeletonBox(width: 40, height: 8)),
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(SkeletonBox), findsOneWidget);
    });

    testWidgets('disposes its ticker cleanly when removed mid-sweep', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: Shimmer(child: SkeletonBox(width: 40, height: 8)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Replacing the skeleton mid-animation is what a list does the moment its
      // data lands; it must not leak a ticker or a pending frame.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(find.byType(Shimmer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
