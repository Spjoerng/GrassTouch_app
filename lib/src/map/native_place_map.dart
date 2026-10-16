import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    this.liveLocation = false,
    this.followLocation = false,
    this.onFollowLocationDismissed,
    this.camera,
    this.routeGeometry,
    this.routeStops = const [],
    this.selectedRouteStop,
    this.onRouteStopSelected,
    this.offlineRegion,
  });
  final List<Map<String, Object?>> places;
  final ValueChanged<List<int>> onPlacesSelected;
  final ValueChanged<MapCoordinate> onCoordinateSelected;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final MapCoordinate? selected, location;
  final bool liveLocation, followLocation;
  final VoidCallback? onFollowLocationDismissed;
  final MapCameraRequest? camera;
  final Map<String, dynamic>? routeGeometry;
  final List<MapCoordinate> routeStops;
  final int? selectedRouteStop;
  final ValueChanged<int>? onRouteStopSelected;
  final OfflineRegionDefinition? offlineRegion;
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
  List<(Object?, Object?, Object?, String)>? appliedPlaces;
  MapCoordinate? appliedSelection, appliedLocation;
  Map<String, dynamic>? appliedRoad;
  List<(double, double)> appliedStops = const [];
  int? appliedStopSelection;
  bool optionsQueued = false;
  bool appliedFollowing = false;
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
      await map.addSource(
        'planned-road',
        GeojsonSourceProperties(data: routeLineGeoJson(null)),
      );
      await map.addLineLayer(
        'planned-road',
        'planned-road-casing',
        const LineLayerProperties(
          lineColor: '#ffffff',
          lineWidth: 9,
          lineJoin: 'round',
          lineCap: 'round',
        ),
        enableInteraction: false,
      );
      await map.addLineLayer(
        'planned-road',
        'planned-road-line',
        const LineLayerProperties(
          lineColor: '#237854',
          lineWidth: 5,
          lineJoin: 'round',
          lineCap: 'round',
        ),
        enableInteraction: false,
      );
      for (final marker in categoryMarkers.values) {
        final bytes = await cachedMarkerImage(marker);
        if (!mounted) return;
        await map.addImage('journal-${marker.key}', bytes);
      }
      await map.addSource(
        placesSourceId,
        GeojsonSourceProperties(
          data: placesGeoJson(const []),
          cluster: true,
          clusterRadius: 48,
          clusterMaxZoom: widget.options.offlineRegion == null
              ? 14
              : math.max(
                  0,
                  math.min(
                    14,
                    widget.options.offlineRegion!.maxZoom.floor() - 1,
                  ),
                ),
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
      await map.addSource(
        'route-stops',
        GeojsonSourceProperties(data: routeStopsGeoJson(const [])),
      );
      await map.addCircleLayer(
        'route-stops',
        'route-stop-dots',
        const CircleLayerProperties(
          circleColor: [
            'case',
            ['get', 'selected'],
            '#D7782B',
            '#254F40',
          ],
          circleRadius: 14,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 3,
        ),
      );
      await map.addSymbolLayer(
        'route-stops',
        'route-stop-labels',
        const SymbolLayerProperties(
          textField: ['get', 'label'],
          textFont: ['Noto Sans Regular'],
          textSize: 12,
          textColor: '#ffffff',
          textAllowOverlap: true,
          textIgnorePlacement: true,
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
    final signature = options.places
        .map(
          (p) => (
            p['id'],
            p['latitude'],
            p['longitude'],
            markerForCategory(p['category'] as String).key,
          ),
        )
        .toList();
    if (!listEquals(signature, appliedPlaces)) {
      await map.setGeoJsonSource(placesSourceId, placesGeoJson(options.places));
      appliedPlaces = signature;
    }
    if (!mounted) return;
    if (!sameCoordinate(options.selected, appliedSelection)) {
      await map.setGeoJsonSource(
        'journal-selection',
        coordinateGeoJson(options.selected),
      );
      appliedSelection = options.selected;
    }
    if (!mounted) return;
    // The native location component owns the live dot and compass indicator.
    // Keep the GeoJSON dot only for a static observation.
    final staticLocation = options.liveLocation ? null : options.location;
    if (!sameCoordinate(staticLocation, appliedLocation)) {
      await map.setGeoJsonSource(
        'journal-location',
        coordinateGeoJson(staticLocation),
      );
      appliedLocation = staticLocation;
    }
    if (!mounted) return;
    // Route models supply immutable geometry; do not serialize and upload a
    // potentially large road line when only the selection or search changes.
    if (!identical(options.routeGeometry, appliedRoad)) {
      await map.setGeoJsonSource(
        'planned-road',
        routeLineGeoJson(options.routeGeometry),
      );
      appliedRoad = options.routeGeometry;
    }
    if (!mounted) return;
    final stops = options.routeStops
        .map((s) => (s.latitude, s.longitude))
        .toList();
    if (!listEquals(stops, appliedStops) ||
        options.selectedRouteStop != appliedStopSelection) {
      await map.setGeoJsonSource(
        'route-stops',
        routeStopsGeoJson(
          options.routeStops,
          selected: options.selectedRouteStop,
        ),
      );
      appliedStops = stops;
      appliedStopSelection = options.selectedRouteStop;
    }
    if (!mounted) return;
    if (options.camera != null && !identical(options.camera, appliedCamera)) {
      // Programmatic camera moves end native tracking on Android. Apply the
      // requested camera first, then enable following after it completes.
      if (appliedFollowing) {
        appliedFollowing = false;
        await map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
      }
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
    if (!mounted) return;
    // Camera/source work can outlive a stop or pan gesture. Honor the latest
    // intent rather than restoring tracking from the queued options snapshot.
    final follow = widget.options.liveLocation && widget.options.followLocation;
    if (follow != appliedFollowing) {
      appliedFollowing = follow;
      await map.updateMyLocationTrackingMode(
        follow ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.none,
      );
    }
  }

  Future<void> fitPlaces() async {
    final places = widget.options.places;
    final coordinates = places
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    coordinates.addAll(
      widget.options.routeStops.map((p) => LatLng(p.latitude, p.longitude)),
    );
    final routeCoords = widget.options.routeGeometry?['coordinates'] as List?;
    if (routeCoords != null) {
      coordinates.addAll(
        routeCoords.map(
          (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ),
      );
    }
    if (coordinates.isEmpty) return;
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
    if (widget.options.onRouteStopSelected != null) {
      final stops = await controller!.queryRenderedFeatures(point, [
        'route-stop-dots',
      ], null);
      if (!mounted) return;
      if (stops.isNotEmpty) {
        final index =
            (((stops.first as Map)['properties'] as Map)['index'] as num)
                .toInt();
        widget.options.onRouteStopSelected!(index);
        return;
      }
    }
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
    if (ready && !optionsQueued) {
      optionsQueued = true;
      enqueue(() async {
        optionsQueued = false;
        await applyOptions();
      });
    }
  }

  @override
  Widget build(BuildContext context) => MapLibreMap(
    styleString: widget.options.offlineRegion?.mapStyleUrl ?? mapStyleUrl,
    initialCameraPosition: initialCamera(widget.options.offlineRegion),
    minMaxZoomPreference: widget.options.offlineRegion == null
        ? MinMaxZoomPreference.unbounded
        : MinMaxZoomPreference(
            widget.options.offlineRegion!.minZoom,
            widget.options.offlineRegion!.maxZoom,
          ),
    cameraTargetBounds: widget.options.offlineRegion == null
        ? CameraTargetBounds.unbounded
        : CameraTargetBounds(widget.options.offlineRegion!.bounds),
    onMapCreated: (map) => controller = map,
    onStyleLoadedCallback: () => enqueue(() async {
      // A reloaded native style has lost our custom layers and images.
      ready = false;
      appliedPlaces = null;
      appliedSelection = null;
      appliedLocation = null;
      appliedFollowing = false;
      appliedRoad = null;
      appliedStops = const [];
      appliedStopSelection = null;
      await initialize();
    }),
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
    trackCameraPosition: false,
    // Permission is checked by JournalLocation before this is enabled. The
    // native engine owns continuous foreground updates and sensor heading.
    myLocationEnabled: widget.options.liveLocation,
    locationEnginePlatforms: defaultTargetPlatform == TargetPlatform.iOS
        ? const LocationEnginePlatforms.iOS(enableHighAccuracy: true)
        : const LocationEnginePlatforms.android(enableHighAccuracy: true),
    myLocationRenderMode: widget.options.liveLocation
        ? MyLocationRenderMode.compass
        : MyLocationRenderMode.normal,
    onCameraTrackingDismissed: () {
      if (!mounted || !appliedFollowing) return;
      appliedFollowing = false;
      widget.options.onFollowLocationDismissed?.call();
    },
  );
}

bool sameCoordinate(MapCoordinate? a, MapCoordinate? b) =>
    a?.latitude == b?.latitude && a?.longitude == b?.longitude;

CameraPosition initialCamera(OfflineRegionDefinition? region) {
  if (region == null) {
    return const CameraPosition(target: LatLng(13.9, 121.05), zoom: 9);
  }
  final bounds = region.bounds;
  final west = bounds.southwest.longitude;
  var east = bounds.northeast.longitude;
  if (east < west) east += 360;
  return CameraPosition(
    target: LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      ((west + east) / 2 + 180) % 360 - 180,
    ),
    zoom: region.minZoom,
  );
}

final _markerImages = <String, Uint8List>{};
final _pendingMarkerImages = <String, Future<Uint8List>>{};
Future<Uint8List> cachedMarkerImage(CategoryMarker marker) async {
  final cached = _markerImages[marker.key];
  if (cached != null) return cached;
  final pending = _pendingMarkerImages.putIfAbsent(
    marker.key,
    () => markerImage(marker),
  );
  try {
    final bytes = await pending;
    _markerImages[marker.key] = bytes;
    return bytes;
  } finally {
    _pendingMarkerImages.remove(marker.key);
  }
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
  ui.Image? image;
  try {
    image = await picture.toImage(64, 80);
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image?.dispose();
    picture.dispose();
    painter.dispose();
  }
}
