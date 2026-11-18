import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_groups/geo_group.dart';

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

class _MemberMap extends StatelessWidget {
  const _MemberMap({required this.group});

  final GeoGroup group;

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    final markers = <Marker>[];
    for (final location in group.memberLocations) {
      GroupMember? member;
      for (final candidate in group.members) {
        if (candidate.id == location.memberId) {
          member = candidate;
          break;
        }
      }
      if (member == null || member.status != MembershipStatus.active) {
        continue;
      }
      final point = LatLng(
        location.coordinate.latitude,
        location.coordinate.longitude,
      );
      points.add(point);
      markers.add(
        Marker(
          point: point,
          width: 48,
          height: 48,
          alignment: Alignment.topCenter,
          child: Tooltip(
            message: member.name,
            child: Semantics(
              label: 'Позиция участника: ${member.name}',
              child: const Icon(
                Icons.location_on,
                color: Colors.blue,
                size: 48,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _cameraCenter(points),
              initialZoom: points.isEmpty ? 2 : 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geo_groups',
              ),
              MarkerLayer(markers: markers),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Text(
              markers.isEmpty
                  ? 'Нет актуальных позиций участников'
                  : _mapParticipantsText(markers.length),
            ),
          ),
        ),
      ],
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

LatLng _cameraCenter(List<LatLng> points) {
  if (points.isEmpty) {
    return const LatLng(0, 0);
  }
  var latitude = 0.0;
  var longitude = 0.0;
  for (final point in points) {
    latitude += point.latitude;
    longitude += point.longitude;
  }
  return LatLng(latitude / points.length, longitude / points.length);
}
