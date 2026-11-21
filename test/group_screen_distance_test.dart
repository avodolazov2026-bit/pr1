import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/member_distance.dart';

void main() {
  testWidgets('an active member shows distance and update time', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = _activeGroup(
      now: now,
      locations: [
        _location(currentDemoUserId, 55.75, 37.62, now),
        _location(
          'maria',
          55.753,
          37.62,
          now.subtract(const Duration(minutes: 5)),
        ),
      ],
    );
    final meters = geodesicDistanceMeters(55.75, 37.62, 55.753, 37.62)!;

    await tester.pumpWidget(
      MaterialApp(
        home: GroupScreen(group: group, now: now),
      ),
    );

    expect(find.text(formatDistanceMeters(meters)!), findsOneWidget);
    expect(find.text('Обновлено 5 мин назад'), findsOneWidget);
    expect(find.text('Вы'), findsNothing);
    expect(find.textContaining('Ваша позиция'), findsNothing);
  });

  testWidgets('a missing position does not invent a distance', (tester) async {
    final now = DateTime.now();
    final group = _activeGroup(
      now: now,
      locations: [
        _location(
          'maria',
          55.76,
          37.62,
          now.subtract(const Duration(minutes: 1)),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupScreen(group: group, now: now),
      ),
    );

    expect(find.text('Нет данных о расстоянии'), findsOneWidget);
    expect(find.text('Обновлено 1 мин назад'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ м$')), findsNothing);
    expect(find.textContaining('км'), findsNothing);
  });

  testWidgets('an old position stays visible with its update time', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = _activeGroup(
      now: now,
      locations: [
        _location(currentDemoUserId, 55.75, 37.62, now),
        _location('maria', 55.76, 37.63, now.subtract(const Duration(days: 3))),
      ],
    );
    final meters = geodesicDistanceMeters(55.75, 37.62, 55.76, 37.63)!;

    await tester.pumpWidget(
      MaterialApp(
        home: GroupScreen(group: group, now: now),
      ),
    );

    expect(find.text(formatDistanceMeters(meters)!), findsOneWidget);
    expect(find.text('Обновлено 3 дн назад'), findsOneWidget);
    expect(find.text('Нет данных о расстоянии'), findsNothing);
  });

  testWidgets('a planned group does not show distances', (tester) async {
    final now = DateTime.now();
    final group = _activeGroup(
      now: now,
      startsAt: now.add(const Duration(hours: 2)),
      endsAt: now.add(const Duration(hours: 4)),
      locations: [
        _location(currentDemoUserId, 55.75, 37.62, now),
        _location('maria', 55.76, 37.62, now),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupScreen(group: group, now: now),
      ),
    );

    expect(find.text('Расстояние от вас'), findsNothing);
    expect(find.text('Нет данных о расстоянии'), findsNothing);
    expect(find.text('Мария'), findsOneWidget);
  });
}

GeoGroup _activeGroup({
  required DateTime now,
  required List<GroupMemberLocation> locations,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  return GeoGroup(
    id: 'distance-group',
    name: 'Прогулка',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: startsAt ?? now.subtract(const Duration(hours: 1)),
    endsAt: endsAt ?? now.add(const Duration(hours: 2)),
    members: [
      GroupMember(id: currentDemoUserId, name: 'Вы'),
      GroupMember(id: 'maria', name: 'Мария', distanceMeters: 120),
    ],
    memberLocations: locations,
  );
}

GroupMemberLocation _location(
  String memberId,
  double latitude,
  double longitude,
  DateTime updatedAt,
) {
  return GroupMemberLocation(
    memberId: memberId,
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    updatedAt: updatedAt,
  );
}
