import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/map_time_format.dart';

class GroupMapScreen extends StatelessWidget {
  const GroupMapScreen({super.key, required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Карта группы')),
      body: group.canUseMap
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Text(
                    'Группа: «${group.name}»',
                    style: textTheme.titleMedium,
                  ),
                ),
                Expanded(child: _MemberMap(group: group)),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Карта доступна только в активной группе.',
                  style: textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

class _MemberMap extends StatefulWidget {
  const _MemberMap({required this.group});

  final GeoGroup group;

  @override
  State<_MemberMap> createState() => _MemberMapState();
}

class _VisibleMember {
  const _VisibleMember({
    required this.member,
    required this.location,
    required this.point,
  });

  final GroupMember member;
  final GroupMemberLocation location;
  final LatLng point;
}

class _MemberMapState extends State<_MemberMap> {
  final MapController _mapController = MapController();
  String? _selectedMemberId;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _toggleMember(String memberId) {
    setState(() {
      _selectedMemberId = _selectedMemberId == memberId ? null : memberId;
    });
  }

  void _clearSelection() {
    if (_selectedMemberId == null) {
      return;
    }
    setState(() => _selectedMemberId = null);
  }

  List<_VisibleMember> _visibleMembers() {
    final visible = <_VisibleMember>[];
    for (final location in widget.group.memberLocations) {
      GroupMember? member;
      for (final candidate in widget.group.members) {
        if (candidate.id == location.memberId) {
          member = candidate;
          break;
        }
      }
      if (member == null || member.status != MembershipStatus.active) {
        continue;
      }
      visible.add(
        _VisibleMember(
          member: member,
          location: location,
          point: LatLng(
            location.coordinate.latitude,
            location.coordinate.longitude,
          ),
        ),
      );
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleMembers();
    final selectedId = _selectedMemberId;
    final selectionVisible =
        selectedId != null &&
        visible.any((item) => item.member.id == selectedId);
    if (selectedId != null && !selectionVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedMemberId == null) {
          return;
        }
        final stillVisible = _visibleMembers().any(
          (item) => item.member.id == _selectedMemberId,
        );
        if (stillVisible) {
          return;
        }
        setState(() => _selectedMemberId = null);
      });
    }
    _VisibleMember? selected;
    for (final item in visible) {
      if (item.member.id == _selectedMemberId) {
        selected = item;
        break;
      }
    }
    final points = [for (final item in visible) item.point];
    final markers = [
      for (final item in visible)
        Marker(
          point: item.point,
          width: 48,
          height: 48,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _toggleMember(item.member.id),
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: item.member.name,
              child: Semantics(
                label: 'Позиция участника: ${item.member.name}',
                child: Icon(
                  Icons.location_on,
                  color: item.member.id == selected?.member.id
                      ? theme.colorScheme.primary
                      : Colors.blue,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: _optionsFor(points),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.geo_groups',
                  ),
                  MarkerLayer(markers: markers),
                  const SimpleAttributionWidget(
                    source: Text('OpenStreetMap contributors'),
                  ),
                ],
              ),
              if (visible.isNotEmpty)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Material(
                        elevation: 2,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        color: theme.colorScheme.surface,
                        child: IconButton(
                          tooltip: 'Показать всех участников',
                          onPressed: _showAllVisibleMembers,
                          icon: const Icon(
                            Icons.fit_screen,
                            semanticLabel: 'Показать всех участников',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: selected == null
                ? Text(
                    markers.isEmpty
                        ? 'Нет актуальных позиций участников'
                        : _mapParticipantsText(markers.length),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.member.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Обновлено: ${formatUpdatedAgo(selected.location.updatedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  MapOptions _optionsFor(List<LatLng> points) {
    if (points.isEmpty) {
      return MapOptions(
        initialCenter: const LatLng(0, 0),
        initialZoom: 2,
        onTap: (_, _) => _clearSelection(),
      );
    }
    if (points.length == 1) {
      return MapOptions(
        initialCenter: points.single,
        initialZoom: 13,
        onTap: (_, _) => _clearSelection(),
      );
    }
    return MapOptions(
      initialCameraFit: CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
      onTap: (_, _) => _clearSelection(),
    );
  }

  void _showAllVisibleMembers() {
    final points = [for (final item in _visibleMembers()) item.point];
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      _mapController.move(points.single, 13);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
    );
  }
}

String _mapParticipantsText(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  final word = lastTwo >= 11 && lastTwo <= 14
      ? 'участников'
      : switch (last) {
          1 => 'участник',
          2 || 3 || 4 => 'участника',
          _ => 'участников',
        };
  return 'На карте: $count $word';
}
