import 'dart:math' as math;

/// Географическая точка, не зависящая от картографического SDK.
class GeoCoordinate {
  GeoCoordinate({required this.latitude, required this.longitude}) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Широта должна быть конечным числом от -90 до 90',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Долгота должна быть конечным числом от -180 до 180',
      );
    }
  }

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

const earthRadiusMeters = 6371000.0;

/// Расстояние по формуле гаверсинуса, в метрах.
double distanceBetweenMeters(GeoCoordinate from, GeoCoordinate to) {
  final latitude1 = _toRadians(from.latitude);
  final latitude2 = _toRadians(to.latitude);
  final deltaLatitude = _toRadians(to.latitude - from.latitude);
  final deltaLongitude = _toRadians(to.longitude - from.longitude);
  final double haversine =
      (math.pow(math.sin(deltaLatitude / 2), 2).toDouble() +
              math.cos(latitude1) *
                  math.cos(latitude2) *
                  math.pow(math.sin(deltaLongitude / 2), 2).toDouble())
          .clamp(0.0, 1.0)
          .toDouble();
  final arc = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * arc;
}

double _toRadians(double degrees) => degrees * math.pi / 180;

/// Последняя известная позиция участника внутри одной группы.
class GroupMemberLocation {
  GroupMemberLocation({
    required this.memberId,
    required this.coordinate,
    required this.updatedAt,
  }) {
    if (memberId.isEmpty) {
      throw ArgumentError.value(
        memberId,
        'memberId',
        'Идентификатор участника не может быть пустым',
      );
    }
  }

  final String memberId;
  final GeoCoordinate coordinate;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is GroupMemberLocation &&
      other.memberId == memberId &&
      other.coordinate == coordinate &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(memberId, coordinate, updatedAt);
}
