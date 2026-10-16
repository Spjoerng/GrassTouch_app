import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'map_data.dart';

class MapCameraRequest {
  MapCameraRequest.fit() : target = null;
  MapCameraRequest.focus(this.target);
  final MapCoordinate? target;
}

class MapCanvasOptions {
  const MapCanvasOptions({
    required this.places,
    required this.onPlacesSelected,
    required this.onCoordinateSelected,
    required this.onReady,
    required this.onError,
    this.selected,
    this.location,
    this.camera,
  });
  final List<Map<String, Object?>> places;
  final ValueChanged<List<int>> onPlacesSelected;
  final ValueChanged<MapCoordinate> onCoordinateSelected;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final MapCoordinate? selected, location;
  final MapCameraRequest? camera;
}

typedef MapCanvasBuilder =
    Widget Function(BuildContext context, MapCanvasOptions options);

class NativePlaceMap extends StatefulWidget {
  const NativePlaceMap({super.key, required this.options});
  final MapCanvasOptions options;
  @override
  State<NativePlaceMap> createState() => _NativePlaceMapState();
}

class _NativePlaceMapState extends State<NativePlaceMap> {
  MapLibreMapController? controller;
  bool ready = false, initializing = false;
  Future<void> work = Future.value();
  MapCameraRequest? appliedCamera;
  String? appliedPlaces;
  void enqueue(Future<void> Function() action) {
    work = work
        .then((_) async {
          if (mounted && controller != null) await action();
        })
        .catchError((Object error) {
          if (mounted) {
            widget.options.onError(
              'The map could not be updated. Retry the map or use the list.',
            );
          }
        });
  }

  Future<void> initialize() async {
    if (ready || initializing || controller == null) return;
    initializing = true;
    try {
      final map = controller!;
      for (final marker in categoryMarkers.values) {
        await map.addImage('journal-${marker.key}', await markerImage(marker));
      }
      await map.addSource(
        placesSourceId,
        GeojsonSourceProperties(
          data: placesGeoJson(widget.options.places),
          cluster: true,
          clusterRadius: 48,
          clusterMaxZoom: 14,
        ),
      );
      await map.addCircleLayer(
        placesSourceId,
        clustersLayerId,
        const CircleLayerProperties(
          circleColor: '#254F40',
          circleRadius: [
            'step',
            ['get', 'point_count'],
            20,
            10,
            26,
            50,
            32,
          ],
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
        filter: clusterFilter,
      );
      await map.addSymbolLayer(
        placesSourceId,
        clusterCountLayerId,
        const SymbolLayerProperties(
          textField: [
            'to-string',
            ['get', 'point_count_abbreviated'],
          ],
          textFont: ['Noto Sans Regular'],
          textSize: 13,
          textColor: '#ffffff',
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: clusterFilter,
      );
      await map.addSymbolLayer(
        placesSourceId,
        placesLayerId,
        const SymbolLayerProperties(
          iconImage: [
            'concat',
            'journal-',
            ['get', 'marker'],
          ],
          iconSize: 0.6,
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        filter: pointFilter,
      );
      await map.addSource(
        'journal-location',
        GeojsonSourceProperties(data: coordinateGeoJson(null)),
      );
      await map.addCircleLayer(
        'journal-location',
        'journal-location-dot',
        const CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#247DE3',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 3,
        ),
        enableInteraction: false,
      );
      await map.addSource(
        'journal-selection',
        GeojsonSourceProperties(data: coordinateGeoJson(null)),
      );
      await map.addCircleLayer(
        'journal-selection',
        'journal-selection-dot',
        const CircleLayerProperties(
          circleRadius: 10,
          circleColor: '#D7782B',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 3,
        ),
        enableInteraction: false,
      );
      if (!mounted) return;
      ready = true;
      await applyOptions();
      if (mounted) widget.options.onReady();
    } finally {
      initializing = false;
    }
  }

  Future<void> applyOptions() async {
    final map = controller!;
    final options = widget.options;
    final data = placesGeoJson(options.places);
    final signature = jsonEncode(data);
    if (signature != appliedPlaces) {
      await map.setGeoJsonSource(placesSourceId, data);
      appliedPlaces = signature;
    }
    await map.setGeoJsonSource(
      'journal-selection',
      coordinateGeoJson(options.selected),
    );
    await map.setGeoJsonSource(
      'journal-location',
      coordinateGeoJson(options.location),
    );
    if (options.camera != null && !identical(options.camera, appliedCamera)) {
      if (options.camera!.target == null) {
        await fitPlaces();
      } else {
        final target = options.camera!.target!;
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(target.latitude, target.longitude),
            15,
          ),
        );
      }
      appliedCamera = options.camera;
    }
  }

