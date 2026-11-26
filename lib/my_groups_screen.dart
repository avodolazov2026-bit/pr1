import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_period.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/theme/app_theme.dart';

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
  GroupPeriod _period = GroupPeriod.week;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  List<GeoGroup> _membership() => GroupsStore.instance.myGroups;

  List<GeoGroup> _visibleGroups() {
    final now = _now();
    return [
      for (final group in _membership())
        if (groupStartsInPeriod(group.startsAt, _period, now)) group,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GroupsStore.instance.addListener(_onGroupsChanged);
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
    GroupsStore.instance.removeListener(_onGroupsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onGroupsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleStatusRefresh();
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
    final membership = _membership();
    final visible = _visibleGroups();
    final active = visible.where((group) => group.isActive).toList()
      ..sort(compareActiveGroups);
    final upcoming = visible.where((group) => group.isUpcoming).toList()
      ..sort(compareUpcomingGroups);
    final finished = visible.where((group) => group.isFinished).toList()
      ..sort(compareFinishedGroups);
    final sections =
        <({String title, String? note, List<GeoGroup> groups})>[
          (
            title: 'Активные',
            note: 'Группы, в которых я участвую.',
            groups: active,
          ),
          (title: 'Будущие', note: null, groups: upcoming),
          (title: 'Завершённые', note: null, groups: finished),
        ].where((section) => section.groups.isNotEmpty).toList();
    final periodIsEmpty = membership.isNotEmpty && sections.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Мои группы')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: GroupPeriodSelector(
                period: _period,
                labels: myGroupsPeriodLabels,
                onChanged: (period) {
                  setState(() => _period = period);
                  _scheduleStatusRefresh();
                },
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: membership.isEmpty
                  ? const Center(child: Text('Групп пока нет'))
                  : periodIsEmpty
                  ? const Center(child: Text('В выбранном периоде групп нет'))
                  : Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.surfaceSubtleDark
                          : AppColors.surfaceSubtle,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        children: [
                          for (var index = 0; index < sections.length; index++) ...[
                            AppSectionHeader(
                              title: sections[index].title,
                              subtitle: sections[index].note,
                              trailing: Text(
                                '${sections[index].groups.length}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            for (
                              var groupIndex = 0;
                              groupIndex < sections[index].groups.length;
                              groupIndex++
                            ) ...[
                              GroupCard(
                                group: sections[index].groups[groupIndex],
                                onTap: () => _openGroup(
                                  sections[index].groups[groupIndex],
                                ),
                              ),
                              if (groupIndex != sections[index].groups.length - 1)
                                const SizedBox(height: 10),
                            ],
                            if (index != sections.length - 1)
                              const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
