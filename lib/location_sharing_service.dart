import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/location_upload_filter.dart';

/// Координата, уже полученная снаружи сервиса.
class LocationSample {
  LocationSample({
    required this.coordinate,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final GeoCoordinate coordinate;
  final double accuracyMeters;
  final DateTime capturedAt;
}

/// Записывает готовую точку в группы, куда пользователь сейчас может её передавать.
///
/// Карту, поток GPS и жизненный цикл приложения не знает.
class LocationSharingService {
  LocationSharingService({required this.repository});

  final LocationRepository repository;
  final Map<String, LocationUploadFilter> _filters = {};

  /// Пишет [sample] в каждую допустимую группу из снимка [groups].
  ///
  /// Сбой записи в одну группу не прерывает остальные и не запоминается фильтром.
  Future<void> shareLocation({
    required String userId,
    required List<GeoGroup> groups,
    required LocationSample sample,
  }) async {
    final targets = [
      for (final group in groups)
        if (_isSharingTarget(group, userId, sample.capturedAt)) group,
    ];
    final targetIds = {for (final group in targets) group.id};
    _filters.removeWhere((groupId, _) => !targetIds.contains(groupId));
    if (targets.isEmpty) {
      return;
    }

    for (final group in targets) {
      final filter = _filters.putIfAbsent(group.id, LocationUploadFilter.new);
      final acceptable = filter.shouldUpload(
        coordinate: sample.coordinate,
        accuracyMeters: sample.accuracyMeters,
        now: sample.capturedAt,
      );
      if (!acceptable) {
        continue;
      }
      try {
        await repository.upsertMyLocation(
          groupId: group.id,
          userId: userId,
          coordinate: sample.coordinate,
        );
      } catch (_) {
        continue;
      }
      filter.markUploaded(
        coordinate: sample.coordinate,
        uploadedAt: sample.capturedAt,
      );
    }
  }
}

/// Та же граница, что у [GeoGroup.canUseMap], но на момент точки.
///
/// Геттер модели читает [DateTime.now], поэтому здесь используется время точки.
bool _isSharingTarget(GeoGroup group, String userId, DateTime moment) {
  final endsAt = group.endsAt;
  final open =
      group.endedAt == null &&
      !group.endedByOrganizer &&
      !moment.isBefore(group.startsAt) &&
      (endsAt == null || moment.isBefore(endsAt));
  if (!open) {
    return false;
  }
  return group.members.any(
    (member) => member.id == userId && member.status == MembershipStatus.active,
  );
}
