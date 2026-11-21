import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_period.dart';
import 'package:geo_groups/my_groups_screen.dart';

void main() {
  const userId = 'period-member';

  setUp(() {
    currentDemoUserId = userId;
    GroupsStore.instance.replaceGroups(const []);
  });

  test('windows run forward from the local day and ignore weekdays', () {
    final saturday = DateTime(2026, 1, 31, 18);
    final sunday = DateTime(2026, 2, 1, 9);
    final saturdayWindow = groupPeriodBounds(GroupPeriod.week, saturday);
    final sundayWindow = groupPeriodBounds(GroupPeriod.week, sunday);

    expect(saturdayWindow.start, DateTime(2026, 1, 31));
    expect(saturdayWindow.end, DateTime(2026, 1, 31 + 7));
    expect(saturdayWindow.end.hour, 0);
    expect(saturdayWindow.end.minute, 0);
    expect(saturdayWindow.end.second, 0);
    expect(sundayWindow.start, DateTime(2026, 2, 1));
    expect(sundayWindow.end, DateTime(2026, 2, 8));
    expect(saturday.weekday, DateTime.saturday);
    expect(sunday.weekday, DateTime.sunday);

    expect(
      groupPeriodBounds(GroupPeriod.month, saturday).end,
      DateTime(2026, 3, 2),
    );
    expect(
      groupPeriodBounds(GroupPeriod.year, saturday).end,
      DateTime(2027, 1, 31),
    );
    expect(
      groupStartsInPeriod(DateTime(2026, 1, 31), GroupPeriod.week, saturday),
      isTrue,
    );
    expect(
      groupStartsInPeriod(
        DateTime(2026, 2, 6, 23, 59),
        GroupPeriod.week,
        saturday,
      ),
      isTrue,
    );
    expect(
      groupStartsInPeriod(DateTime(2026, 2, 7), GroupPeriod.week, saturday),
      isFalse,
    );
    expect(
      groupStartsInPeriod(
        DateTime(2026, 1, 30, 23, 59),
        GroupPeriod.week,
        saturday,
      ),
      isFalse,
    );
    expect(
      groupStartsInPeriod(DateTime(2026, 3, 2), GroupPeriod.month, saturday),
      isFalse,
    );
    expect(
      groupStartsInPeriod(
        DateTime(2026, 3, 1, 23, 59),
        GroupPeriod.month,
        saturday,
      ),
      isTrue,
    );
    expect(
      groupStartsInPeriod(DateTime(2027, 1, 31), GroupPeriod.year, saturday),
      isFalse,
    );
    expect(
      groupStartsInPeriod(
        DateTime(2027, 1, 30, 23, 59),
        GroupPeriod.year,
        saturday,
      ),
      isTrue,
    );
  });

  test('a leap day still adds whole days, not a calendar year', () {
    final now = DateTime(2024, 2, 29, 12);
    final year = groupPeriodBounds(GroupPeriod.year, now);
    final month = groupPeriodBounds(GroupPeriod.month, now);

    expect(year.start, DateTime(2024, 2, 29));
    expect(year.end, DateTime(2025, 2, 28));
    expect(month.end, DateTime(2024, 3, 30));
    expect(
      groupStartsInPeriod(DateTime(2025, 2, 28), GroupPeriod.year, now),
      isFalse,
    );
    expect(
      groupStartsInPeriod(DateTime(2025, 2, 27, 23, 59), GroupPeriod.year, now),
      isTrue,
    );
  });

  test('new year is inside the forward window when today is 31 December', () {
    final now = DateTime(2026, 12, 31, 23);
    final week = groupPeriodBounds(GroupPeriod.week, now);

    expect(week.start, DateTime(2026, 12, 31));
    expect(week.end, DateTime(2027, 1, 7));
    expect(
      groupStartsInPeriod(DateTime(2027, 1, 1, 0, 30), GroupPeriod.week, now),
      isTrue,
    );
    expect(
      groupStartsInPeriod(DateTime(2026, 12, 30, 12), GroupPeriod.week, now),
      isFalse,
    );
  });

  testWidgets('my groups start on the seven day label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));

    expect(_weight(tester, 'Неделя'), FontWeight.w700);
    expect(find.text('7 дней'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('7 дней'), findsOneWidget);
    expect(find.text('30 дней'), findsOneWidget);
    expect(find.text('365 дней'), findsOneWidget);
    expect(find.text('Неделя'), findsNothing);
    expect(_weight(tester, '7 дней'), FontWeight.w700);
    expect(_weight(tester, '30 дней'), FontWeight.w400);
    expect(_weight(tester, '365 дней'), FontWeight.w400);
    expect(find.text('Групп пока нет'), findsOneWidget);
    expect(find.text('В выбранном периоде групп нет'), findsNothing);
  });

  testWidgets('no groups at all keep the initial empty message', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('Групп пока нет'), findsOneWidget);
    expect(find.text('В выбранном периоде групп нет'), findsNothing);
    expect(find.text('Активные'), findsNothing);
  });

  testWidgets('startsAt is filtered locally across 7, 30 and 365 days', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 31, 18);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GroupsStore.instance
      ..addGroup(
        _group('today', DateTime(2026, 1, 31, 8), DateTime(2026, 1, 31, 10)),
      )
      ..addGroup(
        _group(
          'inside-week',
          DateTime(2026, 2, 6, 23),
          DateTime(2026, 2, 7, 1),
        ),
      )
      ..addGroup(
        _group('week-end', DateTime(2026, 2, 7), DateTime(2026, 2, 7, 2)),
      )
      ..addGroup(
        _group(
          'inside-month',
          DateTime(2026, 3, 1, 12),
          DateTime(2026, 3, 1, 14),
        ),
      )
      ..addGroup(
        _group('month-end', DateTime(2026, 3, 2), DateTime(2026, 3, 2, 2)),
      )
      ..addGroup(
        _group(
          'inside-year',
          DateTime(2027, 1, 30, 12),
          DateTime(2027, 1, 30, 14),
        ),
      )
      ..addGroup(
        _group('year-end', DateTime(2027, 1, 31), DateTime(2027, 1, 31, 2)),
      );
    final loaded = GroupsStore.instance.groups;

    await tester.pumpWidget(MaterialApp(home: MyGroupsScreen(now: () => now)));

    expect(find.text('today'), findsOneWidget);
    expect(find.text('inside-week'), findsOneWidget);
    expect(find.text('week-end'), findsNothing);
    expect(find.text('inside-month'), findsNothing);

    await tester.tap(find.text('30 дней'));
    await tester.pump();

    expect(identical(GroupsStore.instance.groups, loaded), isTrue);
    expect(GroupsStore.instance.groups, hasLength(7));
    expect(find.text('inside-month'), findsOneWidget);
    expect(find.text('month-end'), findsNothing);
    expect(find.text('week-end'), findsOneWidget);
    expect(_weight(tester, '30 дней'), FontWeight.w700);

    await tester.tap(find.text('365 дней'));
    await tester.pump();

    expect(identical(GroupsStore.instance.groups, loaded), isTrue);
    expect(find.text('inside-year'), findsOneWidget);
    expect(find.text('year-end'), findsNothing);
    expect(find.text('month-end'), findsOneWidget);
  });

  testWidgets('sections stay intact inside the forward window', (tester) async {
    final now = DateTime.now();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final finishedStart = _startedToday(now);
    GroupsStore.instance
      ..addGroup(
        _group(
          'active-now',
          _startedToday(now),
          now.add(const Duration(hours: 2)),
          name: 'Активная в периоде',
        ),
      )
      ..addGroup(
        _group(
          'upcoming-now',
          _laterInWindow(now),
          _laterInWindow(now).add(const Duration(hours: 2)),
          name: 'Будущая в периоде',
        ),
      )
      ..addGroup(
        _group(
          'finished-now',
          finishedStart,
          _endedAfter(finishedStart, now),
          name: 'Завершённая в периоде',
        ),
      );

    await tester.pumpWidget(MaterialApp(home: MyGroupsScreen(now: () => now)));

    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Будущие'), findsOneWidget);
    expect(find.text('Завершённые'), findsOneWidget);
    expect(find.text('Активная в периоде'), findsOneWidget);
    expect(find.text('Будущая в периоде'), findsOneWidget);
    expect(find.text('Завершённая в периоде'), findsOneWidget);
    expect(find.text('В выбранном периоде групп нет'), findsNothing);
  });

  testWidgets('an empty selected period does not keep the group cards', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 31, 18);
    GroupsStore.instance.addGroup(
      _group('yesterday', DateTime(2026, 1, 30, 12), now),
    );

    await tester.pumpWidget(MaterialApp(home: MyGroupsScreen(now: () => now)));

    expect(find.text('В выбранном периоде групп нет'), findsOneWidget);
    expect(find.text('Групп пока нет'), findsNothing);
    expect(find.text('yesterday'), findsNothing);
    expect(find.text('Активные'), findsNothing);
  });

  testWidgets('an active group that started yesterday stays outside', (
    tester,
  ) async {
    final now = DateTime.now();
    final yesterday = groupPeriodBounds(
      GroupPeriod.week,
      now,
    ).start.subtract(const Duration(hours: 12));
    GroupsStore.instance.addGroup(
      _group(
        'started-earlier',
        yesterday,
        now.add(const Duration(days: 1)),
        name: 'Началась вчера',
      ),
    );

    await tester.pumpWidget(MaterialApp(home: MyGroupsScreen(now: () => now)));

    expect(find.text('Началась вчера'), findsNothing);
    expect(find.text('В выбранном периоде групп нет'), findsOneWidget);
    expect(find.text('Активные'), findsNothing);
  });
}

