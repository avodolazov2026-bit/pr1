import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/qr_invite_screen.dart';

enum _InviteChannel { qrCode, shareLink }

typedef ShareGroupInvite = Future<void> Function({
  required String text,
  required String subject,
});

Future<void> shareGroupInvite({
  required String text,
  required String subject,
}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

Future<void> showGroupInviteOptions({
  required BuildContext context,
  GeoGroup? group,
  ShareGroupInvite? shareInvite,
}) async {
  final channel = await showModalBottomSheet<_InviteChannel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _InviteSourceSheet(group: group),
  );
  if (channel == null || !context.mounted) {
    return;
  }

  switch (channel) {
    case _InviteChannel.qrCode:
      if (group == null || group.qrInviteToken.isEmpty) {
        await _showNotice(
          context,
          title: 'QR-код группы',
          message:
              'Сначала сохраните группу, чтобы создать QR-код приглашения.',
        );
        return;
      }
      if (group.isFinished) {
        await _showNotice(
          context,
          title: 'QR-код группы',
          message: 'В завершённую группу нельзя приглашать участников.',
        );
        return;
      }
      if (!group.currentUserIsActiveOrganizer || !context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => QrInviteScreen(group: group),
        ),
      );
      return;
    case _InviteChannel.shareLink:
      if (group == null) {
        await _showNotice(
          context,
          title: 'Ссылка-приглашение',
          message:
              'Сначала сохраните группу, чтобы создать ссылку-приглашение.',
        );
        return;
      }
      if (group.isFinished) {
        await _showNotice(
          context,
          title: 'Ссылка-приглашение',
          message: 'В завершённую группу нельзя приглашать участников.',
        );
        return;
      }
      if (!group.currentUserIsActiveOrganizer || !context.mounted) {
        return;
      }
      final share = shareInvite ?? shareGroupInvite;
      await share(
        text: _inviteShareText(group),
        subject: 'Приглашение в Geo Groups',
      );
      return;
  }
}

String _inviteShareText(GeoGroup group) {
  return 'Присоединяйтесь к группе «${group.name}» в Geo Groups:\n'
      '${buildGroupInviteLink(group)}';
}

Future<void> _showNotice(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Понятно'),
          ),
        ],
      );
    },
  );
}

class _InviteSourceSheet extends StatelessWidget {
  const _InviteSourceSheet({required this.group});

  final GeoGroup? group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentGroup = group;
    final savedAndFinished = currentGroup != null && currentGroup.isFinished;
    final canOpenQr =
        currentGroup == null ||
        (!currentGroup.isFinished && currentGroup.currentUserIsActiveOrganizer);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Пригласить участников', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: canOpenQr && !savedAndFinished,
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('QR-код группы'),
            subtitle: Text(
              savedAndFinished
                  ? 'В завершённую группу нельзя приглашать участников'
                  : 'Показать код для присоединения',
            ),
            onTap: canOpenQr && !savedAndFinished
                ? () => Navigator.of(context).pop(_InviteChannel.qrCode)
                : null,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: canOpenQr && !savedAndFinished,
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Поделиться ссылкой'),
            subtitle: Text(
              savedAndFinished
                  ? 'В завершённую группу нельзя приглашать участников'
                  : 'Отправить приглашение через другое приложение',
            ),
            onTap: canOpenQr && !savedAndFinished
                ? () => Navigator.of(context).pop(_InviteChannel.shareLink)
                : null,
          ),
        ],
      ),
    );
  }
}
