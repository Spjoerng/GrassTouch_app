import 'package:flutter/material.dart';
import 'collection_dialog.dart';
import 'data/journal_store.dart';
import 'data/place_filter.dart';
import 'map/journal_location.dart';
import 'map/native_place_map.dart';
import 'place_browser.dart';
import 'ui/journal_motion.dart';

class CollectionsPage extends StatelessWidget {
  const CollectionsPage({
    super.key,
    required this.store,
    required this.collections,
    required this.onChanged,
    this.canvasBuilder,
    this.locationService,
  });
  final JournalStore store;
  final List<Map<String, Object?>> collections;
  final VoidCallback onChanged;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  Future<void> createSuggested(BuildContext context, String name) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CollectionDialog(store: store, suggestedName: name),
    );
    if (saved == true) onChanged();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          'Keep your favorite places close. Make a plan for the next ones.',
        ),
      ),
      if (collections.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
          child: Column(
            children: [
              const JournalEmptyIcon(Icons.folder_open_outlined),
              const SizedBox(height: 16),
              const Text(
                'Give your places a home',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Start with a collection of your own, or try one of these ideas.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children:
                    ['Weekend plans', 'Favorite restaurants', 'Study spots']
                        .map(
                          (name) => ActionChip(
                            label: Text(name),
                            onPressed: () => createSuggested(context, name),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
      ...collections.map(
        (collection) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CollectionDetails(
                    store: store,
                    collection: collection,
                    canvasBuilder: canvasBuilder,
                    locationService: locationService,
                  ),
                ),
              );
              onChanged();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: collection['cover_path'] == null
                          ? const ColoredBox(
                              color: Color(0xFFEAF0E5),
                              child: Icon(Icons.folder_outlined, size: 30),
                            )
                          : Image.file(
                              store.storage.resolve(
                                collection['cover_path'] as String,
                              ),
                              fit: BoxFit.cover,
                              cacheWidth: 228,
                              errorBuilder: (_, error, stack) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection['name'] as String,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ((collection['description'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              collection['description'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          '${collection['place_count']} places',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class CollectionDetails extends StatefulWidget {
  const CollectionDetails({
    super.key,
    required this.store,
    required this.collection,
    this.canvasBuilder,
    this.locationService,
  });
  final JournalStore store;
  final Map<String, Object?> collection;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  @override
  State<CollectionDetails> createState() => _CollectionDetailsState();
}

class _CollectionDetailsState extends State<CollectionDetails> {
  late Map<String, Object?> collection = widget.collection;
  int get id => collection['id'] as int;
  late Future<List<Map<String, Object?>>> places = widget.store
      .collectionPlaces(id);
  PlaceFilter filter = const PlaceFilter();
  bool showMap = false, busy = false;
  String? error;
  void refresh() {
    if (mounted) {
      setState(() {
        places = widget.store.collectionPlaces(id);
      });
    }
  }

  Future<void> edit() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CollectionDialog(store: widget.store, collection: collection),
    );
    if (saved == true) {
      try {
        final updated = await widget.store.collection(id);
        if (mounted) {
          setState(() {
            collection = updated;
            places = widget.store.collectionPlaces(id);
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => error =
                'Could not reload the collection. Go back and open it again.',
          );
        }
      }
    }
  }

  Future<void> manage() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CollectionMembershipDialog(store: widget.store, collectionId: id),
    );
    if (changed == true) refresh();
  }

  Future<void> remove(int placeId) async {
    try {
      await widget.store.removeFromCollection(id, placeId);
      refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not remove this place from the collection. Try again.',
        );
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete collection?'),
        content: const Text(
          'The collection and its cover image will be removed. Your saved places and their journal photos will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep collection'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete collection'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.deleteCollection(id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not delete this collection. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      resizeToAvoidBottomInset: !showMap,
      appBar: AppBar(
        title: Text(
          collection['name'] as String,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Manage places',
            onPressed: busy ? null : manage,
            icon: const Icon(Icons.playlist_add),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Collection options',
            onSelected: (v) => v == 'edit' ? edit() : delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit collection')),
              PopupMenuItem(value: 'delete', child: Text('Delete collection')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            MaterialBanner(
              content: Text(error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (!showMap &&
              (collection['cover_path'] != null ||
                  (collection['description'] as String).isNotEmpty))
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (collection['cover_path'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 96,
                              height: 96,
                              child: Image.file(
                                widget.store.storage.resolve(
                                  collection['cover_path'] as String,
                                ),
                                fit: BoxFit.cover,
                                cacheWidth: 288,
                                errorBuilder: (_, error, stack) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: SelectableText(
                          collection['description'] as String,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: places,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: refresh,
                      child: const Text(
                        'Could not load collection places. Retry',
                      ),
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
                  locationService: widget.locationService,
                  collectionId: id,
                  onRemovePlace: remove,
                  onAddPlaces: manage,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class CollectionMembershipDialog extends StatefulWidget {
  const CollectionMembershipDialog({
    super.key,
    required this.store,
    required this.collectionId,
  });
  final JournalStore store;
  final int collectionId;
  @override
  State<CollectionMembershipDialog> createState() =>
      _CollectionMembershipDialogState();
}

class _CollectionMembershipDialogState
    extends State<CollectionMembershipDialog> {
  List<Map<String, Object?>>? all;
  final selected = <int>{};
  String query = '';
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await Future.wait([
        widget.store.places(),
        widget.store.collectionPlaces(widget.collectionId),
      ]);
      if (mounted) {
        setState(() {
          all = rows[0];
          selected.clear();
          selected.addAll(rows[1].map((p) => p['id'] as int));
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load saved places. Please retry.');
      }
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.setCollectionPlaces(widget.collectionId, selected);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not update this collection. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches =
        all
            ?.where(
              (p) => '${p['name']} ${p['category']} ${p['notes']}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
            )
            .toList() ??
        [];
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Manage places'),
        content: SizedBox(
          width: 520,
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Column(
            children: [
              TextField(
                enabled: !busy,
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  labelText: 'Search saved places',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: all == null
                    ? Center(
                        child: error == null
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: load,
                                child: const Text('Retry'),
                              ),
                      )
                    : all!.isEmpty
                    ? const Center(
                        child: Text(
                          'Save a place in My Places or on the map first.',
                        ),
                      )
                    : matches.isEmpty
                    ? const Center(child: Text('No matching saved places'))
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final place = matches[i];
                          final id = place['id'] as int;
                          return CheckboxListTile(
                            value: selected.contains(id),
                            onChanged: busy
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      selected.add(id);
                                    } else {
                                      selected.remove(id);
                                    }
                                  }),
                            title: Text(place['name'] as String),
                            subtitle: Text(
                              '${place['category']} / ${place['visited'] == 1 ? 'Visited' : 'Want to visit'}',
                            ),
                            secondary: place['favorite'] == 1
                                ? const Icon(Icons.favorite)
                                : null,
                          );
                        },
                      ),
              ),
              Text('${selected.length} selected'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy || all == null ? null : save,
            child: Text(busy ? 'Saving...' : 'Save places'),
          ),
        ],
      ),
    );
  }
}
