import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

/// Подписи экрана созданных групп. Сам отбор там по-прежнему смотрит назад.
const createdGroupPeriodLabels = <GroupPeriod, String>{
  GroupPeriod.week: 'Неделя',
  GroupPeriod.month: 'Месяц',
  GroupPeriod.year: 'Год',
};

/// Подписи фильтра «Мои группы»: окно вперёд от начала текущих суток.
const myGroupsPeriodLabels = <GroupPeriod, String>{
  GroupPeriod.week: '7 дней',
  GroupPeriod.month: '30 дней',
  GroupPeriod.year: '365 дней',
};

/// Общий переключатель периода. Подписи задаёт экран.
class GroupPeriodSelector extends StatelessWidget {
  const GroupPeriodSelector({
    super.key,
    required this.period,
    required this.onChanged,
    this.labels = createdGroupPeriodLabels,
  });

  final GroupPeriod period;
  final ValueChanged<GroupPeriod> onChanged;
  final Map<GroupPeriod, String> labels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<GroupPeriod>(
        showSelectedIcon: false,
        segments: [
          for (final value in GroupPeriod.values)
            ButtonSegment(
              value: value,
              label: Text(
                labels[value]!,
                style: TextStyle(
                  fontWeight: period == value
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
        ],
        selected: {period},
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return colorScheme.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
        ),
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// Окно вперёд от начала локальных суток [now].
///
/// [start] включительно, [end] исключительно. Правая граница — местная
/// полночь через 7, 30 или 365 календарных суток, без [Duration]: иначе
/// переход на летнее или зимнее время сдвигает её на 23:00 или 01:00.
({DateTime start, DateTime end}) groupPeriodBounds(
  GroupPeriod period,
  DateTime now,
) {
  final local = now.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  final end = switch (period) {
    GroupPeriod.week => DateTime(start.year, start.month, start.day + 7),
    GroupPeriod.month => DateTime(start.year, start.month, start.day + 30),
    GroupPeriod.year => DateTime(start.year, start.month, start.day + 365),
  };
  return (start: start, end: end);
}

/// Входит ли начало группы в окно [period] от локальной даты [now].
bool groupStartsInPeriod(DateTime startsAt, GroupPeriod period, DateTime now) {
  final local = startsAt.toLocal();
  final bounds = groupPeriodBounds(period, now);
  return !local.isBefore(bounds.start) && local.isBefore(bounds.end);
}
