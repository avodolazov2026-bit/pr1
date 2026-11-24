import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation_repository.dart';

/// Токен из https://qunora.pro/invite/<64 hex>. Иначе null.
String? groupInviteTokenFromUri(Uri uri) {
  final parsed = parseGroupInvitePayload(uri.toString());
  if (parsed == null || !isGroupInviteToken(parsed.inviteToken)) {
    return null;
  }
  return parsed.inviteToken;
}

bool isGroupJoinLink(Uri uri) => groupInviteTokenFromUri(uri) != null;

/// Адрес qunora.pro/invite/..., но токен не проходит ^[0-9a-f]{64}$.
bool isMalformedGroupInviteLink(Uri uri) {
  if (uri.scheme != 'https' || uri.host != 'qunora.pro') {
    return false;
  }
  if (uri.pathSegments.isEmpty || uri.pathSegments.first != 'invite') {
    return false;
  }
  return groupInviteTokenFromUri(uri) == null;
}
