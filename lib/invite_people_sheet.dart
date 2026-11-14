import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

class InvitePeopleSheet extends StatefulWidget {
  const InvitePeopleSheet({
    super.key,
    required this.initiallySelectedIds,
    this.excludedIds = const <String>{},
  });

  final Set<String> initiallySelectedIds;

  /// Организатор, активные и уже приглашённые не показываются.
  final Set<String> excludedIds;

  @override
  State<InvitePeopleSheet> createState() => _InvitePeopleSheetState();
}

class _InvitePeopleSheetState extends State<InvitePeopleSheet> {
  late final List<DirectoryPerson> _people = demoUsers
      .where(
        (person) =>
            person.id != currentDemoUserId &&
            !widget.excludedIds.contains(person.id),
      )
      .toList();
  late final Set<String> _selected = {
    for (final id in widget.initiallySelectedIds)
      if (!widget.excludedIds.contains(id)) id,
  };

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _confirm() {
    final people = _people
        .where((person) => _selected.contains(person.id))
        .toList();
    Navigator.of(context).pop(people);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Выбрать из списка', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Нет людей, которых можно пригласить',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final person in _people)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: CircleAvatar(
                  child: Text(memberInitials(person.name)),
                ),
                title: Text(person.name),
                value: _selected.contains(person.id),
                onChanged: (value) => _toggle(person.id, value ?? false),
              ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _people.isEmpty ? null : _confirm,
            child: const Text('Добавить выбранных'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }
}
