import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_schedule_form.dart';
import 'package:geo_groups/invite_source_sheet.dart';
import 'package:geo_groups/user_profile.dart';

class EditGroupScreen extends StatefulWidget {
  const EditGroupScreen({super.key, required this.group});

  final GeoGroup group;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _MemberDraft {
  _MemberDraft({
    required this.id,
    required this.name,
    required this.originalStatus,
    required this.status,
    this.role = MemberRole.participant,
    this.distanceMeters,
    this.persisted,
  });

  final String id;
  final String name;
  final MembershipStatus originalStatus;
  MembershipStatus status;
  final MemberRole role;
  final int? distanceMeters;
  final GroupMember? persisted;

  bool get isOrganizer =>
      role == MemberRole.organizer || id == currentDemoUserId;
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  late final TextEditingController _nameController;
  late final bool _originallyIndefinite;
  late final bool _canChangeStart;
  late final List<_MemberDraft> _members;
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _date;
  TimeOfDay? _time;
  late bool _indefinite;
  String? _extraError;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameController = TextEditingController(text: group.name);
    _originallyIndefinite = group.endsAt == null;
    _canChangeStart = group.isUpcoming;
    _indefinite = _originallyIndefinite;
    final startsAt = group.startsAt.toLocal();
    _startDate = DateTime(startsAt.year, startsAt.month, startsAt.day);
    _startTime = TimeOfDay(hour: startsAt.hour, minute: startsAt.minute);
    final endsAt = group.endsAt?.toLocal();
    if (endsAt != null) {
      _date = DateTime(endsAt.year, endsAt.month, endsAt.day);
      _time = TimeOfDay(hour: endsAt.hour, minute: endsAt.minute);
    }
    _members = [
      for (final member in group.members)
        _MemberDraft(
          id: member.id,
          name: member.name,
          originalStatus: member.status,
          status: member.status,
          role: member.role,
          distanceMeters: member.distanceMeters,
          persisted: member,
        ),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime? get _startsAt {
    final date = _startDate;
    final time = _startTime;
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? get _endsAt {
    final date = _date;
    final time = _time;
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  bool get _hidesEnd => _indefinite;

  DateTime get _nextStartsAt => _startsAt ?? widget.group.startsAt;

  GroupFormIssue? _formIssue() {
    final endsAt = _hidesEnd ? null : _endsAt;
    return groupFormIssue(
      name: _nameController.text,
      originalStartsAt: widget.group.startsAt,
      nextStartsAt: _nextStartsAt,
      originalEndsAt: widget.group.endsAt,
      nextEndsAt: endsAt,
      upcoming: _canChangeStart,
      endOmitted: !_hidesEnd && endsAt == null,
      extraError: _extraError,
    );
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 2, now.month, now.day);
    var initial = _startDate ?? today;
    if (initial.isBefore(today)) {
      initial = today;
    }
    if (initial.isAfter(lastDate)) {
      initial = lastDate;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDate,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _startDate = picked;
      _extraError = null;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _startTime = picked;
      _extraError = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final original = widget.group.endsAt?.toLocal();
    var lastDate = DateTime(now.year + 2, now.month, now.day);
    if (!_canChangeStart && original != null) {
      lastDate = DateTime(original.year, original.month, original.day);
    }
    if (lastDate.isBefore(today)) {
      setState(() => _extraError = 'Нельзя выбрать дату и время в прошлом');
      return;
    }

    var initial = _date ?? today;
    if (initial.isBefore(today)) {
      initial = today;
    }
    if (initial.isAfter(lastDate)) {
      initial = lastDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDate,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _date = picked;
      _extraError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _time = picked;
      _extraError = null;
    });
  }

  Future<void> _confirmExclude(_MemberDraft member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final errorColor = Theme.of(dialogContext).colorScheme.error;
        return AlertDialog(
          title: const Text('Исключить участника?'),
          content: const Text(
            'Участник перестанет видеть геолокацию группы, а другие участники перестанут видеть его геолокацию.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: errorColor),
              child: const Text('Исключить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => member.status = MembershipStatus.removedByOrganizer);
  }

  void _removeInvite(_MemberDraft member) {
    setState(() {
      if (member.persisted == null ||
          member.originalStatus == MembershipStatus.invited) {
        _members.remove(member);
        return;
      }
      member.status = member.originalStatus;
    });
  }

  Future<void> _invitePeople() {
    return showGroupInviteOptions(
      context: context,
      group: widget.group,
    );
  }

  List<GroupMember> _membersToSave() {
    return [
      for (final member in _members)
        if (member.persisted != null)
          member.persisted!
        else
          GroupMember(
            id: member.id,
            name: member.name,
            role: member.role,
            status: member.status,
          ),
    ];
  }

  void _save() {
    if (_formIssue() != null) {
      return;
    }

    final startsAt = _nextStartsAt;
    final endsAt = _hidesEnd ? null : _endsAt;
    for (final member in _members) {
      member.persisted?.status = member.status;
    }
    final error = widget.group.updateDetails(
      name: _nameController.text.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      members: _membersToSave(),
    );
    if (error != null) {
      for (final member in _members) {
        member.persisted?.status = member.originalStatus;
      }
      setState(() => _extraError = error);
      return;
    }

    GroupsStore.instance.syncInvitations(widget.group);
    Navigator.of(context).pop(true);
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
    _MemberDraft? organizer;
    for (final member in _members) {
      if (member.role == MemberRole.organizer) {
        organizer = member;
        break;
      }
    }
    final organizerName = organizer?.name ?? currentDemoUser.name;
    final organizerMember = organizer?.persisted;
    final activeMembers = _members.where(
      (member) =>
          member.status == MembershipStatus.active && !member.isOrganizer,
    );
    final invited = _members.where(
      (member) => member.status == MembershipStatus.invited,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать группу')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
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
              onChanged: (_) => setState(() => _extraError = null),
            ),
            const SizedBox(height: 16),
            if (_canChangeStart) ...[
              ScheduleOutlinedButton(
                onPressed: _pickStartDate,
                icon: Icons.event_outlined,
                label: _startDate == null
                    ? 'Дата начала'
                    : 'Дата начала: ${formatGroupDate(_startDate!)}',
                invalid: startInvalid,
              ),
              const SizedBox(height: 12),
              ScheduleOutlinedButton(
                onPressed: _pickStartTime,
                icon: Icons.schedule,
                label: _startTime == null
                    ? 'Время начала'
                    : 'Время начала: ${formatGroupTime(_startTime!)}',
                invalid: startInvalid,
              ),
              if (issue?.field == GroupScheduleField.start) ...[
                const SizedBox(height: 8),
                ScheduleIssueText(issue!.message),
              ],
            ] else
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Начало группы',
                  border: OutlineInputBorder(),
                  helperText: 'Время начала активной группы нельзя изменить.',
                ),
                child: Text(formatGroupDateTime(widget.group.startsAt)),
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
              onChanged: _canChangeStart || _originallyIndefinite
                  ? (value) {
                      setState(() {
                        _indefinite = value ?? false;
                        _extraError = null;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 4),
            ScheduleOutlinedButton(
              onPressed: _hidesEnd ? null : _pickDate,
              icon: Icons.calendar_today,
              label: _date == null
                  ? 'Дата завершения'
                  : 'Дата завершения: ${formatGroupDate(_date!)}',
              invalid: endInvalid,
            ),
            const SizedBox(height: 12),
            ScheduleOutlinedButton(
              onPressed: _hidesEnd ? null : _pickTime,
              icon: Icons.schedule,
              label: _time == null
                  ? 'Время завершения'
                  : 'Время завершения: ${formatGroupTime(_time!)}',
              invalid: endInvalid,
            ),
            if (issue?.field == GroupScheduleField.end) ...[
              const SizedBox(height: 8),
              ScheduleIssueText(issue!.message),
            ] else if (!_hidesEnd && endsAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Активно до: ${formatGroupDateTime(endsAt)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!_canChangeStart && !_originallyIndefinite) ...[
              const SizedBox(height: 8),
              Text(
                'Продлить срок группы нельзя: это потребует нового согласия участников.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('Участники', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: organizerMember == null
                  ? CircleAvatar(child: Text(memberInitials(organizerName)))
                  : ProfileAvatar(
                      avatarId: organizerMember.displayAvatarId,
                      displayName: organizerMember.name,
                      radius: 20,
                    ),
              title: Text('$organizerName — организатор'),
            ),
            for (final member in activeMembers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ProfileAvatar(
                  avatarId:
                      member.persisted?.displayAvatarId ?? defaultAvatarId,
                  displayName: member.name,
                  radius: 20,
                ),
                title: Text(member.name),
                subtitle: Text(
                  'Участник',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Исключить',
                  onPressed: () => _confirmExclude(member),
                  icon: const Icon(Icons.person_remove_outlined),
                ),
              ),
            if (invited.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Приглашены', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final member in invited)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ProfileAvatar(
                    avatarId:
                        member.persisted?.displayAvatarId ?? defaultAvatarId,
                    displayName: member.name,
                    radius: 20,
                  ),
                  title: Text(member.name),
                  subtitle: Text(
                    'Ожидает ответа',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить приглашение',
                    onPressed: () => _removeInvite(member),
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _invitePeople,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Пригласить участников'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: issue == null ? _save : null,
                child: const Text('Сохранить изменения'),
              ),
              if (issue != null) ...[
                const SizedBox(height: 8),
                ScheduleIssueText(issue.message, small: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
