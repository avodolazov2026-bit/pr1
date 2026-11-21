import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/location_sharing_coordinator.dart';
import 'package:geo_groups/location_sharing_service.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 11, 21, 9);
  final origin = GeoCoordinate(latitude: 55.75, longitude: 37.62);

  test(
    'точка уходит с текущим пользователем и текущим списком групп',
    () async {
      final sharing = _RecordingSharing();
      final groups = [_group('group-a', capturedAt)];
      final coordinator = LocationSharingCoordinator(
        sharing: sharing,
        readGroups: () => groups,
        readUserId: () => 'user-1',
      );
      final sample = _sample(origin, capturedAt);

      await coordinator.shareSample(sample);

      expect(sharing.calls, hasLength(1));
      expect(sharing.calls.single.userId, 'user-1');
      expect(sharing.calls.single.groups.map((group) => group.id), ['group-a']);
      expect(sharing.calls.single.sample.capturedAt, capturedAt);
      expect(sharing.calls.single.sample.coordinate.latitude, origin.latitude);
    },
  );

  test('следующая точка читает уже изменённый снимок групп', () async {
    final sharing = _RecordingSharing();
    var groups = [_group('group-a', capturedAt)];
    final coordinator = LocationSharingCoordinator(
      sharing: sharing,
      readGroups: () => groups,
      readUserId: () => 'user-1',
    );

    await coordinator.shareSample(_sample(origin, capturedAt));
    groups = [_group('group-a', capturedAt), _group('group-b', capturedAt)];
    await coordinator.shareSample(
      _sample(origin, capturedAt.add(const Duration(seconds: 30))),
    );

    expect(sharing.calls[0].groups.map((group) => group.id), ['group-a']);
    expect(sharing.calls[1].groups.map((group) => group.id), [
      'group-a',
      'group-b',
    ]);
  });

  test('пустой идентификатор пользователя ничего не отправляет', () async {
    final sharing = _RecordingSharing();
    final coordinator = LocationSharingCoordinator(
      sharing: sharing,
      readGroups: () => [_group('group-a', capturedAt)],
      readUserId: () => '',
    );

    await coordinator.shareSample(_sample(origin, capturedAt));

    expect(sharing.calls, isEmpty);
  });

  test('после dispose точка больше не передаётся', () async {
    final sharing = _RecordingSharing();
    final coordinator = LocationSharingCoordinator(
      sharing: sharing,
      readGroups: () => [_group('group-a', capturedAt)],
      readUserId: () => 'user-1',
    );

    coordinator.dispose();
    await coordinator.shareSample(_sample(origin, capturedAt));

    expect(sharing.calls, isEmpty);
  });
}

LocationSample _sample(GeoCoordinate coordinate, DateTime capturedAt) {
  return LocationSample(
    coordinate: coordinate,
    accuracyMeters: 5,
    capturedAt: capturedAt,
  );
}

GeoGroup _group(String id, DateTime at) {
  return GeoGroup(
    id: id,
    name: 'Прогулка',
    createdAt: at.subtract(const Duration(days: 1)),
    startsAt: at.subtract(const Duration(hours: 1)),
    endsAt: at.add(const Duration(hours: 2)),
    members: [
      GroupMember(
        id: 'user-1',
        name: 'Участник',
        status: MembershipStatus.active,
      ),
    ],
  );
}

class _ShareCall {
  _ShareCall(this.userId, this.groups, this.sample);

  final String userId;
  final List<GeoGroup> groups;
  final LocationSample sample;
}

class _RecordingSharing extends LocationSharingService {
  _RecordingSharing() : super(repository: const LocalLocationRepository());

  final calls = <_ShareCall>[];

  @override
  Future<void> shareLocation({
    required String userId,
    required List<GeoGroup> groups,
    required LocationSample sample,
  }) async {
    calls.add(_ShareCall(userId, groups, sample));
  }
}
