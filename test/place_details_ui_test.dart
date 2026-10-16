import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/app.dart';
import 'package:map_app/src/data/journal_store.dart';
import 'package:map_app/src/place_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'map_browser_test.dart' show drainMap;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late JournalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('details_layout_');
    store = await JournalStore.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/journal.sqlite',
    );
    final photo = await File('${directory.path}/photo.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await store.saveJournalPlace(
      {
        'name': 'Heem',
        'latitude': 13.93280463058106,
        'longitude': 121.15061776904258,
        'rating': 5,
        'favorite': 1,
        'category': 'Stay',
      },
      retainedPhotos: [],
      newPhotos: [photo],
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.4)]) {
    testWidgets(
      'place details use phone width and reachable actions at $width / $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(JournalApp(store: store));
        await drainMap(tester);
        await tester.tap(find.text('My Places'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Heem'));
        await drainMap(tester);
        final dialog = find.byType(AlertDialog);
        final scroll = find.descendant(
          of: dialog,
          matching: find.byType(SingleChildScrollView),
        );
        expect(tester.getRect(scroll).width, greaterThanOrEqualTo(width - 80));
        final edit = find.widgetWithText(FilledButton, 'Edit place');
        expect(tester.getRect(edit).width, greaterThanOrEqualTo(width - 80));
        expect(
          tester.getCenter(find.text('Delete')).dy,
          tester.getCenter(find.text('Close')).dy,
        );
        expect(
          tester.getRect(edit).bottom,
          lessThan(tester.getRect(find.text('Close')).top),
        );
        expect(find.text('13.932805, 121.150618'), findsOneWidget);
        await tester.ensureVisible(find.byType(PhotoTile));
        expect(tester.getRect(find.byType(PhotoTile)).width, greaterThan(220));
        await tester.tap(find.byType(PhotoTile));
      await drainMap(tester);
        expect(find.text('Journal photo'), findsOneWidget);
        await tester.tap(find.byTooltip('Close photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(PlaceDetails), findsNothing);
        final rows = await tester.runAsync(store.places);
        expect(rows!.single['latitude'], 13.93280463058106);
        expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
