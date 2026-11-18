import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_screen.dart';

class MyGroupsScreen extends StatefulWidget {
  const MyGroupsScreen({super.key, this.now});

  /// Часы для выбора ближайшего перехода. В приложении это [DateTime.now].
  final DateTime Function()? now;

  @override
  State<MyGroupsScreen> createState() => _MyGroupsScreenState();
}

class _MyGroupsScreenState extends State<MyGroupsScreen>
    with WidgetsBindingObserver {
  Timer? _statusRefreshTimer;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  List<GeoGroup> _visibleGroups() => GroupsStore.instance.myGroups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleStatusRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduleStatusRefresh();
    });
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }
    setState(() {});
    _scheduleStatusRefresh();
  }

  void _scheduleStatusRefresh() {
    _statusRefreshTimer?.cancel();
    _statusRefreshTimer = null;
    final now = _now();
    final next = nextGroupStatusChange(_visibleGroups(), now);
    if (next == null) {
      return;
    }
    var delay = next.difference(now);
    if (delay <= Duration.zero) {
      delay = Duration.zero;
    }
    _statusRefreshTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      setState(() {});
      _scheduleStatusRefresh();
    });
  }

  Future<void> _openGroup(GeoGroup group) async {
    final leftGroupName = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => GroupScreen(
          group: group,
          onChanged: () {
            if (!mounted) {
              return;
            }
            setState(() {});
            _scheduleStatusRefresh();
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleStatusRefresh();
    if (leftGroupName == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Вы покинули группу „$leftGroupName“')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membership = _visibleGroups();
    final active = membership.where((group) => group.isActive).toList()
      ..sort(compareActiveGroups);
    final upcoming = membership.where((group) => group.isUpcoming).toList()
      ..sort(compareUpcomingGroups);
    final finished = membership.where((group) => group.isFinished).toList()
      ..sort(compareFinishedGroups);
    final sections =
        <({String title, String? note, List<GeoGroup> groups, Color color})>[
          (
            title: 'Активные',
            note: 'Группы, в которых я участвую.',
            groups: active,
            color: activeGroupAccent,
          ),
          (
            title: 'Будущие',
            note: null,
            groups: upcoming,
            color: upcomingGroupAccent,
          ),
          (
            title: 'Завершённые',
            note: null,
            groups: finished,
            color: finishedGroupAccent,
          ),
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
              if (section.note != null) ...[
                const SizedBox(height: 4),
                Text(
                  section.note!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
