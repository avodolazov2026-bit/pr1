import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation.dart';
import 'package:geo_groups/group_invitation_repository.dart' hide GroupInvitation;
import 'package:geo_groups/join_group_route.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({
    super.key,
    this.invitations,
    this.onInvitationsChanged,
  });

  final GroupInvitationRepository? invitations;
  final Future<void> Function()? onInvitationsChanged;

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final _payloadController = TextEditingController();
  var _loadingSaved = false;
  var _saved = const <SavedGroupInvitation>[];
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    groupFlowRevision.addListener(_onGroupFlowChanged);
    if (widget.invitations != null) {
      _loadingSaved = true;
      _loadSaved();
    }
  }

  @override
  void dispose() {
    groupFlowRevision.removeListener(_onGroupFlowChanged);
    _payloadController.dispose();
    super.dispose();
  }

  void _onGroupFlowChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSaved() async {
    final invitations = widget.invitations;
    if (invitations == null) {
      return;
    }
    try {
      final rows = await invitations.listSaved();
      if (!mounted) {
        return;
      }
      setState(() {
        _saved = rows;
        _loadingSaved = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingSaved = false);
      _showSnackBar(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _acceptSaved(SavedGroupInvitation invitation) async {
    final invitations = widget.invitations;
    if (invitations == null || _joiningId != null) {
      return;
    }
    final savedBefore = _saved;
    setState(() => _joiningId = invitation.savedInvitationId);
    try {
      final result = await invitations.acceptSaved(invitation.savedInvitationId);
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showSnackBar('Приглашение недоступно');
        return;
      }
      if (result.membershipResult == MembershipResult.joined) {
        await _loadSaved();
        await widget.onInvitationsChanged?.call();
        if (mounted) {
          _showSnackBar('Вы вступили в группу');
        }
        return;
      }
      await widget.onInvitationsChanged?.call();
      await _loadSaved();
      if (mounted) {
        _showSnackBar('Вы уже участвуете в этой группе');
      }
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saved = savedBefore);
      _showSnackBar(error.message);
    } finally {
      if (mounted) {
        setState(() => _joiningId = null);
      }
    }
  }

  Future<void> _pastePayload() async {
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Не удалось прочитать буфер обмена');
      return;
    }
    if (!mounted) {
      return;
    }
    final pasted = text;
    if (pasted == null || pasted.isEmpty) {
      _showSnackBar('В буфере обмена нет кода приглашения');
      return;
    }
    setState(() {
      _payloadController.text = pasted;
    });
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _claimPayload() async {
    final payload = _payloadController.text;
    final inspection = GroupsStore.instance.inspectQrInvitation(payload);
    final group = inspection.group;
    final canConfirm =
        group != null &&
        (inspection.result == QrInviteClaimResult.added ||
            inspection.result == QrInviteClaimResult.alreadyPending);
    if (!canConfirm) {
      setState(() {});
      _showSnackBar(messageForQrInviteClaim(inspection.result));
      return;
    }
    final joined = await _openJoin(
      group: group,
      onJoin: (name, avatarId) {
        return Future.value(
          GroupsStore.instance.joinFromQrPayload(
            payload,
            displayName: name,
            avatarId: avatarId,
          ),
        );
      },
    );
    if (joined && mounted) {
      setState(() => _payloadController.clear());
    }
  }

  Future<bool> _openJoin({
    required GeoGroup group,
    required Future<InvitationAcceptResult> Function(
      String name,
      String avatarId,
    )
    onJoin,
  }) {
    return openJoinGroupConfirmation(
      context: context,
      group: group,
      onJoin: onJoin,
    );
  }

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
    if (group == null || group.isFinished || group.currentUserIsActiveMember) {
      setState(() {});
      return;
    }

    await _openJoin(
      group: group,
      onJoin: (name, avatarId) {
        return Future.value(
          GroupsStore.instance.acceptInvitation(
            invitation,
            displayName: name,
            avatarId: avatarId,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final localInvitations = GroupsStore.instance.incomingPending;
    final useSaved = widget.invitations != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Приглашения')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Получить приглашение по коду', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Вставьте данные из QR-кода приглашения. '
              'Сканирование камерой будет добавлено позднее.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payloadController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Данные приглашения',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pastePayload,
                icon: const Icon(Icons.content_paste_outlined),
                label: const Text('Вставить из буфера'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _claimPayload,
              child: const Text('Обработать приглашение'),
            ),
            const SizedBox(height: 24),
            Text('Ожидающие приглашения', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            ..._pendingInvitations(
              textTheme: textTheme,
              colorScheme: colorScheme,
              useSaved: useSaved,
              localInvitations: localInvitations,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingInvitations({
    required TextTheme textTheme,
    required ColorScheme colorScheme,
    required bool useSaved,
    required List<GroupInvitation> localInvitations,
  }) {
    if (useSaved) {
      if (_loadingSaved && _saved.isEmpty) {
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      if (_saved.isEmpty) {
        return [
          _EmptyInvitations(textTheme: textTheme, colorScheme: colorScheme),
        ];
      }
      return [
        for (var index = 0; index < _saved.length; index++) ...[
          _SavedInvitationCard(
            invitation: _saved[index],
            joining: _joiningId == _saved[index].savedInvitationId,
            enabled: _joiningId == null,
            onJoin: () => _acceptSaved(_saved[index]),
          ),
          if (index != _saved.length - 1) const SizedBox(height: 12),
        ],
      ];
    }
    if (localInvitations.isEmpty) {
      return [
        _EmptyInvitations(textTheme: textTheme, colorScheme: colorScheme),
      ];
    }
    return [
      for (var index = 0; index < localInvitations.length; index++) ...[
        _InvitationCard(
          invitation: localInvitations[index],
          onDecline: () => _decline(localInvitations[index]),
          onJoin: () => _join(localInvitations[index]),
        ),
        if (index != localInvitations.length - 1) const SizedBox(height: 12),
      ],
    ];
  }
}

class _EmptyInvitations extends StatelessWidget {
  const _EmptyInvitations({required this.textTheme, required this.colorScheme});

  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 48,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
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
    );
  }
}

class _SavedInvitationCard extends StatelessWidget {
  const _SavedInvitationCard({
    required this.invitation,
    required this.joining,
    required this.enabled,
    required this.onJoin,
  });

  final SavedGroupInvitation invitation;
  final bool joining;
  final bool enabled;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = invitation.endsAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(invitation.groupName, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Организатор: ${invitation.organizerDisplayName}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              endsAt == null
                  ? 'Начнётся ${formatGroupDateTime(invitation.startsAt)}'
                  : 'До ${formatGroupDateTime(endsAt)}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled ? onJoin : null,
              child: joining
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Вступить в группу'),
            ),
          ],
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
    if (group == null) {
      return 'Группа завершена';
    }
    if (group.isFinished) {
      return group.wasCancelledBeforeStart ? 'Отменена' : 'Группа завершена';
    }
    return group.scheduleSummary;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final group = GroupsStore.instance.groupById(invitation.groupId);
    final ended = group == null || group.isFinished;
    final alreadyMember = group?.currentUserIsActiveMember ?? false;
    final canJoin = group != null && !group.isFinished && !alreadyMember;
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
