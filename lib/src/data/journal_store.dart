import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'attachment_storage.dart';
import '../routes/route_models.dart';

class JournalStore {
  JournalStore(this.db, this.storage);
  final Database db;
  final AttachmentStorage storage;
  static Future<JournalStore> open({
    DatabaseFactory? factory,
    String? path,
    AttachmentStorage? storage,
  }) async {
    if (factory == null && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final location =
        path ??
        p.join((await getApplicationSupportDirectory()).path, 'journal.sqlite');
    if (path == null) {
      await Directory(p.dirname(location)).create(recursive: true);
    }
    final db = await (factory ?? databaseFactory).openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final statement in schema) {
            await db.execute(statement);
          }
          await installPortableIds(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await db.execute(cleanupSchema);
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE collections ADD COLUMN cover_path TEXT',
            );
          }
          if (oldVersion < 4) await installPortableIds(db);
        },
      ),
    );
    final store = JournalStore(
      db,
      storage ??
          AttachmentStorage(
            Directory(p.join(p.dirname(location), 'attachments')),
          ),
    );
    await store.cleanupAttachments();
    return store;
  }

  Future<List<Map<String, Object?>>> places() =>
      db.query('places', orderBy: 'id DESC');
  Future<int> savePlace(Map<String, Object?> place) async {
    final id = place['id'];
    return id == null
        ? db.insert('places', place)
        : db.update('places', place, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlace(int id) => deleteJournalPlace(id);
  Future<Map<String, Object?>> place(int id) async =>
      (await db.query('places', where: 'id = ?', whereArgs: [id])).single;
  Future<List<Map<String, Object?>>> attachments(int placeId) => db.query(
    'attachments',
    where: 'place_id = ?',
    whereArgs: [placeId],
    orderBy: 'id',
  );

  /// File copies complete before the transaction. Failed saves leave the
  /// original journal intact; deferred deletions are retried on next open.
  Future<int> saveJournalPlace(
    Map<String, Object?> place, {
    required List<String> retainedPhotos,
    List<File> newPhotos = const [],
    Set<int> collectionIds = const {},
  }) async {
    final copied = <String>[];
    late final int id;
    try {
      for (final source in newPhotos) {
        final path = await storage.importFile(source);
        copied.add(path);
      }
      id = await db.transaction((txn) async {
        final existingId = place['id'] as int?;
        final int placeId;
        if (existingId == null) {
          placeId = await txn.insert('places', place);
        } else {
          final changed = await txn.update(
            'places',
            place,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          if (changed != 1) throw StateError('Place no longer exists');
          placeId = existingId;
        }
        for (final collectionId in collectionIds) {
          await txn.insert('collection_places', {
            'collection_id': collectionId,
            'place_id': placeId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final old = await txn.query(
          'attachments',
          where: 'place_id = ?',
          whereArgs: [placeId],
        );
        final owned = old
            .map((photo) => photo['relative_path'] as String)
            .toSet();
        if (retainedPhotos.any((path) => !owned.contains(path))) {
          throw ArgumentError('Photo does not belong to this place');
        }
        for (final photo in old) {
          final path = photo['relative_path'] as String;
          if (!retainedPhotos.contains(path)) {
            await txn.insert('attachment_cleanup', {
              'relative_path': path,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            await txn.delete(
              'attachments',
              where: 'id = ?',
              whereArgs: [photo['id']],
            );
          }
        }
        for (final path in copied) {
          await txn.insert('attachments', {
            'place_id': placeId,
            'relative_path': path,
          });
        }
        return placeId;
      });
    } catch (_) {
      // Queue failed imports before deleting so interrupted cleanup is retryable.
      for (final path in copied) {
        try {
          await db.insert('attachment_cleanup', {
            'relative_path': path,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } on DatabaseException {
          // If SQLite itself is unavailable, still try to remove the copy.
          try {
            await storage.delete(path);
          } on FileSystemException {
            /* Original save error is preserved. */
          }
        }
      }
      await tryCleanupAttachments();
      rethrow;
    }
    await tryCleanupAttachments();
    return id;
  }

  Future<void> deleteJournalPlace(int id) async {
    await db.transaction((txn) async {
      final photos = await txn.query(
        'attachments',
        where: 'place_id = ?',
        whereArgs: [id],
      );
      for (final photo in photos) {
        await txn.insert('attachment_cleanup', {
          'relative_path': photo['relative_path'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete('places', where: 'id = ?', whereArgs: [id]);
    });
    await tryCleanupAttachments();
  }

  /// Cleanup cannot turn a committed journal save/delete into an apparent
  /// failure. The durable queue remains available to retry next time.
  Future<void> tryCleanupAttachments() async {
    try {
      await cleanupAttachments();
    } on DatabaseException {
      /* Retry on reopen. */
    }
  }

  Future<void> cleanupAttachments() async {
    for (final row in await db.query('attachment_cleanup')) {
      final path = row['relative_path'] as String;
      // Never remove a file that is still attached to a record.
      if ((await db.query(
        'attachments',
        where: 'relative_path = ?',
        whereArgs: [path],
      )).isNotEmpty) {
        continue;
      }
      if ((await db.query(
        'collections',
        where: 'cover_path = ?',
        whereArgs: [path],
      )).isNotEmpty) {
        continue;
      }
      try {
        await storage.delete(path);
        await db.delete(
          'attachment_cleanup',
          where: 'relative_path = ?',
          whereArgs: [path],
        );
      } on FileSystemException {
        // A temporarily locked file is retried after the next save or restart.
      }
    }
  }

  Future<List<Map<String, Object?>>> collections() => db.rawQuery(
    'SELECT c.*, COUNT(cp.place_id) AS place_count FROM collections c LEFT JOIN collection_places cp ON cp.collection_id = c.id GROUP BY c.id ORDER BY c.id DESC',
  );
  Future<int> addCollection(String name) =>
      db.insert('collections', {'name': name.trim()});
  Future<Map<String, Object?>> collection(int id) async =>
      (await db.query('collections', where: 'id = ?', whereArgs: [id])).single;
  Future<List<Map<String, Object?>>> collectionPlaces(int id) => db.rawQuery(
    'SELECT p.* FROM places p INNER JOIN collection_places cp ON cp.place_id = p.id WHERE cp.collection_id = ? ORDER BY p.id DESC',
    [id],
  );
  Future<void> removeFromCollection(int collectionId, int placeId) async {
    await db.delete(
      'collection_places',
      where: 'collection_id = ? AND place_id = ?',
      whereArgs: [collectionId, placeId],
    );
  }

  Future<void> setCollectionPlaces(int collectionId, Set<int> placeIds) =>
      db.transaction((txn) async {
        if ((await txn.query(
          'collections',
          where: 'id = ?',
          whereArgs: [collectionId],
        )).isEmpty) {
          throw StateError('Collection no longer exists');
        }
        await txn.delete(
          'collection_places',
          where: 'collection_id = ?',
          whereArgs: [collectionId],
        );
        for (final placeId in placeIds) {
          await txn.insert('collection_places', {
            'collection_id': collectionId,
            'place_id': placeId,
          });
        }
      });

  Future<int> saveCollection({
    int? id,
    required String name,
    String description = '',
    File? newCover,
    bool removeCover = false,
  }) async {
    String? copied;
    late final int result;
    try {
      if (newCover != null) copied = await storage.importFile(newCover);
      result = await db.transaction((txn) async {
        final old = id == null
            ? null
            : (await txn.query(
                'collections',
                where: 'id = ?',
                whereArgs: [id],
              )).single;
        final oldCover = old?['cover_path'] as String?;
        final cover = copied ?? (removeCover ? null : oldCover);
        final values = {
          'name': name.trim(),
          'description': description.trim(),
          'cover_path': cover,
        };
        final collectionId = id ?? await txn.insert('collections', values);
        if (id != null) {
          await txn.update(
            'collections',
            values,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        if (oldCover != null && oldCover != cover) {
          await txn.insert('attachment_cleanup', {
            'relative_path': oldCover,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        return collectionId;
      });
    } catch (_) {
      if (copied != null) {
        try {
          await db.insert('attachment_cleanup', {
            'relative_path': copied,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } on DatabaseException {
          try {
            await storage.delete(copied);
          } on FileSystemException {
            /* Retry manually if storage remains unavailable. */
          }
        }
        await tryCleanupAttachments();
      }
      rethrow;
    }
    await tryCleanupAttachments();
    return result;
  }

  Future<void> deleteCollection(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'collections',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      final cover = rows.single['cover_path'] as String?;
      if (cover != null) {
        await txn.insert('attachment_cleanup', {
          'relative_path': cover,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete('collections', where: 'id = ?', whereArgs: [id]);
    });
    await tryCleanupAttachments();
  }

  Future<void> addToCollection(int collectionId, int placeId) async {
    await db.insert('collection_places', {
      'collection_id': collectionId,
      'place_id': placeId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> routes() => db.rawQuery(
    'SELECT r.id, r.name, r.distance_meters, r.duration_seconds, r.created_at, COUNT(w.id) AS stop_count FROM routes r LEFT JOIN waypoints w ON w.route_id = r.id GROUP BY r.id ORDER BY r.id DESC',
  );
  Future<Map<String, Object?>> route(int id) async =>
      (await db.query('routes', where: 'id = ?', whereArgs: [id])).single;
  Future<List<Map<String, Object?>>> routeStops(int id) => db.query(
    'waypoints',
    where: 'route_id = ?',
    whereArgs: [id],
    orderBy: 'position',
  );
  Future<void> deleteRoute(int id) async {
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> savePlannedRoute(
    String name,
    List<RouteStop> stops, {
    int? id,
    RoadRoute? road,
  }) {
    if (name.trim().isEmpty ||
        stops.length < 2 ||
        stops.length > 25 ||
        stops.any((s) => !s.valid)) {
      throw ArgumentError('A named route needs 2 to 25 valid stops');
    }
    if (road != null && road.stopsSignature != stopSignature(stops)) {
      throw ArgumentError('Route geometry is out of date');
    }
    return saveRoute(
      name.trim(),
      stops.map((s) => {...s.toRow(), 'id': s.placeId}).toList(),
      id: id,
      road: road,
    );
  }

  Future<int> saveRoute(
    String name,
    List<Map<String, Object?>> stops, {
    int? id,
    RoadRoute? road,
  }) => db.transaction((txn) async {
    final values = {
      'name': name.trim(),
      'distance_meters': road?.distanceMeters,
      'duration_seconds': road?.durationSeconds,
      'geometry_json': road == null ? null : jsonEncode(road.geometry),
    };
    final routeId = id ?? await txn.insert('routes', values);
    if (id != null) {
      final changed = await txn.update(
        'routes',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) throw StateError('Route no longer exists');
    }
    await txn.delete('waypoints', where: 'route_id = ?', whereArgs: [routeId]);
    for (var i = 0; i < stops.length; i++) {
      await txn.insert('waypoints', {
        'route_id': routeId,
        'position': i,
        'place_id': stops[i]['id'],
        'name': stops[i]['name'],
        'latitude': stops[i]['latitude'],
        'longitude': stops[i]['longitude'],
      });
    }
    return routeId;
  });
  Future<void> close() => db.close();
}

const schema = [
  cleanupSchema,
  '''CREATE TABLE places (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name)) > 0), latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90), longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180), notes TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT 'Other', visited INTEGER NOT NULL DEFAULT 0 CHECK(visited IN (0,1)), favorite INTEGER NOT NULL DEFAULT 0 CHECK(favorite IN (0,1)), rating INTEGER CHECK(rating BETWEEN 1 AND 5), visit_date TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
  '''CREATE TABLE collections (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name)) > 0), description TEXT NOT NULL DEFAULT '', cover_path TEXT)''',
  '''CREATE TABLE collection_places (collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE, place_id INTEGER NOT NULL REFERENCES places(id) ON DELETE CASCADE, PRIMARY KEY(collection_id, place_id))''',
  '''CREATE TABLE routes (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name)) > 0), distance_meters REAL, duration_seconds REAL, geometry_json TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
  '''CREATE TABLE waypoints (id INTEGER PRIMARY KEY AUTOINCREMENT, route_id INTEGER NOT NULL REFERENCES routes(id) ON DELETE CASCADE, place_id INTEGER REFERENCES places(id) ON DELETE SET NULL, position INTEGER NOT NULL CHECK(position >= 0), name TEXT NOT NULL, latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90), longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180), UNIQUE(route_id, position))''',
  '''CREATE TABLE attachments (id INTEGER PRIMARY KEY AUTOINCREMENT, place_id INTEGER NOT NULL REFERENCES places(id) ON DELETE CASCADE, relative_path TEXT NOT NULL UNIQUE, caption TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''',
  'CREATE INDEX attachments_place_idx ON attachments(place_id)',
  'CREATE INDEX collection_places_place_idx ON collection_places(place_id)',
];
const cleanupSchema =
    'CREATE TABLE attachment_cleanup (relative_path TEXT PRIMARY KEY NOT NULL)';

const portableTables = [
  'places',
  'collections',
  'routes',
  'waypoints',
  'attachments',
];

/// Local integer keys remain fast; random identities survive device transfers.
Future<void> installPortableIds(DatabaseExecutor db) async {
  for (final table in portableTables) {
    await db.execute('ALTER TABLE $table ADD COLUMN stable_id TEXT');
    await db.execute(
      'UPDATE $table SET stable_id = lower(hex(randomblob(16)))',
    );
    await db.execute(
      'CREATE UNIQUE INDEX ${table}_stable_idx ON $table(stable_id)',
    );
    await db.execute(
      '''CREATE TRIGGER ${table}_portable_id AFTER INSERT ON $table
      WHEN NEW.stable_id IS NULL BEGIN
      UPDATE $table SET stable_id = lower(hex(randomblob(16))) WHERE id = NEW.id;
      END''',
    );
  }
}
