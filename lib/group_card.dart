import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_status_style.dart';
import 'package:geo_groups/theme/app_theme.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
    this.onInvite,
  });

  final GeoGroup group;
  final VoidCallback onTap;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final participating = !group.currentUserHasLeft;
    final onInvite = this.onInvite;
    final cardColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : AppColors.surfaceContainer;
    final statusStyle = GroupStatusStyle.of(colorScheme, group);
    const cardRadius = 18.0;

    return Opacity(
      opacity: group.isFinished ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: AppTheme.cardShadows(colorScheme.brightness),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(cardRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                style: textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GroupStatusBadge(group: group),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Начало ${formatGroupSchedulePoint(group.startsAt)}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (group.endsAt case final endsAt?) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Окончание ${formatGroupSchedulePoint(endsAt)}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                children: [
                                  Icon(
                                    participating
                                        ? Icons.check_circle
                                        : Icons.logout,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      participating
                                          ? 'Участвую'
                                          : 'Покинул группу',
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Участников: ${group.activeMemberCount}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
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
                        if (group.isUpcoming) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Карта и обмен геопозицией станут доступны после начала',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: onTap,
                              child: const Text('Подробнее'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onInvite != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: onInvite,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Пригласить в группу'),
                      ),
                    ),
                  ),
              ],
            ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: GroupStatusStripe(color: statusStyle.line),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Правая полоса статуса. Лежит внутри обрезанной карточки и тянется по её высоте.
class GroupStatusStripe extends StatelessWidget {
  const GroupStatusStripe({super.key, required this.color});

  final Color color;

  static const width = 4.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ColoredBox(color: color),
    );
  }
}

