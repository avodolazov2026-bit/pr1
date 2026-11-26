import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/auth_repository.dart';
import 'package:geo_groups/foreground_location_sharing.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_period.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_invitation_repository.dart';
import 'package:geo_groups/group_repository.dart';
import 'package:geo_groups/group_schedule_form.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/invite_source_sheet.dart';
import 'package:geo_groups/phone_auth_screen.dart';
import 'package:geo_groups/theme/app_theme.dart';
import 'package:geo_groups/user_profile.dart';

class CreatedGroupsScreen extends StatefulWidget {
  const CreatedGroupsScreen({super.key, this.auth, this.groups});

  final AuthRepository? auth;
  final GroupReadRepository? groups;

  @override
  State<CreatedGroupsScreen> createState() => _CreatedGroupsScreenState();
}

class _CreatedGroupsScreenState extends State<CreatedGroupsScreen>
    with WidgetsBindingObserver {
  GroupPeriod _period = GroupPeriod.week;
  Timer? _statusRefreshTimer;
  var _promptOpen = false;

  List<GeoGroup> _visibleGroups() =>
      GroupsStore.instance.createdGroups(_period);

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

  AuthRepository get _auth => widget.auth ?? const SupabaseAuthRepository();

  Future<void> _addGroup() async {
    final draft = await showModalBottomSheet<_GroupDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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

    final GroupReadRepository groups =
        widget.groups ?? defaultGroupRepository();
    final String groupId;
    try {
      groupId = await groups.createGroup(
        name: draft.name,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
      );
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }
    if (!mounted) {
      return;
    }

    final group = GeoGroup(
      id: groupId,
      name: draft.name,
      createdAt: DateTime.now(),
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      createdByUserId: creatorId,
      members: membersForNewGroup(
        creatorId: creatorId,
        creatorName: profile.displayName,
        creatorAvatarId: profile.avatarId,
      ),
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);
    notifySharingTargetsChanged();
    setState(() {});
    _scheduleStatusRefresh();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Группа создана')));
  }

  Future<void> _onCreateGroupPressed() async {
    if (_auth.current.needsPhoneSignIn) {
      await _promptPhoneSignIn();
      return;
    }
    _addGroup();
  }

  Future<void> _promptPhoneSignIn() async {
    if (_promptOpen || !mounted) {
      return;
    }
    _promptOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(phoneSignInDialogTitle),
            content: const Text(phoneSignInDialogMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Войти'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) {
        return;
      }
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => PhoneAuthScreen(auth: _auth),
        ),
      );
      if (signedIn == true && mounted) {
        setState(() {});
      }
    } finally {
      _promptOpen = false;
    }
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
              onPressed: _onCreateGroupPressed,
              icon: const Icon(Icons.add),
              iconSize: 36,
              style: IconButton.styleFrom(fixedSize: const Size(72, 72)),
            ),
            TextButton(
              onPressed: _onCreateGroupPressed,
              child: Text('Создать группу', style: textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
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
                      style: groupPeriodSegmentStyle(colorScheme),
                      onSelectionChanged: (selection) {
                        setState(() => _period = selection.first);
                        _scheduleStatusRefresh();
                      },
                    ),
                  ),
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
                        final canInvite =
                            group.currentUserIsActiveOrganizer &&
                            !group.isFinished;
                        return GroupCard(
                          group: group,
                          onTap: () => _openGroup(group),
                          onInvite: canInvite
                              ? () {
                                  showGroupInviteOptions(
                                    context: context,
                                    group: group,
                                    invitations:
                                        defaultGroupInvitationRepository(),
                                  );
                                }
                              : null,
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
  });

  final String name;
  final DateTime startsAt;
  final DateTime? endsAt;
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

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (pickedTime == null || !mounted) {
      return;
    }
    setState(() {
      _startDate = pickedDate;
      _startTime = pickedTime;
    });
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDate = _endDate ?? _startDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate.isBefore(today) ? today : currentDate,
      firstDate: today,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _endTime ?? _startTime,
    );
    if (pickedTime == null || !mounted) {
      return;
    }
    setState(() {
      _endDate = pickedDate;
      _endTime = pickedTime;
    });
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = _endsAt;
    final issue = _formIssue();

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
            AppTonalButton(
              onPressed: _pickStart,
              icon: Icons.event_outlined,
              label: 'Начало: ${formatGroupDateTime(_startsAt)}',
            ),
            if (issue?.field == GroupScheduleField.start) ...[
              const SizedBox(height: 8),
              _ScheduleError(issue!.message),
            ],
            const SizedBox(height: 10),
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
              side: BorderSide(
                color: _indefinite ? colorScheme.primary : colorScheme.outline,
              ),
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.primary;
                }
                return Colors.transparent;
              }),
              checkColor: colorScheme.onPrimary,
              title: const Text('Бессрочная группа'),
              subtitle: Text(
                'Группа не завершится автоматически по времени',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onChanged: (value) {
                setState(() => _indefinite = value ?? false);
              },
            ),
            const SizedBox(height: 10),
            AppTonalButton(
              onPressed: _indefinite ? null : _pickEnd,
              icon: Icons.event_outlined,
              label: endsAt == null
                  ? 'Окончание группы'
                  : 'Окончание: ${formatGroupDateTime(endsAt)}',
              placeholder: endsAt == null && !_indefinite,
            ),
            if (issue?.field == GroupScheduleField.end) ...[
              const SizedBox(height: 8),
              _ScheduleError(issue!.message),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
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
              _ScheduleError(issue.message),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
