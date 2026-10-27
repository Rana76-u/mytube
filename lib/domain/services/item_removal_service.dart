import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// What removing one library item does to the originals behind it (ADR-017).
enum ItemRemovalScope {
  /// At least one original can be destroyed. The item's remaining locations —
  /// direct URLs, and providers with no deleter yet — are only unlinked.
  deleteOriginals,

  /// Nothing outside the app is touched: the record alone goes away. This is
  /// the direct-URL case (there is no file to delete) and also what an item
  /// whose last local copy disappeared resolves to.
  removeFromLibrary,
}

/// The decided action for one item.
///
/// The plan is computed *before* the user is asked to confirm, so the dialog
/// can state exactly what will be destroyed instead of a generic warning, and
/// so the same decision can be asserted in tests without a widget tree.
class ItemRemovalPlan {
  const ItemRemovalPlan({
    required this.item,
    required this.scope,
    this.originalsToDelete = const <SourceLocation>[],
    this.recordOnly = const <SourceLocation>[],
    this.unsupportedProviders = const <ProviderType>{},
  });

  /// The item being removed.
  final VideoItemSummary item;

  /// Whether confirming destroys anything outside the app's database.
  final ItemRemovalScope scope;

  /// Source locations whose original file/object will be deleted, primary
  /// first — the same order [VideoRepository.getSourceLocationsForVideo]
  /// returns. Always empty for [ItemRemovalScope.removeFromLibrary].
  final List<SourceLocation> originalsToDelete;

  /// Source locations that are only unlinked from the app: direct URLs (the
  /// link *is* the entry), and locations already known to be gone.
  final List<SourceLocation> recordOnly;

  /// Providers present in [recordOnly] that cannot be deleted from yet.
  ///
  /// Cloud providers arrive after local media and direct URLs (AGENTS.md), so
  /// their originals must stay untouched and unreported rather than silently
  /// claimed as deleted.
  final Set<ProviderType> unsupportedProviders;

  /// How many originals this plan permanently deletes.
  int get originalCount => originalsToDelete.length;

  /// True when confirming destroys data the app does not own.
  bool get isDestructive => scope == ItemRemovalScope.deleteOriginals;

  /// The providers whose originals are deleted, in enum order so two plans for
  /// the same item always describe themselves identically.
  Set<ProviderType> get deletingProviders => {
    for (final type in ProviderType.values)
      if (originalsToDelete.any((location) => location.providerType == type))
        type,
  };
}

/// What actually happened, for the confirmation message.
class ItemRemovalOutcome {
  const ItemRemovalOutcome({
    required this.scope,
    this.deletedOriginals = 0,
    this.undeletedOriginals = 0,
    this.recordRemoved = true,
  });

  /// The scope the executed plan declared.
  final ItemRemovalScope scope;

  /// Originals confirmed deleted by their provider.
  final int deletedOriginals;

  /// Originals the provider refused or could not confirm.
  final int undeletedOriginals;

  /// Whether the library record is gone. [ItemRemovalService.remove] only
  /// returns an outcome after a successful delete, so this is false solely for
  /// callers that construct an outcome themselves.
  final bool recordRemoved;

  /// Some originals went and some did not.
  bool get isPartial => deletedOriginals > 0 && undeletedOriginals > 0;

  /// Nothing was destroyed, so the record removal is all the user got.
  bool get nothingDeleted => deletedOriginals == 0 && undeletedOriginals > 0;
}

/// Deletes originals for one family of providers.
///
/// Declared here rather than on `VideoSourceAdapter` because deletion is not a
/// capability every adapter needs: only providers that can destroy data
/// register one, so the set of destructive paths is explicit and testable
/// (ADR-017). Local files are the only family today; cloud adapters add their
/// own deleter as they land, without touching the removal flow.
abstract interface class ItemOriginalDeleter {
  /// The provider types whose originals this deleter can destroy.
  Set<ProviderType> get providerTypes;

  /// Deletes the originals behind [sourceIds].
  ///
  /// Implementations must account for every id exactly once across the
  /// report's two lists — never silently drop one — because the UI tells the
  /// user how many files were actually deleted.
  Future<Result<SourceDeletionReport>> deleteOriginals(List<String> sourceIds);
}

