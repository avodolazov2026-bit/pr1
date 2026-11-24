import 'package:flutter/material.dart';

import 'package:geo_groups/service_availability.dart';
import 'package:geo_groups/theme/app_theme.dart';

/// Показывает приложение только после успешной проверки сервиса.
class ServiceAvailabilityShell extends StatefulWidget {
  const ServiceAvailabilityShell({
    super.key,
    required this.controller,
    required this.child,
  });

  final ServiceAvailabilityController controller;
  final Widget child;

  @override
  State<ServiceAvailabilityShell> createState() =>
      _ServiceAvailabilityShellState();
}

class _ServiceAvailabilityShellState extends State<ServiceAvailabilityShell> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.ensureStarted();
  }

  @override
  void didUpdateWidget(ServiceAvailabilityShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
    widget.controller.ensureStarted();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.status == ServiceAvailability.available) {
      return widget.child;
    }
    final retrying = controller.retryInProgress;
    return MaterialApp(
      title: 'Qunora',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: retrying || controller.status == ServiceAvailability.unavailable
          ? ServiceUnavailableScreen(
              busy: retrying,
              onRetry: controller.retry,
            )
          : const ServiceConnectingScreen(),
    );
  }
}

class ServiceConnectingScreen extends StatelessWidget {
  const ServiceConnectingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Подключаемся к Qunora…',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceUnavailableScreen extends StatelessWidget {
  const ServiceUnavailableScreen({
    super.key,
    required this.onRetry,
    this.busy = false,
  });

  final Future<void> Function() onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 48
                        ? constraints.maxHeight - 48
                        : 0,
                  ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.brightness == Brightness.dark
                            ? scheme.surfaceContainerHighest
                            : AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        boxShadow: AppTheme.cardShadows(scheme.brightness),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _OfflineMark(),
                            const SizedBox(height: 20),
                            Text(
                              'Сервис временно недоступен',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Не удалось подключиться к Qunora. '
                              'Проверьте подключение к интернету '
                              'и попробуйте ещё раз.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: busy ? null : () => onRetry(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (busy) ...[
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  const Text('Повторить'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfflineMark extends StatelessWidget {
  const _OfflineMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 72),
            ),
            Icon(
              Icons.cloud_off_outlined,
              size: 34,
              color: scheme.primary,
            ),
          Positioned(
            right: 6,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 10),
            ),
          ),
        ],
      ),
    );
  }
}
