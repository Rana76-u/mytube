import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/features/downloads/download_preset_notifier.dart';

ProviderContainer _container({AppDatabase? database, bool broken = false}) {
  final overrides = [
    if (broken)
      databaseProvider.overrideWith((ref) => throw StateError('storage gone'))
    else
      databaseProvider.overrideWithValue(database ?? AppDatabase.inMemory()),
  ];
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('DownloadPresetNotifier', () {
    test('starts at the documented defaults', () {
      final container = _container();
      expect(container.read(downloadPresetProvider), DownloadPreset.defaults);
    });

    test('update changes state and persists for the next session', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final container = _container(database: db);

      await container
          .read(downloadPresetProvider.notifier)
          .update(
            DownloadPreset.defaults.copyWith(maxHeight: 720, maxConcurrent: 5),
          );
      expect(container.read(downloadPresetProvider).maxHeight, 720);

      // The rows a later session's notifier would read back are present and
      // decode to the saved choice.
      final raw = <String, String?>{
        for (final key in AppPreferenceKeys.downloadKeys)
          key: await db.appPreferencesDao.getString(key),
      };
      expect(raw[AppPreferenceKeys.downloadMaxHeight], '720');
      final restored = DownloadPresetCodec.decode(raw);
      expect(restored.maxHeight, 720);
      expect(restored.maxConcurrent, 5);
    });

    test('patch applies one field and keeps the rest', () async {
      final container = _container();
      final notifier = container.read(downloadPresetProvider.notifier);

      await notifier.update(DownloadPreset.defaults.copyWith(maxHeight: 480));
      await notifier.patch(
        (p) => p.copyWith(container: ContainerPreference.mkv),
      );

      final state = container.read(downloadPresetProvider);
      expect(state.maxHeight, 480);
      expect(state.container, ContainerPreference.mkv);
    });

    test('update normalises an out-of-range value before storing', () async {
      final container = _container();
      await container
          .read(downloadPresetProvider.notifier)
          .update(DownloadPreset(maxConcurrent: 99, fragments: 99));
      final state = container.read(downloadPresetProvider);
      expect(state.maxConcurrent, 3);
      expect(state.fragments, 8);
    });

    test(
      'a broken database still yields defaults and keeps in-memory edits',
      () async {
        final container = _container(broken: true);
        await _settle();
        expect(container.read(downloadPresetProvider), DownloadPreset.defaults);

        // Persistence throws internally; the session value must still apply.
        await container
            .read(downloadPresetProvider.notifier)
            .update(DownloadPreset.defaults.copyWith(wifiOnly: true));
        expect(container.read(downloadPresetProvider).wifiOnly, isTrue);
      },
    );
  });
}
