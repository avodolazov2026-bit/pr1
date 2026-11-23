import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/group_invitation_repository.dart';

void main() {
  const token =
      'abababababababababababababababababababababababababababababababab';

  test('the default repository is the supabase implementation', () {
    expect(
      defaultGroupInvitationRepository(),
      isA<SupabaseGroupInvitationRepository>(),
    );
  });

  test('createOrGet maps the invitation row', () async {
    final rpc = _FakeRpc(
      {
        'create_or_get_group_invitation': [
          {
            'invitation_id': 'link-1',
            'invite_token': token,
            'group_id': 'group-1',
            'is_active': true,
            'expires_at': null,
          },
        ],
      },
    );
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final invitation = await repository.createOrGet('group-1');

    expect(rpc.calls.single.$1, 'create_or_get_group_invitation');
    expect(rpc.calls.single.$2, {'p_group_id': 'group-1'});
    expect(invitation?.invitationId, 'link-1');
    expect(invitation?.inviteToken, token);
    expect(invitation?.groupId, 'group-1');
    expect(invitation?.isActive, isTrue);
    expect(invitation?.expiresAt, isNull);
  });

  test('revoke returns the server boolean', () async {
    final rpc = _FakeRpc({'revoke_group_invitation': false});
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    expect(await repository.revoke('group-1'), isFalse);
    expect(rpc.calls.single.$2, {'p_group_id': 'group-1'});
  });

  test('resolve maps an available invitation and drops an unavailable one', () async {
    final rpc = _FakeRpc({
      'resolve_group_invitation': [
        {
          'available': true,
          'invitation_id': 'link-1',
          'group_id': 'group-1',
          'group_name': 'Прогулка',
          'starts_at': '2026-11-20T09:00:00Z',
          'ends_at': '2026-11-20T12:00:00Z',
          'organizer_display_name': 'Ника',
        },
      ],
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final resolved = await repository.resolve(token);

    expect(resolved?.invitationId, 'link-1');
    expect(resolved?.groupId, 'group-1');
    expect(resolved?.groupName, 'Прогулка');
    expect(resolved?.startsAt, DateTime.parse('2026-11-20T09:00:00Z'));
    expect(resolved?.endsAt, DateTime.parse('2026-11-20T12:00:00Z'));
    expect(resolved?.organizerDisplayName, 'Ника');

    rpc.responses['resolve_group_invitation'] = [
      {
        'available': false,
        'invitation_id': null,
        'group_id': null,
        'group_name': null,
        'starts_at': null,
        'ends_at': null,
        'organizer_display_name': null,
      },
    ];
    expect(await repository.resolve(token), isNull);
  });

  test('save maps a pending invitation and returns null when unavailable', () async {
    final rpc = _FakeRpc({
      'save_group_invitation': {
        'available': true,
        'saved_invitation_id': 'saved-1',
        'invitation_id': 'link-1',
        'group_id': 'group-1',
        'group_name': 'Прогулка',
        'starts_at': '2026-11-20T09:00:00Z',
        'ends_at': null,
        'organizer_display_name': 'Ника',
        'is_pending': true,
      },
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final saved = await repository.save(token);

    expect(rpc.calls.single.$1, 'save_group_invitation');
    expect(rpc.calls.single.$2, {'p_invite_token': token});
    expect(saved?.savedInvitationId, 'saved-1');
    expect(saved?.invitationId, 'link-1');
    expect(saved?.isPending, isTrue);
    expect(saved?.endsAt, isNull);
    expect(saved?.isUnseen, isNull);
    expect(saved?.createdAt, isNull);

    rpc.responses['save_group_invitation'] = {'available': false};
    expect(await repository.save(token), isNull);
  });

  test('listSaved maps unseen rows and skips an incomplete row', () async {
    final rpc = _FakeRpc({
      'list_saved_group_invitations': [
        {
          'saved_invitation_id': 'saved-1',
          'invitation_id': 'link-1',
          'group_id': 'group-1',
          'group_name': 'Прогулка',
          'starts_at': '2026-11-20T09:00:00Z',
          'ends_at': '2026-11-20T12:00:00Z',
          'organizer_display_name': 'Ника',
          'is_unseen': true,
          'created_at': '2026-11-20T08:00:00Z',
        },
        {'saved_invitation_id': 'broken'},
      ],
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final saved = await repository.listSaved();

    expect(saved, hasLength(1));
    expect(saved.single.savedInvitationId, 'saved-1');
    expect(saved.single.isUnseen, isTrue);
    expect(saved.single.isPending, isNull);
    expect(saved.single.createdAt, DateTime.parse('2026-11-20T08:00:00Z'));
  });

  test('countUnseen and markSeen return the server integers', () async {
    final rpc = _FakeRpc({
      'count_unseen_saved_group_invitations': 2,
      'mark_saved_group_invitations_seen': 2,
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    expect(await repository.countUnseen(), 2);
    expect(await repository.markSeen(), 2);
    expect(rpc.calls[0].$2, isEmpty);
    expect(rpc.calls[1].$2, isEmpty);
  });

  test('accept maps joined and already_member', () async {
    final rpc = _FakeRpc({
      'accept_group_invitation': [
        {'group_id': 'group-1', 'membership_result': 'joined'},
      ],
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final joined = await repository.accept(token);
    expect(joined?.groupId, 'group-1');
    expect(joined?.membershipResult, MembershipResult.joined);

    rpc.responses['accept_group_invitation'] = {
      'group_id': 'group-1',
      'membership_result': 'already_member',
    };
    final again = await repository.accept(token);
    expect(again?.membershipResult, MembershipResult.alreadyMember);
  });

  test('acceptSaved joins by saved invitation id and does not send a token', () async {
    final rpc = _FakeRpc({
      'accept_saved_group_invitation': [
        {'group_id': 'group-1', 'membership_result': 'joined'},
      ],
    });
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    final joined = await repository.acceptSaved('saved-1');

    expect(rpc.calls.single.$1, 'accept_saved_group_invitation');
    expect(rpc.calls.single.$2, {'p_saved_invitation_id': 'saved-1'});
    expect(rpc.calls.single.$2.containsKey('p_invite_token'), isFalse);
    expect(joined?.groupId, 'group-1');
    expect(joined?.membershipResult, MembershipResult.joined);

    rpc.responses['accept_saved_group_invitation'] = {
      'group_id': 'group-1',
      'membership_result': 'already_member',
    };
    final again = await repository.acceptSaved('saved-1');
    expect(again?.membershipResult, MembershipResult.alreadyMember);
  });

  test('a token that is not 64 lowercase hex characters skips the rpc', () async {
    final rpc = _FakeRpc(const {});
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    expect(await repository.resolve(''), isNull);
    expect(await repository.save('AB' * 32), isNull);
    expect(await repository.accept('a' * 63), isNull);
    expect(rpc.calls, isEmpty);
  });

  test('a PostgrestException from rpc is not turned into an empty result', () async {
    final rpc = _FakeRpc(const {});
    rpc.handler = (functionName, params) {
      throw const PostgrestException(message: 'Приглашение недоступно');
    };
    final repository = SupabaseGroupInvitationRepository(rpc: rpc.call);

    expect(
      repository.save(token),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.message,
          'message',
          'Приглашение недоступно',
        ),
      ),
    );
  });
}

class _FakeRpc {
  _FakeRpc(this.responses);

  final Map<String, Object?> responses;
  final calls = <(String, Map<String, dynamic>)>[];
  Object? Function(String functionName, Map<String, dynamic> params)? handler;

  Future<Object?> call(String functionName, Map<String, dynamic> params) async {
    calls.add((functionName, params));
    final handler = this.handler;
    if (handler != null) {
      return handler(functionName, params);
    }
    return responses[functionName];
  }
}
