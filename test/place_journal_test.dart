import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/place_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> drain(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> editor(
  WidgetTester tester,
  JournalStore store, {
  Map<String, Object?>? place,
  PhotoPicker pick = pickJournalPhotos,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  PlaceDialog(store: store, place: place, pickPhotos: pick),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await drain(tester);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('journal_ui_');
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
    'create full journal entry with date, rating, favorite and local photo',
    (tester) async {
      tester.view.physicalSize = const Size(700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = await tester.runAsync(
        () => File('${directory.path}/photo.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      );
      await editor(tester, store, pick: () async => [source!]);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place name'),
        'Mountain cafe',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '16.4',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '120.6',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes'),
        'Coffee above the clouds',
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<bool>));
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visited').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Visit date: Not set'));
      await tester.tap(find.text('Visit date: Not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 / 5').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add photos'));
      await tester.tap(find.text('Add photos'));
      await drain(tester);
      expect(find.byType(PhotoTile), findsOneWidget);
      await tester.tap(find.text('Save place'));
      await drain(tester);
      final places = await tester.runAsync(store.places);
      final place = places!.single;
      expect(place['name'], 'Mountain cafe');
      expect(place['notes'], 'Coffee above the clouds');
      expect(place['visited'], 1);
      expect(place['favorite'], 1);
      expect(place['rating'], 5);
      final today = DateTime.now();
      expect(
        DateTime.parse(place['visit_date'] as String),
        DateTime(today.year, today.month, today.day),
      );
      final photos = await tester.runAsync(
        () => store.attachments(place['id'] as int),
      );
      expect(photos, hasLength(1));
    },
  );
  testWidgets('cancelling photo changes leaves original journal untouched', (
    tester,
  ) async {
    final source = await tester.runAsync(
      () => File('${directory.path}/photo.png').writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
    );
    final id = await tester.runAsync(
      () => store.saveJournalPlace(
        {'name': 'Old name', 'latitude': 1, 'longitude': 2},
        retainedPhotos: [],
        newPhotos: [source!],
      ),
    );
    final place = await tester.runAsync(() => store.place(id!));
    await editor(tester, store, place: place, pick: () async => [source!]);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Place name'),
      'Unsaved',
    );
    await tester.ensureVisible(find.byTooltip('Remove photo'));
    await tester.tap(find.byTooltip('Remove photo'));
    await tester.ensureVisible(find.text('Add photos'));
    await tester.tap(find.text('Add photos'));
    await drain(tester);
    await tester.tap(find.text('Cancel'));
    await drain(tester);
    expect(
      (await tester.runAsync(() => store.place(id!)))!['name'],
      'Old name',
    );
    expect(await tester.runAsync(() => store.attachments(id!)), hasLength(1));
    expect(await tester.runAsync(() => store.storage.root.list().length), 1);
  });
  testWidgets(
    'filters combine and details support edit and confirmed deletion',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await store.savePlace({
          'name': 'Pine trail',
          'latitude': 1,
          'longitude': 2,
          'category': 'Nature',
          'visited': 1,
          'favorite': 1,
          'notes': 'Cool mountain air',
          'rating': 4,
          'visit_date': '2026-10-10T00:00:00.000',
        });
        await store.savePlace({
          'name': 'Beach',
          'latitude': 2,
          'longitude': 3,
          'category': 'Nature',
          'visited': 0,
        });
        await store.savePlace({
          'name': 'Museum',
          'latitude': 3,
          'longitude': 4,
          'category': 'Culture',
          'visited': 1,
        });
      });
      await tester.pumpWidget(JournalApp(store: store));
      await drain(tester);
      await tester.tap(find.text('My Places'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nature').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Museum'), findsNothing);
      expect(find.text('Beach'), findsOneWidget);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('status-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visited').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Beach'), findsNothing);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mountain');
      await tester.pumpAndSettle();
      expect(find.text('Pine trail'), findsOneWidget);
      await tester.tap(find.text('Pine trail'));
      await drain(tester);
      expect(find.text('Cool mountain air'), findsOneWidget);
      expect(find.text('Rating: 4 / 5'), findsOneWidget);
      expect(find.text('Visit date: 2026-10-10'), findsOneWidget);
      await tester.tap(find.text('Edit place'));
      await drain(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place name'),
        'Pine forest',
      );
      await tester.tap(find.text('Save place'));
      await drain(tester);
      expect(find.text('Pine forest'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep place'));
      await tester.pumpAndSettle();
      expect(find.text('Pine forest'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete place'));
      await drain(tester);
      expect(find.text('No places found'), findsOneWidget);
      final places = await tester.runAsync(store.places);
      expect(places!.map((p) => p['name']), ['Museum', 'Beach']);
    },
  );
  testWidgets(
    'saved photos open offline and can be removed while clearing journal fields',
    (tester) async {
      final id = await tester.runAsync(() async {
        final source = await File('${directory.path}/source.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        final id = await store.saveJournalPlace(
          {
            'name': 'Photo spot',
            'latitude': 1,
            'longitude': 2,
            'rating': 4,
            'visited': 1,
            'visit_date': '2026-10-10T00:00:00.000',
          },
          retainedPhotos: [],
          newPhotos: [source],
        );
        await source.delete();
        return id;
      });
      final place = await tester.runAsync(() => store.place(id!));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceDetails(store: store, place: place!),
          ),
        ),
      );
      await drain(tester);
      await tester.ensureVisible(find.byType(PhotoTile));
      await tester.tap(find.byType(PhotoTile));
      await drain(tester);
      expect(find.text('Journal photo'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        find.text('This photo is missing or could not be read.'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit place'));
      await drain(tester);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<bool>));
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Want to visit').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not rated').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Remove photo'));
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.tap(find.text('Save place'));
      await drain(tester);
      final updated = await tester.runAsync(() => store.place(id!));
      expect(updated!['visited'], 0);
      expect(updated['visit_date'], isNull);
      expect(updated['rating'], isNull);
      await drain(tester);
      expect(find.text('No photos yet.'), findsOneWidget);
      expect(await tester.runAsync(() => store.storage.root.list().length), 0);
    },
  );
  testWidgets('picker failure and cancellation keep editor usable', (
    tester,
  ) async {
    var fail = true;
    await editor(
      tester,
      store,
      pick: () async {
        if (fail) throw const FileSystemException('Picker unavailable');
        return [];
      },
    );
    await tester.ensureVisible(find.text('Add photos'));
    await tester.tap(find.text('Add photos'));
    await drain(tester);
    expect(find.textContaining('Could not open photos.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Add photos'));
    await drain(tester);
    expect(find.byType(PhotoTile), findsNothing);
    expect(find.textContaining('Could not open photos.'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await drain(tester);
    expect(await tester.runAsync(store.places), isEmpty);
  });
}
