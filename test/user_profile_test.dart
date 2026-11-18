import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    store = UserProfileStore(preferences: () async => preferences);
  });

  test('unsaved profile uses the fallback name and default avatar', () async {
    final profile = await store.loadProfile(
      userId: 'anton',
      fallbackName: 'Антон',
    );

    expect(profile.userId, 'anton');
    expect(profile.displayName, 'Антон');
    expect(profile.avatarId, defaultAvatarId);
  });

  test(
    'saved profiles stay separate for each user and survive reload',
    () async {
      await store.saveProfile(
        const UserProfile(
          userId: 'anton',
          displayName: '  Антон  ',
          avatarId: 'blue_face',
        ),
      );
      await store.saveProfile(
        const UserProfile(
          userId: 'boris',
          displayName: 'Борис',
          avatarId: 'green_hiking',
        ),
      );

      final reloaded = UserProfileStore();
      final anton = await reloaded.loadProfile(
        userId: 'anton',
        fallbackName: 'Другое имя',
      );
      final boris = await reloaded.loadProfile(
        userId: 'boris',
        fallbackName: 'Другое имя',
      );

      expect(anton.displayName, 'Антон');
      expect(anton.avatarId, 'blue_face');
      expect(boris.displayName, 'Борис');
      expect(boris.avatarId, 'green_hiking');
    },
  );

  test('an empty name is not written', () async {
    await store.saveProfile(
      const UserProfile(
        userId: 'anton',
        displayName: 'Антон',
        avatarId: 'blue_face',
      ),
    );

    await expectLater(
      store.saveProfile(
        const UserProfile(
          userId: 'anton',
          displayName: '   ',
          avatarId: 'red_favorite',
        ),
      ),
      throwsArgumentError,
    );

    final profile = await store.loadProfile(
      userId: 'anton',
      fallbackName: 'Запасное',
    );
    expect(profile.displayName, 'Антон');
    expect(profile.avatarId, 'blue_face');
  });
}
