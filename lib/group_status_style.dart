import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

/// Цвета линии и бейджа для [GeoGroup.scheduleStatus].
///
/// Подпись бейджа и эта палитра читают один и тот же статус.
class GroupStatusStyle {
  const GroupStatusStyle({
    required this.line,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.icon,
    required this.badgeRadius,
    required this.iconSize,
    this.labelFontSize,
  });

  final Color line;
  final Color badgeBackground;
  final Color badgeForeground;
  final IconData icon;
  final double badgeRadius;
  final double iconSize;
  final double? labelFontSize;

  static GroupStatusStyle of(ColorScheme scheme, GeoGroup group) {
    return switch (group.scheduleStatus) {
      GroupScheduleStatus.active => GroupStatusStyle(
        line: scheme.secondary,
        badgeBackground: scheme.secondary,
        badgeForeground: scheme.onSecondary,
        icon: Icons.play_circle_outline,
        badgeRadius: 100,
        iconSize: 13,
        labelFontSize: 12,
      ),
      GroupScheduleStatus.upcoming => GroupStatusStyle(
        line: scheme.primary,
        badgeBackground: scheme.primary,
        badgeForeground: scheme.onPrimary,
        icon: Icons.event_outlined,
        badgeRadius: 8,
        iconSize: 16,
      ),
      GroupScheduleStatus.finished => _neutral(scheme),
      GroupScheduleStatus.cancelled => GroupStatusStyle(
        line: scheme.error,
        badgeBackground: scheme.error,
        badgeForeground: scheme.onError,
        icon: Icons.event_busy_outlined,
        badgeRadius: 8,
        iconSize: 16,
      ),
      GroupScheduleStatus.expired => GroupStatusStyle(
        line: scheme.onErrorContainer,
        badgeBackground: scheme.errorContainer,
        badgeForeground: scheme.onErrorContainer,
        icon: Icons.history,
        badgeRadius: 8,
        iconSize: 16,
      ),
    };
  }

  static GroupStatusStyle _neutral(ColorScheme scheme) {
    return GroupStatusStyle(
      line: scheme.onSurfaceVariant,
      badgeBackground: scheme.onSurfaceVariant,
      badgeForeground: scheme.surface,
      icon: Icons.history,
      badgeRadius: 8,
      iconSize: 16,
    );
  }
}

/// Бейдж статуса. Подпись и цвет берутся из одной и той же группы.
class GroupStatusBadge extends StatelessWidget {
  const GroupStatusBadge({super.key, required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = GroupStatusStyle.of(Theme.of(context).colorScheme, group);
    final label = group.statusBadge;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.badgeBackground,
        borderRadius: BorderRadius.circular(style.badgeRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              style.icon,
              size: style.iconSize,
              color: style.badgeForeground,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: style.badgeForeground,
                fontSize: style.labelFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
