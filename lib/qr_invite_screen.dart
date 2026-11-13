import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';

class QrInviteScreen extends StatelessWidget {
  const QrInviteScreen({super.key, required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = group.endsAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашение по QR-коду'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(group.name, style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Организатор: ${group.organizerName}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              endsAt == null
                  ? 'Бессрочная группа'
                  : 'До ${formatGroupDateTime(endsAt)}',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.qr_code_2_outlined,
                      size: 96,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'QR-код будет доступен после подключения сервера',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Участник сможет отсканировать код, просмотреть приглашение и самостоятельно подтвердить присоединение.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Сканирование кода не предоставляет доступ к геолокации. Участник должен принять приглашение.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
