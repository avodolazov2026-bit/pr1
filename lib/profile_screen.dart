import 'package:flutter/material.dart';

import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.repository,
  });

  final String userId;
  final String fallbackName;
  final UserProfileRepository? repository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  UserProfileRepository get _repository =>
      widget.repository ?? UserProfileStore.instance;

  var _loading = true;
  var _saving = false;
  var _avatarId = defaultAvatarId;
  var _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
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
    final profile = await _repository.loadProfile(
      userId: userId,
      fallbackName: fallbackName,
    );
    if (!mounted || request != _loadId) {
      return;
    }
    _nameController.text = profile.displayName;
    setState(() {
      _avatarId = profile.avatarId;
      _loading = false;
      _saving = false;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving || _loading) {
      return;
    }
    final userId = widget.userId;
    final avatarId = _avatarId;
    setState(() => _saving = true);
    try {
      await _repository.saveProfile(
        UserProfile(userId: userId, displayName: name, avatarId: avatarId),
      );
    } catch (_) {
      if (mounted && userId == widget.userId) {
        setState(() => _saving = false);
      }
      return;
    }
    if (!mounted || userId != widget.userId) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = _nameController.text.trim();
    final canSave = !_loading && !_saving && name.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Мой профиль')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
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
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: const Text('Сохранить'),
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
