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
      if (group != null && !group.isActive) {
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
        message:
            'Выбор контактов появится после подключения аккаунтов, сервера и разрешения на доступ к адресной книге.',
      );
      return null;
    case _InviteChannel.qrCode:
      if (group == null) {
        await _showNotice(
          context,
          title: 'QR-код группы',
          message:
              'Сначала создайте группу, затем можно будет пригласить участника по QR-коду.',
        );
        return null;
      }
      if (!group.isActive || !context.mounted) {
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
    final savedAndEnded = group != null && !group!.isActive;

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
            enabled: !savedAndEnded,
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('QR-код группы'),
            subtitle: Text(
              savedAndEnded
                  ? 'Группа завершена, приглашение недоступно'
                  : 'Показать код для присоединения',
            ),
            onTap: savedAndEnded
                ? null
                : () => Navigator.of(context).pop(_InviteChannel.qrCode),
          ),
        ],
      ),
    );
  }
}
