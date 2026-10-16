import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/journal_store.dart';
import '../map/journal_map_view.dart' show nativeMapsSupported;
import '../map/map_data.dart';
import '../map/native_place_map.dart';
import 'road_router.dart';
import 'route_draft.dart';
import 'route_models.dart';

class RoutesPage extends StatelessWidget {
  const RoutesPage({
    super.key,
    required this.store,
    required this.routes,
    required this.onChanged,
    this.canvasBuilder,
    this.router,
  });
  final JournalStore store;
  final List<Map<String, Object?>> routes;
  final VoidCallback onChanged;
  final MapCanvasBuilder? canvasBuilder;
  final RoadRouter? router;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    children: [
      if (routes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40, horizontal: 12),
          child: Column(
            children: [
              Icon(Icons.route_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Good trips begin with a plan',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Connect saved places, choose your stops, and keep a route for your next trip.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ...routes.map(
        (route) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const Icon(Icons.route, size: 32),
            title: Text(
              route['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${route['stop_count']} stops\n${route['distance_meters'] == null ? 'Plan saved / calculate roads when online' : '${routeDistance(route['distance_meters'] as num)} / ${routeDuration(route['duration_seconds'] as num)} driving'}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => RoutePlanner(
                    store: store,
                    routeId: route['id'] as int,
                    canvasBuilder: canvasBuilder,
                    router: router,
                  ),
                ),
              );
              onChanged();
            },
          ),
        ),
      ),
    ],
  );
}

