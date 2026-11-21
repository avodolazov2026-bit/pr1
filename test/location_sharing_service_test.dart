import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/location_sharing_service.dart';

void main() {
  const userId = 'user-1';
  final capturedAt = DateTime.utc(2026, 11, 21, 9);
  final origin = GeoCoordinate(latitude: 55.75, longitude: 37.62);

  test('первая точная точка записывается во все активные группы', () async {
    final repository = _JournalRepository();
    final service = LocationSharingService(repository: repository);
    final sample = _sample(origin, capturedAt);

    await service.shareLocation(
      userId: userId,
      groups: [
        _activeGroup(id: 'group-a', at: capturedAt),
        _activeGroup(id: 'group-b', at: capturedAt),
      ],
      sample: sample,
    );

    expect(repository.upserts, hasLength(2));
    expect(repository.upserts.map((call) => call.groupId), [
      'group-a',
      'group-b',
    ]);
    for (final call in repository.upserts) {
      expect(call.userId, userId);
      expect(call.coordinate.latitude, origin.latitude);
      expect(call.coordinate.longitude, origin.longitude);
    }
  });

  test('точка с точностью хуже 30 м не записывается', () async {
    final repository = _JournalRepository();
    final service = LocationSharingService(repository: repository);

    await service.shareLocation(
      userId: userId,
      groups: [
        _activeGroup(id: 'group-a', at: capturedAt),
        _activeGroup(id: 'group-b', at: capturedAt),
      ],
      sample: _sample(origin, capturedAt, accuracyMeters: 30.1),
    );

    expect(repository.upserts, isEmpty);
  });

  test('фильтр одной группы не подавляет первую запись в другую', () async {
    final repository = _JournalRepository();
    final service = LocationSharingService(repository: repository);
    final nearby = _northOf(origin, 9);
    expect(distanceBetweenMeters(origin, nearby), lessThan(10));

    await service.shareLocation(
      userId: userId,
      groups: [_activeGroup(id: 'group-a', at: capturedAt)],
      sample: _sample(origin, capturedAt),
    );
    await service.shareLocation(
      userId: userId,
      groups: [
        _activeGroup(id: 'group-a', at: capturedAt),
        _activeGroup(id: 'group-b', at: capturedAt),
      ],
      sample: _sample(nearby, capturedAt.add(const Duration(seconds: 30))),
    );

    expect(repository.upserts.map((call) => call.groupId), [
      'group-a',
      'group-b',
    ]);
    expect(repository.upserts.last.coordinate.latitude, nearby.latitude);
  });

  test(
    'ошибка одной группы не блокирует другую и не расходует её фильтр',
    () async {
      final failing = <String>{'group-a'};
      final repository = _JournalRepository(failingGroupIds: failing);
      final service = LocationSharingService(repository: repository);
      final later = capturedAt.add(const Duration(seconds: 20));

      await service.shareLocation(
        userId: userId,
        groups: [
          _activeGroup(id: 'group-a', at: capturedAt),
          _activeGroup(id: 'group-b', at: capturedAt),
        ],
        sample: _sample(origin, capturedAt),
      );

      expect(repository.upserts.map((call) => call.groupId), ['group-b']);

      failing.remove('group-a');
      await service.shareLocation(
        userId: userId,
        groups: [
          _activeGroup(id: 'group-a', at: capturedAt),
          _activeGroup(id: 'group-b', at: capturedAt),
        ],
        sample: _sample(origin, later),
      );

      expect(repository.upserts.map((call) => call.groupId), [
        'group-b',
        'group-a',
      ]);
    },
  );

  test('не записывает точку в недопустимые группы', () async {
    final cases = <String, GeoGroup>{
      'запланированная': _group(
        id: 'upcoming',
        at: capturedAt,
        startsAt: capturedAt.add(const Duration(hours: 1)),
        endsAt: capturedAt.add(const Duration(hours: 3)),
      ),
      'завершённая по времени': _group(
        id: 'expired',
        at: capturedAt,
        startsAt: capturedAt.subtract(const Duration(hours: 3)),
        endsAt: capturedAt.subtract(const Duration(minutes: 1)),
      ),
      'завершённая организатором': _endedByOrganizer(capturedAt),
      'без текущего пользователя': _group(
        id: 'foreign',
        at: capturedAt,
        memberId: 'someone-else',
      ),
      'приглашённый': _group(
        id: 'invited',
        at: capturedAt,
        status: MembershipStatus.invited,
      ),
      'покинувший': _group(
        id: 'left',
        at: capturedAt,
        status: MembershipStatus.left,
      ),
      'исключённый организатором': _group(
        id: 'removed',
        at: capturedAt,
        status: MembershipStatus.removedByOrganizer,
      ),
    };

    for (final entry in cases.entries) {
      final repository = _JournalRepository();
      final service = LocationSharingService(repository: repository);
      await service.shareLocation(
        userId: userId,
        groups: [entry.value],
        sample: _sample(origin, capturedAt),
      );
      expect(repository.upserts, isEmpty, reason: entry.key);
    }
  });

  test('возвращённая группа не наследует старый фильтр', () async {
    final repository = _JournalRepository();
    final service = LocationSharingService(repository: repository);
    final group = _activeGroup(id: 'group-a', at: capturedAt);

    await service.shareLocation(
      userId: userId,
      groups: [group],
      sample: _sample(origin, capturedAt),
    );
    await service.shareLocation(
      userId: userId,
      groups: const [],
      sample: _sample(origin, capturedAt.add(const Duration(seconds: 20))),
    );
    await service.shareLocation(
      userId: userId,
      groups: [group],
      sample: _sample(origin, capturedAt.add(const Duration(seconds: 40))),
    );

    expect(repository.upserts, hasLength(2));
    expect(
      repository.upserts.every((call) => call.groupId == 'group-a'),
      isTrue,
    );
  });

  test('завершённая группа не даёт границу расписания', () {
    final at = DateTime.utc(2026, 11, 21, 9);
    final finished = _activeGroup(id: 'finished', at: at)
      ..endedByOrganizer = true
      ..endedAt = at.subtract(const Duration(minutes: 1));
    final active = _activeGroup(id: 'active', at: at);

    expect(
      sharingBoundaryAfter(userId: userId, groups: [finished], moment: at),
      isNull,
    );
    expect(
      sharingBoundaryAfter(
        userId: userId,
        groups: [finished, active],
        moment: at,
      ),
      active.endsAt,
    );
  });
}

