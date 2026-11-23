import 'package:supabase_flutter/supabase_flutter.dart';

/// 64 hex-символа, как проверяет сервер до поиска ссылки.
final RegExp groupInviteTokenPattern = RegExp(r'^[0-9a-f]{64}$');

bool isGroupInviteToken(String token) => groupInviteTokenPattern.hasMatch(token);

/// Ссылка группы из create_or_get_group_invitation.
///
/// Это не личное приглашение из group_invitation.dart.
class GroupInvitation {
  const GroupInvitation({
    required this.invitationId,
    required this.inviteToken,
    required this.groupId,
    required this.isActive,
    this.expiresAt,
  });

  final String invitationId;
  final String inviteToken;
  final String groupId;
  final bool isActive;
  final DateTime? expiresAt;
}

/// Сохранённая входящая ссылка. Поля isPending и isUnseen приходят из разных RPC.
class SavedGroupInvitation {
  const SavedGroupInvitation({
    required this.savedInvitationId,
    required this.invitationId,
    required this.groupId,
    required this.groupName,
    required this.startsAt,
    required this.organizerDisplayName,
    this.endsAt,
    this.isPending,
    this.isUnseen,
    this.createdAt,
  });

  final String savedInvitationId;
  final String invitationId;
  final String groupId;
  final String groupName;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String organizerDisplayName;
  final bool? isPending;
  final bool? isUnseen;
  final DateTime? createdAt;
}

/// Публичная карточка ссылки. Отсутствует, когда available = false.
class ResolvedInvitation {
  const ResolvedInvitation({
    required this.invitationId,
    required this.groupId,
    required this.groupName,
    required this.startsAt,
    required this.organizerDisplayName,
    this.endsAt,
  });

  final String invitationId;
  final String groupId;
  final String groupName;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String organizerDisplayName;
}

enum MembershipResult { joined, alreadyMember }

class AcceptResult {
  const AcceptResult({
    required this.groupId,
    required this.membershipResult,
  });

  final String groupId;
  final MembershipResult membershipResult;
}

/// Доступ к многоразовым ссылкам. Реализация не выбирается по сессии.
abstract class GroupInvitationRepository {
  Future<GroupInvitation?> createOrGet(String groupId);

  Future<bool> revoke(String groupId);

  Future<ResolvedInvitation?> resolve(String token);

  Future<SavedGroupInvitation?> save(String token);

  Future<List<SavedGroupInvitation>> listSaved();

  Future<int> countUnseen();

  Future<int> markSeen();

  Future<AcceptResult?> accept(String token);

  /// Вступление по строке списка. Токен клиенту не передаётся.
  Future<AcceptResult?> acceptSaved(String savedInvitationId);
}

typedef InvitationRpcCall = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);

GroupInvitationRepository defaultGroupInvitationRepository() {
  return SupabaseGroupInvitationRepository();
}

class SupabaseGroupInvitationRepository implements GroupInvitationRepository {
  SupabaseGroupInvitationRepository({
    SupabaseClient? client,
    InvitationRpcCall? rpc,
  }) : _rpc =
           rpc ??
           ((functionName, params) =>
               (client ?? Supabase.instance.client).rpc(
                 functionName,
                 params: params,
               ));

  final InvitationRpcCall _rpc;

  @override
  Future<GroupInvitation?> createOrGet(String groupId) async {
    final raw = await _rpc(
      'create_or_get_group_invitation',
      {'p_group_id': groupId},
    );
    return groupInvitationFromRow(_firstRow(raw));
  }

  @override
  Future<bool> revoke(String groupId) async {
    final raw = await _rpc(
      'revoke_group_invitation',
      {'p_group_id': groupId},
    );
    if (raw is bool) {
      return raw;
    }
    throw const PostgrestException(
      message: 'Сервер не вернул результат отзыва приглашения',
    );
  }

  @override
  Future<ResolvedInvitation?> resolve(String token) async {
    if (!isGroupInviteToken(token)) {
      return null;
    }
    final raw = await _rpc(
      'resolve_group_invitation',
      {'p_invite_token': token},
    );
    return resolvedInvitationFromRow(_firstRow(raw));
  }

  @override
  Future<SavedGroupInvitation?> save(String token) async {
    if (!isGroupInviteToken(token)) {
      return null;
    }
    final raw = await _rpc(
      'save_group_invitation',
      {'p_invite_token': token},
    );
    return savedInvitationFromRow(_firstRow(raw));
  }

  @override
  Future<List<SavedGroupInvitation>> listSaved() async {
    final raw = await _rpc('list_saved_group_invitations', const {});
    return savedInvitationsFromRows(raw);
  }

  @override
  Future<int> countUnseen() async {
    final raw = await _rpc('count_unseen_saved_group_invitations', const {});
    return _requiredInt(raw, 'Сервер не вернул число непросмотренных приглашений');
  }

  @override
  Future<int> markSeen() async {
    final raw = await _rpc('mark_saved_group_invitations_seen', const {});
    return _requiredInt(raw, 'Сервер не вернул число отмеченных приглашений');
  }

  @override
  Future<AcceptResult?> accept(String token) async {
    if (!isGroupInviteToken(token)) {
      return null;
    }
    final raw = await _rpc(
      'accept_group_invitation',
      {'p_invite_token': token},
    );
    return acceptResultFromRow(_firstRow(raw));
  }

