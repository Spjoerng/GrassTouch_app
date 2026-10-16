import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show OfflineRegionDefinition;
import 'journal_location.dart';
import 'journal_map_view.dart';
import 'map_data.dart';
import 'native_place_map.dart';

class PlaceLocationPicker extends StatelessWidget {
  const PlaceLocationPicker({
    super.key,
    this.initialLocation,
    this.canvasBuilder,
    this.locationService,
    this.offlineRegion,
  });
  final MapCoordinate? initialLocation;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  final OfflineRegionDefinition? offlineRegion;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a location')),
    body: Stack(
      children: [
        Positioned.fill(
          child: JournalMapView(
            places: const [],
            initialSelection: initialLocation,
            selectionActionLabel: 'Use this location',
            fallbackActionLabel: 'Back to place form',
            onPlacesSelected: (_) {},
            onSaveCoordinate: (point) async {
              Navigator.pop(context, point);
              return true;
            },
            onShowList: () => Navigator.pop(context),
            canvasBuilder: canvasBuilder,
            locationService: locationService,
            offlineRegion: offlineRegion,
          ),
        ),
        const Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tap a spot on the map, or use My location. Confirm the pin to continue.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
