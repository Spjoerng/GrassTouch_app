import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/collections.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/map/offline_maps.dart';
import 'package:map_app/src/map/offline_maps_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'offline_maps_test.dart' show offlineTestRegion, completeMapStatus;
import 'package:map_app/src/routes/route_planner.dart';
import 'route_logic_test.dart' show routeTestStops, testRoad;

void configureView(WidgetTester tester, {double width = 390}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  keyboardHeight(tester, 0);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
}

void keyboardHeight(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  tester.view.padding = FakeViewPadding(top: 24, bottom: height == 0 ? 24 : 0);
}

Future<void> checkStableMap(WidgetTester tester) async {
  final canvas = find.byType(TestMapCanvas);
  final bounds = tester.getRect(canvas);
  final state = tester.state(canvas);
  final camera = tester.widget<TestMapCanvas>(canvas).options.camera;
  await tester.tap(find.byKey(const ValueKey('place-search')));
  await tester.pump();
  for (final height in [80.0, 180.0, 320.0, 220.0, 0.0, 300.0, 0.0]) {
    keyboardHeight(tester, height);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getRect(canvas),
      bounds,
      reason:
          'Map must not resize during the keyboard transition at $height px',
    );
    expect(tester.state(canvas), same(state));
    expect(tester.widget<TestMapCanvas>(canvas).options.camera, same(camera));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(canvas), bounds);
  }
  await tester.enterText(find.byKey(const ValueKey('place-search')), 'Coast');
  await tester.pump();
  expect(tester.getRect(canvas), bounds);
  expect(
    tester.widget<TestMapCanvas>(canvas).options.places.single['name'],
    'Coast',
  );
  await tester.tap(find.byTooltip('Clear search'));
  await tester.pump();
  expect(
    tester
        .widget<TextFormField>(find.byKey(const ValueKey('place-search')))
        .controller!
        .text,
    isEmpty,
  );
  expect(tester.state(canvas), same(state));
  expect(tester.getRect(canvas), bounds);
  expect(tester.takeException(), isNull);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('map_keyboard_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
    await store.savePlace({
      'name': 'Coast',
      'latitude': 13.9,
      'longitude': 121.05,
    });
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'Explore viewport and map instance stay fixed throughout keyboard animation at width $width',
      (tester) async {
        configureView(tester, width: width);
        await tester.pumpWidget(
          JournalApp(
            store: store,
            mapCanvasBuilder: (_, options) => TestMapCanvas(options: options),
          ),
        );
        await drainMap(tester);
        await checkStableMap(tester);
      },
    );
  }

  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'route rename keeps viewport and camera fixed at width $width',
      (tester) async {
        configureView(tester, width: width);
        final id = await tester.runAsync(
          () => store.savePlannedRoute(
            'Weekend drive',
            routeTestStops,
            road: testRoad(routeTestStops),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RoutePlanner(
              store: store,
              routeId: id,
              canvasBuilder: (_, options) => TestMapCanvas(options: options),
            ),
          ),
        );
        await drainMap(tester);
        final canvas = find.byType(TestMapCanvas);
        final bounds = tester.getRect(canvas);
        final state = tester.state(canvas);
        final camera = tester.widget<TestMapCanvas>(canvas).options.camera;
        await tester.tap(find.byTooltip('Route options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename route'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextFormField, 'Route name'));
        for (final height in [80.0, 180.0, 320.0, 220.0, 0.0, 300.0]) {
          keyboardHeight(tester, height);
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(canvas), bounds);
          expect(tester.state(canvas), same(state));
          expect(
            tester.widget<TestMapCanvas>(canvas).options.camera,
            same(camera),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.getRect(canvas), bounds);
        }
        expect(
          tester.getRect(find.text('Use name')).bottom,
          lessThan(844 - 300),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Route name'),
          'Coastal drive',
        );
        await tester.tap(find.text('Use name'));
        keyboardHeight(tester, 0);
        await tester.pumpAndSettle();
        expect(find.text('Coastal drive'), findsOneWidget);
        expect(tester.getRect(canvas), bounds);
        expect(
          tester.widget<TestMapCanvas>(canvas).options.camera,
          same(camera),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('collection map search keeps the same viewport', (tester) async {
    configureView(tester);
    late Map<String, Object?> collection;
    await tester.runAsync(() async {
      final id = await store.addCollection('Weekend');
      await store.addToCollection(
        id,
        (await store.places()).single['id'] as int,
      );
      collection = await store.collection(id);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionDetails(
          store: store,
          collection: collection,
          canvasBuilder: (_, options) => TestMapCanvas(options: options),
        ),
      ),
    );
    await drainMap(tester);
    await tester.tap(find.text('Map'));
    await drainMap(tester);
    await checkStableMap(tester);
  });

  testWidgets('offline area map search keeps the same viewport', (
    tester,
  ) async {
    configureView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineAreaPage(
          store: store,
          area: OfflineArea(offlineTestRegion, completeMapStatus),
          canvasBuilder: (_, options) => TestMapCanvas(options: options),
        ),
      ),
    );
    await drainMap(tester);
    await checkStableMap(tester);
  });

  testWidgets(
    'list search and the place form still make room for the keyboard',
    (tester) async {
      configureView(tester);
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
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      final list = find.byType(ListView);
      final listBefore = tester.getRect(list);
      await tester.tap(find.byKey(const ValueKey('place-search')));
      keyboardHeight(tester, 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(list).height, lessThan(listBefore.height));
      keyboardHeight(tester, 0);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      latest!.onCoordinateSelected(const MapCoordinate(13.95, 121.06));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this place'));
      await drainMap(tester);
      final saveAction = find.widgetWithText(FilledButton, 'Save place');
      final before = tester.getRect(saveAction);
      await tester.tap(find.widgetWithText(TextFormField, 'Place name'));
      keyboardHeight(tester, 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(saveAction).bottom, lessThan(before.bottom));
      expect(tester.getRect(saveAction).bottom, lessThanOrEqualTo(844 - 300));
      expect(tester.takeException(), isNull);
    },
  );
}
