import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';

void main() {
  test('boundary coordinates are accepted and invalid ones are rejected', () {
    final southWest = GeoCoordinate(latitude: -90, longitude: -180);
    final northEast = GeoCoordinate(latitude: 90, longitude: 180);
    expect(southWest.latitude, -90);
    expect(southWest.longitude, -180);
    expect(northEast.latitude, 90);
    expect(northEast.longitude, 180);

    expect(
      () => GeoCoordinate(latitude: -90.1, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 90.1, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 0, longitude: -180.1),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 0, longitude: 180.1),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: double.nan, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: double.infinity, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: double.negativeInfinity, longitude: 0),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 0, longitude: double.nan),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 0, longitude: double.infinity),
      throwsArgumentError,
    );
    expect(
      () => GeoCoordinate(latitude: 0, longitude: double.negativeInfinity),
      throwsArgumentError,
    );
  });

  test('distance between antipodes stays finite', () {
    final distance = distanceBetweenMeters(
      GeoCoordinate(latitude: 0, longitude: 0),
      GeoCoordinate(latitude: 0, longitude: 180),
    );
    expect(distance.isFinite, isTrue);
    expect(distance, inInclusiveRange(20000000, 20150000));
  });

  test('equal coordinates match and the distance is symmetric', () {
    final kremlin = GeoCoordinate(latitude: 55.751244, longitude: 37.618423);
    final same = GeoCoordinate(latitude: 55.751244, longitude: 37.618423);
    final vdnh = GeoCoordinate(latitude: 55.8298, longitude: 37.6333);

    expect(kremlin, same);
    expect(kremlin.hashCode, same.hashCode);
    expect(distanceBetweenMeters(kremlin, kremlin), closeTo(0, 0.001));

    final forward = distanceBetweenMeters(kremlin, vdnh);
    final backward = distanceBetweenMeters(vdnh, kremlin);
    expect(forward, inInclusiveRange(8500, 9500));
    expect(backward, closeTo(forward, 0.001));
  });

  test('a member location keeps its member, coordinate and time', () {
    final updatedAt = DateTime.utc(2026, 11, 18, 12);
    final location = GroupMemberLocation(
      memberId: 'maria',
      coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
      updatedAt: updatedAt,
    );

    expect(location.memberId, 'maria');
    expect(location.coordinate.latitude, 55.7558);
    expect(location.updatedAt, updatedAt);
    expect(
      () => GroupMemberLocation(
        memberId: '',
        coordinate: GeoCoordinate(latitude: 0, longitude: 0),
        updatedAt: updatedAt,
      ),
      throwsArgumentError,
    );
  });

  test('a group starts without locations and replaces one per member', () {
    final now = DateTime.now();
    final group = GeoGroup(
      id: 'locations',
      name: 'Локации',
      createdAt: now,
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [
        GroupMember(id: 'maria', name: 'Мария'),
        GroupMember(id: 'alexey', name: 'Алексей'),
      ],
    );
    expect(group.memberLocations, isEmpty);
    expect(group.memberLocation('maria'), isNull);

    final first = GroupMemberLocation(
      memberId: 'maria',
      coordinate: GeoCoordinate(latitude: 55.75, longitude: 37.61),
      updatedAt: now.subtract(const Duration(minutes: 10)),
    );
    final newer = GroupMemberLocation(
      memberId: 'maria',
      coordinate: GeoCoordinate(latitude: 55.76, longitude: 37.62),
      updatedAt: now,
    );
    group.updateMemberLocation(first);
    group.updateMemberLocation(newer);

    expect(group.memberLocations, [newer]);
    expect(
      () => group.updateMemberLocation(
        GroupMemberLocation(
          memberId: 'nobody',
          coordinate: GeoCoordinate(latitude: 55.75, longitude: 37.61),
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    expect(group.memberLocations, [newer]);
    expect(() => group.memberLocations.add(newer), throwsUnsupportedError);
    expect(group.memberLocations, [newer]);
    expect(
      () => GeoGroup(
        id: 'duplicate',
        name: 'Дубль',
        createdAt: now,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
        members: [GroupMember(id: 'maria', name: 'Мария')],
        memberLocations: [first, newer],
      ),
      throwsArgumentError,
    );
  });

  test('removing a member drops only that member location', () {
    final now = DateTime.now();
    final maria = GroupMemberLocation(
      memberId: 'maria',
      coordinate: GeoCoordinate(latitude: 55.75, longitude: 37.61),
      updatedAt: now,
    );
    final alexey = GroupMemberLocation(
      memberId: 'alexey',
      coordinate: GeoCoordinate(latitude: 55.76, longitude: 37.62),
      updatedAt: now,
    );
    final group = GeoGroup(
      id: 'prune-locations',
      name: 'Состав',
      createdAt: now,
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [
        GroupMember(id: 'maria', name: 'Мария'),
        GroupMember(id: 'alexey', name: 'Алексей'),
      ],
      memberLocations: [maria, alexey],
    );

    expect(
      group.updateDetails(
        name: 'Состав',
        startsAt: group.startsAt,
        endsAt: group.endsAt,
        members: [GroupMember(id: 'maria', name: 'Мария')],
      ),
      isNull,
    );

    expect(group.memberLocation('maria'), maria);
    expect(group.memberLocation('alexey'), isNull);
  });

  test('the picnic demo locations belong only to its members', () {
    final picnic = GroupsStore.instance.groupById('picnic');
    final concert = GroupsStore.instance.groupById('concert');
    expect(picnic, isNotNull);
    expect(concert, isNotNull);
    expect(picnic!.memberLocations, isNotEmpty);
    expect(concert!.memberLocations, isEmpty);

    final memberIds = picnic.members.map((member) => member.id).toSet();
    final locationIds = picnic.memberLocations.map(
      (location) => location.memberId,
    );
    expect(locationIds.toSet().length, picnic.memberLocations.length);
    expect(memberIds.containsAll(locationIds), isTrue);
    expect(
      picnic.memberLocations.every(
        (location) => DateTime.now().difference(location.updatedAt).inHours < 1,
      ),
      isTrue,
    );
  });
}
