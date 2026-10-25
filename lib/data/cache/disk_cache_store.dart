import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/domain/models/app_error.dart';

/// A disposable, key-addressed byte store confined to one directory
/// (ARCHITECTURE §10, P8-01).
///
/// The contract is what keeps cache cleanup safe: every implementation only
/// ever touches regular files it created itself (its own [FileDiskCacheStore.filePrefix])
/// directly inside its own root, so Clear Cache and eviction can never follow a
/// path into downloads or into an original video. Methods never throw; failures
/// come back as [Err] so callers can degrade instead of crashing.
abstract interface class DiskCacheStore {
  /// Total size and entry count of the managed entries.
  Future<Result<CacheUsage>> usage();

  /// Returns the bytes stored for [key], or `Result.ok(null)` on a miss.
  Future<Result<Uint8List?>> read(String key);

  /// Writes [bytes] for [key], atomically replacing any existing entry.
  Future<Result<void>> write(String key, Uint8List bytes);

  /// Deletes every managed entry (and any interrupted write). Returns the
  /// number of bytes freed. Files the store did not create are left alone.
  Future<Result<int>> clear();

  /// Deletes least-recently-used entries until the store fits in [maxBytes].
  /// Returns the number of bytes freed (`0` when already inside the budget).
  Future<Result<int>> evictToBudget(int maxBytes);
}

/// [DiskCacheStore] writing one file per key inside [root] (P8-01).
///
/// Details that matter:
/// * **Keys are hashed, never written to disk.** Keys are thumbnail URLs and
///   content URIs; a signed URL's query string must not end up in a filename
///   that a backup or a file browser can read (SEC-005).
/// * **Writes are atomic.** Bytes go to a temp file first and are renamed into
///   place, so an interrupted or concurrent write never leaves a truncated
///   entry that would decode as a corrupt image.
/// * **Recency is the file mtime**, refreshed on every read, which gives
///   eviction a cheapest-to-lose ordering without a second metadata store.
/// * **Only files matching the prefix are managed.** Anything else in the
///   directory (including subdirectories) is invisible to usage, clear, and
///   eviction.
class FileDiskCacheStore implements DiskCacheStore {
  FileDiskCacheStore({required this.root, this.filePrefix = 'thumb_'});

  /// Directory owned by this store. Created on first write.
  final String root;

  /// Marker for files this store created; also the safety fence for cleanup.
  final String filePrefix;

  static const String _entrySuffix = '.bin';
  static const String _tempPrefix = 'tmp_';
  static const String _tempSuffix = '.part';

  Directory get _directory => Directory(root);

  /// Absolute path of the file backing [key]. Exposed for diagnostics and for
  /// tests that need to pin an entry's recency; callers must not write through
  /// it, because a direct write bypasses the atomic temp-file swap.
  String entryPathFor(String key) => _fileFor(key).path;

