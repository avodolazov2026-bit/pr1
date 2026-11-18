import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/join_group_confirmation_screen.dart';

/// Сигнал спискам обновить карточки после закрытия экрана вступления.
final groupFlowRevision = ValueNotifier<int>(0);

Future<bool> openJoinGroupConfirmation({
  required BuildContext context,
  required GeoGroup group,
  required Future<InvitationAcceptResult> Function(String name, String avatarId)
  onJoin,
}) async {
  final user = currentDemoUser;
  final joined = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (context) => JoinGroupConfirmationScreen(
        group: group,
        userId: user.id,
        fallbackName: user.name,
        onJoin: onJoin,
      ),
    ),
  );
  if (!context.mounted) {
    return false;
  }
  groupFlowRevision.value++;
  if (joined == true) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(content: Text('Вы вступили в группу')),
    );
  }
  return joined == true;
}
