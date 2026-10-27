import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/item_removal_service.dart';
import 'package:mytube/domain/services/item_removal_service_provider.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/library/video_item_card.dart';

/// ADR-017 from the user's side: the card's `⋮` gains a destructive entry that
/// states exactly what will be destroyed, asks once, and then reports what
/// actually happened — including when a file could not be deleted.

const _videoId = 'vid-1';

VideoItemSummary _item({
  ProviderType? primaryProvider = ProviderType.localMediaStore,
}) => VideoItemSummary(
  id: VideoItemId(_videoId),
  title: 'Test Video',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: DateTime.now().millisecondsSinceEpoch,
  primaryProvider: primaryProvider,
);

SourceLocation _location(ProviderType providerType, String sourceUri) =>
    SourceLocation(
      id: 'loc-$sourceUri',
      videoItemId: _videoId,
      providerType: providerType,
      sourceUri: sourceUri,
      availability: AvailabilityState.available,
    );

ItemRemovalPlan _localPlan({int files = 1}) => ItemRemovalPlan(
  item: _item(),
  scope: ItemRemovalScope.deleteOriginals,
  originalsToDelete: [
    for (var i = 0; i < files; i++)
      _location(ProviderType.localMediaStore, 'content://media/media/$i'),
  ],
);

ItemRemovalPlan _directUrlPlan() => ItemRemovalPlan(
  item: _item(primaryProvider: ProviderType.directUrl),
  scope: ItemRemovalScope.removeFromLibrary,
  recordOnly: [_location(ProviderType.directUrl, 'https://example.com/a.mp4')],
);

/// A cloud copy no deleter can destroy yet: shown as record-only *plus* an
/// explicit note, so the dialog never implies a OneDrive delete happened.
ItemRemovalPlan _cloudPlan() => ItemRemovalPlan(
  item: _item(primaryProvider: ProviderType.oneDrive),
  scope: ItemRemovalScope.removeFromLibrary,
  recordOnly: [_location(ProviderType.oneDrive, 'onedrive:item/ABC')],
  unsupportedProviders: const {ProviderType.oneDrive},
);

class _FakeRemovalService implements ItemRemovalService {
  _FakeRemovalService({
    required this.planValue,
    this.planError,
    this.outcome,
    this.removeError,
  });

  final ItemRemovalPlan planValue;
  final AppError? planError;
  final ItemRemovalOutcome? outcome;
  final AppError? removeError;

  int planCalls = 0;
  int removeCalls = 0;

  @override
  Future<Result<ItemRemovalPlan>> plan(VideoItemSummary item) async {
    planCalls++;
    if (planError case final error?) return Result.err(error);
    return Result.ok(planValue);
  }

  @override
  Future<Result<ItemRemovalOutcome>> remove(ItemRemovalPlan plan) async {
    removeCalls++;
    if (removeError case final error?) return Result.err(error);
    return Result.ok(outcome ?? ItemRemovalOutcome(scope: plan.scope));
  }
}

/// Renders the card the way every production surface does, through
/// [videoItemActionsFor], so the test exercises the real menu wiring.
class _CardHarness extends ConsumerWidget {
  const _CardHarness({required this.item, this.bundle});

  final VideoItemSummary item;

  /// Overrides the standard bundle (used to prove the entry is opt-in).
  final VideoItemActions? bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: VideoItemCard(
      item: item,
      onTap: () {},
      actions: bundle ?? videoItemActionsFor(context, ref, item),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  VideoItemSummary item, {
  required ItemRemovalService service,
  VideoItemActions? bundle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        itemRemovalServiceProvider.overrideWithValue(service),
        videoThumbnailProvider(
          _videoId,
        ).overrideWith((ref) => Future<Uint8List?>.value(null)),
      ],
      child: MaterialApp(
        home: _CardHarness(item: item, bundle: bundle),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('card_menu_$_videoId')));
  await tester.pumpAndSettle();
}

