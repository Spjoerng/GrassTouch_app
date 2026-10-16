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
import 'map_data_location_test.dart' show FakeLocationGateway;

class TestMapCanvas extends StatefulWidget {
  const TestMapCanvas({super.key, required this.options});
  final MapCanvasOptions options;
  @override
  State<TestMapCanvas> createState() => _TestMapCanvasState();
}

class _TestMapCanvasState extends State<TestMapCanvas> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.options.onReady();
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFEAF0E5),
    child: Center(child: Text('Test map surface')),
  );
}

Future<void> drainMap(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('journal_map_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  testWidgets('map and list retain the same combined filters and records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await store.savePlace({
        'name': 'Pine trail',
        'latitude': 1,
        'longitude': 2,
        'category': 'Nature',
        'visited': 1,
        'favorite': 1,
        'notes': 'Mountain air',
      });
      await store.savePlace({
        'name': 'Beach',
        'latitude': 1.1,
        'longitude': 2.1,
        'category': 'Nature',
        'visited': 0,
      });
      await store.savePlace({
        'name': 'Museum',
        'latitude': 3,
        'longitude': 4,
        'category': 'Culture',
        'visited': 1,
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
    expect(latest!.places, hasLength(3));
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nature').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(latest!.places, hasLength(2));
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visited').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(latest!.places.single['name'], 'Pine trail');
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.text('Pine trail'), findsOneWidget);
    expect(find.text('Beach'), findsNothing);
    expect(find.text('Museum'), findsNothing);
    await tester.enterText(find.byType(TextField), 'mountain');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map'));
    await drainMap(tester);
    expect(latest!.places.single['name'], 'Pine trail');
    expect(find.text('mountain'), findsOneWidget);
    latest!.onPlacesSelected([latest!.places.single['id'] as int]);
    await drainMap(tester);
    expect(find.text('Mountain air'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await drainMap(tester);
    await tester.enterText(find.byType(TextField), 'No match');
    await tester.pumpAndSettle();
    expect(latest!.places, isEmpty);
  });
  testWidgets(
    'tapping coordinates creates one persistent place shared by map and list',
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
      final mapRect = tester.getRect(find.byType(TestMapCanvas));
      expect(mapRect.top, 0);
      expect(mapRect.height, greaterThan(844 * 0.85));
      latest!.onCoordinateSelected(const MapCoordinate(14.5995, 120.9842));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 14.599500, 120.984200'), findsOneWidget);
      await tester.tap(find.text('Save this place'));
      await drainMap(tester);
      expect(find.text('14.5995'), findsOneWidget);
      expect(find.text('120.9842'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place name'),
        'Map memory',
      );
      await tester.tap(find.text('Save place'));
      await drainMap(tester);
      expect(latest!.places.single['name'], 'Map memory');
      final records = await tester.runAsync(store.places);
      expect(records!.single['latitude'], 14.5995);
      expect(records.single['longitude'], 120.9842);
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('Map memory'), findsOneWidget);
    },
  );
  testWidgets(
    'location is explicit, denied access keeps the map usable, then a fix focuses it',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.deniedForever;
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        JournalApp(
          store: store,
          locationService: JournalLocation(gateway: gateway),
          mapCanvasBuilder: (_, options) {
            latest = options;
            return TestMapCanvas(options: options);
          },
        ),
      );
      await drainMap(tester);
      expect(gateway.requests, 0);
      expect(gateway.fixes, 0);
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Location access is blocked.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(gateway.appSettings, 1);
      latest!.onCoordinateSelected(const MapCoordinate(0, 0));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 0.000000, 0.000000'), findsOneWidget);
      gateway.permission = LocationPermission.whileInUse;
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(gateway.fixes, 1);
      expect(latest!.location!.latitude, 14.6);
      expect(latest!.camera!.target!.longitude, 121);
    },
  );
  testWidgets(
    'map failure offers retry and offline list without losing records',
    (tester) async {
      await tester.runAsync(
        () => store.savePlace({
          'name': 'Offline place',
          'latitude': 0,
          'longitude': 0,
        }),
      );
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
      latest!.onError('Tiles unavailable');
      await tester.pumpAndSettle();
      expect(find.text('Tiles unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry map'));
      await tester.pumpAndSettle();
      expect(find.text('Tiles unavailable'), findsNothing);
      latest!.onError('Tiles unavailable');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use offline list'));
      await tester.pumpAndSettle();
      expect(find.text('Offline place'), findsOneWidget);
    },
  );
}