LocationSample _sample(
  GeoCoordinate coordinate,
  DateTime capturedAt, {
  double accuracyMeters = 5,
}) {
  return LocationSample(
    coordinate: coordinate,
    accuracyMeters: accuracyMeters,
    capturedAt: capturedAt,
  );
}

GeoGroup _activeGroup({required String id, required DateTime at}) {
  return _group(id: id, at: at);
}

GeoGroup _endedByOrganizer(DateTime at) {
  final group = _group(id: 'ended-by-organizer', at: at);
  group.endedByOrganizer = true;
  group.endedAt = at.subtract(const Duration(minutes: 5));
  return group;
}

GeoGroup _group({
  required String id,
  required DateTime at,
  String memberId = 'user-1',
  MembershipStatus status = MembershipStatus.active,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  return GeoGroup(
    id: id,
    name: 'Прогулка',
    createdAt: at.subtract(const Duration(days: 1)),
    startsAt: startsAt ?? at.subtract(const Duration(hours: 1)),
    endsAt: endsAt ?? at.add(const Duration(hours: 2)),
    members: [GroupMember(id: memberId, name: 'Участник', status: status)],
  );
}

GeoCoordinate _northOf(GeoCoordinate origin, double meters) {
  final degrees = meters / earthRadiusMeters * (180 / math.pi);
  return GeoCoordinate(
    latitude: origin.latitude + degrees,
    longitude: origin.longitude,
  );
}

class _Upsert {
  _Upsert(this.groupId, this.userId, this.coordinate);

  final String groupId;
  final String userId;
  final GeoCoordinate coordinate;
}

class _JournalRepository implements LocationRepository {
  _JournalRepository({Set<String>? failingGroupIds})
    : failingGroupIds = failingGroupIds ?? <String>{};

  final Set<String> failingGroupIds;
  final upserts = <_Upsert>[];

  @override
  Future<List<GroupMemberLocation>> loadGroupLocations(String groupId) async {
    return const [];
  }

  @override
  Future<void> upsertMyLocation({
    required String groupId,
    required String userId,
    required GeoCoordinate coordinate,
  }) async {
    if (failingGroupIds.contains(groupId)) {
      throw StateError('upsert failed');
    }
    upserts.add(_Upsert(groupId, userId, coordinate));
  }
}
