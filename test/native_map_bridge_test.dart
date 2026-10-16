import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';

/// Exercises the real MapLibre widget/controller bridge with a fake SDK surface.
class RecordingMapPlatform extends MapLibrePlatform {
  bool created = false, disposed = false;
  final sources = <String, Map<String, dynamic>>{};
  final layers = <String, Map<String, dynamic>>{};
  final images = <String>[];
  final updates = <String, Map<String, dynamic>>{};
  final cameras = <dynamic>[];
  List<dynamic> hits = [];
  int? expandedCluster;
  @override
  Future<void> initPlatform(int id) async {}
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
    return true;
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
      Widget map(List<Map<String, Object?>> records) => MaterialApp(
        home: Scaffold(
          body: NativePlaceMap(
            options: MapCanvasOptions(
              places: records,
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
      sdk.hits = [];
      sdk.onMapClickPlatform({
        'point': const Point<double>(80, 80),
        'latLng': const LatLng(0, 0),
      });
      await tester.pumpAndSettle();
      expect(tapped!.latitude, 0);
      expect(tapped!.longitude, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(sdk.disposed, isTrue);
    },
  );
}
