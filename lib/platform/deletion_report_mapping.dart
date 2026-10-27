import 'package:mytube/domain/models/source_deletion_report.dart';

/// Maps a native deletion reply to the domain [SourceDeletionReport] (ADR-017).
///
/// Both platform channels answer with the same `{deleted: [...], failed: [...]}`
/// shape so the two bridges cannot drift. Every requested id is accounted for:
/// one the platform never mentioned is reported as kept, because "we could not
/// confirm it" must never be presented to the user as "it was deleted".
SourceDeletionReport parseSourceDeletionReport(
  Object? raw,
  List<String> requested,
) {
  final deleted = <String>[];
  final failed = <String>[];
  if (raw is Map) {
    for (final id in (raw['deleted'] as List?) ?? const <Object?>[]) {
      if (id is String) deleted.add(id);
    }
    for (final id in (raw['failed'] as List?) ?? const <Object?>[]) {
      if (id is String) failed.add(id);
    }
  }
  for (final id in requested) {
    if (!deleted.contains(id) && !failed.contains(id)) failed.add(id);
  }
  return SourceDeletionReport(deleted: deleted, failed: failed);
}
