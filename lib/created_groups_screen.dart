import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_card.dart';
import 'package:geo_groups/group_screen.dart';
import 'package:geo_groups/invite_source_sheet.dart';

class CreatedGroupsScreen extends StatefulWidget {
  const CreatedGroupsScreen({super.key});

  @override
  State<CreatedGroupsScreen> createState() => _CreatedGroupsScreenState();
}

class _CreatedGroupsScreenState extends State<CreatedGroupsScreen> {
  GroupPeriod _period = GroupPeriod.week;

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

    final group = GeoGroup(
      id: GroupsStore.instance.nextId('group'),
      name: draft.name,
      createdAt: DateTime.now(),
      endsAt: draft.endsAt,
      createdByUserId: currentDemoUserId,
      qrInviteToken: GroupsStore.instance.nextQrInviteToken(),
      members: [
        GroupMember(
          id: currentDemoUser.id,
          name: currentDemoUser.name,
          role: MemberRole.organizer,
          status: MembershipStatus.active,
        ),
        for (final person in draft.invited)
          GroupMember(
            id: person.id,
            name: person.name,
            status: MembershipStatus.invited,
          ),
      ],
    );
    GroupsStore.instance.addGroup(group);
    GroupsStore.instance.syncInvitations(group);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Группа создана')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final groups = GroupsStore.instance.createdGroups(_period);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Созданные группы'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton.filled(
              tooltip: 'Добавить группу',
              onPressed: _addGroup,
              icon: const Icon(Icons.add),
              iconSize: 36,
              style: IconButton.styleFrom(
                fixedSize: const Size(72, 72),
              ),
            ),
            TextButton(
              onPressed: _addGroup,
              child: Text('Добавить группу', style: textTheme.titleMedium),
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
                      itemCount: groups.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final group = groups[index];
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
    required this.endsAt,
    required this.invited,
  });

  final String name;
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
  DateTime? _date;
  TimeOfDay? _time;
  bool _indefinite = false;
  final List<DirectoryPerson> _invited = <DirectoryPerson>[];
  String? _nameError;
  String? _scheduleError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _date = picked;
      _scheduleError = null;
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
      _scheduleError = null;
    });
  }

  DateTime? get _endsAt {
    final date = _date;
    final time = _time;
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

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название группы');
      return;
    }

    DateTime? endsAt;
    if (!_indefinite) {
      endsAt = _endsAt;
      if (endsAt == null) {
        setState(() => _scheduleError = 'Выберите дату и время завершения');
        return;
      }
      if (!endsAt.isAfter(DateTime.now())) {
        setState(
          () => _scheduleError = 'Нельзя выбрать дату и время в прошлом',
        );
        return;
      }
    }

    Navigator.of(context).pop(
      _GroupDraft(
        name: name,
        endsAt: endsAt,
        invited: List<DirectoryPerson>.of(_invited),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = _endsAt;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
              value: _indefinite,
              title: const Text('Бессрочная группа'),
              subtitle: Text(
                'Группа не завершится автоматически по времени',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _indefinite = value ?? false;
                  _scheduleError = null;
                });
              },
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _indefinite ? null : _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _date == null
                    ? 'Дата завершения'
                    : 'Дата завершения: ${formatGroupDate(_date!)}',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _indefinite ? null : _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                _time == null
                    ? 'Время завершения'
                    : 'Время завершения: ${formatGroupTime(_time!)}',
              ),
            ),
            if (!_indefinite && _scheduleError != null) ...[
              const SizedBox(height: 8),
              Text(
                _scheduleError!,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
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
                    onPressed: _submit,
                    child: const Text('Создать'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

