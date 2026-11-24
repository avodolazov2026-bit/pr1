import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/auth_repository.dart';
import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_map_screen.dart';
import 'package:geo_groups/group_repository.dart';
import 'package:geo_groups/my_groups_screen.dart';
import 'package:geo_groups/phone_auth_screen.dart';

void main() {
  late List<GeoGroup> groupsBefore;
  late List<GroupInvitation> invitationsBefore;

  setUp(() {
    currentDemoUserId = defaultDemoUserId;
    groupsBefore = List<GeoGroup>.of(GroupsStore.instance.groups);
    invitationsBefore = List<GroupInvitation>.of(
      GroupsStore.instance.invitations,
    );
  });

  tearDown(() {
    currentDemoUserId = defaultDemoUserId;
    GroupsStore.instance.groups
      ..clear()
      ..addAll(groupsBefore);
    GroupsStore.instance.invitations
      ..clear()
      ..addAll(invitationsBefore);
  });

  test('creator is added once as the active organizer', () {
    final members = membersForNewGroup(
      creatorId: 'creator',
      creatorName: 'Ника',
      creatorAvatarId: 'amber_star',
      others: [
        GroupMember(
          id: 'creator',
          name: 'Дубль',
          status: MembershipStatus.invited,
        ),
        GroupMember(id: 'anna', name: 'Анна', status: MembershipStatus.invited),
        GroupMember(id: 'anna', name: 'Анна ещё раз'),
      ],
    );

    expect(members.map((member) => member.id), ['creator', 'anna']);
    expect(members.first.name, 'Ника');
    expect(members.first.avatarId, 'amber_star');
    expect(members.first.role, MemberRole.organizer);
    expect(members.first.status, MembershipStatus.active);
    expect(members[1].status, MembershipStatus.invited);
  });

  test('an empty creator avatar falls back to the default preset', () {
    final members = membersForNewGroup(
      creatorId: currentDemoUserId,
      creatorName: 'Вы',
      creatorAvatarId: '',
    );

    expect(members, hasLength(1));
    expect(members.single.avatarId, defaultAvatarId);
  });

  test('a newly created group is both mine and created', () {
    currentDemoUserId = 'listed-creator';
    final now = DateTime.now();
    final group = GeoGroup(
      id: 'listed-created-group',
      name: 'Свежая группа',
      createdAt: now,
      startsAt: now.subtract(const Duration(minutes: 5)),
      endsAt: now.add(const Duration(hours: 2)),
      createdByUserId: currentDemoUserId,
      members: membersForNewGroup(
        creatorId: currentDemoUserId,
        creatorName: 'Ника',
        creatorAvatarId: 'amber_star',
      ),
    );
    GroupsStore.instance.addGroup(group);

    expect(
      GroupsStore.instance.myGroups.where((item) => item.id == group.id),
      hasLength(1),
    );
    expect(
      GroupsStore.instance
          .createdGroups(GroupPeriod.week)
          .where((item) => item.id == group.id),
      hasLength(1),
    );
    expect(
      group.members.where((member) => member.id == currentDemoUserId),
      hasLength(1),
    );
  });

  testWidgets('the create form stores the current user as organizer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    currentDemoUserId = 'new-group-creator';
    SharedPreferences.setMockInitialValues({
      'user_profile.new-group-creator.display_name': 'Ника',
      'user_profile.new-group-creator.avatar_id': 'amber_star',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CreatedGroupsScreen(groups: LocalGroupRepository()),
      ),
    );
    await tester.tap(find.text('Создать группу').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Новый поход');
    await tester.pump();
    await tester.ensureVisible(find.text('Бессрочная группа'));
    await tester.tap(find.text('Бессрочная группа'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
    await tester.pumpAndSettle();

    final created = GroupsStore.instance.groups
        .where((group) => group.name == 'Новый поход')
        .toList();
    expect(created, hasLength(1));
    final group = created.single;
    expect(group.createdByUserId, 'new-group-creator');
    expect(group.members, hasLength(1));
    expect(group.members.single.id, currentDemoUserId);
    expect(group.members.single.name, 'Ника');
    expect(group.members.single.avatarId, 'amber_star');
    expect(group.members.single.role, MemberRole.organizer);
    expect(group.members.single.status, MembershipStatus.active);

    await tester.pumpWidget(const MaterialApp(home: MyGroupsScreen()));
    expect(find.text('Мои группы'), findsOneWidget);
    expect(find.text('Новый поход'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));
    expect(find.text('Созданные группы'), findsOneWidget);
    expect(find.text('Новый поход'), findsOneWidget);
  });

  testWidgets('a created organizer with a saved point is shown on the map', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = GeoGroup(
      id: 'created-organizer-map',
      name: 'Точка организатора',
      createdAt: now,
      startsAt: now.subtract(const Duration(minutes: 10)),
      endsAt: now.add(const Duration(hours: 2)),
      createdByUserId: currentDemoUserId,
      members: membersForNewGroup(
        creatorId: currentDemoUserId,
        creatorName: currentDemoUser.name,
        creatorAvatarId: defaultAvatarId,
        others: [
          GroupMember(
            id: currentDemoUserId,
            name: 'Дубль',
            status: MembershipStatus.invited,
          ),
        ],
      ),
      memberLocations: [
        GroupMemberLocation(
          memberId: currentDemoUserId,
          coordinate: GeoCoordinate(latitude: 59.93, longitude: 30.31),
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupMapScreen(locationProvider: _silentLocation, group: group),
      ),
    );
    await tester.pump();

    expect(group.members, hasLength(1));
    expect(_semantics('Ваше местоположение, организатор'), findsOneWidget);
    expect(
      find.descendant(
        of: _semantics('Ваше местоположение, организатор'),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
    final pin = tester.widget<Icon>(
      find.descendant(
        of: _semantics('Ваше местоположение, организатор'),
        matching: find.byIcon(Icons.location_on),
      ),
    );
    final scheme = Theme.of(
      tester.element(find.byType(GroupMapScreen)),
    ).colorScheme;
    expect(pin.color, scheme.primary);
    expect(pin.shadows?.any((shadow) => shadow.color == scheme.surface), isTrue);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('invite button is separate from opening the card', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = GeoGroup(
      id: 'card-invite',
      name: 'Карточка',
      createdAt: now,
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
      members: [
        GroupMember(
          id: currentDemoUserId,
          name: 'Вы',
          role: MemberRole.organizer,
        ),
      ],
    );
    var opened = 0;
    var invited = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupCard(group: group, onTap: () => opened += 1),
        ),
      ),
    );
    expect(find.text('Пригласить в группу'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupCard(
            group: group,
            onTap: () => opened += 1,
            onInvite: () => invited += 1,
          ),
        ),
      ),
    );
    expect(find.text('Пригласить в группу'), findsOneWidget);

    await tester.tap(find.text('Пригласить в группу'));
    await tester.pump();
    expect(invited, 1);
    expect(opened, 0);

    await tester.tap(find.text('Карточка'));
    await tester.pump();
    expect(opened, 1);
    expect(invited, 1);
  });

  testWidgets('an open organizer group shows invite', (tester) async {
    final now = DateTime.now();
    await _showCreatedGroups(tester, [
      _createdGroup(
        id: 'invite-active',
        name: 'Активная организатора',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
      ),
    ]);

    expect(find.text('Активная организатора'), findsOneWidget);
    expect(_inviteOn('Активная организатора'), findsOneWidget);
  });

  testWidgets('a planned organizer group shows invite', (tester) async {
    final now = DateTime.now();
    await _showCreatedGroups(tester, [
      _createdGroup(
        id: 'invite-upcoming',
        name: 'Будущая организатора',
        startsAt: now.add(const Duration(hours: 2)),
        endsAt: now.add(const Duration(hours: 4)),
      ),
    ]);

    expect(find.text('Будущая организатора'), findsOneWidget);
    expect(_inviteOn('Будущая организатора'), findsOneWidget);
  });

  testWidgets(
    'an organizer group without a link still shows invite',
    (tester) async {
      final now = DateTime.now();
      await _showCreatedGroups(tester, [
        _createdGroup(
          id: 'invite-no-token',
          name: 'Без ссылки',
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 2)),
          qrInviteToken: '',
        ),
      ]);

      expect(find.text('Без ссылки'), findsOneWidget);
      expect(_inviteOn('Без ссылки'), findsOneWidget);
    },
  );

  testWidgets('a finished organizer group does not show invite', (
    tester,
  ) async {
    final now = DateTime.now();
    await _showCreatedGroups(tester, [
      _createdGroup(
        id: 'invite-finished',
        name: 'Завершённая организатора',
        startsAt: now.subtract(const Duration(days: 2)),
        endsAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);

    expect(find.text('Завершённая организатора'), findsOneWidget);
    expect(_inviteOn('Завершённая организатора'), findsNothing);
  });

  testWidgets('a group closed by the organizer does not show invite', (
    tester,
  ) async {
    final now = DateTime.now();
    final group = _createdGroup(
      id: 'invite-closed',
      name: 'Закрытая организатором',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    group.endedByOrganizer = true;
    await _showCreatedGroups(tester, [group]);

    expect(find.text('Закрытая организатором'), findsOneWidget);
    expect(_inviteOn('Закрытая организатором'), findsNothing);
  });

  testWidgets('a group where the user is not the organizer does not show invite', (
    tester,
  ) async {
    final now = DateTime.now();
    await _showCreatedGroups(tester, [
      _createdGroup(
        id: 'invite-participant',
        name: 'Группа участника',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
        role: MemberRole.participant,
      ),
    ]);

    expect(find.text('Группа участника'), findsOneWidget);
    expect(_inviteOn('Группа участника'), findsNothing);
  });

  testWidgets('an anonymous account is asked to sign in before the form', (
    tester,
  ) async {
    await _openCreatedGroups(
      tester,
      _GateAuth(const AuthAccount.anonymous()),
    );

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();

    expect(find.text(phoneSignInDialogTitle), findsOneWidget);
    expect(find.text(phoneSignInDialogMessage), findsOneWidget);
    expect(find.text('Новая группа'), findsNothing);
  });

  testWidgets('cancelling the sign-in prompt leaves the create form closed', (
    tester,
  ) async {
    await _openCreatedGroups(
      tester,
      _GateAuth(const AuthAccount.anonymous()),
    );

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();

    expect(find.text(phoneSignInDialogMessage), findsNothing);
    expect(find.text('Новая группа'), findsNothing);
    expect(find.byType(PhoneAuthScreen), findsNothing);
    expect(find.text('Созданные группы'), findsOneWidget);
  });

  testWidgets('choosing sign-in opens the phone screen', (tester) async {
    await _openCreatedGroups(
      tester,
      _GateAuth(const AuthAccount.anonymous()),
    );

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Войти'));
    await tester.pumpAndSettle();

    expect(find.byType(PhoneAuthScreen), findsOneWidget);
    expect(find.text('Новая группа'), findsNothing);
  });

  testWidgets('the sign-in prompt can be opened again after cancelling', (
    tester,
  ) async {
    await _openCreatedGroups(tester, _GateAuth(const AuthAccount.anonymous()));

    final createButton = find.text('Создать группу');

    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text(phoneSignInDialogMessage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();
    expect(find.text(phoneSignInDialogMessage), findsNothing);

    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text(phoneSignInDialogMessage), findsOneWidget);
    expect(find.text('Новая группа'), findsNothing);
  });

  testWidgets('a confirmed phone opens the create form immediately', (
    tester,
  ) async {
    await _openCreatedGroups(
      tester,
      _GateAuth(const AuthAccount.confirmed('+79991234567')),
    );

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();

    expect(find.text('Новая группа'), findsOneWidget);
    expect(find.text(phoneSignInDialogMessage), findsNothing);
  });

  testWidgets('a local account opens the create form immediately', (
    tester,
  ) async {
    await _openCreatedGroups(tester, _GateAuth(const AuthAccount.local()));

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();

    expect(find.text('Новая группа'), findsOneWidget);
    expect(find.text(phoneSignInDialogMessage), findsNothing);
  });
}

GeoGroup _createdGroup({
  required String id,
  required String name,
  required DateTime startsAt,
  DateTime? endsAt,
  MemberRole role = MemberRole.organizer,
  String qrInviteToken = 'saved-token',
}) {
  return GeoGroup(
    id: id,
    name: name,
    createdAt: DateTime.now(),
    startsAt: startsAt,
    endsAt: endsAt,
    createdByUserId: currentDemoUserId,
    qrInviteToken: qrInviteToken,
    members: [
      GroupMember(
        id: currentDemoUserId,
        name: 'Вы',
        role: role,
        status: MembershipStatus.active,
      ),
    ],
  );
}

Future<void> _showCreatedGroups(
  WidgetTester tester,
  List<GeoGroup> groups,
) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  for (final group in groups) {
    GroupsStore.instance.addGroup(group);
  }
  await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));
  await tester.pumpAndSettle();
}

Finder _inviteOn(String groupName) {
  return find.descendant(
    of: find.widgetWithText(GroupCard, groupName),
    matching: find.text('Пригласить в группу'),
  );
}

Finder _semantics(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}

const _silentLocation = _SilentLocation();

class _GateAuth implements AuthRepository {
  _GateAuth(this.account);

  final AuthAccount account;

  @override
  AuthAccount get current => account;

  @override
  Future<void> sendPhoneOtp(String phoneE164) async {}

  @override
  Future<void> verifyPhoneOtp({
    required String phoneE164,
    required String code,
  }) async {}

  @override
  Future<AuthSignOutResult> signOut() async {
    return const AuthSignOutResult(anonymousSessionRestored: true);
  }
}

Future<void> _openCreatedGroups(
  WidgetTester tester,
  AuthRepository auth,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: CreatedGroupsScreen(auth: auth)));
  await tester.pumpAndSettle();
}

class _SilentLocation implements CurrentLocationProvider {
  const _SilentLocation();

  @override
  Future<LocationAccess> ensurePermissionForJoin() async {
    return LocationAccess.unavailable;
  }

  @override
  Future<GeoCoordinate?> currentPosition() async {
    return null;
  }
}
