// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_preferences_dao.dart';

// ignore_for_file: type=lint
mixin _$AppPreferencesDaoMixin on DatabaseAccessor<AppDatabase> {
  $AppPreferencesTable get appPreferences => attachedDatabase.appPreferences;
  AppPreferencesDaoManager get managers => AppPreferencesDaoManager(this);
}

class AppPreferencesDaoManager {
  final _$AppPreferencesDaoMixin _db;
  AppPreferencesDaoManager(this._db);
  $$AppPreferencesTableTableManager get appPreferences =>
      $$AppPreferencesTableTableManager(
        _db.attachedDatabase,
        _db.appPreferences,
      );
}
