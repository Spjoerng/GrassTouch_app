import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'map_data.dart';

class OfflineMapFailure implements Exception {
  const OfflineMapFailure(this.message);
  final String message;
}

class OfflineArea {
  const OfflineArea(this.region, this.status, {this.statusError});
  final sdk.OfflineRegion region;
  final sdk.OfflineRegionStatus? status;
  final String? statusError;
  String get name => region.metadata['name'] is String
      ? region.metadata['name'] as String
      : 'Offline area ${region.id}';
  bool get usesCurrentStyle => region.definition.mapStyleUrl == mapStyleUrl;
  bool get complete => status?.isComplete ?? false;
}

/// The SDK owns a separate tile store. It never receives journal database or
/// attachment paths, and importing map data cannot replace journal records.
class OfflineMapGateway {
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  Future<List<sdk.OfflineRegion>> regions() => sdk.getListOfRegions();
  Future<sdk.OfflineRegionStatus> status(int id) =>
      sdk.getOfflineRegionStatus(id);
  Future<void> merge(String path) async {
    await sdk.mergeOfflineRegions(path);
  }

  Future<void> delete(int id) async {
    await sdk.deleteOfflineRegion(id);
  }
}

class OfflineMaps {
  OfflineMaps({
    OfflineMapGateway? gateway,
    Future<Directory> Function()? temporaryDirectory,
  }) : gateway = gateway ?? OfflineMapGateway(),
       temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final OfflineMapGateway gateway;
  final Future<Directory> Function() temporaryDirectory;
  bool get supported => gateway.supported;

  Future<List<OfflineArea>> list() async {
    if (!supported) return [];
    final result = <OfflineArea>[];
    for (final region in await gateway.regions()) {
      try {
        result.add(OfflineArea(region, await gateway.status(region.id)));
      } catch (_) {
        result.add(
          OfflineArea(
            region,
            null,
            statusError:
                'Could not verify this area. Retry before relying on it offline.',
          ),
        );
      }
    }
    return result;
  }

  Future<void> importDatabase(File file) async {
    if (!supported) {
      throw const OfflineMapFailure(
        'Offline map data is supported on Android and iOS.',
      );
    }
    final length = await file.length();
    if (length < 100 || length > 512 * 1024 * 1024) {
      throw const OfflineMapFailure(
        'Choose a MapLibre offline database up to 512 MB.',
      );
    }
    final handle = await file.open();
    try {
      final header = await handle.read(16);
      if (!listEquals(header, 'SQLite format 3\u0000'.codeUnits)) {
        throw const OfflineMapFailure(
          'This file is not a SQLite map database. ZIP, MBTiles, and PMTiles are not supported by this importer.',
        );
      }
    } finally {
      await handle.close();
    }
    // Give native code a private, writable copy rather than a provider URL or
    // a user-owned source file. A dedicated directory confines cleanup.
    final staging = await (await temporaryDirectory()).createTemp(
      'map_import_',
    );
    try {
      final copy = await file.copy(p.join(staging.path, 'regions.db'));
      if (await copy.length() != length) {
        throw const OfflineMapFailure(
          'The selected file changed while being copied. Choose it again.',
        );
      }
      await gateway.merge(copy.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<void> delete(OfflineArea area) => gateway.delete(area.region.id);
}
