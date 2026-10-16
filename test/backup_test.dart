import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/backup/journal_backup.dart';
import 'package:map_app/src/data/attachment_storage.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/routes/route_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class UnwritableImportStorage extends AttachmentStorage {
  UnwritableImportStorage(super.root);
  @override
  File resolve(String path) =>
      path.startsWith('restore_') ? File(root.path) : super.resolve(path);
}

Uint8List altered(
  Uint8List bytes,
  void Function(Map<String, dynamic>) change, {
  bool resign = true,
  String? extra,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {for (final file in archive) file.name: file.readBytes()!};
  final journal =
      jsonDecode(utf8.decode(files['journal.json']!)) as Map<String, dynamic>;
  change(journal);
  files['journal.json'] = Uint8List.fromList(utf8.encode(jsonEncode(journal)));
  if (resign) {
    final manifest =
        jsonDecode(utf8.decode(files['manifest.json']!))
            as Map<String, dynamic>;
    manifest['files']['journal.json'] = {
      'bytes': files['journal.json']!.length,
      'sha256': sha256.convert(files['journal.json']!).toString(),
    };
    files['manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest)),
    );
  }
  final result = Archive();
  for (final e in files.entries) {
    result.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  if (extra != null) result.add(ArchiveFile(extra, 1, [1]));
  return ZipEncoder().encodeBytes(result);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore source, target;
  const fields = {
    'name': 'Batangas coast',
    'latitude': 13.75,
    'longitude': 121.05,
    'notes': 'Sunset',
    'category': 'Nature',
    'favorite': 1,
    'visited': 1,
    'rating': 5,
    'visit_date': '2026-10-10T00:00:00.000',
  };
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fieldnotes_backup_');
    source = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/source.sqlite',
    );
    target = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/target/journal.sqlite',
    );
  });
  tearDown(() async {
    await source.close();
    await target.close();
    await directory.delete(recursive: true);
  });

  Future<Uint8List> fixture() async {
    final photo = await File(
      '${directory.path}/photo.jpg',
    ).writeAsBytes([1, 2, 3, 4]);
    final place = await source.saveJournalPlace(
      fields,
      retainedPhotos: [],
      newPhotos: [photo, photo],
    );
    final collection = await source.saveCollection(
      name: 'Weekend',
      description: 'Beach day',
      newCover: photo,
    );
    await source.addToCollection(collection, place);
    final stops = [
      RouteStop.fromPlace(await source.place(place)),
      const RouteStop(name: 'Pier', latitude: 13.76, longitude: 121.06),
    ];
    await source.savePlannedRoute(
      'Coastal drive',
      stops,
      road: RoadRoute(
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [121.05, 13.75],
            [121.06, 13.76],
          ],
        },
        distanceMeters: 1500,
        durationSeconds: 180,
        stopsSignature: stopSignature(stops),
      ),
    );
    return JournalBackup(source).exportZip();
  }

  test(
    'ZIP transfers complete graph, IDs, duplicate-content photos, cover and road geometry; survives reopening',
    () async {
      final bytes = await fixture();
      final backup = await JournalBackup.decode(bytes);
      expect(
        [backup.places, backup.collections, backup.routes, backup.photos],
        [1, 1, 1, 2],
      );
      await JournalBackup(target).restore(backup, RestoreMode.replace);
      final place = (await target.places()).single;
      expect(place, (await source.places()).single);
      final collection = (await target.collections()).single;
      expect(collection['description'], 'Beach day');
      expect(
        (await target.collectionPlaces(
          collection['id'] as int,
        )).single['stable_id'],
        place['stable_id'],
      );
      for (final photo in await target.attachments(place['id'] as int)) {
        expect(
          await target.storage
              .resolve(photo['relative_path'] as String)
              .readAsBytes(),
          [1, 2, 3, 4],
        );
      }
      expect(
        await target.storage
            .resolve(collection['cover_path'] as String)
            .readAsBytes(),
        [1, 2, 3, 4],
      );
      final route = (await target.routes()).single;
      expect(
        await target.route(route['id'] as int),
        await source.route(route['id'] as int),
      );
      expect(
        await target.routeStops(route['id'] as int),
        await source.routeStops(route['id'] as int),
      );
      expect(await target.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await target.close();
      target = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/target/journal.sqlite',
      );
      expect((await target.places()).length, 1);
      expect(await target.db.query('attachment_cleanup'), isEmpty);
    },
  );

  test(
    'merge remaps integer collisions and remains idempotent while keeping local edits and route plans',
    () async {
      final bytes = await fixture();
      final local = await target.savePlace({...fields, 'name': 'Local place'});
      await target.addCollection('Local collection');
      await target.saveRoute('Local route', [
        {'name': 'Start', 'latitude': 13.0, 'longitude': 121.0},
      ]);
      final backup = await JournalBackup.decode(bytes);
      await JournalBackup(target).restore(backup, RestoreMode.merge);
      final imported = (await target.places()).firstWhere(
        (r) => r['name'] == fields['name'],
      );
      expect(imported['id'], isNot(local));
      final collection = (await target.collections()).firstWhere(
        (r) => r['name'] == 'Weekend',
      );
      expect(
        (await target.collectionPlaces(collection['id'] as int)).single['id'],
        imported['id'],
      );
      final route = (await target.routes()).firstWhere(
        (r) => r['name'] == 'Coastal drive',
      );
      expect(
        (await target.routeStops(route['id'] as int)).first['place_id'],
        imported['id'],
      );
      await target.savePlace({...imported, 'name': 'Local revision'});
      final paths = (await target.attachments(
        imported['id'] as int,
      )).map((r) => r['relative_path']).toList();
      await JournalBackup(target).restore(backup, RestoreMode.merge);
      expect((await target.places()).length, 2);
      expect((await target.collections()).length, 2);
      expect((await target.routes()).length, 2);
      expect(
        (await target.place(imported['id'] as int))['name'],
        'Local revision',
      );
      expect(
        (await target.attachments(
          imported['id'] as int,
        )).map((r) => r['relative_path']),
        paths,
      );
      expect((await target.storage.root.list().toList()).length, 3);
    },
  );

  test(
    'replace failure rolls back deletions, metadata and old files; removes staged photos',
    () async {
      final backup = await JournalBackup.decode(await fixture());
      final photo = await File('${directory.path}/old.jpg').writeAsBytes([9]);
      final id = await target.saveJournalPlace(
        {...fields, 'name': 'Keep me'},
        retainedPhotos: [],
        newPhotos: [photo],
      );
      final old =
          (await target.attachments(id)).single['relative_path'] as String;
      await target.db.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON routes BEGIN SELECT RAISE(ABORT, 'Injected storage failure'); END",
      );
      await expectLater(
        JournalBackup(target).restore(backup, RestoreMode.replace),
        throwsA(isA<DatabaseException>()),
      );
      expect((await target.places()).single['name'], 'Keep me');
      expect(await target.storage.resolve(old).readAsBytes(), [9]);
      expect((await target.storage.root.list().toList()).length, 1);
      expect(await target.db.query('attachment_cleanup'), isEmpty);
    },
  );

  test(
    'successful replace retires old files and restores an empty backup too',
    () async {
      final backup = await JournalBackup.decode(await fixture());
      await JournalBackup(target).restore(backup, RestoreMode.replace);
      final oldPaths = await target.storage.root.list().toList();
      final empty = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/empty.sqlite',
      );
      try {
        await JournalBackup(target).restore(
          await JournalBackup.decode(await JournalBackup(empty).exportZip()),
          RestoreMode.replace,
        );
      } finally {
        await empty.close();
      }
      expect(await target.places(), isEmpty);
      expect(await target.routes(), isEmpty);
      for (final file in oldPaths) {
        expect(await file.exists(), isFalse);
      }
    },
  );

  test(
    'rejects malformed ZIP, traversal, checksum corruption, duplicate identities, broken links and invalid geometry',
    () async {
      final bytes = await fixture();
      final invalid = <Uint8List>[
        Uint8List.fromList([0, 1, 2]),
        altered(bytes, (_) {}, extra: '../outside.jpg'),
        altered(bytes, (d) {
          d['places'][0]['name'] = 'Tampered';
        }, resign: false),
        altered(bytes, (d) {
          d['places'].add({...d['places'][0], 'id': 10});
        }),
        altered(bytes, (d) {
          d['waypoints'][0]['place_id'] = 999;
        }),
        altered(bytes, (d) {
          d['places'][0]['latitude'] = 91;
        }),
        altered(bytes, (d) {
          d['routes'][0]['geometry_json'] =
              '{"type":"LineString","coordinates":[[999,0],[1,0]]}';
        }),
        altered(bytes, (d) {
          d['waypoints'][0]['position'] = 10;
        }),
        altered(bytes, (d) {
          d['attachments'][0]['relative_path'] = '/elsewhere';
        }),
      ];
      for (final data in invalid) {
        await expectLater(
          JournalBackup.decode(data),
          throwsA(isA<BackupException>()),
        );
      }
      expect(await target.places(), isEmpty);
    },
  );

  test(
    'missing source photo fails export instead of creating a partial backup',
    () async {
      await fixture();
      final photo =
          (await source.db.query('attachments')).first['relative_path']
              as String;
      await source.storage.delete(photo);
      await expectLater(
        JournalBackup(source).exportZip(),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'GeoJSON preserves longitude-latitude order, collections, road lines and unrouted stops without inventing roads',
    () async {
      await fixture();
      await source.saveRoute('Offline plan', [
        {'name': 'Manual', 'latitude': 14.0, 'longitude': 121.0},
      ]);
      final geo = jsonDecode(
        utf8.decode(await JournalBackup(source).exportGeoJson()),
      );
      expect(geo['type'], 'FeatureCollection');
      final features = geo['features'] as List;
      final point = features.firstWhere(
        (f) => f['properties']['kind'] == 'place',
      );
      expect(point['geometry']['coordinates'], [121.05, 13.75]);
      expect(point['properties']['collections'][0]['name'], 'Weekend');
      final road = features.firstWhere(
        (f) => f['properties']['name'] == 'Coastal drive',
      );
      expect(road['geometry']['type'], 'LineString');
      final plan = features.firstWhere(
        (f) => f['properties']['name'] == 'Offline plan',
      );
      expect(plan['geometry'], isNull);
      expect(plan['properties']['stops'][0]['name'], 'Manual');
      expect(
        features.where((f) => f['properties']['kind'] == 'waypoint').length,
        3,
      );
    },
  );

  test(
    'failed staged photo write leaves existing records and files intact',
    () async {
      final backup = await JournalBackup.decode(await fixture());
      final photo = await File('${directory.path}/old.jpg').writeAsBytes([9]);
      final id = await target.saveJournalPlace(
        {...fields, 'name': 'Keep original'},
        retainedPhotos: [],
        newPhotos: [photo],
      );
      final old =
          (await target.attachments(id)).single['relative_path'] as String;
      final failing = JournalStore(
        target.db,
        UnwritableImportStorage(target.storage.root),
      );
      await expectLater(
        JournalBackup(failing).restore(backup, RestoreMode.replace),
        throwsA(isA<FileSystemException>()),
      );
      expect((await target.places()).single['name'], 'Keep original');
      expect(await target.storage.resolve(old).readAsBytes(), [9]);
      expect((await target.storage.root.list().toList()).length, 1);
    },
  );

  test(
    'preflight rejects oversized headers, symlinks, encryption and unknown versions',
    () async {
      final bytes = await fixture();
      final header = <int>[];
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 4; i++) {
        if (view.getUint32(i, Endian.little) == 0x02014b50) header.add(i);
      }
      for (final kind in ['size', 'symlink', 'encrypted']) {
        final changed = Uint8List.fromList(bytes);
        final data = ByteData.sublistView(changed);
        final offset = header.first;
        if (kind == 'size') {
          data.setUint32(offset + 24, 33 * 1024 * 1024, Endian.little);
        }
        if (kind == 'symlink') {
          data.setUint16(offset + 4, 0x0314, Endian.little);
          data.setUint32(offset + 38, 0xa1ff0000, Endian.little);
        }
        if (kind == 'encrypted') data.setUint16(offset + 8, 1, Endian.little);
        await expectLater(
          JournalBackup.decode(changed),
          throwsA(isA<BackupException>()),
        );
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      final rebuilt = Archive();
      for (final file in archive) {
        var content = file.readBytes()!;
        if (file.name == 'manifest.json') {
          final manifest =
              jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
          manifest['version'] = 999;
          content = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
        }
        rebuilt.add(ArchiveFile(file.name, content.length, content));
      }
      await expectLater(
        JournalBackup.decode(ZipEncoder().encodeBytes(rebuilt)),
        throwsA(isA<BackupException>()),
      );
    },
  );

  test(
    'dense saved road geometry remains portable within the metadata size limit',
    () async {
      const stops = [
        RouteStop(name: 'Start', latitude: 13.9, longitude: 121.0),
        RouteStop(name: 'End', latitude: 14.0, longitude: 121.1),
      ];
      final road = RoadRoute(
        geometry: {
          'type': 'LineString',
          'coordinates': List.generate(
            100001,
            (i) => [121.0 + i / 1000000, 13.9 + i / 1000000],
          ),
        },
        distanceMeters: 20000,
        durationSeconds: 3600,
        stopsSignature: stopSignature(stops),
      );
      final id = await source.savePlannedRoute(
        'Detailed road',
        stops,
        road: road,
      );
      final backup = await JournalBackup.decode(
        await JournalBackup(source).exportZip(),
      );
      await JournalBackup(target).restore(backup, RestoreMode.replace);
      final restored = jsonDecode(
        (await target.route(id))['geometry_json'] as String,
      );
      expect(restored['coordinates'].length, 100001);
      expect(
        restored['coordinates'].last,
        (road.geometry['coordinates'] as List).last,
      );
      expect((await target.route(id))['distance_meters'], 20000);
    },
  );

  test(
    'v3 migration assigns identities once and preserves all existing records',
    () async {
      final path = '${directory.path}/legacy.sqlite';
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            for (final sql in schema) {
              await db.execute(sql);
            }
            await db.insert('places', fields);
          },
        ),
      );
      await db.close();
      var migrated = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final row = (await migrated.places()).single;
      expect(row['stable_id'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(await migrated.db.getVersion(), 4);
      await migrated.close();
      migrated = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await migrated.places()).single['stable_id'], row['stable_id']);
      await migrated.close();
    },
  );
}
