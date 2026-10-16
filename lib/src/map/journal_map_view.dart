import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'journal_location.dart';
import 'map_data.dart';
import 'native_place_map.dart';

bool get nativeMapsSupported => Platform.isAndroid || Platform.isIOS;

class JournalMapView extends StatefulWidget {
  const JournalMapView({
    super.key,
    required this.places,
    required this.onPlacesSelected,
    required this.onSaveCoordinate,
    required this.onShowList,
    this.canvasBuilder,
    this.locationService,
  });
  final List<Map<String, Object?>> places;
  final ValueChanged<List<int>> onPlacesSelected;
  final Future<bool> Function(MapCoordinate) onSaveCoordinate;
  final VoidCallback onShowList;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  @override
  State<JournalMapView> createState() => _JournalMapViewState();
}

class _JournalMapViewState extends State<JournalMapView> {
  late final locationService = widget.locationService ?? JournalLocation();
  MapCoordinate? selected, location;
  MapCameraRequest? camera;
  bool locating = false, ready = false, saving = false;
  String? mapError, settingsError;
  LocationFailure? locationFailure;
  int generation = 0;
  Timer? timeout;
  bool get supported => widget.canvasBuilder != null || nativeMapsSupported;
  @override
  void initState() {
    super.initState();
    startTimeout();
  }

  void startTimeout() {
    timeout?.cancel();
    if (!supported) return;
    timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && !ready) {
        setState(
          () => mapError =
              'The basemap is taking too long to load. Check your connection, retry, or use the offline list.',
        );
      }
    });
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  void retry() => setState(() {
    generation++;
    ready = false;
    mapError = null;
    startTimeout();
  });
  Future<void> locate() async {
    setState(() {
      locating = true;
      locationFailure = null;
      settingsError = null;
    });
    try {
      final point = await locationService.locate();
      if (mounted) {
        setState(() {
          location = point;
          selected = point;
          camera = MapCameraRequest.focus(point);
        });
      }
    } on LocationFailure catch (failure) {
      if (mounted) setState(() => locationFailure = failure);
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> settings() async {
    try {
      final opened = await locationService.settings(locationFailure!.issue);
      if (mounted && !opened) {
        setState(
          () => settingsError =
              'Open location permissions in your device settings, then try My location again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => settingsError =
              'Settings could not be opened. Use your device settings.',
        );
      }
    }
  }

  Future<void> saveSelection() async {
    final point = selected!;
    setState(() => saving = true);
    try {
      final saved = await widget.onSaveCoordinate(point);
      if (saved && mounted) setState(() => selected = null);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void legend() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your map'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...categoryMarkers.entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.value.icon, color: entry.value.color),
                title: Text(entry.key),
              ),
            ),
            const Text(
              'Numbered bubbles group nearby places. Tap a bubble to zoom in. At overlapping pins, choose a place from the selection panel.',
            ),
            const SizedBox(height: 16),
            const Text(
              'The blue dot is your last requested location fix. It may be approximate. Confirm the selected coordinates before saving.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Map tiles: OpenFreeMap / OpenMapTiles / OpenStreetMap contributors. Open the attribution control on the map for source links. Basemap display requires internet or locally available map data. This build does not download offline regions. Your place journal remains available offline.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Widget mapControls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'My location',
          onPressed: locating ? null : locate,
          icon: locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
        ),
      ),
      const SizedBox(height: 10),
      Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Fit places',
              onPressed: widget.places.isEmpty || !ready
                  ? null
                  : () => setState(() => camera = MapCameraRequest.fit()),
              icon: const Icon(Icons.fit_screen),
            ),
            const SizedBox(width: 28, child: Divider(height: 1)),
            PopupMenuButton<String>(
              tooltip: 'Map options',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) => value == 'info' ? legend() : retry(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'info', child: Text('Map info')),
                PopupMenuItem(value: 'reload', child: Text('Reload basemap')),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  Widget statusCard() => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mapError ?? locationFailure!.message,
            style: const TextStyle(fontSize: 13),
          ),
          if (mapError != null)
            Wrap(
              spacing: 8,
              children: [
                TextButton(onPressed: retry, child: const Text('Retry map')),
                TextButton(
                  onPressed: widget.onShowList,
                  child: const Text('Use offline list'),
                ),
              ],
            )
          else ...[
            if (locationFailure!.issue == LocationIssue.deniedForever ||
                locationFailure!.issue == LocationIssue.servicesDisabled)
              TextButton(
                onPressed: settings,
                child: const Text('Open settings'),
              ),
            if (settingsError != null) Text(settingsError!),
            TextButton(
              onPressed: () => setState(() => locationFailure = null),
              child: const Text('Dismiss'),
            ),
          ],
        ],
      ),
    ),
  );
  Widget selectionCard() => Material(
    color: Colors.white,
    elevation: 5,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.add_location_alt_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Selected location',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: saving
                    ? null
                    : () => setState(() => selected = null),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Selected: ${selected!.label}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: saving ? null : saveSelection,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Save this place'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!supported) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 136, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Interactive maps on Android and iOS',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your saved places, photos, and journal are available in the list on this device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.onShowList,
                icon: const Icon(Icons.list),
                label: const Text('View saved places'),
              ),
            ],
          ),
        ),
      );
    }
    final options = MapCanvasOptions(
      places: widget.places,
      selected: selected,
      location: location,
      camera: camera,
      onPlacesSelected: widget.onPlacesSelected,
      onCoordinateSelected: (point) {
        FocusScope.of(context).unfocus();
        setState(() => selected = point);
      },
      onReady: () {
        if (!mounted) return;
        timeout?.cancel();
        setState(() {
          ready = true;
          mapError = null;
        });
      },
      onError: (message) {
        if (!mounted) return;
        timeout?.cancel();
        setState(() => mapError = message);
      },
    );
    return LayoutBuilder(
      builder: (context, bounds) => Stack(
        children: [
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey(generation),
              child:
                  widget.canvasBuilder?.call(context, options) ??
                  NativePlaceMap(options: options),
            ),
          ),
          Positioned(
            right: 16,
            top: selected != null && bounds.maxWidth < 600 ? 132 : null,
            bottom: selected != null && bounds.maxWidth < 600 ? null : 16,
            child: mapControls(),
          ),
          if (!ready && mapError == null)
            const Positioned(
              top: 132,
              left: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Loading map...'),
                ),
              ),
            ),
          if (mapError != null || locationFailure != null)
            Positioned(
              top: 132,
              left: 16,
              right: 80,
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: bounds.maxHeight * 0.38,
                  ),
                  child: SingleChildScrollView(child: statusCard()),
                ),
              ),
            ),
          if (selected != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: bounds.maxWidth >= 600 ? 88 : 16,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: bounds.maxHeight * 0.4,
                  ),
                  child: SingleChildScrollView(child: selectionCard()),
                ),
              ),
            ),
          if (ready &&
              widget.places.isEmpty &&
              selected == null &&
              mapError == null &&
              locationFailure == null)
            const Positioned(
              bottom: 24,
              left: 56,
              right: 84,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Tap the map to save a place',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
