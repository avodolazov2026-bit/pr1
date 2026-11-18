import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/app_link_handler.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    currentDemoUserId = 'elena-kuznetsova';
  });

  GeoGroup addJoinableGroup({
    required String id,
    required String token,
    required DateTime startsAt,
    DateTime? endsAt,
  }) {
    final group = GeoGroup(
      id: id,
      name: 'Группа $id',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      startsAt: startsAt,
      endsAt: endsAt,
      createdByUserId: 'organizer-$id',
      qrInviteToken: token,
      members: [
        GroupMember(
          id: 'organizer-$id',
          name: 'Организатор',
          role: MemberRole.organizer,
        ),
      ],
    );
    GroupsStore.instance.addGroup(group);
    return group;
  }

  test('a geo-groups join URI is recognized and other URIs are ignored', () {
    final now = DateTime.now();
    final active = addJoinableGroup(
      id: 'group-1',
      token: 'qr-2',
      startsAt: now.subtract(const Duration(hours: 1)),
      endsAt: now.add(const Duration(hours: 2)),
    );
    final planned = addJoinableGroup(
      id: 'group-planned',
      token: 'qr-planned',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
    );

    final activeUri = Uri.parse(
      'geo-groups://join?groupId=group-1&inviteToken=qr-2',
    );
    expect(isGroupJoinLink(activeUri), isTrue);
    final activeLink = resolveGroupInviteLink(activeUri);
    expect(activeLink.opensConfirmation, isTrue);
    expect(activeLink.group, same(active));
    expect(
      active.members.any((member) => member.id == currentDemoUserId),
      isFalse,
    );

    final plannedLink = resolveGroupInviteLink(
      Uri.parse(
        'geo-groups://join?groupId=group-planned&inviteToken=qr-planned',
      ),
    );
    expect(planned.isUpcoming, isTrue);
    expect(plannedLink.opensConfirmation, isTrue);

    expect(
      resolveGroupInviteLink(
        Uri.parse('https://example.com/join?groupId=group-1&inviteToken=qr-2'),
      ).opensConfirmation,
      isFalse,
    );
    expect(
      resolveGroupInviteLink(
        Uri.parse('https://example.com/join?groupId=group-1&inviteToken=qr-2'),
      ).kind,
      GroupInviteLinkKind.ignore,
    );
    expect(
      resolveGroupInviteLink(Uri.parse('geo-groups://other-screen')).kind,
      GroupInviteLinkKind.ignore,
    );

    final invalid = resolveGroupInviteLink(
      Uri.parse('geo-groups://join?groupId=group-1&inviteToken=wrong'),
    );
    expect(invalid.opensConfirmation, isFalse);
    expect(invalid.kind, GroupInviteLinkKind.rejected);
    expect(invalid.message, 'Приглашение недействительно');
  });

  testWidgets('a join link confirms before adding the member', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final group = addJoinableGroup(
      id: 'deep-link-active',
      token: 'deep-token',
      startsAt: now.subtract(const Duration(minutes: 20)),
      endsAt: now.add(const Duration(hours: 3)),
    );
    final uri = Uri.parse(
      'geo-groups://join?groupId=deep-link-active&inviteToken=deep-token',
    );
    final links = StreamController<Uri>();
    addTearDown(links.close);

    await tester.pumpWidget(
      MyApp(inviteLinks: _Feed(initial: null, links: links.stream)),
    );
    await tester.pump();
    await tester.pump();

    links.add(uri);
    links.add(uri);
    await tester.pumpAndSettle();

    expect(find.text('Вступление в группу'), findsOneWidget);
    expect(
      group.members.any((member) => member.id == currentDemoUserId),
      isFalse,
    );

    await tester.tap(find.text('Вступить в группу'));
    await tester.pumpAndSettle();

    expect(find.text('Вступление в группу'), findsNothing);
    expect(find.text('Вы вступили в группу'), findsOneWidget);
    expect(
      group.members.any((member) => member.id == currentDemoUserId),
      isTrue,
    );
  });

  testWidgets('cold start opens confirmation from the initial link', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final group = addJoinableGroup(
      id: 'cold-link',
      token: 'cold-token',
      startsAt: now.subtract(const Duration(minutes: 20)),
      endsAt: now.add(const Duration(hours: 3)),
    );
    final uri = Uri.parse(
      'geo-groups://join?groupId=cold-link&inviteToken=cold-token',
    );

    await tester.pumpWidget(
      MyApp(
        inviteLinks: _Feed(initial: uri, links: const Stream<Uri>.empty()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вступление в группу'), findsOneWidget);
    expect(
      group.members.any((member) => member.id == currentDemoUserId),
      isFalse,
    );
  });

  testWidgets(
    'a second different join link is ignored while confirmation is open',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final first = addJoinableGroup(
        id: 'first-link',
        token: 'first-token',
        startsAt: now.subtract(const Duration(minutes: 20)),
        endsAt: now.add(const Duration(hours: 3)),
      );
      final second = addJoinableGroup(
        id: 'second-link',
        token: 'second-token',
        startsAt: now.subtract(const Duration(minutes: 10)),
        endsAt: now.add(const Duration(hours: 4)),
      );
      final links = StreamController<Uri>();
      addTearDown(links.close);

      await tester.pumpWidget(
        MyApp(inviteLinks: _Feed(initial: null, links: links.stream)),
      );
      await tester.pump();
      await tester.pump();

      links.add(
        Uri.parse(
          'geo-groups://join?groupId=first-link&inviteToken=first-token',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Вступление в группу'), findsOneWidget);
      expect(find.text(first.name), findsOneWidget);

      links.add(
        Uri.parse(
          'geo-groups://join?groupId=second-link&inviteToken=second-token',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Вступление в группу'), findsOneWidget);
      expect(find.text(first.name), findsOneWidget);
      expect(find.text(second.name), findsNothing);

      await tester.tap(find.text('Вступить в группу'));
      await tester.pumpAndSettle();

      expect(find.text('Вступление в группу'), findsNothing);
      expect(find.text(second.name), findsNothing);
      expect(
        first.members.any((member) => member.id == currentDemoUserId),
        isTrue,
      );
      expect(
        second.members.any((member) => member.id == currentDemoUserId),
        isFalse,
      );
    },
  );

  testWidgets('a wrong invite token does not open confirmation', (
    tester,
  ) async {
    final now = DateTime.now();
    addJoinableGroup(
      id: 'deep-link-bad',
      token: 'real-token',
      startsAt: now.subtract(const Duration(minutes: 20)),
      endsAt: now.add(const Duration(hours: 3)),
    );
    final links = StreamController<Uri>();
    addTearDown(links.close);

    await tester.pumpWidget(
      MyApp(inviteLinks: _Feed(initial: null, links: links.stream)),
    );
    await tester.pump();
    await tester.pump();

    links
      ..add(Uri.parse('https://example.com/join?groupId=deep-link-bad'))
      ..add(Uri.parse('geo-groups://other-screen'))
      ..add(
        Uri.parse(
          'geo-groups://join?groupId=deep-link-bad&inviteToken=wrong-token',
        ),
      );
    await tester.pumpAndSettle();

    expect(find.text('Вступление в группу'), findsNothing);
    expect(find.text('Приглашение недействительно'), findsOneWidget);
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
