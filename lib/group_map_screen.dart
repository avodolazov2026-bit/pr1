import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_groups/current_location_provider.dart';
import 'package:geo_groups/geo_coordinate.dart';
import 'package:geo_groups/geo_group.dart';
import 'package:geo_groups/location_repository.dart';
import 'package:geo_groups/map_time_format.dart';

class GroupMapScreen extends StatefulWidget {
  const GroupMapScreen({
    super.key,
    required this.group,
    this.locationProvider,
    this.locations,
  });

  final GeoGroup group;
  final CurrentLocationProvider? locationProvider;

  /// Если не задан, берётся репозиторий из [LocationRepositoryScope] или локальный.
  final LocationRepository? locations;

  @override
  State<GroupMapScreen> createState() => _GroupMapScreenState();
}

class _GroupMapScreenState extends State<GroupMapScreen> {
  late GeoGroup _group;
  var _loadStarted = false;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startLoad();
  }

  @override
  void didUpdateWidget(GroupMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final groupChanged = !identical(oldWidget.group, widget.group);
    if (groupChanged) {
      _group = widget.group;
    }
    final groupIdChanged = oldWidget.group.id != widget.group.id;
    if ((groupChanged && groupIdChanged) ||
        oldWidget.locations != widget.locations) {
      _loadGeneration++;
      _loadStarted = false;
      _startLoad();
    }
  }

  void _startLoad() {
    if (_loadStarted || !widget.group.canUseMap) {
      return;
    }
    _loadStarted = true;
    final generation = _loadGeneration;
    final repository =
        widget.locations ??
        LocationRepositoryScope.maybeOf(context) ??
        const LocalLocationRepository();
    _loadLocations(repository, generation);
  }

  Future<void> _loadLocations(
    LocationRepository repository,
    int generation,
  ) async {
    final List<GroupMemberLocation> loaded;
    try {
      loaded = await repository.loadGroupLocations(widget.group.id);
    } catch (_) {
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final next = _copyGroup(widget.group);
    for (final location in loaded) {
      if (next.members.any((member) => member.id == location.memberId)) {
        next.updateMemberLocation(location);
      }
    }
    setState(() => _group = next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final group = _group;

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
                Expanded(
                  child: _MemberMap(
                    group: group,
                    locationProvider: widget.locationProvider,
                  ),
                ),
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

GeoGroup _copyGroup(GeoGroup source) {
  final copy = GeoGroup(
    id: source.id,
    name: source.name,
    createdAt: source.createdAt,
    startsAt: source.startsAt,
    endsAt: source.endsAt,
    createdByUserId: source.createdByUserId,
    qrInviteToken: source.qrInviteToken,
    members: List<GroupMember>.of(source.members),
    memberLocations: source.memberLocations,
  );
  copy.endedByOrganizer = source.endedByOrganizer;
  copy.endedAt = source.endedAt;
  return copy;
}

class _MemberMap extends StatefulWidget {
  const _MemberMap({required this.group, required this.locationProvider});

  final GeoGroup group;
  final CurrentLocationProvider? locationProvider;

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
  GeoCoordinate? _devicePosition;
  DateTime? _deviceReadAt;
  int _locationRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadDevicePosition();
  }

  @override
  void didUpdateWidget(_MemberMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _devicePosition = null;
      _deviceReadAt = null;
      _loadDevicePosition();
    }
  }

  @override
  void dispose() {
    _locationRequest++;
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadDevicePosition() async {
    final request = ++_locationRequest;
    final groupId = widget.group.id;
    final provider = widget.locationProvider ?? DeviceLocationProvider();
    GeoCoordinate? position;
    try {
      position = await provider.currentPosition();
    } catch (_) {
      position = null;
    }
    if (!mounted || request != _locationRequest || widget.group.id != groupId) {
      return;
    }
    if (position == null) {
      return;
    }
    final update = cameraUpdateForDevicePosition(
      otherParticipantVisible: _otherParticipantVisible(),
    );
    setState(() {
      _devicePosition = position;
      _deviceReadAt = DateTime.now();
    });
    if (update != DeviceCameraUpdate.moveToDevice) {
      return;
    }
    final point = LatLng(position.latitude, position.longitude);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _locationRequest ||
          widget.group.id != groupId) {
        return;
      }
      _mapController.move(point, 13);
    });
  }

  bool _otherParticipantVisible() {
    for (final location in widget.group.memberLocations) {
      GroupMember? member;
      for (final candidate in widget.group.members) {
        if (candidate.id == location.memberId) {
          member = candidate;
          break;
        }
      }
      if (member != null &&
          member.status == MembershipStatus.active &&
          !member.isCurrentUser) {
        return true;
      }
    }
    return false;
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
    return _withDevicePosition(visible);
  }

  List<_VisibleMember> _withDevicePosition(List<_VisibleMember> visible) {
    final device = _devicePosition;
    final readAt = _deviceReadAt;
    if (device == null || readAt == null) {
      return visible;
    }
    GroupMember? current;
    for (final member in widget.group.members) {
      if (member.isCurrentUser && member.status == MembershipStatus.active) {
        current = member;
        break;
      }
    }
    if (current == null) {
      return visible;
    }
    final overlay = _VisibleMember(
      member: current,
      location: GroupMemberLocation(
        memberId: current.id,
        coordinate: device,
        updatedAt: readAt,
      ),
      point: LatLng(device.latitude, device.longitude),
    );
    final index = visible.indexWhere((item) => item.member.id == current!.id);
    if (index >= 0) {
      visible[index] = overlay;
    } else {
      visible.add(overlay);
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
    final shown = _withoutStackedMarkers(visible);
    final markers = [
      for (final item in shown)
        _memberMarker(item, selected: item.member.id == selected?.member.id),
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
    points = _uniquePoints(points);
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

  Marker _memberMarker(_VisibleMember item, {required bool selected}) {
    final organizer = item.member.role == MemberRole.organizer;
    final currentUser = item.member.isCurrentUser;
    final iconSize = selected ? 56.0 : 44.0;
    final extent = iconSize + (organizer ? 12 : 4);
    return Marker(
      point: item.point,
      width: extent,
      height: extent,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _toggleMember(item.member.id),
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: item.member.name,
          child: Semantics(
            label: _markerLabel(item.member),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Icon(
                    Icons.location_on,
                    color: _pinColor(item.member),
                    size: iconSize,
                    shadows: _pinShadows(
                      outlined: currentUser || selected,
                      selected: selected,
                    ),
                  ),
                ),
                if (organizer)
                  const Positioned(top: 0, right: 0, child: _OrganizerBadge()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAllVisibleMembers() {
    final points = _uniquePoints([
      for (final item in _visibleMembers()) item.point,
    ]);
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

List<LatLng> _uniquePoints(List<LatLng> points) {
  final unique = <(double, double), LatLng>{};
  for (final point in points) {
    unique.putIfAbsent((point.latitude, point.longitude), () => point);
  }
  return unique.values.toList();
}

List<_VisibleMember> _withoutStackedMarkers(List<_VisibleMember> visible) {
  int priority(_VisibleMember item) {
    if (item.member.isCurrentUser) {
      return 0;
    }
    if (item.member.role == MemberRole.organizer) {
      return 1;
    }
    return 2;
  }

  final kept = <(double, double), _VisibleMember>{};
  for (final item in visible) {
    final key = (item.point.latitude, item.point.longitude);
    final current = kept[key];
    if (current == null || priority(item) < priority(current)) {
      kept[key] = item;
    }
  }
  return [
    for (final item in visible)
      if (identical(kept[(item.point.latitude, item.point.longitude)], item))
        item,
  ];
}

String _markerLabel(GroupMember member) {
  final organizer = member.role == MemberRole.organizer;
  if (member.isCurrentUser && organizer) {
    return 'Ваше местоположение, организатор';
  }
  if (member.isCurrentUser) {
    return 'Ваше местоположение';
  }
  if (organizer) {
    return 'Позиция организатора: ${member.name}';
  }
  return 'Позиция участника: ${member.name}';
}

Color _pinColor(GroupMember member) {
  if (member.isCurrentUser) {
    return const Color(0xFF00897B);
  }
  if (member.role == MemberRole.organizer) {
    return Colors.purple;
  }
  return Colors.blue;
}

List<Shadow> _pinShadows({required bool outlined, required bool selected}) {
  const spread = 1.4;
  return [
    if (outlined) ...[
      for (final offset in const [
        Offset(-spread, 0),
        Offset(spread, 0),
        Offset(0, -spread),
        Offset(0, spread),
        Offset(-spread, -spread),
        Offset(spread, -spread),
        Offset(-spread, spread),
        Offset(spread, spread),
      ])
        Shadow(color: Colors.white, offset: offset),
    ],
    if (selected)
      const Shadow(
        color: Color(0x8A000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
  ];
}

class _OrganizerBadge extends StatelessWidget {
  const _OrganizerBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.purple,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: Colors.white, width: 1.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.star, size: 12, color: Colors.white),
      ),
    );
  }
}

/// Как сдвинуть камеру, когда пришла позиция устройства.
enum DeviceCameraUpdate { moveToDevice, keep }

DeviceCameraUpdate cameraUpdateForDevicePosition({
  required bool otherParticipantVisible,
}) {
  if (otherParticipantVisible) {
    return DeviceCameraUpdate.keep;
  }
  return DeviceCameraUpdate.moveToDevice;
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
