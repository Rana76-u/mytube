// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recommendation_exposures_dao.dart';

// ignore_for_file: type=lint
mixin _$RecommendationExposuresDaoMixin on DatabaseAccessor<AppDatabase> {
  $VideoItemsTable get videoItems => attachedDatabase.videoItems;
  $RecommendationExposuresTable get recommendationExposures =>
      attachedDatabase.recommendationExposures;
  RecommendationExposuresDaoManager get managers =>
      RecommendationExposuresDaoManager(this);
}

class RecommendationExposuresDaoManager {
  final _$RecommendationExposuresDaoMixin _db;
  RecommendationExposuresDaoManager(this._db);
  $$VideoItemsTableTableManager get videoItems =>
      $$VideoItemsTableTableManager(_db.attachedDatabase, _db.videoItems);
  $$RecommendationExposuresTableTableManager get recommendationExposures =>
      $$RecommendationExposuresTableTableManager(
        _db.attachedDatabase,
        _db.recommendationExposures,
      );
}
