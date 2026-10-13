import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('opens without error', () async {
      // Trigger database open by executing a no-op query.
      // customSelect returns an empty result on an empty schema.
      final result = await db.customSelect('SELECT 1').get();
      expect(result, isNotEmpty);
    });

    test('schema version is 1', () async {
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      expect(version, equals(1));
    });

    test('closes without error', () async {
      // tearDown will call db.close(); this test just verifies open succeeded.
      expect(db, isNotNull);
    });
  });
}
