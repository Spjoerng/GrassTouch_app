import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show OfflineRegionDefinition;
import 'data/journal_store.dart';
import 'data/place_filter.dart';
import 'map/journal_location.dart';
import 'map/journal_map_view.dart' show nativeMapsSupported;
import 'map/map_data.dart';
import 'map/native_place_map.dart';
import 'map/place_location_picker.dart';
import 'ui/journal_motion.dart';

typedef PhotoPicker = Future<List<File>> Function();
Future<List<File>> pickJournalPhotos() async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Photos',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
        ],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      ),
    ],
  );
  return files.map((file) => File(file.path)).toList();
}

String journalDate(String? value) =>
    value == null ? 'Not set' : value.split('T').first;

class PlaceDialog extends StatefulWidget {
  const PlaceDialog({
    super.key,
    required this.store,
    this.place,
    this.initialLatitude,
    this.initialLongitude,
    this.collectionId,
    this.pickPhotos = pickJournalPhotos,
    this.canvasBuilder,
    this.locationService,
    this.offlineRegion,
  });
  final JournalStore store;
  final Map<String, Object?>? place;
  final double? initialLatitude, initialLongitude;
  final int? collectionId;
  final PhotoPicker pickPhotos;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  final OfflineRegionDefinition? offlineRegion;
  @override
  State<PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<PlaceDialog> {
  final form = GlobalKey<FormState>();
  final locationKey = GlobalKey();
  bool locationRequired = false;
  late final name = TextEditingController(
    text: widget.place?['name'] as String?,
  );
  late final latitude = TextEditingController(
    text: (widget.place?['latitude'] ?? widget.initialLatitude)?.toString(),
  );
  late final longitude = TextEditingController(
    text: (widget.place?['longitude'] ?? widget.initialLongitude)?.toString(),
  );
  late final notes = TextEditingController(
    text: widget.place?['notes'] as String?,
  );
  late String category = widget.place?['category'] as String? ?? 'Other';
  late bool visited = widget.place?['visited'] == 1;
  late bool favorite = widget.place?['favorite'] == 1;
  late int? rating = widget.place?['rating'] as int?;
  late DateTime? visitDate = DateTime.tryParse(
    widget.place?['visit_date'] as String? ?? '',
  );
  final retained = <String>[];
  final added = <File>[];
  bool loading = true, busy = false;
  String? error;
  String? locationError;
  bool get canPickMap => nativeMapsSupported || widget.canvasBuilder != null;
  MapCoordinate? get selectedLocation {
    final lat = double.tryParse(latitude.text.trim());
    final lng = double.tryParse(longitude.text.trim());
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return MapCoordinate(lat, lng);
  }

  void setLocation(MapCoordinate point) => setState(() {
    latitude.text = point.latitude.toString();
    longitude.text = point.longitude.toString();
    error = null;
    locationRequired = false;
    locationError = null;
  });

  Future<void> chooseLocation() async {
    FocusScope.of(context).unfocus();
    final point = await Navigator.push<MapCoordinate>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceLocationPicker(
          initialLocation: selectedLocation,
          canvasBuilder: widget.canvasBuilder,
          locationService: widget.locationService,
          offlineRegion: widget.offlineRegion,
        ),
      ),
    );
    if (point != null && mounted) setLocation(point);
  }

  Future<void> useCurrentLocation() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      locationError = null;
    });
    try {
      final point = await (widget.locationService ?? JournalLocation())
          .locate();
      if (mounted) setLocation(point);
    } on LocationFailure catch (failure) {
      if (mounted) setState(() => locationError = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    loadPhotos();
  }

  Future<void> loadPhotos() async {
    try {
      final photos = widget.place == null
          ? <Map<String, Object?>>[]
          : await widget.store.attachments(widget.place!['id'] as int);
      if (mounted) {
        setState(() {
          retained.addAll(photos.map((p) => p['relative_path'] as String));
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not load photos. Retry before editing.';
        });
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    latitude.dispose();
    longitude.dispose();
    notes.dispose();
    super.dispose();
  }

  String? coordinate(String? input, double limit) {
    final value = double.tryParse(input ?? '');
    return value == null || !value.isFinite || value.abs() > limit
        ? 'Enter a number from -$limit to $limit'
        : null;
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final files = await widget.pickPhotos();
      if (mounted) {
        setState(() {
          added.addAll(files);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Could not open photos. Try choosing a local JPEG, PNG, or WebP file again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    if (!form.currentState!.validate()) return;
    final point = selectedLocation;
    if (point == null) {
      setState(() => locationRequired = true);
      final target = locationKey.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 200),
          alignment: 0.2,
        );
      }
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.saveJournalPlace(
        {
          if (widget.place != null) ...widget.place!,
          'name': name.text.trim(),
          'latitude': point.latitude,
          'longitude': point.longitude,
          'notes': notes.text.trim(),
          'category': category,
          'visited': visited ? 1 : 0,
          'favorite': favorite ? 1 : 0,
          'rating': rating,
          'visit_date': visited ? visitDate?.toIso8601String() : null,
        },
        retainedPhotos: retained,
        newPhotos: added,
        collectionIds: {if (widget.collectionId != null) widget.collectionId!},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not save this place. Check that the selected photos are available on your device, then try again.';
        });
      }
    }
  }

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: visitDate == null || visitDate!.isAfter(today)
          ? today
          : visitDate,
      firstDate: DateTime(1),
      lastDate: today,
    );
    if (selected != null && mounted) setState(() => visitDate = selected);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.place == null ? 'A place to remember' : 'Edit place'),
      titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      content: SizedBox(
        width: 480,
        child: loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error == null)
                    const CircularProgressIndicator()
                  else ...[
                    Text(error!),
                    TextButton(
                      onPressed: loadPhotos,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Form(
                  key: form,
                  child: AbsorbPointer(
                    absorbing: busy,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'Place name',
                            hintText: 'Give this spot a name',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Give this place a name'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          key: locationKey,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    selectedLocation == null
                                        ? Icons.add_location_alt_outlined
                                        : Icons.location_on_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedLocation == null
                                          ? 'Where is this place?'
                                          : 'Location selected',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (selectedLocation != null && canPickMap)
                                    IconButton(
                                      tooltip: 'Change location',
                                      onPressed: chooseLocation,
                                      icon: const Icon(
                                        Icons.edit_location_alt_outlined,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                selectedLocation == null
                                    ? 'Choose a spot to pin this memory.'
                                    : widget.place == null
                                    ? 'Ready to save with this place.'
                                    : 'Your saved pin is kept.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (locationRequired)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Choose a location before saving.',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              if (locationError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    locationError!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              if (selectedLocation == null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if (canPickMap)
                                      TextButton.icon(
                                        onPressed: chooseLocation,
                                        icon: const Icon(
                                          Icons.map_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          selectedLocation == null
                                              ? 'Choose on map'
                                              : 'Change location',
                                        ),
                                      ),
                                    TextButton.icon(
                                      onPressed: useCurrentLocation,
                                      icon: const Icon(
                                        Icons.my_location,
                                        size: 18,
                                      ),
                                      label: const Text('Use current location'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!canPickMap)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Enter coordinates'),
                            subtitle: const Text(
                              'Optional advanced entry on desktop',
                            ),
                            children: [
                              TextFormField(
                                controller: latitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? null
                                    : coordinate(v, 90),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: longitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? null
                                    : coordinate(v, 180),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: {...placeCategories, category}
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => category = v!),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: notes,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<bool>(
                          isExpanded: true,
                          initialValue: visited,
                          decoration: const InputDecoration(
                            labelText: 'Visit status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text('Want to visit'),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('Visited'),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            visited = v!;
                            if (!visited) visitDate = null;
                          }),
                        ),
                        if (visited) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: chooseDate,
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(
                                  'Visit date: ${journalDate(visitDate?.toIso8601String())}',
                                ),
                              ),
                              if (visitDate != null)
                                IconButton(
                                  onPressed: () =>
                                      setState(() => visitDate = null),
                                  tooltip: 'Clear visit date',
                                  icon: const Icon(Icons.clear),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        PlaceStarRating(
                          value: rating,
                          onChanged: (value) => setState(() => rating = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Favorite'),
                          value: favorite,
                          onChanged: (v) => setState(() => favorite = v),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Photos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'Local JPEG, PNG, or WebP files are copied into your journal when you save.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final path in retained)
                              PhotoTile(
                                file: widget.store.storage.resolve(path),
                                onRemove: () =>
                                    setState(() => retained.remove(path)),
                              ),
                            for (var i = 0; i < added.length; i++)
                              PhotoTile(
                                file: added[i],
                                onRemove: () =>
                                    setState(() => added.removeAt(i)),
                              ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: pick,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('Add photos'),
                          ),
                        ),
                        if (error != null)
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || loading ? null : save,
          child: Text(busy ? 'Please wait...' : 'Save place'),
        ),
      ],
    ),
  );
}

class PlaceStarRating extends StatelessWidget {
  const PlaceStarRating({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Your rating', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(
        children: List.generate(5, (index) {
          final stars = index + 1;
          return Expanded(
            child: Semantics(
              selected: value == stars,
              child: IconButton(
                key: ValueKey('place-rating-$stars'),
                tooltip: 'Rate $stars ${stars == 1 ? 'star' : 'stars'}',
                onPressed: () => onChanged(stars),
                padding: EdgeInsets.zero,
                iconSize: 34,
                color: index < (value ?? 0)
                    ? const Color(0xFFB77C18)
                    : Theme.of(context).colorScheme.outline,
                icon: AnimatedScale(
                  scale: value == stars ? 1.12 : 1,
                  duration: journalMotionDuration(context, 160),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    index < (value ?? 0)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            value == null ? 'Not rated yet' : '$value of 5 stars',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (value != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const Text('Clear rating'),
            ),
        ],
      ),
    ],
  );
}

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.file,
    this.onRemove,
    this.onOpen,
    this.size = 112,
  });
  final File file;
  final double size;
  final VoidCallback? onRemove, onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: onOpen,
              child: Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).clamp(1, 1024).round(),
                errorBuilder: (_, error, stack) => const Center(
                  child: Tooltip(
                    message: 'Photo is missing or could not be read',
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filled(
              tooltip: 'Remove photo',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16),
            ),
          ),
      ],
    ),
  );
}

class PlaceDetails extends StatefulWidget {
  const PlaceDetails({
    super.key,
    required this.store,
    required this.place,
    this.canvasBuilder,
    this.locationService,
    this.offlineRegion,
  });
  final JournalStore store;
  final Map<String, Object?> place;
  final MapCanvasBuilder? canvasBuilder;
  final JournalLocation? locationService;
  final OfflineRegionDefinition? offlineRegion;
  @override
  State<PlaceDetails> createState() => _PlaceDetailsState();
}

class _PlaceDetailsState extends State<PlaceDetails> {
  late Map<String, Object?> place = widget.place;
  late Future<List<Map<String, Object?>>> photos = widget.store.attachments(
    place['id'] as int,
  );
  bool busy = false;
  String? error;
  Future<void> edit() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlaceDialog(
        store: widget.store,
        place: place,
        canvasBuilder: widget.canvasBuilder,
        locationService: widget.locationService,
        offlineRegion: widget.offlineRegion,
      ),
    );
    if (saved == true) {
      try {
        final updated = await widget.store.place(place['id'] as int);
        if (mounted) {
          setState(() {
            place = updated;
            photos = widget.store.attachments(place['id'] as int);
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                error = 'Could not reload this place. Close and open it again.',
          );
        }
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this place?'),
        content: const Text(
          'This removes the place and its journal photos from this device. Original photo files are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep place'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete place'),
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
      await widget.store.deleteJournalPlace(place['id'] as int);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not delete this place. Please try again.';
        });
      }
    }
  }

  void openPhoto(String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Journal photo'),
            leading: IconButton(
              tooltip: 'Close photo',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.file(
                widget.store.storage.resolve(path),
                errorBuilder: (_, error, stack) =>
                    const Text('This photo is missing or could not be read.'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      title: Text(place['name'] as String),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(label: Text(place['category'] as String)),
                  Chip(
                    label: Text(
                      place['visited'] == 1 ? 'Visited' : 'Want to visit',
                    ),
                  ),
                  if (place['favorite'] == 1)
                    const Chip(
                      avatar: Icon(Icons.favorite, size: 16),
                      label: Text('Favorite'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Location',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SelectableText(
                '${(place['latitude'] as num).toStringAsFixed(6)}, ${(place['longitude'] as num).toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (place['rating'] != null)
                Semantics(
                  label: '${place['rating']} out of 5 stars',
                  child: ExcludeSemantics(
                    child: Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < (place['rating'] as int)
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFB77C18),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              Text(
                place['rating'] == null
                    ? 'Not rated'
                    : 'Rating: ${place['rating']} / 5',
              ),
              const SizedBox(height: 12),
              Text(
                'Visit date: ${journalDate(place['visit_date'] as String?)}',
              ),
              const SizedBox(height: 20),
              const Text(
                'Notes',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                (place['notes'] as String).isEmpty
                    ? 'No notes yet.'
                    : place['notes'] as String,
              ),
              const SizedBox(height: 20),
              const Text(
                'Photos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, Object?>>>(
                future: photos,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(
                        () => photos = widget.store.attachments(
                          place['id'] as int,
                        ),
                      ),
                      child: const Text('Could not load photos. Retry'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Text('No photos yet.');
                  }
                  return LayoutBuilder(
                    builder: (context, bounds) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: snapshot.data!.map((photo) {
                        final path = photo['relative_path'] as String;
                        return PhotoTile(
                          size: snapshot.data!.length == 1
                              ? bounds.maxWidth.clamp(0.0, 320.0)
                              : ((bounds.maxWidth - 12) / 2).clamp(0.0, 240.0),
                          file: widget.store.storage.resolve(path),
                          onOpen: () => openPhoto(path),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit place'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: busy ? null : delete,
                      child: const Text('Delete'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
