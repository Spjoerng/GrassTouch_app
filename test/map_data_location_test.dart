import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_app/src/map/journal_location.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/data/place_filter.dart';

class FakeLocationGateway implements LocationGateway {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0, fixes = 0, appSettings = 0, locationSettings = 0;
  Object? positionError;
  @override
  Future<bool> serviceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requested;
  }

  @override
  Future<MapCoordinate> position() async {
    fixes++;
    if (positionError != null) throw positionError!;
    return const MapCoordinate(14.6, 121);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

void main() {
  test(
    'map and list share filtering, GeoJSON uses longitude first and no journal text',
    () {
      final records = [
        <String, Object?>{
          'id': 1,
          'latitude': 14.6,
          'longitude': 121.0,
          'category': 'Nature',
          'name': 'Trail',
          'notes': 'Private memory',
          'visited': 1,
          'favorite': 1,
        },
        <String, Object?>{
          'id': 2,
          'latitude': 1.0,
          'longitude': 2.0,
          'category': 'Stay',
          'name': 'Hotel',
          'notes': '',
          'visited': 0,
          'favorite': 0,
        },
      ];
      const filter = PlaceFilter(
        query: 'trail',
        visited: true,
        favoritesOnly: true,
      );
      final features =
          placesGeoJson(records.where(filter.matches).toList())['features']
              as List;
      expect(features, hasLength(1));
      final feature = features.single as Map;
      expect(feature['id'], 1);
      expect((feature['geometry'] as Map)['coordinates'], [121.0, 14.6]);
      expect(feature['properties'], {'place_id': 1, 'marker': 'nature'});
      expect(feature.toString(), isNot(contains('Private memory')));
      expect(placesGeoJson([])['features'], isEmpty);
      expect(coordinateGeoJson(null)['features'], isEmpty);
      expect(markerForCategory('Custom category').key, 'other');
    },
  );
  test(
    'map taps normalize wrapped longitudes into database coordinate range',
    () {
      expect(MapCoordinate.fromTap(14, 541).longitude, -179);
      expect(MapCoordinate.fromTap(14, -541).longitude, 179);
      expect(MapCoordinate.fromTap(100, 0).latitude, 90);
      expect(const MapCoordinate(0, 0).label, '0.000000, 0.000000');
    },
  );
  testWidgets('every category generates a distinct custom PNG pin', (
    tester,
  ) async {
    final pins = await tester.runAsync(() async {
      final result = <List<int>>[];
      for (final marker in categoryMarkers.values) {
        result.add(await markerImage(marker));
      }
      return result;
    });
    expect(pins, hasLength(5));
    for (final pin in pins!) {
      expect(pin.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    }
    expect(pins.map((p) => p.toString()).toSet(), hasLength(5));
  });
  test(
    'location permission is requested only when denied; granted fix works',
    () async {
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.denied;
      final service = JournalLocation(gateway: gateway);
      final point = await service.locate();
      expect(point.latitude, 14.6);
      expect(gateway.requests, 1);
      expect(gateway.fixes, 1);
      gateway.permission = LocationPermission.whileInUse;
      await service.locate();
      expect(gateway.requests, 1);
      expect(gateway.fixes, 2);
    },
  );
  test(
    'disabled location and permanent denial do not fetch a position or reprompt',
    () async {
      final gateway = FakeLocationGateway()..enabled = false;
      final service = JournalLocation(gateway: gateway);
      await expectLater(
        service.locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.servicesDisabled,
          ),
        ),
      );
      expect(gateway.requests, 0);
      expect(gateway.fixes, 0);
      await service.settings(LocationIssue.servicesDisabled);
      expect(gateway.locationSettings, 1);
      gateway.enabled = true;
      gateway.permission = LocationPermission.deniedForever;
      await expectLater(
        service.locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.deniedForever,
          ),
        ),
      );
      expect(gateway.requests, 0);
      expect(gateway.fixes, 0);
      await service.settings(LocationIssue.deniedForever);
      expect(gateway.appSettings, 1);
    },
  );
  test(
    'denied, undetermined, timed-out and failed fixes have recoverable outcomes',
    () async {
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.denied
        ..requested = LocationPermission.denied;
      final service = JournalLocation(gateway: gateway);
      await expectLater(
        service.locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.denied,
          ),
        ),
      );
      expect(gateway.fixes, 0);
      gateway.permission = LocationPermission.unableToDetermine;
      await expectLater(service.locate(), throwsA(isA<LocationFailure>()));
      expect(gateway.fixes, 0);
      gateway.permission = LocationPermission.whileInUse;
      gateway.positionError = TimeoutException('No fix');
      await expectLater(
        service.locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.timedOut,
          ),
        ),
      );
      gateway.positionError = StateError('Sensor unavailable');
      await expectLater(
        service.locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.unavailable,
          ),
        ),
      );
    },
  );
}
