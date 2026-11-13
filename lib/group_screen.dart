import 'package:flutter/material.dart';

import 'package:geo_groups/edit_group_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_map_screen.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({
    super.key,
    required this.group,
    this.onChanged,
  });

  final GeoGroup group;
  final VoidCallback? onChanged;

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Изменения сохранены')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final endsAt = group.endsAt;
    final canEdit = group.isActive && group.currentUserIsActiveOrganizer;
    final participants = group.members.where(
      (member) =>
          member.status == MembershipStatus.active && !member.isCurrentUser,
    );
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
            Text(
              endsAt == null
                  ? 'Срок действия: бессрочно'
                  : 'Активно до: ${formatGroupDateTime(endsAt)}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Text('Участники', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Расстояние от вас',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final member in participants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(memberInitials(member.name)),
                ),
                title: Text(member.name),
                trailing: member.distanceMeters == null
                    ? null
                    : Text('${member.distanceMeters} м'),
              ),
            if (invited.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Приглашены', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final member in invited)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(memberInitials(member.name)),
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const GroupMapScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.map),
                label: const Text('Открыть карту'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmLeave(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(color: colorScheme.error),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Покинуть группу'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
