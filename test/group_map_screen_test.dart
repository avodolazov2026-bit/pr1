import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('an active group shows the map and the test point', (
    tester,
  ) async {
    final now = DateTime.now();
    final active = group(
      id: 'map-active',
      name: 'Прогулка',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );

    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: active)));
    await tester.pump();

    expect(find.text('Карта группы'), findsOneWidget);
    expect(find.text('Группа: «Прогулка»'), findsOneWidget);
    expect(find.text('Тестовая точка на карте'), findsOneWidget);
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
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
