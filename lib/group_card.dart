import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, required this.onTap});

  final GeoGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final participating = !group.currentUserHasLeft;

    return Opacity(
      opacity: group.isFinished ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(group.name, style: textTheme.titleMedium),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(group: group),
                  ],
                ),
                const SizedBox(height: 8),
                Text(group.scheduleSummary, style: textTheme.bodyLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      participating ? Icons.check_circle : Icons.logout,
                      size: 18,
                      color: participating
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        participating ? 'Участвую' : 'Покинул группу',
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: participating
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.people_outline,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Участников: ${group.activeMemberCount}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (group.invitedCount > 0) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Приглашены: ${group.invitedCount}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground, icon) = switch (group.statusBadge) {
      'Запланирована' => (
        const Color(0xFFE8F0FE),
        const Color(0xFF1A56C4),
        Icons.event_outlined,
      ),
      'Активна' => (
        const Color(0xFFE6F4EA),
        const Color(0xFF1B7F3A),
        Icons.play_circle_outline,
      ),
      'Отменена' => (
        const Color(0xFFF3F4F6),
        const Color(0xFF4B5563),
        Icons.event_busy_outlined,
      ),
      _ => (const Color(0xFFFDECEA), const Color(0xFFB3261E), Icons.history),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 4),
            Text(
              group.statusBadge,
              style: textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
