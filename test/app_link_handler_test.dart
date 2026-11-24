import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/app_link_handler.dart';
import 'package:geo_groups/group_invitation_repository.dart';
import 'package:geo_groups/main.dart';

const _token =
    'abababababababababababababababababababababababababababababababab';
const _other =
    'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only an https qunora invite with a 64-hex token is a join link', () {
    final uri = Uri.parse('https://qunora.pro/invite/$_token');
    expect(isGroupJoinLink(uri), isTrue);
    expect(groupInviteTokenFromUri(uri), _token);

    expect(
      isGroupJoinLink(
        Uri.parse('geo-groups://join?groupId=group-1&inviteToken=qr-2'),
      ),
      isFalse,
    );
    expect(
      isGroupJoinLink(Uri.parse('https://example.com/invite/$_token')),
      isFalse,
    );
    expect(
      isGroupJoinLink(Uri.parse('geo-groups://other-screen')),
      isFalse,
    );
    expect(
      isGroupJoinLink(
        Uri.parse('https://qunora.pro/invite/$_token?groupId=group-1'),
      ),
      isFalse,
    );
    expect(
      isMalformedGroupInviteLink(Uri.parse('https://qunora.pro/invite/qr-2')),
      isTrue,
    );
    expect(
      isMalformedGroupInviteLink(Uri.parse('https://example.com/invite/qr-2')),
      isFalse,
    );
    expect(
      isMalformedGroupInviteLink(Uri.parse('geo-groups://join?groupId=a')),
      isFalse,
    );
  });

  testWidgets('a join link is saved and does not join the group locally', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final invites = _Invites();
    final links = StreamController<Uri>();
    addTearDown(links.close);

    await tester.pumpWidget(
      MyApp(
        invitations: invites,
        inviteLinks: _Feed(initial: null, links: links.stream),
      ),
    );
    await tester.pump();
    await tester.pump();

    links.add(Uri.parse('https://qunora.pro/invite/$_token'));
    links.add(Uri.parse('https://qunora.pro/invite/$_token'));
    invites.release();
    await tester.pumpAndSettle();

    expect(invites.resolved, [_token]);
    expect(invites.saved, [_token]);
    expect(find.text('Приглашение добавлено в список.'), findsOneWidget);
    expect(find.text('Вступление в группу'), findsNothing);
  });

  testWidgets('cold start saves the initial invite link', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final invites = _Invites()..release();
    await tester.pumpWidget(
      MyApp(
        invitations: invites,
        inviteLinks: _Feed(
          initial: Uri.parse('https://qunora.pro/invite/$_token'),
          links: const Stream<Uri>.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(invites.resolved, [_token]);
    expect(invites.saved, [_token]);
    expect(find.text('Приглашение добавлено в список.'), findsOneWidget);
    expect(find.text('Вступление в группу'), findsNothing);
  });

  testWidgets('a second invite is ignored while the first request is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final invites = _Invites();
    final links = StreamController<Uri>();
    addTearDown(links.close);

    await tester.pumpWidget(
      MyApp(
        invitations: invites,
        inviteLinks: _Feed(initial: null, links: links.stream),
      ),
    );
    await tester.pump();
    await tester.pump();

    links.add(Uri.parse('https://qunora.pro/invite/$_token'));
    await tester.pump();
    links.add(Uri.parse('https://qunora.pro/invite/$_other'));
    await tester.pump();

    expect(invites.resolved, [_token]);
    expect(invites.saved, isEmpty);

    invites.release();
    await tester.pumpAndSettle();

    expect(invites.resolved, [_token]);
    expect(invites.saved, [_token]);
    expect(find.text('Вступление в группу'), findsNothing);
  });

  testWidgets('a foreign or malformed link does not call resolve', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final invites = _Invites()..release();
    final links = StreamController<Uri>();
    addTearDown(links.close);

    await tester.pumpWidget(
      MyApp(
        invitations: invites,
        inviteLinks: _Feed(initial: null, links: links.stream),
      ),
    );
    await tester.pump();
    await tester.pump();

    links
      ..add(Uri.parse('https://example.com/invite/$_token'))
      ..add(Uri.parse('geo-groups://other-screen'))
      ..add(
        Uri.parse(
          'geo-groups://join?groupId=deep-link-bad&inviteToken=wrong-token',
        ),
      )
      ..add(Uri.parse('https://qunora.pro/invite/qr-2'));
    await tester.pumpAndSettle();

    expect(invites.resolved, isEmpty);
    expect(invites.saved, isEmpty);
    expect(find.text('Вступление в группу'), findsNothing);
    expect(find.text('Не удалось распознать приглашение'), findsOneWidget);
  });
}

class _Feed implements InviteLinkSource {
  _Feed({required this.initial, required this.links});

  final Uri? initial;
  final Stream<Uri> links;

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get uriStream => links;
}

class _Invites implements GroupInvitationRepository {
  final resolved = <String>[];
  final saved = <String>[];
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<ResolvedInvitation?> resolve(String token) async {
    resolved.add(token);
    await _gate.future;
    return ResolvedInvitation(
      invitationId: 'invitation',
      groupId: 'group',
      groupName: 'Группа',
      startsAt: DateTime.utc(2026, 1, 1),
      organizerDisplayName: 'Организатор',
    );
  }

  @override
  Future<SavedGroupInvitation?> save(String token) async {
    saved.add(token);
    return SavedGroupInvitation(
      savedInvitationId: 'saved',
      invitationId: 'invitation',
      groupId: 'group',
      groupName: 'Группа',
      startsAt: DateTime.utc(2026, 1, 1),
      organizerDisplayName: 'Организатор',
      isPending: true,
    );
  }

  @override
  Future<GroupInvitation?> createOrGet(String groupId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> revoke(String groupId) {
    throw UnimplementedError();
  }

  @override
  Future<List<SavedGroupInvitation>> listSaved() async => const [];

  @override
  Future<int> countUnseen() async => 0;

  @override
  Future<int> markSeen() async => 0;

  @override
  Future<AcceptResult?> accept(String token) {
    throw UnimplementedError();
  }

  @override
  Future<AcceptResult?> acceptSaved(String savedInvitationId) {
    throw UnimplementedError();
  }
}