/// Taps the destructive entry by its label — the row spans the whole menu item,
/// so its centre is a worse tap target than the text the user actually reads.
Future<void> _tapDelete(WidgetTester tester, {String label = 'Delete'}) async {
  await _openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('item_removal_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('VideoItemCard delete entry (ADR-017)', () {
    testWidgets('offers a delete entry for a local item', (tester) async {
      await _pump(
        tester,
        _item(),
        service: _FakeRemovalService(planValue: _localPlan()),
      );
      await _openMenu(tester);

      expect(find.byKey(const ValueKey('delete_$_videoId')), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('labels the entry "Remove from library" for a direct URL', (
      tester,
    ) async {
      await _pump(
        tester,
        _item(primaryProvider: ProviderType.directUrl),
        service: _FakeRemovalService(planValue: _directUrlPlan()),
      );
      await _openMenu(tester);

      // A link has no file of its own, so the entry never promises a delete.
      expect(find.text('Remove from library'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('shows no delete entry when the bundle omits it', (
      tester,
    ) async {
      await _pump(
        tester,
        _item(),
        service: _FakeRemovalService(planValue: _localPlan()),
        bundle: VideoItemActions(onShare: () {}),
      );
      await _openMenu(tester);

      // No dead button: the entry exists only where the removal flow is wired.
      expect(find.byKey(const ValueKey('delete_$_videoId')), findsNothing);
      expect(find.byKey(const ValueKey('share_$_videoId')), findsOneWidget);
    });

    testWidgets('states what will be deleted before asking', (tester) async {
      final service = _FakeRemovalService(planValue: _localPlan(files: 2));
      await _pump(tester, _item(), service: service);

      await _tapDelete(tester);

      expect(find.byKey(const ValueKey('item_removal_dialog')), findsOneWidget);
      expect(find.text('Delete video?'), findsOneWidget);
      expect(
        find.textContaining(
          'This permanently deletes 2 files from this device. '
          'It cannot be undone.',
        ),
        findsOneWidget,
      );
      // Nothing happens until the user confirms.
      expect(service.removeCalls, 0);
    });

    testWidgets('cancelling keeps the item', (tester) async {
      final service = _FakeRemovalService(planValue: _localPlan());
      await _pump(tester, _item(), service: service);
      await _tapDelete(tester);

      await tester.tap(find.byKey(const ValueKey('item_removal_cancel')));
      await tester.pumpAndSettle();

      expect(service.removeCalls, 0);
      expect(find.byKey(const ValueKey('item_removal_dialog')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('confirming deletes and reports how many files went', (
      tester,
    ) async {
      final service = _FakeRemovalService(
        planValue: _localPlan(files: 2),
        outcome: const ItemRemovalOutcome(
          scope: ItemRemovalScope.deleteOriginals,
          deletedOriginals: 2,
        ),
      );
      await _pump(tester, _item(), service: service);
      await _tapDelete(tester);

      await _confirm(tester);

      expect(service.removeCalls, 1);
      expect(find.text('Video and 2 files deleted.'), findsOneWidget);
    });

    testWidgets('unlinking a direct URL says nothing was deleted', (
      tester,
    ) async {
      final service = _FakeRemovalService(
        planValue: _directUrlPlan(),
        outcome: const ItemRemovalOutcome(
          scope: ItemRemovalScope.removeFromLibrary,
        ),
      );
      await _pump(
        tester,
        _item(primaryProvider: ProviderType.directUrl),
        service: service,
      );
      await _tapDelete(tester, label: 'Remove from library');

      expect(find.text('Remove from library?'), findsOneWidget);
      expect(
        find.textContaining('Nothing is deleted from its source.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('a link has no file of its own'),
        findsOneWidget,
      );

      await _confirm(tester);

      expect(find.text('Removed from library.'), findsOneWidget);
    });

    testWidgets('says when a cloud copy can only be unlinked', (tester) async {
      await _pump(
        tester,
        _item(primaryProvider: ProviderType.oneDrive),
        service: _FakeRemovalService(planValue: _cloudPlan()),
      );
      await _tapDelete(tester);

      expect(
        find.textContaining(
          'OneDrive copies are only removed from your library; '
          'deleting there is not supported yet.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reports a partial delete honestly', (tester) async {
      final service = _FakeRemovalService(
        planValue: _localPlan(files: 2),
        outcome: const ItemRemovalOutcome(
          scope: ItemRemovalScope.deleteOriginals,
          deletedOriginals: 1,
          undeletedOriginals: 1,
        ),
      );
      await _pump(tester, _item(), service: service);
      await _tapDelete(tester);

      await _confirm(tester);

      expect(
        find.text("Removed from library. 1 of 2 files couldn't be deleted."),
        findsOneWidget,
      );
    });

    testWidgets('warns when the file could not be deleted at all', (
      tester,
    ) async {
      final service = _FakeRemovalService(
        planValue: _localPlan(),
        outcome: const ItemRemovalOutcome(
          scope: ItemRemovalScope.deleteOriginals,
          undeletedOriginals: 1,
        ),
      );
      await _pump(tester, _item(), service: service);
      await _tapDelete(tester);

      await _confirm(tester);

      expect(
        find.text(
          "Removed from library. The file couldn't be deleted, so it may "
          'still be on your device.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reports a removal failure without claiming success', (
      tester,
    ) async {
      final service = _FakeRemovalService(
        planValue: _localPlan(),
        removeError: const UnexpectedError(
          userMessage: 'Could not remove this video. Try again.',
          diagnosticMessage: 'db locked',
        ),
      );
      await _pump(tester, _item(), service: service);
      await _tapDelete(tester);

      await _confirm(tester);

      expect(
        find.text('Could not remove this video. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Video and 1 file deleted.'), findsNothing);
    });

    testWidgets('reports a plan failure without opening the dialog', (
      tester,
    ) async {
      final service = _FakeRemovalService(
        planValue: _localPlan(),
        planError: const UnexpectedError(
          userMessage: 'Your library is unavailable. Try again.',
          diagnosticMessage: 'db unavailable',
        ),
      );
      await _pump(tester, _item(), service: service);

      await _tapDelete(tester);

      expect(find.byKey(const ValueKey('item_removal_dialog')), findsNothing);
      expect(
        find.text('Your library is unavailable. Try again.'),
        findsOneWidget,
      );
      expect(service.removeCalls, 0);
    });
  });
}
