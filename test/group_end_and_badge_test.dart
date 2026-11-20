import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/invite_source_sheet.dart';
import 'package:geo_groups/main.dart';

void main() {
  var sequence = 0;

  setUp(() {
    currentDemoUserId = defaultDemoUserId;
  });

  GeoGroup buildGroup({
    required String inviteeId,
    required String inviteeName,
    bool inviteeIsOrganizer = false,
    bool active = true,
    bool indefinite = false,
  }) {
    sequence += 1;
    final now = DateTime.now();
    return GeoGroup(
      id: 'end-badge-$sequence',
      name: 'Группа $sequence',
      createdAt: now,
      startsAt: active || indefinite
          ? now.subtract(const Duration(minutes: 5))
          : now.subtract(const Duration(hours: 3)),
      endsAt: indefinite
          ? null
          : active
          ? now.add(const Duration(days: 2))
          : now.subtract(const Duration(hours: 2)),
      createdByUserId: inviteeIsOrganizer ? inviteeId : 'organizer',
      members: [
        if (!inviteeIsOrganizer)
          GroupMember(
            id: 'organizer',
            name: 'Мария Ковалёва',
            role: MemberRole.organizer,
          ),
        GroupMember(
          id: inviteeId,
          name: inviteeName,
          role: inviteeIsOrganizer
              ? MemberRole.organizer
              : MemberRole.participant,
          status: inviteeIsOrganizer
              ? MembershipStatus.active
              : MembershipStatus.invited,
        ),
      ],
    );
  }

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen(key: UniqueKey())));
  }

  test('participant cannot end someone else\'s group', () {
    final group = buildGroup(inviteeId: currentDemoUserId, inviteeName: 'Вы');
    group.members.last.status = MembershipStatus.active;
    expect(GroupsStore.instance.endGroup(group), isFalse);
    expect(group.isActive, isTrue);
    expect(group.endedByOrganizer, isFalse);
  });

  test('ending keeps the group and invitation history', () {
    final group = buildGroup(
      inviteeId: 'anna-smirnova',
      inviteeName: 'Анна Смирнова',
      inviteeIsOrganizer: false,
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);
    final invitation = GroupsStore.instance.invitations.last;
    expect(invitation.status, InvitationStatus.pending);

    currentDemoUserId = 'organizer';
    expect(GroupsStore.instance.endGroup(group), isTrue);
    expect(group.endedByOrganizer, isTrue);
    expect(group.isActive, isFalse);
    expect(GroupsStore.instance.groupById(group.id), same(group));
    expect(invitation.status, InvitationStatus.pending);
    expect(
      group.updateDetails(
        name: 'Новое имя',
        startsAt: group.startsAt,
        endsAt: group.endsAt,
        members: List<GroupMember>.of(group.members),
      ),
      'Завершённую группу нельзя изменить.',
    );

    final before = GroupsStore.instance.invitations.length;
    group.members.add(
      GroupMember(
        id: 'dmitry-petrov',
        name: 'Дмитрий Петров',
        status: MembershipStatus.invited,
      ),
    );
    GroupsStore.instance.syncInvitations(group);
    expect(GroupsStore.instance.invitations.length, before);
    expect(GroupsStore.instance.pendingInvitationCountFor('anna-smirnova'), 0);
    expect(GroupsStore.instance.pendingInvitationCountFor('dmitry-petrov'), 0);
  });

  test('pending count ignores other users and ended groups', () {
    const userId = 'anna-smirnova';
    final active = buildGroup(inviteeId: userId, inviteeName: 'Анна Смирнова');
    final ended = buildGroup(
      inviteeId: userId,
      inviteeName: 'Анна Смирнова',
      active: false,
    );
    final other = buildGroup(
      inviteeId: 'olga-sokolova',
      inviteeName: 'Ольга Соколова',
    );
    final store = GroupsStore.instance;
    store
      ..addGroup(active)
      ..addGroup(ended)
      ..addGroup(other);
    store.syncInvitations(active);
    store.syncInvitations(other);
    store.invitations.add(
      GroupInvitation(
        id: 'ended-manual-$sequence',
        groupId: ended.id,
        inviterName: 'Мария Ковалёва',
        inviteeId: userId,
        inviteeName: 'Михаил Иванов',
        source: InvitationSource.demoList,
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
      ),
    );

    final activeCount = store.invitations
        .where(
          (invitation) =>
              invitation.inviteeId == userId &&
              invitation.groupId == active.id &&
              invitation.status == InvitationStatus.pending,
        )
        .length;
    expect(activeCount, 1);
    expect(
      store.pendingInvitationCountFor(userId),
      store.invitations
          .where(
            (invitation) =>
                invitation.inviteeId == userId &&
                invitation.status == InvitationStatus.pending &&
                store.groupById(invitation.groupId)?.isFinished == false,
          )
          .length,
    );
    expect(
      store.invitations.any(
        (invitation) =>
            invitation.groupId == ended.id &&
            invitation.status == InvitationStatus.pending,
      ),
      isTrue,
    );
  });

  testWidgets('organizer ends an active group and QR stays closed', (
    tester,
  ) async {
    final group = buildGroup(
      inviteeId: currentDemoUserId,
      inviteeName: 'Вы',
      inviteeIsOrganizer: true,
      indefinite: true,
    );
    GroupsStore.instance.addGroup(group);

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: group)));

    expect(find.text('Завершить группу'), findsOneWidget);
    expect(find.text('Покинуть группу'), findsNothing);
    expect(find.text('Открыть карту'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.text('Завершить группу'));
    await tester.pumpAndSettle();
    expect(find.text('Завершить группу?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(group.isActive, isTrue);

    await tester.tap(find.text('Завершить группу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Завершить группу'));
    await tester.pumpAndSettle();

    expect(group.endedByOrganizer, isTrue);
    expect(find.text('Завершена организатором'), findsOneWidget);
    expect(find.text('Завершить группу'), findsNothing);
    expect(find.text('Покинуть группу'), findsNothing);
    expect(find.text('Открыть карту'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showGroupInviteOptions(
                context: context,
                group: group,
              ),
              child: const Text('Пригласить'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Пригласить'));
    await tester.pumpAndSettle();
    expect(
      find.text('В завершённую группу нельзя приглашать участников'),
      findsNWidgets(2),
    );
    expect(find.text('QR-код приглашения'), findsNothing);
  });

  testWidgets('participant can leave and cannot end the group', (tester) async {
    final group = buildGroup(inviteeId: currentDemoUserId, inviteeName: 'Вы');
    group.members.last.status = MembershipStatus.active;

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: group)));

    expect(find.text('Покинуть группу'), findsOneWidget);
    expect(find.text('Завершить группу'), findsNothing);
    expect(find.text('Открыть карту'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('participant of an ended group sees no active actions', (
    tester,
  ) async {
    final group = buildGroup(
      inviteeId: currentDemoUserId,
      inviteeName: 'Вы',
      active: false,
    );
    group.members.last.status = MembershipStatus.active;

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: group)));

    expect(find.textContaining('Истекла'), findsOneWidget);
    expect(find.text('Открыть карту'), findsNothing);
    expect(find.text('Покинуть группу'), findsNothing);
    expect(find.text('Завершить группу'), findsNothing);
  });

  testWidgets('already ended group has no end action', (tester) async {
    final group = buildGroup(
      inviteeId: currentDemoUserId,
      inviteeName: 'Вы',
      inviteeIsOrganizer: true,
      active: false,
    );

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: group)));

    expect(find.textContaining('Истекла'), findsOneWidget);
    expect(find.text('Завершить группу'), findsNothing);
    expect(find.text('Покинуть группу'), findsNothing);
    expect(find.text('Открыть карту'), findsNothing);
  });

  testWidgets('badge follows the current user and state changes', (
    tester,
  ) async {
    const firstUser = 'mikhail-ivanov';
    const secondUser = 'elena-kuznetsova';
    final store = GroupsStore.instance;
    final firstActive = buildGroup(
      inviteeId: firstUser,
      inviteeName: 'Михаил Иванов',
    );
    final firstExtra = buildGroup(
      inviteeId: firstUser,
      inviteeName: 'Михаил Иванов',
    );
    final firstEnded = buildGroup(
      inviteeId: firstUser,
      inviteeName: 'Михаил Иванов',
      active: false,
    );
    final secondActive = buildGroup(
      inviteeId: secondUser,
      inviteeName: 'Елена Кузнецова',
    );
    store
      ..addGroup(firstActive)
      ..addGroup(firstExtra)
      ..addGroup(firstEnded)
      ..addGroup(secondActive);
    store.syncInvitations(firstActive);
    store.syncInvitations(firstExtra);
    store.syncInvitations(secondActive);
    store.invitations.add(
      GroupInvitation(
        id: 'badge-ended-$sequence',
        groupId: firstEnded.id,
        inviterName: 'Мария Ковалёва',
        inviteeId: firstUser,
        inviteeName: 'Михаил Иванов',
        source: InvitationSource.demoList,
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
      ),
    );

    currentDemoUserId = firstUser;
    expect(store.pendingInvitationCountFor(firstUser), 2);
    await pumpHome(tester);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99+'), findsNothing);

    await tester.tap(find.byIcon(Icons.switch_account_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Елена Кузнецова'));
    await tester.pumpAndSettle();
    expect(currentDemoUserId, secondUser);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNothing);

    final accepted = store.incomingPending.firstWhere(
      (invitation) => invitation.groupId == secondActive.id,
    );
    store.acceptInvitation(accepted);
    await pumpHome(tester);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    currentDemoUserId = firstUser;
    await pumpHome(tester);
    expect(find.text('2'), findsOneWidget);
    currentDemoUserId = 'organizer';
    expect(store.endGroup(firstActive), isTrue);
    currentDemoUserId = firstUser;
    await pumpHome(tester);
    expect(store.pendingInvitationCountFor(firstUser), 1);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('badge is hidden when there are no pending invitations', (
    tester,
  ) async {
    currentDemoUserId = 'dmitry-petrov';
    await pumpHome(tester);
    expect(find.text('Присоединиться по приглашению'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('99+'), findsNothing);
  });
}
