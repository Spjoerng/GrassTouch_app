import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'data/journal_store.dart';
import 'data/place_filter.dart';

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
  });
  final JournalStore store;
  final Map<String, Object?>? place;
  final double? initialLatitude, initialLongitude;
  final int? collectionId;
  final PhotoPicker pickPhotos;
  @override
  State<PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<PlaceDialog> {
  final form = GlobalKey<FormState>();
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
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.saveJournalPlace(
        {
          if (widget.place != null) ...widget.place!,
          'name': name.text.trim(),
          'latitude': double.parse(latitude.text.trim()),
          'longitude': double.parse(longitude.text.trim()),
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
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Give this place a name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          validator: (v) => coordinate(v, 90),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          validator: (v) => coordinate(v, 180),
                        ),
                        const SizedBox(height: 16),
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
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: rating ?? 0,
                          decoration: const InputDecoration(
                            labelText: 'Rating',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 0,
                              child: Text('Not rated'),
                            ),
                            ...List.generate(
                              5,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('${i + 1} / 5'),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => rating = v == 0 ? null : v),
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

class PhotoTile extends StatelessWidget {
  const PhotoTile({super.key, required this.file, this.onRemove, this.onOpen});
  final File file;
  final VoidCallback? onRemove, onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112,
    height: 112,
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
                cacheWidth: 336,
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
  const PlaceDetails({super.key, required this.store, required this.place});
  final JournalStore store;
  final Map<String, Object?> place;
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
      builder: (_) => PlaceDialog(store: widget.store, place: place),
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
              SelectableText(
                'Coordinates: ${place['latitude']}, ${place['longitude']}',
              ),
              const SizedBox(height: 12),
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
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: snapshot.data!.map((photo) {
                      final path = photo['relative_path'] as String;
                      return PhotoTile(
                        file: widget.store.storage.resolve(path),
                        onOpen: () => openPhoto(path),
                      );
                    }).toList(),
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
        TextButton(
          onPressed: busy ? null : delete,
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: busy ? null : edit,
          child: const Text('Edit place'),
        ),
      ],
    ),
  );
}
