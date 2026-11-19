import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_schedule_form.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/invite_source_sheet.dart';
import 'package:geo_groups/user_profile.dart';

class CreatedGroupsScreen extends StatefulWidget {
  const CreatedGroupsScreen({super.key});

  @override
  State<CreatedGroupsScreen> createState() => _CreatedGroupsScreenState();
}

class _CreatedGroupsScreenState extends State<CreatedGroupsScreen>
    with WidgetsBindingObserver {
  GroupPeriod _period = GroupPeriod.week;
  Timer? _statusRefreshTimer;

  List<GeoGroup> _visibleGroups() =>
      GroupsStore.instance.createdGroups(_period);

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
    final now = DateTime.now();
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

  Future<void> _addGroup() async {
    final draft = await showModalBottomSheet<_GroupDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _NewGroupSheet(),
    );
    if (draft == null || !mounted) {
      return;
    }

    final creatorId = currentDemoUserId;
    UserProfile profile;
    try {
      profile = await UserProfileStore.instance.loadProfile(
        userId: creatorId,
        fallbackName: currentDemoUser.name,
      );
    } catch (_) {
      profile = UserProfile(
        userId: creatorId,
        displayName: currentDemoUser.name,
        avatarId: defaultAvatarId,
      );
    }
    if (!mounted) {
      return;
    }

    final group = GeoGroup(
      id: GroupsStore.instance.nextId('group'),
      name: draft.name,
      createdAt: DateTime.now(),
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      createdByUserId: creatorId,
      qrInviteToken: GroupsStore.instance.nextQrInviteToken(),
      members: membersForNewGroup(
        creatorId: creatorId,
        creatorName: profile.displayName,
        creatorAvatarId: profile.avatarId,
        others: [
          for (final person in draft.invited)
            GroupMember(
              id: person.id,
              name: person.name,
              status: MembershipStatus.invited,
            ),
        ],
      ),
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);
    setState(() {});
    _scheduleStatusRefresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Группа создана')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final groups = _visibleGroups();

    return Scaffold(
      appBar: AppBar(title: const Text('Созданные группы')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton.filled(
              tooltip: 'Создать группу',
              onPressed: _addGroup,
              icon: const Icon(Icons.add),
              iconSize: 36,
              style: IconButton.styleFrom(fixedSize: const Size(72, 72)),
            ),
            TextButton(
              onPressed: _addGroup,
              child: Text('Создать группу', style: textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<GroupPeriod>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: GroupPeriod.week,
                      label: Text(
                        'Неделя',
                        style: TextStyle(
                          fontWeight: _period == GroupPeriod.week
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: GroupPeriod.month,
                      label: Text(
                        'Месяц',
                        style: TextStyle(
                          fontWeight: _period == GroupPeriod.month
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: GroupPeriod.year,
                      label: Text(
                        'Год',
                        style: TextStyle(
                          fontWeight: _period == GroupPeriod.year
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                  selected: {_period},
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return colorScheme.primaryContainer;
                      }
                      return colorScheme.surface;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return colorScheme.onPrimaryContainer;
                      }
                      return colorScheme.onSurfaceVariant;
                    }),
                  ),
                  onSelectionChanged: (selection) {
                    setState(() => _period = selection.first);
                    _scheduleStatusRefresh();
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: groups.isEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 72,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'За выбранный период групп пока нет',
                            style: textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: groups.length + 1,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Text(
                            'Созданные мной группы',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          );
                        }
                        final group = groups[index - 1];
                        return GroupCard(
                          group: group,
                          onTap: () => _openGroup(group),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupDraft {
  const _GroupDraft({
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.invited,
  });

  final String name;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<DirectoryPerson> invited;
}

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _nameController = TextEditingController();
  late DateTime _startDate;
  late TimeOfDay _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  bool _indefinite = false;
  final List<DirectoryPerson> _invited = <DirectoryPerson>[];

  @override
  void initState() {
    super.initState();
    final start = _roundedFutureStart(DateTime.now());
    _startDate = DateTime(start.year, start.month, start.day);
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime _roundedFutureStart(DateTime now) {
    final base = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final remainder = base.minute % 5;
    var result = base.add(
      Duration(minutes: remainder == 0 ? 0 : 5 - remainder),
    );
    if (!result.isAfter(now)) {
      result = result.add(const Duration(minutes: 5));
    }
    return result;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked == null) {
      return;
    }
    setState(() => _startDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _startTime = picked);
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: today,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked == null) {
      return;
    }
    setState(() => _endDate = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? _startTime,
    );
    if (picked == null) {
      return;
    }
    setState(() => _endTime = picked);
  }

  DateTime get _startsAt => DateTime(
    _startDate.year,
    _startDate.month,
    _startDate.day,
    _startTime.hour,
    _startTime.minute,
  );

  DateTime? get _endsAt {
    final date = _endDate;
    final time = _endTime;
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickInvitees() async {
    final selected = await showInviteParticipants(
      context: context,
      excludedIds: {currentDemoUserId},
      initiallySelectedIds: _invited.map((person) => person.id).toSet(),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _invited
        ..clear()
        ..addAll(selected);
    });
  }

  void _removeInvitee(DirectoryPerson person) {
    setState(() => _invited.remove(person));
  }

  GroupFormIssue? _formIssue() {
    final endsAt = _indefinite ? null : _endsAt;
    return groupFormIssue(
      name: _nameController.text,
      originalStartsAt: _startsAt,
      nextStartsAt: _startsAt,
      originalEndsAt: endsAt,
      nextEndsAt: endsAt,
      upcoming: true,
      endOmitted: !_indefinite && endsAt == null,
    );
  }

  void _submit() {
    if (_formIssue() != null) {
      return;
    }
    Navigator.of(context).pop(
      _GroupDraft(
        name: _nameController.text.trim(),
        startsAt: _startsAt,
        endsAt: _indefinite ? null : _endsAt,
        invited: List<DirectoryPerson>.of(_invited),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = _endsAt;
    final issue = _formIssue();
    final startInvalid =
        issue?.field == GroupScheduleField.start && issue!.highlightFields;
    final endInvalid =
        issue?.field == GroupScheduleField.end && issue!.highlightFields;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новая группа', style: textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Название группы',
                errorText: issue?.field == GroupScheduleField.name
                    ? issue!.message
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            ScheduleOutlinedButton(
              onPressed: _pickStartDate,
              icon: Icons.event_outlined,
              label: 'Дата начала: ${formatGroupDate(_startDate)}',
              invalid: startInvalid,
            ),
            const SizedBox(height: 12),
            ScheduleOutlinedButton(
              onPressed: _pickStartTime,
              icon: Icons.schedule,
              label: 'Время начала: ${formatGroupTime(_startTime)}',
              invalid: startInvalid,
            ),
            if (issue?.field == GroupScheduleField.start) ...[
              const SizedBox(height: 8),
              ScheduleIssueText(issue!.message),
            ],
            const SizedBox(height: 8),
            Text(
              'Начнётся ${formatGroupDateTime(_startsAt)}',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _indefinite,
              title: const Text('Бессрочная группа'),
              subtitle: Text(
                'Группа не завершится автоматически по времени',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onChanged: (value) {
                setState(() => _indefinite = value ?? false);
              },
            ),
            const SizedBox(height: 4),
            ScheduleOutlinedButton(
              onPressed: _indefinite ? null : _pickEndDate,
              icon: Icons.calendar_today,
              label: _endDate == null
                  ? 'Дата завершения'
                  : 'Дата завершения: ${formatGroupDate(_endDate!)}',
              invalid: endInvalid,
            ),
            const SizedBox(height: 12),
            ScheduleOutlinedButton(
              onPressed: _indefinite ? null : _pickEndTime,
              icon: Icons.schedule,
              label: _endTime == null
                  ? 'Время завершения'
                  : 'Время завершения: ${formatGroupTime(_endTime!)}',
              invalid: endInvalid,
            ),
            if (issue?.field == GroupScheduleField.end) ...[
              const SizedBox(height: 8),
              ScheduleIssueText(issue!.message),
            ] else if (!_indefinite && endsAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Активно до: ${formatGroupDateTime(endsAt)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Участники', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(memberInitials(currentDemoUser.name)),
              ),
              title: Text('${currentDemoUser.name} — организатор'),
            ),
            OutlinedButton.icon(
              onPressed: _pickInvitees,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Пригласить участников'),
            ),
            if (_invited.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Пока никто не приглашён',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final person in _invited)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(person.name),
                  subtitle: Text(
                    'Ожидает ответа',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Убрать',
                    onPressed: () => _removeInvitee(person),
                    icon: const Icon(Icons.close),
                  ),
                ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: issue == null ? _submit : null,
                    child: const Text('Создать'),
                  ),
                ),
              ],
            ),
            if (issue != null) ...[
              const SizedBox(height: 8),
              ScheduleIssueText(issue.message, small: true),
            ],
          ],
        ),
      ),
    );
  }
}
