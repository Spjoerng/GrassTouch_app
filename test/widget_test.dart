import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/data/attachment_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fieldnotes_test_');
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
    'records survive reopening; joins cascade and waypoint snapshots survive place deletion',
    () async {
      final place = {'name': 'Baguio', 'latitude': 16.4, 'longitude': 120.6};
      final id = await store.savePlace(place);
      final collection = await store.addCollection('Mountains');
      await store.addToCollection(collection, id);
      await store.saveRoute('Northbound', [
        {...place, 'id': id},
      ]);
      await store.close();
      store = await JournalStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/journal.sqlite',
      );
      expect((await store.places()).single['name'], 'Baguio');
      expect((await store.collections()).single['place_count'], 1);
      await store.deletePlace(id);
      expect((await store.collections()).single['place_count'], 0);
      final waypoint = (await store.db.query('waypoints')).single;
      expect(waypoint['place_id'], isNull);
      expect(waypoint['name'], 'Baguio');
    },
  );
  test(
    'invalid coordinates fail and invalid route replacement rolls back',
    () async {
      await expectLater(
        store.savePlace({'name': 'Invalid', 'latitude': 91, 'longitude': 0}),
        throwsA(anything),
      );
      final id = await store.saveRoute('Original', [
        {'name': 'Start', 'latitude': 0, 'longitude': 0},
      ]);
      await expectLater(
        store.saveRoute('Changed', [
          {'name': 'Bad', 'latitude': 100, 'longitude': 0},
        ], id: id),
        throwsA(anything),
      );
      expect((await store.routes()).single['name'], 'Original');
      expect((await store.db.query('waypoints')).single['name'], 'Start');
    },
  );
  test('attachment copies are portable and cannot escape storage', () async {
    final storage = AttachmentStorage(
      Directory('${directory.path}/attachments'),
    );
    final source = await File(
      '${directory.path}/photo.jpg',
    ).writeAsBytes([1, 2, 3]);
    final relative = await storage.importFile(source);
    expect(await storage.resolve(relative).readAsBytes(), [1, 2, 3]);
    expect(() => storage.resolve('../journal.sqlite'), throwsArgumentError);
    await storage.delete(relative);
    expect(await source.exists(), isTrue);
    expect(await storage.resolve(relative).exists(), isFalse);
  });
  testWidgets('phone navigation, validation, and saving a place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JournalApp(store: store));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Places'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add place'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save place'));
    await tester.pumpAndSettle();
    expect(find.text('Give this place a name'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Place name'),
      'Baguio',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '16.4',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '120.6',
    );
    await tester.tap(find.text('Save place'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    for (var i = 0; i < 10 && find.text('Baguio').evaluate().isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }
    expect(find.text('Baguio'), findsOneWidget);
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    expect(find.text('Give your places a home'), findsOneWidget);
    await tester.tap(find.text('Routes'));
    await tester.pumpAndSettle();
    expect(find.text('Good trips begin with a plan'), findsOneWidget);
  });
  testWidgets('wide layout uses navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(JournalApp(store: store));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Routes'));
    await tester.pumpAndSettle();
    expect(find.text('Good trips begin with a plan'), findsOneWidget);
  });
}
