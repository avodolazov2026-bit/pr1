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
    final sections = <(String, List<GeoGroup>)>[
      ('Активные', active),
      ('Запланированные', upcoming),
      ('Завершённые', finished),
    ].where((section) => section.$2.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Мои группы')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final section in sections) ...[
              Text(section.$1, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final group in section.$2) ...[
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
