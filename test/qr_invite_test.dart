import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/invite_source_sheet.dart';
import 'package:geo_groups/qr_invite_screen.dart';

void main() {
  setUp(() {
    currentDemoUserId = defaultDemoUserId;
  });

  GeoGroup organizerGroup({
    required String id,
    required String name,
    required DateTime? endsAt,
    String token = 'token-1',
  }) {
    return GeoGroup(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      endsAt: endsAt,
      createdByUserId: currentDemoUserId,
      qrInviteToken: token,
      members: [
        GroupMember(
          id: currentDemoUserId,
          name: currentDemoUser.name,
          role: MemberRole.organizer,
        ),
      ],
    );
  }

  test('payload uses the stable invite token', () {
    final group = organizerGroup(
      id: 'walk',
      name: 'Прогулка',
      endsAt: DateTime.now().add(const Duration(days: 1)),
      token: 'token-walk',
    );
    expect(
      buildGroupInvitePayload(group),
      'geo-groups://join?groupId=walk&inviteToken=token-walk',
    );
    expect(group.qrInviteToken, 'token-walk');

    group.updateDetails(
      name: 'Новое имя',
      endsAt: group.endsAt,
      members: List<GroupMember>.of(group.members),
    );
    expect(group.qrInviteToken, 'token-walk');
    expect(group.name, 'Новое имя');
  });

  test('personal invitations still follow the switched demo user', () {
    final group = GeoGroup(
      id: 'switch-check',
      name: 'Проверка приглашения',
      createdAt: DateTime.now(),
      endsAt: DateTime.now().add(const Duration(days: 1)),
      createdByUserId: defaultDemoUserId,
      members: [
        GroupMember(
          id: defaultDemoUserId,
          name: 'Вы',
          role: MemberRole.organizer,
        ),
        GroupMember(
          id: 'anna-smirnova',
          name: 'Анна Смирнова',
          status: MembershipStatus.invited,
        ),
      ],
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);

    expect(
      GroupsStore.instance.incomingPending.any(
        (invitation) => invitation.groupId == group.id,
      ),
      isFalse,
    );

    currentDemoUserId = 'anna-smirnova';
    final incoming = GroupsStore.instance.incomingPending
        .where((invitation) => invitation.groupId == group.id)
        .toList();
    expect(incoming, hasLength(1));
    expect(incoming.single.inviteeId, 'anna-smirnova');
    expect(incoming.single.status, InvitationStatus.pending);
    expect(incoming.single.source, InvitationSource.demoList);

    GroupsStore.instance.declineInvitation(incoming.single);
    expect(
      GroupsStore.instance.incomingPending.any(
        (invitation) => invitation.groupId == group.id,
      ),
      isFalse,
    );
    expect(group.members.any((member) => member.id == 'anna-smirnova'), isFalse);
    expect(group.qrInviteToken, 'qr-switch-check');
  });

  test('demo groups keep a default token without resetting members', () {
    final group = GeoGroup(
      id: 'picnic',
      name: 'Пикник в парке',
      createdAt: DateTime.now(),
      endsAt: DateTime.now().add(const Duration(hours: 3)),
      members: [
        GroupMember(id: 'maria', name: 'Мария'),
      ],
    );
    expect(group.qrInviteToken, 'qr-picnic');
    expect(group.members.single.name, 'Мария');
  });

  testWidgets('organizer of an active group sees the QR and can close it', (
    tester,
  ) async {
    final endsAt = DateTime(2026, 11, 20, 18, 30);
    final group = organizerGroup(
      id: 'active-qr',
      name: 'Тестовая встреча',
      endsAt: endsAt,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => QrInviteScreen(group: group),
                  ),
                );
              },
              child: const Text('Открыть код'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть код'));
    await tester.pumpAndSettle();

    expect(find.text('QR-код приглашения'), findsOneWidget);
    expect(find.text('Тестовая встреча'), findsOneWidget);
    expect(find.text('До ${formatGroupDateTime(endsAt)}'), findsOneWidget);
    expect(
      find.text(
        'Покажите этот код человеку, которого хотите пригласить в группу.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text(
        'Код не передаёт вашу геолокацию. Присоединение к группе потребует отдельного подтверждения.',
      ),
      200,
    );
    expect(
      find.text(
        'Код не передаёт вашу геолокацию. Присоединение к группе потребует отдельного подтверждения.',
      ),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsOneWidget);
    final payload = buildGroupInvitePayload(group);
    expect(payload, contains('groupId=active-qr'));
    expect(payload, contains('inviteToken=token-1'));
    expect(payload.contains('Мария'), isFalse);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('QR-код приглашения'), findsNothing);
  });

  testWidgets('unsaved group does not open a QR code', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showInviteParticipants(
                context: context,
                excludedIds: const <String>{},
                initiallySelectedIds: const <String>{},
              ),
              child: const Text('Пригласить'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Пригласить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR-код группы'));
    await tester.pumpAndSettle();

    expect(
      find.text('Сначала сохраните группу, чтобы создать QR-код приглашения.'),
      findsOneWidget,
    );
    expect(find.text('QR-код приглашения'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('ended group does not open a QR code', (tester) async {
    final group = organizerGroup(
      id: 'ended-qr',
      name: 'Кино',
      endsAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showInviteParticipants(
                context: context,
                excludedIds: const <String>{},
                initiallySelectedIds: const <String>{},
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
      findsOneWidget,
    );
    expect(find.text('QR-код приглашения'), findsNothing);

    await tester.tap(find.text('QR-код группы'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('QR-код приглашения'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });
}