  @override
  Future<AcceptResult?> acceptSaved(String savedInvitationId) async {
    final raw = await _rpc(
      'accept_saved_group_invitation',
      {'p_saved_invitation_id': savedInvitationId},
    );
    return acceptResultFromRow(_firstRow(raw));
  }
}

GroupInvitation? groupInvitationFromRow(Map<String, dynamic>? row) {
  if (row == null) {
    return null;
  }
  final invitationId = _text(row['invitation_id']);
  final inviteToken = _text(row['invite_token']);
  final groupId = _text(row['group_id']);
  final isActive = row['is_active'];
  if (invitationId == null ||
      inviteToken == null ||
      groupId == null ||
      isActive is! bool) {
    return null;
  }
  return GroupInvitation(
    invitationId: invitationId,
    inviteToken: inviteToken,
    groupId: groupId,
    isActive: isActive,
    expiresAt: _dateTime(row['expires_at']),
  );
}

ResolvedInvitation? resolvedInvitationFromRow(Map<String, dynamic>? row) {
  if (row == null || row['available'] != true) {
    return null;
  }
  final card = _invitationCard(row);
  if (card == null) {
    return null;
  }
  return ResolvedInvitation(
    invitationId: card.invitationId,
    groupId: card.groupId,
    groupName: card.groupName,
    startsAt: card.startsAt,
    endsAt: card.endsAt,
    organizerDisplayName: card.organizerDisplayName,
  );
}

SavedGroupInvitation? savedInvitationFromRow(Map<String, dynamic>? row) {
  if (row == null || row['available'] != true) {
    return null;
  }
  final card = _invitationCard(row);
  final savedInvitationId = _text(row['saved_invitation_id']);
  final isPending = row['is_pending'];
  if (card == null || savedInvitationId == null || isPending is! bool) {
    return null;
  }
  return SavedGroupInvitation(
    savedInvitationId: savedInvitationId,
    invitationId: card.invitationId,
    groupId: card.groupId,
    groupName: card.groupName,
    startsAt: card.startsAt,
    endsAt: card.endsAt,
    organizerDisplayName: card.organizerDisplayName,
    isPending: isPending,
  );
}

List<SavedGroupInvitation> savedInvitationsFromRows(Object? raw) {
  if (raw is! List) {
    throw const PostgrestException(
      message: 'Сервер не вернул список сохранённых приглашений',
    );
  }
  final result = <SavedGroupInvitation>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final row = Map<String, dynamic>.from(item);
    final card = _invitationCard(row);
    final savedInvitationId = _text(row['saved_invitation_id']);
    final createdAt = _dateTime(row['created_at']);
    final isUnseen = row['is_unseen'];
    if (card == null ||
        savedInvitationId == null ||
        createdAt == null ||
        isUnseen is! bool) {
      continue;
    }
    result.add(
      SavedGroupInvitation(
        savedInvitationId: savedInvitationId,
        invitationId: card.invitationId,
        groupId: card.groupId,
        groupName: card.groupName,
        startsAt: card.startsAt,
        endsAt: card.endsAt,
        organizerDisplayName: card.organizerDisplayName,
        isUnseen: isUnseen,
        createdAt: createdAt,
      ),
    );
  }
  return result;
}

AcceptResult? acceptResultFromRow(Map<String, dynamic>? row) {
  if (row == null) {
    return null;
  }
  final groupId = _text(row['group_id']);
  final membership = row['membership_result'];
  if (groupId == null || membership is! String) {
    return null;
  }
  final result = switch (membership) {
    'joined' => MembershipResult.joined,
    'already_member' => MembershipResult.alreadyMember,
    _ => null,
  };
  if (result == null) {
    throw PostgrestException(
      message: 'Сервер вернул неизвестный результат вступления',
    );
  }
  return AcceptResult(groupId: groupId, membershipResult: result);
}

class _InvitationCard {
  const _InvitationCard({
    required this.invitationId,
    required this.groupId,
    required this.groupName,
    required this.startsAt,
    required this.organizerDisplayName,
    this.endsAt,
  });

  final String invitationId;
  final String groupId;
  final String groupName;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String organizerDisplayName;
}

_InvitationCard? _invitationCard(Map<String, dynamic> row) {
  final invitationId = _text(row['invitation_id']);
  final groupId = _text(row['group_id']);
  final groupName = _text(row['group_name']);
  final startsAt = _dateTime(row['starts_at']);
  final organizer = _text(row['organizer_display_name']);
  if (invitationId == null ||
      groupId == null ||
      groupName == null ||
      startsAt == null ||
      organizer == null) {
    return null;
  }
  return _InvitationCard(
    invitationId: invitationId,
    groupId: groupId,
    groupName: groupName,
    startsAt: startsAt,
    endsAt: _dateTime(row['ends_at']),
    organizerDisplayName: organizer,
  );
}

Map<String, dynamic>? _firstRow(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is List) {
    if (raw.isEmpty) {
      return null;
    }
    final first = raw.first;
    if (first is Map) {
      return Map<String, dynamic>.from(first);
    }
  }
  return null;
}

int _requiredInt(Object? raw, String message) {
  if (raw is int) {
    return raw;
  }
  throw PostgrestException(message: message);
}

String? _text(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
