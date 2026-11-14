import 'package:flutter/material.dart';

import 'package:geo_groups/group_invitation.dart';

enum MemberRole { organizer, participant }

enum MembershipStatus { active, invited, left, removedByOrganizer }

class DirectoryPerson {
  const DirectoryPerson({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DirectoryPerson && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

const defaultDemoUserId = 'current-user';

const demoDirectory = <DirectoryPerson>[
  DirectoryPerson(id: 'anna-smirnova', name: 'Анна Смирнова'),
  DirectoryPerson(id: 'mikhail-ivanov', name: 'Михаил Иванов'),
  DirectoryPerson(id: 'elena-kuznetsova', name: 'Елена Кузнецова'),
  DirectoryPerson(id: 'dmitry-petrov', name: 'Дмитрий Петров'),
  DirectoryPerson(id: 'olga-sokolova', name: 'Ольга Соколова'),
];

/// Все, между кем можно переключаться в режиме разработки.
final List<DirectoryPerson> demoUsers = <DirectoryPerson>[
  DirectoryPerson(id: defaultDemoUserId, name: 'Вы'),
  ...demoDirectory,
];

/// Единый текущий демонстрационный пользователь.
/// Только память процесса: при перезапуске снова [defaultDemoUserId].
/// Список групп и приглашений при смене пользователя не копируется.
String currentDemoUserId = defaultDemoUserId;

DirectoryPerson get currentDemoUser {
  for (final user in demoUsers) {
    if (user.id == currentDemoUserId) {
      return user;
    }
  }
  return demoUsers.first;
}

class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.role = MemberRole.participant,
    this.status = MembershipStatus.active,
    this.distanceMeters,
  });

  final String id;
  final String name;
  final MemberRole role;
  MembershipStatus status;

  /// Расстояние только у активного участника. У приглашённого его нет.
  final int? distanceMeters;

  bool get isCurrentUser => id == currentDemoUserId;
}

class GeoGroup {
  GeoGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.endsAt,
    required this.members,
    this.createdByUserId,
  });

  final String id;
  String name;
  final DateTime createdAt;

  /// null — группа бессрочная и не завершается по времени.
  DateTime? endsAt;
  final List<GroupMember> members;

  /// Кто создал группу. Общий список групп не делится по пользователям.
  final String? createdByUserId;

  bool get createdByCurrentUser => createdByUserId == currentDemoUserId;

  bool get currentUserHasLeft => members.any(
        (member) =>
            member.isCurrentUser && member.status == MembershipStatus.left,
      );

  bool get currentUserIsActiveOrganizer => members.any(
        (member) =>
            member.isCurrentUser &&
            member.role == MemberRole.organizer &&
            member.status == MembershipStatus.active,
      );

  bool get currentUserIsActiveMember => members.any(
        (member) =>
            member.isCurrentUser && member.status == MembershipStatus.active,
      );

  String get organizerName {
    for (final member in members) {
      if (member.role == MemberRole.organizer) {
        return member.name;
      }
    }
    return 'Организатор';
  }

  /// Обновляет группу только если новое название и срок допустимы.
  /// Возвращает текст ошибки и ничего не меняет, если сохранить нельзя.
  String? updateDetails({
    required String name,
    required DateTime? endsAt,
    required List<GroupMember> members,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Введите название группы';
    }
    final issue = validateEndsAtUpdate(
      originalEndsAt: this.endsAt,
      nextEndsAt: endsAt,
    );
    if (issue != null) {
      return issue;
    }
    this.name = trimmed;
    this.endsAt = endsAt;
    this.members
      ..clear()
      ..addAll(members);
    return null;
  }

  int get activeMemberCount => members
      .where((member) => member.status == MembershipStatus.active)
      .length;

  int get invitedCount => members
      .where((member) => member.status == MembershipStatus.invited)
      .length;

  bool get isIndefinite => endsAt == null;

  bool get isActive {
    final endsAt = this.endsAt;
    if (endsAt == null) {
      return true;
    }
    return endsAt.isAfter(DateTime.now());
  }

  String get activeUntilLabel {
    final endsAt = this.endsAt;
    if (endsAt == null) {
      return 'Бессрочная';
    }
    return formatGroupDateTime(endsAt);
  }
}

