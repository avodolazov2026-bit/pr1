import 'package:flutter/material.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/group_invitation.dart';

enum MemberRole { organizer, participant }

enum MembershipStatus { active, invited, left, removedByOrganizer }

class DirectoryPerson {
  const DirectoryPerson({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is DirectoryPerson && other.id == id;

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

/// Участники новой группы. Создатель всегда активный организатор и встречается один раз.
List<GroupMember> membersForNewGroup({
  required String creatorId,
  required String creatorName,
  String creatorAvatarId = defaultAvatarId,
  List<GroupMember> others = const [],
}) {
  final avatarId = creatorAvatarId.isEmpty ? defaultAvatarId : creatorAvatarId;
  final members = <GroupMember>[
    GroupMember(
      id: creatorId,
      name: creatorName,
      avatarId: avatarId,
      role: MemberRole.organizer,
      status: MembershipStatus.active,
    ),
  ];
  final seen = <String>{creatorId};
  for (final member in others) {
    if (seen.add(member.id)) {
      members.add(member);
    }
  }
  return members;
}

const defaultAvatarId = 'teal_person';

class GroupMember {
  GroupMember({
    required this.id,
    required this.name,
    this.avatarId = defaultAvatarId,
    this.role = MemberRole.participant,
    this.status = MembershipStatus.active,
    this.distanceMeters,
  });

  final String id;

  /// Имя, выбранное для этой группы. Не следует за последующими правками профиля.
  String name;

  /// Аватар, выбранный для этой группы.
  String avatarId;

  /// Снимок аватара для отображения. Пустое значение заменяется пресетом.
  String get displayAvatarId => avatarId.isEmpty ? defaultAvatarId : avatarId;
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
    required this.startsAt,
    required this.endsAt,
    required this.members,
    this.createdByUserId,
    List<GroupMemberLocation> memberLocations = const [],
    String? qrInviteToken,
  }) : qrInviteToken = qrInviteToken ?? 'qr-$id',
       _memberLocations = _memberLocationsFor(members, memberLocations);

  final String id;
  String name;
  final DateTime createdAt;

  /// Локальный токен QR-приглашения. Создаётся один раз и не меняется при редактировании.
  final String qrInviteToken;

  /// Начало группы. Меняется только пока группа запланирована, поэтому поле не final.
  DateTime startsAt;

  /// null — группа бессрочная и не завершается по времени.
  DateTime? endsAt;

  /// Организатор завершил группу раньше срока. Объект и приглашения сохраняются.
  bool endedByOrganizer = false;

  /// Момент ручной отмены или завершения. null у старых групп без этой отметки.
  DateTime? endedAt;
  final List<GroupMember> members;

  /// Последние известные позиции участников. Пусто, пока координаты не заданы.
  final List<GroupMemberLocation> _memberLocations;

  List<GroupMemberLocation> get memberLocations =>
      List<GroupMemberLocation>.unmodifiable(_memberLocations);

  /// Кто создал группу. Общий список групп не делится по пользователям.
  final String? createdByUserId;

  bool get createdByCurrentUser => createdByUserId == currentDemoUserId;

  bool get currentUserHasLeft => members.any(
    (member) => member.isCurrentUser && member.status == MembershipStatus.left,
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
    required DateTime startsAt,
    required DateTime? endsAt,
    required List<GroupMember> members,
  }) {
    if (isFinished) {
      return 'Завершённую группу нельзя изменить.';
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Введите название группы';
    }
    final issue = validateGroupSchedule(
      originalStartsAt: this.startsAt,
      nextStartsAt: startsAt,
      originalEndsAt: this.endsAt,
      nextEndsAt: endsAt,
      upcoming: isUpcoming,
    );
    if (issue != null) {
      return issue;
    }
    this.name = trimmed;
    this.startsAt = startsAt;
    this.endsAt = endsAt;
    this.members
      ..clear()
      ..addAll(members);
    _dropLocationsOfMissingMembers();
    return null;
  }

  /// Позиция участника или null, если её ещё нет.
  GroupMemberLocation? memberLocation(String memberId) {
    for (final location in _memberLocations) {
      if (location.memberId == memberId) {
        return location;
      }
    }
    return null;
  }

