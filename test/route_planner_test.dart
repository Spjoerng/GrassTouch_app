import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'route_logic_test.dart' show TestRouter, testRoad, routeTestStops;

Future<void> renameRoute(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Route options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename route'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Route name'),
    name,
  );
  await tester.tap(find.text('Use name'));
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('route_ui_');
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
    'phone route planner selects places, positions and reorders stops, calculates, restores, renames and deletes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => store.savePlace({
          'name': 'Batangas port',
          'latitude': 13.7565,
          'longitude': 121.0583,
        }),
      );
      final router = TestRouter();
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          roadRouter: router,
          mapCanvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      );
      await drainMap(tester);
      await tester.tap(find.text('Routes'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, 'New route'));
      await drainMap(tester);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save route'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Add stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved place'));
      await drainMap(tester);
      await tester.tap(find.text('Batangas port'));
      await drainMap(tester);
      await tester.tap(find.text('Add stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter coordinates'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stop name'),
        'Lipa',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '999',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '121.15',
      );
      await tester.tap(find.text('Use stop'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between -90 and 90'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '13.95',
      );
      await tester.tap(find.text('Use stop'));
      await drainMap(tester);
      latest!.onCoordinateSelected(const MapCoordinate(13.85, 121.1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stops (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop 3 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      await renameRoute(tester, 'Batangas day trip');
      await tester.tap(find.text('Calculate road route'));
      await tester.pumpAndSettle();
      expect(router.calls, 1);
      expect(find.text('12.4 km / 25 min driving'), findsOneWidget);
      await tester.tap(find.text('Map'));
      await drainMap(tester);
      expect(latest!.routeGeometry, isNotNull);
      expect(latest!.routeStops[1].latitude, 13.85);
      latest!.onRouteStopSelected!(1);
      await tester.pumpAndSettle();
      latest!.onCoordinateSelected(const MapCoordinate(13.86, 121.11));
      await tester.pumpAndSettle();
      expect(latest!.routeGeometry, isNull);
      expect(find.textContaining('No road route calculated.'), findsOneWidget);
      await tester.tap(find.text('Calculate road route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save route'));
      await drainMap(tester);
      expect(find.text('Batangas day trip'), findsOneWidget);
      final rows = await tester.runAsync(store.routes);
      final id = rows!.single['id'] as int;
      final stops = await tester.runAsync(() => store.routeStops(id));
      expect(stops!.map((p) => p['name']), ['Batangas port', 'Stop 3', 'Lipa']);
      expect(stops[1]['latitude'], 13.86);
      await tester.tap(find.text('Batangas day trip'));
      await drainMap(tester);
      expect(latest!.routeGeometry, isNotNull);
      expect(latest!.routeStops, hasLength(3));
      expect(find.text('12.4 km / 25 min driving'), findsOneWidget);
      await renameRoute(tester, 'Sunday drive');
      await tester.tap(find.text('Save route'));
      await drainMap(tester);
      expect(find.text('Sunday drive'), findsOneWidget);
      await tester.tap(find.text('Sunday drive'));
      await drainMap(tester);
      await tester.tap(find.byTooltip('Route options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep route'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Route options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete route'));
      await drainMap(tester);
      expect(find.text('Good trips begin with a plan'), findsOneWidget);
      expect(await tester.runAsync(store.places), hasLength(1));
    },
  );
  testWidgets(
    'saved geometry survives offline routing and modified plans can save without stale geometry',
    (tester) async {
      final id = await tester.runAsync(
        () => store.savePlannedRoute(
          'Offline drive',
          routeTestStops,
          road: testRoad(routeTestStops),
        ),
      );
      final router = TestRouter()..fail = true;
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          roadRouter: router,
          mapCanvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      );
      await drainMap(tester);
      await tester.tap(find.text('Routes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline drive'));
      await drainMap(tester);
      expect(router.calls, 0);
      expect(latest!.routeGeometry, isNotNull);
      await tester.tap(find.text('Calculate road route'));
      await tester.pumpAndSettle();
      expect(find.text('Offline routing unavailable'), findsOneWidget);
      expect(latest!.routeGeometry, isNotNull);
      await tester.tap(find.text('Stops (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop 2 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save route'));
      await drainMap(tester);
      final row = await tester.runAsync(() => store.route(id!));
      expect(row!['geometry_json'], isNull);
      expect(row['distance_meters'], isNull);
      final stops = await tester.runAsync(() => store.routeStops(id!));
      expect(stops!.first['name'], 'Destination');
      await tester.tap(find.text('Offline drive'));
      await drainMap(tester);
      latest!.onCoordinateSelected(const MapCoordinate(14, 121.2));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard route changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await drainMap(tester);
      expect(await tester.runAsync(() => store.routeStops(id!)), hasLength(2));
    },
  );
}
