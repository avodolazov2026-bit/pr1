import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_map_screen.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/my_groups_screen.dart';
import 'package:geo_groups/qr_invite_screen.dart';

void main() {
  setUp(() {
    currentDemoUserId = defaultDemoUserId;
  });

  GeoGroup buildGroup({
    required String id,
    required DateTime startsAt,
    DateTime? endsAt,
    bool endedByOrganizer = false,
    String memberId = defaultDemoUserId,
    MemberRole role = MemberRole.organizer,
  }) {
    final group = GeoGroup(
      id: id,
      name: 'Группа $id',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      startsAt: startsAt,
      endsAt: endsAt,
      createdByUserId: defaultDemoUserId,
      qrInviteToken: 'token-$id',
      members: [
        GroupMember(
          id: memberId,
          name: memberId == defaultDemoUserId ? 'Вы' : 'Участник',
          role: role,
          status: MembershipStatus.active,
        ),
      ],
    );
    if (endedByOrganizer) {
      group.endedByOrganizer = true;
      group.endedAt = DateTime.now();
    }
    return group;
  }

  test(
    'statuses stay exclusive for upcoming, active and finished groups',
    () async {
      final now = DateTime.now();
      final upcoming = buildGroup(
        id: 'status-upcoming',
        startsAt: now.add(const Duration(days: 1)),
      );
      expect(upcoming.isUpcoming, isTrue);
      expect(upcoming.isActive, isFalse);
      expect(upcoming.isFinished, isFalse);
      expect(upcoming.canUseMap, isFalse);

      final active = buildGroup(
        id: 'status-active',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
      );
      expect(active.isActive, isTrue);
      expect(active.canUseMap, isTrue);
      expect(active.isUpcoming, isFalse);
      expect(active.isFinished, isFalse);

      final expired = buildGroup(
        id: 'status-expired',
        startsAt: now.subtract(const Duration(hours: 3)),
        endsAt: now.subtract(const Duration(hours: 1)),
      );
      expect(expired.isFinished, isTrue);
      expect(expired.canUseMap, isFalse);
      expect(expired.statusBadge, 'Истекла');

      final stopped = buildGroup(
        id: 'status-stopped',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(days: 1)),
        endedByOrganizer: true,
      );
      expect(stopped.isFinished, isTrue);
      expect(stopped.isActive, isFalse);
      expect(stopped.scheduleSummary, 'Завершена организатором');

      final cancelled = buildGroup(
        id: 'status-cancelled',
        startsAt: now.add(const Duration(days: 2)),
        endedByOrganizer: true,
      );
      expect(cancelled.isFinished, isTrue);
      expect(cancelled.isUpcoming, isFalse);
      expect(cancelled.statusBadge, 'Отменена');
      expect(cancelled.scheduleSummary, contains('Была запланирована на'));

      expect(
        validateGroupSchedule(
          originalStartsAt: now.add(const Duration(days: 1)),
          nextStartsAt: now.add(const Duration(days: 1)),
          originalEndsAt: now.add(const Duration(days: 2)),
          nextEndsAt: now.add(const Duration(days: 1)),
          upcoming: true,
        ),
        'Окончание должно быть позже начала',
      );
      expect(
        validateGroupSchedule(
          originalStartsAt: now.add(const Duration(days: 2)),
          nextStartsAt: now.add(const Duration(days: 2)),
          originalEndsAt: now.add(const Duration(days: 1)),
          nextEndsAt: now.add(const Duration(days: 1)),
          upcoming: true,
        ),
        'Окончание должно быть позже начала',
      );

      final becomingActive = buildGroup(
        id: 'status-soon',
        startsAt: DateTime.now().add(const Duration(milliseconds: 80)),
      );
      expect(becomingActive.isUpcoming, isTrue);
      expect(becomingActive.endsAt, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(becomingActive.isActive, isTrue);
      expect(becomingActive.isUpcoming, isFalse);
      expect(becomingActive.isFinished, isFalse);
      expect(becomingActive.canUseMap, isTrue);
    },
  );

  test('cancellation stays cancelled after the original start time', () async {
    final startsAt = DateTime.now().add(const Duration(milliseconds: 250));
    final cancelled = buildGroup(id: 'cancel-sticky', startsAt: startsAt);
    expect(GroupsStore.instance.endGroup(cancelled), isTrue);
    expect(cancelled.isFinished, isTrue);
    expect(cancelled.wasCancelledBeforeStart, isTrue);
    expect(cancelled.statusBadge, 'Отменена');
    expect(cancelled.scheduleSummary, contains('Была запланирована на'));

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(DateTime.now().isBefore(cancelled.startsAt), isFalse);
    expect(cancelled.isFinished, isTrue);
    expect(cancelled.wasCancelledBeforeStart, isTrue);
    expect(cancelled.statusBadge, 'Отменена');
    expect(
      cancelled.scheduleSummary,
      'Была запланирована на ${formatGroupDateTime(cancelled.startsAt)}',
    );

    final finished = buildGroup(
      id: 'finished-by-organizer',
      startsAt: DateTime.now().subtract(const Duration(hours: 2)),
      endsAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(GroupsStore.instance.endGroup(finished), isTrue);
    expect(finished.wasCancelledBeforeStart, isFalse);
    expect(finished.statusBadge, 'Завершена');
    expect(finished.scheduleSummary, 'Завершена организатором');

    final legacy = buildGroup(
      id: 'legacy-ended',
      startsAt: DateTime.now().add(const Duration(days: 1)),
    );
    legacy.endedByOrganizer = true;
    expect(legacy.endedAt, isNull);
    expect(legacy.wasCancelledBeforeStart, isFalse);
    expect(legacy.statusBadge, 'Завершена');
  });

  test('start time can move only while the group is upcoming', () {
    final now = DateTime.now();
    final start = now.add(const Duration(days: 2));
    final group = buildGroup(
      id: 'move-start',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 3)),
      memberId: defaultDemoUserId,
    );
    group.members.add(
      GroupMember(
        id: 'anna-smirnova',
        name: 'Анна Смирнова',
        status: MembershipStatus.invited,
      ),
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);
    final invitation = GroupsStore.instance.invitations.last;
    final memberIds = group.members.map((member) => member.id).toList();

    final nextStart = now.add(const Duration(days: 5));
    expect(
      group.updateDetails(
        name: group.name,
        startsAt: nextStart,
        endsAt: nextStart.add(const Duration(hours: 2)),
        members: List<GroupMember>.of(group.members),
      ),
      isNull,
    );
    expect(group.startsAt, nextStart);
    expect(group.members.map((member) => member.id), memberIds);
    expect(invitation.status, InvitationStatus.pending);

    expect(
      group.updateDetails(
        name: group.name,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
        members: List<GroupMember>.of(group.members),
      ),
      'Начало группы должно быть в будущем',
    );
    expect(group.startsAt, nextStart);

    final active = buildGroup(
      id: 'locked-start',
      startsAt: now.subtract(const Duration(hours: 2)),
      endsAt: now.add(const Duration(days: 1)),
    );
    final lockedStart = active.startsAt;
    expect(
      active.updateDetails(
        name: active.name,
        startsAt: now.add(const Duration(days: 1)),
        endsAt: active.endsAt,
        members: List<GroupMember>.of(active.members),
      ),
      'Время начала активной группы нельзя изменить.',
    );
    expect(active.startsAt, lockedStart);
    expect(
      active.updateDetails(
        name: active.name,
        startsAt: active.startsAt,
        endsAt: active.startsAt,
        members: List<GroupMember>.of(active.members),
      ),
      'Окончание должно быть позже начала',
    );
    expect(
      active.updateDetails(
        name: active.name,
        startsAt: active.startsAt,
        endsAt: now.add(const Duration(days: 3)),
        members: List<GroupMember>.of(active.members),
      ),
      'Нельзя продлить срок группы: это потребует нового согласия участников.',
    );
    expect(active.endsAt!.isBefore(now.add(const Duration(days: 2))), isTrue);
  });

  test('upcoming QR can be claimed and accepted without opening the map', () {
    final now = DateTime.now();
    final group = buildGroup(
      id: 'qr-upcoming',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
      memberId: 'maria-organizer',
      role: MemberRole.organizer,
    );
    GroupsStore.instance.addGroup(group);
    currentDemoUserId = 'mikhail-ivanov';
    final store = GroupsStore.instance;

    expect(
      store.claimQrInvitation(buildGroupInvitePayload(group)),
      QrInviteClaimResult.added,
    );
    expect(
      messageForQrInviteClaim(QrInviteClaimResult.added),
      isNot('Срок действия приглашения завершён'),
    );
    final invitation = store.invitations.last;
    expect(store.acceptInvitation(invitation), InvitationAcceptResult.joined);
    expect(group.currentUserIsActiveMember, isTrue);
    expect(group.canUseMap, isFalse);

    final cancelled = buildGroup(
      id: 'qr-cancelled',
      startsAt: now.add(const Duration(days: 3)),
      memberId: 'maria-organizer',
      role: MemberRole.organizer,
    );
    store.addGroup(cancelled);
    currentDemoUserId = 'elena-kuznetsova';
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(cancelled)),
      QrInviteClaimResult.added,
    );
    final pending = store.invitations.last;
    currentDemoUserId = 'maria-organizer';
    expect(store.endGroup(cancelled), isTrue);
    expect(cancelled.statusBadge, 'Отменена');
    expect(cancelled.isFinished, isTrue);
    currentDemoUserId = pending.inviteeId;
    expect(store.acceptInvitation(pending), InvitationAcceptResult.groupEnded);
    currentDemoUserId = 'dmitry-petrov';
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(cancelled)),
      QrInviteClaimResult.inactive,
    );
    expect(
      messageForQrInviteClaim(QrInviteClaimResult.inactive),
      'Срок действия приглашения завершён',
    );
  });

  testWidgets('my groups split into active, upcoming and finished sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    currentDemoUserId = 'schedule-only-user';
    final now = DateTime.now();
    final active = buildGroup(
      id: 'section-active',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 4)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    active.name = 'Секция активная';
    final laterActive = buildGroup(
      id: 'section-active-later',
      startsAt: now.subtract(const Duration(hours: 2)),
      endsAt: now.add(const Duration(days: 2)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    laterActive.name = 'Секция активная позже';
    final indefinite = buildGroup(
      id: 'section-open',
      startsAt: now.subtract(const Duration(hours: 3)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    indefinite.name = 'Секция бессрочная';
    final upcoming = buildGroup(
      id: 'section-upcoming',
      startsAt: now.add(const Duration(days: 3)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    upcoming.name = 'Секция запланированная';
    final finished = buildGroup(
      id: 'section-finished',
      startsAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 5)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    finished.name = 'Секция завершённая';
    GroupsStore.instance
      ..addGroup(finished)
      ..addGroup(upcoming)
      ..addGroup(indefinite)
      ..addGroup(laterActive)
      ..addGroup(active);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Будущие'), findsOneWidget);
    expect(find.text('Завершённые'), findsOneWidget);
    expect(find.text('Запланирована'), findsOneWidget);
    expect(find.textContaining('Начнётся'), findsOneWidget);
    expect(find.text('Активна'), findsWidgets);
    expect(
      find.text('Истекла ${formatGroupDateTime(finished.endsAt!)}'),
      findsOneWidget,
    );
    expect(find.text('Без срока окончания'), findsOneWidget);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('Активные'), lessThan(labels.indexOf('Будущие')));
    expect(labels.indexOf('Будущие'), lessThan(labels.indexOf('Завершённые')));
    expect(
      labels.indexOf('Секция активная'),
      lessThan(labels.indexOf('Секция активная позже')),
    );
    expect(
      labels.indexOf('Секция активная позже'),
      lessThan(labels.indexOf('Секция бессрочная')),
    );
    expect(
      labels.indexOf('Секция запланированная'),
      greaterThan(labels.indexOf('Будущие')),
    );
    expect(
      labels.indexOf('Секция запланированная'),
      lessThan(labels.indexOf('Завершённые')),
    );
    expect(find.text('Активна'), findsWidgets);
    expect(
      find.descendant(
        of: find.widgetWithText(Card, 'Секция завершённая'),
        matching: find.text('Активна'),
      ),
      findsNothing,
    );
  });

  testWidgets('an empty upcoming section has no header', (tester) async {
    currentDemoUserId = 'active-only-user';
    final now = DateTime.now();
    final group = buildGroup(
      id: 'only-active',
      startsAt: now.subtract(const Duration(minutes: 10)),
      endsAt: now.add(const Duration(hours: 1)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Будущие'), findsNothing);
    expect(find.text('Завершённые'), findsNothing);
  });

  testWidgets('upcoming group hides the map and an active group keeps it', (
    tester,
  ) async {
    final now = DateTime.now();
    final upcoming = buildGroup(
      id: 'screen-upcoming',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    );
    GroupsStore.instance.addGroup(upcoming);

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: upcoming)));
    expect(find.text('Открыть карту'), findsNothing);
    expect(
      find.text('Карта станет доступна после начала группы'),
      findsOneWidget,
    );
    expect(find.text('Отменить группу'), findsOneWidget);
    expect(find.text('Завершить группу'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: upcoming)));
    expect(
      find.text('Карта участников будет добавлена на следующем этапе'),
      findsNothing,
    );
    expect(
      find.text('Карта доступна только в активной группе.'),
      findsOneWidget,
    );

    final active = buildGroup(
      id: 'screen-active',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 3)),
    );
    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: active)));
    expect(find.text('Открыть карту'), findsOneWidget);
    await tester.tap(find.text('Открыть карту'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Группа: «Группа screen-active»'), findsOneWidget);
    expect(find.text('Тестовая точка на карте'), findsNothing);
    Navigator.of(tester.element(find.text('Карта группы'))).pop();
    await tester.pumpAndSettle();

    final finished = buildGroup(
      id: 'screen-finished',
      startsAt: now.subtract(const Duration(hours: 4)),
      endsAt: now.subtract(const Duration(hours: 1)),
    );
    await tester.pumpWidget(MaterialApp(home: GroupMapScreen(group: finished)));
    await tester.pumpAndSettle();
    expect(
      find.text('Карта доступна только в активной группе.'),
      findsOneWidget,
    );
    expect(find.text('Открыть карту'), findsNothing);
  });

  testWidgets('organizer can copy a QR code of an upcoming saved group', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = buildGroup(
      id: 'copy-upcoming',
      startsAt: now.add(const Duration(days: 1)),
    );
    GroupsStore.instance.addGroup(group);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: QrInviteScreen(group: group)));

    expect(find.text('Скопировать код приглашения'), findsOneWidget);
    expect(find.textContaining('Начнётся'), findsOneWidget);
    expect(find.text('Срок действия приглашения завершён'), findsNothing);
  });

  test('next status change is the nearest future start or end', () {
    final now = DateTime.now();
    final later = buildGroup(
      id: 'next-later',
      startsAt: now.add(const Duration(days: 2)),
      endsAt: now.add(const Duration(days: 3)),
    );
    final sooner = buildGroup(
      id: 'next-sooner',
      startsAt: now.add(const Duration(hours: 3)),
      endsAt: now.add(const Duration(days: 1)),
    );
    final finished = buildGroup(
      id: 'next-finished',
      startsAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 1)),
    );

    expect(
      nextGroupStatusChange([later, sooner, finished], now),
      sooner.startsAt,
    );
    expect(nextGroupStatusChange([finished], now), isNull);
  });

  testWidgets(
    'a planned card shows the active status after the list refreshes',
    (tester) async {
      currentDemoUserId = 'status-refresh-user';
      final now = DateTime.now();
      final group = buildGroup(
        id: 'status-refresh',
        startsAt: now.add(const Duration(hours: 2)),
        endsAt: now.add(const Duration(hours: 5)),
        memberId: currentDemoUserId,
        role: MemberRole.participant,
      );
      group.name = 'Скоро начнётся';
      GroupsStore.instance.addGroup(group);

      await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

      expect(find.text('Запланирована'), findsOneWidget);
      expect(find.text('Будущие'), findsOneWidget);
      expect(find.text('Активна'), findsNothing);

      group.startsAt = now.subtract(const Duration(minutes: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('Запланирована'), findsNothing);
      expect(find.text('Активна'), findsOneWidget);
      expect(find.text('Активные'), findsOneWidget);
      expect(find.text('Будущие'), findsNothing);
    },
  );

  testWidgets('returning from a group refreshes a stale list status', (
    tester,
  ) async {
    currentDemoUserId = 'status-return-user';
    final now = DateTime.now();
    final group = buildGroup(
      id: 'status-return',
      startsAt: now.add(const Duration(hours: 2)),
      endsAt: now.add(const Duration(hours: 5)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    group.name = 'Вернуться к списку';
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    expect(find.text('Запланирована'), findsOneWidget);

    await tester.tap(find.text('Вернуться к списку'));
    await tester.pumpAndSettle();
    group.startsAt = now.subtract(const Duration(minutes: 1));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Мои группы'), findsOneWidget);
    expect(find.text('Запланирована'), findsNothing);
    expect(find.text('Активна'), findsOneWidget);
  });

  testWidgets('a list without future transitions stays mounted', (
    tester,
  ) async {
    currentDemoUserId = 'status-finished-user';
    final now = DateTime.now();
    final group = buildGroup(
      id: 'status-no-timer',
      startsAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 2)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    expect(find.text('Истекла'), findsOneWidget);

    await tester.pump(const Duration(days: 1));
    expect(find.text('Истекла'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the open list becomes active when the status timer fires', (
    tester,
  ) async {
    currentDemoUserId = 'status-timer-user';
    final startsAt = DateTime.now().add(const Duration(seconds: 1));
    final group = buildGroup(
      id: 'status-timer',
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(hours: 2)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    group.name = 'Таймер статуса';
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    expect(find.text('Запланирована'), findsOneWidget);
    expect(find.text('Активна'), findsNothing);

    await tester.runAsync(() async {
      final wait =
          startsAt.difference(DateTime.now()) +
          const Duration(milliseconds: 50);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    });
    await tester.pump(const Duration(minutes: 5));

    expect(find.text('Мои группы'), findsOneWidget);
    expect(find.text('Запланирована'), findsNothing);
    expect(find.text('Активна'), findsOneWidget);
    expect(find.text('Активные'), findsOneWidget);
  });

  testWidgets('created groups become active when the status timer fires', (
    tester,
  ) async {
    currentDemoUserId = 'created-timer-user';
    final startsAt = DateTime.now().add(const Duration(seconds: 1));
    final group = GeoGroup(
      id: 'created-status-timer',
      name: 'Созданная по таймеру',
      createdAt: DateTime.now(),
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(hours: 2)),
      createdByUserId: currentDemoUserId,
      members: [
        GroupMember(
          id: currentDemoUserId,
          name: 'Организатор',
          role: MemberRole.organizer,
        ),
      ],
    );
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));
    expect(find.text('Созданные группы'), findsOneWidget);
    expect(find.text('Запланирована'), findsOneWidget);
    expect(find.text('Активна'), findsNothing);

    await tester.runAsync(() async {
      final wait =
          startsAt.difference(DateTime.now()) +
          const Duration(milliseconds: 50);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    });
    await tester.pump(const Duration(minutes: 5));

    expect(find.text('Созданные группы'), findsOneWidget);
    expect(find.text('Запланирована'), findsNothing);
    expect(find.text('Активна'), findsOneWidget);
  });

  testWidgets('disposing the list cancels the status timer', (tester) async {
    currentDemoUserId = 'status-dispose-user';
    final now = DateTime.now();
    final group = buildGroup(
      id: 'status-dispose',
      startsAt: now.add(const Duration(minutes: 30)),
      endsAt: now.add(const Duration(hours: 2)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(hours: 3));

    expect(tester.takeException(), isNull);
  });

  testWidgets('created groups caption is hidden when the period is empty', (
    tester,
  ) async {
    currentDemoUserId = 'caption-empty-creator';

    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));

    expect(find.text('Создать группу'), findsOneWidget);
    expect(find.text('Созданные мной группы'), findsNothing);
    expect(find.text('За выбранный период групп пока нет'), findsOneWidget);
  });

  testWidgets('created groups caption appears above a non-empty list', (
    tester,
  ) async {
    currentDemoUserId = 'caption-creator';
    final now = DateTime.now();
    GroupsStore.instance.addGroup(
      GeoGroup(
        id: 'caption-created',
        name: 'Моя созданная',
        createdAt: now,
        startsAt: now.subtract(const Duration(minutes: 5)),
        endsAt: now.add(const Duration(hours: 2)),
        createdByUserId: currentDemoUserId,
        members: [
          GroupMember(
            id: currentDemoUserId,
            name: 'Организатор',
            role: MemberRole.organizer,
          ),
        ],
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));

    expect(find.text('Создать группу'), findsOneWidget);
    expect(find.text('Созданные мной группы'), findsOneWidget);
    expect(find.text('Моя созданная'), findsOneWidget);
  });

  testWidgets('active groups note is hidden without active groups', (
    tester,
  ) async {
    currentDemoUserId = 'caption-finished-member';
    final now = DateTime.now();
    GroupsStore.instance.addGroup(
      buildGroup(
        id: 'caption-finished-only',
        startsAt: now.subtract(const Duration(days: 2)),
        endsAt: now.subtract(const Duration(hours: 2)),
        memberId: currentDemoUserId,
        role: MemberRole.participant,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('Завершённые'), findsOneWidget);
    expect(find.text('Активные'), findsNothing);
    expect(find.text('Группы, в которых я участвую.'), findsNothing);
  });

  testWidgets('active groups note appears under the active section', (
    tester,
  ) async {
    currentDemoUserId = 'caption-active-member';
    final now = DateTime.now();
    final group = buildGroup(
      id: 'caption-active',
      startsAt: now.subtract(const Duration(minutes: 10)),
      endsAt: now.add(const Duration(hours: 2)),
      memberId: currentDemoUserId,
      role: MemberRole.participant,
    );
    group.name = 'Моя активная';
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));

    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Группы, в которых я участвую.'), findsOneWidget);
    expect(find.text('Моя активная'), findsOneWidget);
  });
}
