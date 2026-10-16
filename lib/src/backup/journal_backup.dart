import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/journal_store.dart';

enum RestoreMode { merge, replace }

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Only the decoder can construct a validated snapshot. No archive paths are
/// extracted onto disk; media receives fresh, app-owned filenames on restore.
class ValidatedBackup {
  ValidatedBackup._(this._data, this._media, this.createdAt);
  final Map<String, List<Map<String, Object?>>> _data;
  final Map<String, Uint8List> _media;
  final String createdAt;
  int get places => _data['places']!.length;
  int get collections => _data['collections']!.length;
  int get routes => _data['routes']!.length;
  int get photos => _data['attachments']!.length;
}

const _tables = [...portableTables, 'collection_places'];
const maxBackupBytes = 128 * 1024 * 1024;
const _maxExpanded = 256 * 1024 * 1024;
const _maxFile = 32 * 1024 * 1024;
const _maxEntries = 10002;
final _mediaName = RegExp(r'^media/[a-f0-9]{64}(\.[a-z0-9]{1,8})?$');
final _identity = RegExp(r'^[a-f0-9]{32}$');

class JournalBackup {
  JournalBackup(this.store);
  final JournalStore store;

  /// Read files while holding the SQLite snapshot, before a concurrent delete
  /// can commit and clean them up. A missing photo fails the whole export.
  Future<Uint8List> exportZip() async {
    final media = <String, Uint8List>{};
    final data = await store.db.transaction((txn) async {
      final result = <String, List<Map<String, Object?>>>{};
      var expanded = 0;
      Future<String> pack(String path) async {
        final file = store.storage.resolve(path);
        final length = await file.length();
        if (length > _maxFile) {
          throw const BackupException('A photo exceeds the 32 MB file limit.');
        }
        final bytes = await file.readAsBytes();
        var extension = p.extension(path).toLowerCase();
        if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) extension = '';
        final key = 'media/${sha256.convert(bytes)}$extension';
        if (!media.containsKey(key)) {
          expanded += bytes.length;
          if (expanded > _maxExpanded || media.length >= _maxEntries - 2) {
            throw const BackupException(
              'Journal exceeds the backup size limit.',
            );
          }
          media[key] = bytes;
        }
        return key;
      }

      for (final table in _tables) {
        final rows = (await txn.query(
          table,
        )).map((r) => Map<String, Object?>.of(r)).toList();
        for (final row in rows) {
          if (table == 'attachments') {
            row['relative_path'] = await pack(row['relative_path'] as String);
          } else if (table == 'collections' && row['cover_path'] != null) {
            row['cover_path'] = await pack(row['cover_path'] as String);
          }
        }
        result[table] = rows;
      }
      return result;
    });
    return Isolate.run(() => _encode(data, media));
  }

  static Future<ValidatedBackup> readFile(File file) async {
    if (await file.length() > maxBackupBytes) {
      throw const BackupException('Backup exceeds the 128 MB archive limit.');
    }
    return decode(await file.readAsBytes());
  }

  static Future<ValidatedBackup> decode(Uint8List bytes) =>
      Isolate.run(() => _decode(bytes));

  /// Merge keeps local fields for matching portable IDs, adds missing records,
  /// and unions memberships/photos. Existing route plans remain intact.
  /// Replace removes records only inside the same transaction as the inserts.
  Future<void> restore(ValidatedBackup backup, RestoreMode mode) async {
    final paths = <String, String>{};
    final staged = <String, Uint8List>{};
    try {
      await store.storage.root.create(recursive: true);
      for (final table in ['attachments', 'collections']) {
        for (final row in backup._data[table]!) {
          final media =
              row[table == 'attachments' ? 'relative_path' : 'cover_path']
                  as String?;
          if (media == null) continue;
          final name =
              'restore_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}${p.extension(media)}';
          // Register before writing: interrupted imports are cleaned on reopen.
          await store.db.insert('attachment_cleanup', {'relative_path': name});
          paths['$table:${row['id']}'] = name;
          staged[name] = backup._media[media]!;
        }
      }
      await store.db.transaction((txn) async {
        // Holding the database lock also prevents another save's cleanup from
        // deleting queued staging files before their references are committed.
        for (final entry in staged.entries) {
          await store.storage
              .resolve(entry.key)
              .writeAsBytes(entry.value, flush: true);
        }
        if (mode == RestoreMode.replace) {
          for (final row in await txn.query('attachments')) {
            await _queue(txn, row['relative_path'] as String);
          }
          for (final row in await txn.query('collections')) {
            if (row['cover_path'] != null) {
              await _queue(txn, row['cover_path'] as String);
            }
          }
          await txn.delete('routes');
          await txn.delete('collections');
          await txn.delete('places');
        }
        final ids = <String, Map<int, int>>{};
        final existingRoutes = <int>{};
        for (final table in portableTables) {
          final mapping = ids[table] = <int, int>{};
          for (final source in backup._data[table]!) {
            final originalId = source['id'] as int;
            if (table == 'waypoints' &&
                existingRoutes.contains(source['route_id'])) {
              continue;
            }
            final existing = await txn.query(
              table,
              columns: ['id'],
              where: 'stable_id = ?',
              whereArgs: [source['stable_id']],
            );
            if (existing.isNotEmpty) {
              mapping[originalId] = existing.single['id'] as int;
              if (table == 'routes') existingRoutes.add(originalId);
              continue;
            }
            final row = Map<String, Object?>.of(source);
            // Preserve integer IDs when free, remap collisions by portable ID.
            if ((await txn.query(
              table,
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [originalId],
            )).isNotEmpty) {
              row.remove('id');
            }
            if (table == 'attachments' || table == 'waypoints') {
              final place = row['place_id'];
              row['place_id'] = place == null ? null : ids['places']![place];
            }
            if (table == 'waypoints') {
              row['route_id'] = ids['routes']![row['route_id']];
            }
            if (table == 'attachments') {
              row['relative_path'] = paths['$table:$originalId'];
            }
            if (table == 'collections' && row['cover_path'] != null) {
              row['cover_path'] = paths['$table:$originalId'];
            }
            mapping[originalId] = await txn.insert(table, row);
          }
        }
        for (final membership in backup._data['collection_places']!) {
          await txn.insert('collection_places', {
            'collection_id': ids['collections']![membership['collection_id']],
            'place_id': ids['places']![membership['place_id']],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        // Live references protect files in the cleanup queue; remove those
        // entries so it contains only retired or unused staged media.
        await txn.rawDelete(
          'DELETE FROM attachment_cleanup WHERE relative_path IN (SELECT relative_path FROM attachments UNION SELECT cover_path FROM collections WHERE cover_path IS NOT NULL)',
        );
      });
    } finally {
      await store.tryCleanupAttachments();
    }
  }

  Future<Uint8List> exportGeoJson() async {
    final snapshot = await store.db.transaction(
      (txn) async => {
        for (final table in _tables) table: await txn.query(table),
      },
    );
    return Isolate.run(() {
      final features = <Map<String, Object?>>[];
      final collections = {
        for (final c in snapshot['collections']!) c['id']: c,
      };
      final places = {
        for (final place in snapshot['places']!) place['id']: place,
      };
      for (final place in places.values) {
        features.add({
          'type': 'Feature',
          'id': 'place:${place['stable_id']}',
          'geometry': {
            'type': 'Point',
            'coordinates': [place['longitude'], place['latitude']],
          },
          'properties': {
            for (final e in place.entries)
              if (e.key != 'id') e.key: e.value,
            'kind': 'place',
            'collections': snapshot['collection_places']!
                .where((m) => m['place_id'] == place['id'])
                .map(
                  (m) => {
                    'id': collections[m['collection_id']]!['stable_id'],
                    'name': collections[m['collection_id']]!['name'],
                  },
                )
                .toList(),
          },
        });
      }
      for (final route in snapshot['routes']!) {
        final stops =
            snapshot['waypoints']!
                .where((w) => w['route_id'] == route['id'])
                .toList()
              ..sort(
                (a, b) =>
                    (a['position'] as int).compareTo(b['position'] as int),
              );
        features.add({
          'type': 'Feature',
          'id': 'route:${route['stable_id']}',
          'geometry': route['geometry_json'] == null
              ? null
              : jsonDecode(route['geometry_json'] as String),
          'properties': {
            'kind': 'route',
            'name': route['name'],
            'created_at': route['created_at'],
            'distance_meters': route['distance_meters'],
            'duration_seconds': route['duration_seconds'],
            'stops': stops
                .map(
                  (s) => {
                    'name': s['name'],
                    'longitude': s['longitude'],
                    'latitude': s['latitude'],
                    'place_id': places[s['place_id']]?['stable_id'],
                  },
                )
                .toList(),
          },
        });
        for (final stop in stops) {
          features.add({
            'type': 'Feature',
            'id': 'waypoint:${stop['stable_id']}',
            'geometry': {
              'type': 'Point',
              'coordinates': [stop['longitude'], stop['latitude']],
            },
            'properties': {
              'kind': 'waypoint',
              'route_id': route['stable_id'],
              'position': stop['position'],
              'name': stop['name'],
            },
          });
        }
      }
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({'type': 'FeatureCollection', 'features': features}),
        ),
      );
    });
  }
}

