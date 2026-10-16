import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'data/journal_store.dart';
import 'place_journal.dart';

Future<List<File>> pickCollectionCover() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Photos',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
        ],
      ),
    ],
  );
  return file == null ? [] : [File(file.path)];
}

class CollectionDialog extends StatefulWidget {
  const CollectionDialog({
    super.key,
    required this.store,
    this.collection,
    this.suggestedName = '',
    this.pickCover = pickCollectionCover,
  });
  final JournalStore store;
  final Map<String, Object?>? collection;
  final String suggestedName;
  final PhotoPicker pickCover;
  @override
  State<CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<CollectionDialog> {
  late final name = TextEditingController(
    text: widget.collection?['name'] as String? ?? widget.suggestedName,
  );
  late final description = TextEditingController(
    text: widget.collection?['description'] as String?,
  );
  final form = GlobalKey<FormState>();
  File? newCover;
  bool removeCover = false, busy = false;
  String? error;
  File? get cover =>
      newCover ??
      (removeCover || widget.collection?['cover_path'] == null
          ? null
          : widget.store.storage.resolve(
              widget.collection!['cover_path'] as String,
            ));
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> chooseCover() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await widget.pickCover();
      if (mounted && selected.isNotEmpty) {
        setState(() {
          newCover = selected.first;
          removeCover = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not open that cover image. Try a local JPEG, PNG, or WebP file.',
        );
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
      await widget.store.saveCollection(
        id: widget.collection?['id'] as int?,
        name: name.text,
        description: description.text,
        newCover: newCover,
        removeCover: removeCover,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not save this collection. Check available storage and the cover file, then try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.collection == null ? 'A new collection' : 'Edit collection',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
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
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Collection name',
                      hintText: 'Weekend plans',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a collection name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: description,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'What makes these places belong together?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (cover != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 140,
                        child: Image.file(
                          cover!,
                          fit: BoxFit.cover,
                          cacheWidth: 880,
                          errorBuilder: (_, error, stack) => const Center(
                            child: Text('Cover image unavailable'),
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: chooseCover,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          cover == null
                              ? 'Add cover image'
                              : 'Change cover image',
                        ),
                      ),
                      if (cover != null)
                        TextButton(
                          onPressed: () => setState(() {
                            newCover = null;
                            removeCover = true;
                          }),
                          child: const Text('Remove cover'),
                        ),
                    ],
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
          onPressed: busy ? null : save,
          child: Text(
            busy
                ? 'Saving...'
                : widget.collection == null
                ? 'Create collection'
                : 'Save collection',
          ),
        ),
      ],
    ),
  );
}
