import 'package:flutter/material.dart';
import 'data/journal_store.dart';
import 'data/place_filter.dart';
import 'map/journal_location.dart';
import 'map/native_place_map.dart';
import 'place_browser.dart';
import 'place_journal.dart';
import 'collection_dialog.dart';
import 'collections.dart';

const forest = Color(0xFF254F40);
const cream = Color(0xFFF6F5EF);
const destinations = ['Explore', 'My Places', 'Collections', 'Routes'];
const destinationIcons = [
  Icons.explore_outlined,
  Icons.place_outlined,
  Icons.folder_outlined,
  Icons.route_outlined,
];

class JournalApp extends StatelessWidget {
  const JournalApp({
    super.key,
    required this.store,
    this.mapCanvasBuilder,
    this.locationService,
  });
  final JournalStore store;
  final MapCanvasBuilder? mapCanvasBuilder;
  final JournalLocation? locationService;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fieldnotes - Place journal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        surface: cream,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: JournalShell(
      store: store,
      mapCanvasBuilder: mapCanvasBuilder,
      locationService: locationService,
    ),
  );
}

class JournalShell extends StatefulWidget {
  const JournalShell({
    super.key,
    required this.store,
    this.mapCanvasBuilder,
    this.locationService,
  });
  final JournalStore store;
  final MapCanvasBuilder? mapCanvasBuilder;
  final JournalLocation? locationService;
  @override
  State<JournalShell> createState() => _JournalShellState();
}

class _JournalShellState extends State<JournalShell> {
  int selected = 0;
  PlaceFilter filter = const PlaceFilter();
  late Future<List<List<Map<String, Object?>>>> data;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    data = Future.wait([
      widget.store.places(),
      widget.store.collections(),
      widget.store.routes(),
    ]);
  }

  Future<void> add() async {
    final saved = selected == 2
        ? await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => CollectionDialog(store: widget.store),
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => PlaceDialog(store: widget.store),
          );
    if (saved == true && mounted) setState(refresh);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 220,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFE2E5DB))),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 32, 24, 32),
                      child: Row(
                        children: [
                          Icon(Icons.terrain, color: forest),
                          SizedBox(width: 10),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'fieldnotes',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: forest,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: NavigationRail(
                        minExtendedWidth: 220,
                        extended: true,
                        backgroundColor: cream,
                        selectedIndex: selected,
                        onDestinationSelected: (value) =>
                            setState(() => selected = value),
                        destinations: List.generate(
                          4,
                          (i) => NavigationRailDestination(
                            icon: Icon(destinationIcons[i]),
                            label: Text(destinations[i]),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'A little closer to the places\nthat matter.',
                        style: TextStyle(color: forest, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (selected != 0)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 28 : 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  destinations[selected],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Tooltip(
                            message:
                                'Journal records are saved on this device. Basemap tiles may require internet.',
                            child: Icon(
                              Icons.offline_pin_outlined,
                              color: forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: FutureBuilder<List<List<Map<String, Object?>>>>(
                      future: data,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return EmptyPanel(
                            icon: Icons.error_outline,
                            title: 'Could not load your journal',
                            message: 'Try loading your saved records again.',
                            action: TextButton(
                              onPressed: () => setState(refresh),
                              child: const Text('Retry'),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final places = snapshot.data![0],
                            collections = snapshot.data![1],
                            routes = snapshot.data![2];
                        if (selected <= 1) {
                          return PlaceBrowser(
                            store: widget.store,
                            places: places,
                            filter: filter,
                            onFilterChanged: (value) =>
                                setState(() => filter = value),
                            showMap: selected == 0,
                            onViewChanged: (map) =>
                                setState(() => selected = map ? 0 : 1),
                            onChanged: () {
                              if (mounted) setState(refresh);
                            },
                            canvasBuilder: widget.mapCanvasBuilder,
                            locationService: widget.locationService,
                          );
                        }
                        if (selected == 2) {
                          return CollectionsPage(
                            store: widget.store,
                            collections: collections,
                            onChanged: () {
                              if (mounted) setState(refresh);
                            },
                            canvasBuilder: widget.mapCanvasBuilder,
                            locationService: widget.locationService,
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          children: [
                            if (selected == 3) ...[
                              const EmptyPanel(
                                icon: Icons.route_outlined,
                                title: 'Good trips begin with a plan',
                                message:
                                    'Your saved routes will live here. Multi-stop planning, distances, and travel times are planned for a later build.',
                              ),
                              ...routes.map(
                                (r) => Card(
                                  child: ListTile(
                                    title: Text(r['name'] as String),
                                    leading: const Icon(Icons.route),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: selected == 0 || selected == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: add,
              backgroundColor: forest,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(selected == 2 ? 'New collection' : 'Add place'),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 68,
              selectedIndex: selected,
              onDestinationSelected: (value) =>
                  setState(() => selected = value),
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(destinationIcons[i]),
                  label: destinations[i],
                ),
              ),
            ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: forest),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.6, color: Colors.black54),
          ),
        ),
        ?action,
      ],
    ),
  );
}
