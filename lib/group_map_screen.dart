import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:geo_groups/geo_group.dart';

const _testPoint = LatLng(55.751244, 37.618423);

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
                Expanded(
                  child: FlutterMap(
                    options: const MapOptions(
                      initialCenter: _testPoint,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.geo_groups',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _testPoint,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.location_on,
                              color: Colors.blue,
                              size: 48,
                            ),
                          ),
                        ],
                      ),
                      SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                ),
                const SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Text('Тестовая точка на карте'),
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
