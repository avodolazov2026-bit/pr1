import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    DateTime? startsAt,
    String token = 'token-1',
  }) {
    final now = DateTime.now();
    return GeoGroup(
      id: id,
      name: name,
      createdAt: now,
      startsAt:
          startsAt ??
          (endsAt != null && !endsAt.isAfter(now)
              ? endsAt.subtract(const Duration(hours: 1))
              : now.subtract(const Duration(minutes: 5))),
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
      startsAt: group.startsAt,
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
      startsAt: DateTime.now().subtract(const Duration(minutes: 5)),
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
    expect(
      group.members.any((member) => member.id == 'anna-smirnova'),
      isFalse,
    );
    expect(group.qrInviteToken, 'qr-switch-check');
  });

  test('demo groups keep a default token without resetting members', () {
    final group = GeoGroup(
      id: 'picnic',
      name: 'Пикник в парке',
      createdAt: DateTime.now(),
      startsAt: DateTime.now().subtract(const Duration(minutes: 5)),
      endsAt: DateTime.now().add(const Duration(hours: 3)),
      members: [GroupMember(id: 'maria', name: 'Мария')],
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
    GroupsStore.instance.addGroup(group);

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
    await tester.scrollUntilVisible(
      find.text('До ${formatGroupDateTime(endsAt)}'),
      200,
    );
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
    expect(find.text('Скопировать код приглашения'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final payload = buildGroupInvitePayload(group);
    expect(payload, contains('groupId=active-qr'));
    expect(payload, contains('inviteToken=token-1'));
    expect(payload.contains('Мария'), isFalse);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          copied = arguments['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.tap(find.text('Скопировать код приглашения'));
    await tester.pump();
    expect(copied, payload);
    expect(find.text('Код приглашения скопирован'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('QR-код приглашения'), findsNothing);
  });

  testWidgets('copy button stays hidden when the group is not active', (
    tester,
  ) async {
    final expired = organizerGroup(
      id: 'expired-qr',
      name: 'Завершённая встреча',
      endsAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final ended = organizerGroup(
      id: 'ended-qr-copy',
      name: 'Остановленная встреча',
      endsAt: DateTime.now().add(const Duration(days: 1)),
    );
    ended.endedByOrganizer = true;
    final foreign = organizerGroup(
      id: 'foreign-qr',
      name: 'Чужая встреча',
      endsAt: DateTime.now().add(const Duration(days: 1)),
    );
    GroupsStore.instance
      ..addGroup(expired)
      ..addGroup(ended)
      ..addGroup(foreign);

    await tester.pumpWidget(MaterialApp(home: QrInviteScreen(group: expired)));
    expect(find.text('Скопировать код приглашения'), findsNothing);

    await tester.pumpWidget(MaterialApp(home: QrInviteScreen(group: ended)));
    expect(find.text('Скопировать код приглашения'), findsNothing);

    currentDemoUserId = 'anna-smirnova';
    await tester.pumpWidget(MaterialApp(home: QrInviteScreen(group: foreign)));
    expect(find.text('Скопировать код приглашения'), findsNothing);
  });

  testWidgets('unsaved group does not show the copy button', (tester) async {
    final group = organizerGroup(
      id: 'unsaved-copy',
      name: 'Черновик',
      endsAt: DateTime.now().add(const Duration(days: 1)),
      token: 'draft-token',
    );

    await tester.pumpWidget(MaterialApp(home: QrInviteScreen(group: group)));

    expect(group.isActive, isTrue);
    expect(group.qrInviteToken, isNotEmpty);
    expect(group.currentUserIsActiveOrganizer, isTrue);
    expect(GroupsStore.instance.groupById(group.id), isNull);
    expect(find.text('Скопировать код приглашения'), findsNothing);
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
      findsNWidgets(2),
    );
    expect(find.text('QR-код приглашения'), findsNothing);

    await tester.tap(find.text('QR-код группы'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('QR-код приглашения'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('share link is available for saved active and planned groups', (
    tester,
  ) async {
    final shared = <({String text, String subject})>[];
    Future<void> record({required String text, required String subject}) async {
      shared.add((text: text, subject: subject));
    }

    final active = organizerGroup(
      id: 'share-active',
      name: 'Прогулка',
      endsAt: DateTime.now().add(const Duration(hours: 3)),
      token: 'token-active',
    );
    final invitesBefore = GroupsStore.instance.invitations.length;
    final membersBefore = active.members.length;

    await _openInviteSheet(tester, group: active, shareInvite: record);
    expect(find.text('Поделиться ссылкой'), findsOneWidget);
    expect(
      find.text('Отправить приглашение через другое приложение'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Поделиться ссылкой'))
          .onTap,
      isNotNull,
    );

    await tester.tap(find.text('Поделиться ссылкой'));
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    expect(shared.single.subject, 'Приглашение в Geo Groups');
    expect(
      shared.single.text,
      'Присоединяйтесь к группе «Прогулка» в Geo Groups:\n'
      '${buildGroupInvitePayload(active)}',
    );
    expect(find.text('Пригласить участников'), findsNothing);
    expect(GroupsStore.instance.invitations, hasLength(invitesBefore));
    expect(active.members, hasLength(membersBefore));
    expect(active.qrInviteToken, 'token-active');

    final planned = organizerGroup(
      id: 'share-planned',
      name: 'Завтра',
      startsAt: DateTime.now().add(const Duration(days: 1)),
      endsAt: DateTime.now().add(const Duration(days: 2)),
      token: 'token-planned',
    );
    expect(planned.isUpcoming, isTrue);

    await _openInviteSheet(tester, group: planned, shareInvite: record);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Поделиться ссылкой'))
          .onTap,
      isNotNull,
    );
    expect(
      find.text('Отправить приглашение через другое приложение'),
      findsOneWidget,
    );
  });

  testWidgets('share link is disabled for a finished group', (tester) async {
    final group = organizerGroup(
      id: 'share-finished',
      name: 'Кино',
      endsAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    var shares = 0;

    await _openInviteSheet(
      tester,
      group: group,
      shareInvite: ({required String text, required String subject}) async {
        shares += 1;
      },
    );

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Поделиться ссылкой'),
    );
    expect(tile.onTap, isNull);
    expect(
      find.text('В завершённую группу нельзя приглашать участников'),
      findsWidgets,
    );

    await tester.tap(find.text('Поделиться ссылкой'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(shares, 0);
    expect(find.text('Ссылка-приглашение'), findsNothing);
  });
}

Future<void> _openInviteSheet(
  WidgetTester tester, {
  required GeoGroup group,
  required ShareGroupInvite shareInvite,
}) async {
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
              shareInvite: shareInvite,
            ),
            child: const Text('Пригласить'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Пригласить'));
  await tester.pumpAndSettle();
}