/// Decides and performs the removal of one library item (ADR-017).
///
/// The two steps are separate on purpose: [plan] is a pure read used to build
/// the confirmation dialog, and [remove] is the destructive step that only runs
/// after the user confirmed.
abstract interface class ItemRemovalService {
  /// Classifies the item's locations into "delete the original" and
  /// "unlink only".
  Future<Result<ItemRemovalPlan>> plan(VideoItemSummary item);

  /// Deletes the plan's originals, then removes the library record.
  ///
  /// Originals are deleted first: a database failure after that leaves the item
  /// listed with a missing file (which the next scan deindexes), while deleting
  /// the record first could orphan a file with nothing left in the app to
  /// point at it. An [Err] means the record is still in the library.
  Future<Result<ItemRemovalOutcome>> remove(ItemRemovalPlan plan);
}

/// The production [ItemRemovalService] (ADR-017).
///
/// Uses the injected [ItemOriginalDeleter]s — never the native bridges
/// directly — so the decision "can this provider's original be deleted" has a
/// single, listed answer and cloud providers stay untouched until one registers
/// a deleter.
class VideoItemRemovalService implements ItemRemovalService {
  const VideoItemRemovalService({
    required this.repository,
    required this.deleters,
  });

  final VideoRepository repository;
  final List<ItemOriginalDeleter> deleters;

  @override
  Future<Result<ItemRemovalPlan>> plan(VideoItemSummary item) async {
    final result = await repository.getSourceLocationsForVideo(item.id);
    final List<SourceLocation> locations;
    switch (result) {
      case Ok(:final value):
        locations = value;
      case Err(:final error):
        return Err(error);
    }

    final originals = <SourceLocation>[];
    final recordOnly = <SourceLocation>[];
    final unsupported = <ProviderType>{};

    for (final location in locations) {
      // A direct URL has no file of its own: unlinking the row *is* the removal.
      if (location.providerType == ProviderType.directUrl) {
        recordOnly.add(location);
        continue;
      }
      // Already gone (a previous scan flagged it): there is nothing to delete,
      // and treating it as a failure would report a phantom problem. It is
      // still unlinked, so it belongs with the record-only locations.
      if (location.availability == AvailabilityState.missing) {
        recordOnly.add(location);
        continue;
      }
      if (_deleterFor(location.providerType) == null) {
        recordOnly.add(location);
        unsupported.add(location.providerType);
        continue;
      }
      originals.add(location);
    }

    return Result.ok(
      ItemRemovalPlan(
        item: item,
        scope: originals.isEmpty
            ? ItemRemovalScope.removeFromLibrary
            : ItemRemovalScope.deleteOriginals,
        originalsToDelete: originals,
        recordOnly: recordOnly,
        unsupportedProviders: unsupported,
      ),
    );
  }

  @override
  Future<Result<ItemRemovalOutcome>> remove(ItemRemovalPlan plan) async {
    // Group ids per deleter so one provider pays for one batch call — a
    // MediaStore batch is a single system confirmation dialog, not one per file.
    final batches = <ItemOriginalDeleter, List<String>>{};
    var undeleted = 0;
    for (final location in plan.originalsToDelete) {
      final deleter = _deleterFor(location.providerType);
      if (deleter == null) {
        // The plan said this location was deletable; if the deleter set changed
        // since, report it as kept rather than pretending it went away.
        undeleted++;
        continue;
      }
      batches.putIfAbsent(deleter, () => <String>[]).add(location.sourceUri);
    }

    var deleted = 0;
    for (final entry in batches.entries) {
      final result = await entry.key.deleteOriginals(entry.value);
      switch (result) {
        case Ok(:final value):
          deleted += value.deleted.length;
          undeleted += value.failed.length;
          // Defensive: a deleter that under-reports must not make the user
          // believe a file was deleted when the app cannot confirm it.
          final unreported = entry.value.length - value.total;
          if (unreported > 0) undeleted += unreported;
        case Err():
          undeleted += entry.value.length;
      }
    }

    final removal = await repository.deleteItem(plan.item.id);
    if (removal case Err(:final error)) return Result.err(error);

    return Result.ok(
      ItemRemovalOutcome(
        scope: plan.scope,
        deletedOriginals: deleted,
        undeletedOriginals: undeleted,
      ),
    );
  }

  /// The deleter registered for [type], or null when no provider can destroy
  /// that kind of original yet.
  ItemOriginalDeleter? _deleterFor(ProviderType type) {
    for (final deleter in deleters) {
      if (deleter.providerTypes.contains(type)) return deleter;
    }
    return null;
  }
}
