import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/collection_dialog.dart';
import 'package:map_app/src/collections.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/place_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;

Future<void> openCollectionEditor(
  WidgetTester tester,
  JournalStore store,
  PhotoPicker picker, {
  Map<String, Object?>? collection,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => CollectionDialog(
                store: store,
                collection: collection,
                pickCover: picker,
              ),
            ),
            child: const Text('Open collection editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open collection editor'));
  await drainMap(tester);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('collections_ui_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  testWidgets(
    'custom collection creation, membership, shared map filters, rename, removal and safe deletion',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await store.savePlace({
          'name': 'Cafe',
          'latitude': 14,
          'longitude': 121,
          'category': 'Food & drink',
        });
        await store.savePlace({
          'name': 'Park',
          'latitude': 14.1,
          'longitude': 121.1,
          'category': 'Nature',
          'visited': 1,
          'favorite': 1,
        });
        await store.savePlace({
          'name': 'Outside forest',
          'latitude': 14.2,
          'longitude': 121.2,
          'category': 'Nature',
          'visited': 1,
          'favorite': 1,
        });
      });
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          mapCanvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      );
      await drainMap(tester);
      await tester.tap(find.text('Collections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekend plans'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'Coffee and a walk',
      );
      await tester.tap(find.text('Create collection'));
      await drainMap(tester);
      await tester.tap(find.text('Weekend plans'));
      await drainMap(tester);
      expect(find.text('Coffee and a walk'), findsOneWidget);
      expect(find.text('No places in this collection'), findsOneWidget);
      await tester.tap(find.byTooltip('Manage places'));
      await drainMap(tester);
      await tester.tap(find.text('Park'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Search saved places'),
        'Cafe',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Cafe'));
      await tester.tap(find.text('Save places'));
      await drainMap(tester);
      expect(find.text('Cafe'), findsOneWidget);
      expect(find.text('Park'), findsOneWidget);
      expect(find.text('Outside forest'), findsNothing);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nature').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('status-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visited').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites only'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Cafe'), findsNothing);
      expect(find.text('Park'), findsOneWidget);
      await tester.tap(find.text('Map'));
      await drainMap(tester);
      expect(latest!.places.single['name'], 'Park');
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from collection'));
      await drainMap(tester);
      expect(find.text('No places found'), findsOneWidget);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Cafe'), findsOneWidget);
      await tester.tap(find.byTooltip('Manage places'));
      await drainMap(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Cafe'));
      await tester.tap(find.text('Cancel'));
      await drainMap(tester);
      expect(find.text('Cafe'), findsOneWidget);
      await tester.tap(find.byTooltip('Collection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit collection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Collection name'),
        'Sunday plans',
      );
      await tester.tap(find.text('Save collection'));
      await drainMap(tester);
      expect(find.text('Sunday plans'), findsOneWidget);
      await tester.tap(find.byTooltip('Collection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep collection'));
      await tester.pumpAndSettle();
      expect(find.text('Sunday plans'), findsOneWidget);
      await tester.tap(find.byTooltip('Collection options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete collection'));
      await drainMap(tester);
      expect(find.text('Give your places a home'), findsOneWidget);
      expect(await tester.runAsync(store.places), hasLength(3));
    },
  );
  testWidgets('new places saved from a collection map join that collection', (
    tester,
  ) async {
    final id = await tester.runAsync(
      () => store.saveCollection(name: 'Map study spots'),
    );
    final collection = await tester.runAsync(() => store.collection(id!));
    MapCanvasOptions? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionDetails(
          store: store,
          collection: collection!,
          canvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      ),
    );
    await drainMap(tester);
    await tester.tap(find.text('Map'));
    await drainMap(tester);
    latest!.onCoordinateSelected(const MapCoordinate(13.9, 121.05));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this place'));
    await drainMap(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Place name'),
      'New study spot',
    );
    await tester.tap(find.text('Save place'));
    await drainMap(tester);
    final members = await tester.runAsync(() => store.collectionPlaces(id!));
    expect(members!.single['name'], 'New study spot');
    expect(latest!.places.single['id'], members.single['id']);
    expect(await tester.runAsync(store.places), hasLength(1));
  });
  testWidgets(
    'collection covers save locally; cancelling replacement preserves the original',
    (tester) async {
      final source = await tester.runAsync(
        () => File('${directory.path}/cover.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      );
      Future<List<File>> picker() async => [source!];
      await openCollectionEditor(tester, store, picker);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a collection name'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Collection name'),
        'Study spots',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'Quiet places to read',
      );
      await tester.ensureVisible(find.text('Add cover image'));
      await tester.tap(find.text('Add cover image'));
      await drainMap(tester);
      await tester.tap(find.text('Create collection'));
      await drainMap(tester);
      final rows = await tester.runAsync(store.collections);
      final collection = rows!.single;
      final cover = collection['cover_path'] as String;
      expect(
        await tester.runAsync(() => store.storage.resolve(cover).exists()),
        isTrue,
      );
      await openCollectionEditor(tester, store, picker, collection: collection);
      await tester.ensureVisible(find.text('Change cover image'));
      await tester.tap(find.text('Change cover image'));
      await drainMap(tester);
      await tester.tap(find.text('Cancel'));
      await drainMap(tester);
      expect(
        (await tester.runAsync(
          () => store.collection(collection['id'] as int),
        ))!['cover_path'],
        cover,
      );
      expect(await tester.runAsync(() => store.storage.root.list().length), 1);
      await openCollectionEditor(tester, store, picker, collection: collection);
      await tester.ensureVisible(find.text('Remove cover'));
      await tester.tap(find.text('Remove cover'));
      await tester.tap(find.text('Save collection'));
      await drainMap(tester);
      expect(
        (await tester.runAsync(
          () => store.collection(collection['id'] as int),
        ))!['cover_path'],
        isNull,
      );
      expect(
        await tester.runAsync(() => store.storage.resolve(cover).exists()),
        isFalse,
      );
      expect(await tester.runAsync(() => source!.exists()), isTrue);
    },
  );
}
