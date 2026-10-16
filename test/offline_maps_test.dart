import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'package:map_app/src/map/offline_maps.dart';

final offlineTestRegion = OfflineRegion(
  id: 7,
  metadata: {'name': 'Batangas'},
  definition: OfflineRegionDefinition(
    bounds: LatLngBounds(
      southwest: LatLng(13.7, 120.9),
      northeast: LatLng(14.1, 121.2),
    ),
    mapStyleUrl: mapStyleUrl,
    minZoom: 9,
    maxZoom: 13,
  ),
);
const completeMapStatus = OfflineRegionStatus(
  completedResourceCount: 20,
  requiredResourceCount: 20,
  completedResourceSize: 2048,
  isComplete: true,
  downloadProgress: 100,
);
const partialMapStatus = OfflineRegionStatus(
  completedResourceCount: 5,
  requiredResourceCount: 20,
  completedResourceSize: 512,
  isComplete: false,
  downloadProgress: 25,
);

class FakeOfflineGateway extends OfflineMapGateway {
  bool enabled = true, failList = false, failMerge = false;
  final entries = <OfflineRegion>[offlineTestRegion];
  final statuses = <int, OfflineRegionStatus>{7: completeMapStatus};
  int merges = 0, deletes = 0;
  String? importedPath;
  @override
  bool get supported => enabled;
  @override
  Future<List<OfflineRegion>> regions() async {
    if (failList) throw StateError('Map store unavailable');
    return List.of(entries);
  }

  @override
  Future<OfflineRegionStatus> status(int id) async {
    if (!statuses.containsKey(id)) throw StateError('Status unavailable');
    return statuses[id]!;
  }

  @override
  Future<void> merge(String path) async {
    merges++;
    importedPath = path;
    expect(await File(path).exists(), isTrue);
    if (failMerge) throw StateError('Unsupported database');
  }

  @override
  Future<void> delete(int id) async {
    deletes++;
    entries.removeWhere((r) => r.id == id);
  }
}

Future<File> mapDatabaseFixture(Directory directory) => File(
  '${directory.path}/source.db',
).writeAsBytes([...'SQLite format 3\u0000'.codeUnits, ...List.filled(100, 0)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FakeOfflineGateway gateway;
  late OfflineMaps maps;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline_maps_');
    gateway = FakeOfflineGateway();
    maps = OfflineMaps(
      gateway: gateway,
      temporaryDirectory: () async => directory,
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'local map import copies into private staging, preserves source, and cleans after SDK success or failure',
    () async {
      final source = await mapDatabaseFixture(directory);
      final bytes = await source.readAsBytes();
      await maps.importDatabase(source);
      expect(gateway.importedPath, isNot(source.path));
      expect(await File(gateway.importedPath!).exists(), isFalse);
      expect(await source.readAsBytes(), bytes);
      gateway.failMerge = true;
      await expectLater(maps.importDatabase(source), throwsStateError);
      expect(await File(gateway.importedPath!).exists(), isFalse);
      expect(await source.readAsBytes(), bytes);
      expect((await directory.list().toList()).length, 1);
    },
  );

  test(
    'invalid, inaccessible, oversized and unsupported files do not reach the SDK',
    () async {
      final invalid = await File(
        '${directory.path}/invalid.db',
      ).writeAsBytes(List.filled(120, 0));
      await expectLater(
        maps.importDatabase(invalid),
        throwsA(isA<OfflineMapFailure>()),
      );
      await expectLater(
        maps.importDatabase(File('${directory.path}/missing.db')),
        throwsA(isA<FileSystemException>()),
      );
      final large = await File(
        '${directory.path}/large.db',
      ).open(mode: FileMode.write);
      await large.truncate(512 * 1024 * 1024 + 1);
      await large.close();
      await expectLater(
        maps.importDatabase(File('${directory.path}/large.db')),
        throwsA(isA<OfflineMapFailure>()),
      );
      gateway.enabled = false;
      await expectLater(
        maps.importDatabase(invalid),
        throwsA(isA<OfflineMapFailure>()),
      );
      expect(gateway.merges, 0);
      expect(await maps.list(), isEmpty);
    },
  );

  test(
    'incomplete or unavailable status is never presented as ready offline',
    () async {
      expect((await maps.list()).single.complete, isTrue);
      gateway.statuses[7] = partialMapStatus;
      expect((await maps.list()).single.complete, isFalse);
      gateway.statuses.clear();
      final area = (await maps.list()).single;
      expect(area.complete, isFalse);
      expect(area.statusError, isNotNull);
      await maps.delete(area);
      expect(await maps.list(), isEmpty);
    },
  );

  test(
    'offline camera starts inside prepared coverage while default remains Batangas',
    () {
      final position = initialCamera(offlineTestRegion.definition);
      expect(position.target.latitude, closeTo(13.9, 0.00001));
      expect(position.target.longitude, closeTo(121.05, 0.00001));
      expect(position.zoom, 9);
      expect(initialCamera(null).target, const LatLng(13.9, 121.05));
      expect(initialCamera(null).zoom, 9);
    },
  );

  test(
    'real native gateway uses the MapLibre offline APIs and parses status',
    () async {
      const channel = MethodChannel('plugins.flutter.io/maplibre_gl');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getListOfRegions') {
              return '[{"id":7,"definition":{"bounds":[[13.7,120.9],[14.1,121.2]],"mapStyleUrl":"$mapStyleUrl","minZoom":9,"maxZoom":13},"metadata":{"name":"Batangas"}}]';
            }
            if (call.method == 'getOfflineRegionStatus') {
              return '{"completedResourceCount":20,"requiredResourceCount":20,"completedResourceSize":2048,"isComplete":true,"downloadProgress":100}';
            }
            if (call.method == 'mergeOfflineRegions') return '[]';
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final native = OfflineMapGateway();
      expect((await native.regions()).single.id, 7);
      expect((await native.status(7)).isComplete, isTrue);
      await native.merge('/private/staged.db');
      await native.delete(7);
      expect(calls.map((c) => c.method), [
        'getListOfRegions',
        'getOfflineRegionStatus',
        'mergeOfflineRegions',
        'deleteOfflineRegion',
      ]);
      expect(calls[2].arguments, {'path': '/private/staged.db'});
    },
  );
}
