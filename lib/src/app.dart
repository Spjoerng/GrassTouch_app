import 'package:flutter/material.dart';
import 'data/journal_store.dart';
import 'data/place_filter.dart';
import 'map/journal_location.dart';
import 'map/native_place_map.dart';
import 'place_browser.dart';
import 'place_journal.dart';
import 'collection_dialog.dart';
import 'collections.dart';
import 'routes/route_planner.dart';
import 'routes/road_router.dart';
import 'backup/backup_page.dart';
import 'map/offline_maps_page.dart';
import 'ui/journal_motion.dart';

const forest = Color(0xFF254F40);
const cream = Color(0xFFF6F5EF);
const destinations = ['Explore', 'My Places', 'Collections', 'Routes'];
const destinationIcons = [
  Icons.explore_outlined,
  Icons.place_outlined,
  Icons.folder_outlined,
  Icons.route_outlined,
];
const selectedDestinationIcons = [
  Icons.explore,
  Icons.place,
  Icons.folder,
  Icons.route,
];

class JournalApp extends StatelessWidget {
  const JournalApp({
    super.key,
    required this.store,
    this.mapCanvasBuilder,
    this.locationService,
    this.roadRouter,
  });
  final JournalStore store;
  final MapCanvasBuilder? mapCanvasBuilder;
  final JournalLocation? locationService;
  final RoadRouter? roadRouter;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TouchGrass',
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCAD4CD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: forest, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFD5E8DD),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: forest,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: forest,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5EAE4)),
        ),
      ),
    ),
    home: JournalShell(
      store: store,
      mapCanvasBuilder: mapCanvasBuilder,
      locationService: locationService,
      roadRouter: roadRouter,
    ),
  );
}

class JournalShell extends StatefulWidget {
  const JournalShell({
    super.key,
    required this.store,
    this.mapCanvasBuilder,
    this.locationService,
    this.roadRouter,
  });
  final JournalStore store;
  final MapCanvasBuilder? mapCanvasBuilder;
  final JournalLocation? locationService;
  final RoadRouter? roadRouter;
  @override
  State<JournalShell> createState() => _JournalShellState();
}

class _JournalShellState extends State<JournalShell>
    with WidgetsBindingObserver {
  int selected = 0;
  PlaceFilter filter = const PlaceFilter();
  late Future<List<List<Map<String, Object?>>>> data;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(refresh);
  }

  void refresh() {
    data = Future.wait([
      widget.store.places(),
      widget.store.collections(),
      widget.store.routes(),
    ]);
  }

  Future<void> add() async {
    if (selected == 3) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RoutePlanner(
            store: widget.store,
            canvasBuilder: widget.mapCanvasBuilder,
            router: widget.roadRouter,
            locationService: widget.locationService,
          ),
        ),
      );
      if (mounted) setState(refresh);
      return;
    }
    final saved = selected == 2
        ? await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => CollectionDialog(store: widget.store),
          )
        : await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => PlaceDialog(
              store: widget.store,
              canvasBuilder: widget.mapCanvasBuilder,
              locationService: widget.locationService,
            ),
          );
    if (saved == true && mounted) setState(refresh);
  }

  Future<void> openBackup() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BackupPage(
          store: widget.store,
          onRestored: () {
            if (mounted) setState(refresh);
          },
        ),
      ),
    );
  }

  Future<void> openOfflineMaps() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => OfflineMapsPage(store: widget.store)),
    );
    if (mounted) setState(refresh);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      // The keyboard overlays Explore instead of resizing the native viewport.
      // Lists still resize so search results remain reachable above the IME.
      resizeToAvoidBottomInset: selected != 0,
      body: SafeArea(
        maintainBottomViewPadding: wide && selected == 0,
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
                                'TouchGrass',
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
                            selectedIcon: Icon(selectedDestinationIcons[i]),
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
                          IconButton(
                            tooltip: 'Backup & export',
                            onPressed: openBackup,
                            icon: const Icon(
                              Icons.backup_outlined,
                              color: forest,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Offline maps',
                            onPressed: openOfflineMaps,
                            icon: const Icon(
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
                            onOpenBackup: openBackup,
                            onOpenOfflineMaps: openOfflineMaps,
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
                          return JournalReveal(
                            key: const ValueKey('collections-entry'),
                            child: CollectionsPage(
                              store: widget.store,
                              collections: collections,
                              onChanged: () {
                                if (mounted) setState(refresh);
                              },
                              canvasBuilder: widget.mapCanvasBuilder,
                              locationService: widget.locationService,
                            ),
                          );
                        }
                        if (selected == 3) {
                          return JournalReveal(
                            key: const ValueKey('routes-entry'),
                            child: RoutesPage(
                              store: widget.store,
                              routes: routes,
                              onChanged: () {
                                if (mounted) setState(refresh);
                              },
                              canvasBuilder: widget.mapCanvasBuilder,
                              router: widget.roadRouter,
                              locationService: widget.locationService,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: selected == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: add,
              backgroundColor: forest,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(
                selected == 2
                    ? 'New collection'
                    : selected == 3
                    ? 'New route'
                    : 'Add place',
              ),
            ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 68,
              animationDuration: journalMotionDuration(context),
              maintainBottomViewPadding: selected == 0,
              selectedIndex: selected,
              onDestinationSelected: (value) =>
                  setState(() => selected = value),
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(destinationIcons[i]),
                  selectedIcon: Icon(selectedDestinationIcons[i]),
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
        JournalEmptyIcon(icon),
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
