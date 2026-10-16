import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show OfflineRegionDefinition;
import 'data/journal_store.dart';
import 'data/place_filter.dart';
import 'map/journal_location.dart';
import 'map/journal_map_view.dart';
import 'map/map_data.dart';
import 'map/native_place_map.dart';
import 'place_journal.dart';
import 'place_filter_sheet.dart';

class PlaceBrowser extends StatelessWidget {
  const PlaceBrowser({
    super.key,
    required this.store,
    required this.places,
    required this.filter,
    required this.onFilterChanged,
    required this.showMap,
    required this.onViewChanged,
    required this.onChanged,
    this.canvasBuilder,
    this.locationService,
    this.collectionId,
    this.onRemovePlace,
    this.onAddPlaces,
    this.onOpenBackup,
    this.onOpenOfflineMaps,
    this.offlineRegion,
  });
  final JournalStore store;
  final List<Map<String, Object?>> places;
  final PlaceFilter filter;
  final ValueChanged<PlaceFilter> onFilterChanged;
  final bool showMap;
  final ValueChanged<bool> onViewChanged;
  final VoidCallback onChanged;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  final int? collectionId;
  final ValueChanged<int>? onRemovePlace;
  final VoidCallback? onAddPlaces;
  final VoidCallback? onOpenBackup;
  final VoidCallback? onOpenOfflineMaps;
  final OfflineRegionDefinition? offlineRegion;
  List<Map<String, Object?>> get filtered =>
      places.where(filter.matches).toList();
  Future<void> openPlace(
    BuildContext context,
    Map<String, Object?> place,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlaceDetails(store: store, place: place),
    );
    onChanged();
  }

  Future<void> selectPlaces(BuildContext context, List<int> ids) async {
    final matches = filtered.where((p) => ids.contains(p['id'])).toList();
    if (matches.isEmpty) return;
    if (matches.length == 1) {
      await openPlace(context, matches.single);
      return;
    }
    final choice = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Places at this spot')),
            ...matches.map(
              (place) => ListTile(
                leading: Icon(
                  markerForCategory(place['category'] as String).icon,
                ),
                title: Text(place['name'] as String),
                subtitle: Text(place['category'] as String),
                onTap: () => Navigator.pop(context, place),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice != null && context.mounted) await openPlace(context, choice);
  }

  Future<bool> saveCoordinate(BuildContext context, MapCoordinate point) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlaceDialog(
        store: store,
        initialLatitude: point.latitude,
        initialLongitude: point.longitude,
        collectionId: collectionId,
      ),
    );
    if (saved == true) onChanged();
    return saved == true;
  }

  void update({
    String? query,
    String? category,
    bool clearCategory = false,
    bool? visited,
    bool clearStatus = false,
    bool? favorites,
  }) => onFilterChanged(
    PlaceFilter(
      query: query ?? filter.query,
      category: clearCategory ? null : category ?? filter.category,
      visited: clearStatus ? null : visited ?? filter.visited,
      favoritesOnly: favorites ?? filter.favoritesOnly,
    ),
  );
  int get activeFilters =>
      (filter.category == null ? 0 : 1) +
      (filter.visited == null ? 0 : 1) +
      (filter.favoritesOnly ? 1 : 0);
  Future<void> openFilters(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<PlaceFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => PlaceFilterSheet(
        initial: filter,
        categories: {
          ...placeCategories,
          ...places.map((p) => p['category'] as String),
        },
      ),
    );
    if (result != null && context.mounted) onFilterChanged(result);
  }

  Widget searchTools(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Material(
        color: Colors.white,
        elevation: showMap ? 4 : 1,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        child: TextFormField(
          key: const ValueKey('place-search'),
          initialValue: filter.query,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
          onChanged: (v) => update(query: v),
          decoration: InputDecoration(
            hintText: collectionId == null
                ? 'Search your places'
                : 'Search this collection',
            prefixIcon: showMap && onOpenBackup != null
                ? PopupMenuButton<String>(
                    tooltip: 'Journal menu',
                    icon: const Icon(Icons.menu),
                    onSelected: (value) => value == 'offline'
                        ? onOpenOfflineMaps?.call()
                        : onOpenBackup!(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'backup',
                        child: Text('Backup & export'),
                      ),
                      if (onOpenOfflineMaps != null)
                        const PopupMenuItem(
                          value: 'offline',
                          child: Text('Offline maps'),
                        ),
                    ],
                  )
                : const Icon(Icons.search),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: 'Filters',
                onPressed: () => openFilters(context),
                icon: Badge(
                  isLabelVisible: activeFilters > 0,
                  label: Text('$activeFilters'),
                  child: const Icon(Icons.tune),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Flexible(
            child: Material(
              color: showMap ? Colors.white : Colors.transparent,
              elevation: showMap ? 1 : 0,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${filtered.length} places${activeFilters == 0 ? '' : ' / $activeFilters filters'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            elevation: showMap ? 1 : 0,
            borderRadius: BorderRadius.circular(24),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => onViewChanged(!showMap),
              icon: Icon(showMap ? Icons.list : Icons.map_outlined, size: 18),
              label: Text(showMap ? 'List' : 'Map'),
            ),
          ),
        ],
      ),
    ],
  );
  Widget placeList(BuildContext context) {
    final visible = filtered;
    return visible.isEmpty
        ? Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place_outlined, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    places.isEmpty
                        ? (collectionId == null
                              ? 'Make room for a memory'
                              : 'No places in this collection')
                        : 'No places found',
                    style: const TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    places.isEmpty
                        ? (collectionId == null
                              ? 'Your visited places and future destinations will live here.'
                              : 'Add saved places to start organizing this collection.')
                        : 'Try another search or clear your filters.',
                    textAlign: TextAlign.center,
                  ),
                  if (places.isEmpty && onAddPlaces != null)
                    TextButton.icon(
                      onPressed: onAddPlaces,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Manage places'),
                    ),
                ],
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final place = visible[i];
              final marker = markerForCategory(place['category'] as String);
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: marker.color,
                    child: Icon(marker.icon, color: Colors.white),
                  ),
                  title: Text(
                    place['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${place['category']} - ${place['visited'] == 1 ? 'Visited' : 'Want to visit'}\n${place['latitude']}, ${place['longitude']}${place['rating'] == null ? '' : ' | ${place['rating']} / 5'}',
                  ),
                  isThreeLine: true,
                  trailing: onRemovePlace != null
                      ? IconButton(
                          tooltip: 'Remove from collection',
                          onPressed: () => onRemovePlace!(place['id'] as int),
                          icon: const Icon(Icons.remove_circle_outline),
                        )
                      : place['favorite'] == 1
                      ? const Icon(Icons.favorite)
                      : const Icon(Icons.chevron_right),
                  onTap: () => openPlace(context, place),
                ),
              );
            },
          );
  }

  @override
  Widget build(BuildContext context) {
    if (showMap) {
      return Stack(
        children: [
          Positioned.fill(
            child: JournalMapView(
              offlineRegion: offlineRegion,
              onOpenOfflineMaps: onOpenOfflineMaps,
              places: filtered,
              onPlacesSelected: (ids) => selectPlaces(context, ids),
              onSaveCoordinate: (point) => saveCoordinate(context, point),
              onShowList: () => onViewChanged(false),
              canvasBuilder: canvasBuilder,
              locationService: locationService,
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
                child: searchTools(context),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: searchTools(context),
        ),
        Expanded(child: placeList(context)),
      ],
    );
  }
}