class RoutePlanner extends StatefulWidget {
  const RoutePlanner({
    super.key,
    required this.store,
    this.routeId,
    this.canvasBuilder,
    this.router,
  });
  final JournalStore store;
  final int? routeId;
  final MapCanvasBuilder? canvasBuilder;
  final RoadRouter? router;
  @override
  State<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends State<RoutePlanner>
    with WidgetsBindingObserver {
  RouteDraft? draft;
  late final RoadRouter router = widget.router ?? OsrmRouter();
  String name = 'New route';
  bool nameDirty = false, saving = false, showMap = true, ready = false;
  String? loadError, actionError, mapError;
  MapCameraRequest? camera;
  int? placing;
  int mapGeneration = 0;
  Timer? mapTimeout;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      var stops = <RouteStop>[];
      RoadRoute? road;
      if (widget.routeId != null) {
        final row = await widget.store.route(widget.routeId!);
        name = row['name'] as String;
        stops = (await widget.store.routeStops(
          widget.routeId!,
        )).map(RouteStop.fromRow).toList();
        if (row['geometry_json'] != null) {
          road = RoadRoute(
            geometry:
                jsonDecode(row['geometry_json'] as String)
                    as Map<String, dynamic>,
            distanceMeters: (row['distance_meters'] as num).toDouble(),
            durationSeconds: (row['duration_seconds'] as num).toDouble(),
            stopsSignature: stopSignature(stops),
          );
        }
      }
      if (mounted) {
        setState(() {
          draft = RouteDraft(stops: stops, road: road)..addListener(changed);
          camera = stops.isEmpty ? null : MapCameraRequest.fit();
          loadError = null;
          startMapTimeout();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => loadError = 'Could not open this route. Try again.');
      }
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    mapTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    draft?.removeListener(changed);
    draft?.dispose();
    if (widget.router == null) (router as OsrmRouter).close();
    super.dispose();
  }

  void startMapTimeout() {
    mapTimeout?.cancel();
    if (!showMap || (widget.canvasBuilder == null && !nativeMapsSupported)) {
      return;
    }
    mapTimeout = Timer(const Duration(seconds: 25), () {
      if (mounted && !ready && showMap) {
        setState(
          () => mapError =
              'The basemap is unavailable or taking too long. Retry the map, or use Stops to edit and save your plan offline.',
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!ready && mapError == null) startMapTimeout();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      mapTimeout?.cancel();
    }
  }

  void retryMap() => setState(() {
    mapGeneration++;
    ready = false;
    mapError = null;
    startMapTimeout();
  });

  void openMap() {
    if (showMap) return;
    showMap = true;
    mapGeneration++;
    ready = false;
    mapError = null;
    startMapTimeout();
  }

  bool get dirty => nameDirty || (draft?.dirty ?? false);
  Future<void> leave() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard route changes?'),
        content: const Text('Your previously saved route will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> rename() async {
    final renamed = await showDialog<String>(
      context: context,
      builder: (_) => RouteNameDialog(initialName: name),
    );
    if (renamed != null && mounted && renamed != name) {
      setState(() {
        name = renamed;
        nameDirty = true;
      });
    }
  }

  Future<void> save() async {
    if (draft == null || draft!.stops.length < 2 || draft!.calculating) return;
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      await widget.store.savePlannedRoute(
        name,
        draft!.stops,
        id: widget.routeId,
        road: draft!.road,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          actionError = 'Could not save this route. Please try again.';
        });
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete route?'),
        content: const Text(
          'The route and its waypoints will be removed. Saved journal places will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep route'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete route'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.store.deleteRoute(widget.routeId!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          actionError = 'Could not delete this route. Try again.';
        });
      }
    }
  }

  void addStop(RouteStop stop) {
    try {
      draft!.add(stop);
      setState(() {
        placing = null;
        camera = MapCameraRequest.focus(stop.coordinate);
        actionError = null;
      });
    } on RoutingFailure catch (failure) {
      setState(() => actionError = failure.message);
    }
  }

  Future<void> add(String mode) async {
    if (mode == 'map') {
      setState(() {
        openMap();
        placing = -1;
      });
      return;
    }
    final stop = mode == 'saved'
        ? await showDialog<RouteStop>(
            context: context,
            builder: (_) => SavedStopPicker(store: widget.store),
          )
        : await showDialog<RouteStop>(
            context: context,
            builder: (_) => const RouteStopDialog(),
          );
    if (stop != null && mounted) addStop(stop);
  }

  Future<void> editStop(int index) async {
    final stop = await showDialog<RouteStop>(
      context: context,
      builder: (_) => RouteStopDialog(initial: draft!.stops[index]),
    );
    if (stop != null && mounted) draft!.replace(index, stop);
  }

  void chooseCoordinate(MapCoordinate point) {
    if (saving || draft == null) return;
    FocusScope.of(context).unfocus();
    if (placing != null && placing! >= 0 && placing! < draft!.stops.length) {
      final index = placing!;
      draft!.replace(
        index,
        RouteStop(
          name: draft!.stops[index].name,
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      );
      setState(() => placing = null);
    } else {
      addStop(
        RouteStop(
          name: 'Stop ${draft!.stops.length + 1}',
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      );
    }
  }

  Widget stopList() => draft!.stops.isEmpty
      ? const Center(child: Text('Add a starting point and destination.'))
      : ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.all(12),
          itemCount: draft!.stops.length,
          onReorderItem: (from, to) {
            if (!saving) draft!.move(from, to);
          },
          itemBuilder: (context, index) {
            final stop = draft!.stops[index];
            return Card(
              key: ObjectKey(stop),
              child: ListTile(
                leading: Tooltip(
                  message: 'Drag to reorder stop',
                  child: ReorderableDragStartListener(
                    index: index,
                    child: CircleAvatar(
                      child: Text(
                        index == 0
                            ? 'S'
                            : index == draft!.stops.length - 1
                            ? 'D'
                            : '$index',
                      ),
                    ),
                  ),
                ),
                title: Text(stop.name),
                subtitle: Text(
                  '${index == 0
                      ? 'Start'
                      : index == draft!.stops.length - 1
                      ? 'Destination'
                      : 'Intermediate stop'} / ${stop.placeId == null ? 'Positioned stop' : 'Saved place'}\n${stop.coordinate.label}',
                ),
                isThreeLine: true,
                onTap: saving ? null : () => editStop(index),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Stop ${index + 1} options',
                  enabled: !saving,
                  onSelected: (value) {
                    if (value == 'remove') draft!.remove(index);
                    if (value == 'up') draft!.move(index, index - 1);
                    if (value == 'down') draft!.move(index, index + 1);
                    if (value == 'position') {
                      setState(() {
                        placing = index;
                        openMap();
                        camera = MapCameraRequest.focus(stop.coordinate);
                      });
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'position',
                      child: Text('Position on map'),
                    ),
                    if (index > 0)
                      const PopupMenuItem(value: 'up', child: Text('Move up')),
                    if (index < draft!.stops.length - 1)
                      const PopupMenuItem(
                        value: 'down',
                        child: Text('Move down'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove stop'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  Widget map() {
    if (widget.canvasBuilder == null && !nativeMapsSupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Interactive route maps are available on Android and iOS. Use Stops to add coordinates and calculate or save a route on this device.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final currentGeneration = mapGeneration;
    final options = MapCanvasOptions(
      places: const [],
      routeGeometry: draft!.road?.geometry,
      routeStops: draft!.stops.map((s) => s.coordinate).toList(),
      selectedRouteStop: placing,
      camera: camera,
      onPlacesSelected: (_) {},
      onCoordinateSelected: chooseCoordinate,
      onRouteStopSelected: (index) {
        if (index >= 0 && index < draft!.stops.length && !saving) {
          setState(() => placing = index);
        }
      },
      onReady: () {
        if (mounted && currentGeneration == mapGeneration) {
          mapTimeout?.cancel();
          setState(() {
            ready = true;
            mapError = null;
          });
        }
      },
      onError: (message) {
        if (mounted && currentGeneration == mapGeneration) {
          mapTimeout?.cancel();
          setState(() => mapError = message);
        }
      },
    );
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(
            key: ValueKey(mapGeneration),
            child:
                widget.canvasBuilder?.call(context, options) ??
                NativePlaceMap(options: options),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 72,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                !ready
                    ? 'Loading map. You can still edit coordinates in Stops.'
                    : placing != null && placing! >= 0
                    ? 'Tap the map to move ${draft!.stops[placing!].name}. This will clear the old road route.'
                    : 'Tap the map to add a stop. Tap a waypoint to move it.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                IconButton(
                  tooltip: 'Fit route',
                  onPressed: ready && draft!.stops.isNotEmpty
                      ? () => setState(() => camera = MapCameraRequest.fit())
                      : null,
                  icon: const Icon(Icons.fit_screen),
                ),
                IconButton(
                  tooltip: 'Reload route map',
                  onPressed: retryMap,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
        if (mapError != null)
          Positioned(
            left: 12,
            right: 72,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mapError!),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: retryMap,
                          child: const Text('Retry map'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            showMap = false;
                            placing = null;
                            mapTimeout?.cancel();
                          }),
                          child: const Text('Use offline stops'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving && !dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !saving) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed:
                saving ||
                    draft == null ||
                    draft!.calculating ||
                    draft!.stops.length < 2
                ? null
                : save,
            child: Text(saving ? 'Saving...' : 'Save route'),
          ),
          PopupMenuButton<String>(
            enabled: !saving,
            tooltip: 'Route options',
            onSelected: (value) => value == 'rename' ? rename() : delete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename route')),
              if (widget.routeId != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete route'),
                ),
            ],
          ),
        ],
      ),
      body: draft == null
          ? Center(
              child: loadError == null
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: load, child: Text(loadError!)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          showMap = !showMap;
                          mapGeneration++;
                          placing = null;
                          if (showMap) {
                            ready = false;
                            mapError = null;
                            startMapTimeout();
                          } else {
                            mapTimeout?.cancel();
                          }
                        }),
                        icon: Icon(showMap ? Icons.list : Icons.map_outlined),
                        label: Text(
                          showMap ? 'Stops (${draft!.stops.length})' : 'Map',
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        enabled: !saving && draft!.stops.length < 25,
                        tooltip: 'Add stop',
                        onSelected: add,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'saved',
                            child: Text('Saved place'),
                          ),
                          PopupMenuItem(
                            value: 'manual',
                            child: Text('Enter coordinates'),
                          ),
                          PopupMenuItem(
                            value: 'map',
                            child: Text('Pick on map'),
                          ),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.add),
                              SizedBox(width: 6),
                              Text('Add stop'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: showMap ? map() : stopList()),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (draft!.error != null || actionError != null)
                          Text(
                            actionError ?? draft!.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (draft!.road != null)
                          Text(
                            '${routeDistance(draft!.road!.distanceMeters)} / ${routeDuration(draft!.road!.durationSeconds)} driving',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          const Text(
                            'No road route calculated. You can save the stop plan offline.',
                          ),
                        const SizedBox(height: 6),
                        FilledButton.icon(
                          onPressed:
                              saving ||
                                  draft!.calculating ||
                                  draft!.stops.length < 2
                              ? null
                              : () => draft!.calculate(router),
                          icon: const Icon(Icons.route),
                          label: Text(
                            draft!.calculating
                                ? 'Calculating...'
                                : 'Calculate road route',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Calculate sends stop coordinates to OSRM. Driving estimates exclude live traffic. Routing data: OpenStreetMap contributors.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class RouteStopDialog extends StatefulWidget {
  const RouteStopDialog({super.key, this.initial});
  final RouteStop? initial;
  @override
  State<RouteStopDialog> createState() => _RouteStopDialogState();
}

class _RouteStopDialogState extends State<RouteStopDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial?.name);
  late final latitude = TextEditingController(
    text: widget.initial?.latitude.toString(),
  );
  late final longitude = TextEditingController(
    text: widget.initial?.longitude.toString(),
  );
  @override
  void dispose() {
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    super.dispose();
  }

  String? coordinate(String? input, int limit) {
    final value = double.tryParse(input ?? '');
    return value == null || !value.isFinite || value.abs() > limit
        ? 'Enter a valid coordinate between -$limit and $limit'
        : null;
  }

  void save() {
    if (!form.currentState!.validate()) return;
    final lat = double.parse(latitude.text.trim()),
        lon = double.parse(longitude.text.trim());
    Navigator.pop(
      context,
      RouteStop(
        name: name.text.trim(),
        latitude: lat,
        longitude: lon,
        placeId:
            lat == widget.initial?.latitude && lon == widget.initial?.longitude
            ? widget.initial?.placeId
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Add route stop' : 'Edit route stop'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Stop name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a stop name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: latitude,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (v) => coordinate(v, 90),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: longitude,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (v) => coordinate(v, 180),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Use stop')),
    ],
  );
}

class SavedStopPicker extends StatefulWidget {
  const SavedStopPicker({super.key, required this.store});
  final JournalStore store;
  @override
  State<SavedStopPicker> createState() => _SavedStopPickerState();
}

class _SavedStopPickerState extends State<SavedStopPicker> {
  late Future<List<Map<String, Object?>>> places = widget.store.places();
  String query = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a saved place'),
    content: SizedBox(
      width: 480,
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              labelText: 'Search places',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: places,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () => setState(() {
                      places = widget.store.places();
                    }),
                    child: const Text('Could not load places. Retry'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final matches = snapshot.data!
                    .where(
                      (p) => '${p['name']} ${p['category']}'
                          .toLowerCase()
                          .contains(query.toLowerCase()),
                    )
                    .toList();
                if (matches.isEmpty) {
                  return const Center(
                    child: Text(
                      'No saved places found. You can enter coordinates instead.',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(matches[i]['name'] as String),
                    subtitle: Text(matches[i]['category'] as String),
                    onTap: () =>
                        Navigator.pop(context, RouteStop.fromPlace(matches[i])),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class RouteNameDialog extends StatefulWidget {
  const RouteNameDialog({super.key, required this.initialName});
  final String initialName;
  @override
  State<RouteNameDialog> createState() => _RouteNameDialogState();
}

class _RouteNameDialogState extends State<RouteNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Route name'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Route name'),
        validator: (v) =>
            v == null || v.trim().isEmpty ? 'Enter a route name' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Use name'),
      ),
    ],
  );
}