enum GroupPeriod {
  week,
  month,
  year;

  Duration get duration => switch (this) {
        GroupPeriod.week => const Duration(days: 7),
        GroupPeriod.month => const Duration(days: 30),
        GroupPeriod.year => const Duration(days: 365),
      };
}

enum InvitationAcceptResult {
  joined,
  notPending,
  missingGroup,
  groupEnded,
  alreadyMember,
}

class GroupsStore {
  GroupsStore._() {
    groups.addAll(_demoGroups());
    invitations.addAll(_demoInvitations());
  }

  static final GroupsStore instance = GroupsStore._();

  final List<GeoGroup> groups = <GeoGroup>[];
  final List<GroupInvitation> invitations = <GroupInvitation>[];
  int _sequence = 0;

  String nextId(String prefix) {
    _sequence += 1;
    return '$prefix-$_sequence';
  }

  void addGroup(GeoGroup group) {
    groups.insert(0, group);
  }

  GeoGroup? groupById(String id) {
    for (final group in groups) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  List<GeoGroup> get myGroups =>
      groups.where((group) => group.currentUserIsActiveMember).toList();

  List<GroupInvitation> get incomingPending {
    final result = invitations
        .where(
          (invitation) =>
              invitation.inviteeId == currentDemoUserId &&
              invitation.status == InvitationStatus.pending,
        )
        .toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  bool hasPendingInvitation(String groupId, String inviteeId) {
    return invitations.any(
      (invitation) =>
          invitation.groupId == groupId &&
          invitation.inviteeId == inviteeId &&
          invitation.status == InvitationStatus.pending,
    );
  }

  /// Создаёт pending-приглашения для приглашённых и отзывает снятые.
  void syncInvitations(GeoGroup group) {
    final invitedMembers = group.members
        .where((member) => member.status == MembershipStatus.invited)
        .toList();
    final invitedIds = invitedMembers.map((member) => member.id).toSet();

    for (final invitation in invitations) {
      if (invitation.groupId != group.id ||
          invitation.status != InvitationStatus.pending) {
        continue;
      }
      if (!invitedIds.contains(invitation.inviteeId)) {
        invitation.status = InvitationStatus.revoked;
      }
    }
    if (!group.isActive) {
      return;
    }

    for (final member in invitedMembers) {
      if (hasPendingInvitation(group.id, member.id)) {
        continue;
      }
      invitations.add(
        GroupInvitation(
          id: nextId('invitation'),
          groupId: group.id,
          inviterName: group.organizerName,
          inviteeId: member.id,
          inviteeName: member.name,
          source: InvitationSource.demoList,
          status: InvitationStatus.pending,
          createdAt: DateTime.now(),
          expiresAt: group.endsAt,
        ),
      );
    }
  }

  InvitationAcceptResult acceptInvitation(GroupInvitation invitation) {
    if (invitation.status != InvitationStatus.pending) {
      return InvitationAcceptResult.notPending;
    }
    final group = groupById(invitation.groupId);
    if (group == null) {
      return InvitationAcceptResult.missingGroup;
    }
    if (!group.isActive) {
      return InvitationAcceptResult.groupEnded;
    }
    GroupMember? member;
    for (final candidate in group.members) {
      if (candidate.id == invitation.inviteeId) {
        member = candidate;
        break;
      }
    }
    if (member != null && member.status == MembershipStatus.active) {
      return InvitationAcceptResult.alreadyMember;
    }

    invitation.status = InvitationStatus.accepted;
    if (member == null) {
      group.members.add(
        GroupMember(
          id: invitation.inviteeId,
          name: invitation.inviteeName,
          status: MembershipStatus.active,
        ),
      );
    } else if (member.status == MembershipStatus.invited) {
      member.status = MembershipStatus.active;
    }
    return InvitationAcceptResult.joined;
  }

  void declineInvitation(GroupInvitation invitation) {
    if (invitation.status != InvitationStatus.pending) {
      return;
    }
    invitation.status = InvitationStatus.declined;
    final group = groupById(invitation.groupId);
    group?.members.removeWhere(
      (member) =>
          member.id == invitation.inviteeId &&
          member.status == MembershipStatus.invited,
    );
  }

  List<GeoGroup> createdGroups(GroupPeriod period) {
    final from = DateTime.now().subtract(period.duration);
    final result = groups
        .where(
          (group) =>
              group.createdByCurrentUser && !group.createdAt.isBefore(from),
        )
        .toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }
}

/// null — срок можно сохранить. Иначе текст, который нужно показать пользователю.
String? validateEndsAtUpdate({
  required DateTime? originalEndsAt,
  required DateTime? nextEndsAt,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (originalEndsAt == null) {
    if (nextEndsAt == null) {
      return null;
    }
    if (!nextEndsAt.isAfter(current)) {
      return 'Нельзя выбрать дату и время в прошлом';
    }
    return null;
  }
  if (nextEndsAt == null) {
    return 'Нельзя сделать срочную группу бессрочной.';
  }
  if (nextEndsAt.isAfter(originalEndsAt)) {
    return 'Нельзя продлить срок группы: это потребует нового согласия участников.';
  }
  if (!nextEndsAt.isAfter(current)) {
    return 'Нельзя выбрать дату и время в прошлом';
  }
  return null;
}

String memberInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '';
  }
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

String formatGroupDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]}, $hour:$minute';
}

String formatGroupDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]}';
}

String formatGroupTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const _months = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

DateTime _upcoming(int month, int day, int hour, int minute) {
  final now = DateTime.now();
  var date = DateTime(now.year, month, day, hour, minute);
  if (!date.isAfter(now)) {
    date = DateTime(now.year + 1, month, day, hour, minute);
  }
  return date;
}

GroupMember _currentUser({bool organizer = false}) {
  return GroupMember(
    id: defaultDemoUserId,
    name: 'Вы',
    role: organizer ? MemberRole.organizer : MemberRole.participant,
    status: MembershipStatus.active,
  );
}

GroupMember _activeMember({
  required String id,
  required String name,
  required int distanceMeters,
}) {
  return GroupMember(
    id: id,
    name: name,
    status: MembershipStatus.active,
    distanceMeters: distanceMeters,
  );
}

GroupMember _invitedCurrentUser() {
  return GroupMember(
    id: defaultDemoUserId,
    name: 'Вы',
    status: MembershipStatus.invited,
  );
}

List<GeoGroup> _demoGroups() {
  final now = DateTime.now();
  return [
    GeoGroup(
      id: 'picnic',
      name: 'Пикник в парке',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 15, 18, 0),
      members: [
        _activeMember(id: 'maria', name: 'Мария', distanceMeters: 120),
        _activeMember(id: 'alexey', name: 'Алексей', distanceMeters: 340),
        _activeMember(id: 'elena', name: 'Елена', distanceMeters: 680),
        _currentUser(),
      ],
    ),
    GeoGroup(
      id: 'concert',
      name: 'Концерт',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 16, 23, 30),
      members: [
        _activeMember(id: 'dmitry', name: 'Дмитрий', distanceMeters: 85),
        _activeMember(id: 'olga', name: 'Ольга', distanceMeters: 210),
        _currentUser(),
      ],
    ),
    GeoGroup(
      id: 'out-of-town',
      name: 'Поездка за город',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 17, 20, 0),
      members: [
        _activeMember(id: 'igor', name: 'Игорь', distanceMeters: 150),
        _activeMember(id: 'anna', name: 'Анна', distanceMeters: 420),
        _activeMember(id: 'sergey', name: 'Сергей', distanceMeters: 760),
        _activeMember(id: 'victoria', name: 'Виктория', distanceMeters: 1100),
        _currentUser(),
      ],
    ),
    GeoGroup(
      id: 'fountain',
      name: 'Сборы у фонтана',
      createdAt: now.subtract(const Duration(minutes: 30)),
      endsAt: now.add(const Duration(hours: 6)),
      createdByUserId: defaultDemoUserId,
      members: [
        _activeMember(id: 'maria-fountain', name: 'Мария', distanceMeters: 90),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      id: 'evening-walk',
      name: 'Вечерняя прогулка',
      createdAt: now.subtract(const Duration(days: 3)),
      endsAt: now.add(const Duration(days: 2)),
      createdByUserId: defaultDemoUserId,
      members: [
        _activeMember(id: 'alexey-walk', name: 'Алексей', distanceMeters: 250),
        _activeMember(id: 'elena-walk', name: 'Елена', distanceMeters: 500),
        GroupMember(
          id: 'olga-sokolova',
          name: 'Ольга Соколова',
          status: MembershipStatus.invited,
        ),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      id: 'cinema',
      name: 'Кино',
      createdAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 3)),
      createdByUserId: defaultDemoUserId,
      members: [
        _activeMember(id: 'dmitry-cinema', name: 'Дмитрий', distanceMeters: 40),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      id: 'friends-trip',
      name: 'Поездка к друзьям',
      createdAt: now.subtract(const Duration(days: 12)),
      endsAt: now.add(const Duration(days: 4)),
      createdByUserId: defaultDemoUserId,
      members: [
        _activeMember(id: 'igor-trip', name: 'Игорь', distanceMeters: 180),
        _activeMember(id: 'anna-trip', name: 'Анна', distanceMeters: 640),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      id: 'invite-ride',
      name: 'Велопрогулка',
      createdAt: now.subtract(const Duration(hours: 5)),
      endsAt: now.add(const Duration(days: 5)),
      members: [
        GroupMember(
          id: 'maria-kovaleva',
          name: 'Мария Ковалёва',
          role: MemberRole.organizer,
          distanceMeters: 860,
        ),
        _activeMember(id: 'pavel-ride', name: 'Павел', distanceMeters: 240),
        _invitedCurrentUser(),
      ],
    ),
    GeoGroup(
      id: 'invite-neighbors',
      name: 'Соседи по району',
      createdAt: now.subtract(const Duration(days: 1)),
      endsAt: null,
      members: [
        GroupMember(
          id: 'igor-belov',
          name: 'Игорь Белов',
          role: MemberRole.organizer,
          distanceMeters: 150,
        ),
        _invitedCurrentUser(),
      ],
    ),
    GeoGroup(
      id: 'invite-breakfast',
      name: 'Вчерашний завтрак',
      createdAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 5)),
      members: [
        GroupMember(
          id: 'elena-orlova',
          name: 'Елена Орлова',
          role: MemberRole.organizer,
          distanceMeters: 40,
        ),
        _invitedCurrentUser(),
      ],
    ),
  ];
}

