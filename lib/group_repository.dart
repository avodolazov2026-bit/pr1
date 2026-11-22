import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/foreground_location_sharing.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/supabase_bootstrap.dart';

/// Чтение групп текущего пользователя. Запись в хранилище здесь не выполняется.
abstract class GroupReadRepository {
  Future<List<GeoGroup>> loadMyGroups();
}

/// Какой источник групп использовать после bootstrap.
enum GroupRepositoryKind { local, supabase }

GroupRepositoryKind groupRepositoryKindFor(SupabaseStartup startup) {
  if (startup == SupabaseStartup.ready) {
    return GroupRepositoryKind.supabase;
  }
  return GroupRepositoryKind.local;
}

GroupReadRepository groupRepositoryFor(SupabaseStartup startup) {
  if (groupRepositoryKindFor(startup) == GroupRepositoryKind.supabase) {
    return SupabaseGroupRepository();
  }
  return LocalGroupRepository();
}

/// Записывает прочитанные группы в живое хранилище только после успешного входа.
///
/// Пустой список очищает демо-группы. В локальном режиме и при ошибке хранилище не трогается.
void publishLoadedGroups(
  SupabaseStartup startup,
  List<GeoGroup> groups, {
  String? currentUserId,
}) {
  if (startup != SupabaseStartup.ready) {
    return;
  }
  if (currentUserId != null && currentUserId.isNotEmpty) {
    currentDemoUserId = currentUserId;
  }
  GroupsStore.instance.replaceGroups(groups);
  notifySharingTargetsChanged();
}

/// Текущий локальный список. К сети не обращается.
class LocalGroupRepository implements GroupReadRepository {
  @override
  Future<List<GeoGroup>> loadMyGroups() async {
    return GroupsStore.instance.myGroups;
  }
}

typedef MembershipRows = Future<List<Map<String, dynamic>>> Function(
  String userId,
);

typedef GroupRows = Future<List<Map<String, dynamic>>> Function(
  List<String> groupIds,
);

/// Группы пользователя: сначала его строки memberships, затем связанные groups.
class SupabaseGroupRepository implements GroupReadRepository {
  SupabaseGroupRepository({
    this.userId,
    MembershipRows? memberships,
    GroupRows? groups,
  }) : _memberships = memberships ?? _membershipsFromSupabase,
       _groups = groups ?? _groupsFromSupabase;

  final String? userId;
  final MembershipRows _memberships;
  final GroupRows _groups;

  @override
  Future<List<GeoGroup>> loadMyGroups() async {
    final userId = this.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return const [];
    }
    final memberships = _activeMemberships(await _memberships(userId));
    final groupIds = <String>[];
    for (final row in memberships) {
      final groupId = row['group_id'];
      if (groupId is String &&
          groupId.isNotEmpty &&
          !groupIds.contains(groupId)) {
        groupIds.add(groupId);
      }
    }
    if (groupIds.isEmpty) {
      return const [];
    }
    final groups = await _groups(groupIds);
    return mapSupabaseGroups(
      currentUserId: userId,
      memberships: memberships,
      groups: groups,
    );
  }
}

Future<List<Map<String, dynamic>>> _membershipsFromSupabase(
  String userId,
) async {
  final rows = await Supabase.instance.client
      .from('memberships')
      .select('group_id,user_id,role,status,display_name')
      .eq('user_id', userId);
  return _rowMaps(rows);
}

Future<List<Map<String, dynamic>>> _groupsFromSupabase(
  List<String> groupIds,
) async {
  final rows = await Supabase.instance.client
      .from('groups')
      .select(
        'id,name,creator_id,created_at,starts_at,ends_at,ended_at,ended_by_user_id',
      )
      .inFilter('id', groupIds);
  return _rowMaps(rows);
}

List<Map<String, dynamic>> _rowMaps(Object? rows) {
  if (rows is! List) {
    return const [];
  }
  return [
    for (final row in rows)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

/// Собирает модели приложения из уже прочитанных строк. Пустой вход даёт пустой список.
List<GeoGroup> mapSupabaseGroups({
  required String currentUserId,
  required List<Map<String, dynamic>> memberships,
  required List<Map<String, dynamic>> groups,
}) {
  final byId = <String, Map<String, dynamic>>{};
  for (final row in groups) {
    final id = row['id'];
    if (id is String && id.isNotEmpty) {
      byId[id] = row;
    }
  }
  final result = <GeoGroup>[];
  final seen = <String>{};
  for (final membership in _activeMemberships(memberships)) {
    final groupId = membership['group_id'];
    if (groupId is! String || !seen.add(groupId)) {
      continue;
    }
    final group = byId[groupId];
    if (group == null) {
      continue;
    }
    final mapped = _groupFromRows(
      currentUserId: currentUserId,
      group: group,
      membership: membership,
    );
    if (mapped != null) {
      result.add(mapped);
    }
  }
  return result;
}

GeoGroup? _groupFromRows({
  required String currentUserId,
  required Map<String, dynamic> group,
  required Map<String, dynamic> membership,
}) {
  final id = group['id'];
  final name = group['name'];
  final startsAt = _dateTime(group['starts_at']);
  if (id is! String || id.isEmpty || name is! String || startsAt == null) {
    return null;
  }
  final creatorId = group['creator_id'];
  final memberId = membership['user_id'];
  final resolvedMemberId = memberId is String && memberId.isNotEmpty
      ? memberId
      : currentUserId;
  final displayName = membership['display_name'];
  final mapped = GeoGroup(
    id: id,
    name: name,
    createdAt: _dateTime(group['created_at']) ?? startsAt,
    startsAt: startsAt,
    endsAt: _dateTime(group['ends_at']),
    createdByUserId: creatorId is String ? creatorId : null,
    members: [
      GroupMember(
        id: resolvedMemberId,
        name: displayName is String && displayName.trim().isNotEmpty
            ? displayName.trim()
            : 'Участник',
        role: membership['role'] == 'organizer'
            ? MemberRole.organizer
            : MemberRole.participant,
        status: _membershipStatus(membership['status']),
      ),
    ],
  );
  mapped.endedAt = _dateTime(group['ended_at']);
  return mapped;
}

List<Map<String, dynamic>> _activeMemberships(
  List<Map<String, dynamic>> memberships,
) {
  return [
    for (final membership in memberships)
      if (membership['status'] == 'active') membership,
  ];
}

MembershipStatus _membershipStatus(Object? value) {
  return switch (value) {
    'invited' => MembershipStatus.invited,
    'left' => MembershipStatus.left,
    'removed' || 'removed_by_organizer' => MembershipStatus.removedByOrganizer,
    _ => MembershipStatus.active,
  };
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
