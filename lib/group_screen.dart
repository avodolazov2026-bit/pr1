import 'package:flutter/material.dart';

import 'package:geo_groups/edit_group_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_map_screen.dart';
import 'package:geo_groups/group_status_style.dart';
import 'package:geo_groups/map_time_format.dart';
import 'package:geo_groups/member_distance.dart';
import 'package:geo_groups/user_profile.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.group, this.onChanged, this.now});

  final GeoGroup group;
  final VoidCallback? onChanged;

  /// Фиксированный момент для подписей «обновлено …». В приложении это текущее время.
  final DateTime? now;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  Future<void> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final errorColor = Theme.of(dialogContext).colorScheme.error;
        return AlertDialog(
          title: const Text('Покинуть группу?'),
          content: const Text(
            'Вы перестанете делиться своей геопозицией с участниками этой группы.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: errorColor),
              child: const Text('Покинуть'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    for (final member in widget.group.members) {
      if (member.isCurrentUser) {
        member.status = MembershipStatus.left;
      }
    }
    widget.onChanged?.call();
    Navigator.of(context).pop(widget.group.name);
  }

  Future<void> _confirmEnd() async {
    final upcoming = widget.group.isUpcoming;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final errorColor = Theme.of(dialogContext).colorScheme.error;
        return AlertDialog(
          title: Text(upcoming ? 'Отменить группу?' : 'Завершить группу?'),
          content: Text(
            upcoming
                ? 'Группа не начнётся. Приглашения перестанут действовать, а отменённую группу нельзя будет изменить или восстановить.'
                : 'Обмен геолокацией для всех участников будет остановлен. Завершённую группу нельзя будет изменить или восстановить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: errorColor),
              child: Text(upcoming ? 'Отменить группу' : 'Завершить группу'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    GroupsStore.instance.endGroup(widget.group);
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => EditGroupScreen(group: widget.group),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    setState(() {});
    widget.onChanged?.call();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Изменения сохранены')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final canPrepare = !group.isFinished && group.currentUserIsActiveOrganizer;
    final canEdit = canPrepare;
    final canCancel = group.isUpcoming && group.currentUserIsActiveOrganizer;
    final canEnd = group.isActive && group.currentUserIsActiveOrganizer;
    final canLeave =
        group.isActive &&
        group.currentUserIsActiveMember &&
        !group.currentUserIsActiveOrganizer;
    final participants = _listedMembers(group);
    final invited = group.members
        .where((member) => member.status == MembershipStatus.invited)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Редактировать',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _GroupScheduleBlock(group: group),
            if (group.isUpcoming) ...[
              const SizedBox(height: 12),
              Text(
                'Карта станет доступна после начала группы',
                style: textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 24),
            Text('Участники', style: textTheme.titleMedium),
            if (group.canUseMap) ...[
              const SizedBox(height: 4),
              Text(
                'Расстояние от вас',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final member in participants)
              _MemberTile(
                member: member,
                lines: group.canUseMap && !member.isCurrentUser
                    ? _memberLocationLines(
                        group,
                        member,
                        widget.now ?? DateTime.now(),
                      )
                    : const [],
              ),
            if (invited.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Приглашены', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final member in invited)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ProfileAvatar(
                    avatarId: member.displayAvatarId,
                    displayName: member.name,
                    radius: 20,
                  ),
                  title: Text(member.name),
                  trailing: Text(
                    'Ожидает ответа',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: group.canUseMap || canCancel || canLeave
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (group.canUseMap)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) =>
                                  GroupMapScreen(group: group),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Открыть карту'),
                      ),
                    if (canEnd || canCancel || canLeave) ...[
                      if (group.canUseMap) const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: canEnd || canCancel
                            ? _confirmEnd
                            : () => _confirmLeave(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                        ),
                        icon: Icon(canLeave ? Icons.logout : Icons.event_busy),
                        label: Text(
                          canCancel
                              ? 'Отменить группу'
                              : canEnd
                              ? 'Завершить группу'
                              : 'Покинуть группу',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// Активные участники, включая текущего пользователя.
Iterable<GroupMember> _listedMembers(GeoGroup group) {
  return group.members.where(
    (member) => member.status == MembershipStatus.active,
  );
}

List<String> _memberLocationLines(
  GeoGroup group,
  GroupMember member,
  DateTime now,
) {
  final location = group.memberLocation(member.id);
  final own = group.memberLocation(currentDemoUserId);
  final meters = location == null || own == null
      ? null
      : geodesicDistanceMeters(
          own.coordinate.latitude,
          own.coordinate.longitude,
          location.coordinate.latitude,
          location.coordinate.longitude,
        );
  final distance = meters == null ? null : formatDistanceMeters(meters);
  return [
    distance ?? 'Нет данных о расстоянии',
    if (location != null) formatLocationUpdated(location.updatedAt, now: now),
  ];
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.lines});

  final GroupMember member;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      isThreeLine: lines.length > 1,
      leading: ProfileAvatar(
        avatarId: member.displayAvatarId,
        displayName: member.name,
        radius: 20,
      ),
      title: Text(member.name),
      trailing: member.isCurrentUser && member.role == MemberRole.organizer
          ? Text(
              'Организатор',
              style: textTheme.bodyMedium?.copyWith(color: color),
            )
          : null,
      subtitle: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    style: textTheme.bodyMedium?.copyWith(color: color),
                  ),
              ],
            ),
    );
  }
}

class _GroupScheduleBlock extends StatelessWidget {
  const _GroupScheduleBlock({required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = group.endsAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Расписание', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        _ScheduleLine(
          label: 'Начало',
          value: formatGroupSchedulePoint(group.startsAt),
        ),
        const SizedBox(height: 8),
        _ScheduleLine(
          label: 'Окончание',
          value: endsAt == null
              ? groupScheduleOpenEnded
              : formatGroupSchedulePoint(endsAt),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 108,
              child: Text(
                'Статус',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(child: GroupStatusBadge(group: group)),
          ],
        ),
        if (group.scheduleStatus == GroupScheduleStatus.finished) ...[
          const SizedBox(height: 12),
          Text(
            group.scheduleSummary,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _ScheduleLine extends StatelessWidget {
  const _ScheduleLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: textTheme.bodyLarge)),
      ],
    );
  }
}