  /// Заменяет позицию участника. Участник должен уже состоять в группе.
  void updateMemberLocation(GroupMemberLocation location) {
    if (!members.any((member) => member.id == location.memberId)) {
      throw ArgumentError.value(
        location.memberId,
        'location',
        'Позиция относится к участнику, которого нет в группе',
      );
    }
    _memberLocations.removeWhere((item) => item.memberId == location.memberId);
    _memberLocations.add(location);
  }

  void _dropLocationsOfMissingMembers() {
    final memberIds = members.map((member) => member.id).toSet();
    _memberLocations.removeWhere(
      (location) => !memberIds.contains(location.memberId),
    );
  }

  int get activeMemberCount => members
      .where((member) => member.status == MembershipStatus.active)
      .length;

  int get invitedCount => members
      .where((member) => member.status == MembershipStatus.invited)
      .length;

  bool get isIndefinite => endsAt == null;

  bool get isUpcoming => !endedByOrganizer && DateTime.now().isBefore(startsAt);

  bool get isActive {
    final endsAt = this.endsAt;
    return !endedByOrganizer &&
        !DateTime.now().isBefore(startsAt) &&
        (endsAt == null || DateTime.now().isBefore(endsAt));
  }

  bool get isFinished {
    final endsAt = this.endsAt;
    return endedByOrganizer ||
        (endsAt != null && !DateTime.now().isBefore(endsAt));
  }

  /// Карта и передача геопозиции доступны только у уже начавшейся группы.
  bool get canUseMap => isActive;

  bool get wasCancelledBeforeStart {
    final endedAt = this.endedAt;
    return endedByOrganizer && endedAt != null && endedAt.isBefore(startsAt);
  }

  String get statusBadge {
    if (isUpcoming) {
      return 'Запланирована';
    }
    if (isActive) {
      return 'Активна';
    }
    if (wasCancelledBeforeStart) {
      return 'Отменена';
    }
    if (endedByOrganizer) {
      return 'Завершена';
    }
    return 'Истекла';
  }

  String get scheduleSummary {
    if (isUpcoming) {
      return 'Начнётся ${formatGroupDateTime(startsAt)}';
    }
    if (isActive) {
      final activeUntil = endsAt;
      if (activeUntil == null) {
        return 'Без срока окончания';
      }
      return 'До ${formatGroupDateTime(activeUntil)}';
    }
    if (wasCancelledBeforeStart) {
      return 'Была запланирована на ${formatGroupDateTime(startsAt)}';
    }
    if (endedByOrganizer) {
      return 'Завершена организатором';
    }
    final finishedAt = endsAt;
    if (finishedAt != null) {
      return 'Истекла ${formatGroupDateTime(finishedAt)}';
    }
    return 'Завершена организатором';
  }

  String get activeUntilLabel => scheduleSummary;
}

