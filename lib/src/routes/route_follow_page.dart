import 'package:flutter/material.dart';
import '../map/journal_location.dart';
import '../map/journal_map_view.dart';
import '../map/native_place_map.dart';
import 'route_models.dart';

/// A foreground route viewer. Live movement never modifies the saved route.
class RouteFollowPage extends StatelessWidget {
  const RouteFollowPage({
    super.key,
    required this.name,
    required this.stops,
    required this.road,
    this.canvasBuilder,
    this.locationService,
  });
  final String name;
  final List<RouteStop> stops;
  final RoadRoute road;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(
      title: const Text('Follow route'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('End following'),
        ),
      ],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: JournalMapView(
              places: const [],
              routeGeometry: road.geometry,
              routeStops: stops
                  .map((s) => s.coordinate)
                  .toList(growable: false),
              initialCamera: MapCameraRequest.fit(),
              allowPlaceSelection: false,
              startWithLiveLocation: true,
              canvasBuilder: canvasBuilder,
              locationService: locationService,
              onPlacesSelected: (_) {},
              onSaveCoordinate: (_) async => false,
              onShowList: () => Navigator.pop(context),
              fallbackActionLabel: 'Back to route',
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${routeDistance(road.distanceMeters)} · ${routeDuration(road.durationSeconds)} · ${stops.length} stops',
                        ),
                        const Text(
                          'Saved route overview · No turn-by-turn guidance',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
