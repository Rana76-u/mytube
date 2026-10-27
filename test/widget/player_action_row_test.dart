import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_controller.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/player/player_action_row.dart';
import '../support/fake_download.dart';

VideoItemSummary _item({ProviderType? provider}) => VideoItemSummary(
  id: VideoItemId('vid-1'),
  title: 'Trip clip',
  durationMs: 120000,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: DateTime.now().millisecondsSinceEpoch,
  primaryProvider: provider,
);

/// The bundle the row consumes, with every callback counted so a test can prove
/// the pill is wired to the shared action rather than to a no-op.
VideoItemActions _counts({
  void Function()? onToggleFavourite,
  void Function()? onSaveToCollection,
  void Function()? onShare,
  void Function()? onManageTags,
  void Function()? onManageSources,
}) => VideoItemActions(
  onToggleFavourite: onToggleFavourite,
  onSaveToCollection: onSaveToCollection,
  onShare: onShare,
  onManageTags: onManageTags,
  onManageSources: onManageSources,
);

Future<void> _pump(
  WidgetTester tester, {
  VideoItemSummary? item,
  VideoItemActions? actions,
  bool loop = false,
  VoidCallback? onToggleLoop,
}) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerActionRow(
            item: item ?? _item(provider: ProviderType.localMediaStore),
            actions: actions ?? _counts(),
            loop: loop,
            onToggleLoop: onToggleLoop,
          ),
        ),
      ),
    ),
  ),
);

/// Pumps [PlayerActionRow] with the download controller overridden to a ready
/// idle one, so a remote-item row mounts the real [DownloadPill] without the
/// persistence/transport graph.
Future<void> _pumpRemoteWithDownload(
  WidgetTester tester,
  VideoItemSummary item,
) async {
  final controller = DownloadController(
    videoItemId: item.id,
    manager: FakeDownloadManager(),
    downloadRepository: FakeDownloadRepository(),
    videoRepository: FakeVideoRepository([loc()]),
    onlineProbe: () async => true,
  );
  await controller.bootstrap();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadControllerProvider.overrideWith((ref, arg) => controller),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerActionRow(item: item, actions: _counts()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('downloadOfferedFor (VP3.4 / VP6.4)', () {
    test('a remote copy — direct URL or cloud — can be downloaded', () {
      for (final provider in [
        ProviderType.directUrl,
        ProviderType.oneDrive,
        ProviderType.googleDrive,
        ProviderType.cloudflareR2,
      ]) {
        expect(downloadOfferedFor(_item(provider: provider)), isTrue);
      }
    });

    test('an on-device file or an unknown source offers nothing', () {
      for (final provider in [
        ProviderType.localMediaStore,
        ProviderType.selectedFolder,
        null,
      ]) {
        expect(downloadOfferedFor(_item(provider: provider)), isFalse);
      }
    });
  });

  group('PlayerActionRow', () {
    testWidgets('a local item never shows the Download pill', (tester) async {
      await _pump(tester);

      expect(
        find.byKey(const ValueKey('player_action_download')),
        findsNothing,
      );
    });

    testWidgets('a remote item mounts a working Download pill', (tester) async {
      await _pumpRemoteWithDownload(
        tester,
        _item(provider: ProviderType.googleDrive),
      );

      final chip = tester.widget<ActionChip>(
        find.byKey(const ValueKey('player_action_download')),
      );
      // VP6.4: the pill is now actionable, not a disabled placeholder.
      expect(chip.onPressed, isNotNull);
    });

    testWidgets('every pill routes to the shared action bundle', (
      tester,
    ) async {
      final calls = <String>[];
      await _pump(
        tester,
        actions: _counts(
          onToggleFavourite: () => calls.add('like'),
          onSaveToCollection: () => calls.add('save'),
          onShare: () => calls.add('share'),
          onManageTags: () => calls.add('tags'),
          onManageSources: () => calls.add('sources'),
        ),
      );

      for (final key in const [
        'player_action_like',
        'player_action_save',
        'player_action_share',
        'player_action_tags',
        'player_action_sources',
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        // The Like pill pops for 220 ms; settle so the next tap is not swallowed
        // by an in-flight animation.
        await tester.pumpAndSettle();
      }

      expect(calls, ['like', 'save', 'share', 'tags', 'sources']);
    });

    testWidgets('Like reads as selected when the item is a favourite', (
      tester,
    ) async {
      await _pump(
        tester,
        item: VideoItemSummary(
          id: VideoItemId('vid-1'),
          title: 'Trip clip',
          isFavourite: true,
          watchProgressMs: 0,
          createdAt: 0,
          primaryProvider: ProviderType.localMediaStore,
        ),
        actions: _counts(onToggleFavourite: () {}),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      // A selected pill is filled, not just re-glyphed (design §4).
      final chip = tester.widget<ActionChip>(
        find.byKey(const ValueKey('player_action_like')),
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey('player_action_like'))),
      ).colorScheme;
      expect(chip.backgroundColor, scheme.primaryContainer);
      expect((chip.side as BorderSide).color, scheme.primary);
    });

    testWidgets('the Loop pill reflects the session state and flips on tap', (
      tester,
    ) async {
      var loop = false;
      await _pump(tester, loop: loop, onToggleLoop: () => loop = !loop);

      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byIcon(Icons.repeat_on), findsNothing);

      await tester.tap(find.byKey(const ValueKey('player_action_loop')));
      await tester.pumpAndSettle();
      expect(loop, isTrue);

      await _pump(tester, loop: true, onToggleLoop: () {});
      expect(find.byIcon(Icons.repeat_on), findsOneWidget);
    });

    testWidgets('a null callback leaves Loop disabled, not dead-hidden', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byKey(const ValueKey('player_action_loop')), findsOneWidget);
      expect(
        tester
            .widget<ActionChip>(
              find.byKey(const ValueKey('player_action_loop')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the strip scrolls under the right-edge fade', (tester) async {
      await _pump(tester);

      final toolbar = find.byKey(const ValueKey('player_action_toolbar'));
      expect(
        tester.widget<SingleChildScrollView>(toolbar).scrollDirection,
        Axis.horizontal,
      );

      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: toolbar, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.pixels, 0);
      // The pills are laid out in a Row inside the view, so a drag has somewhere
      // to go even in the 800-logical-pixel test window.
      await tester.drag(toolbar, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));

      expect(find.byKey(const ValueKey('player_action_fade')), findsOneWidget);
    });

    testWidgets('the row keeps its 48 dp tap height', (tester) async {
      await _pump(tester);

      expect(
        tester
            .getSize(find.byKey(const ValueKey('player_action_toolbar')))
            .height,
        greaterThanOrEqualTo(AppSizes.minTapTarget - 2 * AppSpacing.xs),
      );
    });
  });
}
