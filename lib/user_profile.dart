import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/theme/app_theme.dart';

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.avatarId,
  });

  final String userId;
  final String displayName;
  final String avatarId;
}

class ProfileAvatarOption {
  const ProfileAvatarOption({
    required this.id,
    required this.color,
    required this.icon,
  });

  final String id;
  final Color color;
  final IconData icon;
}

const profileAvatarOptions = <ProfileAvatarOption>[
  ProfileAvatarOption(
    id: defaultAvatarId,
    color: AppColors.primary,
    icon: Icons.person,
  ),
  ProfileAvatarOption(
    id: 'blue_face',
    color: AppColors.tertiary,
    icon: Icons.face,
  ),
  ProfileAvatarOption(
    id: 'green_hiking',
    color: AppColors.onPrimaryContainer,
    icon: Icons.hiking,
  ),
  ProfileAvatarOption(
    id: 'orange_bike',
    color: AppColors.error,
    icon: Icons.directions_bike,
  ),
  ProfileAvatarOption(
    id: 'purple_pets',
    color: AppColors.primaryContainerDark,
    icon: Icons.pets,
  ),
  ProfileAvatarOption(
    id: 'amber_star',
    color: AppColors.errorContainerDark,
    icon: Icons.star,
  ),
  ProfileAvatarOption(
    id: 'red_favorite',
    color: AppColors.onSurface,
    icon: Icons.favorite,
  ),
  ProfileAvatarOption(
    id: 'indigo_palette',
    color: AppColors.onSurfaceVariant,
    icon: Icons.palette,
  ),
  ProfileAvatarOption(
    id: 'brown_park',
    color: AppColors.secondaryContainerDark,
    icon: Icons.park,
  ),
  ProfileAvatarOption(
    id: 'cyan_walk',
    color: AppColors.onErrorContainer,
    icon: Icons.directions_walk,
  ),
];

ProfileAvatarOption? profileAvatarById(String avatarId) {
  for (final option in profileAvatarOptions) {
    if (option.id == avatarId) {
      return option;
    }
  }
  return null;
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarId,
    required this.displayName,
    this.radius = 28,
  });

  final String avatarId;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final option = profileAvatarById(avatarId);
    if (option == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary,
        child: Text(
          memberInitials(displayName),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: option.color,
      child: Icon(
        option.icon,
        color: Theme.of(context).colorScheme.onPrimary,
        size: radius,
      ),
    );
  }
}

abstract class UserProfileRepository {
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  });

  Future<void> saveProfile(UserProfile profile);
}

class UserProfileStore implements UserProfileRepository {
  UserProfileStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static final UserProfileStore instance = UserProfileStore();

  static String _nameKey(String userId) => 'user_profile.$userId.display_name';

  static String _avatarKey(String userId) => 'user_profile.$userId.avatar_id';

  Future<SharedPreferences> _prefs() => _preferences();

  @override
  Future<UserProfile> loadProfile({
    required String userId,
    required String fallbackName,
  }) async {
    final preferences = await _prefs();
    final storedName = preferences.getString(_nameKey(userId));
    final storedAvatar = preferences.getString(_avatarKey(userId));
    final name = storedName?.trim();
    return UserProfile(
      userId: userId,
      displayName: name == null || name.isEmpty ? fallbackName : name,
      avatarId: storedAvatar == null || storedAvatar.isEmpty
          ? defaultAvatarId
          : storedAvatar,
    );
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    final name = profile.displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(
        profile.displayName,
        'displayName',
        'Пустое имя сохранять нельзя',
      );
    }
    final preferences = await _prefs();
    await preferences.setString(_nameKey(profile.userId), name);
    await preferences.setString(_avatarKey(profile.userId), profile.avatarId);
  }
}
