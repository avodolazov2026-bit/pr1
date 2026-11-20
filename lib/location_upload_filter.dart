import 'package:geo_groups/geo_coordinate.dart';

/// Решает, стоит ли отправлять координату.
///
/// [shouldUpload] состояние не меняет. Последняя успешная отправка
/// запоминается только в [markUploaded], после сохранения на сервере.
class LocationUploadFilter {
  /// Точки с точностью хуже этого порога не отправляются.
  static const maxAccuracyMeters = 30.0;

  /// Сдвиг от последней успешно сохранённой точки, достаточный для отправки.
  static const minimumDistanceMeters = 10.0;

  /// Пауза после успешного сохранения, после которой точка отправляется снова.
  static const maximumInterval = Duration(minutes: 2);

  GeoCoordinate? _uploadedCoordinate;
  DateTime? _uploadedAt;

  bool shouldUpload({
    required GeoCoordinate coordinate,
    required double accuracyMeters,
    required DateTime now,
  }) {
    if (accuracyMeters > maxAccuracyMeters) {
      return false;
    }
    final uploadedCoordinate = _uploadedCoordinate;
    final uploadedAt = _uploadedAt;
    if (uploadedCoordinate == null || uploadedAt == null) {
      return true;
    }
    final moved =
        distanceBetweenMeters(uploadedCoordinate, coordinate) >=
        minimumDistanceMeters;
    final waited = !now.isBefore(uploadedAt.add(maximumInterval));
    return moved || waited;
  }

  /// Запоминает координату и время только успешного сохранения.
  void markUploaded({
    required GeoCoordinate coordinate,
    required DateTime uploadedAt,
  }) {
    _uploadedCoordinate = coordinate;
    _uploadedAt = uploadedAt;
  }
}
