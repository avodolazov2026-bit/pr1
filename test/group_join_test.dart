import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/join_group_confirmation_screen.dart';
import 'package:geo_groups/user_profile.dart';

import 'fake_location_device.dart';

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
                        locationProvider: const _SilentJoinLocation(),
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

  testWidgets('joining continues when location access fails', (tester) async {
    final denied = FakeLocationDevice(
      permission: LocationAccess.denied,
      afterRequest: LocationAccess.denied,
    );
    await _confirmJoin(tester, id: 'join-denied', device: denied);
    expect(denied.requests, 1);

    final forever = FakeLocationDevice(
      permission: LocationAccess.deniedForever,
    );
    await _confirmJoin(tester, id: 'join-forever', device: forever);
    expect(forever.requests, 0);

    final broken = FakeLocationDevice(serviceError: StateError('offline'));
    await _confirmJoin(tester, id: 'join-broken', device: broken);
    expect(broken.requests, 0);
  });

  testWidgets('an existing location grant is not requested again', (
    tester,
  ) async {
    final device = FakeLocationDevice(permission: LocationAccess.granted);
    await _confirmJoin(tester, id: 'join-granted', device: device);
    expect(device.checks, greaterThan(0));
    expect(device.requests, 0);
  });

  testWidgets('successful join does not wait for the location prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<LocationAccess>();
    final device = FakeLocationDevice(
      permission: LocationAccess.denied,
      permissionRequestGate: gate,
    );
    const userId = 'join-prompt-user';
    final now = DateTime.now();
    final group = GeoGroup(
      id: 'join-prompt',
      name: 'Группа join-prompt',
      createdAt: now,
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      qrInviteToken: 'token-join-prompt',
      members: [
        GroupMember(
          id: 'organizer-join-prompt',
          name: 'Организатор',
          role: MemberRole.organizer,
        ),
      ],
    );
    GroupsStore.instance.addGroup(group);
    final repository = _MemoryProfiles()
      ..profiles[userId] = const UserProfile(
        userId: userId,
        displayName: 'Антон',
        avatarId: defaultAvatarId,
      );
    bool? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .push<bool>(
                        PageRouteBuilder<bool>(
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                          pageBuilder: (context, _, _) {
                            return JoinGroupConfirmationScreen(
                              group: group,
                              userId: userId,
                              fallbackName: 'Запасное',
                              repository: repository,
                              locationProvider: DeviceLocationProvider(
                                device: device,
                              ),
                              onJoin: (name, avatarId) async {
                                return InvitationAcceptResult.joined;
                              },
                            );
                          },
                        ),
                      )
                      .then((value) {
                        popped = value;
                      });
                },
                child: const Text('Открыть'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Вступление в группу'), findsOneWidget);

    await tester.tap(find.text('Вступить в группу'));
    await tester.pump();

    expect(popped, isTrue);
    expect(find.text('Вступление в группу'), findsNothing);
    expect(device.requests, 1);
    expect(gate.isCompleted, isFalse);
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

    final joined = _avatarInRow(tester, 'В походе');
    expect(joined.displayName, 'В походе');
    expect(joined.avatarId, 'blue_face');
    expect(
      find.descendant(
        of: _memberRow('В походе'),
        matching: find.byIcon(Icons.face),
      ),
      findsOneWidget,
    );

    final legacy = _avatarInRow(tester, 'Старый');
    expect(legacy.displayName, 'Старый');
    expect(legacy.avatarId, defaultAvatarId);
    expect(
      find.descendant(
        of: _memberRow('Старый'),
        matching: find.byIcon(Icons.person),
      ),
      findsOneWidget,
    );

    expect(_memberRow('Организатор'), findsOneWidget);
    expect(find.byType(ProfileAvatar), findsNWidgets(3));
    expect(find.text(memberInitials('В походе')), findsNothing);
    expect(find.text(memberInitials('Старый')), findsNothing);
  });
}

Finder _memberRow(String name) {
  return find.byWidgetPredicate((widget) {
    if (widget is! ListTile) {
      return false;
    }
    final title = widget.title;
    return title is Text && title.data == name;
  });
}

ProfileAvatar _avatarInRow(WidgetTester tester, String name) {
  return tester.widget<ProfileAvatar>(
    find.descendant(
      of: _memberRow(name),
      matching: find.byType(ProfileAvatar),
    ),
  );
}

Future<void> _confirmJoin(
  WidgetTester tester, {
  required String id,
  required FakeLocationDevice device,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final now = DateTime.now();
  final group = GeoGroup(
    id: id,
    name: 'Группа $id',
    createdAt: now,
    startsAt: now.subtract(const Duration(hours: 1)),
    endsAt: now.add(const Duration(hours: 2)),
    qrInviteToken: 'token-$id',
    members: [
      GroupMember(
        id: 'organizer-$id',
        name: 'Организатор',
        role: MemberRole.organizer,
      ),
    ],
  );
  GroupsStore.instance.addGroup(group);
  final repository = _MemoryProfiles()
    ..profiles[id] = UserProfile(
      userId: id,
      displayName: 'Антон',
      avatarId: defaultAvatarId,
    );
  var joined = false;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(id),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => JoinGroupConfirmationScreen(
                      group: group,
                      userId: id,
                      fallbackName: 'Запасное',
                      repository: repository,
                      locationProvider: DeviceLocationProvider(device: device),
                      onJoin: (name, avatarId) async {
                        joined = true;
                        return InvitationAcceptResult.joined;
                      },
                    ),
                  ),
                );
              },
              child: Text('Открыть $id'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Открыть $id'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Вступить в группу'));
  await tester.pumpAndSettle();

  expect(joined, isTrue);
  expect(find.text('Вступление в группу'), findsNothing);
  expect(find.text('Не удалось вступить в группу'), findsNothing);
}

class _SilentJoinLocation implements CurrentLocationProvider {
  const _SilentJoinLocation();

  @override
  Future<LocationAccess> ensurePermissionForJoin() async {
    return LocationAccess.unavailable;
  }

  @override
  Future<GeoCoordinate?> currentPosition() async => null;
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
