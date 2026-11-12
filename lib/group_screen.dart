import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_map_screen.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({
    super.key,
    required this.name,
    required this.activeUntil,
    required this.members,
  });

  final String name;
  final String activeUntil;
  final List<GroupMember> members;

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

    for (final member in members) {
      if (member.isCurrentUser) {
        member.hasLeftGroup = true;
      }
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final visibleMembers = members.where(
      (member) => !member.isCurrentUser || member.hasLeftGroup,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Активно до: $activeUntil',
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
            for (final member in visibleMembers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Opacity(
                  opacity: member.hasLeftGroup ? 0.45 : 1,
                  child: CircleAvatar(
                    child: Text(member.name.substring(0, 1)),
                  ),
                ),
                title: Text(member.name),
                trailing: Text(
                  member.hasLeftGroup
                      ? 'Покинул группу'
                      : '${member.distanceMeters} м',
                  style: member.hasLeftGroup
                      ? textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
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
