import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geo_groups/geo_group.dart';

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
    color: Color(0xFF00796B),
    icon: Icons.person,
  ),
  ProfileAvatarOption(
    id: 'blue_face',
    color: Color(0xFF1565C0),
    icon: Icons.face,
  ),
  ProfileAvatarOption(
    id: 'green_hiking',
    color: Color(0xFF2E7D32),
    icon: Icons.hiking,
  ),
  ProfileAvatarOption(
    id: 'orange_bike',
    color: Color(0xFFEF6C00),
    icon: Icons.directions_bike,
  ),
  ProfileAvatarOption(
    id: 'purple_pets',
    color: Color(0xFF6A1B9A),
    icon: Icons.pets,
  ),
  ProfileAvatarOption(
    id: 'amber_star',
    color: Color(0xFFF57F17),
    icon: Icons.star,
  ),
  ProfileAvatarOption(
    id: 'red_favorite',
    color: Color(0xFFC62828),
    icon: Icons.favorite,
  ),
  ProfileAvatarOption(
    id: 'indigo_palette',
    color: Color(0xFF283593),
    icon: Icons.palette,
  ),
  ProfileAvatarOption(
    id: 'brown_park',
    color: Color(0xFF6D4C41),
    icon: Icons.park,
  ),
  ProfileAvatarOption(
    id: 'cyan_walk',
    color: Color(0xFF00838F),
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
        backgroundColor: const Color(0xFF00796B),
        child: Text(
          memberInitials(displayName),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: option.color,
      child: Icon(option.icon, color: Colors.white, size: radius),
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
