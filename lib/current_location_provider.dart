import 'package:geolocator/geolocator.dart';

import 'package:geo_groups/geo_coordinate.dart';

/// Итог проверки доступа. Не зависит от типов geolocator.
enum LocationAccess {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  unavailable,
}

/// Источник текущей позиции устройства.
///
/// [ensurePermissionForJoin] — единственное место, где можно показать
/// системный запрос. [currentPosition] запрос не показывает.
abstract class CurrentLocationProvider {
  Future<LocationAccess> ensurePermissionForJoin();

  Future<GeoCoordinate?> currentPosition();
}

/// Порт системных служб геолокации. UI его не использует.
abstract class LocationDevice {
  Future<bool> isLocationServiceEnabled();

  Future<LocationAccess> checkPermission();

  Future<LocationAccess> requestPermission();

  Future<GeoCoordinate> getCurrentPosition();

  /// Поток позиций для переднего плана. Точность и время сохраняются.
  Stream<LocationFix> watchPositions();
}

/// Одно измерение устройства, ещё не прошедшее фильтр отправки.
class LocationFix {
  LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
}

class DeviceLocationProvider implements CurrentLocationProvider {
  DeviceLocationProvider({LocationDevice? device})
    : _device = device ?? GeolocatorLocationDevice();

  final LocationDevice _device;

  @override
  Future<LocationAccess> ensurePermissionForJoin() async {
    try {
      if (!await _device.isLocationServiceEnabled()) {
        return LocationAccess.serviceDisabled;
      }
      final status = await _device.checkPermission();
      if (status != LocationAccess.denied) {
        return status;
      }
      return await _device.requestPermission();
    } catch (_) {
      return LocationAccess.unavailable;
    }
  }

  @override
  Future<GeoCoordinate?> currentPosition() async {
    try {
      if (!await _device.isLocationServiceEnabled()) {
        return null;
      }
      if (await _device.checkPermission() != LocationAccess.granted) {
        return null;
      }
      return await _device.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }
}

class GeolocatorLocationDevice implements LocationDevice {
  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationAccess> checkPermission() async {
    return _accessFrom(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> requestPermission() async {
    return _accessFrom(await Geolocator.requestPermission());
  }

  @override
  Future<GeoCoordinate> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition();
    return GeoCoordinate(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  @override
  Stream<LocationFix> watchPositions() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).map(
      (position) => LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
      ),
    );
  }
}

LocationAccess _accessFrom(LocationPermission permission) {
  return switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.denied => LocationAccess.denied,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    LocationPermission.unableToDetermine => LocationAccess.unavailable,
  };
}
