// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $VideoItemsTable extends VideoItems
    with TableInfo<$VideoItemsTable, VideoItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideoItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthPxMeta = const VerificationMeta(
    'widthPx',
  );
  @override
  late final GeneratedColumn<int> widthPx = GeneratedColumn<int>(
    'width_px',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightPxMeta = const VerificationMeta(
    'heightPx',
  );
  @override
  late final GeneratedColumn<int> heightPx = GeneratedColumn<int>(
    'height_px',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavouriteMeta = const VerificationMeta(
    'isFavourite',
  );
  @override
  late final GeneratedColumn<bool> isFavourite = GeneratedColumn<bool>(
    'is_favourite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favourite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _watchProgressMsMeta = const VerificationMeta(
    'watchProgressMs',
  );
  @override
  late final GeneratedColumn<int> watchProgressMs = GeneratedColumn<int>(
    'watch_progress_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<int> lastPlayedAt = GeneratedColumn<int>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    durationMs,
    widthPx,
    heightPx,
    isFavourite,
    watchProgressMs,
    lastPlayedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'video_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<VideoItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('width_px')) {
      context.handle(
        _widthPxMeta,
        widthPx.isAcceptableOrUnknown(data['width_px']!, _widthPxMeta),
      );
    }
    if (data.containsKey('height_px')) {
      context.handle(
        _heightPxMeta,
        heightPx.isAcceptableOrUnknown(data['height_px']!, _heightPxMeta),
      );
    }
    if (data.containsKey('is_favourite')) {
      context.handle(
        _isFavouriteMeta,
        isFavourite.isAcceptableOrUnknown(
          data['is_favourite']!,
          _isFavouriteMeta,
        ),
      );
    }
    if (data.containsKey('watch_progress_ms')) {
      context.handle(
        _watchProgressMsMeta,
        watchProgressMs.isAcceptableOrUnknown(
          data['watch_progress_ms']!,
          _watchProgressMsMeta,
        ),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VideoItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VideoItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      widthPx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width_px'],
      ),
      heightPx: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height_px'],
      ),
      isFavourite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favourite'],
      )!,
      watchProgressMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watch_progress_ms'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_played_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VideoItemsTable createAlias(String alias) {
    return $VideoItemsTable(attachedDatabase, alias);
  }
}

class VideoItem extends DataClass implements Insertable<VideoItem> {
  /// Stable, app-assigned UUID (TEXT, NOT NULL, PRIMARY KEY).
  final String id;

  /// User-facing title.  Defaults to the filename discovered at index time.
  final String title;

  /// Total playback duration in milliseconds, if known.
  final int? durationMs;

  /// Video width in pixels, if known.
  final int? widthPx;

  /// Video height in pixels, if known.
  final int? heightPx;

  /// Whether the user has marked this item as a favourite.
  final bool isFavourite;

  /// Playback position at last pause/seek, in milliseconds.
  final int watchProgressMs;

