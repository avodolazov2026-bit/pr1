import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_status_style.dart';
import 'package:geo_groups/my_groups_screen.dart';
import 'package:geo_groups/theme/app_theme.dart';

void main() {
  late List<GeoGroup> groupsBefore;

  setUp(() {
    groupsBefore = List<GeoGroup>.of(GroupsStore.instance.groups);
    currentDemoUserId = defaultDemoUserId;
  });

  tearDown(() {
    currentDemoUserId = defaultDemoUserId;
    GroupsStore.instance.replaceGroups(groupsBefore);
  });

  test('styles follow the schedule status in both themes', () {
    final now = DateTime.now();
    final groups = _statusGroups(now);
    expect(
      groups.map((group) => group.scheduleStatus).toSet(),
      GroupScheduleStatus.values.toSet(),
    );
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      for (final group in groups) {
        final style = GroupStatusStyle.of(scheme, group);
        final (line, background, foreground) = switch (group.scheduleStatus) {
          GroupScheduleStatus.active => (
            scheme.secondary,
            scheme.secondary,
            scheme.onSecondary,
          ),
          GroupScheduleStatus.upcoming => (
            scheme.primary,
            scheme.primary,
            scheme.onPrimary,
          ),
          GroupScheduleStatus.finished => (
            scheme.onSurfaceVariant,
            scheme.onSurfaceVariant,
            scheme.surface,
          ),
          GroupScheduleStatus.cancelled => (
            scheme.error,
            scheme.error,
            scheme.onError,
          ),
          GroupScheduleStatus.expired => (
            scheme.onErrorContainer,
            scheme.errorContainer,
            scheme.onErrorContainer,
          ),
        };
        expect(style.line, line, reason: group.scheduleStatus.name);
        expect(style.badgeBackground, background);
        expect(style.badgeForeground, foreground);
        expect(
          _contrast(style.badgeForeground, style.badgeBackground),
          greaterThanOrEqualTo(4.5),
          reason: '${group.scheduleStatus.name} ${theme.brightness.name}',
        );
      }
    }
  });

  testWidgets('cards for every schedule status show the status stripe', (
    tester,
  ) async {
    final now = DateTime.now();
    final groups = [
      for (final status in GroupScheduleStatus.values)
        _statusGroups(
          now,
        ).firstWhere((group) => group.scheduleStatus == status),
    ];

    for (final group in groups) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GroupCard(group: group, onTap: () {}),
          ),
        ),
      );

      final style = GroupStatusStyle.of(
        AppTheme.light().colorScheme,
        group,
      );
      final card = tester.getRect(find.byType(GroupCard));
      final stripe = tester.getRect(find.byType(GroupStatusStripe));
      final stripeWidget = tester.widget<GroupStatusStripe>(
        find.byType(GroupStatusStripe),
      );
      final label = tester.widget<Text>(find.text(group.statusBadge));

      expect(stripeWidget.color, style.line);
      expect(stripe.width, GroupStatusStripe.width);
      expect(stripe.right, card.right);
      expect(stripe.top, card.top);
      expect(stripe.bottom, card.bottom);
      expect(stripe.left, greaterThanOrEqualTo(card.left));
      expect(label.style?.color, style.badgeForeground);
      expect(
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color == style.badgeBackground,
        ),
        isTrue,
      );
    }
  });

  testWidgets('publishing groups refreshes an open list', (tester) async {
    final now = DateTime.now();
    GroupsStore.instance.replaceGroups(const []);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    expect(find.text('Групп пока нет'), findsOneWidget);

    final published = _memberGroup(
      name: 'Опубликованная',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    GroupsStore.instance.replaceGroups([published]);
    await tester.pump();

    expect(find.text('Опубликованная'), findsOneWidget);
    expect(find.text('Активна'), findsOneWidget);
    expect(find.byType(GroupStatusStripe), findsOneWidget);
    final scheme = Theme.of(
      tester.element(find.byType(GroupStatusStripe)),
    ).colorScheme;
    expect(
      tester.widget<GroupStatusStripe>(find.byType(GroupStatusStripe)).color,
      GroupStatusStyle.of(scheme, published).line,
    );

    GroupsStore.instance.replaceGroups(const []);
    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));
    expect(find.text('За выбранный период групп пока нет'), findsOneWidget);

    final created = _memberGroup(
      name: 'Созданная с сервера',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      role: MemberRole.organizer,
    );
    GroupsStore.instance.replaceGroups([created]);
    await tester.pump();

    expect(find.text('Созданная с сервера'), findsOneWidget);
    expect(find.text('Активна'), findsOneWidget);
    expect(find.byType(GroupStatusStripe), findsOneWidget);
  });
}

List<GeoGroup> _statusGroups(DateTime now) {
  return [
    _memberGroup(
      name: 'Активная',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    ),
    _memberGroup(
      name: 'Запланированная',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    ),
    _memberGroup(
      name: 'Завершённая',
      startsAt: now.subtract(const Duration(hours: 3)),
      endsAt: now.add(const Duration(hours: 2)),
      endedByOrganizer: true,
      endedAt: now.subtract(const Duration(minutes: 5)),
    ),
    _memberGroup(
      name: 'Истекшая',
      startsAt: now.subtract(const Duration(hours: 5)),
      endsAt: now.subtract(const Duration(hours: 1)),
    ),
    _memberGroup(
      name: 'Отменённая',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
      endedByOrganizer: true,
      endedAt: now.subtract(const Duration(minutes: 5)),
    ),
  ];
}

GeoGroup _memberGroup({
  required String name,
  required DateTime startsAt,
  DateTime? endsAt,
  MemberRole role = MemberRole.participant,
  bool endedByOrganizer = false,
  DateTime? endedAt,
}) {
  final group = GeoGroup(
    id: name,
    name: name,
    createdAt: DateTime.now(),
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

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
