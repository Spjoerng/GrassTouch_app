import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/routes/road_router.dart';
import 'package:map_app/src/routes/route_draft.dart';
import 'package:map_app/src/routes/route_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const routeTestStops = [
  RouteStop(name: 'Start', latitude: 13.9, longitude: 121),
  RouteStop(name: 'Destination', latitude: 13.95, longitude: 121.05),
];
RoadRoute testRoad(List<RouteStop> stops) => RoadRoute(
  geometry: {
    'type': 'LineString',
    'coordinates': [
      [121.0, 13.9],
      [121.02, 13.92],
      [121.05, 13.95],
    ],
  },
  distanceMeters: 12450,
  durationSeconds: 1500,
  stopsSignature: stopSignature(stops),
);

class TestRouter implements RoadRouter {
  int calls = 0;
  bool fail = false;
  @override
  Future<RoadRoute> route(List<RouteStop> stops) async {
    calls++;
    if (fail) throw const RoutingFailure('Offline routing unavailable');
    return testRoad(stops);
  }
}

class PendingRouter implements RoadRouter {
  final result = Completer<RoadRoute>();
  @override
  Future<RoadRoute> route(List<RouteStop> stops) => result.future;
}

void main() {
  test(
    'routing requests ordered longitude-first driving coordinates and parses road geometry',
    () async {
      Uri? requested;
      final router = OsrmRouter(
        client: MockClient((request) async {
          requested = request.url;
          expect(request.headers['User-Agent'], contains('Fieldnotes'));
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 12450,
                  'duration': 1500,
                  'geometry': testRoad(routeTestStops).geometry,
                },
              ],
            }),
            200,
          );
        }),
      );
      final road = await router.route(routeTestStops);
      expect(requested!.path, '/route/v1/driving/121.0,13.9;121.05,13.95');
      expect(requested!.queryParameters['geometries'], 'geojson');
      expect(requested!.queryParameters['overview'], 'full');
      expect(road.distanceMeters, 12450);
      expect(road.durationSeconds, 1500);
      expect(road.geometry['coordinates'], hasLength(3));
      expect(
        () => (road.geometry['coordinates'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(routeDistance(road.distanceMeters), '12.4 km');
      expect(routeDuration(road.durationSeconds), '25 min');
      await expectLater(
        router.route(routeTestStops),
        throwsA(
          isA<RoutingFailure>().having(
            (f) => f.message,
            'message',
            contains('wait a moment'),
          ),
        ),
      );
    },
  );
  test(
    'no road, throttling, network failures, malformed geometry and timeouts remain recoverable',
    () async {
      for (final status in [200, 400]) {
        final router = OsrmRouter(
          client: MockClient(
            (_) async => http.Response('{"code":"NoSegment"}', status),
          ),
        );
        await expectLater(
          router.route(routeTestStops),
          throwsA(
            isA<RoutingFailure>().having(
              (f) => f.message,
              'message',
              contains('No driving route'),
            ),
          ),
        );
      }
      for (final response in [
        http.Response('busy', 429),
        http.Response('down', 503),
        http.Response(
          '{"code":"Ok","routes":[{"distance":-1,"duration":1,"geometry":{"type":"LineString","coordinates":[[999,0],[0,0]]}}]}',
          200,
        ),
      ]) {
        final router = OsrmRouter(client: MockClient((_) async => response));
        await expectLater(
          router.route(routeTestStops),
          throwsA(isA<RoutingFailure>()),
        );
      }
      final offline = OsrmRouter(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.route(routeTestStops),
        throwsA(
          isA<RoutingFailure>().having(
            (f) => f.message,
            'message',
            contains('offline'),
          ),
        ),
      );
      final timeout = OsrmRouter(
        client: MockClient((_) async => throw TimeoutException('timeout')),
      );
      await expectLater(
        timeout.route(routeTestStops),
        throwsA(
          isA<RoutingFailure>().having(
            (f) => f.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    },
  );
  test(
    'changed stops clear geometry and late road responses cannot replace the current plan',
    () async {
      final draft = RouteDraft(
        stops: routeTestStops,
        road: testRoad(routeTestStops),
      );
      addTearDown(draft.dispose);
      draft.add(
        const RouteStop(name: 'Intermediate', latitude: 14, longitude: 121),
      );
      expect(draft.road, isNull);
      draft.move(2, 1);
      expect(draft.stops.map((s) => s.name), [
        'Start',
        'Intermediate',
        'Destination',
      ]);
      draft.remove(1);
      final pending = PendingRouter();
      final calculation = draft.calculate(pending);
      draft.replace(
        1,
        const RouteStop(name: 'Moved', latitude: 14.1, longitude: 121.1),
      );
      pending.result.complete(testRoad(routeTestStops));
      await calculation;
      expect(draft.road, isNull);
      expect(draft.calculating, isFalse);
      final good = TestRouter();
      await draft.calculate(good);
      expect(draft.road!.stopsSignature, stopSignature(draft.stops));
      good.fail = true;
      final previous = draft.road;
      await draft.calculate(good);
      expect(identical(draft.road, previous), isTrue);
      expect(draft.error, contains('Offline'));
    },
  );
  group('route persistence', () {
    sqfliteFfiInit();
    late Directory directory;
    late JournalStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('routes_store_');
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
      'ordered snapshots and road geometry survive reopen, rename and source-place deletion',
      () async {
        final place = await store.savePlace({
          'name': 'Saved start',
          'latitude': 13.9,
          'longitude': 121,
        });
        final stops = [
          RouteStop(
            name: 'Saved start',
            latitude: 13.9,
            longitude: 121,
            placeId: place,
          ),
          routeTestStops.last,
        ];
        final id = await store.savePlannedRoute(
          'Batangas drive',
          stops,
          road: testRoad(stops),
        );
        await store.close();
        store = await JournalStore.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/journal.sqlite',
        );
        expect((await store.routeStops(id)).map((s) => s['name']), [
          'Saved start',
          'Destination',
        ]);
        final row = await store.route(id);
        expect(
          jsonDecode(row['geometry_json'] as String),
          testRoad(stops).geometry,
        );
        expect(row['distance_meters'], 12450);
        await store.savePlannedRoute(
          'Renamed drive',
          stops,
          id: id,
          road: testRoad(stops),
        );
        expect((await store.route(id))['name'], 'Renamed drive');
        await store.deletePlace(place);
        expect((await store.routeStops(id)).first['place_id'], isNull);
        expect((await store.routeStops(id)).first['name'], 'Saved start');
        expect((await store.route(id))['geometry_json'], isNotNull);
      },
    );
    test(
      'waypoint edits invalidate cached metrics; deletes preserve journal places and atomic failures preserve route',
      () async {
        final place = await store.savePlace({
          'name': 'Kept place',
          'latitude': 0,
          'longitude': 0,
        });
        final id = await store.savePlannedRoute(
          'Road plan',
          routeTestStops,
          road: testRoad(routeTestStops),
        );
        final changed = [routeTestStops.last, routeTestStops.first];
        expect(
          () => store.savePlannedRoute(
            'Stale',
            changed,
            id: id,
            road: testRoad(routeTestStops),
          ),
          throwsArgumentError,
        );
        await expectLater(
          store.savePlannedRoute('Invalid place reference', [
            RouteStop(name: 'Missing', latitude: 1, longitude: 1, placeId: 999),
            routeTestStops.last,
          ], id: id),
          throwsA(anything),
        );
        expect((await store.route(id))['name'], 'Road plan');
        expect((await store.routeStops(id)).first['name'], 'Start');
        await store.savePlannedRoute('Offline plan', changed, id: id);
        final row = await store.route(id);
        expect(row['geometry_json'], isNull);
        expect(row['duration_seconds'], isNull);
        expect(row['distance_meters'], isNull);
        expect((await store.routeStops(id)).first['name'], 'Destination');
        await store.deleteRoute(id);
        expect(await store.routes(), isEmpty);
        expect(await store.routeStops(id), isEmpty);
        expect((await store.places()).single['id'], place);
      },
    );
  });
}
