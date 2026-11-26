import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/group_status_style.dart';
import 'package:geo_groups/theme/app_theme.dart';

void main() {
  testWidgets('a group card shows the start, the end and the status', (
    tester,
  ) async {
    final now = DateTime.now();
    final groups = _statusGroups(now);
    expect(
      groups.map((group) => group.scheduleStatus).toSet(),
      GroupScheduleStatus.values.toSet(),
    );
    for (final group in groups) {
      await tester.pumpWidget(_cardApp(group));

      expect(
        find.text('Начало ${formatGroupSchedulePoint(group.startsAt)}'),
        findsOneWidget,
      );
      final endsAt = group.endsAt;
      expect(
        find.text(
          'Окончание ${formatGroupSchedulePoint(endsAt!)}',
        ),
        findsOneWidget,
      );
      expect(find.text(group.statusBadge), findsOneWidget);
      _expectBadgeUsesScheduleStyle(tester, group);
    }
  });

  testWidgets('an open group shows the schedule block', (tester) async {
    final now = DateTime.now();
    for (final group in _statusGroups(now)) {
      await tester.pumpWidget(_screenApp(group));

      expect(find.text('Расписание'), findsOneWidget);
      expect(find.text('Начало'), findsOneWidget);
      expect(find.text('Окончание'), findsOneWidget);
      expect(find.text('Статус'), findsOneWidget);
      expect(
        find.text(formatGroupSchedulePoint(group.startsAt)),
        findsOneWidget,
      );
      expect(
        find.text(formatGroupSchedulePoint(group.endsAt!)),
        findsOneWidget,
      );
      expect(find.text(group.statusBadge), findsOneWidget);
      _expectBadgeUsesScheduleStyle(tester, group);
    }
  });

  testWidgets('a group without an end stays open-ended', (tester) async {
    final now = DateTime.now();
    final group = _group(
      name: 'Без окончания',
      startsAt: now.subtract(const Duration(hours: 1)),
    );

    await tester.pumpWidget(_cardApp(group));
    expect(
      find.text('Начало ${formatGroupSchedulePoint(group.startsAt)}'),
      findsOneWidget,
    );
    expect(find.textContaining('Окончание'), findsNothing);
    expect(find.text(group.statusBadge), findsOneWidget);

    await tester.pumpWidget(_screenApp(group));
    expect(find.text(formatGroupSchedulePoint(group.startsAt)), findsOneWidget);
    expect(find.text(groupScheduleOpenEnded), findsOneWidget);
    expect(find.text(group.statusBadge), findsOneWidget);
    expect(group.scheduleStatus, GroupScheduleStatus.active);
  });

  testWidgets('the members section shows the current user role', (
    tester,
  ) async {
    final now = DateTime.now();
    final organizer = _group(
      name: 'Группа организатора',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      role: MemberRole.organizer,
    );
    await tester.pumpWidget(_screenApp(organizer));
    expect(find.text('Участники'), findsOneWidget);
    expect(find.text('Вы'), findsOneWidget);
    expect(find.text('Организатор'), findsOneWidget);

    final participant = _group(
      name: 'Группа участника',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    await tester.pumpWidget(_screenApp(participant));
    expect(find.text('Вы'), findsOneWidget);
    expect(find.text('Организатор'), findsNothing);
  });
}

void _expectBadgeUsesScheduleStyle(WidgetTester tester, GeoGroup group) {
  final scheme = Theme.of(
    tester.element(find.byType(GroupStatusBadge)),
  ).colorScheme;
  final style = GroupStatusStyle.of(scheme, group);
  final badge = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(GroupStatusBadge),
      matching: find.byType(DecoratedBox),
    ),
  );
  final decoration = badge.decoration as BoxDecoration;
  expect(decoration.color, style.badgeBackground);
  expect(
    tester.widget<Text>(find.text(group.statusBadge)).style?.color,
    style.badgeForeground,
  );
}

Widget _cardApp(GeoGroup group) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: GroupCard(group: group, onTap: () {})),
  );
}

Widget _screenApp(GeoGroup group) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: GroupScreen(group: group),
  );
}

List<GeoGroup> _statusGroups(DateTime now) {
  return [
    _group(
      name: 'Запланированная',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    ),
    _group(
      name: 'Активная',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    ),
    _group(
      name: 'Завершённая',
      startsAt: now.subtract(const Duration(hours: 3)),
      endsAt: now.add(const Duration(hours: 2)),
      endedByOrganizer: true,
      endedAt: now.subtract(const Duration(minutes: 5)),
    ),
    _group(
      name: 'Отменённая',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
      endedByOrganizer: true,
      endedAt: now.subtract(const Duration(minutes: 5)),
    ),
    _group(
      name: 'Истекшая',
      startsAt: now.subtract(const Duration(hours: 5)),
      endsAt: now.subtract(const Duration(hours: 1)),
    ),
  ];
}

GeoGroup _group({
  required String name,
  required DateTime startsAt,
  DateTime? endsAt,
  bool endedByOrganizer = false,
  DateTime? endedAt,
  MemberRole role = MemberRole.participant,
}) {
  final group = GeoGroup(
    id: name,
    name: name,
    createdAt: startsAt,
    startsAt: startsAt,
    endsAt: endsAt,
    createdByUserId: currentDemoUserId,
    members: [
      GroupMember(
        id: currentDemoUserId,
        name: 'Вы',
        role: role,
        status: MembershipStatus.active,
      ),
    ],
  );
  group.endedByOrganizer = endedByOrganizer;
  group.endedAt = endedAt;
  return group;
}
