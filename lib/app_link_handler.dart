import 'package:geo_groups/geo_group.dart';

enum GroupInviteLinkKind { ignore, confirm, rejected }

class GroupInviteLinkResolution {
  const GroupInviteLinkResolution.ignore()
    : kind = GroupInviteLinkKind.ignore,
      group = null,
      payload = null,
      message = null;

  const GroupInviteLinkResolution.confirm({
    required GeoGroup this.group,
    required this.payload,
  }) : kind = GroupInviteLinkKind.confirm,
       message = null;

  const GroupInviteLinkResolution.rejected(this.message)
    : kind = GroupInviteLinkKind.rejected,
      group = null,
      payload = null;

  final GroupInviteLinkKind kind;
  final GeoGroup? group;
  final String? payload;
  final String? message;

  bool get opensConfirmation => kind == GroupInviteLinkKind.confirm;
}

bool isGroupJoinLink(Uri uri) {
  return uri.scheme == 'geo-groups' && uri.host == 'join';
}

/// Проверяет входящий URI, не меняя группы и приглашения.
GroupInviteLinkResolution resolveGroupInviteLink(Uri uri) {
  if (!isGroupJoinLink(uri)) {
    return const GroupInviteLinkResolution.ignore();
  }
  final payload = uri.toString();
  final inspection = GroupsStore.instance.inspectQrInvitation(payload);
  final group = inspection.group;
  final canConfirm =
      group != null &&
      (inspection.result == QrInviteClaimResult.added ||
          inspection.result == QrInviteClaimResult.alreadyPending);
  if (!canConfirm) {
    return GroupInviteLinkResolution.rejected(
      messageForQrInviteClaim(inspection.result),
    );
  }
  return GroupInviteLinkResolution.confirm(group: group, payload: payload);
}
