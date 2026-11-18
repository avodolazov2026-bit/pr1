import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_map_screen.dart';

void main() {
  GeoGroup group({
    required String id,
    required String name,
    required DateTime startsAt,
    DateTime? endsAt,
  }) {
    return GeoGroup(
      id: id,
      name: name,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      startsAt: startsAt,
      endsAt: endsAt,
      members: const [],
    );
  }

  testWidgets('an active group shows a marker for each active member', (
    tester,
  ) async {
    final now = DateTime.now();
    final active = GeoGroup(
      id: 'map-active',
      name: 'Прогулка',
      createdAt: now.subtract(const Duration(days: 1)),
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [
        GroupMember(id: 'maria', name: 'Мария'),
        GroupMember(
          id: 'olga',
          name: 'Ольга',
          status: MembershipStatus.invited,
        ),
        GroupMember(id: 'alexey', name: 'Алексей'),
      ],
      memberLocations: [
        GroupMemberLocation(
          memberId: 'maria',
          coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
          updatedAt: now,
        ),
        GroupMemberLocation(
          memberId: 'olga',
          coordinate: GeoCoordinate(latitude: 55.7601, longitude: 37.6186),
          updatedAt: now,
        ),
        GroupMemberLocation(
          memberId: 'alexey',
          coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: active)));
    await tester.pump();

    expect(find.text('Карта группы'), findsOneWidget);
    expect(find.text('Группа: «Прогулка»'), findsOneWidget);
    expect(find.text('Тестовая точка на карте'), findsNothing);
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    expect(_positionLabel('Мария'), findsOneWidget);
    expect(_positionLabel('Алексей'), findsOneWidget);
    expect(_positionLabel('Ольга'), findsNothing);
    expect(find.byTooltip('Мария'), findsOneWidget);
    expect(find.byTooltip('Ольга'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsNothing);
  });

  testWidgets('tap on a marker shows the member and the update time', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(home: GroupMapScreen(group: _twoActiveMembers(now))),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();

    expect(find.text('Мария'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsOneWidget);
    expect(find.text('Алексей'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsNothing);
  });

  testWidgets('tap on the same marker again hides the details', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(home: GroupMapScreen(group: _twoActiveMembers(now))),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();

    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
  });

  testWidgets('tap on empty map hides the member details', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(home: GroupMapScreen(group: _twoActiveMembers(now))),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Мария'));
    await tester.pump();
    expect(find.textContaining('Обновлено:'), findsOneWidget);

    final mapBox = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapBox.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(find.text('На карте: 2 участника'), findsOneWidget);
  });

  testWidgets(
    'a removed position clears the selection and does not restore it',
    (tester) async {
      final now = DateTime.now();
      GeoGroup withMaria({required bool located}) {
        return GeoGroup(
          id: 'map-maria',
          name: 'Прогулка',
          createdAt: now.subtract(const Duration(days: 1)),
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 2)),
          members: [GroupMember(id: 'maria', name: 'Мария')],
          memberLocations: located
              ? [
                  GroupMemberLocation(
                    memberId: 'maria',
                    coordinate: GeoCoordinate(
                      latitude: 55.7558,
                      longitude: 37.6173,
                    ),
                    updatedAt: now.subtract(const Duration(minutes: 5)),
                  ),
                ]
              : const [],
        );
      }

      await tester.pumpWidget(
        MaterialApp(home: GroupMapScreen(group: withMaria(located: true))),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Мария'));
      await tester.pump();
      expect(find.textContaining('Обновлено:'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(home: GroupMapScreen(group: withMaria(located: false))),
      );
      await tester.pump();

      expect(find.textContaining('Обновлено:'), findsNothing);
      expect(find.text('Нет актуальных позиций участников'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(home: GroupMapScreen(group: withMaria(located: true))),
      );
      await tester.pump();

      expect(find.textContaining('Обновлено:'), findsNothing);
      expect(find.text('На карте: 1 участник'), findsOneWidget);
    },
  );

  testWidgets('an active group without locations shows an empty map', (
    tester,
  ) async {
    final now = DateTime.now();
    final active = GeoGroup(
      id: 'map-empty',
      name: 'Без позиций',
      createdAt: now.subtract(const Duration(days: 1)),
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [GroupMember(id: 'maria', name: 'Мария')],
    );

    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: active)));
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNothing);
    expect(find.text('Нет актуальных позиций участников'), findsOneWidget);
    expect(find.textContaining('Обновлено:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a planned group does not build the map', (tester) async {
    final now = DateTime.now();
    final planned = group(
      id: 'map-planned',
      name: 'Позже',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    );

    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: planned)));
    await tester.pump();

    expect(
      find.text('Карта доступна только в активной группе.'),
      findsOneWidget,
    );
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Тестовая точка на карте'), findsNothing);
  });
}

GeoGroup _twoActiveMembers(DateTime now) {
  return GeoGroup(
    id: 'map-tap',
    name: 'Прогулка',
    createdAt: now.subtract(const Duration(days: 1)),
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    members: [
      GroupMember(id: 'maria', name: 'Мария'),
      GroupMember(id: 'alexey', name: 'Алексей'),
    ],
    memberLocations: [
      GroupMemberLocation(
        memberId: 'maria',
        coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
        updatedAt: now.subtract(const Duration(minutes: 5)),
      ),
      GroupMemberLocation(
        memberId: 'alexey',
        coordinate: GeoCoordinate(latitude: 55.749, longitude: 37.605),
        updatedAt: now.subtract(const Duration(minutes: 8)),
      ),
    ],
  );
}

Finder _positionLabel(String name) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.label == 'Позиция участника: $name',
  );
}
