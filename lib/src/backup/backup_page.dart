import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/journal_store.dart';
import 'journal_backup.dart';

/// Platform dialogs are isolated so the complete restore flow can be tested.
class BackupFiles {
  Future<File?> pick() async {
    final choice = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Fieldnotes ZIP backup',
          extensions: ['zip'],
          mimeTypes: ['application/zip', 'application/x-zip-compressed'],
          uniformTypeIdentifiers: ['public.zip-archive'],
        ),
      ],
    );
    return choice == null ? null : File(choice.path);
  }

  Future<String> save(Uint8List bytes, String extension, Rect origin) async {
    final name =
        'fieldnotes_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.$extension';
    final mime = extension == 'zip'
        ? 'application/zip'
        : 'application/geo+json';
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, name));
      await file.writeAsBytes(bytes, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mime)],
          sharePositionOrigin: origin,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? 'Export ready. Sharing was cancelled; no destination was confirmed.'
          : 'Export handed to the share sheet. Check your chosen destination for the file.';
    }
    final destination = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(
          label: extension == 'zip' ? 'ZIP archive' : 'GeoJSON',
          extensions: [extension],
        ),
      ],
    );
    if (destination == null) return 'Export cancelled.';
    await XFile.fromData(
      bytes,
      mimeType: mime,
      name: name,
    ).saveTo(destination.path);
    return 'Saved to ${destination.path}';
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.store,
    required this.onRestored,
    this.files,
  });
  final JournalStore store;
  final VoidCallback onRestored;
  final BackupFiles? files;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final service = JournalBackup(widget.store);
  late final files = widget.files ?? BackupFiles();
  ValidatedBackup? preview;
  RestoreMode mode = RestoreMode.merge;
  bool busy = false;
  String? message, error;
  String activity = '';

  Future<void> run(String label, Future<void> Function() action) async {
    setState(() {
      busy = true;
      activity = label;
      message = null;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure is BackupException
              ? failure.message
              : failure is FileSystemException
              ? 'Could not read or write a file. Check available storage and file access, then retry.'
              : 'The operation could not finish. Your existing journal has been kept. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(bool geoJson, Rect origin) =>
      run('Preparing export…', () async {
        final bytes = geoJson
            ? await service.exportGeoJson()
            : await service.exportZip();
        final result = await files.save(
          bytes,
          geoJson ? 'geojson' : 'zip',
          origin,
        );
        if (mounted) setState(() => message = result);
      });

  Future<void> choose() => run('Validating backup…', () async {
    final file = await files.pick();
    if (file == null) return;
    // A previous preview must never remain available after a failed selection.
    setState(() => preview = null);
    final result = await JournalBackup.readFile(file);
    if (mounted) {
      setState(() {
        preview = result;
        mode = RestoreMode.merge;
      });
    }
  });

  Future<void> restore() async {
    final backup = preview;
    if (backup == null) return;
    if (mode == RestoreMode.replace) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace this journal?'),
          content: const Text(
            'All current places, collections, routes, and photos will be replaced by this backup. Export a backup first if you want to keep them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace journal'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await run('Restoring journal…', () async {
      await service.restore(backup, mode);
      widget.onRestored();
      if (mounted) {
        setState(() {
          preview = null;
          message =
              'Journal restored successfully. Your records and photos are available offline.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Backup & export'),
        automaticallyImplyLeading: !busy,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Your journal, wherever you go',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create a ZIP backup to transfer your journal between devices. No account or cloud sync is needed. Backups include your notes and photos; keep a copy in a destination you trust.',
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Full journal backup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Places, collections, route plans, saved road geometry, and photos in one versioned ZIP archive.',
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (buttonContext) => FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  final box =
                                      buttonContext.findRenderObject()
                                          as RenderBox;
                                  export(
                                    false,
                                    box.localToGlobal(Offset.zero) & box.size,
                                  );
                                },
                          icon: const Icon(Icons.archive_outlined),
                          label: const Text('Export backup'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Restore a backup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Select a Fieldnotes ZIP. Records, references, and checksums are checked before anything changes.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : choose,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Choose backup'),
                      ),
                      if (preview case final backup?) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Validated backup · ${backup.createdAt}\n${backup.places} places · ${backup.collections} collections · ${backup.routes} routes · ${backup.photos} photos',
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<RestoreMode>(
                          segments: const [
                            ButtonSegment(
                              value: RestoreMode.merge,
                              label: Text('Merge'),
                            ),
                            ButtonSegment(
                              value: RestoreMode.replace,
                              label: Text('Replace'),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: busy
                              ? null
                              : (value) => setState(() => mode = value.single),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          mode == RestoreMode.merge
                              ? 'Keep local fields and existing route plans for matching record IDs. Add missing records and photos, and combine collection memberships. Reimporting the same backup avoids duplicates.'
                              : 'Remove current journal records and restore this backup, including its photos. Confirmation is required.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: busy ? null : restore,
                          child: Text(
                            mode == RestoreMode.merge
                                ? 'Merge backup'
                                : 'Restore and replace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Use your places in other map apps',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'GeoJSON includes place points, collection membership, route stops, and saved road lines. Uncalculated routes have no line geometry. Photos are included only in ZIP backups. Use ZIP to restore Fieldnotes.',
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (buttonContext) => OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  final box =
                                      buttonContext.findRenderObject()
                                          as RenderBox;
                                  export(
                                    true,
                                    box.localToGlobal(Offset.zero) & box.size,
                                  );
                                },
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Export GeoJSON'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (busy) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(activity, semanticsLabel: activity),
              ],
              if (message != null) ...[
                const SizedBox(height: 20),
                Text(
                  message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Limits: 128 MB ZIP, 256 MB expanded, 32 MB per file. Imported archives must use a supported Fieldnotes format.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
