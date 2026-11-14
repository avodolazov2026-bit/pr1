import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

class GroupMapScreen extends StatelessWidget {
  const GroupMapScreen({super.key, required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final blockedMessage = group.isUpcoming
        ? 'Карта станет доступна после начала группы'
        : 'Карта недоступна для завершённой группы';

    return Scaffold(
      appBar: AppBar(title: const Text('Карта группы')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: group.canUseMap
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map, size: 72, color: colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(
                      'Карта участников будет добавлена на следующем этапе',
                      style: textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Text(
                  blockedMessage,
                  style: textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}
