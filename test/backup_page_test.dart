import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/backup/backup_page.dart';
import 'package:map_app/src/backup/journal_backup.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'map_browser_test.dart' show TestMapCanvas, drainMap;

class MemoryBackupFiles extends BackupFiles {
  File? selected;
  String? extension;
  Uint8List? exported;
  @override
  Future<File?> pick() async => selected;
  @override
  Future<String> save(Uint8List bytes, String extension, Rect origin) async {
    exported = bytes;
    this.extension = extension;
    return 'Saved test export';
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fieldnotes_backup_ui_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'phone restore previews records, confirms replace, merges, and exports through platform boundary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = MemoryBackupFiles();
      await tester.runAsync(() async {
        final source = await JournalStore.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/other.sqlite',
        );
        try {
          await source.savePlace({
            'name': 'Transferred coast',
            'latitude': 13.7,
            'longitude': 121.0,
          });
          files.selected = await File(
            '${directory.path}/backup.zip',
          ).writeAsBytes(await JournalBackup(source).exportZip());
        } finally {
          await source.close();
        }
        await store.savePlace({
          'name': 'Local coast',
          'latitude': 13.8,
          'longitude': 121.1,
        });
      });
      var restored = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupPage(
            store: store,
            files: files,
            onRestored: () => restored++,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Choose backup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose backup'));
      await drainMap(tester);
      await tester.ensureVisible(find.text('Merge backup'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 places · 0 collections'), findsOneWidget);
      await tester.ensureVisible(find.text('Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restore and replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore and replace'));
      await tester.pumpAndSettle();
      expect(find.text('Replace this journal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(restored, 0);
      await tester.ensureVisible(find.text('Merge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Merge backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge backup'));
      await drainMap(tester);
      expect(restored, 1);
      await tester.runAsync(() async {
        expect((await store.places()).length, 2);
      });
      await tester.ensureVisible(find.text('Export GeoJSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export GeoJSON'));
      await drainMap(tester);
      expect(files.extension, 'geojson');
      expect(files.exported, isNotEmpty);
      await tester.scrollUntilVisible(
        find.text('Export backup'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export backup'));
      await drainMap(tester);
      expect(files.extension, 'zip');
      await tester.runAsync(() async {
        expect((await JournalBackup.decode(files.exported!)).places, 2);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid selection removes previous restore preview and leaves journal unchanged',
    (tester) async {
      final files = MemoryBackupFiles();
      await tester.runAsync(() async {
        await store.savePlace({
          'name': 'Original',
          'latitude': 13.0,
          'longitude': 121.0,
        });
        files.selected = await File(
          '${directory.path}/valid.zip',
        ).writeAsBytes(await JournalBackup(store).exportZip());
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BackupPage(
            store: store,
            files: files,
            onRestored: () => fail('Must not restore invalid archive'),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Choose backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose backup'));
      await drainMap(tester);
      await tester.ensureVisible(find.text('Merge backup'));
      await tester.pumpAndSettle();
      expect(find.text('Merge backup'), findsOneWidget);
      await tester.runAsync(() async {
        files.selected = await File(
          '${directory.path}/invalid.zip',
        ).writeAsBytes([1, 2]);
      });
      await tester.ensureVisible(find.text('Choose backup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose backup'));
      await drainMap(tester);
      expect(find.text('Merge backup'), findsNothing);
      await tester.runAsync(() async {
        expect((await store.places()).single['name'], 'Original');
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backup page is accessible from Explore journal menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      JournalApp(
        store: store,
        mapCanvasBuilder: (_, options) => TestMapCanvas(options: options),
      ),
    );
    await drainMap(tester);
    await tester.tap(find.byTooltip('Journal menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup & export'));
    await tester.pumpAndSettle();
    expect(find.byType(BackupPage), findsOneWidget);
  });
}
