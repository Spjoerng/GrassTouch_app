import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/journal_location.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/routes/route_follow_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'map_data_location_test.dart' show FakeLocationGateway;
import 'route_logic_test.dart' show routeTestStops, testRoad, TestRouter;

void main() {
  sqfliteFfiInit();
  testWidgets(
    'saved route follow mode retains geometry, supports indefinite live following and ends without editing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('route_follow_'),
      ))!;
      final store = (await tester.runAsync(
        () => JournalStore.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/journal.sqlite',
        ),
      ))!;
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final road = testRoad(routeTestStops);
      final id = await tester.runAsync(
        () =>
            store.savePlannedRoute('Coastal drive', routeTestStops, road: road),
      );
      final gateway = FakeLocationGateway();
      final router = TestRouter();
      late MapCanvasOptions latest;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          roadRouter: router,
          locationService: JournalLocation(gateway: gateway),
          mapCanvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      );
      await drainMap(tester);
      await tester.tap(find.text('Routes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coastal drive'));
      await drainMap(tester);
      expect(gateway.fixes, 0);
      await tester.tap(find.text('Follow route'));
      await tester.pumpAndSettle();
      expect(find.byType(RouteFollowPage), findsOneWidget);
      expect(latest.liveLocation, isTrue);
      expect(latest.followLocation, isTrue);
      expect(latest.routeGeometry, road.geometry);
      expect(latest.routeStops, hasLength(2));
      expect(latest.selected, isNull);
      latest.onCoordinateSelected(const MapCoordinate(14, 121));
      await tester.pumpAndSettle();
      expect(latest.selected, isNull);
      expect(find.text('Save this place'), findsNothing);
      await tester.tap(find.byTooltip('Fit route'));
      await tester.pumpAndSettle();
      expect(latest.followLocation, isFalse);
      expect(latest.liveLocation, isTrue);
      expect(latest.camera!.target, isNull);
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(hours: 2));
      expect(latest.liveLocation, isTrue);
      expect(latest.followLocation, isTrue);
      expect(gateway.fixes, 1);
      expect(router.calls, 0);
      await tester.tap(find.byTooltip('Stop live location'));
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isFalse);
      expect(latest.routeGeometry, road.geometry);
      await tester.tap(find.text('End following'));
      await tester.pumpAndSettle();
      expect(find.byType(RouteFollowPage), findsNothing);
      final row = await tester.runAsync(() => store.route(id!));
      expect(row!['name'], 'Coastal drive');
      expect(row['distance_meters'], road.distanceMeters);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'denied route location keeps road visible and can recover on request',
    (tester) async {
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.deniedForever;
      late MapCanvasOptions latest;
      await tester.pumpWidget(
        MaterialApp(
          home: RouteFollowPage(
            name: 'Coastal drive',
            stops: routeTestStops,
            road: testRoad(routeTestStops),
            locationService: JournalLocation(gateway: gateway),
            canvasBuilder: (_, options) {
              latest = options;
              return TestMapCanvas(options: options);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isFalse);
      expect(latest.routeGeometry, isNotNull);
      expect(find.textContaining('Location access is blocked'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(gateway.appSettings, 1);
      gateway.permission = LocationPermission.whileInUse;
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isTrue);
      expect(latest.selected, isNull);
      expect(latest.routeGeometry, isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
