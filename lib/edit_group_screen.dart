import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/invite_source_sheet.dart';

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
  late final List<_MemberDraft> _members;
  DateTime? _date;
  TimeOfDay? _time;
  late bool _indefinite;
  String? _nameError;
  String? _scheduleError;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameController = TextEditingController(text: group.name);
    _originallyIndefinite = group.endsAt == null;
    _indefinite = _originallyIndefinite;
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

  DateTime? get _endsAt {
    final date = _date;
    final time = _time;
    if (date == null || time == null) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  bool get _keepsIndefinite => _originallyIndefinite && _indefinite;

  void _rejectSchedule(String message) {
    setState(() => _scheduleError = message);
  }

  void _acceptSchedule(DateTime next) {
    final issue = validateEndsAtUpdate(
      originalEndsAt: widget.group.endsAt,
      nextEndsAt: next,
    );
    if (issue != null) {
      _rejectSchedule(issue);
      return;
    }
    setState(() => _scheduleError = null);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final original = widget.group.endsAt?.toLocal();
    var lastDate = DateTime(now.year + 2, now.month, now.day);
    if (original != null) {
      lastDate = DateTime(original.year, original.month, original.day);
    }
    if (lastDate.isBefore(today)) {
      _rejectSchedule('Нельзя выбрать дату и время в прошлом');
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
      _scheduleError = null;
    });
    final endsAt = _endsAt;
    if (endsAt != null) {
      _acceptSchedule(endsAt);
    }
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
      _scheduleError = null;
    });
    final endsAt = _endsAt;
    if (endsAt != null) {
      _acceptSchedule(endsAt);
    }
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

  Future<void> _invitePeople() async {
    final excluded = _members
        .where(
          (member) =>
              member.isOrganizer ||
              member.status == MembershipStatus.active ||
              member.status == MembershipStatus.invited,
        )
        .map((member) => member.id)
        .toSet();
    final selected = await showInviteParticipants(
      context: context,
      excludedIds: excluded,
      initiallySelectedIds: const <String>{},
      group: widget.group,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      for (final person in selected) {
        final existing = _members.where((member) => member.id == person.id);
        if (existing.isEmpty) {
          _members.add(
            _MemberDraft(
              id: person.id,
              name: person.name,
              originalStatus: MembershipStatus.invited,
              status: MembershipStatus.invited,
            ),
          );
          continue;
        }
        final member = existing.first;
        if (member.status == MembershipStatus.active ||
            member.status == MembershipStatus.invited ||
            member.isOrganizer) {
          continue;
        }
        member.status = MembershipStatus.invited;
      }
    });
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название группы');
      return;
    }

    DateTime? endsAt;
    if (!_keepsIndefinite) {
      endsAt = _endsAt;
      if (endsAt == null) {
        _rejectSchedule('Выберите дату и время завершения');
        return;
      }
    }

    final issue = validateEndsAtUpdate(
      originalEndsAt: widget.group.endsAt,
      nextEndsAt: endsAt,
    );
    if (issue != null) {
      _rejectSchedule(issue);
      return;
    }

    for (final member in _members) {
      member.persisted?.status = member.status;
    }
    final error = widget.group.updateDetails(
      name: name,
      endsAt: endsAt,
      members: _membersToSave(),
    );
    if (error != null) {
      for (final member in _members) {
        member.persisted?.status = member.originalStatus;
      }
      setState(() => _scheduleError = error);
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
    _MemberDraft? organizer;
    for (final member in _members) {
      if (member.role == MemberRole.organizer) {
        organizer = member;
        break;
      }
    }
    final organizerName = organizer?.name ?? currentDemoUser.name;
    final activeMembers = _members.where(
      (member) =>
          member.status == MembershipStatus.active && !member.isOrganizer,
    );
    final invited = _members.where(
      (member) => member.status == MembershipStatus.invited,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать группу'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Название группы',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _keepsIndefinite,
              title: const Text('Бессрочная группа'),
              subtitle: Text(
                'Группа не завершится автоматически по времени',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onChanged: _originallyIndefinite
                  ? (value) {
                      setState(() {
                        _indefinite = value ?? false;
                        _scheduleError = null;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _keepsIndefinite ? null : _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _date == null
                    ? 'Дата завершения'
                    : 'Дата завершения: ${formatGroupDate(_date!)}',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _keepsIndefinite ? null : _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                _time == null
                    ? 'Время завершения'
                    : 'Время завершения: ${formatGroupTime(_time!)}',
              ),
            ),
            if (!_keepsIndefinite && _scheduleError != null) ...[
              const SizedBox(height: 8),
              Text(
                _scheduleError!,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
            ] else if (!_keepsIndefinite && endsAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Активно до: ${formatGroupDateTime(endsAt)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!_originallyIndefinite) ...[
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
              leading: CircleAvatar(
                child: Text(memberInitials(organizerName)),
              ),
              title: Text('$organizerName — организатор'),
            ),
            for (final member in activeMembers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(memberInitials(member.name)),
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
                  leading: CircleAvatar(
                    child: Text(memberInitials(member.name)),
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
          child: FilledButton(
            onPressed: _save,
            child: const Text('Сохранить изменения'),
          ),
        ),
      ),
    );
  }
}
