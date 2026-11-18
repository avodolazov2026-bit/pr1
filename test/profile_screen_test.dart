import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/profile_screen.dart';
import 'package:geo_groups/user_profile.dart';

void main() {
  testWidgets('empty name shows an error and disables save', (tester) async {
    final repository = _MemoryProfiles()
      ..profiles['anton'] = const UserProfile(
        userId: 'anton',
        displayName: '   ',
        avatarId: defaultAvatarId,
      );

    await _openProfile(
      tester,
      repository,
      userId: 'anton',
      fallbackName: 'Антон',
    );

    expect(find.text('Введите имя'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('valid name, avatar choice and save close the screen', (
    tester,
  ) async {
    final repository = _MemoryProfiles();
    currentDemoUserId = 'elena-kuznetsova';
    addTearDown(() => currentDemoUserId = defaultDemoUserId);

    await _openProfile(
      tester,
      repository,
      userId: 'anton',
      fallbackName: 'Антон',
    );

    expect(
      find.bySemanticsLabel('Выбран аватар $defaultAvatarId'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '  Антон  ');
    await tester.pump();
    expect(find.text('Введите имя'), findsNothing);
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.bySemanticsLabel('Аватар blue_face'));
    await tester.pump();
    expect(find.bySemanticsLabel('Выбран аватар blue_face'), findsOneWidget);
    expect(find.bySemanticsLabel('Аватар $defaultAvatarId'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Мой профиль'), findsNothing);
    expect(find.text('Профиль сохранён'), findsOneWidget);
    expect(repository.saves, hasLength(1));
    expect(repository.saves.single.userId, 'anton');
    expect(repository.saves.single.displayName, 'Антон');
    expect(repository.saves.single.avatarId, 'blue_face');
    expect(currentDemoUserId, 'elena-kuznetsova');
  });

  testWidgets('a late load for the previous user does not replace the form', (
    tester,
  ) async {
    final repository = _DeferredProfiles();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          userId: 'anton',
          fallbackName: 'Антон',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          userId: 'boris',
          fallbackName: 'Борис',
          repository: repository,
        ),
      ),
    );
    repository.complete(
      'anton',
      const UserProfile(
        userId: 'anton',
        displayName: 'Антон',
        avatarId: 'red_favorite',
      ),
    );
    await tester.pump();
    expect(find.text('Антон'), findsNothing);

    repository.complete(
      'boris',
      const UserProfile(
        userId: 'boris',
        displayName: 'Борис',
        avatarId: 'green_hiking',
      ),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Борис',
    );
    expect(find.bySemanticsLabel('Выбран аватар green_hiking'), findsOneWidget);
    expect(repository.saves, isEmpty);
  });

  testWidgets('unknown avatar falls back to initials', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            avatarId: 'missing',
            displayName: 'Анна Смирнова',
            radius: 28,
          ),
        ),
      ),
    );

    expect(find.text('АС'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
  });
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Сохранить'),
  );
}

Future<void> _openProfile(
  WidgetTester tester,
  UserProfileRepository repository, {
  required String userId,
  required String fallbackName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ProfileScreen(
                      userId: userId,
                      fallbackName: fallbackName,
                      repository: repository,
                    ),
                  ),
                );
              },
              child: const Text('Открыть профиль'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Открыть профиль'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _MemoryProfiles implements UserProfileRepository {
  final Map<String, UserProfile> profiles = {};
  final List<UserProfile> saves = [];

  @override
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  }) async {
    return profiles[userId] ??
        UserProfile(
          userId: userId,
          displayName: fallbackName,
          avatarId: defaultAvatarId,
        );
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saves.add(profile);
    profiles[profile.userId] = profile;
  }
}

class _DeferredProfiles implements UserProfileRepository {
  final Map<String, Completer<UserProfile>> _loads = {};
  final List<UserProfile> saves = [];

  void complete(String userId, UserProfile profile) {
    _loads[userId]!.complete(profile);
  }

  @override
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  }) {
    return _loads.putIfAbsent(userId, Completer<UserProfile>.new).future;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    saves.add(profile);
  }
}
