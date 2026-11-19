import 'dart:async';

import 'package:flutter/material.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/user_profile.dart';

class JoinGroupConfirmationScreen extends StatefulWidget {
  const JoinGroupConfirmationScreen({
    super.key,
    required this.group,
    required this.userId,
    required this.fallbackName,
    required this.onJoin,
    this.repository,
    this.locationProvider,
  });

  final GeoGroup group;
  final String userId;
  final String fallbackName;
  final Future<InvitationAcceptResult> Function(String name, String avatarId)
  onJoin;
  final UserProfileRepository? repository;
  final CurrentLocationProvider? locationProvider;

  @override
  State<JoinGroupConfirmationScreen> createState() =>
      _JoinGroupConfirmationScreenState();
}

class _JoinGroupConfirmationScreenState
    extends State<JoinGroupConfirmationScreen> {
  final _nameController = TextEditingController();
  UserProfileRepository get _repository =>
      widget.repository ?? UserProfileStore.instance;

  var _loading = true;
  var _submitting = false;
  var _avatarId = defaultAvatarId;
  var _loadId = 0;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(JoinGroupConfirmationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.fallbackName != widget.fallbackName ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadId;
    final userId = widget.userId;
    final fallbackName = widget.fallbackName;
    UserProfile profile;
    try {
      profile = await _repository.loadProfile(
        userId: userId,
        fallbackName: fallbackName,
      );
    } catch (_) {
      profile = UserProfile(
        userId: userId,
        displayName: fallbackName,
        avatarId: defaultAvatarId,
      );
    }
    if (!mounted || request != _loadId || userId != widget.userId) {
      return;
    }
    _nameController.text = profile.displayName;
    setState(() {
      _avatarId = profile.avatarId;
      _loading = false;
      _submitting = false;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _submitting || _loading || widget.group.isFinished) {
      return;
    }
    final userId = widget.userId;
    final avatarId = _avatarId;
    setState(() {
      _submitting = true;
      _joinError = null;
    });
    late final InvitationAcceptResult result;
    try {
      result = await widget.onJoin(name, avatarId);
    } catch (_) {
      if (mounted && userId == widget.userId) {
        setState(() {
          _submitting = false;
          _joinError = 'Не удалось вступить в группу';
        });
      }
      return;
    }
    if (!mounted || userId != widget.userId) {
      return;
    }
    if (result == InvitationAcceptResult.joined) {
      final provider = widget.locationProvider ?? DeviceLocationProvider();
      unawaited(_requestLocationAccess(provider));
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _joinError = _messageFor(result);
    });
  }

  Future<void> _requestLocationAccess(CurrentLocationProvider provider) async {
    try {
      await provider.ensurePermissionForJoin();
    } catch (_) {}
  }

  String _messageFor(InvitationAcceptResult result) {
    return switch (result) {
      InvitationAcceptResult.joined => 'Вы вступили в группу',
      InvitationAcceptResult.alreadyMember => 'Вы уже участвуете в этой группе',
      InvitationAcceptResult.groupEnded => 'В эту группу уже нельзя вступить',
      InvitationAcceptResult.missingGroup => 'Группа недоступна',
      InvitationAcceptResult.notPending => 'Приглашение больше не действует',
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final name = _nameController.text.trim();
    final blocked = group.isFinished;
    final canJoin = !_loading && !_submitting && name.isNotEmpty && !blocked;

    return Scaffold(
      appBar: AppBar(title: const Text('Вступление в группу')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Text(group.name, style: textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(group.statusBadge, style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(group.scheduleSummary, style: textTheme.bodyLarge),
                  if (group.isUpcoming) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Группа ещё не началась. Карта и обмен геопозицией станут доступны после её начала.',
                      style: textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: ProfileAvatar(
                      avatarId: _avatarId,
                      displayName: name,
                      radius: 48,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Имя',
                      errorText: name.isEmpty ? 'Введите имя' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  Text('Аватар', style: textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in profileAvatarOptions)
                        _AvatarChoice(
                          option: option,
                          selected: option.id == _avatarId,
                          displayName: name,
                          onSelected: (avatarId) {
                            setState(() => _avatarId = avatarId);
                          },
                        ),
                    ],
                  ),
                  if (blocked || _joinError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      blocked
                          ? 'В эту группу уже нельзя вступить'
                          : _joinError!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: canJoin ? _submit : null,
                        child: _submitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Text('Вступить в группу'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.option,
    required this.selected,
    required this.displayName,
    required this.onSelected,
  });

  final ProfileAvatarOption option;
  final bool selected;
  final String displayName;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = selected
        ? 'Выбран аватар ${option.id}'
        : 'Аватар ${option.id}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: () => onSelected(option.id),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onSelected(option.id),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ProfileAvatar(
                      avatarId: option.id,
                      displayName: displayName,
                      radius: 22,
                    ),
                  ),
                ),
                if (selected)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
