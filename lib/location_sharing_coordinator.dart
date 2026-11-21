import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_sharing_service.dart';

/// Связывает готовую точку с текущим пользователем и актуальным снимком групп.
///
/// Карту и поток GPS не знает. Список читается заново при каждой передаче.
class LocationSharingCoordinator {
  LocationSharingCoordinator({
    required this.sharing,
    List<GeoGroup> Function()? readGroups,
    String Function()? readUserId,
  }) : _readGroups = readGroups ?? _groupsFromStore,
       _readUserId = readUserId ?? _userIdFromApp;

  final LocationSharingService sharing;
  final List<GeoGroup> Function() _readGroups;
  final String Function() _readUserId;
  var _disposed = false;

  /// Передаёт уже полученную точку в единственный [LocationSharingService].
  Future<void> shareSample(LocationSample sample) {
    if (_disposed) {
      return Future<void>.value();
    }
    final userId = _readUserId();
    if (userId.isEmpty) {
      return Future<void>.value();
    }
    return sharing.shareLocation(
      userId: userId,
      groups: List<GeoGroup>.of(_readGroups()),
      sample: sample,
    );
  }

  /// Есть ли сейчас хотя бы одна группа, куда можно передать точку.
  bool hasSharingTarget(DateTime moment) {
    if (_disposed) {
      return false;
    }
    final userId = _readUserId();
    if (userId.isEmpty) {
      return false;
    }
    return _readGroups().any((group) => isSharingTarget(group, userId, moment));
  }

  /// Когда расписание групп пользователя изменит набор целей.
  DateTime? nextSharingBoundary(DateTime moment) {
    if (_disposed) {
      return null;
    }
    final userId = _readUserId();
    if (userId.isEmpty) {
      return null;
    }
    return sharingBoundaryAfter(
      userId: userId,
      groups: _readGroups(),
      moment: moment,
    );
  }

  void dispose() {
    _disposed = true;
  }
}

List<GeoGroup> _groupsFromStore() => GroupsStore.instance.groups;

String _userIdFromApp() => currentDemoUserId;