List<GroupInvitation> _demoInvitations() {
  final now = DateTime.now();
  final walkEndsAt = now.add(const Duration(days: 2));
  final rideEndsAt = now.add(const Duration(days: 5));
  return [
    GroupInvitation(
      id: 'invitation-olga-walk',
      groupId: 'evening-walk',
      inviterName: 'Вы',
      inviteeId: 'olga-sokolova',
      inviteeName: 'Ольга Соколова',
      source: InvitationSource.demoList,
      status: InvitationStatus.pending,
      createdAt: now.subtract(const Duration(days: 3)),
      expiresAt: walkEndsAt,
    ),
    GroupInvitation(
      id: 'invitation-ride',
      groupId: 'invite-ride',
      inviterName: 'Мария Ковалёва',
      inviteeId: defaultDemoUserId,
      inviteeName: 'Вы',
      source: InvitationSource.demoList,
      status: InvitationStatus.pending,
      createdAt: now.subtract(const Duration(hours: 1)),
      expiresAt: rideEndsAt,
    ),
    GroupInvitation(
      id: 'invitation-neighbors',
      groupId: 'invite-neighbors',
      inviterName: 'Игорь Белов',
      inviteeId: defaultDemoUserId,
      inviteeName: 'Вы',
      source: InvitationSource.qrCode,
      status: InvitationStatus.pending,
      createdAt: now.subtract(const Duration(hours: 2)),
    ),
    GroupInvitation(
      id: 'invitation-breakfast',
      groupId: 'invite-breakfast',
      inviterName: 'Елена Орлова',
      inviteeId: defaultDemoUserId,
      inviteeName: 'Вы',
      source: InvitationSource.demoList,
      status: InvitationStatus.pending,
      createdAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.subtract(const Duration(hours: 5)),
    ),
  ];
}