FontWeight? _weight(WidgetTester tester, String label) {
  return tester.widget<Text>(find.text(label)).style?.fontWeight;
}

DateTime _startedToday(DateTime now) {
  final start = groupPeriodBounds(GroupPeriod.week, now).start;
  final earlier = now.subtract(const Duration(minutes: 20));
  if (!earlier.isBefore(start)) {
    return earlier;
  }
  return start;
}

DateTime _laterInWindow(DateTime now) {
  final end = groupPeriodBounds(GroupPeriod.week, now).end;
  final soon = now.add(const Duration(minutes: 30));
  if (soon.isBefore(end)) {
    return soon;
  }
  final last = end.subtract(const Duration(minutes: 1));
  if (last.isAfter(now)) {
    return last;
  }
  return soon;
}

DateTime _endedAfter(DateTime startsAt, DateTime now) {
  final preferred = now.subtract(const Duration(minutes: 10));
  if (preferred.isAfter(startsAt)) {
    return preferred;
  }
  final soon = startsAt.add(const Duration(minutes: 1));
  if (soon.isBefore(now)) {
    return soon;
  }
  return now;
}

GeoGroup _group(String id, DateTime startsAt, DateTime endsAt, {String? name}) {
  return GeoGroup(
    id: id,
    name: name ?? id,
    createdAt: DateTime(2026, 1, 1),
    startsAt: startsAt,
    endsAt: endsAt,
    members: [GroupMember(id: 'period-member', name: 'Участник')],
  );
}
