import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/journal_location.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'map_data_location_test.dart' show FakeLocationGateway;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('place_editor_ui_');
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
    'phone map-picked form has room above the name, no coordinate fields, and accessible visual stars',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      latest!.onCoordinateSelected(
        const MapCoordinate(13.900012345, 121.050012345),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this place'));
      await drainMap(tester);
      expect(find.widgetWithText(TextFormField, 'Latitude'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Longitude'), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      final name = find.widgetWithText(TextFormField, 'Place name');
      final gap =
          tester.getTopLeft(name).dy -
          tester.getBottomLeft(find.text('A place to remember')).dy;
      expect(gap, greaterThanOrEqualTo(24));
      await tester.enterText(name, 'Coastal walk');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('place-rating-4'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('place-rating-4')));
      await tester.pumpAndSettle();
      expect(find.text('4 of 5 stars'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      await tester.ensureVisible(find.text('Clear rating'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear rating'));
      await tester.pumpAndSettle();
      expect(find.text('Not rated yet'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('place-rating-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('place-rating-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save place'));
      await drainMap(tester);
      await tester.runAsync(() async {
        final place = (await store.places()).single;
        expect(place['rating'], 3);
        expect(place['latitude'], 13.900012345);
        expect(place['longitude'], 121.050012345);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list creation chooses a map pin, keeps the draft through cancellation, and never defaults to zero coordinates',
    (tester) async {
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
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add place'));
      await drainMap(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place name'),
        'Quiet nook',
      );
      await tester.tap(find.text('Save place'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a location before saving.'), findsOneWidget);
      await tester.runAsync(() async {
        expect(await store.places(), isEmpty);
      });
      await tester.ensureVisible(find.text('Choose on map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose on map'));
      await tester.pumpAndSettle();
      latest!.onCoordinateSelected(const MapCoordinate(14.01, 121.08));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this location'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Quiet nook'), findsOneWidget);
      expect(find.text('Location selected'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Change location'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change location'));
      await tester.pumpAndSettle();
      expect(latest!.selected!.latitude, 14.01);
      latest!.onCoordinateSelected(const MapCoordinate(0, 0));
      await tester.pumpAndSettle();
      latest!.onError('Tiles unavailable');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to place form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save place'));
      await drainMap(tester);
      await tester.runAsync(() async {
        final place = (await store.places()).single;
        expect(place['name'], 'Quiet nook');
        expect(place['latitude'], 14.01);
        expect(place['longitude'], 121.08);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current location is requested only by the user and denial leaves the editor usable',
    (tester) async {
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.deniedForever;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          locationService: JournalLocation(gateway: gateway),
          mapCanvasBuilder: (_, options) => TestMapCanvas(options: options),
        ),
      );
      await drainMap(tester);
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add place'));
      await drainMap(tester);
      expect(gateway.requests, 0);
      expect(gateway.fixes, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place name'),
        'Current spot',
      );
      await tester.ensureVisible(find.text('Use current location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Location access is blocked.'),
        findsOneWidget,
      );
      gateway.permission = LocationPermission.whileInUse;
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(gateway.fixes, 1);
      await tester.tap(find.text('Save place'));
      await drainMap(tester);
      await tester.runAsync(() async {
        expect((await store.places()).single['latitude'], 14.6);
      });
      expect(tester.takeException(), isNull);
    },
  );
}
