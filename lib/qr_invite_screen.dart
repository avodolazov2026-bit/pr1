import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:geo_groups/geo_group.dart';

class QrInviteScreen extends StatelessWidget {
  const QrInviteScreen({super.key, required this.group});

  final GeoGroup group;

  bool get _canCopy {
    final saved = GroupsStore.instance.groupById(group.id);
    return identical(saved, group) &&
        group.isActive &&
        group.qrInviteToken.isNotEmpty &&
        group.currentUserIsActiveOrganizer;
  }

  Future<void> _copyPayload(BuildContext context) async {
    final payload = buildGroupInvitePayload(group);
    try {
      await Clipboard.setData(ClipboardData(text: payload));
    } catch (_) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Код приглашения скопирован')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final endsAt = group.endsAt;
    final canCopy = _canCopy;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final qrSize = (screenWidth - 96).clamp(180.0, 300.0);

    return Scaffold(
      appBar: AppBar(title: const Text('QR-код приглашения')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: buildGroupInvitePayload(group),
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              group.name,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              endsAt == null
                  ? 'Бессрочная группа'
                  : 'До ${formatGroupDateTime(endsAt)}',
              style: textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Покажите этот код человеку, которого хотите пригласить в группу.',
              style: textTheme.bodyLarge,
              textAlign: TextAlign.center,
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
                  'Код не передаёт вашу геолокацию. Присоединение к группе потребует отдельного подтверждения.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canCopy) ...[
                OutlinedButton.icon(
                  onPressed: () => _copyPayload(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Скопировать код приглашения'),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
