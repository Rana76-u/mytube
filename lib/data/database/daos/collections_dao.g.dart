// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collections_dao.dart';

// ignore_for_file: type=lint
mixin _$CollectionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $VideoItemsTable get videoItems => attachedDatabase.videoItems;
  $CollectionItemsTable get collectionItems => attachedDatabase.collectionItems;
  CollectionsDaoManager get managers => CollectionsDaoManager(this);
}

class CollectionsDaoManager {
  final _$CollectionsDaoMixin _db;
  CollectionsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$VideoItemsTableTableManager get videoItems =>
      $$VideoItemsTableTableManager(_db.attachedDatabase, _db.videoItems);
  $$CollectionItemsTableTableManager get collectionItems =>
      $$CollectionItemsTableTableManager(
        _db.attachedDatabase,
        _db.collectionItems,
      );
}
