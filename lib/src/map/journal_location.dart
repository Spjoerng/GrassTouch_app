import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'map_data.dart';

enum LocationIssue {
  servicesDisabled,
  denied,
  deniedForever,
  timedOut,
  unavailable,
}

class LocationFailure implements Exception {
  const LocationFailure(this.issue);
  final LocationIssue issue;
  String get message => switch (issue) {
    LocationIssue.servicesDisabled =>
      'Device location is turned off. Enable it in location settings, then try again.',
    LocationIssue.denied =>
      'Location permission was declined. You can still browse and select places on the map.',
    LocationIssue.deniedForever =>
      'Location access is blocked. Enable it in app settings to use your current location.',
    LocationIssue.timedOut =>
      'A location fix is taking too long. Try again outdoors or select a point on the map.',
    LocationIssue.unavailable =>
      'Current location is unavailable. Try again or select a point on the map.',
  };
}

/// Injectable boundary keeps permission flows testable without device prompts.
abstract class LocationGateway {
  Future<bool> serviceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<MapCoordinate> position();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class DeviceLocationGateway implements LocationGateway {
  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<MapCoordinate> position() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return MapCoordinate(p.latitude, p.longitude);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

class JournalLocation {
  JournalLocation({LocationGateway? gateway})
    : gateway = gateway ?? DeviceLocationGateway();
  final LocationGateway gateway;
  Future<MapCoordinate> locate() async {
    try {
      if (!await gateway.serviceEnabled()) {
        throw const LocationFailure(LocationIssue.servicesDisabled);
      }
      var permission = await gateway.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await gateway.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(LocationIssue.deniedForever);
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure(LocationIssue.denied);
      }
      final point = await gateway.position().timeout(
        const Duration(seconds: 16),
      );
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude.abs() > 90 ||
          point.longitude.abs() > 180) {
        throw const LocationFailure(LocationIssue.unavailable);
      }
      return point;
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(LocationIssue.timedOut);
    } on LocationServiceDisabledException {
      throw const LocationFailure(LocationIssue.servicesDisabled);
    } catch (_) {
      throw const LocationFailure(LocationIssue.unavailable);
    }
  }

  Future<bool> settings(LocationIssue issue) =>
      issue == LocationIssue.servicesDisabled
      ? gateway.openLocationSettings()
      : gateway.openAppSettings();
}
