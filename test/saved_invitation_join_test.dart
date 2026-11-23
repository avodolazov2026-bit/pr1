import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/group_invitation_repository.dart';
import 'package:geo_groups/invitations_screen.dart';

void main() {
  testWidgets('join uses the saved invitation id and refreshes the list', (
    tester,
  ) async {
    final invitations = _FakeInvitations(
      saved: [_row('saved-1', 'Прогулка')],
      result: const AcceptResult(
        groupId: 'group-1',
        membershipResult: MembershipResult.joined,
      ),
    );
    var counterRefreshes = 0;
    await _open(
      tester,
      invitations: invitations,
      onChanged: () async {
        counterRefreshes++;
      },
    );

    await tester.tap(find.text('Вступить в группу'));
    await tester.pumpAndSettle();

    expect(invitations.acceptedIds, ['saved-1']);
    expect(invitations.tokenAccepts, 0);
    expect(find.text('Прогулка'), findsNothing);
    expect(find.text('Вы вступили в группу'), findsOneWidget);
    expect(counterRefreshes, 1);
    expect(invitations.listReads, 2);
  });

  testWidgets('an existing membership shows a neutral message and refreshes', (
    tester,
  ) async {
    final invitations = _FakeInvitations(
      saved: [_row('saved-2', 'Поездка')],
      result: const AcceptResult(
        groupId: 'group-2',
        membershipResult: MembershipResult.alreadyMember,
      ),
    );
    var counterRefreshes = 0;
    await _open(
      tester,
      invitations: invitations,
      onChanged: () async {
        counterRefreshes++;
      },
    );

    await tester.tap(find.text('Вступить в группу'));
    await tester.pumpAndSettle();

    expect(invitations.acceptedIds, ['saved-2']);
    expect(find.text('Вы уже участвуете в этой группе'), findsOneWidget);
    expect(counterRefreshes, 1);
    expect(find.text('Поездка'), findsNothing);
  });

  testWidgets('a PostgrestException stays in a snackbar and keeps the row', (
    tester,
  ) async {
    final invitations = _FakeInvitations(
      saved: [_row('saved-3', 'Встреча')],
      error: const PostgrestException(message: 'Приглашение недоступно'),
    );
    var counterRefreshes = 0;
    await _open(
      tester,
      invitations: invitations,
      onChanged: () async {
        counterRefreshes++;
      },
    );

    await tester.tap(find.text('Вступить в группу'));
    await tester.pumpAndSettle();

    expect(find.text('Приглашение недоступно'), findsOneWidget);
    expect(find.text('Встреча'), findsOneWidget);
    expect(find.text('Вступить в группу'), findsOneWidget);
    expect(counterRefreshes, 0);
    expect(invitations.listReads, 1);
  });

  testWidgets('the join button shows progress and ignores another tap', (
    tester,
  ) async {
    final gate = Completer<void>();
    final invitations = _FakeInvitations(
      saved: [_row('saved-4', 'Прогулка')],
      result: const AcceptResult(
        groupId: 'group-4',
        membershipResult: MembershipResult.joined,
      ),
      gate: gate,
    );
    await _open(tester, invitations: invitations);

    await tester.tap(find.text('Вступить в группу'));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    expect(invitations.acceptedIds, ['saved-4']);

    gate.complete();
    await tester.pumpAndSettle();
  });
}

Future<void> _open(
  WidgetTester tester, {
  required _FakeInvitations invitations,
  Future<void> Function()? onChanged,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: InvitationsScreen(
        invitations: invitations,
        onInvitationsChanged: onChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SavedGroupInvitation _row(String id, String name) {
  return SavedGroupInvitation(
    savedInvitationId: id,
    invitationId: 'link-$id',
    groupId: 'group-$id',
    groupName: name,
    startsAt: DateTime.utc(2026, 11, 20, 9),
    organizerDisplayName: 'Ника',
    isPending: true,
  );
}

class _FakeInvitations implements GroupInvitationRepository {
  _FakeInvitations({
    required this.saved,
    this.result,
    this.error,
    this.gate,
  });

  List<SavedGroupInvitation> saved;
  final AcceptResult? result;
  final PostgrestException? error;
  final Completer<void>? gate;
  final acceptedIds = <String>[];
  var tokenAccepts = 0;
  var listReads = 0;

  @override
  Future<AcceptResult?> acceptSaved(String savedInvitationId) async {
    acceptedIds.add(savedInvitationId);
    final gate = this.gate;
    if (gate != null) {
      await gate.future;
    }
    final error = this.error;
    if (error != null) {
      throw error;
    }
    saved = [
      for (final item in saved)
        if (item.savedInvitationId != savedInvitationId) item,
    ];
    return result;
  }

  @override
  Future<List<SavedGroupInvitation>> listSaved() async {
    listReads++;
    return saved;
  }

  @override
  Future<AcceptResult?> accept(String token) async {
    tokenAccepts++;
    return null;
  }

  @override
  Future<int> countUnseen() async => saved.length;

  @override
  Future<GroupInvitation?> createOrGet(String groupId) async => null;

  @override
  Future<int> markSeen() async => 0;

  @override
  Future<ResolvedInvitation?> resolve(String token) async => null;

  @override
  Future<bool> revoke(String groupId) async => false;

  @override
  Future<SavedGroupInvitation?> save(String token) async => null;
}
