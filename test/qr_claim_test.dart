import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/invitations_screen.dart';

void main() {
  const inviteeId = 'mikhail-ivanov';

  setUp(() {
    currentDemoUserId = inviteeId;
  });

  GeoGroup addGroup({
    required String id,
    String token = 'token-ok',
    bool active = true,
    bool endedByOrganizer = false,
    String organizerId = 'maria-organizer',
  }) {
    final now = DateTime.now();
    final group = GeoGroup(
      id: id,
      name: 'Встреча $id',
      createdAt: now,
      startsAt: active
          ? now.subtract(const Duration(minutes: 5))
          : now.subtract(const Duration(hours: 4)),
      endsAt: active
          ? now.add(const Duration(days: 2))
          : now.subtract(const Duration(hours: 3)),
      qrInviteToken: token,
      members: [
        GroupMember(
          id: organizerId,
          name: 'Мария Ковалёва',
          role: MemberRole.organizer,
        ),
        GroupMember(id: 'sergey', name: 'Сергей', distanceMeters: 120),
      ],
    );
    if (endedByOrganizer) {
      group.endedByOrganizer = true;
    }
    GroupsStore.instance.addGroup(group);
    return group;
  }

  int pendingCount(String groupId) {
    return GroupsStore.instance.invitations
        .where(
          (invitation) =>
              invitation.groupId == groupId &&
              invitation.inviteeId == currentDemoUserId &&
              invitation.status == InvitationStatus.pending,
        )
        .length;
  }

  test('parser matches the payload builder and rejects other strings', () {
    final group = GeoGroup(
      id: 'walk id',
      name: 'Прогулка',
      createdAt: DateTime.now(),
      startsAt: DateTime.now().subtract(const Duration(minutes: 5)),
      endsAt: DateTime.now().add(const Duration(days: 1)),
      qrInviteToken: 'token value',
      members: [
        GroupMember(
          id: 'maria-organizer',
          name: 'Мария',
          role: MemberRole.organizer,
        ),
      ],
    );
    final payload = buildGroupInvitePayload(group);
    final parsed = parseGroupInvitePayload('  $payload  ');
    expect(parsed?.groupId, 'walk id');
    expect(parsed?.inviteToken, 'token value');
    expect(payload.contains('Сергей'), isFalse);
    expect(payload.contains('120'), isFalse);
    expect(parseGroupInvitePayload(''), isNull);
    expect(parseGroupInvitePayload('не приглашение'), isNull);
    expect(
      parseGroupInvitePayload(
        'https://go.geogroups.app/join?groupId=a&inviteToken=b',
      ),
      isNull,
    );
    expect(parseGroupInvitePayload('geo-groups://join?groupId=walk'), isNull);
  });

  test(
    'valid payload creates one pending invitation and updates the badge',
    () {
      final group = addGroup(id: 'qr-valid');
      final store = GroupsStore.instance;
      final before = store.pendingInvitationCountFor(inviteeId);

      final result = store.claimQrInvitation(buildGroupInvitePayload(group));

      expect(result, QrInviteClaimResult.added);
      expect(pendingCount(group.id), 1);
      expect(store.pendingInvitationCountFor(inviteeId), before + 1);
      final invitation = store.incomingPending.firstWhere(
        (item) => item.groupId == group.id,
      );
      expect(invitation.status, InvitationStatus.pending);
      expect(invitation.source, InvitationSource.qrCode);
      expect(invitation.inviteeId, inviteeId);
      expect(store.myGroups.any((item) => item.id == group.id), isFalse);

      expect(
        store.claimQrInvitation(buildGroupInvitePayload(group)),
        QrInviteClaimResult.alreadyPending,
      );
      expect(pendingCount(group.id), 1);
      expect(store.pendingInvitationCountFor(inviteeId), before + 1);

      store.acceptInvitation(invitation);
      expect(store.pendingInvitationCountFor(inviteeId), before);
      expect(
        store.claimQrInvitation(buildGroupInvitePayload(group)),
        QrInviteClaimResult.alreadyMember,
      );
      expect(pendingCount(group.id), 0);
    },
  );

  test(
    'declined QR invite can be claimed again without a duplicate pending',
    () {
      final group = addGroup(id: 'qr-declined');
      final store = GroupsStore.instance;
      final before = store.pendingInvitationCountFor(inviteeId);
      expect(
        store.claimQrInvitation(buildGroupInvitePayload(group)),
        QrInviteClaimResult.added,
      );
      final invitation = store.incomingPending.firstWhere(
        (item) => item.groupId == group.id,
      );
      store.declineInvitation(invitation);
      expect(store.pendingInvitationCountFor(inviteeId), before);

      expect(
        store.claimQrInvitation(buildGroupInvitePayload(group)),
        QrInviteClaimResult.added,
      );
      expect(pendingCount(group.id), 1);
      expect(invitation.status, InvitationStatus.declined);
      expect(store.pendingInvitationCountFor(inviteeId), before + 1);
    },
  );

  test('invalid payloads do not create invitations or change the badge', () {
    final group = addGroup(id: 'qr-invalid', token: 'real-token');
    final inactive = addGroup(id: 'qr-inactive', active: false);
    final ended = addGroup(id: 'qr-ended', endedByOrganizer: true);
    final store = GroupsStore.instance;
    final beforeInvites = store.invitations.length;
    final beforeBadge = store.pendingInvitationCountFor(inviteeId);

    expect(store.claimQrInvitation('   '), QrInviteClaimResult.empty);
    expect(
      store.claimQrInvitation('geo-groups://join?groupId=&inviteToken='),
      QrInviteClaimResult.unrecognized,
    );
    expect(
      store.claimQrInvitation(
        'geo-groups://join?groupId=missing-group&inviteToken=real-token',
      ),
      QrInviteClaimResult.unavailable,
    );
    expect(
      store.claimQrInvitation(
        buildGroupInvitePayload(group)
            .replaceFirst('real-token', 'other-token'),
      ),
      QrInviteClaimResult.invalidToken,
    );
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(inactive)),
      QrInviteClaimResult.inactive,
    );
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(ended)),
      QrInviteClaimResult.inactive,
    );

    expect(store.invitations.length, beforeInvites);
    expect(store.pendingInvitationCountFor(inviteeId), beforeBadge);
    expect(pendingCount(group.id), 0);
  });

  test('organizer and active member do not receive another invitation', () {
    final group = addGroup(id: 'qr-self', organizerId: inviteeId);
    final store = GroupsStore.instance;
    final before = store.invitations.length;
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(group)),
      QrInviteClaimResult.organizer,
    );
    expect(store.invitations.length, before);

    currentDemoUserId = 'sergey';
    expect(
      store.claimQrInvitation(buildGroupInvitePayload(group)),
      QrInviteClaimResult.alreadyMember,
    );
    expect(store.invitations.length, before);
  });

  testWidgets(
    'invitations screen adds a standard card and keeps the group private',
    (tester) async {
      currentDemoUserId = 'elena-kuznetsova';
      final group = addGroup(id: 'qr-screen');
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: InvitationsScreen()));

      expect(find.text('Получить приглашение по коду'), findsOneWidget);
      expect(find.text('Сканировать QR'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        buildGroupInvitePayload(group),
      );
      await tester.tap(find.text('Обработать приглашение'));
      await tester.pump();

      expect(find.text('Приглашение добавлено в список.'), findsOneWidget);
      expect(find.text('Встреча qr-screen'), findsOneWidget);
      expect(find.text('Приглашение по QR-коду'), findsOneWidget);
      expect(find.text('Сергей'), findsNothing);
      expect(find.textContaining('120'), findsNothing);
      expect(find.text('Открыть карту'), findsNothing);
      expect(find.byType(InvitationsScreen), findsOneWidget);
      expect(
        GroupsStore.instance.myGroups.any((item) => item.id == group.id),
        isFalse,
      );

      await tester.enterText(
        find.byType(TextField),
        buildGroupInvitePayload(group),
      );
      await tester.tap(find.text('Обработать приглашение'));
      await tester.pump();
      expect(find.text('Это приглашение уже есть в списке'), findsOneWidget);
      expect(pendingCount(group.id), 1);

      await tester.tap(find.text('Присоединиться'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Присоединиться'));
      await tester.pumpAndSettle();
      expect(find.text('Встреча qr-screen'), findsNothing);
      expect(pendingCount(group.id), 0);
      expect(
        GroupsStore.instance.myGroups.any((item) => item.id == group.id),
        isTrue,
      );
    },
  );

  testWidgets('paste fills the field and does not create an invitation', (
    tester,
  ) async {
    currentDemoUserId = 'dmitry-petrov';
    final group = addGroup(id: 'qr-paste');
    final payload = buildGroupInvitePayload(group);
    final store = GroupsStore.instance;
    final invitesBefore = store.invitations.length;
    final badgeBefore = store.pendingInvitationCountFor(currentDemoUserId);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': '  $payload  '};
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

    await tester.pumpWidget(const MaterialApp(home: InvitationsScreen()));
    expect(find.text('Вставить из буфера'), findsOneWidget);
    await tester.tap(find.text('Вставить из буфера'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      payload,
    );
    expect(store.invitations.length, invitesBefore);
    expect(store.pendingInvitationCountFor(currentDemoUserId), badgeBefore);
    expect(find.text('Встреча qr-paste'), findsNothing);
    expect(pendingCount(group.id), 0);

    await tester.tap(find.text('Обработать приглашение'));
    await tester.pump();
    expect(find.text('Приглашение добавлено в список.'), findsOneWidget);
    expect(find.text('Встреча qr-paste'), findsOneWidget);
    expect(find.text('Приглашение по QR-коду'), findsOneWidget);
    expect(pendingCount(group.id), 1);
    expect(store.pendingInvitationCountFor('dmitry-petrov'), badgeBefore + 1);
  });

  testWidgets('empty or unreadable clipboard does not change the field', (
    tester,
  ) async {
    currentDemoUserId = 'olga-sokolova';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': '   '};
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

    await tester.pumpWidget(const MaterialApp(home: InvitationsScreen()));
    await tester.tap(find.text('Вставить из буфера'));
    await tester.pump();
    expect(find.text('В буфере обмена нет кода приглашения'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          throw PlatformException(code: 'clipboard_error');
        }
        return null;
      },
    );
    await tester.tap(find.text('Вставить из буфера'));
    await tester.pump();
    expect(find.text('Не удалось прочитать буфер обмена'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });
}
