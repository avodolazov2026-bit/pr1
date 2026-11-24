import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:geo_groups/app_link_handler.dart';
import 'package:geo_groups/created_groups_screen.dart';
import 'package:geo_groups/foreground_location_sharing.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/group_invitation_repository.dart';
import 'package:geo_groups/group_repository.dart';
import 'package:geo_groups/invitations_screen.dart';
import 'package:geo_groups/join_group_route.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/location_sharing_coordinator.dart';
import 'package:geo_groups/location_sharing_service.dart';
import 'package:geo_groups/my_groups_screen.dart';
import 'package:geo_groups/profile_screen.dart';
import 'package:geo_groups/service_availability.dart';
import 'package:geo_groups/service_unavailable_screen.dart';
import 'package:geo_groups/supabase_bootstrap.dart';
import 'package:geo_groups/theme/app_theme.dart';

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
  late final ServiceAvailabilityController _availability;

  @override
  void initState() {
    super.initState();
    _availability = ServiceAvailabilityController(check: _openWhenReachable);
  }

  @override
  void dispose() {
    _availability.dispose();
    super.dispose();
  }

  Future<bool> _openWhenReachable() async {
    if (kDebugMode) {
      final config = supabaseConfigFromEnvironment();
      final host = Uri.tryParse(config.url)?.host ?? '';
      debugPrint(
        'bootstrap start: url=$host keyLength=${config.publishableKey.length}',
      );
    }
    final result = await bootstrapSupabase();
    if (kDebugMode) {
      debugPrint('bootstrap result: $result');
    }
    if (result != SupabaseStartup.ready) {
      return false;
    }
    final reachable = await const SupabaseServiceAvailabilityCheck().check();
    if (!reachable) {
      return false;
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final groups = await groupRepositoryFor(result).loadMyGroups();
      publishLoadedGroups(result, groups, currentUserId: userId);
    } catch (error, stack) {
      if (isConnectivityFailure(error)) {
        return false;
      }
      if (kDebugMode) {
        debugPrint('loadMyGroups failed: ${error.runtimeType}');
        debugPrintStack(stackTrace: stack);
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ServiceAvailabilityShell(
      controller: _availability,
      child: MyApp(locations: locationRepositoryFor(SupabaseStartup.ready)),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.inviteLinks,
    this.invitations,
    this.locations = const LocalLocationRepository(),
  });

  final InviteLinkSource? inviteLinks;
  final GroupInvitationRepository? invitations;
  final LocationRepository locations;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Uri>? _linkSubscription;
  String? _openInvitePayload;
  late final LocationSharingCoordinator _locationSharing;
  late final ForegroundLocationSharing _foregroundSharing;

  @override
  void initState() {
    super.initState();
    _locationSharing = LocationSharingCoordinator(
      sharing: LocationSharingService(repository: widget.locations),
    );
    _foregroundSharing = ForegroundLocationSharing(
      coordinator: _locationSharing,
    );
    _foregroundSharing.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInviteLinks();
    });
  }

  @override
  void dispose() {
    _foregroundSharing.dispose();
    _locationSharing.dispose();
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
    if (!mounted || appNavigatorKey.currentState == null) {
      return;
    }
    final token = groupInviteTokenFromUri(uri);
    if (token == null) {
      if (isMalformedGroupInviteLink(uri)) {
        _showInviteMessage('Не удалось распознать приглашение');
      }
      return;
    }
    if (_openInvitePayload != null) {
      return;
    }
    _openInvitePayload = token;
    final repository =
        widget.invitations ?? defaultGroupInvitationRepository();
    try {
      final resolved = await repository.resolve(token);
      if (!mounted) {
        return;
      }
      if (resolved == null) {
        _showInviteMessage('Приглашение недоступно');
        return;
      }
      final saved = await repository.save(token);
      if (!mounted) {
        return;
      }
      if (saved == null) {
        _showInviteMessage('Приглашение недоступно');
        return;
      }
      _showInviteMessage('Приглашение добавлено в список.');
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      _showInviteMessage(error.message);
    } finally {
      if (_openInvitePayload == token) {
        _openInvitePayload = null;
      }
    }
  }

  void _showInviteMessage(String message) {
    final context = appNavigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Qunora',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: HomeScreen(
        invitations: widget.invitations ?? defaultGroupInvitationRepository(),
      ),
      builder: (context, child) {
        return LocationRepositoryScope(
          repository: widget.locations,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.invitations});

  final GroupInvitationRepository? invitations;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _serverUnseen;

  @override
  void initState() {
    super.initState();
    groupFlowRevision.addListener(_onGroupFlowChanged);
    _refreshUnseen();
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

  Future<void> _refreshUnseen() async {
    final invitations = widget.invitations;
    if (invitations == null) {
      return;
    }
    try {
      final count = await invitations.countUnseen();
      if (mounted) {
        setState(() => _serverUnseen = count);
      }
    } catch (_) {
      // Счётчик на кнопке остаётся прежним, пока сервер не ответил.
    }
  }

  Future<void> _switchDemoUser() async {
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
    if (!mounted) {
      return;
    }
    setState(() {});
    await _refreshUnseen();
  }

   @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qunora'),
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
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _openScreen(
                  InvitationsScreen(
                    invitations: widget.invitations,
                    onInvitationsChanged: _refreshUnseen,
                  ),
                ),
                child: _JoinInvitationLabel(
                  count:
                      _serverUnseen ??
                      GroupsStore.instance.pendingInvitationCountFor(
                        currentDemoUserId,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
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
