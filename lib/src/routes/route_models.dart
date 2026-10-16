import 'dart:convert';
import '../map/map_data.dart';

class RouteStop {
  const RouteStop({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.placeId,
  });
  final String name;
  final double latitude, longitude;
  final int? placeId;
  MapCoordinate get coordinate => MapCoordinate(latitude, longitude);
  bool get valid =>
      name.trim().isNotEmpty &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  factory RouteStop.fromPlace(Map<String, Object?> row) => RouteStop(
    name: row['name'] as String,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    placeId: row['id'] as int?,
  );
  factory RouteStop.fromRow(Map<String, Object?> row) => RouteStop(
    name: row['name'] as String,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    placeId: row['place_id'] as int?,
  );
  Map<String, Object?> toRow() => {
    'name': name.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'place_id': placeId,
  };
}

String stopSignature(List<RouteStop> stops) =>
    jsonEncode(stops.map((s) => [s.latitude, s.longitude]).toList());

class RoadRoute {
  RoadRoute({
    required Map<String, dynamic> geometry,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.stopsSignature,
  }) : geometry = Map.unmodifiable({
         ...geometry,
         'coordinates': List.unmodifiable(
           (geometry['coordinates'] as List).map(
             (c) => List<num>.unmodifiable((c as List).cast<num>()),
           ),
         ),
       }) {
    if (!distanceMeters.isFinite ||
        distanceMeters < 0 ||
        !durationSeconds.isFinite ||
        durationSeconds < 0 ||
        geometry['type'] != 'LineString') {
      throw const FormatException('Invalid route metrics');
    }
    final coordinates = geometry['coordinates'] as List;
    if (coordinates.length < 2 ||
        coordinates.any(
          (c) =>
              c is! List ||
              c.length < 2 ||
              c[0] is! num ||
              c[1] is! num ||
              !(c[0] as num).isFinite ||
              !(c[1] as num).isFinite ||
              (c[0] as num).abs() > 180 ||
              (c[1] as num).abs() > 90,
        )) {
      throw const FormatException('Invalid road geometry');
    }
  }
  final Map<String, dynamic> geometry;
  final double distanceMeters, durationSeconds;
  final String stopsSignature;
}

String routeDistance(num? meters) => meters == null
    ? 'Not calculated'
    : meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
String routeDuration(num? seconds) {
  if (seconds == null) return 'Not calculated';
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
  return '${minutes ~/ 60} hr${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}';
}
