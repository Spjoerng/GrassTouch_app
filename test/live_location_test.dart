import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;
import 'package:maplibre_gl_platform_interface/maplibre_gl_platform_interface.dart';
import 'package:map_app/src/map/journal_location.dart';
import 'package:map_app/src/map/journal_map_view.dart';
import 'package:map_app/src/map/map_data.dart';
import 'package:map_app/src/map/native_place_map.dart';
import 'native_map_bridge_test.dart' show RecordingMapPlatform;
import 'map_browser_test.dart' show TestMapCanvas;
import 'map_data_location_test.dart' show FakeLocationGateway;

class WaitingCameraPlatform extends RecordingMapPlatform {
  final gate = Completer<void>();
  @override
  Future<bool?> animateCamera(CameraUpdate update, {Duration? duration}) async {
    await super.animateCamera(update, duration: duration);
    await gate.future;
    return true;
  }
}

void main() {
  testWidgets(
    'stopping during camera focus cannot restart tracking from queued work',
    (tester) async {
      final previousFactory = MapLibrePlatform.createInstance;
      final sdk = WaitingCameraPlatform();
      MapLibrePlatform.createInstance = () => sdk;
      addTearDown(() => MapLibrePlatform.createInstance = previousFactory);
      final camera = MapCameraRequest.focus(const MapCoordinate(13.9, 121.05));
      final errors = <String>[];
      Widget map(bool live) => MaterialApp(
        home: NativePlaceMap(
          options: MapCanvasOptions(
            places: const [],
            camera: camera,
            liveLocation: live,
            followLocation: live,
            onPlacesSelected: (_) {},
            onCoordinateSelected: (_) {},
            onReady: () {},
            onError: errors.add,
          ),
        ),
      );
      await tester.pumpWidget(map(true));
      await tester.pumpAndSettle();
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 30 && sdk.cameras.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(sdk.cameras, isNotEmpty);
      await tester.pumpWidget(map(false));
      sdk.gate.complete();
      await tester.pumpAndSettle();
      expect(
        sdk.trackingModes,
        isNot(contains(MyLocationTrackingMode.tracking)),
      );
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native live compass follows after camera focus and can stop without reuploading places',
    (tester) async {
      final previousFactory = MapLibrePlatform.createInstance;
      final sdk = RecordingMapPlatform();
      MapLibrePlatform.createInstance = () => sdk;
      addTearDown(() => MapLibrePlatform.createInstance = previousFactory);
      var ready = false;
      var dismissed = 0;
      final errors = <String>[];
      final camera = MapCameraRequest.focus(const MapCoordinate(13.9, 121.05));
      Widget map({required bool live, required bool follow}) => MaterialApp(
        home: NativePlaceMap(
          options: MapCanvasOptions(
            places: const [],
            location: const MapCoordinate(13.9, 121.05),
            camera: camera,
            liveLocation: live,
            followLocation: follow,
            onFollowLocationDismissed: () => dismissed++,
            onPlacesSelected: (_) {},
            onCoordinateSelected: (_) {},
            onReady: () => ready = true,
            onError: errors.add,
          ),
        ),
      );
      await tester.pumpWidget(map(live: false, follow: false));
      await tester.pumpAndSettle();
      sdk.onMapStyleLoadedPlatform(null);
      for (var i = 0; i < 30 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready, isTrue);
      expect(
        tester
            .widget<gl.MapLibreMap>(find.byType(gl.MapLibreMap))
            .myLocationEnabled,
        isFalse,
      );
      await tester.pumpWidget(map(live: true, follow: true));
      await tester.pumpAndSettle();
      final native = tester.widget<gl.MapLibreMap>(find.byType(gl.MapLibreMap));
      expect(native.myLocationEnabled, isTrue);
      expect(native.myLocationRenderMode, MyLocationRenderMode.compass);
      expect(native.locationEnginePlatforms.enableHighAccuracy, isTrue);
      expect(sdk.trackingModes.last, MyLocationTrackingMode.tracking);
      expect(
        sdk.cameraActions.indexOf('camera'),
        lessThan(
          sdk.cameraActions.indexOf(
            'tracking:${MyLocationTrackingMode.tracking}',
          ),
        ),
      );
      expect(sdk.updates['journal-location']!['features'], isEmpty);
      final placeUpdates = sdk.updateCounts[placesSourceId];
      sdk.onCameraTrackingDismissedPlatform(null);
      expect(dismissed, 1);
      await tester.pumpWidget(map(live: true, follow: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(map(live: true, follow: true));
      await tester.pumpAndSettle();
      expect(
        sdk.trackingModes.where((m) => m == MyLocationTrackingMode.tracking),
        hasLength(2),
      );
      await tester.pumpWidget(map(live: false, follow: false));
      await tester.pumpAndSettle();
      expect(sdk.trackingModes.last, MyLocationTrackingMode.none);
      expect(
        tester
            .widget<gl.MapLibreMap>(find.byType(gl.MapLibreMap))
            .myLocationEnabled,
        isFalse,
      );
      expect(sdk.updateCounts[placesSourceId], placeUpdates);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'live location starts explicitly; pan, recenter, stop and background preserve chosen pin',
    (tester) async {
      final gateway = FakeLocationGateway();
      late MapCanvasOptions latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JournalMapView(
              places: const [],
              onPlacesSelected: (_) {},
              onSaveCoordinate: (_) async => false,
              onShowList: () {},
              locationService: JournalLocation(gateway: gateway),
              canvasBuilder: (_, options) {
                latest = options;
                return TestMapCanvas(options: options);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isFalse);
      expect(gateway.fixes, 0);
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isTrue);
      expect(latest.followLocation, isTrue);
      final selection = latest.selected;
      latest.onFollowLocationDismissed!();
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isTrue);
      expect(latest.followLocation, isFalse);
      expect(find.text('Live · Exploring'), findsOneWidget);
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(latest.followLocation, isTrue);
      expect(gateway.fixes, 1);
      await tester.tap(find.byTooltip('Stop live location'));
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isFalse);
      expect(latest.selected, same(selection));
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(gateway.fixes, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // Hidden/paused apps do not render; inspect the updated canvas on resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(latest.liveLocation, isFalse);
      expect(gateway.fixes, 2);
      expect(gateway.requests, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
