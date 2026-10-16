import 'package:flutter/material.dart';

class MapCoordinate {
  const MapCoordinate(this.latitude, this.longitude);
  final double latitude, longitude;
  String get label =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  static MapCoordinate fromTap(double latitude, double longitude) =>
      MapCoordinate(
        latitude.clamp(-90, 90).toDouble(),
        ((longitude + 180) % 360 + 360) % 360 - 180,
      );
}

class CategoryMarker {
  const CategoryMarker(this.key, this.color, this.icon);
  final String key;
  final Color color;
  final IconData icon;
}

const categoryMarkers = <String, CategoryMarker>{
  'Other': CategoryMarker('other', Color(0xFF52616B), Icons.place),
  'Nature': CategoryMarker('nature', Color(0xFF35734F), Icons.park),
  'Food & drink': CategoryMarker('food', Color(0xFFB96A32), Icons.restaurant),
  'Culture': CategoryMarker('culture', Color(0xFF79549A), Icons.museum),
  'Stay': CategoryMarker('stay', Color(0xFF326C9E), Icons.hotel),
};
CategoryMarker markerForCategory(String category) =>
    categoryMarkers[category] ?? categoryMarkers['Other']!;

/// Only coordinates, category icons, and local identifiers enter the map source.
/// Journal notes and photos are never passed to the basemap provider.
Map<String, dynamic> placesGeoJson(List<Map<String, Object?>> places) => {
  'type': 'FeatureCollection',
  'features': places
      .map(
        (place) => {
          'type': 'Feature',
          'id': place['id'],
          'geometry': {
            'type': 'Point',
            'coordinates': [place['longitude'], place['latitude']],
          },
          'properties': {
            'place_id': place['id'],
            'marker': markerForCategory(place['category'] as String).key,
          },
        },
      )
      .toList(),
};
Map<String, dynamic> coordinateGeoJson(MapCoordinate? coordinate) => {
  'type': 'FeatureCollection',
  'features': [
    if (coordinate != null)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [coordinate.longitude, coordinate.latitude],
        },
        'properties': <String, dynamic>{},
      },
  ],
};

const mapStyleUrl = String.fromEnvironment(
  'MAP_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/bright',
);
const placesSourceId = 'journal-places';
const placesLayerId = 'journal-place-markers';
const clustersLayerId = 'journal-clusters';
const clusterCountLayerId = 'journal-cluster-count';
const clusterFilter = ['has', 'point_count'];
const pointFilter = [
  '!',
  ['has', 'point_count'],
];
