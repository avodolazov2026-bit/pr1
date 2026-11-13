import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  Future<void> _decline(GroupInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final errorColor = Theme.of(dialogContext).colorScheme.error;
        return AlertDialog(
          title: const Text('Отклонить приглашение?'),
          content: const Text(
            'Вы не станете участником группы и не будете делиться геолокацией.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: errorColor),
              child: const Text('Отклонить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    GroupsStore.instance.declineInvitation(invitation);
    setState(() {});
  }

  Future<void> _join(GroupInvitation invitation) async {
    final group = GroupsStore.instance.groupById(invitation.groupId);
    if (group == null || !group.isActive || group.currentUserIsActiveMember) {
      setState(() {});
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Присоединиться к группе?'),
          content: Text(
            group.isIndefinite
                ? 'Группа бессрочная. После присоединения вы сможете видеть геолокацию участников и делиться своей геолокацией. Вы сможете покинуть группу в любое время.'
                : 'После присоединения вы сможете видеть геолокацию участников группы и делиться своей геолокацией до окончания срока группы. Разрешение геолокации будет запрошено отдельно.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Присоединиться'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final result = GroupsStore.instance.acceptInvitation(invitation);
    if (!mounted) {
      return;
    }
    setState(() {});
    if (result != InvitationAcceptResult.joined) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Вы присоединились к группе. Запрос геолокации будет добавлен позже.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final invitations = GroupsStore.instance.incomingPending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашения'),
      ),
      body: SafeArea(
        child: invitations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_email_unread_outlined,
                        size: 72,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Нет новых приглашений',
                        style: textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Здесь появятся приглашения в группы.',
                        style: textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: invitations.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final invitation = invitations[index];
                  return _InvitationCard(
                    invitation: invitation,
                    onDecline: () => _decline(invitation),
                    onJoin: () => _join(invitation),
                  );
                },
              ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.onDecline,
    required this.onJoin,
  });

  final GroupInvitation invitation;
  final VoidCallback onDecline;
  final VoidCallback onJoin;

  String _scheduleLabel(GeoGroup? group) {
    if (group == null || !group.isActive) {
      return 'Группа завершена';
    }
    if (group.isIndefinite) {
      return 'Бессрочная группа';
    }
    final endsAt = group.endsAt;
    if (endsAt == null) {
      return 'Бессрочная группа';
    }
    return 'До ${formatGroupDateTime(endsAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final group = GroupsStore.instance.groupById(invitation.groupId);
    final ended = group == null || !group.isActive;
    final alreadyMember = group?.currentUserIsActiveMember ?? false;
    final canJoin = group != null && group.isActive && !alreadyMember;
    final scheduleLabel = _scheduleLabel(group);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group?.name ?? 'Группа недоступна',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Организатор: ${invitation.inviterName}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              invitation.source.incomingLabel,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              scheduleLabel,
              style: textTheme.bodyLarge?.copyWith(
                color: ended ? colorScheme.error : null,
                fontWeight: ended ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    child: const Text('Отклонить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canJoin ? onJoin : null,
                    child: const Text('Присоединиться'),
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
