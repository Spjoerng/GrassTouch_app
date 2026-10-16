import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/map/journal_location.dart';
import 'package:map_app/src/map/journal_map_view.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/routes/road_router.dart';
import 'package:map_app/src/routes/route_planner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show TestMapCanvas, drainMap;
import 'map_data_location_test.dart' show FakeLocationGateway;
import 'route_logic_test.dart' show routeTestStops, testRoad;

void background(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void foreground(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

class PendingLocationGateway extends FakeLocationGateway {
  final pending = Completer<MapCoordinate>();
  @override
  Future<MapCoordinate> position() {
    fixes++;
    return pending.future;
  }
}

class StreamingRouteClient extends http.BaseClient {
  StreamingRouteClient(this.response);
  final Future<http.StreamedResponse> Function(http.BaseRequest) response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response(request);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline_lifecycle_');
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
    'map loading pauses in background, resumes with a bound, and ignores obsolete canvas callbacks',
    (tester) async {
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalMapView(
              places: const [],
              onPlacesSelected: (_) {},
              onSaveCoordinate: (_) async => false,
              onShowList: () {},
              canvasBuilder: (_, options) {
                latest = options;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final old = latest!;
      background(tester);
      await tester.pump(const Duration(seconds: 40));
      expect(find.textContaining('taking too long'), findsNothing);
      foreground(tester);
      await tester.pump(const Duration(seconds: 24));
      expect(find.textContaining('taking too long'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('taking too long'), findsOneWidget);
      await tester.tap(find.text('Retry map'));
      await tester.pump();
      old.onReady();
      await tester.pump();
      expect(find.text('Loading map...'), findsOneWidget);
      latest!.onReady();
      await tester.pump();
      expect(find.text('Loading map...'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      old.onError('Late failure');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location result after background is ignored and resume never requests permissions',
    (tester) async {
      final gateway = PendingLocationGateway();
      MapCanvasOptions? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalMapView(
              places: const [],
              onPlacesSelected: (_) {},
              onSaveCoordinate: (_) async => false,
              onShowList: () {},
              locationService: JournalLocation(gateway: gateway),
              canvasBuilder: (_, options) {
                latest = options;
                return TestMapCanvas(options: options);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('My location'));
      await tester.pump();
      expect(gateway.fixes, 1);
      background(tester);
      gateway.pending.complete(const MapCoordinate(13.9, 121.05));
      await tester.pump();
      foreground(tester);
      await tester.pumpAndSettle();
      expect(latest!.location, isNull);
      expect(latest!.selected, isNull);
      expect(gateway.fixes, 1);
      expect(gateway.requests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('journal refreshes persisted records after resuming', (
    tester,
  ) async {
    await tester.pumpWidget(
      JournalApp(
        store: store,
        mapCanvasBuilder: (_, options) => TestMapCanvas(options: options),
      ),
    );
    await drainMap(tester);
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    background(tester);
    await tester.runAsync(
      () => store.savePlace({
        'name': 'Resumed journal',
        'latitude': 13.9,
        'longitude': 121.05,
      }),
    );
    foreground(tester);
    await drainMap(tester);
    expect(find.text('Resumed journal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'route map timeout keeps cached geometry and provides offline stop editing',
    (tester) async {
      late int id;
      await tester.runAsync(() async {
        id = await store.savePlannedRoute(
          'Offline drive',
          routeTestStops,
          road: testRoad(routeTestStops),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePlanner(
            store: store,
            routeId: id,
            canvasBuilder: (_, options) => const SizedBox.expand(),
          ),
        ),
      );
      await drainMap(tester);
      await tester.pump(const Duration(seconds: 26));
      expect(find.textContaining('basemap is unavailable'), findsOneWidget);
      await tester.tap(find.text('Use offline stops'));
      await tester.pumpAndSettle();
      expect(find.text('Start'), findsWidgets);
      expect(find.text('Destination'), findsWidgets);
      await tester.runAsync(() async {
        expect((await store.route(id))['geometry_json'], isNotNull);
      });
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'routing enforces advertised and streaming byte limits, and aborts on close',
    () async {
      for (final advertised in [true, false]) {
        var cancelled = false;
        final body = Stream<List<int>>.multi((sink) {
          sink.onCancel = () {
            cancelled = true;
          };
          sink.add(Uint8List(6 * 1024 * 1024));
          sink.add(Uint8List(6 * 1024 * 1024));
          sink.close();
        });
        final router = OsrmRouter(
          client: StreamingRouteClient(
            (_) async => http.StreamedResponse(
              body,
              200,
              contentLength: advertised ? 12 * 1024 * 1024 : null,
            ),
          ),
        );
        await expectLater(
          router.route(routeTestStops),
          throwsA(
            isA<RoutingFailure>().having(
              (f) => f.message,
              'message',
              contains('too large'),
            ),
          ),
        );
        expect(cancelled, isTrue);
        router.close();
      }
      final started = Completer<http.AbortableRequest>();
      final router = OsrmRouter(
        client: StreamingRouteClient((request) async {
          final abortable = request as http.AbortableRequest;
          started.complete(abortable);
          await abortable.abortTrigger;
          throw http.RequestAbortedException(request.url);
        }),
      );
      final request = router.route(routeTestStops);
      await started.future;
      final failure = expectLater(request, throwsA(isA<RoutingFailure>()));
      router.close();
      await failure;
    },
  );
}
