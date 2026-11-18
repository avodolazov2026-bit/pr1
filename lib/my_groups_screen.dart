import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_screen.dart';

class MyGroupsScreen extends StatefulWidget {
  const MyGroupsScreen({super.key});

  @override
  State<MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends State<MyGroupsScreen> {
  Future<void> _openGroup(GeoGroup group) async {
    final leftGroupName = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => GroupScreen(
          group: group,
          onChanged: () {
            if (mounted) {
              setState(() {});
            }
          },
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
    final membership = GroupsStore.instance.myGroups;
    final active = membership.where((group) => group.isActive).toList()
      ..sort(compareActiveGroups);
    final upcoming = membership.where((group) => group.isUpcoming).toList()
      ..sort(compareUpcomingGroups);
    final finished = membership.where((group) => group.isFinished).toList()
      ..sort(compareFinishedGroups);
    final sections = <({String title, List<GeoGroup> groups, Color color})>[
      (title: 'Активные', groups: active, color: activeGroupAccent),
      (title: 'Будущие', groups: upcoming, color: upcomingGroupAccent),
      (title: 'Завершённые', groups: finished, color: finishedGroupAccent),
    ].where((section) => section.groups.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Мои группы')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final section in sections) ...[
              _SectionHeader(
                title: section.title,
                count: section.groups.length,
                color: section.color,
              ),
              const SizedBox(height: 12),
              for (final group in section.groups) ...[
                GroupCard(group: group, onTap: () => _openGroup(group)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(title, style: style),
        const SizedBox(width: 8),
        Text('$count', style: style),
      ],
    );
  }
}