  /// Wall-clock timestamp (ms since epoch) when the item was last played.
  /// NULL if never played.
  final int? lastPlayedAt;

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  final int createdAt;

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  final int updatedAt;
  const VideoItem({
    required this.id,
    required this.title,
    this.durationMs,
    this.widthPx,
    this.heightPx,
    required this.isFavourite,
    required this.watchProgressMs,
    this.lastPlayedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || widthPx != null) {
      map['width_px'] = Variable<int>(widthPx);
    }
    if (!nullToAbsent || heightPx != null) {
      map['height_px'] = Variable<int>(heightPx);
    }
    map['is_favourite'] = Variable<bool>(isFavourite);
    map['watch_progress_ms'] = Variable<int>(watchProgressMs);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<int>(lastPlayedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  VideoItemsCompanion toCompanion(bool nullToAbsent) {
    return VideoItemsCompanion(
      id: Value(id),
      title: Value(title),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      widthPx: widthPx == null && nullToAbsent
          ? const Value.absent()
          : Value(widthPx),
      heightPx: heightPx == null && nullToAbsent
          ? const Value.absent()
          : Value(heightPx),
      isFavourite: Value(isFavourite),
      watchProgressMs: Value(watchProgressMs),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory VideoItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VideoItem(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      widthPx: serializer.fromJson<int?>(json['widthPx']),
      heightPx: serializer.fromJson<int?>(json['heightPx']),
      isFavourite: serializer.fromJson<bool>(json['isFavourite']),
      watchProgressMs: serializer.fromJson<int>(json['watchProgressMs']),
      lastPlayedAt: serializer.fromJson<int?>(json['lastPlayedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'durationMs': serializer.toJson<int?>(durationMs),
      'widthPx': serializer.toJson<int?>(widthPx),
      'heightPx': serializer.toJson<int?>(heightPx),
      'isFavourite': serializer.toJson<bool>(isFavourite),
      'watchProgressMs': serializer.toJson<int>(watchProgressMs),
      'lastPlayedAt': serializer.toJson<int?>(lastPlayedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  VideoItem copyWith({
    String? id,
    String? title,
    Value<int?> durationMs = const Value.absent(),
    Value<int?> widthPx = const Value.absent(),
    Value<int?> heightPx = const Value.absent(),
    bool? isFavourite,
    int? watchProgressMs,
    Value<int?> lastPlayedAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => VideoItem(
    id: id ?? this.id,
    title: title ?? this.title,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    widthPx: widthPx.present ? widthPx.value : this.widthPx,
    heightPx: heightPx.present ? heightPx.value : this.heightPx,
    isFavourite: isFavourite ?? this.isFavourite,
    watchProgressMs: watchProgressMs ?? this.watchProgressMs,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VideoItem copyWithCompanion(VideoItemsCompanion data) {
    return VideoItem(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      widthPx: data.widthPx.present ? data.widthPx.value : this.widthPx,
      heightPx: data.heightPx.present ? data.heightPx.value : this.heightPx,
      isFavourite: data.isFavourite.present
          ? data.isFavourite.value
          : this.isFavourite,
      watchProgressMs: data.watchProgressMs.present
          ? data.watchProgressMs.value
          : this.watchProgressMs,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VideoItem(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('durationMs: $durationMs, ')
          ..write('widthPx: $widthPx, ')
          ..write('heightPx: $heightPx, ')
          ..write('isFavourite: $isFavourite, ')
          ..write('watchProgressMs: $watchProgressMs, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    durationMs,
    widthPx,
    heightPx,
    isFavourite,
    watchProgressMs,
    lastPlayedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VideoItem &&
          other.id == this.id &&
          other.title == this.title &&
          other.durationMs == this.durationMs &&
          other.widthPx == this.widthPx &&
          other.heightPx == this.heightPx &&
          other.isFavourite == this.isFavourite &&
          other.watchProgressMs == this.watchProgressMs &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VideoItemsCompanion extends UpdateCompanion<VideoItem> {
  final Value<String> id;
  final Value<String> title;
  final Value<int?> durationMs;
  final Value<int?> widthPx;
  final Value<int?> heightPx;
  final Value<bool> isFavourite;
  final Value<int> watchProgressMs;
  final Value<int?> lastPlayedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const VideoItemsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.widthPx = const Value.absent(),
    this.heightPx = const Value.absent(),
    this.isFavourite = const Value.absent(),
    this.watchProgressMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VideoItemsCompanion.insert({
    required String id,
    required String title,
    this.durationMs = const Value.absent(),
    this.widthPx = const Value.absent(),
    this.heightPx = const Value.absent(),
    this.isFavourite = const Value.absent(),
    this.watchProgressMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<VideoItem> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? durationMs,
    Expression<int>? widthPx,
    Expression<int>? heightPx,
    Expression<bool>? isFavourite,
    Expression<int>? watchProgressMs,
    Expression<int>? lastPlayedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (durationMs != null) 'duration_ms': durationMs,
      if (widthPx != null) 'width_px': widthPx,
      if (heightPx != null) 'height_px': heightPx,
      if (isFavourite != null) 'is_favourite': isFavourite,
      if (watchProgressMs != null) 'watch_progress_ms': watchProgressMs,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VideoItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int?>? durationMs,
    Value<int?>? widthPx,
    Value<int?>? heightPx,
    Value<bool>? isFavourite,
    Value<int>? watchProgressMs,
    Value<int?>? lastPlayedAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return VideoItemsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      durationMs: durationMs ?? this.durationMs,
      widthPx: widthPx ?? this.widthPx,
      heightPx: heightPx ?? this.heightPx,
      isFavourite: isFavourite ?? this.isFavourite,
      watchProgressMs: watchProgressMs ?? this.watchProgressMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (widthPx.present) {
      map['width_px'] = Variable<int>(widthPx.value);
    }
    if (heightPx.present) {
      map['height_px'] = Variable<int>(heightPx.value);
    }
    if (isFavourite.present) {
      map['is_favourite'] = Variable<bool>(isFavourite.value);
    }
    if (watchProgressMs.present) {
      map['watch_progress_ms'] = Variable<int>(watchProgressMs.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<int>(lastPlayedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideoItemsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('durationMs: $durationMs, ')
          ..write('widthPx: $widthPx, ')
          ..write('heightPx: $heightPx, ')
          ..write('isFavourite: $isFavourite, ')
          ..write('watchProgressMs: $watchProgressMs, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceLocationsTable extends SourceLocations
    with TableInfo<$SourceLocationsTable, SourceLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoItemIdMeta = const VerificationMeta(
    'videoItemId',
  );
  @override
  late final GeneratedColumn<String> videoItemId = GeneratedColumn<String>(
    'video_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES video_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _providerTypeMeta = const VerificationMeta(
    'providerType',
  );
  @override
  late final GeneratedColumn<String> providerType = GeneratedColumn<String>(
    'provider_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailUriMeta = const VerificationMeta(
    'thumbnailUri',
  );
  @override
  late final GeneratedColumn<String> thumbnailUri = GeneratedColumn<String>(
    'thumbnail_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _availabilityMeta = const VerificationMeta(
    'availability',
  );
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
    'availability',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _lastCheckedAtMeta = const VerificationMeta(
    'lastCheckedAt',
  );
  @override
  late final GeneratedColumn<int> lastCheckedAt = GeneratedColumn<int>(
    'last_checked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    videoItemId,
    providerType,
    sourceId,
    displayName,
    mimeType,
    sizeBytes,
    thumbnailUri,
    availability,
    lastCheckedAt,
    isPrimary,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceLocation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('video_item_id')) {
      context.handle(
        _videoItemIdMeta,
        videoItemId.isAcceptableOrUnknown(
          data['video_item_id']!,
          _videoItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_videoItemIdMeta);
    }
    if (data.containsKey('provider_type')) {
      context.handle(
        _providerTypeMeta,
        providerType.isAcceptableOrUnknown(
          data['provider_type']!,
          _providerTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerTypeMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('thumbnail_uri')) {
      context.handle(
        _thumbnailUriMeta,
        thumbnailUri.isAcceptableOrUnknown(
          data['thumbnail_uri']!,
          _thumbnailUriMeta,
        ),
      );
    }
    if (data.containsKey('availability')) {
      context.handle(
        _availabilityMeta,
        availability.isAcceptableOrUnknown(
          data['availability']!,
          _availabilityMeta,
        ),
      );
    }
    if (data.containsKey('last_checked_at')) {
      context.handle(
        _lastCheckedAtMeta,
        lastCheckedAt.isAcceptableOrUnknown(
          data['last_checked_at']!,
          _lastCheckedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceLocation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      videoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_item_id'],
      )!,
      providerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_type'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      thumbnailUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_uri'],
      ),
      availability: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}availability'],
      )!,
      lastCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_checked_at'],
      ),
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SourceLocationsTable createAlias(String alias) {
    return $SourceLocationsTable(attachedDatabase, alias);
  }
}

class SourceLocation extends DataClass implements Insertable<SourceLocation> {
  /// Stable, app-assigned UUID (TEXT, NOT NULL, PRIMARY KEY).
  final String id;

  /// The parent [VideoItems.id].
  final String videoItemId;

  /// Serialised [ProviderType] enum name (e.g. `"localMediaStore"`).
  final String providerType;

  /// The durable identity of this source within its provider:
  ///   • local file → absolute file path
  ///   • MediaStore → MediaStore content URI string
  ///   • direct URL → the URL itself
  ///   • cloud → provider-assigned item id
  ///
  /// Never store ephemeral signed URLs here.
  final String sourceId;

  /// Human-readable label for this location (e.g. "OneDrive — My Videos").
  /// May be NULL when derived automatically.
  final String? displayName;

  /// MIME type reported by the source, if known.
  final String? mimeType;

  /// File size in bytes, if known.
  final int? sizeBytes;

  /// Durable provider thumbnail reference (P7-02): a content:// URI for
  /// MediaStore rows, a document:// URI for SAF rows, or an https:// URL for
  /// providers that expose a stable preview endpoint.  This is a *thumbnail*
  /// reference only — never a playback identity — so storing it does not
  /// violate the signed-URL durability rule (ARCHITECTURE §4).
  final String? thumbnailUri;

  /// Serialised [AvailabilityState] enum name (e.g. `"available"`).
  final String availability;

  /// Wall-clock timestamp (ms since epoch) of the last availability check.
  /// NULL if never checked.
  final int? lastCheckedAt;

  /// Whether this is the preferred location for playback resolution when
  /// multiple locations exist for the same video item.
  final bool isPrimary;

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  final int createdAt;

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  final int updatedAt;
  const SourceLocation({
    required this.id,
    required this.videoItemId,
    required this.providerType,
    required this.sourceId,
    this.displayName,
    this.mimeType,
    this.sizeBytes,
    this.thumbnailUri,
    required this.availability,
    this.lastCheckedAt,
    required this.isPrimary,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['video_item_id'] = Variable<String>(videoItemId);
    map['provider_type'] = Variable<String>(providerType);
    map['source_id'] = Variable<String>(sourceId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || thumbnailUri != null) {
      map['thumbnail_uri'] = Variable<String>(thumbnailUri);
    }
    map['availability'] = Variable<String>(availability);
    if (!nullToAbsent || lastCheckedAt != null) {
      map['last_checked_at'] = Variable<int>(lastCheckedAt);
    }
    map['is_primary'] = Variable<bool>(isPrimary);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SourceLocationsCompanion toCompanion(bool nullToAbsent) {
    return SourceLocationsCompanion(
      id: Value(id),
      videoItemId: Value(videoItemId),
      providerType: Value(providerType),
      sourceId: Value(sourceId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      thumbnailUri: thumbnailUri == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUri),
      availability: Value(availability),
      lastCheckedAt: lastCheckedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckedAt),
      isPrimary: Value(isPrimary),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SourceLocation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceLocation(
      id: serializer.fromJson<String>(json['id']),
      videoItemId: serializer.fromJson<String>(json['videoItemId']),
      providerType: serializer.fromJson<String>(json['providerType']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      thumbnailUri: serializer.fromJson<String?>(json['thumbnailUri']),
      availability: serializer.fromJson<String>(json['availability']),
      lastCheckedAt: serializer.fromJson<int?>(json['lastCheckedAt']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'videoItemId': serializer.toJson<String>(videoItemId),
      'providerType': serializer.toJson<String>(providerType),
      'sourceId': serializer.toJson<String>(sourceId),
      'displayName': serializer.toJson<String?>(displayName),
      'mimeType': serializer.toJson<String?>(mimeType),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'thumbnailUri': serializer.toJson<String?>(thumbnailUri),
      'availability': serializer.toJson<String>(availability),
      'lastCheckedAt': serializer.toJson<int?>(lastCheckedAt),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SourceLocation copyWith({
    String? id,
    String? videoItemId,
    String? providerType,
    String? sourceId,
    Value<String?> displayName = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    Value<String?> thumbnailUri = const Value.absent(),
    String? availability,
    Value<int?> lastCheckedAt = const Value.absent(),
    bool? isPrimary,
    int? createdAt,
    int? updatedAt,
  }) => SourceLocation(
    id: id ?? this.id,
    videoItemId: videoItemId ?? this.videoItemId,
    providerType: providerType ?? this.providerType,
    sourceId: sourceId ?? this.sourceId,
    displayName: displayName.present ? displayName.value : this.displayName,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    thumbnailUri: thumbnailUri.present ? thumbnailUri.value : this.thumbnailUri,
    availability: availability ?? this.availability,
    lastCheckedAt: lastCheckedAt.present
        ? lastCheckedAt.value
        : this.lastCheckedAt,
    isPrimary: isPrimary ?? this.isPrimary,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SourceLocation copyWithCompanion(SourceLocationsCompanion data) {
    return SourceLocation(
      id: data.id.present ? data.id.value : this.id,
      videoItemId: data.videoItemId.present
          ? data.videoItemId.value
          : this.videoItemId,
      providerType: data.providerType.present
          ? data.providerType.value
          : this.providerType,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      thumbnailUri: data.thumbnailUri.present
          ? data.thumbnailUri.value
          : this.thumbnailUri,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      lastCheckedAt: data.lastCheckedAt.present
          ? data.lastCheckedAt.value
          : this.lastCheckedAt,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceLocation(')
          ..write('id: $id, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('providerType: $providerType, ')
          ..write('sourceId: $sourceId, ')
          ..write('displayName: $displayName, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('thumbnailUri: $thumbnailUri, ')
          ..write('availability: $availability, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    videoItemId,
    providerType,
    sourceId,
    displayName,
    mimeType,
    sizeBytes,
    thumbnailUri,
    availability,
    lastCheckedAt,
    isPrimary,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceLocation &&
          other.id == this.id &&
          other.videoItemId == this.videoItemId &&
          other.providerType == this.providerType &&
          other.sourceId == this.sourceId &&
          other.displayName == this.displayName &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.thumbnailUri == this.thumbnailUri &&
          other.availability == this.availability &&
          other.lastCheckedAt == this.lastCheckedAt &&
          other.isPrimary == this.isPrimary &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SourceLocationsCompanion extends UpdateCompanion<SourceLocation> {
  final Value<String> id;
  final Value<String> videoItemId;
  final Value<String> providerType;
  final Value<String> sourceId;
  final Value<String?> displayName;
  final Value<String?> mimeType;
  final Value<int?> sizeBytes;
  final Value<String?> thumbnailUri;
  final Value<String> availability;
  final Value<int?> lastCheckedAt;
  final Value<bool> isPrimary;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SourceLocationsCompanion({
    this.id = const Value.absent(),
    this.videoItemId = const Value.absent(),
    this.providerType = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.thumbnailUri = const Value.absent(),
    this.availability = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceLocationsCompanion.insert({
    required String id,
    required String videoItemId,
    required String providerType,
    required String sourceId,
    this.displayName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.thumbnailUri = const Value.absent(),
    this.availability = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.isPrimary = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       videoItemId = Value(videoItemId),
       providerType = Value(providerType),
       sourceId = Value(sourceId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SourceLocation> custom({
    Expression<String>? id,
    Expression<String>? videoItemId,
    Expression<String>? providerType,
    Expression<String>? sourceId,
    Expression<String>? displayName,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<String>? thumbnailUri,
    Expression<String>? availability,
    Expression<int>? lastCheckedAt,
    Expression<bool>? isPrimary,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (videoItemId != null) 'video_item_id': videoItemId,
      if (providerType != null) 'provider_type': providerType,
      if (sourceId != null) 'source_id': sourceId,
      if (displayName != null) 'display_name': displayName,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (thumbnailUri != null) 'thumbnail_uri': thumbnailUri,
      if (availability != null) 'availability': availability,
      if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceLocationsCompanion copyWith({
    Value<String>? id,
    Value<String>? videoItemId,
    Value<String>? providerType,
    Value<String>? sourceId,
    Value<String?>? displayName,
    Value<String?>? mimeType,
    Value<int?>? sizeBytes,
    Value<String?>? thumbnailUri,
    Value<String>? availability,
    Value<int?>? lastCheckedAt,
    Value<bool>? isPrimary,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SourceLocationsCompanion(
      id: id ?? this.id,
      videoItemId: videoItemId ?? this.videoItemId,
      providerType: providerType ?? this.providerType,
      sourceId: sourceId ?? this.sourceId,
      displayName: displayName ?? this.displayName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailUri: thumbnailUri ?? this.thumbnailUri,
      availability: availability ?? this.availability,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (videoItemId.present) {
      map['video_item_id'] = Variable<String>(videoItemId.value);
    }
    if (providerType.present) {
      map['provider_type'] = Variable<String>(providerType.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (thumbnailUri.present) {
      map['thumbnail_uri'] = Variable<String>(thumbnailUri.value);
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (lastCheckedAt.present) {
      map['last_checked_at'] = Variable<int>(lastCheckedAt.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceLocationsCompanion(')
          ..write('id: $id, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('providerType: $providerType, ')
          ..write('sourceId: $sourceId, ')
          ..write('displayName: $displayName, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('thumbnailUri: $thumbnailUri, ')
          ..write('availability: $availability, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  /// Stable, app-assigned UUID.
  final String id;

  /// User-visible tag label, lower-cased and trimmed.
  /// UNIQUE to prevent duplicates.
  final String name;

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  final int createdAt;
  const Tag({required this.id, required this.name, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Tag copyWith({String? id, String? name, int? createdAt}) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Tag> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VideoTagsTable extends VideoTags
    with TableInfo<$VideoTagsTable, VideoTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideoTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoItemIdMeta = const VerificationMeta(
    'videoItemId',
  );
  @override
  late final GeneratedColumn<String> videoItemId = GeneratedColumn<String>(
    'video_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES video_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [videoItemId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'video_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<VideoTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_item_id')) {
      context.handle(
        _videoItemIdMeta,
        videoItemId.isAcceptableOrUnknown(
          data['video_item_id']!,
          _videoItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_videoItemIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoItemId, tagId};
  @override
  VideoTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VideoTag(
      videoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_item_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $VideoTagsTable createAlias(String alias) {
    return $VideoTagsTable(attachedDatabase, alias);
  }
}

class VideoTag extends DataClass implements Insertable<VideoTag> {
  /// FK → [VideoItems.id].
  final String videoItemId;

  /// FK → [Tags.id].
  final String tagId;
  const VideoTag({required this.videoItemId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_item_id'] = Variable<String>(videoItemId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  VideoTagsCompanion toCompanion(bool nullToAbsent) {
    return VideoTagsCompanion(
      videoItemId: Value(videoItemId),
      tagId: Value(tagId),
    );
  }

  factory VideoTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VideoTag(
      videoItemId: serializer.fromJson<String>(json['videoItemId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoItemId': serializer.toJson<String>(videoItemId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  VideoTag copyWith({String? videoItemId, String? tagId}) => VideoTag(
    videoItemId: videoItemId ?? this.videoItemId,
    tagId: tagId ?? this.tagId,
  );
  VideoTag copyWithCompanion(VideoTagsCompanion data) {
    return VideoTag(
      videoItemId: data.videoItemId.present
          ? data.videoItemId.value
          : this.videoItemId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VideoTag(')
          ..write('videoItemId: $videoItemId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(videoItemId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VideoTag &&
          other.videoItemId == this.videoItemId &&
          other.tagId == this.tagId);
}

class VideoTagsCompanion extends UpdateCompanion<VideoTag> {
  final Value<String> videoItemId;
  final Value<String> tagId;
  final Value<int> rowid;
  const VideoTagsCompanion({
    this.videoItemId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VideoTagsCompanion.insert({
    required String videoItemId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : videoItemId = Value(videoItemId),
       tagId = Value(tagId);
  static Insertable<VideoTag> custom({
    Expression<String>? videoItemId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoItemId != null) 'video_item_id': videoItemId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VideoTagsCompanion copyWith({
    Value<String>? videoItemId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return VideoTagsCompanion(
      videoItemId: videoItemId ?? this.videoItemId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoItemId.present) {
      map['video_item_id'] = Variable<String>(videoItemId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideoTagsCompanion(')
          ..write('videoItemId: $videoItemId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, Collection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<int> pinnedAt = GeneratedColumn<int>(
    'pinned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
    isPinned,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Collection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Collection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Collection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pinned_at'],
      ),
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class Collection extends DataClass implements Insertable<Collection> {
  /// Stable, app-assigned UUID.
  final String id;

  /// User-facing collection name.
  final String name;

  /// Optional freeform description.
  final String? description;

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  final int createdAt;

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  final int updatedAt;

  /// Whether the user pinned this collection to the top of Discover (P4 disc
  /// redesign §19). Presentation/navigation preference only — it never changes
  /// collection membership or favourites.
  final bool isPinned;

  /// Wall-clock timestamp (ms since epoch) when the collection was pinned,
  /// or NULL when it is not pinned. Together with [isPinned] it gives a
  /// deterministic pinned ordering (most-recently-pinned first, id tie-break)
  /// without a manual drag-to-reorder subsystem.
  final int? pinnedAt;
  const Collection({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.isPinned,
    this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<int>(pinnedAt);
    }
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isPinned: Value(isPinned),
      pinnedAt: pinnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedAt),
    );
  }

  factory Collection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Collection(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      pinnedAt: serializer.fromJson<int?>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'isPinned': serializer.toJson<bool>(isPinned),
      'pinnedAt': serializer.toJson<int?>(pinnedAt),
    };
  }

  Collection copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    bool? isPinned,
    Value<int?> pinnedAt = const Value.absent(),
  }) => Collection(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isPinned: isPinned ?? this.isPinned,
    pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
  );
  Collection copyWithCompanion(CollectionsCompanion data) {
    return Collection(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Collection(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    createdAt,
    updatedAt,
    isPinned,
    pinnedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collection &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isPinned == this.isPinned &&
          other.pinnedAt == this.pinnedAt);
}

class CollectionsCompanion extends UpdateCompanion<Collection> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> isPinned;
  final Value<int?> pinnedAt;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.isPinned = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Collection> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? isPinned,
    Expression<int>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isPinned != null) 'is_pinned': isPinned,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? isPinned,
    Value<int?>? pinnedAt,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<int>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionItemsTable extends CollectionItems
    with TableInfo<$CollectionItemsTable, CollectionItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _videoItemIdMeta = const VerificationMeta(
    'videoItemId',
  );
  @override
  late final GeneratedColumn<String> videoItemId = GeneratedColumn<String>(
    'video_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES video_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    collectionId,
    videoItemId,
    sortOrder,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('video_item_id')) {
      context.handle(
        _videoItemIdMeta,
        videoItemId.isAcceptableOrUnknown(
          data['video_item_id']!,
          _videoItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_videoItemIdMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collectionId, videoItemId};
  @override
  CollectionItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionItem(
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      )!,
      videoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_item_id'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $CollectionItemsTable createAlias(String alias) {
    return $CollectionItemsTable(attachedDatabase, alias);
  }
}

class CollectionItem extends DataClass implements Insertable<CollectionItem> {
  /// FK → [Collections.id].
  final String collectionId;

  /// FK → [VideoItems.id].
  final String videoItemId;

  /// Ascending sort order within the collection (lower = first).
  /// Defaults to 0; callers should assign monotonically increasing values
  /// when appending items.
  final int sortOrder;

  /// Wall-clock timestamp (ms since epoch) when this item was added to the
  /// collection.
  final int addedAt;
  const CollectionItem({
    required this.collectionId,
    required this.videoItemId,
    required this.sortOrder,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection_id'] = Variable<String>(collectionId);
    map['video_item_id'] = Variable<String>(videoItemId);
    map['sort_order'] = Variable<int>(sortOrder);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  CollectionItemsCompanion toCompanion(bool nullToAbsent) {
    return CollectionItemsCompanion(
      collectionId: Value(collectionId),
      videoItemId: Value(videoItemId),
      sortOrder: Value(sortOrder),
      addedAt: Value(addedAt),
    );
  }

  factory CollectionItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionItem(
      collectionId: serializer.fromJson<String>(json['collectionId']),
      videoItemId: serializer.fromJson<String>(json['videoItemId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collectionId': serializer.toJson<String>(collectionId),
      'videoItemId': serializer.toJson<String>(videoItemId),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  CollectionItem copyWith({
    String? collectionId,
    String? videoItemId,
    int? sortOrder,
    int? addedAt,
  }) => CollectionItem(
    collectionId: collectionId ?? this.collectionId,
    videoItemId: videoItemId ?? this.videoItemId,
    sortOrder: sortOrder ?? this.sortOrder,
    addedAt: addedAt ?? this.addedAt,
  );
  CollectionItem copyWithCompanion(CollectionItemsCompanion data) {
    return CollectionItem(
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      videoItemId: data.videoItemId.present
          ? data.videoItemId.value
          : this.videoItemId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionItem(')
          ..write('collectionId: $collectionId, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(collectionId, videoItemId, sortOrder, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionItem &&
          other.collectionId == this.collectionId &&
          other.videoItemId == this.videoItemId &&
          other.sortOrder == this.sortOrder &&
          other.addedAt == this.addedAt);
}

class CollectionItemsCompanion extends UpdateCompanion<CollectionItem> {
  final Value<String> collectionId;
  final Value<String> videoItemId;
  final Value<int> sortOrder;
  final Value<int> addedAt;
  final Value<int> rowid;
  const CollectionItemsCompanion({
    this.collectionId = const Value.absent(),
    this.videoItemId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionItemsCompanion.insert({
    required String collectionId,
    required String videoItemId,
    this.sortOrder = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : collectionId = Value(collectionId),
       videoItemId = Value(videoItemId),
       addedAt = Value(addedAt);
  static Insertable<CollectionItem> custom({
    Expression<String>? collectionId,
    Expression<String>? videoItemId,
    Expression<int>? sortOrder,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collectionId != null) 'collection_id': collectionId,
      if (videoItemId != null) 'video_item_id': videoItemId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionItemsCompanion copyWith({
    Value<String>? collectionId,
    Value<String>? videoItemId,
    Value<int>? sortOrder,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return CollectionItemsCompanion(
      collectionId: collectionId ?? this.collectionId,
      videoItemId: videoItemId ?? this.videoItemId,
      sortOrder: sortOrder ?? this.sortOrder,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (videoItemId.present) {
      map['video_item_id'] = Variable<String>(videoItemId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionItemsCompanion(')
          ..write('collectionId: $collectionId, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppPreferencesTable extends AppPreferences
    with TableInfo<$AppPreferencesTable, AppPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppPreference(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppPreferencesTable createAlias(String alias) {
    return $AppPreferencesTable(attachedDatabase, alias);
  }
}

class AppPreference extends DataClass implements Insertable<AppPreference> {
  /// Preference identifier — see [AppPreferenceKeys].
  final String key;

  /// Serialised preference value.
  final String value;
  const AppPreference({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppPreferencesCompanion toCompanion(bool nullToAbsent) {
    return AppPreferencesCompanion(key: Value(key), value: Value(value));
  }

  factory AppPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppPreference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppPreference copyWith({String? key, String? value}) =>
      AppPreference(key: key ?? this.key, value: value ?? this.value);
  AppPreference copyWithCompanion(AppPreferencesCompanion data) {
    return AppPreference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppPreference(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppPreference &&
          other.key == this.key &&
          other.value == this.value);
}

class AppPreferencesCompanion extends UpdateCompanion<AppPreference> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppPreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppPreference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppPreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecommendationExposuresTable extends RecommendationExposures
    with TableInfo<$RecommendationExposuresTable, RecommendationExposure> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecommendationExposuresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _videoItemIdMeta = const VerificationMeta(
    'videoItemId',
  );
  @override
  late final GeneratedColumn<String> videoItemId = GeneratedColumn<String>(
    'video_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES video_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstExposedAtMeta = const VerificationMeta(
    'firstExposedAt',
  );
  @override
  late final GeneratedColumn<int> firstExposedAt = GeneratedColumn<int>(
    'first_exposed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastExposedAtMeta = const VerificationMeta(
    'lastExposedAt',
  );
  @override
  late final GeneratedColumn<int> lastExposedAt = GeneratedColumn<int>(
    'last_exposed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    videoItemId,
    sessionId,
    firstExposedAt,
    lastExposedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recommendation_exposures';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecommendationExposure> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('video_item_id')) {
      context.handle(
        _videoItemIdMeta,
        videoItemId.isAcceptableOrUnknown(
          data['video_item_id']!,
          _videoItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_videoItemIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('first_exposed_at')) {
      context.handle(
        _firstExposedAtMeta,
        firstExposedAt.isAcceptableOrUnknown(
          data['first_exposed_at']!,
          _firstExposedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstExposedAtMeta);
    }
    if (data.containsKey('last_exposed_at')) {
      context.handle(
        _lastExposedAtMeta,
        lastExposedAt.isAcceptableOrUnknown(
          data['last_exposed_at']!,
          _lastExposedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastExposedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {videoItemId, sessionId};
  @override
  RecommendationExposure map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecommendationExposure(
      videoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_item_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      firstExposedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_exposed_at'],
      )!,
      lastExposedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_exposed_at'],
      )!,
    );
  }

  @override
  $RecommendationExposuresTable createAlias(String alias) {
    return $RecommendationExposuresTable(attachedDatabase, alias);
  }
}

class RecommendationExposure extends DataClass
    implements Insertable<RecommendationExposure> {
  /// FK → [VideoItems.id] — the logical video that was shown.
  final String videoItemId;

  /// Stable id identifying the browsing session the exposure happened in
  /// (§18.4). No backend/account: a locally generated grouping token.
  final String sessionId;

  /// Wall-clock timestamp (ms since epoch) of the first meaningful exposure.
  final int firstExposedAt;

  /// Wall-clock timestamp (ms since epoch) of the most recent exposure.
  final int lastExposedAt;
  const RecommendationExposure({
    required this.videoItemId,
    required this.sessionId,
    required this.firstExposedAt,
    required this.lastExposedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['video_item_id'] = Variable<String>(videoItemId);
    map['session_id'] = Variable<String>(sessionId);
    map['first_exposed_at'] = Variable<int>(firstExposedAt);
    map['last_exposed_at'] = Variable<int>(lastExposedAt);
    return map;
  }

  RecommendationExposuresCompanion toCompanion(bool nullToAbsent) {
    return RecommendationExposuresCompanion(
      videoItemId: Value(videoItemId),
      sessionId: Value(sessionId),
      firstExposedAt: Value(firstExposedAt),
      lastExposedAt: Value(lastExposedAt),
    );
  }

  factory RecommendationExposure.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecommendationExposure(
      videoItemId: serializer.fromJson<String>(json['videoItemId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      firstExposedAt: serializer.fromJson<int>(json['firstExposedAt']),
      lastExposedAt: serializer.fromJson<int>(json['lastExposedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'videoItemId': serializer.toJson<String>(videoItemId),
      'sessionId': serializer.toJson<String>(sessionId),
      'firstExposedAt': serializer.toJson<int>(firstExposedAt),
      'lastExposedAt': serializer.toJson<int>(lastExposedAt),
    };
  }

  RecommendationExposure copyWith({
    String? videoItemId,
    String? sessionId,
    int? firstExposedAt,
    int? lastExposedAt,
  }) => RecommendationExposure(
    videoItemId: videoItemId ?? this.videoItemId,
    sessionId: sessionId ?? this.sessionId,
    firstExposedAt: firstExposedAt ?? this.firstExposedAt,
    lastExposedAt: lastExposedAt ?? this.lastExposedAt,
  );
  RecommendationExposure copyWithCompanion(
    RecommendationExposuresCompanion data,
  ) {
    return RecommendationExposure(
      videoItemId: data.videoItemId.present
          ? data.videoItemId.value
          : this.videoItemId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      firstExposedAt: data.firstExposedAt.present
          ? data.firstExposedAt.value
          : this.firstExposedAt,
      lastExposedAt: data.lastExposedAt.present
          ? data.lastExposedAt.value
          : this.lastExposedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecommendationExposure(')
          ..write('videoItemId: $videoItemId, ')
          ..write('sessionId: $sessionId, ')
          ..write('firstExposedAt: $firstExposedAt, ')
          ..write('lastExposedAt: $lastExposedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(videoItemId, sessionId, firstExposedAt, lastExposedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecommendationExposure &&
          other.videoItemId == this.videoItemId &&
          other.sessionId == this.sessionId &&
          other.firstExposedAt == this.firstExposedAt &&
          other.lastExposedAt == this.lastExposedAt);
}

class RecommendationExposuresCompanion
    extends UpdateCompanion<RecommendationExposure> {
  final Value<String> videoItemId;
  final Value<String> sessionId;
  final Value<int> firstExposedAt;
  final Value<int> lastExposedAt;
  final Value<int> rowid;
  const RecommendationExposuresCompanion({
    this.videoItemId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.firstExposedAt = const Value.absent(),
    this.lastExposedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecommendationExposuresCompanion.insert({
    required String videoItemId,
    required String sessionId,
    required int firstExposedAt,
    required int lastExposedAt,
    this.rowid = const Value.absent(),
  }) : videoItemId = Value(videoItemId),
       sessionId = Value(sessionId),
       firstExposedAt = Value(firstExposedAt),
       lastExposedAt = Value(lastExposedAt);
  static Insertable<RecommendationExposure> custom({
    Expression<String>? videoItemId,
    Expression<String>? sessionId,
    Expression<int>? firstExposedAt,
    Expression<int>? lastExposedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (videoItemId != null) 'video_item_id': videoItemId,
      if (sessionId != null) 'session_id': sessionId,
      if (firstExposedAt != null) 'first_exposed_at': firstExposedAt,
      if (lastExposedAt != null) 'last_exposed_at': lastExposedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecommendationExposuresCompanion copyWith({
    Value<String>? videoItemId,
    Value<String>? sessionId,
    Value<int>? firstExposedAt,
    Value<int>? lastExposedAt,
    Value<int>? rowid,
  }) {
    return RecommendationExposuresCompanion(
      videoItemId: videoItemId ?? this.videoItemId,
      sessionId: sessionId ?? this.sessionId,
      firstExposedAt: firstExposedAt ?? this.firstExposedAt,
      lastExposedAt: lastExposedAt ?? this.lastExposedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (videoItemId.present) {
      map['video_item_id'] = Variable<String>(videoItemId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (firstExposedAt.present) {
      map['first_exposed_at'] = Variable<int>(firstExposedAt.value);
    }
    if (lastExposedAt.present) {
      map['last_exposed_at'] = Variable<int>(lastExposedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecommendationExposuresCompanion(')
          ..write('videoItemId: $videoItemId, ')
          ..write('sessionId: $sessionId, ')
          ..write('firstExposedAt: $firstExposedAt, ')
          ..write('lastExposedAt: $lastExposedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, Download> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoItemIdMeta = const VerificationMeta(
    'videoItemId',
  );
  @override
  late final GeneratedColumn<String> videoItemId = GeneratedColumn<String>(
    'video_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLocationIdMeta = const VerificationMeta(
    'sourceLocationId',
  );
  @override
  late final GeneratedColumn<String> sourceLocationId = GeneratedColumn<String>(
    'source_location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _providerTypeMeta = const VerificationMeta(
    'providerType',
  );
  @override
  late final GeneratedColumn<String> providerType = GeneratedColumn<String>(
    'provider_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceUriMeta = const VerificationMeta(
    'sourceUri',
  );
  @override
  late final GeneratedColumn<String> sourceUri = GeneratedColumn<String>(
    'source_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadedBytesMeta = const VerificationMeta(
    'downloadedBytes',
  );
  @override
  late final GeneratedColumn<int> downloadedBytes = GeneratedColumn<int>(
    'downloaded_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _acceptsRangeMeta = const VerificationMeta(
    'acceptsRange',
  );
  @override
  late final GeneratedColumn<bool> acceptsRange = GeneratedColumn<bool>(
    'accepts_range',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("accepts_range" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    videoItemId,
    sourceLocationId,
    providerType,
    sourceUri,
    fileName,
    sizeBytes,
    downloadedBytes,
    status,
    acceptsRange,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Download> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('video_item_id')) {
      context.handle(
        _videoItemIdMeta,
        videoItemId.isAcceptableOrUnknown(
          data['video_item_id']!,
          _videoItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_videoItemIdMeta);
    }
    if (data.containsKey('source_location_id')) {
      context.handle(
        _sourceLocationIdMeta,
        sourceLocationId.isAcceptableOrUnknown(
          data['source_location_id']!,
          _sourceLocationIdMeta,
        ),
      );
    }
    if (data.containsKey('provider_type')) {
      context.handle(
        _providerTypeMeta,
        providerType.isAcceptableOrUnknown(
          data['provider_type']!,
          _providerTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerTypeMeta);
    }
    if (data.containsKey('source_uri')) {
      context.handle(
        _sourceUriMeta,
        sourceUri.isAcceptableOrUnknown(data['source_uri']!, _sourceUriMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceUriMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('downloaded_bytes')) {
      context.handle(
        _downloadedBytesMeta,
        downloadedBytes.isAcceptableOrUnknown(
          data['downloaded_bytes']!,
          _downloadedBytesMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('accepts_range')) {
      context.handle(
        _acceptsRangeMeta,
        acceptsRange.isAcceptableOrUnknown(
          data['accepts_range']!,
          _acceptsRangeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Download map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Download(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      videoItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_item_id'],
      )!,
      sourceLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_location_id'],
      ),
      providerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_type'],
      )!,
      sourceUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_uri'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      downloadedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}downloaded_bytes'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      acceptsRange: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}accepts_range'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }
}

class Download extends DataClass implements Insertable<Download> {
  /// Stable app-assigned UUID (TEXT, PRIMARY KEY); also keys the file name.
  final String id;

  /// The parent library item's id (raw string, no cascade — see class doc).
  final String videoItemId;

  /// The source location this copy came from, when known.
  final String? sourceLocationId;

  /// Serialised [ProviderType] name (e.g. `"directUrl"`).
  final String providerType;

  /// Durable source identity — never an ephemeral signed URL (ARCHITECTURE §4).
  final String sourceUri;

  /// Final file name relative to the downloads root; the running transfer uses
  /// `fileName + '.part'`.
  final String fileName;

  /// Total expected size in bytes, or null when the server declared none.
  final int? sizeBytes;

  /// Bytes written so far.
  final int downloadedBytes;

  /// Serialised [DownloadStatus] name (e.g. `"running"`).
  final String status;

  /// Whether the source advertised byte-range support (resume, P12-04).
  final bool acceptsRange;

  /// Wall-clock timestamp (ms since epoch) when the row was created.
  final int createdAt;

  /// Wall-clock timestamp (ms since epoch) of the last update.
  final int updatedAt;
  const Download({
    required this.id,
    required this.videoItemId,
    this.sourceLocationId,
    required this.providerType,
    required this.sourceUri,
    required this.fileName,
    this.sizeBytes,
    required this.downloadedBytes,
    required this.status,
    required this.acceptsRange,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['video_item_id'] = Variable<String>(videoItemId);
    if (!nullToAbsent || sourceLocationId != null) {
      map['source_location_id'] = Variable<String>(sourceLocationId);
    }
    map['provider_type'] = Variable<String>(providerType);
    map['source_uri'] = Variable<String>(sourceUri);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    map['downloaded_bytes'] = Variable<int>(downloadedBytes);
    map['status'] = Variable<String>(status);
    map['accepts_range'] = Variable<bool>(acceptsRange);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      id: Value(id),
      videoItemId: Value(videoItemId),
      sourceLocationId: sourceLocationId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceLocationId),
      providerType: Value(providerType),
      sourceUri: Value(sourceUri),
      fileName: Value(fileName),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      downloadedBytes: Value(downloadedBytes),
      status: Value(status),
      acceptsRange: Value(acceptsRange),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Download.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Download(
      id: serializer.fromJson<String>(json['id']),
      videoItemId: serializer.fromJson<String>(json['videoItemId']),
      sourceLocationId: serializer.fromJson<String?>(json['sourceLocationId']),
      providerType: serializer.fromJson<String>(json['providerType']),
      sourceUri: serializer.fromJson<String>(json['sourceUri']),
      fileName: serializer.fromJson<String>(json['fileName']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      downloadedBytes: serializer.fromJson<int>(json['downloadedBytes']),
      status: serializer.fromJson<String>(json['status']),
      acceptsRange: serializer.fromJson<bool>(json['acceptsRange']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'videoItemId': serializer.toJson<String>(videoItemId),
      'sourceLocationId': serializer.toJson<String?>(sourceLocationId),
      'providerType': serializer.toJson<String>(providerType),
      'sourceUri': serializer.toJson<String>(sourceUri),
      'fileName': serializer.toJson<String>(fileName),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'downloadedBytes': serializer.toJson<int>(downloadedBytes),
      'status': serializer.toJson<String>(status),
      'acceptsRange': serializer.toJson<bool>(acceptsRange),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Download copyWith({
    String? id,
    String? videoItemId,
    Value<String?> sourceLocationId = const Value.absent(),
    String? providerType,
    String? sourceUri,
    String? fileName,
    Value<int?> sizeBytes = const Value.absent(),
    int? downloadedBytes,
    String? status,
    bool? acceptsRange,
    int? createdAt,
    int? updatedAt,
  }) => Download(
    id: id ?? this.id,
    videoItemId: videoItemId ?? this.videoItemId,
    sourceLocationId: sourceLocationId.present
        ? sourceLocationId.value
        : this.sourceLocationId,
    providerType: providerType ?? this.providerType,
    sourceUri: sourceUri ?? this.sourceUri,
    fileName: fileName ?? this.fileName,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    status: status ?? this.status,
    acceptsRange: acceptsRange ?? this.acceptsRange,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Download copyWithCompanion(DownloadsCompanion data) {
    return Download(
      id: data.id.present ? data.id.value : this.id,
      videoItemId: data.videoItemId.present
          ? data.videoItemId.value
          : this.videoItemId,
      sourceLocationId: data.sourceLocationId.present
          ? data.sourceLocationId.value
          : this.sourceLocationId,
      providerType: data.providerType.present
          ? data.providerType.value
          : this.providerType,
      sourceUri: data.sourceUri.present ? data.sourceUri.value : this.sourceUri,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      downloadedBytes: data.downloadedBytes.present
          ? data.downloadedBytes.value
          : this.downloadedBytes,
      status: data.status.present ? data.status.value : this.status,
      acceptsRange: data.acceptsRange.present
          ? data.acceptsRange.value
          : this.acceptsRange,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Download(')
          ..write('id: $id, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('sourceLocationId: $sourceLocationId, ')
          ..write('providerType: $providerType, ')
          ..write('sourceUri: $sourceUri, ')
          ..write('fileName: $fileName, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('status: $status, ')
          ..write('acceptsRange: $acceptsRange, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    videoItemId,
    sourceLocationId,
    providerType,
    sourceUri,
    fileName,
    sizeBytes,
    downloadedBytes,
    status,
    acceptsRange,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Download &&
          other.id == this.id &&
          other.videoItemId == this.videoItemId &&
          other.sourceLocationId == this.sourceLocationId &&
          other.providerType == this.providerType &&
          other.sourceUri == this.sourceUri &&
          other.fileName == this.fileName &&
          other.sizeBytes == this.sizeBytes &&
          other.downloadedBytes == this.downloadedBytes &&
          other.status == this.status &&
          other.acceptsRange == this.acceptsRange &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DownloadsCompanion extends UpdateCompanion<Download> {
  final Value<String> id;
  final Value<String> videoItemId;
  final Value<String?> sourceLocationId;
  final Value<String> providerType;
  final Value<String> sourceUri;
  final Value<String> fileName;
  final Value<int?> sizeBytes;
  final Value<int> downloadedBytes;
  final Value<String> status;
  final Value<bool> acceptsRange;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.id = const Value.absent(),
    this.videoItemId = const Value.absent(),
    this.sourceLocationId = const Value.absent(),
    this.providerType = const Value.absent(),
    this.sourceUri = const Value.absent(),
    this.fileName = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.acceptsRange = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String id,
    required String videoItemId,
    this.sourceLocationId = const Value.absent(),
    required String providerType,
    required String sourceUri,
    required String fileName,
    this.sizeBytes = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.acceptsRange = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       videoItemId = Value(videoItemId),
       providerType = Value(providerType),
       sourceUri = Value(sourceUri),
       fileName = Value(fileName),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Download> custom({
    Expression<String>? id,
    Expression<String>? videoItemId,
    Expression<String>? sourceLocationId,
    Expression<String>? providerType,
    Expression<String>? sourceUri,
    Expression<String>? fileName,
    Expression<int>? sizeBytes,
    Expression<int>? downloadedBytes,
    Expression<String>? status,
    Expression<bool>? acceptsRange,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (videoItemId != null) 'video_item_id': videoItemId,
      if (sourceLocationId != null) 'source_location_id': sourceLocationId,
      if (providerType != null) 'provider_type': providerType,
      if (sourceUri != null) 'source_uri': sourceUri,
      if (fileName != null) 'file_name': fileName,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (downloadedBytes != null) 'downloaded_bytes': downloadedBytes,
      if (status != null) 'status': status,
      if (acceptsRange != null) 'accepts_range': acceptsRange,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith({
    Value<String>? id,
    Value<String>? videoItemId,
    Value<String?>? sourceLocationId,
    Value<String>? providerType,
    Value<String>? sourceUri,
    Value<String>? fileName,
    Value<int?>? sizeBytes,
    Value<int>? downloadedBytes,
    Value<String>? status,
    Value<bool>? acceptsRange,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DownloadsCompanion(
      id: id ?? this.id,
      videoItemId: videoItemId ?? this.videoItemId,
      sourceLocationId: sourceLocationId ?? this.sourceLocationId,
      providerType: providerType ?? this.providerType,
      sourceUri: sourceUri ?? this.sourceUri,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      acceptsRange: acceptsRange ?? this.acceptsRange,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (videoItemId.present) {
      map['video_item_id'] = Variable<String>(videoItemId.value);
    }
    if (sourceLocationId.present) {
      map['source_location_id'] = Variable<String>(sourceLocationId.value);
    }
    if (providerType.present) {
      map['provider_type'] = Variable<String>(providerType.value);
    }
    if (sourceUri.present) {
      map['source_uri'] = Variable<String>(sourceUri.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (downloadedBytes.present) {
      map['downloaded_bytes'] = Variable<int>(downloadedBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (acceptsRange.present) {
      map['accepts_range'] = Variable<bool>(acceptsRange.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('id: $id, ')
          ..write('videoItemId: $videoItemId, ')
          ..write('sourceLocationId: $sourceLocationId, ')
          ..write('providerType: $providerType, ')
          ..write('sourceUri: $sourceUri, ')
          ..write('fileName: $fileName, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('status: $status, ')
          ..write('acceptsRange: $acceptsRange, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $VideoItemsTable videoItems = $VideoItemsTable(this);
  late final $SourceLocationsTable sourceLocations = $SourceLocationsTable(
    this,
  );
  late final $TagsTable tags = $TagsTable(this);
  late final $VideoTagsTable videoTags = $VideoTagsTable(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $CollectionItemsTable collectionItems = $CollectionItemsTable(
    this,
  );
  late final $AppPreferencesTable appPreferences = $AppPreferencesTable(this);
  late final $RecommendationExposuresTable recommendationExposures =
      $RecommendationExposuresTable(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  late final VideoItemsDao videoItemsDao = VideoItemsDao(this as AppDatabase);
  late final SourceLocationsDao sourceLocationsDao = SourceLocationsDao(
    this as AppDatabase,
  );
  late final AppPreferencesDao appPreferencesDao = AppPreferencesDao(
    this as AppDatabase,
  );
  late final CollectionsDao collectionsDao = CollectionsDao(
    this as AppDatabase,
  );
  late final RecommendationExposuresDao recommendationExposuresDao =
      RecommendationExposuresDao(this as AppDatabase);
  late final DownloadsDao downloadsDao = DownloadsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    videoItems,
    sourceLocations,
    tags,
    videoTags,
    collections,
    collectionItems,
    appPreferences,
    recommendationExposures,
    downloads,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'video_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('source_locations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'video_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('video_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('video_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('collection_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'video_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('collection_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'video_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('recommendation_exposures', kind: UpdateKind.delete),
      ],
    ),
  ]);
}

typedef $$VideoItemsTableCreateCompanionBuilder =
    VideoItemsCompanion Function({
      required String id,
      required String title,
      Value<int?> durationMs,
      Value<int?> widthPx,
      Value<int?> heightPx,
      Value<bool> isFavourite,
      Value<int> watchProgressMs,
      Value<int?> lastPlayedAt,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$VideoItemsTableUpdateCompanionBuilder =
    VideoItemsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<int?> durationMs,
      Value<int?> widthPx,
      Value<int?> heightPx,
      Value<bool> isFavourite,
      Value<int> watchProgressMs,
      Value<int?> lastPlayedAt,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$VideoItemsTableReferences
    extends BaseReferences<_$AppDatabase, $VideoItemsTable, VideoItem> {
  $$VideoItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SourceLocationsTable, List<SourceLocation>>
  _sourceLocationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sourceLocations,
    aliasName: 'video_items__id__source_locations__video_item_id',
  );

  $$SourceLocationsTableProcessedTableManager get sourceLocationsRefs {
    final manager = $$SourceLocationsTableTableManager(
      $_db,
      $_db.sourceLocations,
    ).filter((f) => f.videoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sourceLocationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VideoTagsTable, List<VideoTag>>
  _videoTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.videoTags,
    aliasName: 'video_items__id__video_tags__video_item_id',
  );

  $$VideoTagsTableProcessedTableManager get videoTagsRefs {
    final manager = $$VideoTagsTableTableManager(
      $_db,
      $_db.videoTags,
    ).filter((f) => f.videoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_videoTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CollectionItemsTable, List<CollectionItem>>
  _collectionItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.collectionItems,
    aliasName: 'video_items__id__collection_items__video_item_id',
  );

  $$CollectionItemsTableProcessedTableManager get collectionItemsRefs {
    final manager = $$CollectionItemsTableTableManager(
      $_db,
      $_db.collectionItems,
    ).filter((f) => f.videoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _collectionItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $RecommendationExposuresTable,
    List<RecommendationExposure>
  >
  _recommendationExposuresRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.recommendationExposures,
        aliasName: 'video_items__id__recommendation_exposures__video_item_id',
      );

  $$RecommendationExposuresTableProcessedTableManager
  get recommendationExposuresRefs {
    final manager = $$RecommendationExposuresTableTableManager(
      $_db,
      $_db.recommendationExposures,
    ).filter((f) => f.videoItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recommendationExposuresRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VideoItemsTableFilterComposer
    extends Composer<_$AppDatabase, $VideoItemsTable> {
  $$VideoItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get widthPx => $composableBuilder(
    column: $table.widthPx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heightPx => $composableBuilder(
    column: $table.heightPx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavourite => $composableBuilder(
    column: $table.isFavourite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchProgressMs => $composableBuilder(
    column: $table.watchProgressMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sourceLocationsRefs(
    Expression<bool> Function($$SourceLocationsTableFilterComposer f) f,
  ) {
    final $$SourceLocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sourceLocations,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLocationsTableFilterComposer(
            $db: $db,
            $table: $db.sourceLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> videoTagsRefs(
    Expression<bool> Function($$VideoTagsTableFilterComposer f) f,
  ) {
    final $$VideoTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videoTags,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoTagsTableFilterComposer(
            $db: $db,
            $table: $db.videoTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> collectionItemsRefs(
    Expression<bool> Function($$CollectionItemsTableFilterComposer f) f,
  ) {
    final $$CollectionItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionItems,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionItemsTableFilterComposer(
            $db: $db,
            $table: $db.collectionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recommendationExposuresRefs(
    Expression<bool> Function($$RecommendationExposuresTableFilterComposer f) f,
  ) {
    final $$RecommendationExposuresTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recommendationExposures,
          getReferencedColumn: (t) => t.videoItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecommendationExposuresTableFilterComposer(
                $db: $db,
                $table: $db.recommendationExposures,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VideoItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $VideoItemsTable> {
  $$VideoItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get widthPx => $composableBuilder(
    column: $table.widthPx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heightPx => $composableBuilder(
    column: $table.heightPx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavourite => $composableBuilder(
    column: $table.isFavourite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchProgressMs => $composableBuilder(
    column: $table.watchProgressMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VideoItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VideoItemsTable> {
  $$VideoItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get widthPx =>
      $composableBuilder(column: $table.widthPx, builder: (column) => column);

  GeneratedColumn<int> get heightPx =>
      $composableBuilder(column: $table.heightPx, builder: (column) => column);

  GeneratedColumn<bool> get isFavourite => $composableBuilder(
    column: $table.isFavourite,
    builder: (column) => column,
  );

  GeneratedColumn<int> get watchProgressMs => $composableBuilder(
    column: $table.watchProgressMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> sourceLocationsRefs<T extends Object>(
    Expression<T> Function($$SourceLocationsTableAnnotationComposer a) f,
  ) {
    final $$SourceLocationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sourceLocations,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLocationsTableAnnotationComposer(
            $db: $db,
            $table: $db.sourceLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> videoTagsRefs<T extends Object>(
    Expression<T> Function($$VideoTagsTableAnnotationComposer a) f,
  ) {
    final $$VideoTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videoTags,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> collectionItemsRefs<T extends Object>(
    Expression<T> Function($$CollectionItemsTableAnnotationComposer a) f,
  ) {
    final $$CollectionItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionItems,
      getReferencedColumn: (t) => t.videoItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.collectionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recommendationExposuresRefs<T extends Object>(
    Expression<T> Function($$RecommendationExposuresTableAnnotationComposer a)
    f,
  ) {
    final $$RecommendationExposuresTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.recommendationExposures,
          getReferencedColumn: (t) => t.videoItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RecommendationExposuresTableAnnotationComposer(
                $db: $db,
                $table: $db.recommendationExposures,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VideoItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VideoItemsTable,
          VideoItem,
          $$VideoItemsTableFilterComposer,
          $$VideoItemsTableOrderingComposer,
          $$VideoItemsTableAnnotationComposer,
          $$VideoItemsTableCreateCompanionBuilder,
          $$VideoItemsTableUpdateCompanionBuilder,
          (VideoItem, $$VideoItemsTableReferences),
          VideoItem,
          PrefetchHooks Function({
            bool sourceLocationsRefs,
            bool videoTagsRefs,
            bool collectionItemsRefs,
            bool recommendationExposuresRefs,
          })
        > {
  $$VideoItemsTableTableManager(_$AppDatabase db, $VideoItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VideoItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VideoItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VideoItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> widthPx = const Value.absent(),
                Value<int?> heightPx = const Value.absent(),
                Value<bool> isFavourite = const Value.absent(),
                Value<int> watchProgressMs = const Value.absent(),
                Value<int?> lastPlayedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VideoItemsCompanion(
                id: id,
                title: title,
                durationMs: durationMs,
                widthPx: widthPx,
                heightPx: heightPx,
                isFavourite: isFavourite,
                watchProgressMs: watchProgressMs,
                lastPlayedAt: lastPlayedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<int?> durationMs = const Value.absent(),
                Value<int?> widthPx = const Value.absent(),
                Value<int?> heightPx = const Value.absent(),
                Value<bool> isFavourite = const Value.absent(),
                Value<int> watchProgressMs = const Value.absent(),
                Value<int?> lastPlayedAt = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => VideoItemsCompanion.insert(
                id: id,
                title: title,
                durationMs: durationMs,
                widthPx: widthPx,
                heightPx: heightPx,
                isFavourite: isFavourite,
                watchProgressMs: watchProgressMs,
                lastPlayedAt: lastPlayedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VideoItemsTable, VideoItem>(table),
                  $$VideoItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sourceLocationsRefs = false,
                videoTagsRefs = false,
                collectionItemsRefs = false,
                recommendationExposuresRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sourceLocationsRefs) db.sourceLocations,
                    if (videoTagsRefs) db.videoTags,
                    if (collectionItemsRefs) db.collectionItems,
                    if (recommendationExposuresRefs) db.recommendationExposures,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sourceLocationsRefs)
                        await $_getPrefetchedData<
                          VideoItem,
                          $VideoItemsTable,
                          SourceLocation
                        >(
                          currentTable: table,
                          referencedTable: $$VideoItemsTableReferences
                              ._sourceLocationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VideoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).sourceLocationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.videoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (videoTagsRefs)
                        await $_getPrefetchedData<
                          VideoItem,
                          $VideoItemsTable,
                          VideoTag
                        >(
                          currentTable: table,
                          referencedTable: $$VideoItemsTableReferences
                              ._videoTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VideoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).videoTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.videoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (collectionItemsRefs)
                        await $_getPrefetchedData<
                          VideoItem,
                          $VideoItemsTable,
                          CollectionItem
                        >(
                          currentTable: table,
                          referencedTable: $$VideoItemsTableReferences
                              ._collectionItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VideoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).collectionItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.videoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recommendationExposuresRefs)
                        await $_getPrefetchedData<
                          VideoItem,
                          $VideoItemsTable,
                          RecommendationExposure
                        >(
                          currentTable: table,
                          referencedTable: $$VideoItemsTableReferences
                              ._recommendationExposuresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VideoItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).recommendationExposuresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.videoItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$VideoItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VideoItemsTable,
      VideoItem,
      $$VideoItemsTableFilterComposer,
      $$VideoItemsTableOrderingComposer,
      $$VideoItemsTableAnnotationComposer,
      $$VideoItemsTableCreateCompanionBuilder,
      $$VideoItemsTableUpdateCompanionBuilder,
      (VideoItem, $$VideoItemsTableReferences),
      VideoItem,
      PrefetchHooks Function({
        bool sourceLocationsRefs,
        bool videoTagsRefs,
        bool collectionItemsRefs,
        bool recommendationExposuresRefs,
      })
    >;
typedef $$SourceLocationsTableCreateCompanionBuilder =
    SourceLocationsCompanion Function({
      required String id,
      required String videoItemId,
      required String providerType,
      required String sourceId,
      Value<String?> displayName,
      Value<String?> mimeType,
      Value<int?> sizeBytes,
      Value<String?> thumbnailUri,
      Value<String> availability,
      Value<int?> lastCheckedAt,
      Value<bool> isPrimary,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SourceLocationsTableUpdateCompanionBuilder =
    SourceLocationsCompanion Function({
      Value<String> id,
      Value<String> videoItemId,
      Value<String> providerType,
      Value<String> sourceId,
      Value<String?> displayName,
      Value<String?> mimeType,
      Value<int?> sizeBytes,
      Value<String?> thumbnailUri,
      Value<String> availability,
      Value<int?> lastCheckedAt,
      Value<bool> isPrimary,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$SourceLocationsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SourceLocationsTable, SourceLocation> {
  $$SourceLocationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VideoItemsTable _videoItemIdTable(_$AppDatabase db) => db.videoItems
      .createAlias('source_locations__video_item_id__video_items__id');

  $$VideoItemsTableProcessedTableManager get videoItemId {
    final $_column = $_itemColumn<String>('video_item_id')!;

    final manager = $$VideoItemsTableTableManager(
      $_db,
      $_db.videoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_videoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SourceLocationsTableFilterComposer
    extends Composer<_$AppDatabase, $SourceLocationsTable> {
  $$SourceLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUri => $composableBuilder(
    column: $table.thumbnailUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$VideoItemsTableFilterComposer get videoItemId {
    final $$VideoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableFilterComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SourceLocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceLocationsTable> {
  $$SourceLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUri => $composableBuilder(
    column: $table.thumbnailUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$VideoItemsTableOrderingComposer get videoItemId {
    final $$VideoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SourceLocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceLocationsTable> {
  $$SourceLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get thumbnailUri => $composableBuilder(
    column: $table.thumbnailUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$VideoItemsTableAnnotationComposer get videoItemId {
    final $$VideoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SourceLocationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceLocationsTable,
          SourceLocation,
          $$SourceLocationsTableFilterComposer,
          $$SourceLocationsTableOrderingComposer,
          $$SourceLocationsTableAnnotationComposer,
          $$SourceLocationsTableCreateCompanionBuilder,
          $$SourceLocationsTableUpdateCompanionBuilder,
          (SourceLocation, $$SourceLocationsTableReferences),
          SourceLocation,
          PrefetchHooks Function({bool videoItemId})
        > {
  $$SourceLocationsTableTableManager(
    _$AppDatabase db,
    $SourceLocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceLocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceLocationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourceLocationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> videoItemId = const Value.absent(),
                Value<String> providerType = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> thumbnailUri = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<int?> lastCheckedAt = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceLocationsCompanion(
                id: id,
                videoItemId: videoItemId,
                providerType: providerType,
                sourceId: sourceId,
                displayName: displayName,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                thumbnailUri: thumbnailUri,
                availability: availability,
                lastCheckedAt: lastCheckedAt,
                isPrimary: isPrimary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String videoItemId,
                required String providerType,
                required String sourceId,
                Value<String?> displayName = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> thumbnailUri = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<int?> lastCheckedAt = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SourceLocationsCompanion.insert(
                id: id,
                videoItemId: videoItemId,
                providerType: providerType,
                sourceId: sourceId,
                displayName: displayName,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                thumbnailUri: thumbnailUri,
                availability: availability,
                lastCheckedAt: lastCheckedAt,
                isPrimary: isPrimary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourceLocationsTable, SourceLocation>(table),
                  $$SourceLocationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({videoItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (videoItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.videoItemId,
                                referencedTable:
                                    $$SourceLocationsTableReferences
                                        ._videoItemIdTable(db),
                                referencedColumn:
                                    $$SourceLocationsTableReferences
                                        ._videoItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SourceLocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceLocationsTable,
      SourceLocation,
      $$SourceLocationsTableFilterComposer,
      $$SourceLocationsTableOrderingComposer,
      $$SourceLocationsTableAnnotationComposer,
      $$SourceLocationsTableCreateCompanionBuilder,
      $$SourceLocationsTableUpdateCompanionBuilder,
      (SourceLocation, $$SourceLocationsTableReferences),
      SourceLocation,
      PrefetchHooks Function({bool videoItemId})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, Tag> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$VideoTagsTable, List<VideoTag>>
  _videoTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.videoTags,
    aliasName: 'tags__id__video_tags__tag_id',
  );

  $$VideoTagsTableProcessedTableManager get videoTagsRefs {
    final manager = $$VideoTagsTableTableManager(
      $_db,
      $_db.videoTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_videoTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> videoTagsRefs(
    Expression<bool> Function($$VideoTagsTableFilterComposer f) f,
  ) {
    final $$VideoTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videoTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoTagsTableFilterComposer(
            $db: $db,
            $table: $db.videoTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> videoTagsRefs<T extends Object>(
    Expression<T> Function($$VideoTagsTableAnnotationComposer a) f,
  ) {
    final $$VideoTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videoTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, $$TagsTableReferences),
          Tag,
          PrefetchHooks Function({bool videoTagsRefs})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TagsTable, Tag>(table),
                  $$TagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({videoTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (videoTagsRefs) db.videoTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (videoTagsRefs)
                    await $_getPrefetchedData<Tag, $TagsTable, VideoTag>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._videoTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).videoTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, $$TagsTableReferences),
      Tag,
      PrefetchHooks Function({bool videoTagsRefs})
    >;
typedef $$VideoTagsTableCreateCompanionBuilder =
    VideoTagsCompanion Function({
      required String videoItemId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$VideoTagsTableUpdateCompanionBuilder =
    VideoTagsCompanion Function({
      Value<String> videoItemId,
      Value<String> tagId,
      Value<int> rowid,
    });

final class $$VideoTagsTableReferences
    extends BaseReferences<_$AppDatabase, $VideoTagsTable, VideoTag> {
  $$VideoTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $VideoItemsTable _videoItemIdTable(_$AppDatabase db) =>
      db.videoItems.createAlias('video_tags__video_item_id__video_items__id');

  $$VideoItemsTableProcessedTableManager get videoItemId {
    final $_column = $_itemColumn<String>('video_item_id')!;

    final manager = $$VideoItemsTableTableManager(
      $_db,
      $_db.videoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_videoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias('video_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$VideoTagsTableFilterComposer
    extends Composer<_$AppDatabase, $VideoTagsTable> {
  $$VideoTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$VideoItemsTableFilterComposer get videoItemId {
    final $$VideoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableFilterComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VideoTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $VideoTagsTable> {
  $$VideoTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$VideoItemsTableOrderingComposer get videoItemId {
    final $$VideoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VideoTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VideoTagsTable> {
  $$VideoTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$VideoItemsTableAnnotationComposer get videoItemId {
    final $$VideoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VideoTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VideoTagsTable,
          VideoTag,
          $$VideoTagsTableFilterComposer,
          $$VideoTagsTableOrderingComposer,
          $$VideoTagsTableAnnotationComposer,
          $$VideoTagsTableCreateCompanionBuilder,
          $$VideoTagsTableUpdateCompanionBuilder,
          (VideoTag, $$VideoTagsTableReferences),
          VideoTag,
          PrefetchHooks Function({bool videoItemId, bool tagId})
        > {
  $$VideoTagsTableTableManager(_$AppDatabase db, $VideoTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VideoTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VideoTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VideoTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> videoItemId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VideoTagsCompanion(
                videoItemId: videoItemId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoItemId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => VideoTagsCompanion.insert(
                videoItemId: videoItemId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VideoTagsTable, VideoTag>(table),
                  $$VideoTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({videoItemId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (videoItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.videoItemId,
                                referencedTable: $$VideoTagsTableReferences
                                    ._videoItemIdTable(db),
                                referencedColumn: $$VideoTagsTableReferences
                                    ._videoItemIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$VideoTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$VideoTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$VideoTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VideoTagsTable,
      VideoTag,
      $$VideoTagsTableFilterComposer,
      $$VideoTagsTableOrderingComposer,
      $$VideoTagsTableAnnotationComposer,
      $$VideoTagsTableCreateCompanionBuilder,
      $$VideoTagsTableUpdateCompanionBuilder,
      (VideoTag, $$VideoTagsTableReferences),
      VideoTag,
      PrefetchHooks Function({bool videoItemId, bool tagId})
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      required int createdAt,
      required int updatedAt,
      Value<bool> isPinned,
      Value<int?> pinnedAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> isPinned,
      Value<int?> pinnedAt,
      Value<int> rowid,
    });

final class $$CollectionsTableReferences
    extends BaseReferences<_$AppDatabase, $CollectionsTable, Collection> {
  $$CollectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CollectionItemsTable, List<CollectionItem>>
  _collectionItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.collectionItems,
    aliasName: 'collections__id__collection_items__collection_id',
  );

  $$CollectionItemsTableProcessedTableManager get collectionItemsRefs {
    final manager = $$CollectionItemsTableTableManager(
      $_db,
      $_db.collectionItems,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _collectionItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CollectionsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> collectionItemsRefs(
    Expression<bool> Function($$CollectionItemsTableFilterComposer f) f,
  ) {
    final $$CollectionItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionItems,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionItemsTableFilterComposer(
            $db: $db,
            $table: $db.collectionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  Expression<T> collectionItemsRefs<T extends Object>(
    Expression<T> Function($$CollectionItemsTableAnnotationComposer a) f,
  ) {
    final $$CollectionItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.collectionItems,
      getReferencedColumn: (t) => t.collectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.collectionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionsTable,
          Collection,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (Collection, $$CollectionsTableReferences),
          Collection,
          PrefetchHooks Function({bool collectionItemsRefs})
        > {
  $$CollectionsTableTableManager(_$AppDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int?> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<bool> isPinned = const Value.absent(),
                Value<int?> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionsTable, Collection>(table),
                  $$CollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (collectionItemsRefs) db.collectionItems,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (collectionItemsRefs)
                    await $_getPrefetchedData<
                      Collection,
                      $CollectionsTable,
                      CollectionItem
                    >(
                      currentTable: table,
                      referencedTable: $$CollectionsTableReferences
                          ._collectionItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CollectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).collectionItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.collectionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionsTable,
      Collection,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (Collection, $$CollectionsTableReferences),
      Collection,
      PrefetchHooks Function({bool collectionItemsRefs})
    >;
typedef $$CollectionItemsTableCreateCompanionBuilder =
    CollectionItemsCompanion Function({
      required String collectionId,
      required String videoItemId,
      Value<int> sortOrder,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$CollectionItemsTableUpdateCompanionBuilder =
    CollectionItemsCompanion Function({
      Value<String> collectionId,
      Value<String> videoItemId,
      Value<int> sortOrder,
      Value<int> addedAt,
      Value<int> rowid,
    });

final class $$CollectionItemsTableReferences
    extends
        BaseReferences<_$AppDatabase, $CollectionItemsTable, CollectionItem> {
  $$CollectionItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) => db
      .collections
      .createAlias('collection_items__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<String>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VideoItemsTable _videoItemIdTable(_$AppDatabase db) => db.videoItems
      .createAlias('collection_items__video_item_id__video_items__id');

  $$VideoItemsTableProcessedTableManager get videoItemId {
    final $_column = $_itemColumn<String>('video_item_id')!;

    final manager = $$VideoItemsTableTableManager(
      $_db,
      $_db.videoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_videoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CollectionItemsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionItemsTable> {
  $$CollectionItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VideoItemsTableFilterComposer get videoItemId {
    final $$VideoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableFilterComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionItemsTable> {
  $$CollectionItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VideoItemsTableOrderingComposer get videoItemId {
    final $$VideoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionItemsTable> {
  $$CollectionItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VideoItemsTableAnnotationComposer get videoItemId {
    final $$VideoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CollectionItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionItemsTable,
          CollectionItem,
          $$CollectionItemsTableFilterComposer,
          $$CollectionItemsTableOrderingComposer,
          $$CollectionItemsTableAnnotationComposer,
          $$CollectionItemsTableCreateCompanionBuilder,
          $$CollectionItemsTableUpdateCompanionBuilder,
          (CollectionItem, $$CollectionItemsTableReferences),
          CollectionItem,
          PrefetchHooks Function({bool collectionId, bool videoItemId})
        > {
  $$CollectionItemsTableTableManager(
    _$AppDatabase db,
    $CollectionItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> collectionId = const Value.absent(),
                Value<String> videoItemId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionItemsCompanion(
                collectionId: collectionId,
                videoItemId: videoItemId,
                sortOrder: sortOrder,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String collectionId,
                required String videoItemId,
                Value<int> sortOrder = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => CollectionItemsCompanion.insert(
                collectionId: collectionId,
                videoItemId: videoItemId,
                sortOrder: sortOrder,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionItemsTable, CollectionItem>(table),
                  $$CollectionItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({collectionId = false, videoItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable:
                                    $$CollectionItemsTableReferences
                                        ._collectionIdTable(db),
                                referencedColumn:
                                    $$CollectionItemsTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (videoItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.videoItemId,
                                referencedTable:
                                    $$CollectionItemsTableReferences
                                        ._videoItemIdTable(db),
                                referencedColumn:
                                    $$CollectionItemsTableReferences
                                        ._videoItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CollectionItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionItemsTable,
      CollectionItem,
      $$CollectionItemsTableFilterComposer,
      $$CollectionItemsTableOrderingComposer,
      $$CollectionItemsTableAnnotationComposer,
      $$CollectionItemsTableCreateCompanionBuilder,
      $$CollectionItemsTableUpdateCompanionBuilder,
      (CollectionItem, $$CollectionItemsTableReferences),
      CollectionItem,
      PrefetchHooks Function({bool collectionId, bool videoItemId})
    >;
typedef $$AppPreferencesTableCreateCompanionBuilder =
    AppPreferencesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppPreferencesTableUpdateCompanionBuilder =
    AppPreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppPreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppPreferencesTable,
          AppPreference,
          $$AppPreferencesTableFilterComposer,
          $$AppPreferencesTableOrderingComposer,
          $$AppPreferencesTableAnnotationComposer,
          $$AppPreferencesTableCreateCompanionBuilder,
          $$AppPreferencesTableUpdateCompanionBuilder,
          (
            AppPreference,
            BaseReferences<_$AppDatabase, $AppPreferencesTable, AppPreference>,
          ),
          AppPreference,
          PrefetchHooks Function()
        > {
  $$AppPreferencesTableTableManager(
    _$AppDatabase db,
    $AppPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  AppPreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppPreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppPreferencesTable, AppPreference>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppPreferencesTable,
                    AppPreference
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppPreferencesTable,
      AppPreference,
      $$AppPreferencesTableFilterComposer,
      $$AppPreferencesTableOrderingComposer,
      $$AppPreferencesTableAnnotationComposer,
      $$AppPreferencesTableCreateCompanionBuilder,
      $$AppPreferencesTableUpdateCompanionBuilder,
      (
        AppPreference,
        BaseReferences<_$AppDatabase, $AppPreferencesTable, AppPreference>,
      ),
      AppPreference,
      PrefetchHooks Function()
    >;
typedef $$RecommendationExposuresTableCreateCompanionBuilder =
    RecommendationExposuresCompanion Function({
      required String videoItemId,
      required String sessionId,
      required int firstExposedAt,
      required int lastExposedAt,
      Value<int> rowid,
    });
typedef $$RecommendationExposuresTableUpdateCompanionBuilder =
    RecommendationExposuresCompanion Function({
      Value<String> videoItemId,
      Value<String> sessionId,
      Value<int> firstExposedAt,
      Value<int> lastExposedAt,
      Value<int> rowid,
    });

final class $$RecommendationExposuresTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RecommendationExposuresTable,
          RecommendationExposure
        > {
  $$RecommendationExposuresTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VideoItemsTable _videoItemIdTable(_$AppDatabase db) => db.videoItems
      .createAlias('recommendation_exposures__video_item_id__video_items__id');

  $$VideoItemsTableProcessedTableManager get videoItemId {
    final $_column = $_itemColumn<String>('video_item_id')!;

    final manager = $$VideoItemsTableTableManager(
      $_db,
      $_db.videoItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_videoItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecommendationExposuresTableFilterComposer
    extends Composer<_$AppDatabase, $RecommendationExposuresTable> {
  $$RecommendationExposuresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstExposedAt => $composableBuilder(
    column: $table.firstExposedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastExposedAt => $composableBuilder(
    column: $table.lastExposedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$VideoItemsTableFilterComposer get videoItemId {
    final $$VideoItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableFilterComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecommendationExposuresTableOrderingComposer
    extends Composer<_$AppDatabase, $RecommendationExposuresTable> {
  $$RecommendationExposuresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstExposedAt => $composableBuilder(
    column: $table.firstExposedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastExposedAt => $composableBuilder(
    column: $table.lastExposedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$VideoItemsTableOrderingComposer get videoItemId {
    final $$VideoItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableOrderingComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecommendationExposuresTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecommendationExposuresTable> {
  $$RecommendationExposuresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get firstExposedAt => $composableBuilder(
    column: $table.firstExposedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastExposedAt => $composableBuilder(
    column: $table.lastExposedAt,
    builder: (column) => column,
  );

  $$VideoItemsTableAnnotationComposer get videoItemId {
    final $$VideoItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoItemId,
      referencedTable: $db.videoItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideoItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.videoItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecommendationExposuresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecommendationExposuresTable,
          RecommendationExposure,
          $$RecommendationExposuresTableFilterComposer,
          $$RecommendationExposuresTableOrderingComposer,
          $$RecommendationExposuresTableAnnotationComposer,
          $$RecommendationExposuresTableCreateCompanionBuilder,
          $$RecommendationExposuresTableUpdateCompanionBuilder,
          (RecommendationExposure, $$RecommendationExposuresTableReferences),
          RecommendationExposure,
          PrefetchHooks Function({bool videoItemId})
        > {
  $$RecommendationExposuresTableTableManager(
    _$AppDatabase db,
    $RecommendationExposuresTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecommendationExposuresTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RecommendationExposuresTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RecommendationExposuresTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> videoItemId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> firstExposedAt = const Value.absent(),
                Value<int> lastExposedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecommendationExposuresCompanion(
                videoItemId: videoItemId,
                sessionId: sessionId,
                firstExposedAt: firstExposedAt,
                lastExposedAt: lastExposedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String videoItemId,
                required String sessionId,
                required int firstExposedAt,
                required int lastExposedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecommendationExposuresCompanion.insert(
                videoItemId: videoItemId,
                sessionId: sessionId,
                firstExposedAt: firstExposedAt,
                lastExposedAt: lastExposedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $RecommendationExposuresTable,
                    RecommendationExposure
                  >(table),
                  $$RecommendationExposuresTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({videoItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (videoItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.videoItemId,
                                referencedTable:
                                    $$RecommendationExposuresTableReferences
                                        ._videoItemIdTable(db),
                                referencedColumn:
                                    $$RecommendationExposuresTableReferences
                                        ._videoItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RecommendationExposuresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecommendationExposuresTable,
      RecommendationExposure,
      $$RecommendationExposuresTableFilterComposer,
      $$RecommendationExposuresTableOrderingComposer,
      $$RecommendationExposuresTableAnnotationComposer,
      $$RecommendationExposuresTableCreateCompanionBuilder,
      $$RecommendationExposuresTableUpdateCompanionBuilder,
      (RecommendationExposure, $$RecommendationExposuresTableReferences),
      RecommendationExposure,
      PrefetchHooks Function({bool videoItemId})
    >;
typedef $$DownloadsTableCreateCompanionBuilder =
    DownloadsCompanion Function({
      required String id,
      required String videoItemId,
      Value<String?> sourceLocationId,
      required String providerType,
      required String sourceUri,
      required String fileName,
      Value<int?> sizeBytes,
      Value<int> downloadedBytes,
      Value<String> status,
      Value<bool> acceptsRange,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$DownloadsTableUpdateCompanionBuilder =
    DownloadsCompanion Function({
      Value<String> id,
      Value<String> videoItemId,
      Value<String?> sourceLocationId,
      Value<String> providerType,
      Value<String> sourceUri,
      Value<String> fileName,
      Value<int?> sizeBytes,
      Value<int> downloadedBytes,
      Value<String> status,
      Value<bool> acceptsRange,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$DownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoItemId => $composableBuilder(
    column: $table.videoItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLocationId => $composableBuilder(
    column: $table.sourceLocationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUri => $composableBuilder(
    column: $table.sourceUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get acceptsRange => $composableBuilder(
    column: $table.acceptsRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoItemId => $composableBuilder(
    column: $table.videoItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLocationId => $composableBuilder(
    column: $table.sourceLocationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUri => $composableBuilder(
    column: $table.sourceUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get acceptsRange => $composableBuilder(
    column: $table.acceptsRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get videoItemId => $composableBuilder(
    column: $table.videoItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLocationId => $composableBuilder(
    column: $table.sourceLocationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceUri =>
      $composableBuilder(column: $table.sourceUri, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get acceptsRange => $composableBuilder(
    column: $table.acceptsRange,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DownloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadsTable,
          Download,
          $$DownloadsTableFilterComposer,
          $$DownloadsTableOrderingComposer,
          $$DownloadsTableAnnotationComposer,
          $$DownloadsTableCreateCompanionBuilder,
          $$DownloadsTableUpdateCompanionBuilder,
          (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
          Download,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableManager(_$AppDatabase db, $DownloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> videoItemId = const Value.absent(),
                Value<String?> sourceLocationId = const Value.absent(),
                Value<String> providerType = const Value.absent(),
                Value<String> sourceUri = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<int> downloadedBytes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> acceptsRange = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion(
                id: id,
                videoItemId: videoItemId,
                sourceLocationId: sourceLocationId,
                providerType: providerType,
                sourceUri: sourceUri,
                fileName: fileName,
                sizeBytes: sizeBytes,
                downloadedBytes: downloadedBytes,
                status: status,
                acceptsRange: acceptsRange,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String videoItemId,
                Value<String?> sourceLocationId = const Value.absent(),
                required String providerType,
                required String sourceUri,
                required String fileName,
                Value<int?> sizeBytes = const Value.absent(),
                Value<int> downloadedBytes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> acceptsRange = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion.insert(
                id: id,
                videoItemId: videoItemId,
                sourceLocationId: sourceLocationId,
                providerType: providerType,
                sourceUri: sourceUri,
                fileName: fileName,
                sizeBytes: sizeBytes,
                downloadedBytes: downloadedBytes,
                status: status,
                acceptsRange: acceptsRange,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DownloadsTable, Download>(table),
                  BaseReferences<_$AppDatabase, $DownloadsTable, Download>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadsTable,
      Download,
      $$DownloadsTableFilterComposer,
      $$DownloadsTableOrderingComposer,
      $$DownloadsTableAnnotationComposer,
      $$DownloadsTableCreateCompanionBuilder,
      $$DownloadsTableUpdateCompanionBuilder,
      (Download, BaseReferences<_$AppDatabase, $DownloadsTable, Download>),
      Download,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$VideoItemsTableTableManager get videoItems =>
      $$VideoItemsTableTableManager(_db, _db.videoItems);
  $$SourceLocationsTableTableManager get sourceLocations =>
      $$SourceLocationsTableTableManager(_db, _db.sourceLocations);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$VideoTagsTableTableManager get videoTags =>
      $$VideoTagsTableTableManager(_db, _db.videoTags);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$CollectionItemsTableTableManager get collectionItems =>
      $$CollectionItemsTableTableManager(_db, _db.collectionItems);
  $$AppPreferencesTableTableManager get appPreferences =>
      $$AppPreferencesTableTableManager(_db, _db.appPreferences);
  $$RecommendationExposuresTableTableManager get recommendationExposures =>
      $$RecommendationExposuresTableTableManager(
        _db,
        _db.recommendationExposures,
      );
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
}
