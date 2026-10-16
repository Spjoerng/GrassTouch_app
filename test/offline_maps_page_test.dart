import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/map/offline_maps.dart';
import 'package:map_app/src/map/offline_maps_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'offline_maps_test.dart'
    show
        FakeOfflineGateway,
        mapDatabaseFixture,
        partialMapStatus,
        completeMapStatus;

class FakeOfflineFiles extends OfflineMapFiles {
  File? file;
  bool fail = false;
  @override
  Future<File?> pick() async {
    if (fail) throw const FileSystemException('Access denied');
    return file;
  }
}

Future<void> tapVisible(
  WidgetTester tester,
  String text, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(
    find.text(text),
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text(text));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  late FakeOfflineGateway gateway;
  late OfflineMaps maps;
  late FakeOfflineFiles files;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline_map_ui_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
    gateway = FakeOfflineGateway();
    maps = OfflineMaps(
      gateway: gateway,
      temporaryDirectory: () async => directory,
    );
    files = FakeOfflineFiles();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'phone imports local map data, checks coverage, opens journal places with saved style, and safely removes area',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MapCanvasOptions? latest;
      await tester.runAsync(() async {
        await store.savePlace({
          'name': 'Coast',
          'latitude': 13.9,
          'longitude': 121.05,
        });
        files.file = await mapDatabaseFixture(directory);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsPage(
            store: store,
            maps: maps,
            files: files,
            canvasBuilder: (_, options) {
              latest = options;
              return TestMapCanvas(options: options);
            },
          ),
        ),
      );
      await drainMap(tester);
      await tapVisible(tester, 'Import map database');
      await drainMap(tester);
      expect(gateway.merges, 1);
      await tapVisible(tester, 'Open area');
      await drainMap(tester);
      expect(
        latest!.offlineRegion!.mapStyleUrl,
        gateway.entries.single.definition.mapStyleUrl,
      );
      expect(latest!.offlineRegion!.maxZoom, 13);
      expect(latest!.places.single['name'], 'Coast');
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('Coast'), findsOneWidget);
      await tester.pageBack();
      await drainMap(tester);
      await tapVisible(tester, 'Remove');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.deletes, 0);
      await tapVisible(tester, 'Remove');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove area'));
      await drainMap(tester);
      expect(gateway.deletes, 1);
      await tester.runAsync(() async {
        expect((await store.places()).single['name'], 'Coast');
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incomplete coverage cannot open and status rechecks on resume; file failure can retry',
    (tester) async {
      gateway.statuses[7] = partialMapStatus;
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsPage(store: store, maps: maps, files: files),
        ),
      );
      await drainMap(tester);
      await tester.scrollUntilVisible(
        find.text('Open area'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Open area'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gateway.statuses[7] = completeMapStatus;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drainMap(tester);
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Open area'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      files.fail = true;
      await tapVisible(tester, 'Import map database', delta: -250);
      await drainMap(tester);
      expect(gateway.merges, 0);
      files.fail = false;
      await tapVisible(tester, 'Import map database');
      await drainMap(tester);
      expect(gateway.merges, 0); // Picker cancellation is harmless.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map-store status failure recovers and offline maps is discoverable from Explore',
    (tester) async {
      gateway.failList = true;
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineMapsPage(store: store, maps: maps),
        ),
      );
      await drainMap(tester);
      await tester.scrollUntilVisible(
        find.text('Retry status'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      gateway.failList = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry status'));
      await drainMap(tester);
      expect(find.text('Retry status'), findsNothing);
      await tester.pumpWidget(
        JournalApp(
          store: store,
          mapCanvasBuilder: (_, options) => TestMapCanvas(options: options),
        ),
      );
      await drainMap(tester);
      await tester.tap(find.byTooltip('Journal menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline maps'));
      await tester.pumpAndSettle();
      expect(find.byType(OfflineMapsPage), findsOneWidget);
    },
  );
}
