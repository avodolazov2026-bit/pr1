import 'package:geo_groups/geo_coordinate.dart';

/// Расстояние между двумя точками в метрах.
///
/// Некорректные координаты и нечисловой результат дают `null`, а не ошибку.
double? geodesicDistanceMeters(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  if (!_isLatitude(fromLatitude) ||
      !_isLongitude(fromLongitude) ||
      !_isLatitude(toLatitude) ||
      !_isLongitude(toLongitude)) {
    return null;
  }
  final meters = distanceBetweenMeters(
    GeoCoordinate(latitude: fromLatitude, longitude: fromLongitude),
    GeoCoordinate(latitude: toLatitude, longitude: toLongitude),
  );
  if (!meters.isFinite || meters < 0) {
    return null;
  }
  return meters;
}

/// `350 м` до километра и `2,3 км` начиная с километра.
String? formatDistanceMeters(double meters) {
  if (!meters.isFinite || meters < 0) {
    return null;
  }
  final roundedMeters = meters.round();
  if (roundedMeters < 1000) {
    return '$roundedMeters м';
  }
  final tenths = (roundedMeters / 100).round();
  final whole = tenths ~/ 10;
  final fraction = tenths.abs() % 10;
  return '$whole,$fraction км';
}

bool _isLatitude(double value) => value.isFinite && value >= -90 && value <= 90;

bool _isLongitude(double value) =>
    value.isFinite && value >= -180 && value <= 180;
