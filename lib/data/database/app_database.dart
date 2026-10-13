import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Empty Drift database — tables are added in P2-02 and later.
/// Annotated with tables: [] intentionally; generation produces
/// a valid but empty schema at schema version 1.
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  /// Opens the on-disk SQLite database via drift_flutter.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'mytube_db');
  }

  /// Opens an in-memory database for use in tests.
  static AppDatabase inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }
}
