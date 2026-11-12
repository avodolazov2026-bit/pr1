import 'package:flutter/material.dart';

class GroupMember {
  GroupMember({
    required this.name,
    required this.distanceMeters,
    this.isCurrentUser = false,
    this.isOrganizer = false,
    this.hasLeftGroup = false,
  });

  final String name;
  final int distanceMeters;
  final bool isCurrentUser;
  final bool isOrganizer;

  /// Участник остаётся в составе группы, но больше не делится геопозицией.
  bool hasLeftGroup;
}

class GeoGroup {
  GeoGroup({
    required this.name,
    required this.createdAt,
    required this.endsAt,
    required this.members,
    this.createdByCurrentUser = false,
  });

  final String name;
  final DateTime createdAt;
  final DateTime endsAt;
  final List<GroupMember> members;
  final bool createdByCurrentUser;

  bool get currentUserHasLeft =>
      members.any((member) => member.isCurrentUser && member.hasLeftGroup);

  int get memberCount => members.length;

  bool get isActive => endsAt.isAfter(DateTime.now());

  String get activeUntilLabel => formatGroupDateTime(endsAt);
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

class GroupsStore {
  GroupsStore._() {
    groups.addAll(_demoGroups());
  }

  static final GroupsStore instance = GroupsStore._();

  final List<GeoGroup> groups = <GeoGroup>[];

  void addGroup(GeoGroup group) {
    groups.insert(0, group);
  }

  List<GeoGroup> get myGroups =>
      groups.where((group) => !group.currentUserHasLeft).toList();

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

String membersLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  final noun = (mod10 == 1 && mod100 != 11)
      ? 'участник'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
          ? 'участника'
          : 'участников';
  return '$count $noun';
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
    name: 'Вы',
    distanceMeters: 0,
    isCurrentUser: true,
    isOrganizer: organizer,
  );
}

List<GeoGroup> _demoGroups() {
  final now = DateTime.now();
  return [
    GeoGroup(
      name: 'Пикник в парке',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 15, 18, 0),
      members: [
        GroupMember(name: 'Мария', distanceMeters: 120),
        GroupMember(name: 'Алексей', distanceMeters: 340),
        GroupMember(name: 'Елена', distanceMeters: 680),
        _currentUser(),
      ],
    ),
    GeoGroup(
      name: 'Концерт',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 16, 23, 30),
      members: [
        GroupMember(name: 'Дмитрий', distanceMeters: 85),
        GroupMember(name: 'Ольга', distanceMeters: 210),
        _currentUser(),
      ],
    ),
    GeoGroup(
      name: 'Поездка за город',
      createdAt: now.subtract(const Duration(days: 20)),
      endsAt: _upcoming(11, 17, 20, 0),
      members: [
        GroupMember(name: 'Игорь', distanceMeters: 150),
        GroupMember(name: 'Анна', distanceMeters: 420),
        GroupMember(name: 'Сергей', distanceMeters: 760),
        GroupMember(name: 'Виктория', distanceMeters: 1100),
        _currentUser(),
      ],
    ),
    GeoGroup(
      name: 'Сборы у фонтана',
      createdAt: now.subtract(const Duration(minutes: 30)),
      endsAt: now.add(const Duration(hours: 6)),
      createdByCurrentUser: true,
      members: [
        GroupMember(name: 'Мария', distanceMeters: 90),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      name: 'Вечерняя прогулка',
      createdAt: now.subtract(const Duration(days: 3)),
      endsAt: now.add(const Duration(days: 2)),
      createdByCurrentUser: true,
      members: [
        GroupMember(name: 'Алексей', distanceMeters: 250),
        GroupMember(name: 'Елена', distanceMeters: 500),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      name: 'Кино',
      createdAt: now.subtract(const Duration(days: 2)),
      endsAt: now.subtract(const Duration(hours: 3)),
      createdByCurrentUser: true,
      members: [
        GroupMember(name: 'Дмитрий', distanceMeters: 40),
        _currentUser(organizer: true),
      ],
    ),
    GeoGroup(
      name: 'Поездка к друзьям',
      createdAt: now.subtract(const Duration(days: 12)),
      endsAt: now.add(const Duration(days: 4)),
      createdByCurrentUser: true,
      members: [
        GroupMember(name: 'Игорь', distanceMeters: 180),
        GroupMember(name: 'Анна', distanceMeters: 640),
        _currentUser(organizer: true),
      ],
    ),
  ];
}
