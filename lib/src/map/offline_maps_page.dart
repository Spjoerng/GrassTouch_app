import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/journal_store.dart';
import '../data/place_filter.dart';
import '../place_browser.dart';
import 'native_place_map.dart';
import 'map_data.dart';
import 'offline_maps.dart';

class OfflineMapFiles {
  Future<File?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'MapLibre offline database',
          extensions: ['db', 'sqlite'],
          mimeTypes: [
            'application/vnd.sqlite3',
            'application/x-sqlite3',
            'application/octet-stream',
          ],
          uniformTypeIdentifiers: ['public.database', 'public.data'],
        ),
      ],
    );
    return file == null ? null : File(file.path);
  }
}

class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({
    super.key,
    required this.store,
    this.maps,
    this.files,
    this.canvasBuilder,
  });
  final JournalStore store;
  final OfflineMaps? maps;
  final OfflineMapFiles? files;
  final MapCanvasBuilder? canvasBuilder;
  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage>
    with WidgetsBindingObserver {
  late final maps = widget.maps ?? OfflineMaps();
  late Future<List<OfflineArea>> areas;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    areas = maps.list();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) refresh();
  }

  void refresh() {
    if (mounted) {
      setState(() {
        areas = maps.list();
      });
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await operation();
    } on OfflineMapFailure catch (failure) {
      if (mounted) setState(() => message = failure.message);
    } on FileSystemException catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not access the map file. Check file access and available device storage, then retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Map data could not be updated. Use a complete MapLibre offline database and retry. Your journal is unchanged.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        refresh();
      }
    }
  }

  Future<void> importDatabase() => run(() async {
    final file = await (widget.files ?? OfflineMapFiles()).pick();
    if (file == null) return;
    await maps.importDatabase(file);
    if (mounted) {
      setState(
        () => message =
            'Map database imported. Check each area’s status and test it in airplane mode before your trip.',
      );
    }
  });

  Future<void> delete(OfflineArea area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove offline area?'),
        content: Text(
          'Remove ${area.name} from the map store? Places, photos, collections, and routes will be kept. Shared cached tiles may remain in use by other areas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove area'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await run(() => maps.delete(area));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Offline maps'),
        automaticallyImplyLeading: !busy,
        actions: [
          IconButton(
            tooltip: 'Refresh offline areas',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Prepare your map before a trip',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your journal, photos, and saved route geometry work offline. Basemap coverage is separate: browsing a map does not guarantee it will be available later. Calculating new road routes still needs a routing service.',
              ),
              const SizedBox(height: 20),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supported local map workflow',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '1. Prepare a completed MapLibre Native offline database containing your area, zoom levels, style, tiles, fonts, and sprites. Use the same Bright style as Explore to share its cached coverage.',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '2. Transfer the checkpointed, single .db file to this device and import it below. Standard MBTiles, PMTiles, journal ZIP backups, and raw map images are different formats.',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '3. Check that the area is complete. Open it and test in airplane mode at the zoom levels you need. iOS may evict cached resources when storage is low.',
                      ),
                      SizedBox(height: 8),
                      SelectableText('Explore style: $mapStyleUrl'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (maps.supported)
                FilledButton.icon(
                  onPressed: busy ? null : importDatabase,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Import map database'),
                )
              else
                const Text(
                  'Native offline maps are available on Android and iOS. On this device, use the journal list, photos, and saved route plans offline.',
                ),
              if (busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Updating map data…'),
              ],
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(message!),
                ),
              const SizedBox(height: 24),
              const Text(
                'Local map areas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              FutureBuilder<List<OfflineArea>>(
                future: areas,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          const Text(
                            'Offline map status is unavailable. Your journal still works.',
                          ),
                          TextButton(
                            onPressed: busy ? null : refresh,
                            child: const Text('Retry status'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No offline areas imported. Import a completed MapLibre database to prepare local map coverage.',
                      ),
                    );
                  }
                  return Column(
                    children: snapshot.data!
                        .map(
                          (area) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    area.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    area.statusError ??
                                        (area.complete
                                            ? 'Complete · ${(area.status!.completedResourceSize / 1048576).toStringAsFixed(1)} MB'
                                            : 'Incomplete · ${area.status!.completedResourceCount} / ${area.status!.requiredResourceCount} resources. Import a completed database before relying on this area.'),
                                  ),
                                  Text(
                                    'Zoom ${area.region.definition.minZoom.toStringAsFixed(0)}–${area.region.definition.maxZoom.toStringAsFixed(0)} · ${area.usesCurrentStyle ? 'Bright / Explore coverage' : 'Different style / available in area view'}',
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      OutlinedButton(
                                        onPressed: busy || !area.complete
                                            ? null
                                            : () => Navigator.push<void>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      OfflineAreaPage(
                                                        store: widget.store,
                                                        area: area,
                                                        canvasBuilder: widget
                                                            .canvasBuilder,
                                                      ),
                                                ),
                                              ),
                                        child: const Text('Open area'),
                                      ),
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => delete(area),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Offline maps use a separate tile store and are not included in journal ZIP backups. This build imports prepared map data; it does not download regions or provide offline road routing.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OfflineAreaPage extends StatefulWidget {
  const OfflineAreaPage({
    super.key,
    required this.store,
    required this.area,
    this.canvasBuilder,
  });
  final JournalStore store;
  final OfflineArea area;
  final MapCanvasBuilder? canvasBuilder;
  @override
  State<OfflineAreaPage> createState() => _OfflineAreaPageState();
}

class _OfflineAreaPageState extends State<OfflineAreaPage> {
  late Future<List<Map<String, Object?>>> places = widget.store.places();
  PlaceFilter filter = const PlaceFilter();
  bool showMap = true;
  void refresh() => setState(() {
    places = widget.store.places();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.area.name)),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: places,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Could not load places. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return PlaceBrowser(
          store: widget.store,
          places: snapshot.data!,
          filter: filter,
          onFilterChanged: (value) => setState(() => filter = value),
          showMap: showMap,
          onViewChanged: (value) => setState(() => showMap = value),
          onChanged: refresh,
          canvasBuilder: widget.canvasBuilder,
          offlineRegion: widget.area.region.definition,
        );
      },
    ),
  );
}
