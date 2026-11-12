import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo Groups',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Groups'),
        leading: const Icon(Icons.groups),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.groups,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Делитесь геолокацией только с теми, кому доверяете',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Создавайте временные группы для встреч, поездок и событий '
                'и делитесь местоположением только с их участниками.',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _showMessage(
                  context,
                  'Создание группы скоро будет доступно',
                ),
                child: const Text('Создать группу'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _showMessage(
                  context,
                  'Присоединение по приглашению скоро будет доступно',
                ),
                child: const Text('Присоединиться по приглашению'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _showMessage(
                  context,
                  'Раздел „Мои группы“ пока в разработке',
                ),
                child: const Text('Мои группы'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
