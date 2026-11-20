import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/app_link_handler.dart';
import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_repository.dart';
import 'package:geo_groups/invitations_screen.dart';
import 'package:geo_groups/join_group_route.dart';
import 'package:geo_groups/my_groups_screen.dart';
import 'package:geo_groups/profile_screen.dart';
import 'package:geo_groups/supabase_bootstrap.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  if (!supabaseConfigFromEnvironment().isConfigured) {
    runApp(const MyApp());
    return;
  }
  runApp(const _SupabaseStartupApp());
}

abstract class InviteLinkSource {
  Future<Uri?> initialLink();

  Stream<Uri> get uriStream;
}

class AppLinksInviteSource implements InviteLinkSource {
  AppLinksInviteSource({AppLinks? links}) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> get uriStream => _links.uriLinkStream;
}

class _SupabaseStartupApp extends StatefulWidget {
  const _SupabaseStartupApp();

  @override
  State<_SupabaseStartupApp> createState() => _SupabaseStartupAppState();
}

class _SupabaseStartupAppState extends State<_SupabaseStartupApp> {
  var _connecting = true;
  SupabaseStartup? _startup;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final result = await bootstrapSupabase();
    if (!mounted) {
      return;
    }
    if (result != SupabaseStartup.ready) {
      setState(() {
        _connecting = false;
        _startup = result;
      });
      return;
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final groups = await groupRepositoryFor(result).loadMyGroups();
      if (!mounted) {
        return;
      }
      publishLoadedGroups(result, groups, currentUserId: userId);
      setState(() {
        _connecting = false;
        _startup = result;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connecting = false;
        _startup = SupabaseStartup.failed;
      });
    }
  }

  void _retry() {
    setState(() {
      _connecting = true;
      _startup = null;
    });
    _connect();
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_startup == SupabaseStartup.ready) {
      return const MyApp();
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось подключиться'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _retry, child: const Text('Повторить')),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.inviteLinks});

  final InviteLinkSource? inviteLinks;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Uri>? _linkSubscription;
  String? _openInvitePayload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInviteLinks();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startInviteLinks() async {
    if (!mounted) {
      return;
    }
    final source = widget.inviteLinks ?? AppLinksInviteSource();
    try {
      _linkSubscription = source.uriStream.listen(
        _openInviteLink,
        onError: (_) {},
      );
    } catch (_) {}
    if (!mounted) {
      return;
    }
    try {
      final initial = await source.initialLink();
      if (!mounted) {
        return;
      }
      if (initial != null) {
        await _openInviteLink(initial);
      }
    } catch (_) {}
  }

  Future<void> _openInviteLink(Uri uri) async {
    final resolution = resolveGroupInviteLink(uri);
    final navigator = appNavigatorKey.currentState;
    final context = navigator?.overlay?.context;
    if (!mounted || navigator == null || context == null || !context.mounted) {
      return;
    }
    if (_openInvitePayload != null && isGroupJoinLink(uri)) {
      return;
    }
    final message = resolution.message;
    if (resolution.kind == GroupInviteLinkKind.rejected && message != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final group = resolution.group;
    final payload = resolution.payload;
    if (!resolution.opensConfirmation || group == null || payload == null) {
      return;
    }
    _openInvitePayload = payload;
    try {
      await openJoinGroupConfirmation(
        context: context,
        group: group,
        onJoin: (name, avatarId) {
          return Future.value(
            GroupsStore.instance.joinFromQrPayload(
              payload,
              displayName: name,
              avatarId: avatarId,
            ),
          );
        },
      );
    } finally {
      if (_openInvitePayload == payload) {
        _openInvitePayload = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
  @override
  void initState() {
    super.initState();
    groupFlowRevision.addListener(_onGroupFlowChanged);
  }

  @override
  void dispose() {
    groupFlowRevision.removeListener(_onGroupFlowChanged);
    super.dispose();
  }

  void _onGroupFlowChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _switchDemoUser() async {
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          _DemoUserSheet(users: demoUsers, currentUserId: currentDemoUserId),
    );
    if (selectedId == null || selectedId == currentDemoUserId || !mounted) {
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
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => screen));
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
            tooltip: 'Мой профиль',
            onPressed: () {
              final user = currentDemoUser;
              _openScreen(
                ProfileScreen(userId: user.id, fallbackName: user.name),
              );
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
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
  const _DemoUserSheet({required this.users, required this.currentUserId});

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
              leading: CircleAvatar(child: Text(memberInitials(user.name))),
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