/// Ближайший будущий старт или конец среди [groups]. null, если переходов нет.
DateTime? nextGroupStatusChange(Iterable<GeoGroup> groups, DateTime now) {
  DateTime? nearest;
  for (final group in groups) {
    final moments = <DateTime>[
      group.startsAt,
      if (group.endsAt != null) group.endsAt!,
    ];
    for (final moment in moments) {
      if (!moment.isAfter(now)) {
        continue;
      }
      if (nearest == null || moment.isBefore(nearest)) {
        nearest = moment;
      }
    }
  }
  return nearest;
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

  /// Уникальный токен QR для новой группы. Повторно при редактировании не вызывается.
  String nextQrInviteToken() => nextId('qr');

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

  /// Завершает активную группу или отменяет запланированную.
  /// Участник без роли организатора сделать этого не может.
  bool endGroup(GeoGroup group) {
    if (group.isFinished || !group.currentUserIsActiveOrganizer) {
      return false;
    }
    group.endedByOrganizer = true;
    group.endedAt = DateTime.now();
    return true;
  }

  /// Ожидающие приглашения пользователя в запланированные и активные группы.
  int pendingInvitationCountFor(String userId) {
    var count = 0;
    for (final invitation in invitations) {
      if (invitation.inviteeId != userId ||
          invitation.status != InvitationStatus.pending) {
        continue;
      }
      final group = groupById(invitation.groupId);
      if (group != null && !group.isFinished) {
        count += 1;
      }
    }
    return count;
  }

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

  bool _hasInvitation({
    required String groupId,
    required String inviteeId,
    required InvitationStatus status,
  }) {
    return invitations.any(
      (invitation) =>
          invitation.groupId == groupId &&
          invitation.inviteeId == inviteeId &&
          invitation.status == status,
    );
  }

  /// Проверяет QR payload и не меняет участников или приглашения.
  QrInviteInspection inspectQrInvitation(String rawPayload) {
    final payload = rawPayload.trim();
    if (payload.isEmpty) {
      return const QrInviteInspection(QrInviteClaimResult.empty);
    }
    final parsed = parseGroupInvitePayload(payload);
    if (parsed == null) {
      return const QrInviteInspection(QrInviteClaimResult.unrecognized);
    }
    final group = groupById(parsed.groupId);
    if (group == null) {
      return const QrInviteInspection(QrInviteClaimResult.unavailable);
    }
    if (group.qrInviteToken != parsed.inviteToken) {
      return QrInviteInspection(QrInviteClaimResult.invalidToken, group);
    }
    if (group.isFinished) {
      return QrInviteInspection(QrInviteClaimResult.inactive, group);
    }

    final userId = currentDemoUserId;
    final isOrganizer = group.members.any(
      (member) => member.id == userId && member.role == MemberRole.organizer,
    );
    if (isOrganizer) {
      return QrInviteInspection(QrInviteClaimResult.organizer, group);
    }
    if (group.currentUserIsActiveMember ||
        _hasInvitation(
          groupId: group.id,
          inviteeId: userId,
          status: InvitationStatus.accepted,
        )) {
      return QrInviteInspection(QrInviteClaimResult.alreadyMember, group);
    }
    if (hasPendingInvitation(group.id, userId)) {
      return QrInviteInspection(QrInviteClaimResult.alreadyPending, group);
    }
    return QrInviteInspection(QrInviteClaimResult.added, group);
  }

  /// Разбирает QR payload и создаёт обычное pending-приглашение текущему пользователю.
  /// Сканер камеры позже может передать сюда распознанную строку.
  QrInviteClaimResult claimQrInvitation(String rawPayload) {
    final inspection = inspectQrInvitation(rawPayload);
    if (inspection.result != QrInviteClaimResult.added) {
      return inspection.result;
    }
    final group = inspection.group!;
    final userId = currentDemoUserId;
    if (!group.members.any((member) => member.id == userId)) {
      group.members.add(
        GroupMember(
          id: userId,
          name: currentDemoUser.name,
          status: MembershipStatus.invited,
        ),
      );
    }
    invitations.add(
      GroupInvitation(
        id: nextId('invitation'),
        groupId: group.id,
        inviterName: group.organizerName,
        inviteeId: userId,
        inviteeName: currentDemoUser.name,
        source: InvitationSource.qrCode,
        status: InvitationStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: group.endsAt,
      ),
    );
    return QrInviteClaimResult.added;
  }

  /// Вступает по уже проверенному QR после подтверждения имени и аватара.
  InvitationAcceptResult joinFromQrPayload(
    String rawPayload, {
    required String displayName,
    required String avatarId,
  }) {
    if (displayName.trim().isEmpty) {
      return InvitationAcceptResult.notPending;
    }
    final inspection = inspectQrInvitation(rawPayload);
    if (inspection.result == QrInviteClaimResult.added) {
      final claimed = claimQrInvitation(rawPayload);
      if (claimed != QrInviteClaimResult.added &&
          claimed != QrInviteClaimResult.alreadyPending) {
        return _acceptResultForQr(claimed);
      }
    } else if (inspection.result != QrInviteClaimResult.alreadyPending) {
      return _acceptResultForQr(inspection.result);
    }

    final group = inspection.group;
    if (group == null) {
      return InvitationAcceptResult.missingGroup;
    }
    GroupInvitation? invitation;
    for (final candidate in invitations) {
      if (candidate.groupId == group.id &&
          candidate.inviteeId == currentDemoUserId &&
          candidate.status == InvitationStatus.pending) {
        invitation = candidate;
        break;
      }
    }
    if (invitation == null) {
      return InvitationAcceptResult.notPending;
    }
    return acceptInvitation(
      invitation,
      displayName: displayName,
      avatarId: avatarId,
    );
  }

  InvitationAcceptResult _acceptResultForQr(QrInviteClaimResult result) {
    return switch (result) {
      QrInviteClaimResult.alreadyMember => InvitationAcceptResult.alreadyMember,
      QrInviteClaimResult.inactive => InvitationAcceptResult.groupEnded,
      QrInviteClaimResult.unavailable => InvitationAcceptResult.missingGroup,
      _ => InvitationAcceptResult.notPending,
    };
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
    if (group.isFinished) {
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

  InvitationAcceptResult acceptInvitation(
    GroupInvitation invitation, {
    String? displayName,
    String? avatarId,
  }) {
    if (displayName != null && displayName.trim().isEmpty) {
      return InvitationAcceptResult.notPending;
    }
    if (invitation.status != InvitationStatus.pending) {
      return InvitationAcceptResult.notPending;
    }
    final group = groupById(invitation.groupId);
    if (group == null) {
      return InvitationAcceptResult.missingGroup;
    }
    if (group.isFinished) {
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

    final resolvedName = displayName == null
        ? invitation.inviteeName
        : displayName.trim();
    final resolvedAvatar = avatarId == null || avatarId.isEmpty
        ? defaultAvatarId
        : avatarId;
    invitation.status = InvitationStatus.accepted;
    if (member == null) {
      group.members.add(
        GroupMember(
          id: invitation.inviteeId,
          name: resolvedName,
          avatarId: resolvedAvatar,
          status: MembershipStatus.active,
        ),
      );
    } else if (member.status == MembershipStatus.invited) {
      member
        ..name = resolvedName
        ..avatarId = resolvedAvatar
        ..status = MembershipStatus.active;
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
    group?._dropLocationsOfMissingMembers();
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

/// null — расписание можно сохранить. Иначе текст, который нужно показать пользователю.
String? validateGroupSchedule({
  required DateTime originalStartsAt,
  required DateTime nextStartsAt,
  required DateTime? originalEndsAt,
  required DateTime? nextEndsAt,
  required bool upcoming,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (upcoming) {
    if (!nextStartsAt.isAfter(current)) {
      return 'Начало группы должно быть в будущем';
    }
  } else if (nextStartsAt != originalStartsAt) {
    return 'Время начала активной группы нельзя изменить.';
  }
  if (nextEndsAt != null && !nextEndsAt.isAfter(nextStartsAt)) {
    return 'Окончание должно быть позже начала';
  }
  if (upcoming) {
    if (nextEndsAt != null && !nextEndsAt.isAfter(current)) {
      return 'Нельзя выбрать дату и время в прошлом';
    }
    return null;
  }
  return validateEndsAtUpdate(
    originalEndsAt: originalEndsAt,
    nextEndsAt: nextEndsAt,
    now: current,
  );
}

int compareActiveGroups(GeoGroup a, GeoGroup b) {
  final aEnd = a.endsAt;
  final bEnd = b.endsAt;
  if (aEnd == null && bEnd == null) {
    return a.startsAt.compareTo(b.startsAt);
  }
  if (aEnd == null) {
    return 1;
  }
  if (bEnd == null) {
    return -1;
  }
  return aEnd.compareTo(bEnd);
}

int compareUpcomingGroups(GeoGroup a, GeoGroup b) =>
    a.startsAt.compareTo(b.startsAt);

int compareFinishedGroups(GeoGroup a, GeoGroup b) =>
    _finishedSortKey(b).compareTo(_finishedSortKey(a));

DateTime _finishedSortKey(GeoGroup group) =>
    group.endedAt ?? group.endsAt ?? group.startsAt;

/// Локальная схема приглашения. Позже её можно заменить на HTTPS-ссылку.
String buildGroupInviteLink(GeoGroup group) {
  return 'geo-groups://join'
      '?groupId=${Uri.encodeQueryComponent(group.id)}'
      '&inviteToken=${Uri.encodeQueryComponent(group.qrInviteToken)}';
}

/// @deprecated Используйте buildGroupInviteLink.
String buildGroupInvitePayload(GeoGroup group) {
  return buildGroupInviteLink(group);
}

class GroupInvitePayload {
  const GroupInvitePayload({required this.groupId, required this.inviteToken});

  final String groupId;
  final String inviteToken;
}

enum QrInviteClaimResult {
  added,
  empty,
  unrecognized,
  unavailable,
  invalidToken,
  inactive,
  organizer,
  alreadyMember,
  alreadyPending,
}

class QrInviteInspection {
  const QrInviteInspection(this.result, [this.group]);

  final QrInviteClaimResult result;
  final GeoGroup? group;
}

String messageForQrInviteClaim(QrInviteClaimResult result) {
  return switch (result) {
    QrInviteClaimResult.added => 'Приглашение добавлено в список.',
    QrInviteClaimResult.empty => 'Вставьте данные приглашения',
    QrInviteClaimResult.unrecognized => 'Не удалось распознать приглашение',
    QrInviteClaimResult.unavailable =>
      'Приглашение недоступно на этом устройстве',
    QrInviteClaimResult.invalidToken => 'Приглашение недействительно',
    QrInviteClaimResult.inactive => 'Срок действия приглашения завершён',
    QrInviteClaimResult.organizer => 'Организатор уже участвует в этой группе',
    QrInviteClaimResult.alreadyMember => 'Вы уже участвуете в этой группе',
    QrInviteClaimResult.alreadyPending => 'Это приглашение уже есть в списке',
  };
}

/// Разбирает строку, которую создаёт [buildGroupInviteLink].
GroupInvitePayload? parseGroupInvitePayload(String rawPayload) {
  final uri = Uri.tryParse(rawPayload.trim());
  if (uri == null || uri.scheme != 'geo-groups' || uri.host != 'join') {
    return null;
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    return null;
  }
  if (uri.fragment.isNotEmpty || uri.queryParameters.length != 2) {
    return null;
  }
  final groupId = uri.queryParameters['groupId'];
  final inviteToken = uri.queryParameters['inviteToken'];
  if (groupId == null ||
      groupId.isEmpty ||
      inviteToken == null ||
      inviteToken.isEmpty) {
    return null;
  }
  return GroupInvitePayload(groupId: groupId, inviteToken: inviteToken);
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

List<GroupMemberLocation> _memberLocationsFor(
  List<GroupMember> members,
  List<GroupMemberLocation> locations,
) {
  final memberIds = members.map((member) => member.id).toSet();
  final seen = <String>{};
  final copy = <GroupMemberLocation>[];
  for (final location in locations) {
    if (!memberIds.contains(location.memberId)) {
      throw ArgumentError.value(
        location.memberId,
        'memberLocations',
        'Позиция относится к участнику, которого нет в группе',
      );
    }
    if (!seen.add(location.memberId)) {
      throw ArgumentError.value(
        location.memberId,
        'memberLocations',
        'У участника может быть только одна позиция',
      );
    }
    copy.add(location);
  }
  return copy;
}

List<GeoGroup> _demoGroups() {
  final now = DateTime.now();
  return [
    GeoGroup(
      id: 'picnic',
      name: 'Пикник в парке',
      createdAt: now.subtract(const Duration(days: 20)),
      startsAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 15, 18, 0),
      members: [
        _activeMember(id: 'maria', name: 'Мария', distanceMeters: 120),
        _activeMember(id: 'alexey', name: 'Алексей', distanceMeters: 340),
        _activeMember(id: 'elena', name: 'Елена', distanceMeters: 680),
        _currentUser(),
      ],
      memberLocations: [
        GroupMemberLocation(
          memberId: 'maria',
          coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
          updatedAt: now.subtract(const Duration(minutes: 4)),
        ),
        GroupMemberLocation(
          memberId: 'alexey',
          coordinate: GeoCoordinate(latitude: 55.7601, longitude: 37.6186),
          updatedAt: now.subtract(const Duration(minutes: 7)),
        ),
        GroupMemberLocation(
          memberId: 'elena',
          coordinate: GeoCoordinate(latitude: 55.7490, longitude: 37.6050),
          updatedAt: now.subtract(const Duration(minutes: 11)),
        ),
        GroupMemberLocation(
          memberId: defaultDemoUserId,
          coordinate: GeoCoordinate(latitude: 55.7539, longitude: 37.6208),
          updatedAt: now.subtract(const Duration(minutes: 2)),
        ),
      ],
    ),
    GeoGroup(
      id: 'concert',
      name: 'Концерт',
      createdAt: now.subtract(const Duration(days: 20)),
      startsAt: now.subtract(const Duration(days: 20)),
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
      startsAt: now.subtract(const Duration(days: 20)),
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
      startsAt: now.subtract(const Duration(minutes: 30)),
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
      startsAt: now.subtract(const Duration(days: 3)),
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
      startsAt: now.subtract(const Duration(days: 2)),
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
      startsAt: now.subtract(const Duration(days: 12)),
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
      startsAt: now.subtract(const Duration(hours: 5)),
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
      startsAt: now.subtract(const Duration(days: 1)),
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
      startsAt: now.subtract(const Duration(days: 2)),
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
