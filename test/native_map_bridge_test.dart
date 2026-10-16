import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';

/// Exercises the real MapLibre widget/controller bridge with a fake SDK surface.
class RecordingMapPlatform extends MapLibrePlatform {
  bool created = false, disposed = false;
  final sources = <String, Map<String, dynamic>>{};
  final layers = <String, Map<String, dynamic>>{};
  final images = <String>[];
  final updates = <String, Map<String, dynamic>>{};
  final updateCounts = <String, int>{};
  final optionUpdates = <Map<String, dynamic>>[];
  final cameras = <dynamic>[];
  final trackingModes = <MyLocationTrackingMode>[];
  final cameraActions = <String>[];
  List<dynamic> hits = [];
  int? expandedCluster;
  @override
  Future<void> initPlatform(int id) async {}
  @override
  Future<CameraPosition?> updateMapOptions(
    Map<String, dynamic> optionsUpdate,
  ) async {
    optionUpdates.add(optionsUpdate);
    return null;
  }

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    if (!created) {
      created = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onPlatformViewCreated(1),
      );
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> addSource(String sourceId, SourceProperties properties) async {
    sources[sourceId] = properties.toJson();
  }

  @override
  Future<void> addImage(
    String name,
    Uint8List bytes, [
    bool sdf = false,
  ]) async {
    images.add(name);
  }

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    updates[sourceId] = geojson;
    updateCounts.update(sourceId, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  Future<void> addLineLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    layers[layerId] = {
      'source': sourceId,
      'filter': filter,
      'properties': properties,
    };
  }

  @override
  Future<void> addCircleLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    layers[layerId] = {
      'source': sourceId,
      'filter': filter,
      'properties': properties,
    };
  }

  @override
  Future<void> addSymbolLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    required bool enableInteraction,
  }) async {
    layers[layerId] = {
      'source': sourceId,
      'filter': filter,
      'properties': properties,
    };
  }

  @override
  Future<bool?> animateCamera(
    CameraUpdate cameraUpdate, {
    Duration? duration,
  }) async {
    cameras.add(cameraUpdate.toJson());
    cameraActions.add('camera');
    return true;
  }

  @override
  Future<void> updateMyLocationTrackingMode(MyLocationTrackingMode mode) async {
    trackingModes.add(mode);
    cameraActions.add('tracking:$mode');
  }

  @override
  Future<List> queryRenderedFeatures(
    Point<double> point,
    List<String> layerIds,
    List<Object>? filter,
  ) async => hits;
  @override
  Future<int> getClusterExpansionZoom(String sourceId, int clusterId) async {
    expandedCluster = clusterId;
    return 12;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected map SDK call: ${invocation.memberName}',
  );
}

