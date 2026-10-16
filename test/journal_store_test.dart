import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/data/attachment_storage.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/data/place_filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LockedStorage extends AttachmentStorage {
  LockedStorage(super.root);
  bool locked = true;
  @override
  Future<void> delete(String path) async {
    if (locked) throw const FileSystemException('Temporarily locked');
    return super.delete(path);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('journal_stage02_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  const fields = <String, Object?>{
    'name': 'Pine trail',
    'latitude': 16.4,
    'longitude': 120.6,
    'category': 'Nature',
    'notes': 'Quiet afternoon',
    'rating': 4,
    'visit_date': '2026-10-10T00:00:00.000',
    'visited': 1,
    'favorite': 1,
  };
  test(
    'full journal and photo copies survive reopening and source removal',
    () async {
      final source = await File(
        '${directory.path}/source.jpg',
      ).writeAsBytes([1, 2, 3]);
      final id = await store.saveJournalPlace(
        fields,
        retainedPhotos: [],
        newPhotos: [source],
      );
      final path =
          (await store.attachments(id)).single['relative_path'] as String;
      expect(File(path).isAbsolute, isFalse);
      await source.delete();
      await store.close();
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
      );
      expect(await store.place(id), containsPair('rating', 4));
      for (final field in fields.entries) {
        expect((await store.place(id))[field.key], field.value);
      }
      expect(await store.storage.resolve(path).readAsBytes(), [1, 2, 3]);
      await store.saveJournalPlace(
        {
          ...fields,
          'id': id,
          'name': 'Renamed',
          'rating': null,
          'visited': 0,
          'favorite': 0,
          'visit_date': null,
        },
        retainedPhotos: [path],
      );
      expect((await store.place(id))['name'], 'Renamed');
      expect((await store.place(id))['rating'], isNull);
      expect((await store.attachments(id)).length, 1);
      await store.saveJournalPlace({...fields, 'id': id}, retainedPhotos: []);
      expect(await store.attachments(id), isEmpty);
      expect(await store.storage.resolve(path).exists(), isFalse);
    },
  );
  test(
    'failed save and unavailable source preserve existing photos and fields',
    () async {
      final source = await File(
        '${directory.path}/source.png',
      ).writeAsBytes([1]);
      final id = await store.saveJournalPlace(
        fields,
        retainedPhotos: [],
        newPhotos: [source],
      );
      final path =
          (await store.attachments(id)).single['relative_path'] as String;
      await expectLater(
        store.saveJournalPlace(
          {...fields, 'id': id, 'rating': 6},
          retainedPhotos: [],
          newPhotos: [source],
        ),
        throwsA(anything),
      );
      expect((await store.place(id))['rating'], 4);
      expect((await store.attachments(id)).single['relative_path'], path);
      expect(await store.storage.root.list().length, 1);
      await expectLater(
        store.saveJournalPlace(
          {...fields, 'id': id, 'name': 'Changed'},
          retainedPhotos: [],
          newPhotos: [source, File('${directory.path}/missing.png')],
        ),
        throwsA(anything),
      );
      expect((await store.place(id))['name'], 'Pine trail');
      expect(await store.storage.root.list().length, 1);
      await expectLater(
        store.saveJournalPlace(
          {...fields, 'id': id},
          retainedPhotos: ['not-owned.jpg'],
        ),
        throwsArgumentError,
      );
      expect((await store.attachments(id)).single['relative_path'], path);
    },
  );
  test(
    'place deletion removes owned files, cascades joins, and preserves originals',
    () async {
      final source = await File(
        '${directory.path}/source.jpg',
      ).writeAsBytes([1]);
      final id = await store.saveJournalPlace(
        fields,
        retainedPhotos: [],
        newPhotos: [source],
      );
      final path =
          (await store.attachments(id)).single['relative_path'] as String;
      final collection = await store.addCollection('Trails');
      await store.addToCollection(collection, id);
      await store.deletePlace(id);
      expect(await store.places(), isEmpty);
      expect(await store.attachments(id), isEmpty);
      expect((await store.collections()).single['place_count'], 0);
      expect(await store.storage.resolve(path).exists(), isFalse);
      expect(await source.exists(), isTrue);
    },
  );
  test(
    'locked deleted photos remain queued and cleanup retries on reopen',
    () async {
      await store.close();
      final storage = LockedStorage(Directory('${directory.path}/attachments'));
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
        storage: storage,
      );
      final source = await File(
        '${directory.path}/source.jpg',
      ).writeAsBytes([1]);
      final id = await store.saveJournalPlace(
        fields,
        retainedPhotos: [],
        newPhotos: [source],
      );
      final path =
          (await store.attachments(id)).single['relative_path'] as String;
      await store.deletePlace(id);
      expect(await store.places(), isEmpty);
      expect(await store.db.query('attachment_cleanup'), hasLength(1));
      expect(await storage.resolve(path).exists(), isTrue);
      await store.close();
      storage.locked = false;
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
        storage: storage,
      );
      expect(await store.db.query('attachment_cleanup'), isEmpty);
      expect(await storage.resolve(path).exists(), isFalse);
    },
  );
  test('v1 upgrades without losing journal fields', () async {
    await store.close();
    final path = '${directory.path}/legacy.sqlite';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final sql in schema.where((sql) => sql != cleanupSchema)) {
            await db.execute(sql.replaceAll(', cover_path TEXT', ''));
          }
        },
      ),
    );
    await legacy.insert('places', fields);
    await legacy.close();
    store = await JournalStore.open(factory: databaseFactoryFfi, path: path);
    expect((await store.places()).single['notes'], 'Quiet afternoon');
    expect(await store.db.getVersion(), 4);
    expect(await store.db.query('attachment_cleanup'), isEmpty);
  });
  test('search, categories, status and favorites intersect', () {
    expect(
      const PlaceFilter(
        query: ' QUIET ',
        category: 'Nature',
        visited: true,
        favoritesOnly: true,
      ).matches(fields),
      isTrue,
    );
    expect(const PlaceFilter(category: 'Culture').matches(fields), isFalse);
    expect(const PlaceFilter(visited: false).matches(fields), isFalse);
    expect(
      const PlaceFilter(
        favoritesOnly: true,
      ).matches({...fields, 'favorite': 0}),
      isFalse,
    );
    expect(const PlaceFilter(query: 'pine').matches(fields), isTrue);
    expect(const PlaceFilter(query: 'nature').matches(fields), isTrue);
  });
}
