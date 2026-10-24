import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

VideoItemSummary _item({bool favourite = false, int? durationMs = 120000}) =>
    VideoItemSummary(
      id: VideoItemId('test-id'),
      title: 'Test Video',
      durationMs: durationMs,
      isFavourite: favourite,
      watchProgressMs: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

/// Pumps [card] inside a [ProviderScope] whose thumbnail future resolves to
/// `null`, so [VideoThumbnail] deterministically renders its placeholder
/// without touching the database or the native bridge.
Future<void> _pump(WidgetTester tester, Widget card) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      videoThumbnailProvider(
        'test-id',
      ).overrideWith((ref) => Future<Uint8List?>.value(null)),
    ],
    child: MaterialApp(home: Scaffold(body: card)),
  ),
);

void main() {
  group('VideoItemCard (P5-01)', () {
    testWidgets('displays video title', (tester) async {
      await _pump(tester, VideoItemCard(item: _item(), onTap: () {}));

      expect(find.text('Test Video'), findsOneWidget);
    });

    testWidgets('displays duration in m:ss format', (tester) async {
      await _pump(
        tester,
        VideoItemCard(item: _item(durationMs: 125000), onTap: () {}),
      ); // 2:05

      expect(find.text('2:05'), findsOneWidget);
    });

    testWidgets('displays duration in h:mm:ss format for long videos', (
      tester,
    ) async {
      await _pump(
        tester,
        VideoItemCard(item: _item(durationMs: 3785000), onTap: () {}),
      ); // 1:03:05

      expect(find.text('1:03:05'), findsOneWidget);
    });

    testWidgets('does not display duration when null', (tester) async {
      await _pump(
        tester,
        VideoItemCard(item: _item(durationMs: null), onTap: () {}),
      );

      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('shows favorite icon when isFavourite is true', (tester) async {
      await _pump(
        tester,
        VideoItemCard(item: _item(favourite: true), onTap: () {}),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('does not show favorite icon when isFavourite is false', (
      tester,
    ) async {
      await _pump(tester, VideoItemCard(item: _item(), onTap: () {}));

      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await _pump(
        tester,
        VideoItemCard(item: _item(), onTap: () => tapped = true),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });

    // ── P7 thumbnails ───────────────────────────────────────────────────────

    testWidgets('renders a VideoThumbnail that falls back to the placeholder '
        'when no preview is available (P7-03)', (tester) async {
      await _pump(tester, VideoItemCard(item: _item(), onTap: () {}));
      await tester.pumpAndSettle();

      expect(find.byType(VideoThumbnail), findsOneWidget);
      expect(
        find.byKey(const ValueKey('thumbnail_placeholder')),
        findsOneWidget,
      );
    });

    testWidgets('shows the manage-sources entry point only when a handler is '
        'supplied (P7-06)', (tester) async {
      // No handler → no overflow menu, so no sources entry.
      await _pump(tester, VideoItemCard(item: _item(), onTap: () {}));
      expect(find.byKey(const ValueKey('card_menu_test-id')), findsNothing);

      // Handler supplied → the ⋮ menu exposes a tappable sources entry.
      var opened = false;
      await _pump(
        tester,
        VideoItemCard(
          item: _item(),
          onTap: () {},
          onManageSources: () => opened = true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('card_menu_test-id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sources_test-id')));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('labels the source and shows a watched/added date (UI-1)', (
      tester,
    ) async {
      await _pump(
        tester,
        VideoItemCard(
          item: VideoItemSummary(
            id: VideoItemId('test-id'),
            title: 'Test Video',
            isFavourite: false,
            watchProgressMs: 0,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            primaryProvider: ProviderType.oneDrive,
          ),
          onTap: () {},
        ),
      );

      final meta = find.byKey(const ValueKey('meta_test-id'));
      expect(meta, findsOneWidget);
      expect(
        tester.widget<Text>(meta).data,
        allOf(contains('OneDrive'), contains('Added')),
      );
    });

    testWidgets('overlays a progress bar for a partially-watched item (UI-1)', (
      tester,
    ) async {
      await _pump(
        tester,
        VideoItemCard(
          item: VideoItemSummary(
            id: VideoItemId('test-id'),
            title: 'Test Video',
            durationMs: 100000,
            isFavourite: false,
            watchProgressMs: 40000,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          onTap: () {},
        ),
      );

      expect(find.byKey(const ValueKey('progress_test-id')), findsOneWidget);
    });
  });
}
