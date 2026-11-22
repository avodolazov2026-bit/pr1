import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/auth_repository.dart';
import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/phone_auth_screen.dart';
import 'package:geo_groups/profile_screen.dart';
import 'package:geo_groups/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<GeoGroup> groupsBefore;

  setUp(() {
    currentDemoUserId = defaultDemoUserId;
    groupsBefore = List<GeoGroup>.of(GroupsStore.instance.groups);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    currentDemoUserId = defaultDemoUserId;
    GroupsStore.instance.groups
      ..clear()
      ..addAll(groupsBefore);
  });

  test('phone numbers normalize to E.164 and mask the middle', () {
    expect(normalizePhoneE164(''), isNull);
    expect(normalizePhoneE164('12'), isNull);
    expect(normalizePhoneE164('8 999 123-45-67'), '+79991234567');
    expect(normalizePhoneE164('79991234567'), '+79991234567');
    expect(normalizePhoneE164('9991234567'), '+79991234567');
    expect(normalizePhoneE164('+1 202 555 0143'), '+12025550143');
    expect(maskPhoneNumber('+79991234567'), '+7 ••• •••-45-67');
  });

  test('only a confirmed phone user counts as signed in', () {
    expect(accountFromSupabaseUser(null).needsPhoneSignIn, isTrue);
    expect(
      accountFromSupabaseUser(_user(isAnonymous: true, phone: '+79991234567'))
          .needsPhoneSignIn,
      isTrue,
    );
    expect(
      accountFromSupabaseUser(_user(phone: '+79991234567')).needsPhoneSignIn,
      isTrue,
    );
    final confirmed = accountFromSupabaseUser(
      _user(phone: '+79991234567', phoneConfirmedAt: '2026-11-22T00:00:00Z'),
    );
    expect(confirmed.needsPhoneSignIn, isFalse);
    expect(confirmed.phoneE164, '+79991234567');
  });

  testWidgets('an anonymous profile offers phone sign-in', (tester) async {
    final auth = _FakeAuth(const AuthAccount.anonymous());

    await _openProfile(tester, auth);

    expect(find.text('Войти или зарегистрироваться'), findsOneWidget);
    expect(
      find.text(
        'Войдите по номеру телефона, чтобы создавать группы',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Войти или зарегистрироваться'));
    await tester.pumpAndSettle();

    expect(find.text('Войдите по номеру телефона'), findsOneWidget);
  });

  testWidgets('a confirmed profile shows the masked number and sign-out', (
    tester,
  ) async {
    final auth = _FakeAuth(const AuthAccount.confirmed('+79991234567'));

    await _openProfile(tester, auth);

    expect(find.text('Номер телефона'), findsOneWidget);
    expect(find.text('+7 ••• •••-45-67'), findsOneWidget);
    expect(find.text('Номер подтверждён'), findsOneWidget);
    expect(find.text('Войти или зарегистрироваться'), findsNothing);

    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Выйти'));
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    expect(find.text('Войти или зарегистрироваться'), findsOneWidget);
    expect(find.text('Номер подтверждён'), findsNothing);
  });

  testWidgets(
    'sign-out keeps the phone account cleared when anonymous restore fails',
    (tester) async {
      final auth = _FakeAuth(const AuthAccount.confirmed('+79991234567'))
        ..restoreAnonymousSession = false;

      await _openProfile(tester, auth);
      await tester.tap(find.text('Выйти из аккаунта'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Выйти'));
      await tester.pumpAndSettle();

      expect(find.text('Номер подтверждён'), findsNothing);
      expect(find.text('+7 ••• •••-45-67'), findsNothing);
      expect(find.text('Войти или зарегистрироваться'), findsOneWidget);
      expect(
        find.text(AuthSignOutResult.anonymousRestoreNotice),
        findsOneWidget,
      );
      expect(find.text('Не удалось выйти из аккаунта'), findsNothing);
    },
  );

  testWidgets('phone screen waits for a valid number and a confirmed code', (
    tester,
  ) async {
    final auth = _FakeAuth(const AuthAccount.anonymous());
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                final signedIn = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (context) => PhoneAuthScreen(auth: auth),
                  ),
                );
                closed = signedIn == true;
              },
              child: const Text('Открыть вход'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Открыть вход'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Получить код'));
    await tester.pump();
    expect(find.text('Введите номер телефона'), findsOneWidget);
    expect(auth.sent, isEmpty);
    expect(find.text('Код из SMS'), findsNothing);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    expect(
      find.text('Проверьте номер: нужен код страны, например +7'),
      findsOneWidget,
    );
    expect(auth.sent, isEmpty);

    auth.failSend = true;
    await tester.enterText(find.byType(TextField), '8 999 123-45-67');
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    expect(find.text('Не удалось отправить код'), findsOneWidget);
    expect(find.text('Код из SMS'), findsNothing);

    auth.failSend = false;
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    expect(auth.sent, ['+79991234567']);
    expect(find.text('Код из SMS'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(auth.verified, ['123456']);
    expect(find.text('Войдите по номеру телефона'), findsNothing);
  });

  testWidgets('creating a group asks an anonymous user for a phone', (
    tester,
  ) async {
    final auth = _FakeAuth(const AuthAccount.anonymous());
    await _openCreate(tester, auth);
    await tester.tap(find.text('Создать группу').first);
    await tester.pumpAndSettle();

    expect(find.text(phoneSignInDialogMessage), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Войти'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9991234567');
    await tester.tap(find.text('Получить код'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '654321');
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();

    expect(_named('После входа'), isEmpty);
    expect(auth.current.needsPhoneSignIn, isFalse);
    await _submitIndefiniteGroup(tester, 'После входа');
    expect(_named('После входа'), hasLength(1));
  });

  testWidgets('cancelling phone sign-in does not create a group', (
    tester,
  ) async {
    final auth = _FakeAuth(const AuthAccount.anonymous());
    await _openCreate(tester, auth);
    await tester.tap(find.text('Создать группу').first);
    await tester.pumpAndSettle();

    expect(find.text(phoneSignInDialogMessage), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Войти'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_named('Не создавать'), isEmpty);
    expect(auth.sent, isEmpty);
    expect(find.text('Новая группа'), findsNothing);
  });

  testWidgets('a confirmed phone skips the auth screen', (tester) async {
    final auth = _FakeAuth(const AuthAccount.confirmed('+79990000000'));
    await _openCreate(tester, auth);
    await _submitIndefiniteGroup(tester, 'Сразу создана');

    expect(find.text('Войдите по номеру телефона'), findsNothing);
    expect(_named('Сразу создана'), hasLength(1));
    expect(auth.sent, isEmpty);
  });
}

User _user({
  bool isAnonymous = false,
  String? phone,
  String? phoneConfirmedAt,
}) {
  return User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-11-22T00:00:00Z',
    phone: phone,
    phoneConfirmedAt: phoneConfirmedAt,
    isAnonymous: isAnonymous,
  );
}

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.account);

  AuthAccount account;
  final sent = <String>[];
  final verified = <String>[];
  var failSend = false;
  var signOuts = 0;
  var restoreAnonymousSession = true;

  @override
  AuthAccount get current => account;

  @override
  Future<void> sendPhoneOtp(String phoneE164) async {
    if (failSend) {
      throw const AuthRequestException('Не удалось отправить код');
    }
    sent.add(phoneE164);
  }

  @override
  Future<void> verifyPhoneOtp({
    required String phoneE164,
    required String code,
  }) async {
    verified.add(code);
    account = AuthAccount.confirmed(phoneE164);
  }

  @override
  Future<AuthSignOutResult> signOut() async {
    signOuts += 1;
    account = const AuthAccount.anonymous();
    return AuthSignOutResult(
      anonymousSessionRestored: restoreAnonymousSession,
      notice: restoreAnonymousSession
          ? null
          : AuthSignOutResult.anonymousRestoreNotice,
    );
  }
}

class _MemoryProfiles implements UserProfileRepository {
  @override
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  }) async {
    return UserProfile(
      userId: userId,
      displayName: fallbackName,
      avatarId: defaultAvatarId,
    );
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {}
}

Future<void> _openProfile(WidgetTester tester, _FakeAuth auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        userId: 'profile-user',
        fallbackName: 'Ника',
        repository: _MemoryProfiles(),
        auth: auth,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCreate(WidgetTester tester, AuthRepository auth) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: CreatedGroupsScreen(auth: auth)));
}

Future<void> _submitIndefiniteGroup(WidgetTester tester, String name) async {
  await tester.tap(find.text('Создать группу').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.ensureVisible(find.text('Бессрочная группа'));
  await tester.tap(find.text('Бессрочная группа'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать'));
  await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
  await tester.pumpAndSettle();
}

Iterable<GeoGroup> _named(String name) {
  return GroupsStore.instance.groups.where((group) => group.name == name);
}
