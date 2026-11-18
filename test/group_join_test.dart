import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/join_group_confirmation_screen.dart';
import 'package:geo_groups/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    currentDemoUserId = defaultDemoUserId;
  });

  GeoGroup addGroup({
    required String id,
    required DateTime startsAt,
    DateTime? endsAt,
    bool ended = false,
  }) {
    final group = GeoGroup(
      id: id,
      name: 'Группа $id',
      createdAt: DateTime.now(),
      startsAt: startsAt,
      endsAt: endsAt,
      qrInviteToken: 'token-$id',
      members: [
        GroupMember(
          id: 'organizer-$id',
          name: 'Организатор',
          role: MemberRole.organizer,
        ),
      ],
    );
    if (ended) {
      group.endedByOrganizer = true;
      group.endedAt = DateTime.now();
    }
    GroupsStore.instance.addGroup(group);
    return group;
  }

  GroupInvitation invite(GeoGroup group, String userId) {
    final invitation = GroupInvitation(
      id: 'invite-$userId-${group.id}',
      groupId: group.id,
      inviterName: 'Организатор',
      inviteeId: userId,
      inviteeName: 'Старое имя',
      source: InvitationSource.demoList,
      status: InvitationStatus.pending,
      createdAt: DateTime.now(),
    );
    GroupsStore.instance.invitations.add(invitation);
    return invitation;
  }

  test(
    'joining stores the chosen name and avatar and keeps the profile',
    () async {
      SharedPreferences.setMockInitialValues({
        'user_profile.join-user.display_name': 'Профиль',
        'user_profile.join-user.avatar_id': 'amber_star',
      });
      final profiles = UserProfileStore();
      final now = DateTime.now();
      final group = addGroup(
        id: 'join-snapshot',
        startsAt: now.add(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 2)),
      );
      const userId = 'join-user';
      final invitation = invite(group, userId);
      currentDemoUserId = userId;

      final result = GroupsStore.instance.acceptInvitation(
        invitation,
        displayName: '  В походе  ',
        avatarId: 'blue_face',
      );

      expect(result, InvitationAcceptResult.joined);
      final members = group.members.where((member) => member.id == userId);
      expect(members, hasLength(1));
      expect(members.single.name, 'В походе');
      expect(members.single.avatarId, 'blue_face');
      expect(members.single.status, MembershipStatus.active);
      expect(group.isUpcoming, isTrue);
      expect(group.canUseMap, isFalse);
      final profile = await profiles.loadProfile(
        userId: userId,
        fallbackName: 'Другое',
      );
      expect(profile.displayName, 'Профиль');
      expect(profile.avatarId, 'amber_star');
    },
  );

  test('joining again does not create a second member', () {
    final now = DateTime.now();
    final group = addGroup(
      id: 'join-twice',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    const userId = 'join-twice-user';
    final invitation = invite(group, userId);
    final store = GroupsStore.instance;
    expect(
      store.acceptInvitation(
        invitation,
        displayName: 'Первый',
        avatarId: 'green_hiking',
      ),
      InvitationAcceptResult.joined,
    );

    final again = GroupInvitation(
      id: 'invite-again-${group.id}',
      groupId: group.id,
      inviterName: 'Организатор',
      inviteeId: userId,
      inviteeName: 'Другое',
      source: InvitationSource.qrCode,
      status: InvitationStatus.pending,
      createdAt: DateTime.now(),
    );
    store.invitations.add(again);
    expect(
      store.acceptInvitation(
        again,
        displayName: 'Второй',
        avatarId: 'red_favorite',
      ),
      InvitationAcceptResult.alreadyMember,
    );
    final members = group.members.where((member) => member.id == userId);
    expect(members, hasLength(1));
    expect(members.single.name, 'Первый');
    expect(members.single.avatarId, 'green_hiking');
  });

  test('a finished group rejects joining', () {
    final group = addGroup(
      id: 'join-finished',
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      endsAt: DateTime.now().subtract(const Duration(hours: 1)),
      ended: true,
    );
    const userId = 'join-finished-user';
    final invitation = invite(group, userId);
    final before = group.members.length;

    expect(
      GroupsStore.instance.acceptInvitation(
        invitation,
        displayName: 'Поздний',
        avatarId: 'purple_pets',
      ),
      InvitationAcceptResult.groupEnded,
    );
    expect(group.members, hasLength(before));
    expect(invitation.status, InvitationStatus.pending);
    expect(
      GroupsStore.instance.joinFromQrPayload(
        buildGroupInvitePayload(group),
        displayName: 'Поздний',
        avatarId: 'purple_pets',
      ),
      InvitationAcceptResult.groupEnded,
    );
  });

  testWidgets('confirmation uses the profile and passes the edited identity', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = addGroup(
      id: 'join-screen',
      startsAt: now.add(const Duration(days: 2)),
      endsAt: now.add(const Duration(days: 3)),
    );
    final repository = _MemoryProfiles()
      ..profiles['screen-user'] = const UserProfile(
        userId: 'screen-user',
        displayName: 'Антон',
        avatarId: defaultAvatarId,
      );
    final joined = <(String, String)>[];
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => JoinGroupConfirmationScreen(
                        group: group,
                        userId: 'screen-user',
                        fallbackName: 'Запасное',
                        repository: repository,
                        onJoin: (name, avatarId) async {
                          joined.add((name, avatarId));
                          return InvitationAcceptResult.joined;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Открыть'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Вступление в группу'), findsOneWidget);
    expect(find.text('Группа join-screen'), findsOneWidget);
    expect(find.text('Запланирована'), findsOneWidget);
    expect(
      find.text(
        'Группа ещё не началась. Карта и обмен геопозицией станут доступны после её начала.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Антон',
    );
    expect(
      find.bySemanticsLabel('Выбран аватар $defaultAvatarId'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '  Новое имя  ');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Аватар blue_face'));
    await tester.pump();
    expect(find.bySemanticsLabel('Выбран аватар blue_face'), findsOneWidget);

    await tester.tap(find.text('Вступить в группу'));
    await tester.pumpAndSettle();

    expect(joined, [('Новое имя', 'blue_face')]);
    expect(find.text('Вступление в группу'), findsNothing);
    expect(repository.saves, isEmpty);
  });

  testWidgets('an empty name cannot confirm joining', (tester) async {
    final repository = _MemoryProfiles()
      ..profiles['empty-user'] = const UserProfile(
        userId: 'empty-user',
        displayName: '   ',
        avatarId: defaultAvatarId,
      );
    var joins = 0;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: JoinGroupConfirmationScreen(
          group: addGroup(
            id: 'join-empty',
            startsAt: DateTime.now().subtract(const Duration(hours: 1)),
            endsAt: DateTime.now().add(const Duration(hours: 3)),
          ),
          userId: 'empty-user',
          fallbackName: 'Запасное',
          repository: repository,
          onJoin: (name, avatarId) async {
            joins += 1;
            return InvitationAcceptResult.joined;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Введите имя'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Вступить в группу'),
          )
          .onPressed,
      isNull,
    );
    expect(joins, 0);

    await tester.enterText(find.byType(TextField), 'Имя');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Вступить в группу'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.text('Введите имя'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Вступить в группу'),
          )
          .onPressed,
      isNull,
    );
    expect(joins, 0);
  });

  test('a member without an avatar id uses the default avatar', () {
    final member = GroupMember(id: 'legacy', name: 'Старый', avatarId: '');

    expect(member.displayAvatarId, defaultAvatarId);
  });

  testWidgets('group roster shows the avatar chosen at joining', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = addGroup(
      id: 'roster-avatar',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    const userId = 'roster-user';
    final invitation = invite(group, userId);
    expect(
      GroupsStore.instance.acceptInvitation(
        invitation,
        displayName: 'В походе',
        avatarId: 'blue_face',
      ),
      InvitationAcceptResult.joined,
    );
    group.members.add(
      GroupMember(id: 'legacy-user', name: 'Старый', avatarId: ''),
    );
    currentDemoUserId = 'organizer-${group.id}';

    await tester.pumpWidget(MaterialApp(home: GroupScreen(group: group)));

    final avatars = tester
        .widgetList<ProfileAvatar>(find.byType(ProfileAvatar))
        .toList();
    expect(
      avatars.map((avatar) => (avatar.displayName, avatar.avatarId)),
      [
        ('В походе', 'blue_face'),
        ('Старый', defaultAvatarId),
      ],
    );
    expect(find.text(memberInitials('В походе')), findsNothing);
    expect(find.text(memberInitials('Старый')), findsNothing);
    expect(find.byIcon(Icons.face), findsOneWidget);
  });
}

class _MemoryProfiles implements UserProfileRepository {
  final Map<String, UserProfile> profiles = {};
  final List<UserProfile> saves = [];

  @override
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  }) async {
    return profiles[userId] ??
        UserProfile(
          userId: userId,
          displayName: fallbackName,
          avatarId: defaultAvatarId,
        );
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saves.add(profile);
  }
}
