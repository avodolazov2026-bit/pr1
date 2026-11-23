import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_repository.dart';
import 'package:geo_groups/supabase_bootstrap.dart';

void main() {
  late List<GeoGroup> groupsBefore;

  setUp(() {
    groupsBefore = List<GeoGroup>.of(GroupsStore.instance.groups);
  });

  tearDown(() {
    currentDemoUserId = defaultDemoUserId;
    GroupsStore.instance.replaceGroups(groupsBefore);
  });

  test('repository defaults to supabase regardless of startup', () {
    expect(
      groupRepositoryKindFor(SupabaseStartup.local),
      GroupRepositoryKind.supabase,
    );
    expect(
      groupRepositoryKindFor(SupabaseStartup.failed),
      GroupRepositoryKind.supabase,
    );
    expect(
      groupRepositoryKindFor(SupabaseStartup.ready),
      GroupRepositoryKind.supabase,
    );
    expect(
      groupRepositoryFor(SupabaseStartup.local),
      isA<SupabaseGroupRepository>(),
    );
    expect(
      groupRepositoryFor(SupabaseStartup.failed),
      isA<SupabaseGroupRepository>(),
    );
    expect(
      groupRepositoryFor(SupabaseStartup.ready),
      isA<SupabaseGroupRepository>(),
    );
  });

  test('local mode keeps the demo groups', () {
    final demoIds = GroupsStore.instance.groups
        .map((group) => group.id)
        .toList();

    publishLoadedGroups(SupabaseStartup.local, const []);
    publishLoadedGroups(SupabaseStartup.failed, const []);

    expect(GroupsStore.instance.groups.map((group) => group.id), demoIds);
    expect(GroupsStore.instance.myGroups, isNotEmpty);
  });

  test('a ready supabase list replaces demo groups in the live store', () {
    final groups = mapSupabaseGroups(
      currentUserId: 'user-1',
      memberships: [
        {
          'group_id': 'group-1',
          'user_id': 'user-1',
          'role': 'organizer',
          'status': 'active',
          'display_name': 'Ника',
        },
      ],
      groups: [
        {
          'id': 'group-1',
          'name': 'Прогулка',
          'creator_id': 'user-1',
          'starts_at': '2026-11-20T09:00:00Z',
          'ends_at': '2026-11-20T12:00:00Z',
        },
      ],
    );

    publishLoadedGroups(SupabaseStartup.ready, groups, currentUserId: 'user-1');

    expect(GroupsStore.instance.groups.map((group) => group.id), ['group-1']);
    expect(GroupsStore.instance.myGroups.map((group) => group.id), ['group-1']);
    expect(
      GroupsStore.instance.myGroups.single.members.single.isCurrentUser,
      isTrue,
    );
  });

  test('an empty supabase list clears demo groups', () {
    publishLoadedGroups(
      SupabaseStartup.ready,
      const [],
      currentUserId: 'user-1',
    );

    expect(GroupsStore.instance.groups, isEmpty);
    expect(GroupsStore.instance.myGroups, isEmpty);
  });

  test('local repository returns the demo membership list', () async {
    final groups = await LocalGroupRepository().loadMyGroups();

    expect(groups, GroupsStore.instance.myGroups);
  });

  test('supabase rows become the current user group', () {
    currentDemoUserId = 'user-1';
    final groups = mapSupabaseGroups(
      currentUserId: 'user-1',
      memberships: [
        {
          'group_id': 'group-1',
          'user_id': 'user-1',
          'role': 'organizer',
          'status': 'active',
          'display_name': 'Ника',
        },
      ],
      groups: [
        {
          'id': 'group-1',
          'name': 'Прогулка',
          'creator_id': 'user-1',
          'created_at': '2026-11-20T08:00:00Z',
          'starts_at': '2026-11-20T09:00:00Z',
          'ends_at': '2026-11-20T12:00:00Z',
          'ended_at': '2026-11-20T11:30:00Z',
          'ended_by_user_id': 'user-1',
        },
      ],
    );

    expect(groups, hasLength(1));
    final group = groups.single;
    expect(group.id, 'group-1');
    expect(group.name, 'Прогулка');
    expect(group.createdByUserId, 'user-1');
    expect(group.createdAt, DateTime.parse('2026-11-20T08:00:00Z'));
    expect(group.startsAt, DateTime.parse('2026-11-20T09:00:00Z'));
    expect(group.endsAt, DateTime.parse('2026-11-20T12:00:00Z'));
    expect(group.endedAt, DateTime.parse('2026-11-20T11:30:00Z'));
    expect(group.endedByOrganizer, isFalse);
    expect(group.members, hasLength(1));
    expect(group.members.single.id, 'user-1');
    expect(group.members.single.name, 'Ника');
    expect(group.members.single.role, MemberRole.organizer);
    expect(group.members.single.status, MembershipStatus.active);
    expect(group.members.single.isCurrentUser, isTrue);
    expect(group.memberLocations, isEmpty);
  });

  test('missing group rows and empty memberships produce no groups', () {
    expect(
      mapSupabaseGroups(
        currentUserId: 'user-1',
        memberships: const [],
        groups: const [],
      ),
      isEmpty,
    );
    expect(
      mapSupabaseGroups(
        currentUserId: 'user-1',
        memberships: [
          {
            'group_id': 'hidden',
            'user_id': 'user-1',
            'role': 'participant',
            'status': 'active',
          },
        ],
        groups: const [],
      ),
      isEmpty,
    );
  });

  test(
    'repository reads memberships before groups and skips an empty result',
    () async {
      var groupReads = 0;
      final repository = SupabaseGroupRepository(
        userId: 'user-1',
        memberships: (_) async => const [],
        groups: (_) async {
          groupReads++;
          return const [];
        },
      );

      expect(await repository.loadMyGroups(), isEmpty);
      expect(groupReads, 0);
    },
  );

  test(
    'repository keeps only groups returned for the membership ids',
    () async {
      final seenIds = <String>[];
      final repository = SupabaseGroupRepository(
        userId: 'user-1',
        memberships: (_) async => [
          {
            'group_id': 'group-1',
            'user_id': 'user-1',
            'role': 'participant',
            'status': 'invited',
            'display_name': '  ',
          },
          {
            'group_id': 'group-1',
            'user_id': 'user-1',
            'role': 'participant',
            'status': 'active',
          },
        ],
        groups: (ids) async {
          seenIds.addAll(ids);
          return [
            {
              'id': 'group-1',
              'name': 'Встреча',
              'creator_id': 'other',
              'starts_at': '2026-11-21T10:00:00Z',
            },
          ];
        },
      );

      final groups = await repository.loadMyGroups();

      expect(seenIds, ['group-1']);
      expect(groups, hasLength(1));
      expect(groups.single.createdAt, groups.single.startsAt);
      expect(groups.single.endsAt, isNull);
      expect(groups.single.members.single.name, 'Участник');
      expect(groups.single.members.single.status, MembershipStatus.active);
      expect(groups.single.members.single.role, MemberRole.participant);
    },
  );

  test('inactive memberships do not load groups', () async {
    var groupReads = 0;
    final repository = SupabaseGroupRepository(
      userId: 'user-1',
      memberships: (_) async => const [
        {'group_id': 'invited', 'user_id': 'user-1', 'status': 'invited'},
        {'group_id': 'left', 'user_id': 'user-1', 'status': 'left'},
        {'group_id': 'removed', 'user_id': 'user-1', 'status': 'removed'},
        {
          'group_id': 'removed-by-organizer',
          'user_id': 'user-1',
          'status': 'removed_by_organizer',
        },
      ],
      groups: (_) async {
        groupReads++;
        return const [];
      },
    );

    expect(await repository.loadMyGroups(), isEmpty);
    expect(groupReads, 0);
  });

  test('map skips inactive memberships even when group rows exist', () {
    final groups = mapSupabaseGroups(
      currentUserId: 'user-1',
      memberships: const [
        {'group_id': 'invited', 'user_id': 'user-1', 'status': 'invited'},
        {'group_id': 'left', 'user_id': 'user-1', 'status': 'left'},
        {'group_id': 'removed', 'user_id': 'user-1', 'status': 'removed'},
        {
          'group_id': 'removed-by-organizer',
          'user_id': 'user-1',
          'status': 'removed_by_organizer',
        },
      ],
      groups: const [
        {
          'id': 'invited',
          'name': 'Приглашение',
          'starts_at': '2026-11-21T10:00:00Z',
        },
        {'id': 'left', 'name': 'Вышел', 'starts_at': '2026-11-21T10:00:00Z'},
        {
          'id': 'removed',
          'name': 'Удалён',
          'starts_at': '2026-11-21T10:00:00Z',
        },
        {
          'id': 'removed-by-organizer',
          'name': 'Исключён',
          'starts_at': '2026-11-21T10:00:00Z',
        },
      ],
    );

    expect(groups, isEmpty);
  });

  test('createGroup calls create_group and returns its uuid', () async {
    String? seenName;
    DateTime? seenStart;
    DateTime? seenEnd;
    final repository = SupabaseGroupRepository(
      createGroupCall: ({
        required String name,
        required DateTime startsAt,
        DateTime? endsAt,
      }) async {
        seenName = name;
        seenStart = startsAt;
        seenEnd = endsAt;
        return '6b1b1b1b-1b1b-4b1b-8b1b-1b1b1b1b1b1b';
      },
    );
    final startsAt = DateTime.utc(2026, 11, 23, 12);
    final endsAt = DateTime.utc(2026, 11, 23, 15);

    final id = await repository.createGroup(
      name: 'Прогулка',
      startsAt: startsAt,
      endsAt: endsAt,
    );

    expect(id, '6b1b1b1b-1b1b-4b1b-8b1b-1b1b1b1b1b1b');
    expect(seenName, 'Прогулка');
    expect(seenStart, startsAt);
    expect(seenEnd, endsAt);
  });

  test('createGroup lets a PostgrestException through', () {
    final repository = SupabaseGroupRepository(
      createGroupCall: ({
        required String name,
        required DateTime startsAt,
        DateTime? endsAt,
      }) async {
        throw const PostgrestException(message: 'Создание группы недоступно');
      },
    );

    expect(
      () => repository.createGroup(
        name: 'Прогулка',
        startsAt: DateTime.utc(2026, 11, 23, 12),
      ),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.message,
          'message',
          'Создание группы недоступно',
        ),
      ),
    );
  });
}
