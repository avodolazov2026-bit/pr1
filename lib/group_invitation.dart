enum InvitationSource {
  demoList,
  contacts,
  qrCode,
  link;

  String get incomingLabel => switch (this) {
    InvitationSource.demoList => 'Приглашение от организатора',
    InvitationSource.contacts => 'Приглашение из контактов',
    InvitationSource.qrCode => 'Приглашение по QR-коду',
    InvitationSource.link => 'Приглашение по ссылке',
  };
}

enum InvitationStatus { pending, accepted, declined, revoked, expired }

class GroupInvitation {
  GroupInvitation({
    required this.id,
    required this.groupId,
    required this.inviterName,
    required this.inviteeId,
    required this.inviteeName,
    required this.source,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.token,
  });

  final String id;
  final String groupId;
  final String inviterName;
  final String inviteeId;
  final String inviteeName;
  final InvitationSource source;
  InvitationStatus status;
  final DateTime createdAt;
  DateTime? expiresAt;
  final String? token;
}