Future<void> _queue(DatabaseExecutor txn, String path) async {
  await txn.insert('attachment_cleanup', {
    'relative_path': path,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Uint8List _encode(
  Map<String, List<Map<String, Object?>>> data,
  Map<String, Uint8List> media,
) {
  _validate(data, media.keys.toSet());
  _checkRestoredSize(data, media);
  final journal = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  if (journal.length > _maxFile) {
    throw const BackupException('Journal metadata exceeds 32 MB.');
  }
  final files = {'journal.json': journal, ...media};
  if (files.values.fold<int>(0, (sum, b) => sum + b.length) > _maxExpanded) {
    throw const BackupException('Journal exceeds the 256 MB expanded limit.');
  }
  final manifest = utf8.encode(
    jsonEncode({
      'format': 'fieldnotes-journal',
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'files': {
        for (final e in files.entries)
          e.key: {
            'bytes': e.value.length,
            'sha256': sha256.convert(e.value).toString(),
          },
      },
    }),
  );
  final archive = Archive();
  if (manifest.length > _maxFile ||
      manifest.length + files.values.fold<int>(0, (sum, b) => sum + b.length) >
          _maxExpanded) {
    throw const BackupException('Journal exceeds the 256 MB expanded limit.');
  }
  archive.add(ArchiveFile('manifest.json', manifest.length, manifest));
  for (final e in files.entries) {
    archive.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  if (bytes.length > maxBackupBytes) {
    throw const BackupException('Backup exceeds the 128 MB archive limit.');
  }
  return bytes;
}

ValidatedBackup _decode(Uint8List bytes) {
  try {
    if (bytes.length > maxBackupBytes) {
      throw const BackupException('Backup exceeds the 128 MB archive limit.');
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    final headers = directory.fileHeaders;
    if (headers.length < 2 ||
        headers.length > _maxEntries ||
        directory.totalCentralDirectoryEntries != headers.length ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0) {
      throw const BackupException('Invalid ZIP directory.');
    }
    final files = <String, Uint8List>{};
    var total = 0;
    // Preflight every entry before decompressing anything, including symlinks.
    for (final h in headers) {
      total += h.uncompressedSize;
      if (total > _maxExpanded ||
          h.uncompressedSize > _maxFile ||
          h.uncompressedSize < 0 ||
          h.generalPurposeBitFlag & 1 != 0 ||
          (h.file?.flags ?? 1) & 1 != 0 ||
          (h.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          ![0, 8].contains(h.compressionMethod) ||
          h.file?.filename != h.filename ||
          (h.filename != 'manifest.json' &&
              h.filename != 'journal.json' &&
              !_mediaName.hasMatch(h.filename))) {
        throw const BackupException('Unsupported or oversized ZIP entry.');
      }
      if (files.containsKey(h.filename)) {
        throw const BackupException('Duplicate ZIP entry.');
      }
      files[h.filename] = Uint8List(0);
    }
    for (final h in headers) {
      final content = h.file!.getStream().toUint8List();
      if (content.length != h.uncompressedSize ||
          getCrc32(content) != h.crc32) {
        throw const BackupException('Backup contains a damaged file.');
      }
      files[h.filename] = content;
    }
    final manifest = _object(
      jsonDecode(utf8.decode(files.remove('manifest.json')!)),
    );
    if (manifest['format'] != 'fieldnotes-journal' ||
        manifest['version'] != 1) {
      throw const BackupException('Unsupported backup format or version.');
    }
    final created = manifest['created_at'];
    if (created is! String || DateTime.tryParse(created) == null) {
      throw const BackupException('Invalid backup date.');
    }
    final inventory = _object(manifest['files']);
    if (inventory.length != files.length ||
        !files.containsKey('journal.json')) {
      throw const BackupException('Backup file inventory is incomplete.');
    }
    for (final e in files.entries) {
      final item = _object(inventory[e.key]);
      if (item['bytes'] != e.value.length ||
          item['sha256'] != sha256.convert(e.value).toString()) {
        throw const BackupException('Backup checksum does not match.');
      }
    }
    final raw = _object(jsonDecode(utf8.decode(files.remove('journal.json')!)));
    final data = _validate(raw, files.keys.toSet());
    _checkRestoredSize(data, files);
    return ValidatedBackup._(data, files, created);
  } on BackupException {
    rethrow;
  } catch (_) {
    throw const BackupException(
      'This is not a valid Fieldnotes backup, or the archive is damaged.',
    );
  }
}

void _checkRestoredSize(
  Map<String, List<Map<String, Object?>>> data,
  Map<String, Uint8List> media,
) {
  var restoredBytes = 0;
  for (final table in ['attachments', 'collections']) {
    for (final row in data[table]!) {
      final path = row[table == 'attachments' ? 'relative_path' : 'cover_path'];
      if (path == null) continue;
      restoredBytes += media[path]!.length;
      if (restoredBytes > _maxExpanded) {
        throw const BackupException('Restored photos exceed the 256 MB limit.');
      }
    }
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const BackupException('Invalid backup metadata.');
  }
  return value;
}

// Type codes: text, integer, finite number; ? permits null. Every column is
// required, so unsupported schemas cannot silently drop personal information.
const _columns = {
  'places': {
    'id': 'i',
    'stable_id': 's',
    'name': 's',
    'latitude': 'n',
    'longitude': 'n',
    'notes': 's',
    'category': 's',
    'visited': 'i',
    'favorite': 'i',
    'rating': 'i?',
    'visit_date': 's?',
    'created_at': 's',
  },
  'collections': {
    'id': 'i',
    'stable_id': 's',
    'name': 's',
    'description': 's',
    'cover_path': 's?',
  },
  'routes': {
    'id': 'i',
    'stable_id': 's',
    'name': 's',
    'distance_meters': 'n?',
    'duration_seconds': 'n?',
    'geometry_json': 's?',
    'created_at': 's',
  },
  'waypoints': {
    'id': 'i',
    'stable_id': 's',
    'route_id': 'i',
    'place_id': 'i?',
    'position': 'i',
    'name': 's',
    'latitude': 'n',
    'longitude': 'n',
  },
  'attachments': {
    'id': 'i',
    'stable_id': 's',
    'place_id': 'i',
    'relative_path': 's',
    'caption': 's',
    'created_at': 's',
  },
  'collection_places': {'collection_id': 'i', 'place_id': 'i'},
};

Map<String, List<Map<String, Object?>>> _validate(
  Map<String, Object?> raw,
  Set<String> media,
) {
  Never invalid() => throw const BackupException(
    'Backup contains invalid records or broken references.',
  );
  if (raw.length != _tables.length || !_tables.every(raw.containsKey)) {
    invalid();
  }
  final result = <String, List<Map<String, Object?>>>{};
  final ids = <String, Set<int>>{};
  final usedMedia = <String>{};
  var count = 0;
  for (final table in _tables) {
    final list = raw[table];
    if (list is! List || (count += list.length) > 100000) invalid();
    final fields = _columns[table]!;
    final stable = <String>{};
    final integers = ids[table] = <int>{};
    result[table] = list.map((item) {
      final row = _object(item);
      if (row.length != fields.length || !fields.keys.every(row.containsKey)) {
        invalid();
      }
      for (final field in fields.entries) {
        final value = row[field.key];
        if (value == null && field.value.endsWith('?')) continue;
        if (switch (field.value[0]) {
          's' => value is! String,
          'i' => value is! int,
          _ => value is! num || !value.isFinite,
        }) {
          invalid();
        }
      }
      if (row.containsKey('id')) {
        final id = row['id'] as int;
        final identity = row['stable_id'] as String;
        if (id <= 0 ||
            id > 0x1fffffffffffff ||
            !integers.add(id) ||
            !_identity.hasMatch(identity) ||
            !stable.add(identity)) {
          invalid();
        }
      }
      if (row['name'] is String && (row['name'] as String).trim().isEmpty) {
        invalid();
      }
      if (row.containsKey('latitude') &&
          ((row['latitude'] as num).abs() > 90 ||
              (row['longitude'] as num).abs() > 180)) {
        invalid();
      }
      for (final date in ['visit_date', 'created_at']) {
        if (row[date] != null &&
            DateTime.tryParse(row[date] as String) == null) {
          invalid();
        }
      }
      if (table == 'places' &&
          (![0, 1].contains(row['visited']) ||
              ![0, 1].contains(row['favorite']) ||
              (row['rating'] != null &&
                  ((row['rating'] as int) < 1 ||
                      (row['rating'] as int) > 5)))) {
        invalid();
      }
      for (final field in ['relative_path', 'cover_path']) {
        if (row[field] != null) {
          final path = row[field] as String;
          if (!media.contains(path)) invalid();
          usedMedia.add(path);
        }
      }
      if (table == 'routes') {
        final geo = row['geometry_json'];
        final distance = row['distance_meters'];
        final duration = row['duration_seconds'];
        if (geo == null) {
          if (distance != null || duration != null) invalid();
        } else {
          if (distance == null ||
              duration == null ||
              (distance as num) < 0 ||
              (duration as num) < 0) {
            invalid();
          }
          final geometry = _object(jsonDecode(geo as String));
          final coordinates = geometry['coordinates'];
          if (geometry['type'] != 'LineString' ||
              coordinates is! List ||
              coordinates.length < 2) {
            invalid();
          }
          for (final point in coordinates) {
            if (point is! List ||
                point.length != 2 ||
                point.any((v) => v is! num || !v.isFinite) ||
                (point[0] as num).abs() > 180 ||
                (point[1] as num).abs() > 90) {
              invalid();
            }
          }
        }
      }
      return Map<String, Object?>.of(row);
    }).toList();
  }
  if (usedMedia.length != media.length) invalid();
  final memberships = <String>{};
  final positions = <int, Set<int>>{};
  for (final table in ['waypoints', 'attachments', 'collection_places']) {
    for (final row in result[table]!) {
      for (final ref in {
        'place_id': 'places',
        'route_id': 'routes',
        'collection_id': 'collections',
      }.entries) {
        if (row[ref.key] != null && !ids[ref.value]!.contains(row[ref.key])) {
          invalid();
        }
      }
      if (table == 'collection_places' &&
          !memberships.add('${row['collection_id']}:${row['place_id']}')) {
        invalid();
      }
      if (table == 'waypoints') {
        final set = positions.putIfAbsent(
          row['route_id'] as int,
          () => <int>{},
        );
        if ((row['position'] as int) < 0 || !set.add(row['position'] as int)) {
          invalid();
        }
      }
    }
  }
  for (final positions in positions.values) {
    if (positions.length > 25 || positions.any((p) => p >= positions.length)) {
      invalid();
    }
  }
  return result;
}
