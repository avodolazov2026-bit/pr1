import 'package:flutter/material.dart';

import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/invitations_screen.dart';
import 'package:geo_groups/my_groups_screen.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _switchDemoUser() async {
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _DemoUserSheet(
        users: demoUsers,
        currentUserId: currentDemoUserId,
      ),
    );
    if (selectedId == null ||
        selectedId == currentDemoUserId ||
        !mounted) {
      return;
    }

    setState(() {
      currentDemoUserId = selectedId;
    });
    final selected = currentDemoUser;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Выбран пользователь: ${selected.name}')),
    );
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => screen),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Groups'),
        leading: const Icon(Icons.groups),
        actions: [
          IconButton(
            tooltip: 'Демонстрационный пользователь',
            onPressed: _switchDemoUser,
            icon: const Icon(Icons.switch_account_outlined),
          ),
        ],
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
                onPressed: () => _openScreen(const CreatedGroupsScreen()),
                child: const Text('Создать группу'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _openScreen(const InvitationsScreen()),
                child: _JoinInvitationLabel(
                  count: GroupsStore.instance.pendingInvitationCountFor(
                    currentDemoUserId,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _openScreen(const MyGroupsScreen()),
                child: const Text('Мои группы'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinInvitationLabel extends StatelessWidget {
  const _JoinInvitationLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';

    return Row(
      children: [
        const Expanded(
          child: Text(
            'Присоединиться по приглашению',
            textAlign: TextAlign.center,
          ),
        ),
        if (count > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onError,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DemoUserSheet extends StatelessWidget {
  const _DemoUserSheet({
    required this.users,
    required this.currentUserId,
  });

  final List<DirectoryPerson> users;
  final String currentUserId;

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
          Text('Демонстрационный пользователь', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Режим разработки. Данные групп и приглашений общие для всех демонстрационных пользователей.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final user in users)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(memberInitials(user.name)),
              ),
              title: Text(user.name),
              subtitle: user.id == currentUserId
                  ? const Text('Текущий пользователь')
                  : null,
              trailing: user.id == currentUserId
                  ? Icon(Icons.check, color: colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(user.id),
            ),
        ],
      ),
    );
  }
}
