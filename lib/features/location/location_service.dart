import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Whether the app may read the device's position.
enum LocationAccess {
  /// Allowed (while the app is in use).
  granted,

  /// Not allowed yet or refused; asking again may show the system prompt.
  denied,

  /// Refused for good: only the system settings can change it.
  deniedForever,

  /// The device's location services are off.
  serviceOff,
}

/// Where the device is.
class DevicePosition {
  const DevicePosition({
    required this.point,
    required this.at,
    this.accuracyMeters,
    this.heading,
  });

  final LatLng point;
  final DateTime at;
  final double? accuracyMeters;

  /// Degrees clockwise from north when moving, else null.
  final double? heading;
}

/// The position could not be read (timed out, no signal, not allowed).
class LocationUnavailable implements Exception {
  const LocationUnavailable([this.reason]);

  final String? reason;

  @override
  String toString() => 'LocationUnavailable(${reason ?? ''})';
}

/// The device's position. The app talks to this and never to the plugin, so
/// tests give it a fake.
abstract interface class LocationService {
  /// The current permission, without asking.
  Future<LocationAccess> access();

  /// Asks for permission when it can be asked for (the system prompt).
  Future<LocationAccess> requestAccess();

  /// One reading. [precise] false asks the device for a coarse one, which
  /// is quicker and uses less battery.
  Future<DevicePosition> currentPosition({bool precise = true});

  /// Readings as the device moves, at most one per [minDistanceMeters]
  /// moved.
  Stream<DevicePosition> positions({
    bool precise = true,
    int minDistanceMeters = 10,
  });

  /// Opens the system settings page where the permission is changed.
  Future<void> openSettings();
}

/// [LocationService] on the geolocator plugin (iOS, macOS and the web).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      return _fromPermission(await Geolocator.checkPermission());
    } on Object {
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> requestAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return _fromPermission(permission);
    } on Object {
      return LocationAccess.denied;
    }
  }

  static LocationAccess _fromPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  static LocationSettings _settings(bool precise, int distanceFilter) {
    return LocationSettings(
      accuracy: precise ? LocationAccuracy.high : LocationAccuracy.low,
      distanceFilter: distanceFilter,
    );
  }

  static DevicePosition _convert(Position position) {
    return DevicePosition(
      point: LatLng(position.latitude, position.longitude),
      at: position.timestamp.toUtc(),
      accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
      heading: position.heading > 0 ? position.heading : null,
    );
  }

  @override
  Future<DevicePosition> currentPosition({bool precise = true}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precise ? LocationAccuracy.high : LocationAccuracy.low,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      return _convert(position);
    } on Object catch (error) {
      throw LocationUnavailable('$error');
    }
  }

  @override
  Stream<DevicePosition> positions({
    bool precise = true,
    int minDistanceMeters = 10,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: _settings(precise, minDistanceMeters),
    ).map(_convert);
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } on Object {
      // Nothing to open on this platform (the web): the browser's address
      // bar holds the site's permissions.
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});
