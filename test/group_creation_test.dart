import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_map_screen.dart';
import 'package:geo_groups/my_groups_screen.dart';

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

    await tester.pumpWidget(const MaterialApp(home: CreatedGroupsScreen()));
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
    expect(pin.color, const Color(0xFF00897B));
    expect(pin.shadows?.any((shadow) => shadow.color == Colors.white), isTrue);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });
}

Finder _semantics(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}

const _silentLocation = _SilentLocation();

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