  @override
  Future<Result<CacheUsage>> usage() async {
    try {
      final dir = _directory;
      if (!await dir.exists()) return Result.ok(CacheUsage.empty);
      var bytes = 0;
      var count = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !_isManagedName(p.basename(entity.path))) {
          continue;
        }
        final length = await _lengthOrZero(entity);
        if (length == null) continue; // Vanished mid-listing.
        bytes += length;
        count++;
      }
      return Result.ok(CacheUsage(bytes: bytes, entryCount: count));
    } catch (e) {
      return Result.err(_failure('cache usage failed', e));
    }
  }

  @override
  Future<Result<Uint8List?>> read(String key) async {
    final file = _fileFor(key);
    try {
      final bytes = await file.readAsBytes();
      await _touch(file);
      return Result.ok(bytes);
    } on PathNotFoundException {
      return Result.ok(null);
    } on FileSystemException catch (e) {
      // A racing clear() can remove the file between the open and the read;
      // that is a miss, not a cache failure.
      if (!await file.exists()) return Result.ok(null);
      return Result.err(_failure('cache read failed', e));
    } catch (e) {
      return Result.err(_failure('cache read failed', e));
    }
  }

  @override
  Future<Result<void>> write(String key, Uint8List bytes) async {
    final target = _fileFor(key);
    final temp = File(
      p.join(root, '$_tempPrefix${p.basename(target.path)}$_tempSuffix'),
    );
    try {
      await _directory.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
      return Result.ok(null);
    } catch (e) {
      await _deleteQuietly(temp);
      return Result.err(_failure('cache write failed', e));
    }
  }

  @override
  Future<Result<int>> clear() async {
    try {
      final dir = _directory;
      if (!await dir.exists()) return Result.ok(0);
      var freed = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!_isManagedName(name) && !_isStaleTempName(name)) continue;
        final length = await _lengthOrZero(entity) ?? 0;
        await _deleteQuietly(entity);
        freed += length;
      }
      return Result.ok(freed);
    } catch (e) {
      return Result.err(_failure('cache clear failed', e));
    }
  }

  @override
  Future<Result<int>> evictToBudget(int maxBytes) async {
    try {
      final dir = _directory;
      if (!await dir.exists()) return Result.ok(0);

      final entries = <_Entry>[];
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !_isManagedName(p.basename(entity.path))) {
          continue;
        }
        try {
          final length = await entity.length();
          final touchedAt = await entity.lastModified();
          entries.add(_Entry(entity, length, touchedAt));
          total += length;
        } on FileSystemException {
          continue; // Vanished mid-listing (concurrent clear).
        }
      }
      if (total <= maxBytes) return Result.ok(0);

      entries.sort(_oldestFirst);
      var freed = 0;
      for (final entry in entries) {
        if (total <= maxBytes) break;
        await _deleteQuietly(entry.file);
        total -= entry.length;
        freed += entry.length;
      }
      return Result.ok(freed);
    } catch (e) {
      return Result.err(_failure('cache eviction failed', e));
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  File _fileFor(String key) => File(p.join(root, _fileNameFor(key)));

  String _fileNameFor(String key) => '$filePrefix${_hashKey(key)}$_entrySuffix';

  bool _isManagedName(String name) =>
      name.startsWith(filePrefix) && name.endsWith(_entrySuffix);

  static bool _isStaleTempName(String name) =>
      name.startsWith(_tempPrefix) && name.endsWith(_tempSuffix);

  /// Least-recently-used first; ties break on path so eviction order is
  /// deterministic even when several entries share a timestamp.
  static int _oldestFirst(_Entry a, _Entry b) {
    final byTime = a.touchedAt.compareTo(b.touchedAt);
    return byTime != 0 ? byTime : a.file.path.compareTo(b.file.path);
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(clock.now());
    } catch (_) {
      // Recency is an optimisation; a failed touch only skews eviction order.
    }
  }

  static Future<int?> _lengthOrZero(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone, or a permission the OS will reclaim on its own.
    }
  }

  static UnexpectedError _failure(String what, Object error) =>
      UnexpectedError(diagnosticMessage: '$what: $error', cause: error);

  /// 128-bit FNV-1a over the key's UTF-16 code units, rendered as 32 hex
  /// characters. Two independent offset bases keep accidental collisions out
  /// of the "wrong thumbnail" range while staying dependency-free and
  /// deterministic across runs and platforms.
  static String _hashKey(String key) {
    const prime = 0x100000001b3;
    var h1 = 0xcbf29ce484222325;
    var h2 = 0x84222325cbf29ce4;
    for (final unit in key.codeUnits) {
      h1 = (h1 ^ unit) * prime;
      h2 = (h2 ^ unit) * prime;
    }
    return '${_hex32(h1)}${_hex32(h2)}';
  }

  /// Unsigned 32-bit hex of both halves of a 64-bit hash (Dart ints are signed,
  /// so the halves are masked before formatting).
  static String _hex32(int value) {
    final high = (value >> 32) & 0xFFFFFFFF;
    final low = value & 0xFFFFFFFF;
    return high.toRadixString(16).padLeft(8, '0') +
        low.toRadixString(16).padLeft(8, '0');
  }
}

/// One managed entry, as seen by eviction.
class _Entry {
  _Entry(this.file, this.length, this.touchedAt);

  final File file;
  final int length;
  final DateTime touchedAt;
}
