/// The per-id result of deleting originals on one provider (ADR-017).
///
/// Deletion is not all-or-nothing: the OS confirmation can be dismissed, one
/// file in a batch can already be gone, and a SAF folder grant can lack write
/// access. Reporting ids rather than a boolean keeps the UI honest — it can say
/// exactly how many files went away and how many did not.
class SourceDeletionReport {
  const SourceDeletionReport({
    this.deleted = const <String>[],
    this.failed = const <String>[],
  });

  /// Source ids whose original was removed.
  final List<String> deleted;

  /// Source ids whose original still exists (or whose deletion could not be
  /// verified), with the reason left to the caller's message.
  final List<String> failed;

  /// Total ids this report accounts for.
  int get total => deleted.length + failed.length;

  /// True when every id handed to the provider was deleted.
  bool get isComplete => failed.isEmpty;

  /// Combines two reports of the same batch (e.g. MediaStore + SAF).
  SourceDeletionReport merge(SourceDeletionReport other) =>
      SourceDeletionReport(
        deleted: [...deleted, ...other.deleted],
        failed: [...failed, ...other.failed],
      );

  @override
  String toString() =>
      'SourceDeletionReport(deleted: ${deleted.length}, '
      'failed: ${failed.length})';
}
