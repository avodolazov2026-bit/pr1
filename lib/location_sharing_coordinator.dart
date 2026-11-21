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

  void dispose() {
    _disposed = true;
  }
}

List<GeoGroup> _groupsFromStore() => GroupsStore.instance.groups;

String _userIdFromApp() => currentDemoUserId;
