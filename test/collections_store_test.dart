import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'journal_store_test.dart' show LockedStorage;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('collections_store_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'collections and memberships persist, rename, and delete without deleting shared places',
    () async {
      final first = await store.savePlace({
        'name': 'Cafe',
        'latitude': 14,
        'longitude': 121,
      });
      final second = await store.savePlace({
        'name': 'Park',
        'latitude': 15,
        'longitude': 122,
      });
      final weekend = await store.saveCollection(
        name: 'Weekend plans',
        description: 'A day outside',
      );
      final food = await store.saveCollection(name: 'Favorite restaurants');
      await store.setCollectionPlaces(weekend, {first, second});
      await store.addToCollection(food, first);
      await store.addToCollection(food, first);
      await store.close();
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
      );
      expect(await store.collectionPlaces(weekend), hasLength(2));
      expect(await store.collectionPlaces(food), hasLength(1));
      await store.saveCollection(
        id: weekend,
        name: 'Sunday plans',
        description: 'Coffee and a walk',
      );
      expect(
        (await store.collection(weekend))['description'],
        'Coffee and a walk',
      );
      await store.removeFromCollection(weekend, first);
      expect((await store.collectionPlaces(weekend)).single['id'], second);
      expect((await store.collectionPlaces(food)).single['id'], first);
      await store.deleteCollection(weekend);
      expect(await store.places(), hasLength(2));
      expect(
        (await store.collections()).single['name'],
        'Favorite restaurants',
      );
      await store.setCollectionPlaces(food, {});
      expect(await store.collectionPlaces(food), isEmpty);
      expect(await store.places(), hasLength(2));
    },
  );
  test(
    'membership replacement and collection-created places roll back on invalid references',
    () async {
      final id = await store.savePlace({
        'name': 'Original',
        'latitude': 0,
        'longitude': 0,
      });
      final collection = await store.saveCollection(name: 'Study spots');
      await store.setCollectionPlaces(collection, {id});
      await expectLater(
        store.setCollectionPlaces(collection, {999}),
        throwsA(anything),
      );
      expect((await store.collectionPlaces(collection)).single['id'], id);
      await expectLater(store.setCollectionPlaces(999, {}), throwsStateError);
      await expectLater(
        store.saveJournalPlace(
          {'name': 'Should roll back', 'latitude': 0, 'longitude': 0},
          retainedPhotos: [],
          collectionIds: {999},
        ),
        throwsA(anything),
      );
      expect(await store.places(), hasLength(1));
      final created = await store.saveJournalPlace(
        {'name': 'Library', 'latitude': 1, 'longitude': 2},
        retainedPhotos: [],
        collectionIds: {collection},
      );
      expect((await store.collectionPlaces(collection)).map((p) => p['id']), [
        created,
        id,
      ]);
    },
  );
  test(
    'cover copies survive source removal, failed edits preserve originals, replacements clean up',
    () async {
      final source = await File(
        '${directory.path}/cover.jpg',
      ).writeAsBytes([1, 2, 3]);
      final id = await store.saveCollection(
        name: 'Weekend',
        description: 'Original',
        newCover: source,
      );
      final cover = (await store.collection(id))['cover_path'] as String;
      await store.close();
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
      );
      expect(await store.storage.resolve(cover).readAsBytes(), [1, 2, 3]);
      await expectLater(
        store.saveCollection(
          id: id,
          name: ' ',
          description: 'Wrong',
          newCover: source,
        ),
        throwsA(anything),
      );
      expect((await store.collection(id))['description'], 'Original');
      expect((await store.collection(id))['cover_path'], cover);
      expect(await store.storage.root.list().length, 1);
      await store.saveCollection(id: id, name: 'Renamed', newCover: source);
      final replaced = (await store.collection(id))['cover_path'] as String;
      expect(replaced, isNot(cover));
      expect(await store.storage.resolve(cover).exists(), isFalse);
      await source.delete();
      expect(await store.storage.resolve(replaced).exists(), isTrue);
      await store.saveCollection(id: id, name: 'No cover', removeCover: true);
      expect((await store.collection(id))['cover_path'], isNull);
      expect(await store.storage.resolve(replaced).exists(), isFalse);
    },
  );
  test(
    'collection cover deletion is retried on restart and preserves source and place photos',
    () async {
      await store.close();
      final storage = LockedStorage(Directory('${directory.path}/attachments'));
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
        storage: storage,
      );
      final source = await File(
        '${directory.path}/source.png',
      ).writeAsBytes([1]);
      final collection = await store.saveCollection(
        name: 'Covered',
        newCover: source,
      );
      final cover =
          (await store.collection(collection))['cover_path'] as String;
      final place = await store.saveJournalPlace(
        {'name': 'Kept', 'latitude': 1, 'longitude': 2},
        retainedPhotos: [],
        newPhotos: [source],
        collectionIds: {collection},
      );
      await store.deleteCollection(collection);
      expect(await store.collectionPlaces(collection), isEmpty);
      expect(await store.attachments(place), hasLength(1));
      expect(await store.storage.resolve(cover).exists(), isTrue);
      expect(await store.db.query('attachment_cleanup'), hasLength(1));
      await store.close();
      storage.locked = false;
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
        storage: storage,
      );
      expect(await storage.resolve(cover).exists(), isFalse);
      expect(await source.exists(), isTrue);
      expect(await store.places(), hasLength(1));
      expect(await store.attachments(place), hasLength(1));
      expect(await store.db.query('attachment_cleanup'), isEmpty);
    },
  );
  test(
    'v2 migration preserves collection descriptions, memberships, journal records and photos',
    () async {
      await store.close();
      final path = '${directory.path}/legacy-v2.sqlite';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            for (final sql in schema) {
              await db.execute(sql.replaceAll(', cover_path TEXT', ''));
            }
          },
        ),
      );
      final place = await legacy.insert('places', {
        'name': 'Legacy',
        'latitude': 1,
        'longitude': 2,
      });
      final collection = await legacy.insert('collections', {
        'name': 'Old group',
        'description': 'Keep this',
      });
      await legacy.insert('collection_places', {
        'place_id': place,
        'collection_id': collection,
      });
      await legacy.insert('attachments', {
        'place_id': place,
        'relative_path': 'legacy.jpg',
      });
      await legacy.close();
      store = await JournalStore.open(factory: databaseFactoryFfi, path: path);
      expect(await store.db.getVersion(), 3);
      expect((await store.collection(collection))['description'], 'Keep this');
      expect((await store.collection(collection))['cover_path'], isNull);
      expect((await store.collectionPlaces(collection)).single['id'], place);
      expect(
        (await store.attachments(place)).single['relative_path'],
        'legacy.jpg',
      );
    },
  );
}
