import 'package:flutter/material.dart';

import 'package:geo_groups/group_screen.dart';

class MyGroupsScreen extends StatefulWidget {
  const MyGroupsScreen({super.key});

  @override
  State<MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends State<MyGroupsScreen> {
  /// Живёт всё время запуска: экран можно закрыть и открыть снова.
  static final _groups = <_Group>[
    _Group(
      name: 'Пикник в парке',
      activeUntil: '15 ноября, 18:00',
      members: [
        GroupMember(name: 'Мария', distanceMeters: 120),
        GroupMember(name: 'Алексей', distanceMeters: 340),
        GroupMember(name: 'Елена', distanceMeters: 680),
        GroupMember(name: 'Вы', distanceMeters: 0, isCurrentUser: true),
      ],
    ),
    _Group(
      name: 'Концерт',
      activeUntil: '16 ноября, 23:30',
      members: [
        GroupMember(name: 'Дмитрий', distanceMeters: 85),
        GroupMember(name: 'Ольга', distanceMeters: 210),
        GroupMember(name: 'Вы', distanceMeters: 0, isCurrentUser: true),
      ],
    ),
    _Group(
      name: 'Поездка за город',
      activeUntil: '17 ноября, 20:00',
      members: [
        GroupMember(name: 'Игорь', distanceMeters: 150),
        GroupMember(name: 'Анна', distanceMeters: 420),
        GroupMember(name: 'Сергей', distanceMeters: 760),
        GroupMember(name: 'Виктория', distanceMeters: 1100),
        GroupMember(name: 'Вы', distanceMeters: 0, isCurrentUser: true),
      ],
    ),
  ];

  List<_Group> get _visibleGroups =>
      _groups.where((group) => !group.currentUserHasLeft).toList();

  Future<void> _openGroup(_Group group) async {
    final leftGroupName = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => GroupScreen(
          name: group.name,
          activeUntil: group.activeUntil,
          members: group.members,
        ),
      ),
    );
    if (leftGroupName == null || !mounted) {
      return;
    }

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Вы покинули группу „$leftGroupName“')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final groups = _visibleGroups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои группы'),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: groups.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final group = groups[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openGroup(group),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name, style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Активно до: ${group.activeUntil}',
                        style: textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Участвую',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.people_outline,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _membersLabel(group.memberCount),
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Group {
  const _Group({
    required this.name,
    required this.activeUntil,
    required this.members,
  });

  final String name;
  final String activeUntil;
  final List<GroupMember> members;

  bool get currentUserHasLeft =>
      members.any((member) => member.isCurrentUser && member.hasLeftGroup);

  int get memberCount => members.length;
}

String _membersLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  final noun = (mod10 == 1 && mod100 != 11)
      ? 'участник'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
          ? 'участника'
          : 'участников';
  return '$count $noun';
}
