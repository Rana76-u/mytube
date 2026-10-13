import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/database/app_database.dart';

/// Riverpod provider for the application's [AppDatabase].
///
/// Lazy by default (not opened until first use).
/// Override in tests with an in-memory database:
/// ```dart
/// final container = ProviderContainer(
///   overrides: [databaseProvider.overrideWithValue(AppDatabase.inMemory())],
/// );
/// ```
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