void main() {
  testWidgets(
    'native bridge waits for style, clusters, expands taps, updates records, and disposes',
    (tester) async {
      final previousFactory = MapLibrePlatform.createInstance;
      final sdk = RecordingMapPlatform();
      MapLibrePlatform.createInstance = () => sdk;
      addTearDown(() => MapLibrePlatform.createInstance = previousFactory);
      var ready = false;
      final errors = <String>[];
      List<int>? selected;
      MapCoordinate? tapped;
      final records = [
        <String, Object?>{
          'id': 1,
          'name': 'Trail',
          'category': 'Nature',
          'latitude': 14.0,
          'longitude': 120.0,
        },
        <String, Object?>{
          'id': 2,
          'name': 'Cafe',
          'category': 'Food & drink',
          'latitude': 14.0,
          'longitude': 120.0,
        },
      ];
      Map<String, dynamic>? roadGeometry;
      List<MapCoordinate> routePoints = const [];
      int? selectedStop;
      Widget map(List<Map<String, Object?>> records) => MaterialApp(
        home: Scaffold(
          body: NativePlaceMap(
            options: MapCanvasOptions(
              places: records,
              routeGeometry: roadGeometry,
              routeStops: routePoints,
              onRouteStopSelected: routePoints.isEmpty
                  ? null
                  : (index) => selectedStop = index,
              onReady: () => ready = true,
              onError: errors.add,
              onPlacesSelected: (ids) => selected = ids,
              onCoordinateSelected: (point) => tapped = point,
            ),
          ),
        ),
      );
      await tester.pumpWidget(map(records));
      await tester.pumpAndSettle();
      expect(sdk.sources, isEmpty);
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 20 && !ready; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      expect(errors, isEmpty);
      expect(ready, isTrue);
      expect(sdk.images, hasLength(5));
      expect(sdk.sources[placesSourceId], containsPair('cluster', true));
      expect(sdk.sources[placesSourceId], containsPair('clusterMaxZoom', 14));
      expect(sdk.layers[clustersLayerId]!['filter'], clusterFilter);
      expect(sdk.layers[placesLayerId]!['filter'], pointFilter);
      expect((sdk.updates[placesSourceId]!['features'] as List), hasLength(2));
      final initialCounts = Map.of(sdk.updateCounts);
      // Parent rebuilds and journal text edits do not resend map sources.
      await tester.pumpWidget(
        map(
          records.map((r) => {...r, 'notes': 'Edited private note'}).toList(),
        ),
      );
      await tester.pumpAndSettle();
      expect(sdk.updateCounts, initialCounts);
      sdk.hits = [
        {
          'properties': {'cluster_id': 7.0, 'point_count': 40},
          'geometry': {
            'type': 'Point',
            'coordinates': [120.0, 14.0],
          },
        },
      ];
      sdk.onMapClickPlatform({
        'point': const Point<double>(40, 40),
        'latLng': const LatLng(14.1, 120.1),
      });
      await tester.pumpAndSettle();
      expect(sdk.expandedCluster, 7);
      expect(
        sdk.cameras.last,
        CameraUpdate.newLatLngZoom(const LatLng(14, 120), 12).toJson(),
      );
      expect(tapped, isNull);
      sdk.hits = [
        {
          'properties': {'place_id': 1.0},
        },
        {
          'properties': {'place_id': 2},
        },
        {
          'properties': {'place_id': 1},
        },
      ];
      sdk.onMapClickPlatform({
        'point': const Point<double>(40, 40),
        'latLng': const LatLng(14, 120),
      });
      await tester.pumpAndSettle();
      expect(selected, [1, 2]);
      await tester.pumpWidget(map([records.last]));
      await tester.pumpAndSettle();
      expect((sdk.updates[placesSourceId]!['features'] as List), hasLength(1));
      sdk.onMapClickPlatform({
        'point': const Point<double>(40, 40),
        'latLng': const LatLng(14, 120),
      });
      await tester.pumpAndSettle();
      expect(selected, [2]);
      roadGeometry = {
        'type': 'LineString',
        'coordinates': [
          [120.0, 14.0],
          [120.1, 14.1],
        ],
      };
      routePoints = const [MapCoordinate(14, 120), MapCoordinate(14.1, 120.1)];
      await tester.pumpWidget(map([records.last]));
      await tester.pumpAndSettle();
      expect(
        (sdk.updates['planned-road']!['features'] as List).single['geometry'],
        roadGeometry,
      );
      expect(
        sdk.layers['planned-road-line']!['properties'],
        containsPair('line-width', 5),
      );
      expect((sdk.updates['route-stops']!['features'] as List), hasLength(2));
      final withRoadCounts = Map.of(sdk.updateCounts);
      await tester.pumpWidget(map([records.last]));
      await tester.pumpAndSettle();
      expect(sdk.updateCounts, withRoadCounts);
      sdk.hits = [
        {
          'properties': {'index': 1},
        },
      ];
      sdk.onMapClickPlatform({
        'point': const Point<double>(40, 40),
        'latLng': const LatLng(14.1, 120.1),
      });
      await tester.pumpAndSettle();
      expect(selectedStop, 1);
      roadGeometry = null;
      routePoints = const [];
      await tester.pumpWidget(map([records.last]));
      await tester.pumpAndSettle();
      expect(sdk.updates['planned-road']!['features'], isEmpty);
      sdk.hits = [];
      sdk.onMapClickPlatform({
        'point': const Point<double>(80, 80),
        'latLng': const LatLng(0, 0),
      });
      await tester.pumpAndSettle();
      expect(tapped!.latitude, 0);
      expect(tapped!.longitude, 0);
      ready = false;
      sdk.sources.clear();
      sdk.layers.clear();
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 20 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready, isTrue);
      expect(sdk.sources, contains(placesSourceId));
      expect(sdk.layers, contains(placesLayerId));
      expect(sdk.images, hasLength(10));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(sdk.disposed, isTrue);
    },
  );

  testWidgets(
    'large place source is uploaded once while selection updates stay small',
    (tester) async {
      final previousFactory = MapLibrePlatform.createInstance;
      final sdk = RecordingMapPlatform();
      MapLibrePlatform.createInstance = () => sdk;
      addTearDown(() => MapLibrePlatform.createInstance = previousFactory);
      final records = List.generate(
        10000,
        (i) => <String, Object?>{
          'id': i + 1,
          'latitude': 13.5 + (i % 100) / 100,
          'longitude': 120.5 + (i ~/ 100) / 100,
          'category': 'Nature',
        },
      );
      var ready = false;
      Widget map(MapCoordinate? selected) => MaterialApp(
        home: Scaffold(
          body: NativePlaceMap(
            options: MapCanvasOptions(
              places: records,
              selected: selected,
              onPlacesSelected: (_) {},
              onCoordinateSelected: (_) {},
              onReady: () => ready = true,
              onError: (e) => fail(e),
            ),
          ),
        ),
      );
      await tester.pumpWidget(map(null));
      await tester.pumpAndSettle();
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 20 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready, isTrue);
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(map(MapCoordinate(13.9 + i / 100, 121.05)));
        await tester.pumpAndSettle();
      }
      expect(sdk.updateCounts[placesSourceId], 1);
      expect(sdk.updateCounts['journal-selection'], 5);
      expect(sdk.updateCounts['planned-road'], isNull);
      expect((sdk.updates[placesSourceId]!['features'] as List).length, 10000);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline area honors its style and camera limits and unclusters pins before maximum zoom',
    (tester) async {
      final previousFactory = MapLibrePlatform.createInstance;
      final sdk = RecordingMapPlatform();
      MapLibrePlatform.createInstance = () => sdk;
      addTearDown(() => MapLibrePlatform.createInstance = previousFactory);
      final region = gl.OfflineRegionDefinition(
        bounds: LatLngBounds(
          southwest: const LatLng(13.7, 120.9),
          northeast: const LatLng(14.1, 121.2),
        ),
        mapStyleUrl: 'https://example.test/prepared-style.json',
        minZoom: 9,
        maxZoom: 13,
      );
      var ready = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativePlaceMap(
              options: MapCanvasOptions(
                places: const [],
                offlineRegion: region,
                onPlacesSelected: (_) {},
                onCoordinateSelected: (_) {},
                onReady: () => ready = true,
                onError: (e) => fail(e),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final map = tester.widget<gl.MapLibreMap>(find.byType(gl.MapLibreMap));
      expect(map.styleString, region.mapStyleUrl);
      expect(map.minMaxZoomPreference.minZoom, 9);
      expect(map.minMaxZoomPreference.maxZoom, 13);
      expect(map.cameraTargetBounds.bounds, region.bounds);
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 20 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready, isTrue);
      expect(sdk.sources[placesSourceId], containsPair('clusterMaxZoom', 12));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
