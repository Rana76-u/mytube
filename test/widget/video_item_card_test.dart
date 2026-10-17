import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart';

void main() {
  group('VideoItemCard (P5-01)', () {
    testWidgets('displays video title', (tester) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 120000,
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.text('Test Video'), findsOneWidget);
    });

    testWidgets('displays duration in m:ss format', (tester) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 125000, // 2:05
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.text('2:05'), findsOneWidget);
    });

    testWidgets('displays duration in h:mm:ss format for long videos', (
      tester,
    ) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 3785000, // 1:03:05
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.text('1:03:05'), findsOneWidget);
    });

    testWidgets('does not display duration when null', (tester) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: null,
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('shows favorite icon when isFavourite is true', (tester) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 120000,
        isFavourite: true,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('does not show favorite icon when isFavourite is false', (
      tester,
    ) async {
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 120000,
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      final item = VideoItemSummary(
        id: VideoItemId('test-id'),
        title: 'Test Video',
        durationMs: 120000,
        isFavourite: false,
        watchProgressMs: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoItemCard(item: item, onTap: () => tapped = true),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });
  });
}