  Future<void> fitPlaces() async {
    final places = widget.options.places;
    if (places.isEmpty) return;
    final coordinates = places
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    final south = coordinates.map((p) => p.latitude).reduce(math.min);
    final north = coordinates.map((p) => p.latitude).reduce(math.max);
    final west = coordinates.map((p) => p.longitude).reduce(math.min);
    final east = coordinates.map((p) => p.longitude).reduce(math.max);
    if (south == north && west == east) {
      await controller!.animateCamera(
        CameraUpdate.newLatLngZoom(coordinates.first, 13),
      );
    } else {
      await controller!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          left: 48,
          right: 48,
          top: 48,
          bottom: 64,
        ),
      );
    }
  }

  void tap(math.Point<double> point, LatLng coordinate) => enqueue(() async {
    if (!ready) return;
    final features = await controller!.queryRenderedFeatures(point, [
      placesLayerId,
      clustersLayerId,
    ], null);
    if (!mounted) return;
    final ids = <int>{};
    for (final feature in features) {
      final properties = (feature as Map)['properties'] as Map?;
      final id = properties?['place_id'];
      if (id is num &&
          widget.options.places.any((p) => p['id'] == id.toInt())) {
        ids.add(id.toInt());
      }
    }
    if (ids.isNotEmpty) {
      widget.options.onPlacesSelected(ids.toList());
      return;
    }
    if (features.isNotEmpty) {
      final feature = features.first as Map;
      final properties = feature['properties'] as Map?;
      final clusterId = (properties?['cluster_id'] as num?)?.toInt();
      if (clusterId != null) {
        final zoom = await controller!.getClusterExpansionZoom(
          placesSourceId,
          clusterId,
        );
        final coords = (feature['geometry'] as Map)['coordinates'] as List;
        await controller!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              (coords[1] as num).toDouble(),
              (coords[0] as num).toDouble(),
            ),
            zoom.toDouble().clamp(0, 20),
          ),
        );
        return;
      }
    }
    if (mounted) {
      widget.options.onCoordinateSelected(
        MapCoordinate.fromTap(coordinate.latitude, coordinate.longitude),
      );
    }
  });
  @override
  void didUpdateWidget(covariant NativePlaceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready) enqueue(applyOptions);
  }

  @override
  Widget build(BuildContext context) => MapLibreMap(
    styleString: mapStyleUrl,
    initialCameraPosition: const CameraPosition(
      target: LatLng(13.9, 121.05),
      zoom: 9,
    ),
    onMapCreated: (map) => controller = map,
    onStyleLoadedCallback: () => enqueue(initialize),
    onMapClick: tap,
    featureTapsTriggersMapClick: true,
    // We own clustered style layers, so annotation managers are unnecessary.
    annotationOrder: const [],
    attributionButtonPosition: AttributionButtonPosition.bottomLeft,
    attributionButtonMargins: math.Point(
      8,
      widget.options.selected == null ? 8 : 176,
    ),
    compassViewPosition: CompassViewPosition.topLeft,
    compassViewMargins: const math.Point(16, 132),
    trackCameraPosition: true,
    // Location is a single user-requested fix, drawn from our local GeoJSON
    // source. The map SDK never starts a second location engine or prompt.
    myLocationEnabled: false,
  );
}

Future<Uint8List> markerImage(CategoryMarker marker) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final pin = Path()
    ..moveTo(32, 77)
    ..cubicTo(27, 65, 5, 46, 5, 30)
    ..arcToPoint(const Offset(59, 30), radius: const Radius.circular(27))
    ..cubicTo(59, 46, 37, 65, 32, 77)
    ..close();
  canvas.drawPath(pin, Paint()..color = marker.color);
  canvas.drawPath(
    pin,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(marker.icon.codePoint),
      style: TextStyle(
        fontFamily: marker.icon.fontFamily,
        package: marker.icon.fontPackage,
        fontSize: 29,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(32 - painter.width / 2, 29 - painter.height / 2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 80);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  painter.dispose();
  return bytes;
}
