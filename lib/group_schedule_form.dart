import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

enum GroupScheduleField { start, end, name }

class GroupFormIssue {
  const GroupFormIssue({
    required this.message,
    required this.field,
    required this.highlightFields,
  });

  final String message;
  final GroupScheduleField field;
  final bool highlightFields;
}

const missingScheduleEndMessage = 'Выберите дату и время завершения';
const emptyGroupNameMessage = 'Введите название группы';

String groupScheduleFormMessage(String issue) {
  return switch (issue) {
    'Начало группы должно быть в будущем' =>
      'Время начала должно быть позже текущего времени',
    'Окончание должно быть позже начала' =>
      'Время окончания должно быть позже времени начала',
    _ => issue,
  };
}

GroupScheduleField groupScheduleFieldFor(String issue) {
  return switch (issue) {
    'Начало группы должно быть в будущем' ||
    'Время начала активной группы нельзя изменить.' => GroupScheduleField.start,
    _ => GroupScheduleField.end,
  };
}

bool groupScheduleHighlightsFields(String issue) {
  return switch (issue) {
    'Начало группы должно быть в будущем' ||
    'Окончание должно быть позже начала' ||
    'Нельзя выбрать дату и время в прошлом' ||
    'Нельзя продлить срок группы: это потребует нового согласия участников.' =>
      true,
    _ => false,
  };
}

String? validateEditableSchedule({
  required DateTime originalStartsAt,
  required DateTime nextStartsAt,
  required DateTime? originalEndsAt,
  required DateTime? nextEndsAt,
  required bool upcoming,
  required bool endOmitted,
}) {
  if (endOmitted) {
    if (upcoming || nextStartsAt != originalStartsAt) {
      final startIssue = validateGroupSchedule(
        originalStartsAt: originalStartsAt,
        nextStartsAt: nextStartsAt,
        originalEndsAt: originalEndsAt,
        nextEndsAt: upcoming ? null : originalEndsAt,
        upcoming: upcoming,
      );
      if (startIssue != null &&
          groupScheduleFieldFor(startIssue) == GroupScheduleField.start) {
        return startIssue;
      }
    }
    return missingScheduleEndMessage;
  }
  return validateGroupSchedule(
    originalStartsAt: originalStartsAt,
    nextStartsAt: nextStartsAt,
    originalEndsAt: originalEndsAt,
    nextEndsAt: nextEndsAt,
    upcoming: upcoming,
  );
}

GroupFormIssue? groupFormIssue({
  required String name,
  required DateTime originalStartsAt,
  required DateTime nextStartsAt,
  required DateTime? originalEndsAt,
  required DateTime? nextEndsAt,
  required bool upcoming,
  required bool endOmitted,
  String? extraError,
}) {
  final raw = validateEditableSchedule(
    originalStartsAt: originalStartsAt,
    nextStartsAt: nextStartsAt,
    originalEndsAt: originalEndsAt,
    nextEndsAt: nextEndsAt,
    upcoming: upcoming,
    endOmitted: endOmitted,
  );
  if (raw != null) {
    return GroupFormIssue(
      message: groupScheduleFormMessage(raw),
      field: groupScheduleFieldFor(raw),
      highlightFields: groupScheduleHighlightsFields(raw),
    );
  }
  if (extraError != null) {
    return GroupFormIssue(
      message: groupScheduleFormMessage(extraError),
      field: groupScheduleFieldFor(extraError),
      highlightFields: groupScheduleHighlightsFields(extraError),
    );
  }
  if (name.trim().isEmpty) {
    return const GroupFormIssue(
      message: emptyGroupNameMessage,
      field: GroupScheduleField.name,
      highlightFields: false,
    );
  }
  return null;
}

class ScheduleOutlinedButton extends StatelessWidget {
  const ScheduleOutlinedButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.invalid,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: invalid
          ? OutlinedButton.styleFrom(
              foregroundColor: error,
              side: BorderSide(color: error),
            )
          : null,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class ScheduleIssueText extends StatelessWidget {
  const ScheduleIssueText(this.message, {super.key, this.small = false});

  final String message;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = small
        ? theme.textTheme.bodySmall
        : theme.textTheme.bodyMedium;
    return Text(
      message,
      style: style?.copyWith(color: theme.colorScheme.error),
    );
  }
}
