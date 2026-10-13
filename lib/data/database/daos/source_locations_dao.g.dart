// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_locations_dao.dart';

// ignore_for_file: type=lint
mixin _$SourceLocationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $VideoItemsTable get videoItems => attachedDatabase.videoItems;
  $SourceLocationsTable get sourceLocations => attachedDatabase.sourceLocations;
  SourceLocationsDaoManager get managers => SourceLocationsDaoManager(this);
}

class SourceLocationsDaoManager {
  final _$SourceLocationsDaoMixin _db;
  SourceLocationsDaoManager(this._db);
  $$VideoItemsTableTableManager get videoItems =>
      $$VideoItemsTableTableManager(_db.attachedDatabase, _db.videoItems);
  $$SourceLocationsTableTableManager get sourceLocations =>
      $$SourceLocationsTableTableManager(
        _db.attachedDatabase,
        _db.sourceLocations,
      );
}
