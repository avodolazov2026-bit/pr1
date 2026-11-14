import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/invite_people_sheet.dart';
import 'package:geo_groups/qr_invite_screen.dart';

enum _InviteChannel { demoList, contacts, qrCode }

Future<List<DirectoryPerson>?> showInviteParticipants({
  required BuildContext context,
  required Set<String> excludedIds,
  required Set<String> initiallySelectedIds,
  GeoGroup? group,
}) async {
  final channel = await showModalBottomSheet<_InviteChannel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _InviteSourceSheet(group: group),
  );
  if (channel == null || !context.mounted) {
    return null;
  }

  switch (channel) {
    case _InviteChannel.demoList:
      if (group != null && group.isFinished) {
        await _showNotice(
          context,
          title: 'Группа завершена',
          message: 'В завершённую группу нельзя отправить новое приглашение.',
        );
        return null;
      }
      if (!context.mounted) {
        return null;
      }
      return showModalBottomSheet<List<DirectoryPerson>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => InvitePeopleSheet(
          initiallySelectedIds: initiallySelectedIds,
          excludedIds: excludedIds,
        ),
      );
    case _InviteChannel.contacts:
      await _showNotice(
        context,
        title: 'Контакты телефона',
        message: 'Выбор контактов появится после подключения аккаунтов, сервера и разрешения на доступ к адресной книге.',
      );
      return null;
    case _InviteChannel.qrCode:
      if (group == null || group.qrInviteToken.isEmpty) {
        await _showNotice(
          context,
          title: 'QR-код группы',
          message:
              'Сначала сохраните группу, чтобы создать QR-код приглашения.',
        );
        return null;
      }
      if (group.isFinished) {
        await _showNotice(
          context,
          title: 'QR-код группы',
          message: 'В завершённую группу нельзя приглашать участников.',
        );
        return null;
      }
      if (!group.currentUserIsActiveOrganizer || !context.mounted) {
        return null;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => QrInviteScreen(group: group),
        ),
      );
      return null;
  }
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
            leading: const Icon(Icons.person_search_outlined),
            title: const Text('Выбрать из списка'),
            subtitle: const Text('Выбрать демонстрационных пользователей'),
            onTap: () => Navigator.of(context).pop(_InviteChannel.demoList),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.contacts_outlined),
            title: const Text('Контакты телефона'),
            subtitle: const Text('Выбрать людей из адресной книги'),
            onTap: () => Navigator.of(context).pop(_InviteChannel.contacts),
          ),
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
        ],
      ),
    );
  }
}
