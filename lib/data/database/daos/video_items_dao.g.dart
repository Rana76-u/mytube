// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_items_dao.dart';

// ignore_for_file: type=lint
mixin _$VideoItemsDaoMixin on DatabaseAccessor<AppDatabase> {
  $VideoItemsTable get videoItems => attachedDatabase.videoItems;
  VideoItemsDaoManager get managers => VideoItemsDaoManager(this);
}

class VideoItemsDaoManager {
  final _$VideoItemsDaoMixin _db;
  VideoItemsDaoManager(this._db);
  $$VideoItemsTableTableManager get videoItems =>
      $$VideoItemsTableTableManager(_db.attachedDatabase, _db.videoItems);
}
